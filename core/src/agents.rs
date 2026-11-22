//! Read-only, bounded agent session observation. Only active, non-secret
//! question prompts and options are emitted; other transcript content stays local.
use serde_json::{json, Value};
use std::collections::{BTreeSet, HashMap, VecDeque};
use std::fs::{self, File};
use std::io::{BufRead, BufReader, Read, Seek, SeekFrom};
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const TAIL_BYTES: u64 = 256 * 1024;
const MAX_TRANSCRIPT_BACKTRACK_BYTES: u64 = 8 * 1024 * 1024;
// shortcut: discovery remains bounded; larger histories can still hide older sessions.
const DISCOVERY_CANDIDATE_LIMIT: usize = 64;
const OBSERVED_EXTRA_LIMIT: usize = 16;
const MAX_HOOK_BYTES: u64 = 64 * 1024;
const HOOK_FRESHNESS_MS: u64 = 30_000;
const STALL_SILENCE_MS: u64 = 600_000;
const IDLE_STALL_MS: u64 = 90_000;
const TOOL_STALL_MS: u64 = 300_000;
fn transcript_modified_ms(metadata: &fs::Metadata) -> Option<u64> {
    u64::try_from(metadata.modified().ok()?.duration_since(UNIX_EPOCH).ok()?.as_millis()).ok()
}

fn transcript_identity(metadata: &fs::Metadata) -> Option<String> {
    let created = metadata.created().ok()?.duration_since(UNIX_EPOCH).ok()?;
    Some(format!("{:x}:{:x}:{}:{}", metadata.dev(), metadata.ino(), created.as_secs(), created.subsec_nanos()))
}
// shortcut: snapshot expiry is provisional until the reference's failure policy is recovered.
pub fn snapshot_expired(last_success: f64, now: f64) -> bool {
    last_success.is_finite() && now.is_finite() && now >= last_success && now - last_success >= 45.0
}

#[no_mangle]
pub extern "C" fn rium_agent_snapshot_expired(last_success: f64, now: f64) -> i32 {
    i32::from(snapshot_expired(last_success, now))
}
// shortcut: bounded discovery cannot reproduce the reference daemon's
// indefinitely observed pending questions; retain recent unanswered ones for a day.
const QUESTION_RETENTION_SECONDS: u64 = 24 * 60 * 60;
extern "C" { fn kill(pid: i32, signal: i32) -> i32; }

// Signal zero only queries existence. EPERM and all errors except ESRCH are
// deliberately treated as unknown rather than proof that a process ended.
pub(crate) fn process_definitely_absent(pid: u32) -> bool {
    if pid <= 1 || pid > i32::MAX as u32 { return false; }
    let result = unsafe { kill(pid as i32, 0) };
    result == -1 && std::io::Error::last_os_error().raw_os_error() == Some(3) // ESRCH on macOS
}
fn recorded_start_differs(record: &Value, live: Option<(u64, u64)>) -> bool {
    let recorded = record.get("pidStartSec").and_then(Value::as_u64)
        .zip(record.get("pidStartUsec").and_then(Value::as_u64))
        .filter(|(seconds, micros)| *seconds > 0 && *micros < 1_000_000);
    recorded.zip(live).is_some_and(|(expected, observed)| expected != observed)
}
fn recorded_process_definitely_absent(record: &Value) -> bool {
    let Some(pid) = record.get("pid").and_then(Value::as_u64).and_then(|value| u32::try_from(value).ok()).filter(|pid| *pid > 1 && *pid <= i32::MAX as u32) else { return false; };
    if process_definitely_absent(pid) { return true; }
    if record.get("pidStartSec").and_then(Value::as_u64).is_none() || record.get("pidStartUsec").and_then(Value::as_u64).is_none() { return false; }
    let live = crate::process_identity::process_identity(pid).map(|identity| (identity.start_sec, identity.start_usec));
    recorded_start_differs(record, live)
}
fn tool_activity(name: &str) -> &'static str {
    let name = name.to_ascii_lowercase();
    // The reference groups WebFetch with reads, Grep/WebSearch/Task with
    // searches, and local_shell with command execution for the token colors.
    if name == "functions.exec" { "도구 사용" }
    else if name.contains("web") && name.contains("search") { "웹 검색" }
    else if matches!(name.as_str(), "grep" | "task" | "agent" | "toolsearch") { "검색" }
    else if name.contains("apply_patch") || matches!(name.as_str(), "edit" | "write" | "multiedit" | "notebookedit") { "파일 수정" }
    else if name.contains("web") || name.contains("browser") { "웹 확인" }
    else if matches!(name.as_str(), "read" | "glob" | "ls" | "notebookread") { "파일 확인" }
    else if name.contains("exec") || name.contains("terminal") || matches!(name.as_str(), "bash" | "shell" | "local_shell" | "functions.write_stdin" | "mcp__functions__write_stdin") { "작업 실행" }
    else { "도구 사용" }
}

// Reference LumiTokenScreen.Kind: read, edit, command, search, other.
// shortcut: namespace aliases adapt Rium's tool stream to reference categories;
// unknown orchestration tools remain generic until their actual action is known.
fn tool_token_kind(name: &str) -> u8 {
    match name.to_ascii_lowercase().as_str() {
        "read" | "glob" | "ls" | "notebookread" | "webfetch" => 0,
        "edit" | "write" | "multiedit" | "notebookedit" | "apply_patch" | "functions.apply_patch" | "mcp__functions__apply_patch" => 1,
        "bash" | "shell" | "exec_command" | "local_shell" | "functions.exec_command" | "functions.write_stdin" | "mcp__functions__exec_command" | "mcp__functions__write_stdin" => 2,
        "grep" | "websearch" | "web_search" | "task" | "agent" | "toolsearch" => 3,
        _ => 4,
    }
}

fn remember_activity(actions: &mut VecDeque<&'static str>, name: &str) -> &'static str {
    let action = tool_activity(name);
    if actions.len() == 3 { actions.pop_front(); }
    actions.push_back(action);
    action
}
// Only bounded opaque identifiers are retained; tool arguments never leave the parser.
fn update_active_tool(calls: &mut BTreeSet<String>, id: Option<&str>, started: bool) {
    let Some(id) = id.filter(|id| !id.is_empty() && id.len() <= 200 && !id.chars().any(char::is_control)) else { return; };
    if started {
        if calls.len() < 64 { calls.insert(id.to_owned()); }
    } else {
        calls.remove(id);
    }
}

fn valid_session_id(id: &str) -> bool {
    id.len() == 36 && id.bytes().enumerate().all(|(index, byte)| {
        if [8, 13, 18, 23].contains(&index) { byte == b'-' } else { byte.is_ascii_hexdigit() }
    })
}

// Read only matching records; never expose their chat, path or nonce.
fn hook_record(root: &Path, id: &str) -> Option<Value> {
    let session = id.strip_prefix("claude-").unwrap_or(id);
    if !valid_session_id(session) { return None; }
    let path = root.join(format!("{id}.json"));
    let metadata = fs::symlink_metadata(&path).ok()?;
    if !metadata.file_type().is_file() || metadata.len() > MAX_HOOK_BYTES { return None; }
    let record: Value = serde_json::from_reader(File::open(path).ok()?.take(MAX_HOOK_BYTES + 1)).ok()?;
    if record.get("sessionId")?.as_str()? != session { return None; }
    Some(record)
}

fn hook_state(record: &Value, now_ms: u64) -> Option<&'static str> {
    if record.get("state")?.as_str()? != "active" { return None; }
    let updated = record.get("updatedAt")?.as_u64()?;
    if updated > now_ms || now_ms - updated > HOOK_FRESHNESS_MS { return None; }
    if record.get("awaitingPermission").and_then(Value::as_bool) == Some(true) {
        return Some("승인 대기 감지");
    }
    if record.get("awaitingQuestion").and_then(Value::as_bool) == Some(true) {
        return Some("질문 대기 감지");
    }
    if record.get("eventName").and_then(Value::as_str) == Some("PreToolUse") {
        return Some("도구 실행 감지");
    }
    if matches!(record.get("eventName").and_then(Value::as_str), Some("UserPromptSubmit" | "PostToolUse" | "PostToolUseFailure")) {
        return Some("작업 중");
    }
    None
}

// The interactive hook can wait for 55 seconds, longer than the 30-second
// general hook freshness window. Past that window, retain its attention state
// only while the private, authenticated request socket still serves a preview.
fn live_hook_state_with(record: &Value, id: &str, now_ms: u64,
                        probe: impl Fn(&str, bool, bool) -> bool) -> Option<&'static str> {
    if let Some(state) = hook_state(record, now_ms) { return Some(state); }
    if record.get("state")?.as_str()? != "active" || record.get("eventName")?.as_str()? != "PermissionRequest" { return None; }
    let updated = record.get("updatedAt")?.as_u64()?;
    if updated > now_ms || now_ms - updated > 60_000 { return None; }
    let question = record.get("awaitingQuestion").and_then(Value::as_bool) == Some(true);
    let approval = record.get("awaitingPermission").and_then(Value::as_bool) == Some(true);
    if question == approval { return None; }
    let (session, codex) = match id.strip_prefix("claude-") { Some(value) => (value, false), None => (id, true) };
    if !valid_session_id(session) || !probe(session, codex, question) { return None; }
    Some(if question { "질문 대기 감지" } else { "승인 대기 감지" })
}

fn live_hook_state(record: &Value, id: &str, now_ms: u64) -> Option<&'static str> {
    live_hook_state_with(record, id, now_ms, |session, codex, question| {
        let previews = if codex { crate::claude_permission::codex_previews(session) }
            else { crate::claude_permission::previews(session) };
        previews.iter().any(|preview| {
            let Some(request) = preview.get("request") else { return false; };
            let Some(tool) = request.get("tool_name").and_then(Value::as_str) else { return false; };
            (tool == "AskUserQuestion") == question
        })
    })
}

fn latest_hook_record(roots: &[&Path], id: &str, now_ms: u64) -> Option<Value> {
    let mut latest: Option<(u64, Value)> = None;
    let mut conflict = false;
    for root in roots {
        let Some(record) = hook_record(root, id) else { continue; };
        let Some(updated) = record.get("updatedAt").and_then(Value::as_u64) else { continue; };
        if updated > now_ms { return None; }
        match &latest {
            Some((previous, _)) if updated < *previous => {}
            Some((previous, existing)) if updated == *previous => conflict |= existing != &record,
            _ => { latest = Some((updated, record)); conflict = false; }
        }
    }
    if conflict { None } else { latest.map(|(_, record)| record) }
}

#[cfg(test)]
fn fresh_hook_state(root: &Path, id: &str, now_ms: u64) -> Option<&'static str> {
    hook_state(&hook_record(root, id)?, now_ms)
}

fn overlay_stalled(rows: &mut [Value], roots: &[&Path], now_ms: u64) {
    overlay_stalled_with(rows, roots, now_ms, recorded_process_definitely_absent);
}

fn overlay_stalled_with(rows: &mut [Value], roots: &[&Path], now_ms: u64, absent: impl Fn(&Value) -> bool) {
    for row in rows {
        if row.get("state").and_then(Value::as_str) != Some("최근 활동") { continue; }
        let Some(id) = row.get("id").and_then(Value::as_str) else { continue; };
        let Some(record) = latest_hook_record(roots, id, now_ms) else { continue; };
        if record.get("state").and_then(Value::as_str) != Some("active") { continue; }
        let Some(updated) = record.get("updatedAt").and_then(Value::as_u64) else { continue; };
        if updated > now_ms || now_ms - updated > 2 * STALL_SILENCE_MS { continue; }
        if record.get("awaitingPermission").and_then(Value::as_bool) == Some(true) ||
           record.get("awaitingQuestion").and_then(Value::as_bool) == Some(true) { continue; }
        let Some(event @ ("UserPromptSubmit" | "PreToolUse" | "PostToolUse" | "PostToolUseFailure")) = record.get("eventName").and_then(Value::as_str) else { continue; };
        let silent = now_ms - updated;
        let transcript_age = row.get("ageSeconds").and_then(Value::as_u64).unwrap_or(0).saturating_mul(1000);
        let early_deadline = if event == "PreToolUse" { TOOL_STALL_MS } else { IDLE_STALL_MS };
        let process_gone = if silent >= early_deadline && transcript_age >= early_deadline && silent < STALL_SILENCE_MS {
            absent(&record)
        } else { false };
        if !(silent >= STALL_SILENCE_MS && transcript_age >= STALL_SILENCE_MS) && !process_gone { continue; }
        row["state"] = json!("응답 지연 추정");
        row["activity"] = json!("");
        row["toolRunning"] = json!(false);
    }
}

fn agent_work_is_live(state: &str) -> bool {
    matches!(state, "작업 중" | "활동 감지" | "도구 실행 감지" | "도구 실행 중")
}

