//! Read and answer requests through the exact owning Desktop bridge.
//! No request payload is written to disk or exposed to another user.
use serde_json::{json, Value};
use std::fs::{self, File};
use std::io::{BufRead, BufReader, Read, Write};
use std::os::unix::fs::{FileTypeExt, MetadataExt};
use std::os::unix::io::AsRawFd;
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};
use std::collections::HashMap;
use std::sync::mpsc;
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

extern "C" { fn geteuid() -> u32; fn getpeereid(fd: i32, uid: *mut u32, gid: *mut u32) -> i32; }
const REQUEST_LIMIT: usize = 65_536;
const RESPONSE_LIMIT: u64 = 2_000_000;

fn valid_token(value: &str) -> bool {
    value.len() == 32 && value.bytes().all(|byte| byte.is_ascii_hexdigit() && !byte.is_ascii_uppercase())
}
fn valid_session(value: &str) -> bool {
    value.len() == 36 && value.bytes().enumerate().all(|(i, c)| if [8, 13, 18, 23].contains(&i) { c == b'-' } else { c.is_ascii_hexdigit() })
}

fn registration_pid(root: &Path, token: &str) -> Option<u32> {
    if !valid_token(token) { return None; }
    let record = root.join(format!("desktop-{token}.json"));
    let meta = fs::symlink_metadata(&record).ok()?;
    if !meta.file_type().is_file() || meta.uid() != unsafe { geteuid() } || meta.mode() & 0o077 != 0 || meta.len() > 4096 { return None; }
    let file = File::open(&record).ok()?;
    let opened = file.metadata().ok()?;
    if meta.dev() != opened.dev() || meta.ino() != opened.ino() { return None; }
    let record: Value = serde_json::from_reader(file.take(4097)).ok()?;
    let latest = fs::symlink_metadata(root.join(format!("desktop-{token}.json"))).ok()?;
    if latest.dev() != opened.dev() || latest.ino() != opened.ino() || latest.len() != opened.len()
        || latest.mtime() != opened.mtime() || latest.mtime_nsec() != opened.mtime_nsec() { return None; }
    registration_record_pid(&record, token, SystemTime::now().duration_since(UNIX_EPOCH).ok()?.as_millis())
}

fn registration_record_pid(record: &Value, token: &str, now_ms: u128) -> Option<u32> {
    if !valid_token(token) || record.get("token")?.as_str()? != token { return None; }
    let pid = u32::try_from(record.get("pid")?.as_u64()?).ok().filter(|pid| *pid > 1 && *pid <= i32::MAX as u32)?;
    let created = record.get("createdAt")?.as_u64()?;
    if u128::from(created) > now_ms { return None; }
    Some(pid)
}

fn connect(token: &str) -> Option<UnixStream> {
    let root = crate::agent_hook::registry()?;
    registration_pid(&root, token)?;
    let directory = PathBuf::from(format!("/tmp/rium-desktop-{token}"));
    let meta = fs::symlink_metadata(&directory).ok()?;
    if !meta.file_type().is_dir() || meta.uid() != unsafe { geteuid() } || meta.mode() & 0o077 != 0 { return None; }
    let socket = directory.join("socket");
    let meta = fs::symlink_metadata(&socket).ok()?;
    if !meta.file_type().is_socket() || meta.uid() != unsafe { geteuid() } { return None; }
    let stream = UnixStream::connect(socket).ok()?;
    let (mut uid, mut gid) = (0, 0);
    if unsafe { getpeereid(stream.as_raw_fd(), &mut uid, &mut gid) } != 0 || uid != unsafe { geteuid() } { return None; }
    stream.set_read_timeout(Some(Duration::from_secs(8))).ok()?;
    stream.set_write_timeout(Some(Duration::from_secs(2))).ok()?;
    Some(stream)
}

