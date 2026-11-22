//! Identity checks for targeting a single Claude session.
use crate::process_identity::{process_identity, ProcessIdentity};
use serde_json::Value;
use std::fs::{self, File};
use std::io::Read;
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

extern "C" {
    fn geteuid() -> u32;
    fn rium_claude_catches_sigint(pid: i32, sec: u64, usec: u64) -> i32;
    fn kill(pid: i32, signal: i32) -> i32;
}
const MAX_AGE_MS: u64 = 24 * 60 * 60 * 1000;
const MAX_RECORDS: usize = 1024;

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct ClaudeTarget {
    pub pid: u32,
    pub start_sec: u64,
    pub start_usec: u64,
}

fn valid_id(id: &str) -> bool {
    id.len() == 36 && id.bytes().enumerate().all(|(i, byte)|
        if [8, 13, 18, 23].contains(&i) { byte == b'-' } else { byte.is_ascii_hexdigit() })
}

fn active_record(record: &Value, now: u64) -> bool {
    record.get("state").and_then(Value::as_str) == Some("active")
        && record.get("updatedAt").and_then(Value::as_u64)
            .is_some_and(|updated| updated <= now && now - updated <= MAX_AGE_MS)
}

fn target_from_record(session: &str, record: &Value, now: u64, live: &ProcessIdentity, uid: u32) -> Option<ClaudeTarget> {
    let pid = record.get("pid")?.as_u64().and_then(|value| u32::try_from(value).ok()).filter(|value| *value > 1 && *value <= i32::MAX as u32)?;
    if !valid_id(session) || record.get("sessionId")?.as_str()? != session || !active_record(record, now)
        || live.uid != uid || live.name != "claude" || record.get("pidStartSec")?.as_u64()? != live.start_sec
        || record.get("pidStartUsec")?.as_u64()? != live.start_usec { return None; }
    let cwd = record.get("cwd")?.as_str()?;
    if cwd.len() > 4096 || !Path::new(cwd).is_absolute() { return None; }
    Some(ClaudeTarget { pid, start_sec: live.start_sec, start_usec: live.start_usec })
}

fn peer_conflicts(record: &Value, target: &ClaudeTarget) -> bool {
    if record.get("state").and_then(Value::as_str) != Some("active")
        || record.get("pid").and_then(Value::as_u64) != Some(u64::from(target.pid)) { return false; }
    match (record.get("pidStartSec").and_then(Value::as_u64), record.get("pidStartUsec").and_then(Value::as_u64)) {
        (Some(sec), Some(usec)) => sec == target.start_sec && usec == target.start_usec,
        _ => true,
    }
}

fn read_record(path: &Path, uid: u32) -> Option<Value> {
    let before = fs::symlink_metadata(path).ok()?;
    if !before.file_type().is_file() || before.uid() != uid || before.mode() & 0o077 != 0 || before.len() > 65_536 { return None; }
    let file = File::open(path).ok()?;
    let after = file.metadata().ok()?;
    if !after.file_type().is_file() || before.dev() != after.dev() || before.ino() != after.ino()
        || before.uid() != after.uid() || after.mode() & 0o077 != 0 || after.len() > 65_536 { return None; }
    let mut bytes = Vec::new();
    file.take(65_537).read_to_end(&mut bytes).ok()?;
    if bytes.len() > 65_536 { return None; }
    serde_json::from_slice(&bytes).ok()
}

fn registry() -> Option<PathBuf> {
    let root = PathBuf::from(std::env::var_os("HOME")?).join("Library/Application Support/Rium Notch/agent-sessions");
    let metadata = fs::symlink_metadata(&root).ok()?;
    if !metadata.file_type().is_dir() || metadata.uid() != unsafe { geteuid() } || metadata.mode() & 0o077 != 0 { return None; }
    Some(root)
}