fn overlay_hook_status(rows: &mut [Value], roots: &[&Path], now_ms: u64) {
    for row in rows {
        let Some(id) = row.get("id").and_then(Value::as_str) else { continue; };
        let Some(record) = latest_hook_record(roots, id, now_ms) else { continue; };
        if record["eventName"] == "SessionEnd" && record["state"] == "stopped" {
            let provider = if id.starts_with("claude-") { "claude" } else { "codex" };
            let state = row["state"].as_str().unwrap_or("");
            let ended_after_log = row["_transcriptModifiedMs"].as_u64().zip(record["updatedAt"].as_u64())
                .is_some_and(|(modified, ended)| modified < ended);
            // A same-millisecond or newer transcript may belong to a resumed session.
            if row["source"] == provider && ended_after_log &&
                (agent_work_is_live(state) || state == "응답 지연 추정" || activity_priority(row) < 2) {
                row["state"] = json!("최근 활동");
                row["activity"] = json!("");
                row["toolRunning"] = json!(false);
                row["pendingQuestions"] = json!([]);
            }
            continue;
        }
        if recorded_process_definitely_absent(&record) { continue; }
        let Some(state) = live_hook_state(&record, id, now_ms) else { continue; };
        let hook_age = now_ms.saturating_sub(record.get("updatedAt").and_then(Value::as_u64).unwrap_or(now_ms));
        let prompt_after_transcript = record.get("eventName").and_then(Value::as_str) == Some("UserPromptSubmit") &&
            row.get("ageSeconds").and_then(Value::as_u64).is_some_and(|age| age.saturating_mul(1000) > hook_age.saturating_add(1000));
        // An explicit completion/abort from the transcript is stronger than a
        // hook record unless a later user prompt clearly starts another turn.
        if matches!(row.get("state").and_then(Value::as_str), Some("완료" | "실패" | "중단됨")) && !prompt_after_transcript { continue; }
        if row.get("state").and_then(Value::as_str).is_some_and(|old| old.starts_with("질문 대기") || old.starts_with("승인 대기"))
            && state != "승인 대기 감지" && !prompt_after_transcript { continue; }
        let transcript_age = row.get("ageSeconds").and_then(Value::as_u64).map(|age| age.saturating_mul(1000));
        // A completed tool can leave a still-fresh PreToolUse hook behind.
        // Do not replace a newer active transcript with that older routine
        // signal; explicit permission/question signals remain authoritative.
        if matches!(state, "작업 중" | "도구 실행 감지")
            && matches!(row.get("state").and_then(Value::as_str), Some("작업 중" | "활동 감지"))
            && transcript_age.is_some_and(|age| hook_age > age.saturating_add(1000)) { continue; }
        row["state"] = json!(state);
        if state.starts_with("승인 대기") || state.starts_with("질문 대기") {
            row["toolRunning"] = json!(false);
            row["activity"] = json!("");
        } else if transcript_age.map_or(true, |age| hook_age <= age.saturating_add(1000)) {
            row["toolRunning"] = json!(state == "도구 실행 감지");
        }
        if row.get("ageSeconds").and_then(Value::as_u64).is_some_and(|age| hook_age / 1000 < age) {
            row["ageSeconds"] = json!(hook_age / 1000);
        }
        if prompt_after_transcript {
            row["activity"] = json!("");
            row["activities"] = json!([]);
            row["pendingQuestions"] = json!([]);
        }
    }
}
// A hook can arrive before its transcript is discoverable, or when a session
// was resumed from an older date directory. Surface only a fresh, matching
// record and never emit its full path, tool input, or process details.
fn append_hook_only_activity(rows: &mut Vec<Value>, roots: &[&Path], now_ms: u64) {
    let mut ids = BTreeSet::new();
    for root in roots {
        let Ok(entries) = fs::read_dir(root) else { continue; };
        for entry in entries.flatten().take(crate::claude_permission::REGISTRY_SCAN_LIMIT) {
            let path = entry.path();
            if path.extension().and_then(|value| value.to_str()) != Some("json") { continue; }
            let Some(id) = path.file_stem().and_then(|value| value.to_str()) else { continue; };
            if valid_session_id(id.strip_prefix("claude-").unwrap_or(id)) { ids.insert(id.to_owned()); }
        }
    }
    let mut candidates = Vec::new();
    for id in ids {
        if rows.iter().any(|row| row.get("id").and_then(Value::as_str) == Some(id.as_str())) { continue; }
        let Some(record) = latest_hook_record(roots, &id, now_ms) else { continue; };
        let Some(state) = live_hook_state(&record, &id, now_ms) else { continue; };
        let Some(updated) = record.get("updatedAt").and_then(Value::as_u64) else { continue; };
        if recorded_process_definitely_absent(&record) { continue; }
        let source = if id.starts_with("claude-") { "claude" } else { "codex" };
        let fallback = if source == "claude" { "Claude" } else { "Codex" };
        let project = record.get("cwd").and_then(Value::as_str).filter(|cwd| cwd.len() <= 4096)
            .and_then(|cwd| Path::new(cwd).file_name()).and_then(|name| name.to_str())
            .map(|name| name.chars().filter(|c| !c.is_control()).take(80).collect::<String>())
            .filter(|name| !name.is_empty()).unwrap_or_else(|| fallback.to_owned());
        candidates.push((updated, json!({"id":id,"source":source,"project":project,"state":state,
            "activity":"","activities":[],"toolEvents":[],"toolRunning":state == "도구 실행 감지",
            "ageSeconds":now_ms.saturating_sub(updated) / 1000,"pendingQuestions":[]})));
    }
    sort_hook_candidates(&mut candidates);
    rows.extend(candidates.into_iter().take(20).map(|(_, row)| row));
}

fn sort_hook_candidates(candidates: &mut [(u64, Value)]) {
    candidates.sort_unstable_by(|a, b| activity_priority(&a.1).cmp(&activity_priority(&b.1))
        .then_with(|| b.0.cmp(&a.0))
        .then_with(|| a.1.get("id").and_then(Value::as_str).cmp(&b.1.get("id").and_then(Value::as_str))));
}

fn recent_directories(path: &Path, limit: usize) -> Vec<PathBuf> {
    let Ok(entries) = fs::read_dir(path) else { return vec![]; };
    let mut dirs: Vec<_> = entries.flatten().filter_map(|e| {
        let kind = e.file_type().ok()?;
        let name = e.file_name(); let name = name.to_str()?;
        if kind.is_dir() && !kind.is_symlink() && (name.len() == 2 || name.len() == 4) && name.bytes().all(|c| c.is_ascii_digit()) { Some(e.path()) } else { None }
    }).collect();
    dirs.sort_unstable_by(|a, b| b.cmp(a)); dirs.truncate(limit); dirs
}

// Keep offsets stable when the bounded tail moves forward. Only the offset is
// attached to a parsed record; the transcript and its contents stay local.
fn records_with_offsets<R: BufRead>(mut reader: R, mut position: u64) -> impl Iterator<Item = Value> {
    std::iter::from_fn(move || loop {
        let mut bytes = Vec::new();
        let length = match reader.read_until(b'\n', &mut bytes) { Ok(0) | Err(_) => return None, Ok(n) => n };
        let start = position;
        position = position.saturating_add(length as u64);
        let Ok(mut record) = serde_json::from_slice::<Value>(&bytes) else { continue; };
        let Some(object) = record.as_object_mut() else { continue; };
        object.insert("_rium_offset".to_owned(), json!(start));
        return Some(record);
    })
}

fn seek_tail(file: &mut File, offset: u64) -> std::io::Result<bool> {
    if offset == 0 { file.seek(SeekFrom::Start(0))?; return Ok(false); }
    file.seek(SeekFrom::Start(offset - 1))?;
    let mut previous = [0u8; 1];
    file.read_exact(&mut previous)?;
    Ok(previous[0] != b'\n')
}

fn oversized_record_start(file: &mut File, mut cursor: u64) -> Option<u64> {
    let limit = cursor.saturating_sub(MAX_TRANSCRIPT_BACKTRACK_BYTES);
    let mut block = [0; 64 * 1024];
    while cursor > limit {
        let start = cursor.saturating_sub(block.len() as u64).max(limit);
        let bytes = &mut block[..(cursor - start) as usize];
        file.seek(SeekFrom::Start(start)).ok()?;
        file.read_exact(bytes).ok()?;
        if let Some(index) = bytes.iter().rposition(|byte| *byte == b'\n') {
            return Some(start + index as u64 + 1);
        }
        cursor = start;
    }
    (limit == 0).then_some(0)
}

#[derive(serde::Deserialize)]
struct CodexRecordHeader {
    #[serde(rename = "type")]
    kind: String,
    payload: Option<CodexPayloadHeader>,
}

#[derive(serde::Deserialize)]
struct CodexPayloadHeader {
    #[serde(rename = "type")]
    kind: Option<String>,
    call_id: Option<String>,
}

fn summarize_large_codex_record(reader: &mut dyn Read, _: u64) -> Option<Option<Value>> {
    let record: CodexRecordHeader = serde_json::from_reader(reader).ok()?;
    match (record.kind.as_str(), record.payload) {
        ("compacted", _) => Some(None),
        ("response_item", Some(payload))
            if matches!(payload.kind.as_deref(), Some("function_call_output" | "custom_tool_call_output")) =>
            Some(Some(json!({"type":"response_item","payload":{"type":payload.kind,"call_id":payload.call_id}}))),
        _ => None,
    }
}

// Recover earlier lifecycle events when a large record crowds them out of the tail.
fn records_before_large_line(file: &mut File, cut: u64, next: u64, complete: bool,
                             summarize: impl FnOnce(&mut dyn Read, u64) -> Option<Option<Value>>) -> Option<Vec<Value>> {
    let start = oversized_record_start(file, cut)?;
    if next - start <= TAIL_BYTES { return None; }
    let output = if complete {
        file.seek(SeekFrom::Start(start)).ok()?;
        summarize(&mut BufReader::new((&mut *file).take(next - start)), start)?
    } else {
        None
    };
    let offset = start.saturating_sub(TAIL_BYTES);
    let partial = seek_tail(file, offset).ok()?;
    let mut reader = BufReader::new(file.take(start - offset));
    let skipped = if partial { reader.read_until(b'\n', &mut Vec::new()).ok()? as u64 } else { 0 };
    let mut records: Vec<_> = records_with_offsets(reader, offset + skipped).collect();
    records.extend(output);
    Some(records)
}

fn transcript_tail(mut file: File, size: u64, summarize: impl FnOnce(&mut dyn Read, u64) -> Option<Option<Value>>)
    -> Option<impl Iterator<Item = Value>>
{
    let offset = size.saturating_sub(TAIL_BYTES);
    let partial = seek_tail(&mut file, offset).ok()?;
    let mut skipped = Vec::new();
    if partial {
        BufReader::new((&mut file).take(size - offset)).read_until(b'\n', &mut skipped).ok()?;
    }
    let next = offset + skipped.len() as u64;
    let prefix = if skipped.len() as u64 > TAIL_BYTES / 2 {
        records_before_large_line(&mut file, offset, next, skipped.last() == Some(&b'\n'), summarize).unwrap_or_default()
    } else { Vec::new() };
    file.seek(SeekFrom::Start(next)).ok()?;
    let tail = records_with_offsets(BufReader::new(file.take(size - next)), next);
    Some(prefix.into_iter().chain(tail))
}

// Claude may append multiple chunks for the same message. A stable hash of
// its opaque ID avoids treating each chunk as a new incoming message.
fn message_id_marker(id: &str) -> Option<u64> {
    if id.is_empty() || id.len() > 512 { return None; }
    let hash = id.bytes().fold(14_695_981_039_346_656_037u64, |hash, byte|
        (hash ^ u64::from(byte)).wrapping_mul(1_099_511_628_211));
    // Preserve integer precision even if an intermediate JSON reader uses
    // IEEE-754 doubles; this is an event marker, not a security hash.
    Some(hash & ((1u64 << 53) - 1))
}

// Re-read the last known tool record at its old position before treating a
// nonoverlapping tail as an append. Inputs and full records stay in this process.
fn verified_tool_anchor(path: &Path, row: &Value, anchors: &[Value]) -> Option<(u64, u64)> {
    let id = row.get("id")?.as_str()?;
    let source = row.get("source")?.as_str()?;
    let identity = row.get("transcriptIdentity")?.as_str()?;
    let anchor = anchors.iter().find(|a| a.get("id").and_then(Value::as_str) == Some(id)
        && a.get("source").and_then(Value::as_str) == Some(source)
        && a.get("identity").and_then(Value::as_str) == Some(identity))?;
    let offset = anchor.get("offset")?.as_u64()?;
    let marker = anchor.get("marker")?.as_u64()?;
    let mut file = File::open(path).ok()?;
    let meta = file.metadata().ok()?;
    if !meta.is_file() || transcript_identity(&meta).as_deref() != Some(identity) || offset >= meta.len()
        || file.seek(SeekFrom::Start(offset)).is_err() { return None; }
    let mut bytes = Vec::new();
    let mut reader = BufReader::new(file.take(TAIL_BYTES + 1));
    if reader.read_until(b'\n', &mut bytes).is_err() || bytes.len() > TAIL_BYTES as usize || bytes.last() != Some(&b'\n') { return None; }
    let record = serde_json::from_slice::<Value>(&bytes).ok()?;
    let matches_id = |value: Option<&str>| value.and_then(message_id_marker) == Some(marker);
    let matches = if source == "codex" {
        let payload = &record["payload"];
        record.get("type").and_then(Value::as_str) == Some("response_item")
            && matches!(payload.get("type").and_then(Value::as_str), Some("function_call" | "custom_tool_call"))
            && matches_id(payload.get("call_id").and_then(Value::as_str))
    } else { source == "claude" && record.get("type").and_then(Value::as_str) == Some("assistant")
        && id.strip_prefix("claude-").is_some_and(|session| record.get("sessionId").and_then(Value::as_str) == Some(session))
        && record.get("isSidechain").and_then(Value::as_bool) != Some(true)
        && record.pointer("/message/content").and_then(Value::as_array).is_some_and(|items| items.iter().any(|item|
            item.get("type").and_then(Value::as_str) == Some("tool_use") && matches_id(item.get("id").and_then(Value::as_str)))) };
    matches.then_some((marker, offset))
}

// shortcut: identical adjacent forms may still be distinct messages when no shared ID exists.
// Some Codex transcripts contain both an event and a response item for the
// same message. Compare only a single bounded text fragment in this process;
// it is never returned or persisted. Other shapes keep their own markers.
fn codex_message_text(record: &Value) -> Option<(u8, &str)> {
    let payload = record.get("payload")?;
    let text = match (record.get("type")?.as_str()?, payload.get("type")?.as_str()?) {
        ("event_msg", "agent_message") => (0, payload.get("message")?.as_str()?),
        ("response_item", "message") if payload.get("role")?.as_str()? == "assistant" => {
            let content = payload.get("content")?.as_array()?;
            if content.len() != 1 || content[0].get("type")?.as_str()? != "output_text" { return None; }
            (1, content[0].get("text")?.as_str()?)
        }
        _ => return None,
    };
    if text.1.is_empty() || text.1.len() > 8192 { None } else { Some(text) }
}

