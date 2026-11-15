//! Read-only, bounded agent session observation. No transcript content is emitted.
use serde_json::{json, Value};
use std::collections::VecDeque;
use std::fs::{self, File};
use std::io::{BufRead, BufReader, Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime};

const TAIL_BYTES: u64 = 256 * 1024;
const MAX_HOOK_BYTES: u64 = 64 * 1024;
const HOOK_FRESHNESS_MS: u64 = 30_000;
fn tool_activity(name: &str) -> &'static str {
    let name = name.to_ascii_lowercase();
    if name.contains("web") || name.contains("browser") { "웹 확인" }
    else if name.contains("apply_patch") || matches!(name.as_str(), "edit" | "write" | "multiedit") { "파일 수정" }
    else if matches!(name.as_str(), "read" | "grep" | "glob") { "파일 확인" }
    else if name.contains("exec") || name.contains("terminal") || name == "bash" { "작업 실행" }
    else { "도구 사용" }
}

fn remember_activity(actions: &mut VecDeque<&'static str>, name: &str) -> &'static str {
    let action = tool_activity(name);
    if actions.len() == 3 { actions.pop_front(); }
    actions.push_back(action);
    action
}
fn valid_session_id(id: &str) -> bool {
    id.len() == 36 && id.chars().all(|c| c.is_ascii_hexdigit() || c == '-')
}

// Glance's local Codex integration writes one status record per session.
// Read only a fresh, matching record; never expose its chat, path or nonce.
fn fresh_hook_state(root: &Path, id: &str, now_ms: u64) -> Option<&'static str> {
    if !valid_session_id(id) { return None; }
    let path = root.join(format!("{id}.json"));
    let metadata = fs::symlink_metadata(&path).ok()?;
    if !metadata.file_type().is_file() || metadata.len() > MAX_HOOK_BYTES { return None; }
    let record: Value = serde_json::from_reader(File::open(path).ok()?.take(MAX_HOOK_BYTES + 1)).ok()?;
    if record.get("sessionId")?.as_str()? != id || record.get("state")?.as_str()? != "active" { return None; }
    let updated = record.get("updatedAt")?.as_u64()?;
    if updated > now_ms || now_ms - updated > HOOK_FRESHNESS_MS { return None; }
    if record.get("awaitingPermission").and_then(Value::as_bool) == Some(true) {
        return Some("승인 대기 감지");
    }
    if record.get("eventName").and_then(Value::as_str) == Some("PreToolUse") {
        return Some("도구 실행 감지");
    }
    None
}

fn overlay_hook_status(rows: &mut [Value], root: &Path, now_ms: u64) {
    for row in rows {
        let Some(id) = row.get("id").and_then(Value::as_str) else { continue; };
        let Some(state) = fresh_hook_state(root, id, now_ms) else { continue; };
        // An explicit completion/abort from the transcript is stronger than a
        // hook record that might have arrived immediately before it.
        if matches!(row.get("state").and_then(Value::as_str), Some("완료" | "중단됨")) { continue; }
        row["state"] = json!(state);
        if state == "승인 대기 감지" { row["activity"] = json!(""); }
    }
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
fn activity(meta: &Value, lines: impl Iterator<Item = Value>, recently_modified: bool) -> Option<Value> {
    let p = meta.get("payload")?;
    if meta.get("type")?.as_str()? != "session_meta" { return None; }
    if p.get("source").and_then(Value::as_object).and_then(|s| s.get("subagent")).is_some() || p.get("thread_source").and_then(Value::as_str) == Some("guardian_review") { return None; }
    let id = p.get("id").or_else(|| p.get("session_id"))?.as_str()?;
    if !valid_session_id(id) { return None; }
    let project = p.get("cwd").and_then(Value::as_str).and_then(|s| Path::new(s).file_name()).and_then(|s| s.to_str()).unwrap_or("Codex");
    let mut state = "최근 활동"; let mut action = "";
    let mut recent_actions = VecDeque::with_capacity(3);
    for record in lines {
        let kind = record.get("type").and_then(Value::as_str).unwrap_or("");
        let payload = &record["payload"];
        let subtype = payload.get("type").and_then(Value::as_str).unwrap_or("");
        if kind == "event_msg" {
            match subtype { "task_started" => { state = "작업 중"; action = ""; recent_actions.clear(); }, "task_complete" => { state = "완료"; action = ""; }, "turn_aborted" => { state = "중단됨"; action = ""; }, _ => {} }
        } else if kind == "response_item" && matches!(subtype, "function_call" | "custom_tool_call") {
            let name = payload.get("name").and_then(Value::as_str).unwrap_or("");
            action = remember_activity(&mut recent_actions, name);
        }
    }
    // A long-running turn can start before the bounded tail. Recent tool
    // activity indicates activity, but does not prove the task's exact state.
    if state == "최근 활동" && !action.is_empty() && recently_modified { state = "활동 감지"; }
    // A missing completion can also mean the process exited or the session
    // stopped updating. Never leave an old start record marked as running.
    if state == "작업 중" && !recently_modified { state = "최근 활동"; action = ""; }
    Some(json!({"id":id,"source":"codex","project":project,"state":state,"activity":action,"activities":recent_actions}))
}

// Claude Code stores JSONL under its projects directory. Read only the tail,
// ignore child-agent records, and report activity rather than claiming that a
// recently changed transcript proves a live process or a permission request.
fn claude_activity(id: &str, lines: impl Iterator<Item = Value>, recently_modified: bool) -> Option<Value> {
    if !valid_session_id(id) { return None; }
    let mut project = String::from("Claude");
    let mut state = "최근 활동";
    let mut seen = false;
    let mut recent_actions = VecDeque::with_capacity(3);
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
            if let Some(content) = message.get("content").and_then(Value::as_array) {
                for item in content {
                    if item.get("type").and_then(Value::as_str) == Some("tool_use") {
                        if let Some(name) = item.get("name").and_then(Value::as_str) {
                            remember_activity(&mut recent_actions, name);
                        }
                    }
                }
            }
            state = if message.get("stop_reason").and_then(Value::as_str) == Some("end_turn") { "완료" }
                else if recently_modified { "활동 감지" } else { "최근 활동" };
        } else {
            let tool_result = message.get("content").and_then(Value::as_array)
                .is_some_and(|items| items.iter().any(|item| item.get("type").and_then(Value::as_str) == Some("tool_result")));
            if !tool_result { seen = true; recent_actions.clear(); state = if recently_modified { "활동 감지" } else { "최근 활동" }; }
        }
    }
    seen.then(|| json!({"id":format!("claude-{id}"),"source":"claude","project":project,"state":state,"activity":"", "activities":recent_actions}))
}