/// Checks a fresh Rium hook record, the live PID identity and all recent peers.
/// This function does not signal or otherwise control the target process.
pub(crate) fn verified_target(session: &str) -> Result<ClaudeTarget, &'static str> {
    const ERROR: &str = "Claude 작업을 안전하게 확인할 수 없습니다. Claude에서 직접 확인해 주세요";
    if !valid_id(session) { return Err(ERROR); }
    let root = registry().ok_or(ERROR)?;
    let uid = unsafe { geteuid() };
    let now = SystemTime::now().duration_since(UNIX_EPOCH).map_err(|_| ERROR)?.as_millis();
    let now = u64::try_from(now).map_err(|_| ERROR)?;
    let path = root.join(format!("claude-{session}.json"));
    let record = read_record(&path, uid).ok_or(ERROR)?;
    let pid = record.get("pid").and_then(Value::as_u64).and_then(|value| u32::try_from(value).ok()).ok_or(ERROR)?;
    let live = process_identity(pid).ok_or(ERROR)?;
    let target = target_from_record(session, &record, now, &live, uid).ok_or(ERROR)?;
    let mut scanned = 0usize;
    for entry in fs::read_dir(&root).map_err(|_| ERROR)? {
        let entry = entry.map_err(|_| ERROR)?;
        let name = entry.file_name();
        let Some(name) = name.to_str() else { continue; };
        let Some(peer) = name.strip_prefix("claude-").and_then(|name| name.strip_suffix(".json")) else { continue; };
        if !valid_id(peer) { continue; }
        scanned += 1;
        if scanned > MAX_RECORDS { return Err(ERROR); }
        if peer == session { continue; }
        let other = read_record(&entry.path(), uid).ok_or(ERROR)?;
        if other.get("sessionId").and_then(Value::as_str) != Some(peer)
            || !matches!(other.get("state").and_then(Value::as_str), Some("active" | "stopped"))
            || (other.get("state").and_then(Value::as_str) == Some("active")
                && other.get("pid").and_then(Value::as_u64).is_none()) { return Err(ERROR); }
        if peer_conflicts(&other, &target) { return Err(ERROR); }
    }
    if read_record(&path, uid).as_ref() != Some(&record) || process_identity(pid).as_ref() != Some(&live) { return Err(ERROR); }
    Ok(target)
}

fn interrupt_checked(
    mut verify: impl FnMut() -> Result<ClaudeTarget, &'static str>,
    mut catches: impl FnMut(&ClaudeTarget) -> bool,
    mut signal: impl FnMut(u32) -> bool,
) -> Result<Value, String> {
    let target = verify().map_err(str::to_owned)?;
    if !catches(&target) || verify().map_err(str::to_owned)? != target || !catches(&target) {
        return Err("Claude 중단 신호를 안전하게 확인할 수 없습니다. Claude에서 직접 확인해 주세요".into());
    }
    // shortcut: PID can be reused between the final check and kill; use a kernel process handle if macOS provides one.
    if !signal(target.pid) { return Err("Claude에 중단 요청을 전달할 수 없습니다".into()); }
    Ok(serde_json::json!({"status":"accepted"}))
}

pub fn interrupt(session: &str) -> Result<Value, String> {
    interrupt_checked(
        || verified_target(session),
        |target| unsafe { rium_claude_catches_sigint(target.pid as i32, target.start_sec, target.start_usec) == 1 },
        |pid| unsafe { kill(pid as i32, 2) == 0 },
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    #[test]
    fn only_a_fresh_matching_single_session_can_be_targeted() {
        let id = "12345678-1234-1234-1234-123456789abc";
        let live = ProcessIdentity { uid: 501, name: "claude".into(), start_sec: 12, start_usec: 34 };
        let record = json!({"sessionId":id,"pid":42,"cwd":"/tmp","state":"active","updatedAt":1000,"pidStartSec":12,"pidStartUsec":34});
        let target = target_from_record(id, &record, 1001, &live, 501).unwrap();
        assert!(peer_conflicts(&record, &target));
        let mut reused = record.clone(); reused["pidStartSec"] = json!(13);
        assert!(!peer_conflicts(&reused, &target));
        assert!(target_from_record(id, &reused, 1001, &live, 501).is_none());
        assert!(target_from_record(id, &record, 1000 + MAX_AGE_MS + 1, &live, 501).is_none());
        assert!(target_from_record(id, &record, 1001, &live, 502).is_none());
        let mut unknown = record.clone(); unknown.as_object_mut().unwrap().remove("pidStartSec");
        assert!(peer_conflicts(&unknown, &target));
        assert!(target_from_record(id, &unknown, 1001, &live, 501).is_none());
    }

    #[test]
    fn interrupt_never_signals_when_identity_or_handler_changes() {
        let first = ClaudeTarget { pid: 42, start_sec: 12, start_usec: 34 };
        let other = ClaudeTarget { start_sec: 13, ..first.clone() };
        let mut attempts = 0;
        let mut calls = 0;
        assert!(interrupt_checked(|| { calls += 1; Ok(if calls == 1 { first.clone() } else { other.clone() }) },
            |_| true, |_| { attempts += 1; true }).is_err());
        assert_eq!(attempts, 0);
        assert!(interrupt_checked(|| Ok(first.clone()), |_| false, |_| { attempts += 1; true }).is_err());
        assert_eq!(attempts, 0);
        assert_eq!(interrupt_checked(|| Ok(first.clone()), |_| true, |_| { attempts += 1; true }).unwrap()["status"], "accepted");
        assert_eq!(attempts, 1);
    }
}