fn request(token: &str, mut value: Value) -> Option<Value> {
    value.as_object_mut()?.insert("token".into(), json!(token));
    let data = serde_json::to_vec(&value).ok()?;
    if data.len() > REQUEST_LIMIT { return None; }
    let mut stream = connect(token)?;
    stream.write_all(&data).and_then(|_| stream.write_all(b"\n")).ok()?;
    let mut bytes = Vec::new();
    let count = BufReader::new(&stream).take(RESPONSE_LIMIT + 1).read_until(b'\n', &mut bytes).ok()?;
    if count == 0 || bytes.len() as u64 > RESPONSE_LIMIT || bytes.last() != Some(&b'\n') { return None; }
    serde_json::from_slice(&bytes).ok()
}

struct Match { token: String, workspace: PathBuf }
fn endpoint_tokens() -> Vec<String> {
    let Some(root) = crate::agent_hook::registry() else { return Vec::new(); };
    let Ok(entries) = fs::read_dir(&root) else { return Vec::new(); };
    let mut tokens: Vec<String> = entries.flatten().take(512).filter_map(|entry| {
        let name = entry.file_name();
        let name = name.to_str()?;
        let token = name.strip_prefix("desktop-")?.strip_suffix(".json")?;
        if !valid_token(token) || registration_pid(&root, token).is_some_and(crate::agents::process_definitely_absent) { return None; }
        Some(token.to_owned())
    }).take(16).collect();
    tokens.sort();
    tokens
}
fn strict_endpoint_tokens() -> Result<Vec<String>, String> {
    let root = crate::agent_hook::registry().ok_or("Desktop 연결 목록을 확인할 수 없습니다")?;
    let entries = fs::read_dir(&root).map_err(|_| "Desktop 연결 목록을 읽을 수 없습니다")?;
    let mut tokens = Vec::new();
    for (index, entry) in entries.enumerate() {
        if index >= 512 { return Err("연결 목록이 너무 큽니다".into()); }
        let name = entry.map_err(|_| "Desktop 연결 목록을 읽을 수 없습니다")?.file_name();
        let Some(name) = name.to_str() else { return Err("연결 이름을 확인할 수 없습니다".into()); };
        if !name.starts_with("desktop-") { continue; }
        let token = name.strip_prefix("desktop-").and_then(|name| name.strip_suffix(".json"))
            .filter(|token| valid_token(token)).ok_or("Desktop 연결 항목을 확인할 수 없습니다")?;
        // A validated record whose owner no longer exists cannot own a live
        // bridge. Unknown PID states remain in the strict snapshot.
        if registration_pid(&root, token).is_some_and(crate::agents::process_definitely_absent) { continue; }
        tokens.push(token.to_owned());
    }
    tokens.sort();
    if tokens.len() > 16 { return Err("Desktop 연결이 너무 많습니다".into()); }
    Ok(tokens)
}

fn strict_owner_from<F>(session: &str, tokens: &[String], mut fetch: F) -> Result<Option<Match>, String>
where F: FnMut(&str) -> Option<Value> {
    let mut found: Option<Match> = None;
    for token in tokens {
        let response = fetch(token).ok_or("Desktop 연결이 응답하지 않습니다")?;
        let sessions = response.get("sessions").and_then(Value::as_array).ok_or("Desktop 세션 목록을 확인할 수 없습니다")?;
        for row in sessions {
            let id = row.get("sessionId").and_then(Value::as_str).filter(|id| valid_session(id))
                .ok_or("Desktop 세션 식별자를 확인할 수 없습니다")?;
            if id != session { continue; }
            let path = row.get("workspace").and_then(Value::as_str).map(PathBuf::from)
                .filter(|path| path.is_absolute()).ok_or("Desktop 작업 폴더를 확인할 수 없습니다")?;
            let workspace = fs::canonicalize(path).map_err(|_| "Desktop 작업 폴더를 확인할 수 없습니다")?;
            if found.is_some() { return Err("이 대화가 여러 Desktop 연결에 있습니다".into()); }
            found = Some(Match { token: token.clone(), workspace });
        }
    }
    Ok(found)
}