// A bounded list of opaque identifiers and categories; tool inputs stay local.
fn remember_tool_event(events: &mut VecDeque<(u64, &'static str, u8, Option<u64>)>, record: &Value, id: Option<&str>, name: &str) {
    let offset = record.get("_rium_offset").and_then(Value::as_u64).filter(|offset| *offset < (1u64 << 53));
    let marker = id.and_then(message_id_marker)
        .or(offset);
    let Some(marker) = marker else { return; };
    if events.iter().any(|(previous, _, _, _)| *previous == marker) { return; }
    if events.len() == 16 { events.pop_front(); }
    events.push_back((marker, tool_activity(name), tool_token_kind(name), offset));
}

// Track exact question identifiers and indexes. Only current non-secret
// prompts/options are shown; answers and other transcript data are not emitted.
// A successful async tool output acknowledges display, not an answer.
#[derive(Default)]
struct AsyncQuestions {
    pending: HashMap<String, (String, BTreeSet<usize>)>,
    visible: HashMap<String, Vec<(usize, Value)>>,
    order: VecDeque<String>,
}
impl AsyncQuestions {
    fn parse(value: &Value) -> Option<Value> {
        if value.is_object() || value.is_array() { return Some(value.clone()); }
        value.as_str().and_then(|text| serde_json::from_str(text).ok())
    }
    fn tool(name: &str) -> bool {
        let lower = name.to_ascii_lowercase().replace('_', "").replace('-', "");
        lower == "requestuserinputasync"
    }
    fn consume(&mut self, record: &Value) {
        let kind = record.get("type").and_then(Value::as_str).unwrap_or("");
        let payload = &record["payload"];
        let subtype = payload.get("type").and_then(Value::as_str).unwrap_or("");
        if kind == "event_msg" && subtype == "turn_aborted" {
            self.pending.clear();
            self.visible.clear();
            self.order.clear();
            return;
        }
        if kind != "response_item" { return; }
        if matches!(subtype, "function_call" | "custom_tool_call") {
            let Some(name) = payload.get("name").and_then(Value::as_str).filter(|name| Self::tool(name)) else { return; };
            let Some(call) = payload.get("call_id").and_then(Value::as_str).filter(|call| !call.is_empty() && call.len() <= 200) else { return; };
            if self.pending.contains_key(call) || self.pending.len() >= 32 { return; }
            if matches!(payload.get("status").and_then(Value::as_str), Some("failed" | "cancelled" | "canceled")) { return; }
            let input = payload.get("arguments").or_else(|| payload.get("input")).and_then(Self::parse);
            let indexes: BTreeSet<_> = input.as_ref().and_then(|input| input.get("questions")).and_then(Value::as_array)
                .map(|questions| questions.iter().take(3).enumerate().filter_map(|(index, question)| {
                    question.get("title").and_then(Value::as_str).filter(|text| !text.trim().is_empty())
                        .or_else(|| question.get("question").and_then(Value::as_str).filter(|text| !text.trim().is_empty())).map(|_| index)
                }).collect()).unwrap_or_default();
            if !indexes.is_empty() {
                let mut visible = Vec::new();
                if let Some(items) = input.as_ref().and_then(|input| input.get("questions")).and_then(Value::as_array) {
                    for (index, question) in items.iter().take(3).enumerate() {
                        if name != "request_user_input_async" || !indexes.contains(&index)
                            || question.get("isSecret").and_then(Value::as_bool) == Some(true)
                            || question.get("is_secret").and_then(Value::as_bool) == Some(true)
                            || question.get("multiSelect").and_then(Value::as_bool) == Some(true)
                            || question.get("multi_select").and_then(Value::as_bool) == Some(true) { continue; }
                        let title = question.get("title").and_then(Value::as_str).filter(|s| !s.trim().is_empty())
                            .or_else(|| question.get("question").and_then(Value::as_str).filter(|s| !s.trim().is_empty()));
                        let Some(title) = title else { continue; };
                        let title = title.trim();
                        if title.chars().count() > 1000 || title.contains("</send_user_message_question_reply>") { continue; }
                        let raw_options = question.get("options").and_then(Value::as_array);
                        if raw_options.is_some_and(|options| options.len() > 20) { continue; }
                        let mut options = Vec::new();
                        let mut valid = true;
                        for option in raw_options.into_iter().flatten() {
                            let Some(label) = option.as_str().or_else(|| option.get("label").and_then(Value::as_str)) else { valid = false; break; };
                            if label.trim().is_empty() || label != label.trim() || label.chars().count() > 200 { valid = false; break; }
                            options.push(label.to_owned());
                        }
                        if !valid { continue; }
                        let id = json!([name, call, index]).to_string();
                        if id.len() > 230 { continue; }
                        visible.push((index, json!({"id":id,"title":title,"options":options})));
                    }
                }
                if !visible.is_empty() { self.visible.insert(call.to_owned(), visible); }
                self.pending.insert(call.to_owned(), (name.to_owned(), indexes));
                self.order.push_back(call.to_owned());
            }
            return;
        }
        if matches!(subtype, "function_call_output" | "custom_tool_call_output") {
            let Some(call) = payload.get("call_id").and_then(Value::as_str) else { return; };
            let result = payload.get("output").or_else(|| payload.get("content")).and_then(Self::parse);
            if result.as_ref().is_some_and(|result| result.get("accepted").and_then(Value::as_bool) == Some(false)
                || result.get("isError").and_then(Value::as_bool) == Some(true)
                || matches!(result.get("status").and_then(Value::as_str), Some("failed" | "cancelled" | "canceled"))) {
                self.pending.remove(call);
                self.visible.remove(call);
                self.order.retain(|previous| previous != call);
            }
            return;
        }
        if subtype != "message" || payload.get("role").and_then(Value::as_str) != Some("user") { return; }
        let Some(content) = payload.get("content").and_then(Value::as_array) else { return; };
        for part in content {
            let Some(text) = part.get("text").and_then(Value::as_str) else { continue; };
            let Some((_, text)) = text.split_once("<send_user_message_question_reply>") else { continue; };
            let Some((json, _)) = text.split_once("</send_user_message_question_reply>") else { continue; };
            let Ok(replies) = serde_json::from_str::<Value>(json.trim()) else { continue; };
            for reply in replies.as_array().into_iter().flatten() {
                let Some(id) = reply.get("questionItemId").and_then(Self::parse) else { continue; };
                let Some(parts) = id.as_array().filter(|parts| parts.len() == 3) else { continue; };
                let (Some(tool), Some(call), Some(index)) = (parts[0].as_str(), parts[1].as_str(), parts[2].as_u64()) else { continue; };
                if index > 2 || !Self::tool(tool) { continue; }
                let (resolved, remove) = if let Some((name, indexes)) = self.pending.get_mut(call) {
                    if name.as_str() != tool { (false, false) }
                    else { let resolved = indexes.remove(&(index as usize)); (resolved, indexes.is_empty()) }
                } else { (false, false) };
                if resolved {
                    if let Some(items) = self.visible.get_mut(call) { items.retain(|(item_index, _)| *item_index != index as usize); }
                }
                if remove {
                    self.pending.remove(call);
                    self.visible.remove(call);
                    self.order.retain(|previous| previous != call);
                }
            }
        }
    }
    fn visible(&self) -> Vec<Value> {
        self.order.iter().filter_map(|call| self.visible.get(call))
            .flat_map(|items| items.iter().map(|(_, question)| question.clone())).take(6).collect()
    }
}

fn activity(meta: &Value, lines: impl Iterator<Item = Value>, recently_modified: bool) -> Option<Value> {
    let p = meta.get("payload")?;
    if meta.get("type")?.as_str()? != "session_meta" { return None; }
    if p.get("source").and_then(Value::as_object).and_then(|s| s.get("subagent")).is_some() || p.get("thread_source").and_then(Value::as_str) == Some("guardian_review") { return None; }
    let id = p.get("id").or_else(|| p.get("session_id"))?.as_str()?;
    if !valid_session_id(id) { return None; }
    let project = p.get("cwd").and_then(Value::as_str).and_then(|s| Path::new(s).file_name()).and_then(|s| s.to_str()).unwrap_or("Codex");
    let mut state = "최근 활동"; let mut action = "";
    // Only the sequence number is returned; message bodies never leave this parser.
    let mut message_marker: Option<u64> = None;
    let mut message_aliases: Vec<u64> = Vec::new();
    let mut previous_message: Option<(u8, String, u64)> = None;
    let mut recent_actions = VecDeque::with_capacity(3);
    let mut tool_events = VecDeque::with_capacity(16);
    let mut active_tools = BTreeSet::new();
    let mut questions = AsyncQuestions::default();
    for record in lines {
        questions.consume(&record);
        let kind = record.get("type").and_then(Value::as_str).unwrap_or("");
        let payload = &record["payload"];
        let subtype = payload.get("type").and_then(Value::as_str).unwrap_or("");
        if kind == "event_msg" && matches!(subtype, "task_started" | "task_complete" | "turn_aborted")
            || kind == "response_item" && (matches!(subtype, "function_call" | "custom_tool_call")
                || subtype == "message" && payload.get("role").and_then(Value::as_str) == Some("user")) {
            previous_message = None;
        }
        let agent_message = matches!(kind, "event_msg" | "response_item") && subtype == "agent_message"
            || kind == "response_item" && subtype == "message" && payload.get("role").and_then(Value::as_str) == Some("assistant");
        if agent_message {
            if let Some(marker) = record.get("_rium_offset").and_then(Value::as_u64).or_else(|| record.get("ordinal").and_then(Value::as_u64)) {
                match codex_message_text(&record) {
                    Some((form, text)) if previous_message.as_ref().is_some_and(|(prior_form, prior_text, _)| *prior_form != form && prior_text.as_str() == text) => {
                        message_marker = previous_message.take().map(|(_, _, previous)| previous);
                        message_aliases = vec![marker];
                    }
                    Some((form, text)) => {
                        message_marker = Some(marker);
                        message_aliases.clear();
                        previous_message = Some((form, text.to_owned(), marker));
                    }
                    None => { message_marker = Some(marker); message_aliases.clear(); previous_message = None; }
                }
            }
        }
        if kind == "event_msg" {
            match subtype {
                "task_started" => { state = "작업 중"; action = ""; recent_actions.clear(); tool_events.clear(); active_tools.clear(); },
                // Only structured error data changes the outcome; ordinary
                // discussion of an error or rate limit is not a failure signal.
                "task_complete" => {
                    let failed = payload.get("error").is_some_and(|error| !error.is_null() && error != &Value::Bool(false));
                    state = if failed { "실패" } else { "완료" };
                    action = ""; active_tools.clear();
                },
                "turn_aborted" => { state = "중단됨"; action = ""; active_tools.clear(); },
                _ => {}
            }
        } else if kind == "response_item" && matches!(subtype, "function_call" | "custom_tool_call") {
            let name = payload.get("name").and_then(Value::as_str).unwrap_or("");
            action = remember_activity(&mut recent_actions, name);
            remember_tool_event(&mut tool_events, &record, payload.get("call_id").and_then(Value::as_str), name);
            update_active_tool(&mut active_tools, payload.get("call_id").and_then(Value::as_str), true);
        } else if kind == "response_item" && matches!(subtype, "function_call_output" | "custom_tool_call_output") {
            update_active_tool(&mut active_tools, payload.get("call_id").and_then(Value::as_str), false);
        }
    }
    // A long-running turn can start before the bounded tail. Recent tool
    // activity indicates activity, but does not prove the task's exact state.
    if state == "최근 활동" && !action.is_empty() && recently_modified { state = "활동 감지"; }
    // A missing completion can also mean the process exited or the session
    // stopped updating. Never leave an old start record marked as running.
    if state == "작업 중" && !recently_modified { state = "최근 활동"; action = ""; }
    if !questions.pending.is_empty() && !matches!(state, "실패" | "중단됨") {
        state = "질문 대기";
        action = "";
    }
    let pending_questions = if state == "질문 대기" { questions.visible() } else { Vec::new() };
    let tool_events: Vec<_> = tool_events.into_iter().map(|(marker, category, kind, offset)| json!({"marker":marker,"activity":category,"kind":kind,"offset":offset})).collect();
    let tool_running = recently_modified && matches!(state, "작업 중" | "활동 감지") && !active_tools.is_empty();
    Some(json!({"id":id,"source":"codex","project":project,"state":state,"activity":action,"activities":recent_actions,"toolEvents":tool_events,"toolRunning":tool_running,"messageMarker":message_marker,"messageAliases":message_aliases,"pendingQuestions":pending_questions}))
}

// Read the question only; answers and other tool arguments are never emitted.
fn claude_questions(item: &Value) -> Option<(String, Vec<Value>)> {
    if item.get("type")?.as_str()? != "tool_use" || item.get("name")?.as_str()? != "AskUserQuestion" { return None; }
    let call = item.get("id")?.as_str()?;
    if call.is_empty() || call.len() > 200 || call.chars().any(char::is_control) { return None; }
    let questions = item.get("input")?.get("questions")?.as_array()?;
    if questions.is_empty() || questions.len() > 3 { return None; }
    let mut result = Vec::new();
    for (index, question) in questions.iter().enumerate() {
        if question.get("isSecret").and_then(Value::as_bool) == Some(true)
            || question.get("is_secret").and_then(Value::as_bool) == Some(true) { continue; }
        let Some(title) = question.get("question").and_then(Value::as_str).map(str::trim)
            .filter(|title| !title.is_empty() && title.chars().count() <= 1000) else { continue; };
        let raw_options = question.get("options").and_then(Value::as_array);
        if raw_options.is_some_and(|options| options.len() > 20) { continue; }
        let mut options = Vec::new();
        let mut valid = true;
        for option in raw_options.into_iter().flatten() {
            let Some(label) = option.as_str().or_else(|| option.get("label").and_then(Value::as_str)) else { valid = false; break; };
            if label.trim().is_empty() || label != label.trim() || label.chars().count() > 200 { valid = false; break; }
            options.push(label.to_owned());
        }
        if valid {
            result.push(json!({"id":format!("claude:{call}:{index}"),"title":title,"options":options}));
        }
    }
    (!result.is_empty()).then(|| (call.to_owned(), result))
}

// Claude Code stores JSONL under its projects directory. Read only the tail,
// ignore child-agent records, and report activity rather than claiming that a
// recently changed transcript proves a live process or a permission request.
fn claude_activity(id: &str, lines: impl Iterator<Item = Value>, recently_modified: bool) -> Option<Value> {
    if !valid_session_id(id) { return None; }
    let mut project = String::from("Claude");
    let mut state = "최근 활동";
    let mut seen = false;
    let mut message_marker = None;
    let mut recent_actions = VecDeque::with_capacity(3);
    let mut tool_events = VecDeque::with_capacity(16);
    let mut active_tools = BTreeSet::new();
    let mut questions: HashMap<String, Vec<Value>> = HashMap::new();
    for record in lines {
        if record.get("sessionId").and_then(Value::as_str) != Some(id)
            || record.get("isSidechain").and_then(Value::as_bool) == Some(true) { continue; }
        let kind = record.get("type").and_then(Value::as_str).unwrap_or("");
        if !matches!(kind, "assistant" | "user") { continue; }
        if let Some(name) = record.get("cwd").and_then(Value::as_str).and_then(|p| Path::new(p).file_name()).and_then(|s| s.to_str()) {
            let clean: String = name.chars().filter(|c| !c.is_control()).take(80).collect();
            if !clean.is_empty() { project = clean; }
        }
        let message = &record["message"];
        if kind == "assistant" {
            seen = true;
            if record.get("isApiErrorMessage").and_then(Value::as_bool) == Some(true) {
                state = "실패";
                questions.clear(); active_tools.clear();
                continue;
            }
            if let Some(content) = message.get("content").and_then(Value::as_array) {
                if content.iter().any(|item| item.get("type").and_then(Value::as_str) == Some("text")) {
                    message_marker = message.get("id").and_then(Value::as_str).and_then(message_id_marker)
                        .or_else(|| record.get("_rium_offset").and_then(Value::as_u64));
                }
                for item in content {
                    if item.get("type").and_then(Value::as_str) == Some("tool_use") {
                        update_active_tool(&mut active_tools, item.get("id").and_then(Value::as_str), true);
                        if let Some((call, entries)) = claude_questions(item) {
                            if questions.len() < 32 || questions.contains_key(&call) { questions.insert(call, entries); }
                        }
                        if let Some(name) = item.get("name").and_then(Value::as_str) {
                            remember_activity(&mut recent_actions, name);
                            remember_tool_event(&mut tool_events, &record, item.get("id").and_then(Value::as_str), name);
                        }
                    }
                }
            }
            state = if message.get("stop_reason").and_then(Value::as_str) == Some("end_turn") { "완료" }
                else if recently_modified { "활동 감지" } else { "최근 활동" };
            if state == "완료" { questions.clear(); active_tools.clear(); }
        } else {
            let content = message.get("content").and_then(Value::as_array);
            let tool_result = content.is_some_and(|items| items.iter().any(|item| item.get("type").and_then(Value::as_str) == Some("tool_result")));
            for item in content.into_iter().flatten() {
                if item.get("type").and_then(Value::as_str) == Some("tool_result") {
                    update_active_tool(&mut active_tools, item.get("tool_use_id").and_then(Value::as_str), false);
                    if let Some(call) = item.get("tool_use_id").and_then(Value::as_str) { questions.remove(call); }
                }
            }
            if !tool_result { seen = true; recent_actions.clear(); tool_events.clear(); questions.clear(); active_tools.clear(); state = if recently_modified { "활동 감지" } else { "최근 활동" }; }
        }
    }
    let mut ordered: Vec<_> = questions.into_iter().collect();
    ordered.sort_unstable_by(|a, b| a.0.cmp(&b.0));
    let pending: Vec<Value> = ordered.into_iter().flat_map(|(_, items)| items).take(6).collect();
    if !pending.is_empty() { state = "질문 대기 감지"; }
    let tool_events: Vec<_> = tool_events.into_iter().map(|(marker, category, kind, offset)| json!({"marker":marker,"activity":category,"kind":kind,"offset":offset})).collect();
    let tool_running = recently_modified && state == "활동 감지" && !active_tools.is_empty();
    seen.then(|| json!({"id":format!("claude-{id}"),"source":"claude","project":project,"state":state,"activity":"", "activities":recent_actions,"toolEvents":tool_events,"toolRunning":tool_running,"messageMarker":message_marker,"pendingQuestions":pending}))
}

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct ClaudeRecordHeader {
    #[serde(rename = "type")]
    kind: String,
    session_id: Option<String>,
    cwd: Option<String>,
    is_sidechain: Option<bool>,
    is_api_error_message: Option<bool>,
    message: Option<ClaudeMessageHeader>,
}

#[derive(Default, serde::Deserialize)]
struct ClaudeMessageHeader {
    id: Option<String>,
    stop_reason: Option<String>,
    content: Option<Vec<ClaudeContentHeader>>,
}

#[derive(serde::Deserialize)]
struct ClaudeContentHeader {
    #[serde(rename = "type")]
    kind: String,
    tool_use_id: Option<String>,
}

fn summarize_large_claude_record(reader: &mut dyn Read, offset: u64, id: &str) -> Option<Option<Value>> {
    let record: ClaudeRecordHeader = serde_json::from_reader(reader).ok()?;
    if record.session_id.as_deref() != Some(id) || record.is_sidechain == Some(true) {
        return Some(None);
    }
    let message = record.message.unwrap_or_default();
    let mut content = Vec::new();
    match record.kind.as_str() {
        "user" => {
            content.extend(message.content.into_iter().flatten().filter(|item| item.kind == "tool_result")
                .map(|item| json!({"type":"tool_result","tool_use_id":item.tool_use_id})));
            if content.is_empty() { return None; }
        }
        "assistant" if message.stop_reason.as_deref() == Some("end_turn") || record.is_api_error_message == Some(true) => {
            if message.content.into_iter().flatten().any(|item| item.kind == "text") {
                content.push(json!({"type":"text"}));
            }
        }
        _ => return None,
    }
    Some(Some(json!({"type":record.kind, "sessionId":id, "cwd":record.cwd, "_rium_offset":offset,
        "isApiErrorMessage":record.is_api_error_message,
        "message":{"id":message.id, "stop_reason":message.stop_reason, "content":content}})))
}

fn inspect_claude(path: &Path, now: SystemTime) -> Option<Value> {
    let id = path.file_stem()?.to_str()?;
    if !valid_session_id(id) { return None; }
    let metadata = fs::symlink_metadata(path).ok()?;
    if !metadata.file_type().is_file() { return None; }
    let age = now.duration_since(metadata.modified().ok()?).ok()?;
    if age > Duration::from_secs(QUESTION_RETENTION_SECONDS) { return None; }
    let file = File::open(path).ok()?;
    let opened = file.metadata().ok()?;
    if !opened.is_file() || opened.dev() != metadata.dev() || opened.ino() != metadata.ino() { return None; }
    let lines = transcript_tail(file, metadata.len(), |reader, offset| summarize_large_claude_record(reader, offset, id))?;
    let mut row = claude_activity(id, lines, age <= Duration::from_secs(30))?;
    row["ageSeconds"] = json!(age.as_secs());
    row["transcriptIdentity"] = json!(transcript_identity(&opened));
    row["transcriptLength"] = json!(metadata.len());
    row["_transcriptModifiedMs"] = json!(transcript_modified_ms(&metadata));
    Some(row)
}

fn append_observed_claude(candidates: &mut Vec<(SystemTime, PathBuf)>, root: &Path, observed: &[String], now: SystemTime) {
    let Ok(canonical_root) = fs::canonicalize(root) else { return; };
    let mut known: BTreeSet<PathBuf> = candidates.iter().filter_map(|(_, path)| fs::canonicalize(path).ok()).collect();
    let initial = candidates.len();
    for path in observed.iter().take(64).filter(|path| path.len() <= 4096) {
        if candidates.len() >= initial + OBSERVED_EXTRA_LIMIT { break; }
        let Some(candidate) = observed_candidate(root, Path::new(path), now) else { continue; };
        let Ok(relative) = candidate.1.strip_prefix(&canonical_root) else { continue; };
        if relative.components().count() != 2 || !candidate.1.file_stem().and_then(|id| id.to_str()).is_some_and(valid_session_id) { continue; }
        if known.insert(candidate.1.clone()) { candidates.push(candidate); }
    }
}

#[cfg(test)]
fn recent_claude(root: &Path, now: SystemTime, observed: &[String]) -> Vec<Value> {
    recent_claude_with_anchors(root, now, observed, &[], false)
}
// Candidates are ordered newest first; duplicate paths can describe one session.
fn unique_activity_rows(rows: impl Iterator<Item = Value>, limit: usize) -> Vec<Value> {
    let mut seen = BTreeSet::new();
    rows.filter(|row| {
        let Some(source) = row.get("source").and_then(Value::as_str) else { return false; };
        let Some(id) = row.get("id").and_then(Value::as_str) else { return false; };
        seen.insert((source.to_owned(), id.to_owned()))
    }).take(limit).collect()
}

fn recent_claude_with_anchors(root: &Path, now: SystemTime, observed: &[String], anchors: &[Value],
                              include_watch_files: bool) -> Vec<Value> {
    let mut candidates = Vec::new();
    if let Ok(projects) = fs::read_dir(root) {
        for project in projects.flatten().take(512) {
            let Ok(kind) = project.file_type() else { continue; };
            if !kind.is_dir() || kind.is_symlink() { continue; }
            let Ok(files) = fs::read_dir(project.path()) else { continue; };
            for entry in files.flatten().take(512) {
                let Ok(kind) = entry.file_type() else { continue; };
                let path = entry.path();
                if !kind.is_file() || kind.is_symlink() || path.extension().and_then(|x| x.to_str()) != Some("jsonl")
                    || !path.file_stem().and_then(|id| id.to_str()).is_some_and(valid_session_id) { continue; }
                let Ok(modified) = entry.metadata().and_then(|m| m.modified()) else { continue; };
                if now.duration_since(modified).unwrap_or(Duration::MAX) <= Duration::from_secs(QUESTION_RETENTION_SECONDS) { candidates.push((modified, path)); }
            }
        }
    }
    candidates.sort_unstable_by(|a, b| b.0.cmp(&a.0).then_with(|| a.1.cmp(&b.1))); candidates.truncate(DISCOVERY_CANDIDATE_LIMIT);
    append_observed_claude(&mut candidates, root, observed, now);
    candidates.sort_unstable_by(|a, b| b.0.cmp(&a.0).then_with(|| a.1.cmp(&b.1)));
    let watch_root = include_watch_files.then(|| fs::canonicalize(root).ok()).flatten();
    unique_activity_rows(candidates.into_iter().filter_map(|(_, path)| {
        let mut row = inspect_claude(&path, now)?;
        let verified = verified_tool_anchor(&path, &row, anchors);
        row["toolAnchorMarker"] = json!(verified.map(|value| value.0));
        row["toolAnchorOffset"] = json!(verified.map(|value| value.1));
        add_session_watch_file(&mut row, &path, watch_root.as_deref());
        Some(row)
    }), DISCOVERY_CANDIDATE_LIMIT + OBSERVED_EXTRA_LIMIT)
}
fn inspect(path: &Path) -> Option<Value> {
    let file = File::open(path).ok()?;
    let metadata = file.metadata().ok()?;
    let size = metadata.len();
    let age = metadata.modified().ok().and_then(|t| SystemTime::now().duration_since(t).ok());
    let recently_modified = age.map(|age| age <= Duration::from_secs(30)).unwrap_or(false);
    let mut head = BufReader::new(file.try_clone().ok()?);
    let mut first = Vec::new();
    (&mut head).take(512 * 1024).read_until(b'\n', &mut first).ok()?;
    let meta: Value = serde_json::from_slice(&first).ok()?;
    let mut row = activity(&meta, transcript_tail(file, size, summarize_large_codex_record)?, recently_modified)?;
    row["transcriptIdentity"] = json!(transcript_identity(&metadata));
    row["transcriptLength"] = json!(size);
    row["_transcriptModifiedMs"] = json!(transcript_modified_ms(&metadata));
    if let Some(age) = age { row["ageSeconds"] = json!(age.as_secs()); }
    Some(row)
}
fn observed_candidate(root: &Path, path: &Path, now: SystemTime) -> Option<(SystemTime, PathBuf)> {
    if !path.is_absolute() || path.extension().and_then(|value| value.to_str()) != Some("jsonl") { return None; }
    let metadata = fs::symlink_metadata(path).ok()?;
    if !metadata.file_type().is_file() { return None; }
    let canonical_root = fs::canonicalize(root).ok()?;
    let canonical_path = fs::canonicalize(path).ok()?;
    if !canonical_path.starts_with(&canonical_root) { return None; }
    let modified = metadata.modified().ok()?;
    if now.duration_since(modified).ok()? > Duration::from_secs(QUESTION_RETENTION_SECONDS) { return None; }
    Some((modified, canonical_path))
}

// The index can locate an old conversation resumed before FSEvents starts.
// shortcut: the Codex index schema is private; retain filesystem discovery when it changes.
fn indexed_session_paths(codex_home: &Path) -> Vec<String> {
    let database = fs::read_dir(codex_home).ok().into_iter().flatten().flatten().filter_map(|entry| {
        if !entry.file_type().ok()?.is_file() { return None; }
        let name = entry.file_name();
        let version = name.to_str()?.strip_prefix("state_")?.strip_suffix(".sqlite")?.parse::<u32>().ok()?;
        Some((version, entry.path()))
    }).max_by_key(|(version, _)| *version).map(|(_, path)| path);
    let Some(database) = database else { return vec![]; };
    let mut command = std::process::Command::new("/usr/bin/sqlite3");
    command.args(["-batch", "-readonly", "-cmd", ".timeout 100"]).arg(database)
        .arg("SELECT rollout_path FROM threads WHERE length(rollout_path) BETWEEN 1 AND 2048 AND instr(rollout_path,char(0))=0 AND instr(rollout_path,char(10))=0 AND instr(rollout_path,char(13))=0 ORDER BY updated_at DESC LIMIT 64;");
    let Some(bytes) = bounded_index_output(&mut command, Duration::from_secs(2)) else { return vec![]; };
    let Ok(text) = String::from_utf8(bytes) else { return vec![]; };
    text.lines().filter(|path| !path.chars().any(char::is_control)).map(str::to_owned).collect()
}

fn bounded_index_output(command: &mut std::process::Command, timeout: Duration) -> Option<Vec<u8>> {
    let mut child = command.stdin(std::process::Stdio::null()).stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::null()).spawn().ok()?;
    let Some(stdout) = child.stdout.take() else { let _ = child.kill(); let _ = child.wait(); return None; };
    let (sender, reader) = std::sync::mpsc::sync_channel(1);
    std::thread::spawn(move || {
        let mut bytes = Vec::new();
        let result = stdout.take(600_001).read_to_end(&mut bytes).map(|_| bytes);
        let _ = sender.send(result);
    });
    let deadline = std::time::Instant::now() + timeout;
    let status = loop {
        match child.try_wait() {
            Ok(Some(status)) => break Some(status),
            Ok(None) if std::time::Instant::now() < deadline => std::thread::sleep(Duration::from_millis(10)),
            _ => { let _ = child.kill(); let _ = child.wait(); break None; }
        }
    };
    if !status.map(|value| value.success()).unwrap_or(false) { return None; }
    // A child of the query process can keep its output pipe open after exit.
    let bytes = reader.recv_timeout(deadline.saturating_duration_since(std::time::Instant::now())).ok()?.ok()?;
    if bytes.len() > 600_000 { return None; }
    Some(bytes)
}