fn inspect_claude(path: &Path, now: SystemTime) -> Option<Value> {
    let id = path.file_stem()?.to_str()?;
    if !valid_session_id(id) { return None; }
    let metadata = fs::symlink_metadata(path).ok()?;
    if !metadata.file_type().is_file() { return None; }
    let age = now.duration_since(metadata.modified().ok()?).ok()?;
    if age > Duration::from_secs(600) { return None; }
    let mut file = File::open(path).ok()?;
    let offset = metadata.len().saturating_sub(TAIL_BYTES);
    file.seek(SeekFrom::Start(offset)).ok()?;
    let mut tail = BufReader::new(file.take(TAIL_BYTES));
    if offset > 0 { let mut skipped = Vec::new(); tail.read_until(b'\n', &mut skipped).ok()?; }
    let lines = tail.lines().map_while(Result::ok).filter_map(|line| serde_json::from_str::<Value>(&line).ok());
    let mut row = claude_activity(id, lines, age <= Duration::from_secs(30))?;
    row["ageSeconds"] = json!(age.as_secs());
    Some(row)
}

fn recent_claude(root: &Path, now: SystemTime) -> Vec<Value> {
    let mut candidates = Vec::new();
    if let Ok(projects) = fs::read_dir(root) {
        for project in projects.flatten().take(512) {
            let Ok(kind) = project.file_type() else { continue; };
            if !kind.is_dir() || kind.is_symlink() { continue; }
            let Ok(files) = fs::read_dir(project.path()) else { continue; };
            for entry in files.flatten().take(512) {
                let Ok(kind) = entry.file_type() else { continue; };
                let path = entry.path();
                if !kind.is_file() || kind.is_symlink() || path.extension().and_then(|x| x.to_str()) != Some("jsonl") { continue; }
                let Ok(modified) = entry.metadata().and_then(|m| m.modified()) else { continue; };
                if now.duration_since(modified).unwrap_or(Duration::MAX) <= Duration::from_secs(600) { candidates.push((modified, path)); }
            }
        }
    }
    candidates.sort_unstable_by(|a, b| b.0.cmp(&a.0)); candidates.truncate(20);
    candidates.into_iter().filter_map(|(_, path)| inspect_claude(&path, now)).collect()
}
fn inspect(path: &Path) -> Option<Value> {
    let mut file = File::open(path).ok()?;
    let metadata = file.metadata().ok()?;
    let size = metadata.len();
    let age = metadata.modified().ok().and_then(|t| SystemTime::now().duration_since(t).ok());
    let recently_modified = age.map(|age| age <= Duration::from_secs(30)).unwrap_or(false);
    let mut head = BufReader::new(file.try_clone().ok()?);
    let mut first = Vec::new();
    (&mut head).take(512 * 1024).read_until(b'\n', &mut first).ok()?;
    let meta: Value = serde_json::from_slice(&first).ok()?;
    let offset = size.saturating_sub(TAIL_BYTES); file.seek(SeekFrom::Start(offset)).ok()?;
    let mut tail = BufReader::new(file); if offset > 0 { let mut skipped = Vec::new(); tail.read_until(b'\n', &mut skipped).ok()?; }
    let lines = tail.lines().map_while(Result::ok).filter_map(|line| serde_json::from_str::<Value>(&line).ok());
    let mut row = activity(&meta, lines, recently_modified)?;
    if let Some(age) = age { row["ageSeconds"] = json!(age.as_secs()); }
    Some(row)
}
pub fn recent() -> Result<Value, String> {
    let root = if let Some(path) = std::env::var_os("CODEX_HOME") { PathBuf::from(path) } else { PathBuf::from(std::env::var_os("HOME").ok_or("사용자 폴더를 찾을 수 없습니다")?).join(".codex") }.join("sessions");
    let mut candidates = Vec::new();
    for year in recent_directories(&root, 2) { for month in recent_directories(&year, 2) { for day in recent_directories(&month, 3) {
        if let Ok(entries) = fs::read_dir(day) { for entry in entries.flatten() {
            let Ok(kind) = entry.file_type() else { continue }; if !kind.is_file() || kind.is_symlink() || entry.path().extension().and_then(|x| x.to_str()) != Some("jsonl") { continue; }
            let Ok(modified) = entry.metadata().and_then(|m| m.modified()) else { continue };
            if SystemTime::now().duration_since(modified).unwrap_or(Duration::MAX) <= Duration::from_secs(600) { candidates.push((modified, entry.path())); }
        }}
    }}}
    candidates.sort_unstable_by(|a,b| b.0.cmp(&a.0)); candidates.truncate(20);
    let mut rows: Vec<Value> = candidates.into_iter().filter_map(|(_, path)| inspect(&path)).collect();
    if let (Some(home), Ok(now)) = (std::env::var_os("HOME"), SystemTime::now().duration_since(SystemTime::UNIX_EPOCH)) {
        let root = PathBuf::from(&home).join("Library/Application Support/NotchPilot/codex-sessions");
        overlay_hook_status(&mut rows, &root, now.as_millis().min(u64::MAX as u128) as u64);
        let claude = std::env::var_os("CLAUDE_CONFIG_DIR").map(PathBuf::from).unwrap_or_else(|| PathBuf::from(home).join(".claude"));
        rows.extend(recent_claude(&claude.join("projects"), SystemTime::UNIX_EPOCH + now));
    }
    Ok(Value::Array(rows))
}