fn strict_resolve(session: &str) -> Result<Option<Match>, String> {
    if !valid_session(session) { return Err("Codex 대화 식별자를 확인할 수 없습니다".into()); }
    let tokens = strict_endpoint_tokens()?;
    let found = strict_owner_from(session, &tokens, |token| request(token, json!({"action":"sessions"})))?;
    if strict_endpoint_tokens()? != tokens { return Err("조회 중 Desktop 연결이 변경됐습니다".into()); }
    Ok(found)
}

/// Enumerate every advertised endpoint and reject partial or changing views.
pub fn strict_previews(session: &str) -> Result<Value, String> {
    let tokens = strict_endpoint_tokens()?;
    let found = strict_resolve(session)?;
    let requests: Vec<Value> = if let Some(found) = found {
        let response = request(&found.token, json!({"action":"previews","sessionId":session,"workspace":found.workspace}))
            .ok_or("Desktop 요청을 확인할 수 없습니다")?;
        let rows = response.get("previews").and_then(Value::as_array).ok_or("Desktop 요청 형식을 확인할 수 없습니다")?;
        rows.iter().map(|shown| json!({"connection":found.token,"workspace":found.workspace,"shown":shown})).collect()
    } else { Vec::new() };
    if strict_endpoint_tokens()? != tokens { return Err("조회 중 Desktop 연결이 변경됐습니다".into()); }
    Ok(json!({"status":"ok","requests":requests}))
}
fn resolve(session: &str) -> Result<Option<Match>, String> {
    if !valid_session(session) { return Err("Codex 대화 식별자를 확인할 수 없습니다".into()); }
    let mut found = None;
    for token in endpoint_tokens() {
        let Some(response) = request(&token, json!({"action":"sessions"})) else { continue; };
        let Some(sessions) = response.get("sessions").and_then(Value::as_array) else { continue; };
        for row in sessions {
            if row.get("sessionId").and_then(Value::as_str) != Some(session) { continue; }
            let Some(path) = row.get("workspace").and_then(Value::as_str).map(PathBuf::from).filter(|path| path.is_absolute()) else { continue; };
            let Ok(workspace) = fs::canonicalize(path) else { continue; };
            if found.is_some() { return Err("이 대화가 여러 Desktop 연결에 있어 Codex에서 직접 확인해 주세요".into()); }
            found = Some(Match { token: token.clone(), workspace });
        }
    }
    Ok(found)
}

/// Bounded status-only snapshot. A conversation reported by multiple bridges
/// is left unchanged because an owner cannot be chosen with certainty.
pub fn activity() -> Vec<Value> {
    let tokens = endpoint_tokens();
    let count = tokens.len();
    let (tx, rx) = mpsc::channel();
    for token in tokens {
        let tx = tx.clone();
        thread::spawn(move || { let _ = tx.send(request(&token, json!({"action":"activity"}))); });
    }
    drop(tx);
    let deadline = std::time::Instant::now() + Duration::from_millis(1200);
    let mut sessions: HashMap<String, (usize, Option<Value>)> = HashMap::new();
    for _ in 0..count {
        let remaining = deadline.saturating_duration_since(std::time::Instant::now());
        let Ok(response) = rx.recv_timeout(remaining) else { break; };
        let Some(response) = response else { continue; };
        let Some(rows) = response.get("sessions").and_then(Value::as_array) else { continue; };
        for row in rows.iter().take(256) {
            let Some(session) = row.get("sessionId").and_then(Value::as_str).filter(|id| valid_session(id)) else { continue; };
            let state = match row.get("pending").and_then(Value::as_str) {
                Some("approval") => Some("승인 대기 감지"),
                Some("question") => Some("질문 대기 감지"),
                _ => row.get("generating").and_then(Value::as_bool).map(|active| if active { "작업 중" } else { "최근 활동" }),
            };
            let project: String = row.get("project").and_then(Value::as_str).unwrap_or("Codex")
                .chars().filter(|c| !c.is_control()).take(80).collect();
            let value = state.map(|state| json!({"id":session,"project":if project.is_empty() { "Codex" } else { &project },"state":state}));
            let entry = sessions.entry(session.to_owned()).or_insert((0, None));
            entry.0 += 1;
            if value.is_some() { entry.1 = value; }
        }
    }
    let mut activity: Vec<Value> = sessions.into_values().filter_map(|(count, value)| if count == 1 { value } else { None }).collect();
    activity.sort_by(|a, b| a["id"].as_str().cmp(&b["id"].as_str()));
    activity
}