pub fn recent() -> Result<Value, String> { recent_with_observed(&[]) }

pub fn recent_with_observed(observed: &[String]) -> Result<Value, String> {
    recent_with_anchors(observed, &[], false, false)
}
fn add_session_watch_file(row: &mut Value, path: &Path, root: Option<&Path>) {
    if let Some(root) = root {
        if let Some(relative) = fs::canonicalize(path).ok().and_then(|path| path.strip_prefix(root).ok()?.to_str().map(str::to_owned)) {
            row["watchFile"] = json!(relative);
        }
    }
}

pub fn recent_with_anchors(observed: &[String], anchors: &[Value], watch_codex_files: bool,
                           watch_claude_files: bool) -> Result<Value, String> {
    let codex_home = if let Some(path) = std::env::var_os("CODEX_HOME") { PathBuf::from(path) } else { PathBuf::from(std::env::var_os("HOME").ok_or("사용자 폴더를 찾을 수 없습니다")?).join(".codex") };
    let root = codex_home.join("sessions");
    let mut candidates = Vec::new();
    for year in recent_directories(&root, 2) { for month in recent_directories(&year, 2) { for day in recent_directories(&month, 3) {
        if let Ok(entries) = fs::read_dir(day) { for entry in entries.flatten() {
            let Ok(kind) = entry.file_type() else { continue }; if !kind.is_file() || kind.is_symlink() || entry.path().extension().and_then(|x| x.to_str()) != Some("jsonl") { continue; }
            let Ok(modified) = entry.metadata().and_then(|m| m.modified()) else { continue };
            if SystemTime::now().duration_since(modified).unwrap_or(Duration::MAX) <= Duration::from_secs(QUESTION_RETENTION_SECONDS) { candidates.push((modified, entry.path())); }
        }}
    }}}
    // Bound filesystem comparisons while leaving room for unreadable candidates.
    candidates.sort_unstable_by(|a, b| b.0.cmp(&a.0).then_with(|| a.1.cmp(&b.1))); candidates.truncate(DISCOVERY_CANDIDATE_LIMIT);
    let now = SystemTime::now();
    let indexed = indexed_session_paths(&codex_home);
    let mut known: BTreeSet<PathBuf> = candidates.iter().filter_map(|(_, path)| fs::canonicalize(path).ok()).collect();
    let initial = candidates.len();
    for path in observed.iter().take(64).chain(indexed.iter()).filter(|path| path.len() <= 4096) {
        if candidates.len() >= initial + OBSERVED_EXTRA_LIMIT { break; }
        let Some(candidate) = observed_candidate(&root, Path::new(path), now) else { continue; };
        if known.insert(candidate.1.clone()) { candidates.push(candidate); }
    }
    candidates.sort_unstable_by(|a, b| b.0.cmp(&a.0).then_with(|| a.1.cmp(&b.1)));
    let watch_root = watch_codex_files.then(|| fs::canonicalize(&root).ok()).flatten();
    let mut rows = unique_activity_rows(candidates.into_iter().filter_map(|(_, path)| {
        let mut row = inspect(&path)?;
        let verified = verified_tool_anchor(&path, &row, anchors);
        row["toolAnchorMarker"] = json!(verified.map(|value| value.0));
        row["toolAnchorOffset"] = json!(verified.map(|value| value.1));
        add_session_watch_file(&mut row, &path, watch_root.as_deref());
        Some(row)
    }), DISCOVERY_CANDIDATE_LIMIT + OBSERVED_EXTRA_LIMIT);
    if let (Some(home), Ok(now)) = (std::env::var_os("HOME"), SystemTime::now().duration_since(SystemTime::UNIX_EPOCH)) {
        let now_ms = now.as_millis().min(u64::MAX as u128) as u64;
        let root = PathBuf::from(&home).join("Library/Application Support/Rium Notch/agent-sessions");
        let legacy = PathBuf::from(&home).join("Library/Application Support/NotchPilot/codex-sessions");
        let claude = std::env::var_os("CLAUDE_CONFIG_DIR").map(PathBuf::from).unwrap_or_else(|| PathBuf::from(home).join(".claude"));
        rows.extend(recent_claude_with_anchors(&claude.join("projects"), SystemTime::UNIX_EPOCH + now,
                                              observed, anchors, watch_claude_files));
        let roots = [root.as_path(), legacy.as_path()];
        overlay_hook_status(&mut rows, &roots, now_ms);
        overlay_stalled(&mut rows, &roots, now_ms);
        rows.retain(retain_observed_row);
        append_hook_only_activity(&mut rows, &roots, now_ms);
    }
    overlay_desktop_activity(&mut rows, crate::desktop_client::activity());
    retain_visible_activity(&mut rows);
    for row in &mut rows {
        if let Some(row) = row.as_object_mut() { row.remove("_transcriptModifiedMs"); }
    }
    Ok(Value::Array(rows))
}