#[cfg(test)]
mod tests {
    use super::*;
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
        assert_eq!(row["activities"], json!(["웹 확인", "파일 수정", "도구 사용"]));
        assert!(!row.to_string().contains("private text"));
        let reset = vec![json!({"type":"response_item","payload":{"type":"function_call","name":"exec_command"}}), json!({"type":"event_msg","payload":{"type":"task_started"}})];
        assert!(activity(&meta, reset.into_iter(), true).unwrap()["activities"].as_array().unwrap().is_empty());
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
        overlay_hook_status(&mut rows, &root, 101_000);
        assert_eq!(rows[0]["state"], "승인 대기 감지");
        assert!(!rows[0].to_string().contains("private fixture"));
        rows[0]["state"] = json!("완료"); overlay_hook_status(&mut rows, &root, 101_000);
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
        let root = std::env::temp_dir().join(format!("rium-claude-scan-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        let project = root.join("fixture-project"); fs::create_dir_all(&project).unwrap();
        let id = "01234567-89ab-cdef-0123-456789abcdef";
        let record = json!({"type":"assistant","sessionId":id,"cwd":"/tmp/fixture","message":{"stop_reason":"tool_use","content":"private fixture"}});
        fs::write(project.join(format!("{id}.jsonl")), format!("{record}\n")).unwrap();
        let rows = recent_claude(&root, SystemTime::now());
        assert_eq!(rows.len(), 1); assert_eq!(rows[0]["state"], "활동 감지");
        assert_eq!(rows[0]["id"], format!("claude-{id}"));
        assert!(!rows[0].to_string().contains("private fixture"));
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
        assert_eq!(row["activities"], json!(["작업 실행", "파일 수정", "웹 확인"]));
        assert!(!row.to_string().contains("private"));
        let row = claude_activity(id, vec![user.clone(), tools, user].into_iter(), true).unwrap();
        assert_eq!(row["activities"], json!([]));
        assert_eq!(tool_activity("Read"), "파일 확인");
        assert_eq!(tool_activity("mcp__functions__apply_patch"), "파일 수정");
    }
}