pub fn previews(session: &str) -> Result<Value, String> {
    let Some(found) = resolve(session)? else { return Ok(json!({"status":"unavailable","requests":[]})); };
    let response = request(&found.token, json!({"action":"previews","sessionId":session,"workspace":found.workspace}))
        .ok_or("Desktop 연결에서 요청을 읽을 수 없습니다")?;
    let previews = response.get("previews").and_then(Value::as_array).ok_or("Desktop 응답 형식을 확인할 수 없습니다")?;
    let requests: Vec<_> = previews.iter().map(|shown| json!({"connection":found.token,"workspace":found.workspace,"shown":shown})).collect();
    Ok(json!({"status":"ok","requests":requests}))
}

fn send_followup(found: Match, session: &str, text: &str, question_id: Option<&str>) -> Result<Option<Value>, String> {
    let response = request(&found.token, json!({"action":"followup","sessionId":session,"workspace":found.workspace,"text":text,"questionId":question_id}));
    let status = response.as_ref().and_then(|value| value.get("status")).and_then(Value::as_str).unwrap_or("unknown");
    match status {
        "accepted" => Ok(Some(json!({"status":"accepted"}))),
        "unavailable" if question_id.is_some() => Err("질문은 Codex에서 직접 답변해 주세요. 입력한 내용은 유지됩니다".into()),
        "unavailable" => Err("Codex 연결을 확인할 수 없습니다. 입력한 내용은 유지됩니다".into()),
        _ => Ok(Some(json!({"status":"unknown"}))),
    }
}

pub fn followup(session: &str, text: &str) -> Result<Option<Value>, String> {
    let Some(found) = strict_resolve(session)? else { return Ok(None); };
    send_followup(found, session, text, None)
}

fn question_is_pending(rows: &Value, session: &str, id: &str, question: &str, options: &Value) -> bool {
    let Some(rows) = rows.as_array() else { return false; };
    let mut matching = rows.iter().filter(|row| row.get("id").and_then(Value::as_str) == Some(session)
        && row.get("source").and_then(Value::as_str) == Some("codex"));
    let Some(row) = matching.next() else { return false; };
    if matching.next().is_some() { return false; }
    row.get("pendingQuestions").and_then(Value::as_array).is_some_and(|questions| questions.iter().any(|item|
        item.get("id").and_then(Value::as_str) == Some(id)
        && item.get("title").and_then(Value::as_str) == Some(question)
        && item.get("options") == Some(options)))
}

pub fn answer(session: &str, question_id: &str, question: &str, options: &Value, answer: &str) -> Result<Option<Value>, String> {
    let Some(found) = strict_resolve(session)? else { return Ok(None); };
    if !question_is_pending(&crate::agents::recent()?, session, question_id, question, options) {
        return Err("질문이 이미 처리됐거나 변경되었습니다. Codex에서 확인해 주세요".into());
    }
    let prompt = crate::agent_control::encode_question_reply(question_id, question, answer);
    send_followup(found, session, &prompt, Some(question_id))
}