fn retain_observed_row(row: &Value) -> bool {
    let age = row.get("ageSeconds").and_then(Value::as_u64).unwrap_or(0);
    if age <= 600 { return true; }
    match row.get("state").and_then(Value::as_str) {
        Some("응답 지연 추정") => true,
        Some("질문 대기" | "질문 대기 감지") => age <= QUESTION_RETENTION_SECONDS,
        _ => false,
    }
}

fn activity_priority(row: &Value) -> u8 {
    let state = row.get("state").and_then(Value::as_str).unwrap_or("");
    if state.starts_with("승인 대기") { 0 }
    else if state.starts_with("질문 대기") || state.starts_with("입력 대기") { 1 }
    else if state == "실패" { 2 }
    else if state == "응답 지연 추정" { 3 }
    else if agent_work_is_live(state) { 4 }
    else { 5 }
}

fn retain_visible_activity(rows: &mut Vec<Value>) {
    rows.sort_by_key(activity_priority);
    let (mut codex, mut claude) = (0, 0);
    rows.retain(|row| {
        if !retain_observed_row(row) { return false; }
        let count = match row.get("source").and_then(Value::as_str) {
            Some("codex") => &mut codex,
            Some("claude") => &mut claude,
            _ => return false,
        };
        if *count >= 20 { return false; }
        *count += 1;
        true
    });
}