pub fn respond(session: &str, connection: &str, workspace: &str, shown: &Value, action: &str, answer: &Value) -> Result<Value, String> {
    if !matches!(action, "approval" | "question") || !shown.is_object() { return Err("응답 내용을 확인할 수 없습니다".into()); }
    let Some(found) = strict_resolve(session)? else { return Err("Desktop 연결이 종료됐습니다".into()); };
    let supplied = fs::canonicalize(Path::new(workspace)).map_err(|_| "작업 폴더를 확인할 수 없습니다")?;
    if found.token != connection || supplied != found.workspace { return Err("대화 연결이나 작업 폴더가 변경됐습니다".into()); }
    let request_token = shown.get("token").and_then(Value::as_str).ok_or("요청 식별자를 확인할 수 없습니다")?;
    let turn = shown.get("turnId").and_then(Value::as_str).unwrap_or("");
    let mut message = json!({"action":action,"sessionId":session,"workspace":found.workspace,
                             "requestToken":request_token,"turnId":turn,"shown":shown});
    if action == "approval" {
        let decision = answer.as_str().filter(|value| matches!(*value, "allow" | "deny")).ok_or("승인 응답을 확인할 수 없습니다")?;
        message["decision"] = json!(decision);
    } else { message["answers"] = answer.clone(); }
    // Once writing starts the result can be unknown. Never retry a response.
    let response = request(&found.token, message);
    let status = response.as_ref().and_then(|value| value.get("status")).and_then(Value::as_str).unwrap_or("unknown");
    Ok(json!({"status":if matches!(status, "submitted" | "not_pending") { status } else { "unknown" }}))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn answer_requires_the_exact_still_pending_question() {
        let rows = json!([{"source":"codex","id":"s","pendingQuestions":[{"id":"q","title":"질문","options":["네"]}]}]);
        assert!(question_is_pending(&rows,"s","q","질문",&json!(["네"])));
        assert!(!question_is_pending(&rows,"s","q","다른 질문",&json!(["네"])));
        assert!(!question_is_pending(&rows,"s","q","질문",&json!(["아니오"])));
        assert!(!question_is_pending(&rows,"s","other","질문",&json!(["네"])));
    }
    #[test]
    fn reject_invalid_identity_without_connecting() {
        assert!(!valid_token("../socket"));
        assert!(!valid_session("../session"));
        assert!(resolve("../session").is_err());
    }
    #[test]
    fn registration_pid_requires_consistent_token_and_plausible_process() {
        let token = "0123456789abcdef0123456789abcdef";
        let record = json!({"token":token,"pid":42,"createdAt":100});
        assert_eq!(registration_record_pid(&record, token, 100), Some(42));
        assert_eq!(registration_record_pid(&record, token, 99), None);
        assert_eq!(registration_record_pid(&record, "ffffffffffffffffffffffffffffffff", 100), None);
        assert_eq!(registration_record_pid(&json!({"token":token,"pid":1,"createdAt":0}), token, 100), None);
        assert_eq!(registration_record_pid(&json!({"token":token,"pid":u64::MAX,"createdAt":0}), token, 100), None);
    }
    #[test]
    fn strict_owner_rejects_unresponsive_or_duplicate_connections() {
        let session = "01234567-89ab-cdef-0123-456789abcdef";
        let tokens = vec!["first".to_owned(), "second".to_owned()];
        let workspace = std::env::temp_dir().canonicalize().unwrap();
        let row = json!({"sessions":[{"sessionId":session,"workspace":workspace.to_string_lossy()}]});
        assert!(strict_owner_from(session, &tokens, |token| if token == "first" { Some(row.clone()) } else { None }).is_err());
        assert!(strict_owner_from(session, &tokens, |_| Some(row.clone())).is_err());
        let owner = strict_owner_from(session, &tokens, |token| {
            Some(if token == "first" { row.clone() } else { json!({"sessions":[]}) })
        }).unwrap().unwrap();
        assert_eq!(owner.token, "first");
        assert_eq!(owner.workspace, workspace);
    }
}