fn overlay_desktop_activity(rows: &mut Vec<Value>, desktop: Vec<Value>) {
    fn priority(state: &str) -> Option<u8> {
        match state {
            "승인 대기 감지" => Some(0),
            "질문 대기 감지" => Some(1),
            "작업 중" => Some(2),
            "최근 활동" => Some(3),
            _ => None,
        }
    }
    let mut selected: Vec<(&str, &str, u8, &Value)> = Vec::new();
    for entry in &desktop {
        let (Some(id), Some(state)) = (entry.get("id").and_then(Value::as_str), entry.get("state").and_then(Value::as_str)) else { continue; };
        let Some(rank) = priority(state).filter(|_| valid_session_id(id)) else { continue; };
        if let Some(previous) = selected.iter_mut().find(|previous| previous.0 == id) {
            if rank < previous.2 { *previous = (id, state, rank, entry); }
        } else {
            selected.push((id, state, rank, entry));
        }
    }
    for (id, state, rank, entry) in selected {
        if let Some(row) = rows.iter_mut().find(|row| row.get("source").and_then(Value::as_str) == Some("codex") && row.get("id").and_then(Value::as_str) == Some(id)) {
            let previous = row["state"].as_str().unwrap_or("");
            let was_running = agent_work_is_live(previous);
            if rank >= 2 && activity_priority(row) < 2 { continue; }
            if rank == 3 && !was_running && previous != "응답 지연 추정" { continue; }
            if rank == 2 {
                row["ageSeconds"] = json!(0);
                if was_running { continue; }
            }
            row["state"] = json!(state);
            row["toolRunning"] = json!(false);
            row["activity"] = json!("");
        } else if rank < 3 {
            let project = entry.get("project").and_then(Value::as_str).unwrap_or("Codex");
            rows.push(json!({"id":id,"source":"codex","project":project,"state":state,"activity":"","activities":[],"toolRunning":false,"pendingQuestions":[]}));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn expired_rows_do_not_consume_the_visible_session_limit() {
        let mut rows: Vec<_> = (0..20).map(|i| json!({"id":i.to_string(),"source":"codex","state":"완료","ageSeconds":601})).collect();
        rows.push(json!({"id":"waiting","source":"codex","state":"질문 대기","ageSeconds":900}));
        retain_visible_activity(&mut rows);
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0]["id"], "waiting");
        let mut live: Vec<_> = (0..21).map(|i| json!({"id":format!("live-{i}"),"source":"codex","state":"작업 중","ageSeconds":1})).collect();
        live.push(json!({"id":"claude","source":"claude","state":"작업 중","ageSeconds":1}));
        retain_visible_activity(&mut live);
        assert_eq!(live.len(), 21);
        assert!(!live.iter().any(|row| row["id"] == "live-20"));
        assert!(live.iter().any(|row| row["id"] == "claude"));
    }

    #[test]
    fn attention_survives_the_visible_session_limit() {
        let mut rows: Vec<_> = (0..20).map(|i| json!({"id":format!("live-{i}"),"source":"codex","state":"작업 중","ageSeconds":1})).collect();
        rows.push(json!({"id":"question","source":"codex","state":"질문 대기","ageSeconds":900}));
        rows.push(json!({"id":"approval","source":"codex","state":"승인 대기 감지","ageSeconds":2}));
        retain_visible_activity(&mut rows);
        assert_eq!(rows.len(), 20);
        assert_eq!(rows[0]["id"], "approval");
        assert_eq!(rows[1]["id"], "question");
        assert!(!rows.iter().any(|row| row["id"] == "live-19"));
        assert!(rows.iter().any(|row| row["id"] == "live-0"));
    }

    #[test]
    fn recent_completions_cannot_displace_merged_active_work() {
        let codex = "01234567-89ab-cdef-0123-456789abcdef";
        let approval = "fedcba98-7654-3210-fedc-ba9876543210";
        let mut rows = Vec::new();
        for source in ["codex", "claude"] {
            rows.extend((0..20).map(|i| json!({"id":format!("finished-{i}"),"source":source,"state":"완료"})));
        }
        rows.push(json!({"id":codex,"source":"codex","state":"최근 활동","messageMarker":42}));
        rows.push(json!({"id":"claude-live","source":"claude","state":"도구 실행 중"}));
        rows.push(json!({"id":"failed","source":"claude","state":"실패"}));
        rows.push(json!({"id":"stalled","source":"claude","state":"응답 지연 추정"}));
        overlay_desktop_activity(&mut rows, vec![json!({"id":codex,"state":"작업 중"}),
                                                json!({"id":approval,"state":"승인 대기 감지"})]);
        retain_visible_activity(&mut rows);
        assert_eq!(rows[0]["id"], approval);
        assert_eq!(rows[1]["id"], "failed");
        assert_eq!(rows[2]["id"], "stalled");
        assert_eq!(rows[3]["id"], codex);
        assert_eq!(rows[3]["messageMarker"], 42);
        assert_eq!(rows[4]["id"], "claude-live");
        for source in ["codex", "claude"] {
            assert_eq!(rows.iter().filter(|row| row["source"] == source).count(), 20);
        }
    }

    #[test]
    fn approval_precedes_newer_questions_and_running_hooks() {
        let mut rows = vec![
            (30, json!({"id":"question","state":"질문 대기 감지"})),
            (50, json!({"id":"working","state":"작업 중"})),
            (10, json!({"id":"approval","state":"승인 대기 감지"})),
        ];
        sort_hook_candidates(&mut rows);
        assert_eq!(rows[0].1["id"], "approval");
        assert_eq!(rows[1].1["id"], "question");
        assert_eq!(rows[2].1["id"], "working");
    }

    #[test]
    fn duplicate_transcripts_do_not_hide_other_sessions() {
        let rows = vec![
            json!({"source":"codex","id":"a","state":"new"}),
            json!({"source":"codex","id":"a","state":"old"}),
            json!({"source":"claude","id":"a","state":"different provider"}),
            json!({"source":"codex","id":"b","state":"next"}),
        ];
        let result = unique_activity_rows(rows.into_iter(), 3);
        assert_eq!(result.len(), 3);
        assert_eq!(result[0]["state"], "new");
        assert_eq!(result[1]["source"], "claude");
        assert_eq!(result[2]["id"], "b");
    }

    #[test]
    fn a_reused_pid_is_distinguished_from_an_unknown_process() {
        let record = json!({"pid":1234,"pidStartSec":100,"pidStartUsec":10});
        assert!(!recorded_start_differs(&record, Some((100, 10))));
        assert!(recorded_start_differs(&record, Some((101, 10))));
        assert!(recorded_start_differs(&record, Some((100, 11))));
        assert!(!recorded_start_differs(&record, None));
        assert!(!recorded_start_differs(&json!({"pid":1234}), Some((101, 10))));
        assert!(!recorded_start_differs(&json!({"pidStartSec":100,"pidStartUsec":1000000}), Some((101, 10))));
    }
    #[test]
    fn observed_session_ids_match_control_bridge_format() {
        assert!(valid_session_id("01234567-89ab-cdef-0123-456789abcdef"));
        assert!(valid_session_id("01234567-89AB-CDEF-0123-456789ABCDEF"));
        assert!(!valid_session_id("------------------------------------"));
        assert!(!valid_session_id("0123456789abcdef0123456789abcdefabcd"));
        assert!(!valid_session_id("0123456-789ab-cdef-0123-456789abcdef"));
        assert!(!valid_session_id("01234567-89ab-cdef-0123-456789abcdeg"));
    }
    #[test]
    fn snapshot_expiry_uses_monotonic_elapsed_time() {
        assert!(!snapshot_expired(10.0, 54.9));
        assert!(snapshot_expired(10.0, 55.0));
        assert!(!snapshot_expired(10.0, 9.0));
        assert!(!snapshot_expired(f64::NAN, 100.0));
    }
    #[test]
    fn expired_hook_attention_requires_a_live_matching_waiter() {
        let id = "01234567-89ab-cdef-0123-456789abcdef";
        let approval = json!({"state":"active","eventName":"PermissionRequest","updatedAt":100_000,
                              "awaitingPermission":true,"awaitingQuestion":false});
        assert_eq!(live_hook_state_with(&approval, id, 120_000, |_, _, _| panic!("fresh hook should not probe")), Some("승인 대기 감지"));
        assert_eq!(live_hook_state_with(&approval, id, 140_000, |session, codex, question| {
            session == id && codex && !question
        }), Some("승인 대기 감지"));
        assert_eq!(live_hook_state_with(&approval, id, 140_000, |_, _, _| false), None);
        assert_eq!(live_hook_state_with(&approval, id, 161_000, |_, _, _| true), None);
        let question = json!({"state":"active","eventName":"PermissionRequest","updatedAt":100_000,
                              "awaitingPermission":false,"awaitingQuestion":true});
        assert_eq!(live_hook_state_with(&question, &format!("claude-{id}"), 140_000, |session, codex, question| {
            session == id && !codex && question
        }), Some("질문 대기 감지"));
        assert_eq!(live_hook_state_with(&question, "../bad", 140_000, |_, _, _| true), None);
    }

    #[test]
    fn duplicate_codex_message_forms_keep_first_marker_without_exposing_text() {
        let meta = json!({"type":"session_meta","payload":{"id":"01234567-89ab-cdef-0123-456789abcdef","cwd":"/tmp/example"}});
        let event = json!({"type":"event_msg","_rium_offset":10,"payload":{"type":"agent_message","message":"private message"}});
        let response = json!({"type":"response_item","_rium_offset":20,"payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"private message"}]}});
        let first = activity(&meta, vec![event.clone()].into_iter(), true).unwrap();
        let both = activity(&meta, vec![event.clone(), response.clone()].into_iter(), true).unwrap();
        assert_eq!(first["messageMarker"], 10);
        assert_eq!(both["messageMarker"], first["messageMarker"]);
        assert_eq!(both["messageAliases"], json!([20]));
        let tail_only = activity(&meta, vec![response.clone()].into_iter(), true).unwrap();
        assert_eq!(tail_only["messageMarker"], 20);
        assert_eq!(tail_only["messageAliases"], json!([]));
        assert!(!both.to_string().contains("private message"));
        let mut second_event = event.clone(); second_event["_rium_offset"] = json!(30);
        let repeated = activity(&meta, vec![event.clone(), second_event].into_iter(), true).unwrap();
        assert_eq!(repeated["messageMarker"], 30);
        assert_eq!(repeated["messageAliases"], json!([]));
        let tool = json!({"type":"response_item","_rium_offset":15,"payload":{"type":"function_call","name":"Read"}});
        let separate = activity(&meta, vec![event, tool, response].into_iter(), true).unwrap();
        assert_eq!(separate["messageMarker"], 20);
    }
    #[test]
    fn observed_session_candidate_cannot_escape_the_session_root() {
        use std::os::unix::fs::symlink;
        let base = std::env::temp_dir().join(format!("rium-observed-session-{}", std::process::id()));
        let _ = fs::remove_dir_all(&base);
        let root = base.join("sessions");
        fs::create_dir_all(root.join("2020/01/01")).unwrap();
        let old = root.join("2020/01/01/old.jsonl");
        let outside = base.join("outside.jsonl");
        fs::write(&old, b"{}\n").unwrap(); fs::write(&outside, b"{}\n").unwrap();
        let linked = root.join("linked.jsonl");
        symlink(&outside, &linked).unwrap();
        let now = SystemTime::now();
        assert!(observed_candidate(&root, &old, now).is_some());
        assert!(observed_candidate(&root, &outside, now).is_none());
        assert!(observed_candidate(&root, &linked, now).is_none());
        assert!(observed_candidate(&root, Path::new("relative.jsonl"), now).is_none());
        fs::remove_dir_all(base).unwrap();
    }
    #[test]
    fn index_discovers_old_session_without_trusting_outside_paths() {
        let base = std::env::temp_dir().join(format!("rium-indexed-session-{}", std::process::id()));
        let _ = fs::remove_dir_all(&base);
        let root = base.join("sessions");
        fs::create_dir_all(root.join("2020/01/01")).unwrap();
        let session = root.join("2020/01/01/old.jsonl");
        let outside = base.join("outside.jsonl");
        fs::write(&session, b"{}\n").unwrap();
        fs::write(&outside, b"{}\n").unwrap();
        let quote = |path: &Path| path.to_string_lossy().replace('\'', "''");
        let sql = format!("CREATE TABLE threads (rollout_path TEXT, updated_at INTEGER); INSERT INTO threads VALUES ('{}', 2), ('{}', 1);", quote(&session), quote(&outside));
        let status = std::process::Command::new("/usr/bin/sqlite3").arg(base.join("state_5.sqlite")).arg(sql).status().unwrap();
        assert!(status.success());
        let paths = indexed_session_paths(&base);
        assert_eq!(paths.len(), 2);
        let valid: Vec<_> = paths.iter().filter_map(|path| observed_candidate(&root, Path::new(path), SystemTime::now())).collect();
        assert_eq!(valid.len(), 1);
        assert_eq!(valid[0].1, fs::canonicalize(&session).unwrap());
        fs::write(base.join("state_6.sqlite"), b"invalid").unwrap();
        assert!(indexed_session_paths(&base).is_empty());
        fs::remove_dir_all(base).unwrap();
    }
    #[test]
    fn index_query_stops_waiting_for_a_stalled_child() {
        let mut command = std::process::Command::new("/bin/sleep");
        command.arg("5");
        assert!(bounded_index_output(&mut command, Duration::from_millis(50)).is_none());
    }
    #[test]
    fn index_query_does_not_wait_for_inherited_output_pipe() {
        let mut command = std::process::Command::new("/bin/sh");
        command.args(["-c", "sleep 1 & printf ready"]);
        assert!(bounded_index_output(&mut command, Duration::from_millis(100)).is_none());
    }
    #[test]
    fn pending_question_survives_normal_activity_expiry_but_is_bounded() {
        assert!(retain_observed_row(&json!({"state":"질문 대기","ageSeconds":601})));
        assert!(retain_observed_row(&json!({"state":"질문 대기 감지","ageSeconds":QUESTION_RETENTION_SECONDS})));
        assert!(!retain_observed_row(&json!({"state":"질문 대기","ageSeconds":QUESTION_RETENTION_SECONDS + 1})));
        assert!(!retain_observed_row(&json!({"state":"완료","ageSeconds":601})));
        assert!(retain_observed_row(&json!({"state":"응답 지연 추정","ageSeconds":601})));
    }
    #[test]
    fn alternate_async_tool_name_remains_pending_without_unsafe_reply() {
        let mut questions = AsyncQuestions::default();
        questions.consume(&json!({"type":"response_item","payload":{"type":"function_call",
            "name":"request-user-input-async","call_id":"call-1",
            "arguments":{"questions":[{"title":"선택"}]}}}));
        assert_eq!(questions.pending.len(), 1);
        assert!(questions.visible().is_empty());
        questions.consume(&json!({"type":"event_msg","payload":{"type":"turn_aborted"}}));
        assert!(questions.pending.is_empty());
    }
    #[test]
    fn asynchronous_questions_follow_arrival_order_and_remove_only_the_resolved_call() {
        let mut questions = AsyncQuestions::default();
        let call = |id: &str, title: &str| json!({"type":"response_item","payload":{"type":"function_call",
            "name":"request_user_input_async","call_id":id,"arguments":{"questions":[{"title":title}]}}});
        questions.consume(&call("z-first", "먼저"));
        questions.consume(&call("a-second", "나중"));
        questions.consume(&call("z-first", "중복"));
        let visible = questions.visible();
        assert_eq!(visible.len(), 2);
        assert_eq!(visible[0]["title"], "먼저");
        assert_eq!(visible[1]["title"], "나중");
        questions.consume(&json!({"type":"response_item","payload":{"type":"function_call_output",
            "call_id":"z-first","output":{"accepted":false}}}));
        assert_eq!(questions.visible().len(), 1);
        assert_eq!(questions.visible()[0]["title"], "나중");
        questions.consume(&call("z-first", "다시"));
        assert_eq!(questions.visible()[0]["title"], "나중");
        assert_eq!(questions.visible()[1]["title"], "다시");
        questions.consume(&json!({"type":"event_msg","payload":{"type":"turn_aborted"}}));
        assert!(questions.order.is_empty() && questions.visible().is_empty());
    }
    #[test]
    fn session_end_retires_only_older_live_rows_for_the_matching_provider() {
        let root = std::env::temp_dir().join(format!("rium-session-end-{}", std::process::id()));
        fs::create_dir(&root).unwrap();
        let id = "01234567-89ab-cdef-0123-456789abcdef";
        let claude_id = format!("claude-{id}");
        let write_hook = |key: &str, hook_id: &str, event: &str| {
            let value = json!({"sessionId":hook_id,"state":"stopped","eventName":event,"updatedAt":100_000});
            fs::write(root.join(format!("{key}.json")), value.to_string()).unwrap();
        };
        let fixture = |key: &str, source: &str, state: &str, modified: Option<u64>| {
            json!({"id":key,"source":source,"state":state,"toolRunning":true,"activity":"파일 확인",
                   "pendingQuestions":[{"id":"fixture"}],"_transcriptModifiedMs":modified})
        };
        write_hook(id, id, "SessionEnd");
        write_hook(&claude_id, id, "SessionEnd");
        let mut rows = [
            fixture(id, "codex", "작업 중", Some(99_999)),
            fixture(&claude_id, "claude", "질문 대기 감지", Some(99_999)),
            fixture(id, "codex", "작업 중", Some(100_000)),
            fixture(&claude_id, "claude", "활동 감지", Some(100_001)),
            fixture(&claude_id, "claude", "완료", Some(99_999)),
            fixture(id, "claude", "질문 대기", Some(99_999)),
            fixture(id, "codex", "승인 대기", None),
            fixture(&claude_id, "claude", "응답 지연 추정", Some(99_999)),
        ];
        overlay_hook_status(&mut rows, &[root.as_path()], 101_000);
        for index in [0, 1, 7] {
            assert_eq!(rows[index]["state"], "최근 활동");
            assert_eq!(rows[index]["toolRunning"], false);
            assert_eq!(rows[index]["activity"], "");
            assert_eq!(rows[index]["pendingQuestions"], json!([]));
        }
        assert_eq!(rows[2]["state"], "작업 중");
        assert_eq!(rows[3]["state"], "활동 감지");
        assert_eq!(rows[4]["state"], "완료");
        assert_eq!(rows[5]["state"], "질문 대기");
        assert_eq!(rows[6]["state"], "승인 대기");

        write_hook(&claude_id, id, "Stop");
        write_hook(id, "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", "SessionEnd");
        let mut unaffected = [
            fixture(&claude_id, "claude", "활동 감지", Some(99_999)),
            fixture(id, "codex", "승인 대기", Some(99_999)),
        ];
        overlay_hook_status(&mut unaffected, &[root.as_path()], 101_000);
        assert_eq!(unaffected[0]["state"], "활동 감지");
        assert_eq!(unaffected[1]["state"], "승인 대기");
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn stale_routine_hook_does_not_override_newer_transcript() {
        let root = std::env::temp_dir().join(format!("rium-agent-hook-stale-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir(&root).unwrap();
        let id = "01234567-89ab-cdef-0123-456789abcdef";
        let write = |pending| fs::write(root.join(format!("{id}.json")), serde_json::to_vec(&json!({
            "sessionId":id,"state":"active","eventName":"PreToolUse",
            "awaitingPermission":pending,"updatedAt":100_000
        })).unwrap()).unwrap();
        let fixture = || vec![json!({"id":id,"state":"작업 중","toolRunning":false,"ageSeconds":1})];
        write(false);
        let mut newer = fixture();
        overlay_hook_status(&mut newer, &[root.as_path()], 110_000);
        assert_eq!(newer[0]["state"], "작업 중");
        assert_eq!(newer[0]["toolRunning"], false);
        let mut older = vec![json!({"id":id,"state":"작업 중","toolRunning":false,"ageSeconds":20})];
        overlay_hook_status(&mut older, &[root.as_path()], 110_000);
        assert_eq!(older[0]["state"], "도구 실행 감지");
        assert_eq!(older[0]["toolRunning"], true);
        write(true);
        let mut waiting = fixture();
        overlay_hook_status(&mut waiting, &[root.as_path()], 110_000);
        assert_eq!(waiting[0]["state"], "승인 대기 감지");
        fs::write(root.join(format!("{id}.json")), serde_json::to_vec(&json!({
            "sessionId":id,"state":"active","eventName":"PermissionRequest",
            "awaitingQuestion":true,"updatedAt":100_000
        })).unwrap()).unwrap();
        let mut questioning = vec![json!({"id":id,"state":"작업 중","activity":"파일 수정","toolRunning":true,"ageSeconds":20})];
        overlay_hook_status(&mut questioning, &[root.as_path()], 110_000);
        assert_eq!(questioning[0]["state"], "질문 대기 감지");
        assert_eq!(questioning[0]["activity"], "");
        assert_eq!(questioning[0]["toolRunning"], false);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn hook_only_rows_require_fresh_active_records_and_do_not_disclose_paths() {
        let root = std::env::temp_dir().join(format!("rium-agent-hook-only-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir(&root).unwrap();
        let id = "01234567-89ab-cdef-0123-456789abcdef";
        let record = json!({"sessionId":id,"state":"active","eventName":"PreToolUse","updatedAt":100_000,
            "cwd":"/private/secret/project", "tool":"secret"});
        fs::write(root.join(format!("{id}.json")), serde_json::to_vec(&record).unwrap()).unwrap();
        let mut rows = Vec::new();
        append_hook_only_activity(&mut rows, &[root.as_path()], 100_001);
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0]["state"], "도구 실행 감지");
        assert_eq!(rows[0]["project"], "project");
        assert!(!rows[0].to_string().contains("secret"));
        append_hook_only_activity(&mut rows, &[root.as_path()], 100_001);
        assert_eq!(rows.len(), 1);
        rows.clear();
        append_hook_only_activity(&mut rows, &[root.as_path()], 131_000);
        assert!(rows.is_empty());
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn newest_hook_wins_and_conflicting_timestamps_are_not_guessed() {
        let root = std::env::temp_dir().join(format!("rium-agent-hook-order-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        let first = root.join("first"); let second = root.join("second");
        fs::create_dir_all(&first).unwrap(); fs::create_dir_all(&second).unwrap();
        let id = "01234567-89ab-cdef-0123-456789abcdef";
        let write = |dir: &Path, state: &str, stamp: u64| {
            fs::write(dir.join(format!("{id}.json")), serde_json::to_vec(&json!({"sessionId":id,"state":state,"eventName":"PreToolUse","updatedAt":stamp})).unwrap()).unwrap();
        };
        let roots = [first.as_path(), second.as_path()];
        write(&first, "active", 100_000); write(&second, "stopped", 101_000);
        let mut rows = vec![json!({"id":id,"state":"최근 활동","ageSeconds":610})];
        overlay_hook_status(&mut rows, &roots, 710_000); overlay_stalled(&mut rows, &roots, 710_000);
        assert_eq!(rows[0]["state"], "최근 활동");
        write(&second, "active", 705_000);
        overlay_hook_status(&mut rows, &roots, 710_000);
        assert_eq!(rows[0]["state"], "도구 실행 감지");
        write(&first, "stopped", 705_000);
        assert!(latest_hook_record(&roots, id, 710_000).is_none());
        write(&first, "active", 711_000);
        assert!(latest_hook_record(&roots, id, 710_000).is_none());
        fs::remove_dir_all(root).unwrap();
    }
    #[test]
    fn stalled_requires_old_matching_unblocked_hook_and_old_transcript() {
        let root = std::env::temp_dir().join(format!("rium-agent-stalled-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir(&root).unwrap();
        let id = "01234567-89ab-cdef-0123-456789abcdef";
        let path = root.join(format!("{id}.json"));
        let write = |pending: bool, stamp: u64| {
            fs::write(&path, serde_json::to_vec(&json!({"sessionId":id,"state":"active","eventName":"PreToolUse", "awaitingPermission":pending,"updatedAt":stamp})).unwrap()).unwrap();
        };
        let fixture = || vec![json!({"id":id,"state":"최근 활동","ageSeconds":610,"toolRunning":true})];
        write(false, 100_000);
        let mut rows = fixture(); overlay_stalled(&mut rows, &[root.as_path()], 710_000);
        assert_eq!(rows[0]["state"], "응답 지연 추정");
        assert_eq!(rows[0]["toolRunning"], false);
        write(true, 100_000);
        let mut rows = fixture(); overlay_stalled(&mut rows, &[root.as_path()], 710_000);
        assert_eq!(rows[0]["state"], "최근 활동");
        assert_eq!(rows[0]["toolRunning"], true);
        write(false, 700_000);
        let mut rows = fixture(); overlay_stalled(&mut rows, &[root.as_path()], 710_000);
        assert_eq!(rows[0]["state"], "최근 활동");
        write(false, 100_000);
        let mut rows = vec![json!({"id":id,"state":"최근 활동","ageSeconds":20})];
        overlay_stalled(&mut rows, &[root.as_path()], 710_000);
        assert_eq!(rows[0]["state"], "최근 활동");
        fs::remove_dir_all(root).unwrap();
    }
    #[test]
    fn stalled_detects_only_proven_absence_at_event_specific_deadlines() {
        let root = std::env::temp_dir().join(format!("rium-agent-stalled-death-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir(&root).unwrap();
        let id = "01234567-89ab-cdef-0123-456789abcdef";
        let path = root.join(format!("{id}.json"));
        let write = |event: &str, pending: bool| fs::write(&path, serde_json::to_vec(&json!({
            "sessionId":id,"state":"active","eventName":event,"awaitingPermission":pending,"updatedAt":100_000,"pid":1234
        })).unwrap()).unwrap();
        let row = |seconds| vec![json!({"id":id,"state":"최근 활동","ageSeconds":seconds})];
        write("PostToolUse", false);
        let mut rows = row(90); overlay_stalled_with(&mut rows, &[&root], 190_000, |record| record.get("pid").and_then(Value::as_u64) == Some(1234));
        assert_eq!(rows[0]["state"], "응답 지연 추정");
        let mut rows = row(90); overlay_stalled_with(&mut rows, &[&root], 190_000, |_| false);
        assert_eq!(rows[0]["state"], "최근 활동");
        write("PreToolUse", false);
        let mut rows = row(299); overlay_stalled_with(&mut rows, &[&root], 399_000, |_| true);
        assert_eq!(rows[0]["state"], "최근 활동");
        let mut rows = row(300); overlay_stalled_with(&mut rows, &[&root], 400_000, |_| true);
        assert_eq!(rows[0]["state"], "응답 지연 추정");
        write("PostToolUse", true);
        let mut rows = row(100); overlay_stalled_with(&mut rows, &[&root], 200_000, |_| true);
        assert_eq!(rows[0]["state"], "최근 활동");
        fs::remove_dir_all(root).unwrap();
    }
    #[test]
    fn fresh_prompt_supersedes_only_provably_older_terminal_or_question() {
        let root = std::env::temp_dir().join(format!("rium-agent-new-prompt-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir(&root).unwrap();
        let id = "01234567-89ab-cdef-0123-456789abcdef";
        let path = root.join(format!("{id}.json"));
        fs::write(&path, serde_json::to_vec(&json!({"sessionId":id,"state":"active","eventName":"UserPromptSubmit","updatedAt":100_000})).unwrap()).unwrap();
        let mut old = vec![json!({"id":id,"state":"완료","ageSeconds":30,"pendingQuestions":[{"id":"old"}]})];
        overlay_hook_status(&mut old, &[root.as_path()], 101_000);
        assert_eq!(old[0]["state"], "작업 중");
        assert_eq!(old[0]["ageSeconds"], 1);
        assert!(old[0]["pendingQuestions"].as_array().unwrap().is_empty());
        let mut ambiguous = vec![json!({"id":id,"state":"완료","ageSeconds":1})];
        overlay_hook_status(&mut ambiguous, &[root.as_path()], 101_000);
        assert_eq!(ambiguous[0]["state"], "완료");
        let mut pending = vec![json!({"id":id,"state":"질문 대기","ageSeconds":30,"pendingQuestions":[{"id":"old"}]})];
        overlay_hook_status(&mut pending, &[root.as_path()], 101_000);
        assert_eq!(pending[0]["state"], "작업 중");
        assert!(pending[0]["pendingQuestions"].as_array().unwrap().is_empty());
        fs::remove_dir_all(root).unwrap();
    }
    #[test]
    fn desktop_pending_overlays_only_the_matching_codex_session() {
        let id = "01234567-89ab-cdef-0123-456789abcdef";
        let mut rows = vec![json!({"id":id,"source":"codex","project":"작업","state":"완료","toolRunning":true,"activity":"파일 수정"}),
                            json!({"id":format!("claude-{id}"),"source":"claude","project":"작업","state":"완료"})];
        overlay_desktop_activity(&mut rows, vec![json!({"id":id,"state":"승인 대기 감지","project":"작업"})]);
        assert_eq!(rows[0]["state"], "승인 대기 감지");
        assert_eq!(rows[0]["toolRunning"], false);
        assert_eq!(rows[0]["activity"], "");
        assert_eq!(rows[1]["state"], "완료");
        overlay_desktop_activity(&mut rows, vec![json!({"id":"bad","state":"승인 대기 감지"})]);
        assert_eq!(rows.len(), 2);
        let approval = json!({"id":id,"state":"승인 대기 감지"});
        let question = json!({"id":id,"state":"질문 대기 감지"});
        for pending in [vec![approval.clone(), question.clone()], vec![question.clone(), approval.clone()]] {
            let mut combined = Vec::new();
            overlay_desktop_activity(&mut combined, pending);
            assert_eq!(combined.len(), 1);
            assert_eq!(combined[0]["state"], "승인 대기 감지");
            assert_eq!(combined[0]["toolRunning"], false);
        }
    }
    #[test]
    fn desktop_work_reconciles_only_codex_without_hiding_attention_or_inventing_completion() {
        let id = "01234567-89ab-cdef-0123-456789abcdef";
        let state = |value| json!({"id":id,"project":"작업","state":value});
        let mut rows = Vec::new();
        overlay_desktop_activity(&mut rows, vec![state("최근 활동")]);
        assert!(rows.is_empty());
        overlay_desktop_activity(&mut rows, vec![state("작업 중")]);
        assert_eq!(rows[0]["state"], "작업 중");
        rows[0]["toolRunning"] = json!(true);
        rows[0]["activity"] = json!("파일 확인");
        rows.push(json!({"id":id,"source":"claude","state":"작업 중"}));
        overlay_desktop_activity(&mut rows, vec![state("최근 활동")]);
        assert_eq!(rows[0]["state"], "최근 활동");
        assert_eq!(rows[0]["toolRunning"], false);
        assert_eq!(rows[1]["state"], "작업 중");
        rows[0]["state"] = json!("질문 대기");
        overlay_desktop_activity(&mut rows, vec![state("작업 중")]);
        assert_eq!(rows[0]["state"], "질문 대기");
        overlay_desktop_activity(&mut rows, vec![state("작업 중"), state("승인 대기 감지"), state("최근 활동")]);
        assert_eq!(rows[0]["state"], "승인 대기 감지");
        rows[0]["state"] = json!("완료");
        overlay_desktop_activity(&mut rows, vec![state("최근 활동")]);
        assert_eq!(rows[0]["state"], "완료");
    }

    #[test]
    fn unsupported_multiselect_stays_pending_without_offering_single_answers() {
        let mut questions = AsyncQuestions::default();
        questions.consume(&json!({"type":"response_item","payload":{"type":"function_call",
            "name":"request_user_input_async","call_id":"call-1","arguments":{"questions":[
                {"title":"단일 선택","options":["하나"]},
                {"title":"복수 선택","options":["둘"],"multiSelect":true}
            ]}}}));
        assert_eq!(questions.pending.len(), 1);
        let visible = questions.visible();
        assert_eq!(visible.len(), 1);
        assert_eq!(visible[0]["title"], "단일 선택");
    }
    #[test]
    fn active_tool_pairs_calls_and_results_without_emitting_ids() {
        let id = "01234567-89ab-cdef-0123-456789abcdef";
        let meta = json!({"type":"session_meta","payload":{"id":id}});
        let start = json!({"type":"event_msg","payload":{"type":"task_started"}});
        let call = |id: &str| json!({"type":"response_item","payload":{"type":"function_call","call_id":id,"name":"exec_command","arguments":"secret"}});
        let result = |id: &str| json!({"type":"response_item","payload":{"type":"function_call_output","call_id":id,"output":"secret"}});
        let active = activity(&meta, vec![start.clone(), call("private-a"), call("private-b"), result("private-a")].into_iter(), true).unwrap();
        assert_eq!(active["toolRunning"], true);
        assert!(!active.to_string().contains("private-a") && !active.to_string().contains("secret"));
        let done = activity(&meta, vec![start.clone(), call("private-a"), result("private-a")].into_iter(), true).unwrap();
        assert_eq!(done["toolRunning"], false);
        let stale = activity(&meta, vec![start, call("private-a")].into_iter(), false).unwrap();
        assert_eq!(stale["toolRunning"], false);
        let claude_call = json!({"type":"assistant","sessionId":id,"message":{"content":[{"type":"tool_use","id":"private-a","name":"Read"}]}});
        let claude_result = json!({"type":"user","sessionId":id,"message":{"content":[{"type":"tool_result","tool_use_id":"private-a"}]}});
        assert_eq!(claude_activity(id, vec![claude_call.clone()].into_iter(), true).unwrap()["toolRunning"], true);
        assert_eq!(claude_activity(id, vec![claude_call, claude_result].into_iter(), true).unwrap()["toolRunning"], false);
    }
    #[test]
    fn oversized_codex_records_keep_recent_lifecycle_and_pair_results() {
        use std::io::Write;
        let path = std::env::temp_dir().join(format!("rium-codex-large-record-{}.jsonl", std::process::id()));
        let prefix = [
            json!({"type":"session_meta","payload":{"id":"01234567-89ab-cdef-0123-456789abcdef"}}),
            json!({"type":"event_msg","payload":{"type":"task_started"}}),
            json!({"type":"response_item","payload":{"type":"function_call","name":"exec_command","call_id":"fixture-tool"}}),
        ];
        let write = |record: Value, suffix: Option<Value>| {
            let mut file = File::create(&path).unwrap();
            for record in prefix.iter().chain(std::iter::once(&record)).chain(suffix.iter()) {
                writeln!(file, "{record}").unwrap();
            }
        };
        write(json!({"type":"compacted","payload":{"replacement_history":["x".repeat(5 * 1024 * 1024)]}}), None);
        let compacted = inspect(&path).unwrap();
        assert_eq!(compacted["state"], "작업 중");
        assert_eq!(compacted["toolRunning"], true);

        let output = json!({"type":"response_item","payload":{"type":"function_call_output",
            "call_id":"fixture-tool","output":"private ".repeat(TAIL_BYTES as usize / 2)}});
        write(output.clone(), None);
        let completed_tool = inspect(&path).unwrap();
        assert_eq!(completed_tool["state"], "작업 중");
        assert_eq!(completed_tool["toolRunning"], false);
        assert!(!completed_tool.to_string().contains("fixture-tool"));

        write(output, Some(json!({"type":"event_msg","payload":{"type":"turn_aborted"}})));
        let aborted = inspect(&path).unwrap();
        assert_eq!(aborted["state"], "중단됨");
        assert_eq!(aborted["toolRunning"], false);
        fs::remove_file(path).unwrap();
    }

    #[test]
    fn oversized_claude_records_keep_activity_and_apply_main_session_completion() {
        use std::io::Write;
        let root = std::env::temp_dir().join(format!("rium-claude-large-record-{}", std::process::id()));
        fs::create_dir_all(&root).unwrap();
        let id = "01234567-89ab-cdef-0123-456789abcdef";
        let path = root.join(format!("{id}.jsonl"));
        let prefix = [
            json!({"type":"user","sessionId":id,"cwd":"/tmp/fixture","message":{"content":"start"}}),
            json!({"type":"assistant","sessionId":id,"message":{"content":[{"type":"tool_use","id":"fixture-tool","name":"Read"}]}}),
        ];
        let write = |record: Value| {
            let mut file = File::create(&path).unwrap();
            for record in prefix.iter().chain(std::iter::once(&record)) {
                writeln!(file, "{record}").unwrap();
            }
            inspect_claude(&path, SystemTime::now()).unwrap()
        };
        let large = "private".repeat(TAIL_BYTES as usize / 2);
        let result = write(json!({"type":"user","sessionId":id,
            "message":{"content":[{"type":"tool_result","tool_use_id":"fixture-tool","content":large}]}}));
        assert_eq!(result["state"], "활동 감지");
        assert_eq!(result["toolRunning"], false);
        assert!(!result.to_string().contains("fixture-tool") && !result.to_string().contains("private"));

        let mut completion = json!({"type":"assistant","sessionId":id,"message":{"id":"fixture-done",
            "stop_reason":"end_turn","content":[{"type":"text","text":large}]}});
        let completed = write(completion.clone());
        assert_eq!(completed["state"], "완료");
        assert_eq!(completed["toolRunning"], false);
        assert_eq!(completed["messageMarker"].as_u64(), message_id_marker("fixture-done"));

        completion["isSidechain"] = json!(true);
        let child = write(completion);
        assert_eq!(child["state"], "활동 감지");
        assert_eq!(child["toolRunning"], true);
        let failed = write(json!({"type":"assistant","sessionId":id,"isApiErrorMessage":true,"details":large}));
        assert_eq!(failed["state"], "실패");
        assert_eq!(failed["toolRunning"], false);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn strips_transcript_and_ignores_internal_subagents() {
        let meta = json!({"type":"session_meta","payload":{"id":"01234567-89ab-cdef-0123-456789abcdef","cwd":"/tmp/demo"}});
        let events = vec![json!({"type":"event_msg","payload":{"type":"task_started"}}), json!({"type":"response_item","payload":{"type":"function_call","name":"exec_command","arguments":"sensitive test"}})];
        let result = activity(&meta, events.into_iter(), true).unwrap();
        assert_eq!(result["project"], "demo"); assert_eq!(result["state"], "작업 중"); assert!(!result.to_string().contains("sensitive test"));
        let child = json!({"type":"session_meta","payload":{"id":"01234567-89ab-cdef-0123-456789abcdef","source":{"subagent":{}}}});
        assert!(activity(&child, vec![].into_iter(), true).is_none());
    }
    #[test]
    fn recent_bounded_tail_is_inferred_without_overriding_completion() {
        let meta = json!({"type":"session_meta","payload":{"id":"01234567-89ab-cdef-0123-456789abcdef"}});
        let call = json!({"type":"response_item","payload":{"type":"function_call","name":"exec_command"}});
        let done = json!({"type":"event_msg","payload":{"type":"task_complete"}});
        assert_eq!(activity(&meta, vec![call.clone()].into_iter(), true).unwrap()["state"], "활동 감지");
        assert_eq!(activity(&meta, vec![call.clone()].into_iter(), false).unwrap()["state"], "최근 활동");
        assert_eq!(activity(&meta, vec![call, done].into_iter(), true).unwrap()["state"], "완료");
        let start = json!({"type":"event_msg","payload":{"type":"task_started"}});
        let stale = activity(&meta, vec![start].into_iter(), false).unwrap();
        assert_eq!(stale["state"], "최근 활동"); assert_eq!(stale["activity"], "");
    }
    #[test]
    fn recent_activity_history_is_bounded_and_never_exposes_arguments() {
        let meta = json!({"type":"session_meta","payload":{"id":"01234567-89ab-cdef-0123-456789abcdef"}});
        let names = ["exec_command", "web_search", "apply_patch", "other_tool"];
        let calls = names.into_iter().map(|name| json!({"type":"response_item","payload":{"type":"function_call","name":name,"arguments":"private text"}}));
        let row = activity(&meta, calls, true).unwrap();
        assert_eq!(row["activities"], json!(["웹 검색", "파일 수정", "도구 사용"]));
        assert!(!row.to_string().contains("private text"));
        let reset = vec![json!({"type":"response_item","payload":{"type":"function_call","name":"exec_command"}}), json!({"type":"event_msg","payload":{"type":"task_started"}})];
        assert!(activity(&meta, reset.into_iter(), true).unwrap()["activities"].as_array().unwrap().is_empty());
    }
    #[test]
    fn tool_event_markers_distinguish_repeated_calls_without_exposing_inputs() {
        let meta = json!({"type":"session_meta","payload":{"id":"01234567-89ab-cdef-0123-456789abcdef"}});
        let calls = (0..20).map(|i| json!({"type":"response_item","_rium_offset":i * 100,
            "payload":{"type":"function_call","name":"exec_command","call_id":format!("call-{i}"),"arguments":"private"}}));
        let row = activity(&meta, calls, true).unwrap();
        let events = row["toolEvents"].as_array().unwrap();
        assert_eq!(events.len(), 16);
        assert_ne!(events[14]["marker"], events[15]["marker"]);
        assert_eq!(events[15]["activity"], "작업 실행");
        assert_eq!(events[15]["kind"], 2);
        assert_eq!(events[15]["offset"], 1900);
        assert!(!row.to_string().contains("private"));
        let id = "01234567-89ab-cdef-0123-456789abcdef";
        let event = json!({"type":"assistant","sessionId":id,"message":{"content":[
            {"type":"tool_use","id":"same-call","name":"Read","input":"private"}]}});
        let repeated_chunk = claude_activity(id, vec![event.clone(), event].into_iter(), true).unwrap();
        assert_eq!(repeated_chunk["toolEvents"].as_array().unwrap().len(), 1);
        assert_eq!(repeated_chunk["toolEvents"][0]["kind"], 0);
        assert!(!repeated_chunk.to_string().contains("private"));
    }

    #[test]
    fn verifies_previous_tool_before_accepting_a_nonoverlapping_tail() {
        let root = std::env::temp_dir().join(format!("rium-tool-anchor-{}", std::process::id()));
        fs::create_dir_all(&root).unwrap();
        let path = root.join("events.jsonl");
        let id = "01234567-89ab-cdef-0123-456789abcdef";
        let record = |call| format!("{}\n", json!({"type":"response_item","payload":{"type":"function_call","call_id":call,"name":"exec_command","arguments":"private"}}));
        fs::write(&path, record("call-a")).unwrap();
        let identity = transcript_identity(&fs::metadata(&path).unwrap()).unwrap();
        let row = json!({"id":id,"source":"codex","transcriptIdentity":identity.clone()});
        let marker = message_id_marker("call-a").unwrap();
        let anchor = json!({"id":id,"source":"codex","identity":identity,"offset":0,"marker":marker});
        assert_eq!(verified_tool_anchor(&path, &row, &[anchor.clone()]), Some((marker, 0)));
        fs::write(&path, record("call-b")).unwrap();
        assert_eq!(verified_tool_anchor(&path, &row, &[anchor.clone()]), None);
        let mut wrong = anchor; wrong["source"] = json!("claude");
        assert_eq!(verified_tool_anchor(&path, &row, &[wrong]), None);
        let claude = json!({"type":"assistant","sessionId":id,"message":{"content":[{"type":"tool_use","id":"tool-a","name":"Read","input":"private"}]}});
        fs::write(&path, format!("{claude}\n")).unwrap();
        let claude_row = json!({"id":format!("claude-{id}"),"source":"claude","transcriptIdentity":identity.clone()});
        let claude_marker = message_id_marker("tool-a").unwrap();
        let claude_anchor = json!({"id":format!("claude-{id}"),"source":"claude","identity":identity,"offset":0,"marker":claude_marker});
        assert_eq!(verified_tool_anchor(&path, &claude_row, &[claude_anchor.clone()]), Some((claude_marker, 0)));
        fs::write(&path, claude.to_string()).unwrap();
        assert_eq!(verified_tool_anchor(&path, &claude_row, &[claude_anchor]), None);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn token_kind_uses_only_known_tool_categories() {
        assert_eq!(tool_token_kind("WebFetch"), 0);
        assert_eq!(tool_token_kind("apply_patch"), 1);
        assert_eq!(tool_token_kind("functions.apply_patch"), 1);
        assert_eq!(tool_token_kind("mcp__functions__apply_patch"), 1);
        assert_eq!(tool_token_kind("exec_command"), 2);
        assert_eq!(tool_token_kind("functions.exec_command"), 2);
        assert_eq!(tool_token_kind("functions.write_stdin"), 2);
        assert_eq!(tool_token_kind("mcp__functions__exec_command"), 2);
        assert_eq!(tool_token_kind("mcp__functions__write_stdin"), 2);
        assert_eq!(tool_activity("functions.write_stdin"), "작업 실행");
        assert_eq!(tool_activity("mcp__functions__write_stdin"), "작업 실행");
        assert_eq!(tool_token_kind("functions.exec"), 4);
        assert_eq!(tool_activity("functions.exec"), "도구 사용");
        assert_eq!(tool_token_kind("WebSearch"), 3);
        assert_eq!(tool_token_kind("mcp__private_extension"), 4);
    }
    #[test]
    fn fresh_matching_hook_adds_only_bounded_status_and_respects_completion() {
        let root = std::env::temp_dir().join(format!("rium-agent-hook-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir(&root).unwrap();
        let id = "01234567-89ab-cdef-0123-456789abcdef";
        let path = root.join(format!("{id}.json"));
        let write = |state: &str, pending: bool, stamp: u64, session: &str| {
            fs::write(&path, serde_json::to_vec(&json!({"sessionId":session,"state":state,"awaitingPermission":pending,"eventName":"PreToolUse","updatedAt":stamp,"chat":"private fixture","nonce":"private fixture"})).unwrap()).unwrap();
        };
        write("active", true, 100_000, id);
        let mut rows = vec![json!({"id":id,"state":"활동 감지","activity":"도구 사용"})];
        overlay_hook_status(&mut rows, &[root.as_path()], 101_000);
        assert_eq!(rows[0]["state"], "승인 대기 감지");
        assert!(!rows[0].to_string().contains("private fixture"));
        rows[0]["state"] = json!("완료"); overlay_hook_status(&mut rows, &[root.as_path()], 101_000);
        assert_eq!(rows[0]["state"], "완료");
        assert_eq!(fresh_hook_state(&root, id, 131_000), None);
        assert_eq!(fresh_hook_state(&root, id, 99_000), None);
        write("active", false, 100_000, id);
        assert_eq!(fresh_hook_state(&root, id, 100_000), Some("도구 실행 감지"));
        write("stopped", true, 100_000, id);
        assert_eq!(fresh_hook_state(&root, id, 100_000), None);
        write("active", true, 100_000, "other");
        assert_eq!(fresh_hook_state(&root, id, 100_000), None);
        assert_eq!(fresh_hook_state(&root, "../bad", 100_000), None);
        let claude_id = format!("claude-{id}");
        fs::write(root.join(format!("{claude_id}.json")), serde_json::to_vec(&json!({"sessionId":id,"state":"active","awaitingPermission":false,"eventName":"PreToolUse","updatedAt":100_000})).unwrap()).unwrap();
        let mut claude_rows = vec![json!({"id":claude_id.clone(),"state":"질문 대기 감지"})];
        overlay_hook_status(&mut claude_rows, &[root.as_path()], 101_000);
        assert_eq!(claude_rows[0]["state"], "질문 대기 감지");
        assert_eq!(fresh_hook_state(&root, &claude_id, 101_000), Some("도구 실행 감지"));
        fs::remove_dir_all(root).unwrap();
    }
    #[test]
    fn claude_sessions_report_only_matching_main_session_metadata() {
        let id = "01234567-89ab-cdef-0123-456789abcdef";
        let user = json!({"type":"user","sessionId":id,"cwd":"/tmp/demo","message":{"content":"private prompt"}});
        let child = json!({"type":"assistant","sessionId":id,"isSidechain":true,"message":{"stop_reason":"end_turn"}});
        let tool = json!({"type":"assistant","sessionId":id,"message":{"stop_reason":"tool_use","content":[{"type":"tool_use","input":"private command"}]}});
        let done = json!({"type":"assistant","sessionId":id,"message":{"stop_reason":"end_turn","content":"private answer"}});
        let item = claude_activity(id, vec![user.clone(), child, tool].into_iter(), true).unwrap();
        assert_eq!(item["source"], "claude"); assert_eq!(item["project"], "demo"); assert_eq!(item["state"], "활동 감지");
        assert!(!item.to_string().contains("private"));
        assert_eq!(claude_activity(id, vec![user, done].into_iter(), true).unwrap()["state"], "완료");
        assert!(claude_activity(id, vec![json!({"type":"user","sessionId":"different"})].into_iter(), true).is_none());
        assert!(claude_activity("../bad", std::iter::empty(), true).is_none());
    }
    #[test]
    fn claude_project_scan_finds_a_session_without_returning_conversation() {
        use std::os::unix::fs::symlink;
        let root = std::env::temp_dir().join(format!("rium-claude-scan-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        let project = root.join("fixture-project"); fs::create_dir_all(&project).unwrap();
        let id = "01234567-89ab-cdef-0123-456789abcdef";
        let record = json!({"type":"assistant","sessionId":id,"cwd":"/tmp/fixture","message":{"stop_reason":"tool_use","content":"private fixture"}});
        let session = project.join(format!("{id}.jsonl"));
        fs::write(&session, format!("{record}\n")).unwrap();
        File::options().write(true).open(&session).unwrap().set_times(
            fs::FileTimes::new().set_modified(SystemTime::now() - Duration::from_secs(5))
        ).unwrap();
        for index in 0..24 { fs::write(project.join(format!("other-{index}.jsonl")), b"{}\n").unwrap(); }
        let nested = project.join("subagents"); fs::create_dir_all(&nested).unwrap();
        let child = nested.join(format!("{id}.jsonl")); fs::write(&child, format!("{record}\n")).unwrap();
        let linked = project.join("11111111-1111-1111-1111-111111111111.jsonl"); symlink(&session, &linked).unwrap();
        let observed = [session.to_string_lossy().into_owned(), child.to_string_lossy().into_owned(), linked.to_string_lossy().into_owned()];
        let mut candidates = Vec::new();
        append_observed_claude(&mut candidates, &root, &observed, SystemTime::now());
        assert_eq!(candidates.len(), 1);
        append_observed_claude(&mut candidates, &root, &observed, SystemTime::now());
        assert_eq!(candidates.len(), 1);
        let mut crowded: Vec<_> = (0..DISCOVERY_CANDIDATE_LIMIT)
            .map(|index| (SystemTime::now(), root.join(format!("nonexistent-{index}")))).collect();
        append_observed_claude(&mut crowded, &root, &observed, SystemTime::now());
        assert_eq!(crowded.len(), DISCOVERY_CANDIDATE_LIMIT + 1);
        assert_eq!(crowded.last().unwrap().1, fs::canonicalize(&session).unwrap());
        let rows = recent_claude(&root, SystemTime::now(), &[]);
        assert_eq!(rows.len(), 1); assert_eq!(rows[0]["state"], "활동 감지");
        assert_eq!(rows[0]["id"], format!("claude-{id}"));
        assert!(!rows[0].to_string().contains("private fixture"));
        assert!(rows[0].get("watchFile").is_none());
        let watching = recent_claude_with_anchors(&root, SystemTime::now(), &observed, &[], true);
        assert_eq!(watching.len(), 1);
        assert_eq!(watching[0]["watchFile"], format!("fixture-project/{id}.jsonl"));
        assert_eq!(recent_claude(&root, SystemTime::now(), &observed).len(), 1);
        for index in 0..24 {
            fs::write(project.join(format!("00000000-0000-0000-0000-{index:012x}.jsonl")), b"{}\n").unwrap();
        }
        let rows = recent_claude(&root, SystemTime::now(), &[]);
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0]["id"], format!("claude-{id}"));
        fs::remove_dir_all(root).unwrap();
    }
    #[test]
    fn claude_tool_activity_is_bounded_and_does_not_expose_tool_input() {
        let id = "01234567-89ab-cdef-0123-456789abcdef";
        let user = json!({"type":"user","sessionId":id,"message":{"content":"private prompt"}});
        let tools = json!({"type":"assistant","sessionId":id,"message":{"stop_reason":"tool_use","content":[
            {"type":"tool_use","name":"Read","input":{"file_path":"private path"}},
            {"type":"tool_use","name":"Bash","input":{"command":"private command"}},
            {"type":"tool_use","name":"Edit","input":{"new_string":"private text"}},
            {"type":"tool_use","name":"WebSearch","input":{"query":"private query"}}
        ]}});
        let row = claude_activity(id, vec![user.clone(), tools.clone()].into_iter(), true).unwrap();
        assert_eq!(row["activities"], json!(["작업 실행", "파일 수정", "웹 검색"]));
        assert!(!row.to_string().contains("private"));
        let row = claude_activity(id, vec![user.clone(), tools, user].into_iter(), true).unwrap();
        assert_eq!(row["activities"], json!([]));
        assert_eq!(tool_activity("Read"), "파일 확인");
        assert_eq!(tool_activity("mcp__functions__apply_patch"), "파일 수정");
        assert_eq!(tool_activity("WebFetch"), "웹 확인");
        assert_eq!(tool_activity("Grep"), "검색");
        assert_eq!(tool_activity("ToolSearch"), "검색");
        assert_eq!(tool_activity("local_shell"), "작업 실행");
    }
    #[test]
    fn claude_questions_follow_the_matching_tool_result() {
        let id = "01234567-89ab-cdef-0123-456789abcdef";
        let ask = json!({"type":"assistant","sessionId":id,"message":{"stop_reason":"tool_use","content":[
            {"type":"tool_use","id":"call-a","name":"AskUserQuestion","input":{"questions":[
                {"question":"어느 방식인가요?","options":[{"label":"첫 번째"},{"label":"두 번째"}]},
                {"question":"비밀 값","isSecret":true}]}} ,
            {"type":"tool_use","id":"call-b","name":"AskUserQuestion","input":{"questions":[{"question":"계속할까요?","options":[]}]}}
        ]}});
        let answered = json!({"type":"user","sessionId":id,"message":{"content":[{"type":"tool_result","tool_use_id":"call-a","content":"private answer"}]}});
        let row = claude_activity(id, vec![ask.clone()].into_iter(), true).unwrap();
        assert_eq!(row["state"], "질문 대기 감지");
        assert_eq!(row["pendingQuestions"].as_array().unwrap().len(), 2);
        assert_eq!(row["pendingQuestions"][0]["options"], json!(["첫 번째", "두 번째"]));
        assert!(!row.to_string().contains("비밀 값"));
        let row = claude_activity(id, vec![ask.clone(), answered.clone()].into_iter(), true).unwrap();
        assert_eq!(row["pendingQuestions"].as_array().unwrap().len(), 1);
        assert_eq!(row["pendingQuestions"][0]["title"], "계속할까요?");
        assert!(!row.to_string().contains("private answer"));
        let finished = json!({"type":"assistant","sessionId":id,"message":{"stop_reason":"end_turn","content":[]}});
        let row = claude_activity(id, vec![ask, answered, finished].into_iter(), true).unwrap();
        assert_eq!(row["state"], "완료");
        assert_eq!(row["pendingQuestions"], json!([]));
    }
}
