//! Private, short-lived rendezvous for Claude and Codex permission hooks.
//! Request details are served over a local socket, never written to the registry.
//! A timeout or any I/O error leaves Claude's own prompt in control.
use crate::agent_approval::{claude_hook_response, Decision};
use serde_json::{json, Value};
use std::fs::{self, DirBuilder, File, OpenOptions};
use std::io::{BufRead, BufReader, Read, Write};
use std::os::unix::fs::{DirBuilderExt, FileTypeExt, MetadataExt, OpenOptionsExt};
use std::os::unix::io::AsRawFd;
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

extern "C" { fn geteuid() -> u32; fn getpeereid(fd: i32, uid: *mut u32, gid: *mut u32) -> i32; }
const LIMIT: u64 = 65_536;
const WAIT: Duration = Duration::from_secs(55);
const IO_TIMEOUT: Duration = Duration::from_millis(750);
// Session records and active requests share this directory. Check well beyond
// the first few hundred entries so older session files do not hide a waiter.
pub(crate) const REGISTRY_SCAN_LIMIT: usize = 8192;

#[derive(Clone, Copy, PartialEq, Eq)]
enum Provider { Claude, Codex }
impl Provider {
    fn name(self) -> &'static str { match self { Self::Claude => "claude", Self::Codex => "codex" } }
}

fn valid_session(id: &str) -> bool {
    id.len() == 36 && id.bytes().enumerate().all(|(index, byte)| {
        if [8, 13, 18, 23].contains(&index) { byte == b'-' } else { byte.is_ascii_hexdigit() }
    })
}
fn valid_token(token: &str) -> bool { token.len() == 32 && token.bytes().all(|b| b.is_ascii_hexdigit() && !b.is_ascii_uppercase()) }
fn socket_dir(token: &str) -> Option<PathBuf> {
    valid_token(token).then(|| PathBuf::from(format!("/tmp/rium-notice-{token}")))
}
fn registry_path(root: &Path, provider: Provider, session: &str, token: &str) -> Option<PathBuf> {
    if !valid_session(session) || !valid_token(token) { return None; }
    Some(root.join(format!("approval-{}-{session}-{token}.json", provider.name())))
}
fn random_token() -> Option<String> {
    let mut bytes = [0u8; 16];
    File::open("/dev/urandom").ok()?.read_exact(&mut bytes).ok()?;
    Some(bytes.iter().map(|byte| format!("{byte:02x}")).collect())
}
fn peer_is_owner(stream: &UnixStream) -> bool {
    let (mut uid, mut gid) = (0, 0);
    unsafe { getpeereid(stream.as_raw_fd(), &mut uid, &mut gid) == 0 && uid == geteuid() }
}
fn read_message(stream: &UnixStream) -> Option<Value> {
    let mut reader = BufReader::new(stream);
    let mut bytes = Vec::new();
    let count = (&mut reader).take(LIMIT + 1).read_until(b'\n', &mut bytes).ok()?;
    if count == 0 || bytes.len() as u64 > LIMIT || bytes.last() != Some(&b'\n') { return None; }
    serde_json::from_slice(&bytes).ok()
}
fn write_message(stream: &mut UnixStream, value: &Value) -> Option<()> {
    let data = serde_json::to_vec(value).ok()?;
    if data.len() as u64 > LIMIT { return None; }
    stream.write_all(&data).and_then(|_| stream.write_all(b"\n")).ok()
}
struct Rendezvous { directory: PathBuf, socket: PathBuf, record: PathBuf }
impl Drop for Rendezvous {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.record);
        let _ = fs::remove_file(&self.socket);
        let _ = fs::remove_dir(&self.directory);
    }
}

/// Run in the PermissionRequest hook process, only when an active integration
/// is explicitly installed. No decision is returned on failure or timeout.
pub fn wait_for_decision(session: &str, request: &Value) -> Option<Value> {
    wait_for_provider(Provider::Claude, session, request)
}

pub fn wait_for_codex_decision(session: &str, request: &Value) -> Option<Value> {
    wait_for_provider(Provider::Codex, session, request)
}

fn wait_for_provider(provider: Provider, session: &str, request: &Value) -> Option<Value> {
    if !valid_session(session) || request.get("session_id")?.as_str()? != session
        || request.get("hook_event_name")?.as_str()? != "PermissionRequest"
        || request.get("tool_name")?.as_str()?.is_empty()
        || request.get("tool_input").is_some_and(|input| !input.is_object() && !input.is_null())
        || serde_json::to_vec(request).ok()?.len() > 32_768 { return None; }
    let tool = request.get("tool_name")?.as_str()?;
    if provider == Provider::Claude && (!request.get("tool_input")?.is_object() || tool == "ExitPlanMode"
        || (tool == "AskUserQuestion" && question_form(request).is_none())) { return None; }
    if provider == Provider::Codex && crate::agent_hook::codex_question_tool(tool) { return None; }
    let token = random_token()?;
    let directory = socket_dir(&token)?;
    let root = crate::agent_hook::registry()?;
    let record = registry_path(&root, provider, session, &token)?;
    DirBuilder::new().mode(0o700).create(&directory).ok()?;
    let socket = directory.join("socket");
    let cleanup = Rendezvous { directory, socket, record };
    let listener = UnixListener::bind(&cleanup.socket).ok()?;
    listener.set_nonblocking(true).ok()?;
    let now = SystemTime::now().duration_since(UNIX_EPOCH).ok()?.as_millis().min(u64::MAX as u128) as u64;
    let mut file = OpenOptions::new().write(true).create_new(true).mode(0o600).open(&cleanup.record).ok()?;
    writeln!(file, "{}", json!({"sessionId":session,"token":token,"createdAt":now})).ok()?;
    drop(file);
    let deadline = Instant::now() + WAIT;
    while Instant::now() < deadline {
        let (mut peer, _) = match listener.accept() {
            Ok(connection) => connection,
            Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => { thread::sleep(Duration::from_millis(50)); continue; }
            Err(_) => return None,
        };
        if !peer_is_owner(&peer) { continue; }
        let _ = peer.set_read_timeout(Some(IO_TIMEOUT));
        let _ = peer.set_write_timeout(Some(IO_TIMEOUT));
        let Some(message) = read_message(&peer) else { continue; };
        if Instant::now() >= deadline { break; }
        if message.get("token").and_then(Value::as_str) != Some(token.as_str()) { continue; }
        match message.get("action").and_then(Value::as_str) {
            Some("preview") => { let _ = write_message(&mut peer, &json!({"request":request})); }
            Some("release") if message.get("request") == Some(request) => {
                let _ = write_message(&mut peer, &json!({"status":"claimed"}));
                return None;
            }
            Some("settled") if event_settles_request(request, &message) => return None,
            Some("decision") if message.get("request") == Some(request) && request.get("tool_name").and_then(Value::as_str) != Some("AskUserQuestion") => {
                let decision = match message.get("decision").and_then(Value::as_str) {
                    Some("allow") => Decision::Allow, Some("deny") => Decision::Deny, _ => continue,
                };
                let reply = match provider {
                    Provider::Claude => claude_hook_response(request.get("tool_input")?, Some(decision))?,
                    Provider::Codex => codex_hook_response(decision),
                };
                // This only acknowledges the local claim, not delivery to Claude.
                write_message(&mut peer, &json!({"status":"claimed"}))?;
                return Some(reply);
            }
            Some("answer") if provider == Provider::Claude && message.get("request") == Some(request) => {
                let Some(reply) = question_response(request, &message["answers"]) else { continue; };
                write_message(&mut peer, &json!({"status":"claimed"}))?;
                return Some(reply);
            }
            _ => {}
        }
    }
    None
}

// Codex's PermissionRequest protocol must not include Claude's updatedInput.
fn codex_hook_response(decision: Decision) -> Value {
    let decision = match decision {
        Decision::Allow => json!({"behavior":"allow"}),
        Decision::Deny => json!({"behavior":"deny","message":"Rium Notch에서 거절됨"}),
    };
    json!({"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":decision}})
}

// Claude's PermissionRequest may omit tool_use_id. Compare the complete tool
// input and name instead; ambiguous matching errs on the side of closing a
// pending notch request, never approving another one.
fn event_settles_request(request: &Value, message: &Value) -> bool {
    let event = message.get("event").and_then(Value::as_str).unwrap_or("");
    if matches!(event, "Stop" | "SessionEnd") { return true; }
    if !matches!(event, "PostToolUse" | "PostToolUseFailure" | "PermissionDenied") { return false; }
    let Some(name) = request.get("tool_name").and_then(Value::as_str) else { return false; };
    if message.get("toolName").and_then(Value::as_str) != Some(name) { return false; }
    if let (Some(expected), Some(observed)) = (tool_call_id(request), message.get("toolCallId").and_then(Value::as_str)) {
        if expected != observed { return false; }
    }
    let (Some(mut original), Some(mut observed)) = (request.get("tool_input").cloned(), message.get("toolInput").cloned()) else { return false; };
    if name == "AskUserQuestion" {
        // Claude may append answers to the original input when the picker ends.
        if let Some(input) = original.as_object_mut() { input.remove("answers"); }
        if let Some(input) = observed.as_object_mut() { input.remove("answers"); }
    }
    original.is_object() && original == observed
}

fn tool_call_id(value: &Value) -> Option<&str> {
    ["tool_use_id", "tool_call_id", "call_id", "item_id"].iter()
        .find_map(|key| value.get(*key).and_then(Value::as_str).filter(|id| !id.is_empty() && id.len() <= 256))
}

/// Inform still-running local waiters about independently completed hooks.
/// Arguments are transferred over the private socket, not recorded on disk.
pub fn notify_terminal(session: &str, event: &str, input: &Value) {
    notify_provider_terminal(Provider::Claude, session, event, input)
}
pub fn notify_codex_terminal(session: &str, event: &str, input: &Value) {
    notify_provider_terminal(Provider::Codex, session, event, input)
}
fn notify_provider_terminal(provider: Provider, session: &str, event: &str, input: &Value) {
    if !valid_session(session) || !matches!(event, "PostToolUse" | "PostToolUseFailure" | "PermissionDenied" | "Stop" | "SessionEnd") { return; }
    let terminal_session = matches!(event, "Stop" | "SessionEnd");
    let name = input.get("tool_name").and_then(Value::as_str).unwrap_or("");
    let no_input = Value::Null;
    let tool_input = input.get("tool_input").unwrap_or(&no_input);
    if !terminal_session && (name.is_empty() || !tool_input.is_object()
        || serde_json::to_vec(tool_input).map_or(true, |data| data.len() > 32_768)) { return; }
    let Some(root) = crate::agent_hook::registry() else { return; };
    let Ok(entries) = fs::read_dir(root) else { return; };
    let prefix = format!("approval-{}-{session}-", provider.name());
    let mut delivered = 0;
    for entry in entries.flatten().take(REGISTRY_SCAN_LIMIT) {
        let file_name = entry.file_name();
        let Some(name_in_dir) = file_name.to_str() else { continue; };
        let Some(token) = name_in_dir.strip_prefix(&prefix).and_then(|name| name.strip_suffix(".json")) else { continue; };
        let Some(mut stream) = connect(provider, session, token) else { continue; };
        let _ = stream.set_write_timeout(Some(Duration::from_millis(100)));
        let _ = write_message(&mut stream, &json!({"action":"settled","token":token,"event":event,"toolName":name,
            "toolInput":tool_input,"toolCallId":tool_call_id(input)}));
        delivered += 1;
        if delivered >= 8 { break; }
    }
}

fn question_is_multiple(question: &Value) -> Option<bool> {
    let camel = match question.get("multiSelect") { Some(value) => Some(value.as_bool()?), None => None };
    let snake = match question.get("multi_select") { Some(value) => Some(value.as_bool()?), None => None };
    if let (Some(a), Some(b)) = (camel, snake) {
        if a != b { return None; }
    }
    Some(camel.or(snake).unwrap_or(false))
}

/// All questions must be shown and answered. Duplicate question text cannot be
/// represented in Claude's answer map, so leave those to Claude's own picker.
fn question_form(request: &Value) -> Option<&Vec<Value>> {
    if request.get("tool_name")?.as_str()? != "AskUserQuestion" { return None; }
    let input = request.get("tool_input")?.as_object()?;
    if input.get("answers").is_some_and(|answers| !answers.is_null() && answers.as_object().map_or(true, |value| !value.is_empty())) { return None; }
    let questions = input.get("questions")?.as_array()?;
    if questions.is_empty() || questions.len() > 4 { return None; }
    let mut texts = std::collections::HashSet::new();
    for question in questions {
        if question.get("isSecret").and_then(Value::as_bool) == Some(true)
            || question.get("is_secret").and_then(Value::as_bool) == Some(true) { return None; }
        let text = question.get("question")?.as_str()?;
        if text.trim().is_empty() || text.len() > 4000 || !texts.insert(text) { return None; }
        if let Some(options) = question.get("options") {
            let options = options.as_array()?;
            if options.len() > 20 { return None; }
            let mut labels = std::collections::HashSet::new();
            for option in options {
                let label = option.get("label")?.as_str()?;
                if label.trim().is_empty() || label.len() > 1000 || !labels.insert(label) { return None; }
                if option.get("description").is_some_and(|value| !value.is_string()) { return None; }
            }
        }
        question_is_multiple(question)?;
    }
    Some(questions)
}

fn question_response(request: &Value, answers: &Value) -> Option<Value> {
    let questions = question_form(request)?;
    let answers = answers.as_array()?;
    if questions.len() != answers.len() { return None; }
    let mut mapped = serde_json::Map::new();
    for (question, values) in questions.iter().zip(answers) {
        let values = values.as_array()?;
        if values.is_empty() || values.len() > 21 || (!question_is_multiple(question)? && values.len() != 1) { return None; }
        let mut unique = std::collections::HashSet::new();
        let mut selected = Vec::new();
        for value in values {
            let value = value.as_str()?;
            if value.trim().is_empty() || value.len() > 2000 || !unique.insert(value) { return None; }
            selected.push(value);
        }
        mapped.insert(question.get("question")?.as_str()?.to_owned(), json!(selected.join(", ")));
    }
    let mut input = request.get("tool_input")?.as_object()?.clone();
    input.insert("answers".into(), Value::Object(mapped));
    Some(json!({"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","updatedInput":input}}}))
}

fn connect(provider: Provider, session: &str, token: &str) -> Option<UnixStream> {
    let root = crate::agent_hook::registry()?;
    let record = registry_path(&root, provider, session, token)?;
    let meta = fs::symlink_metadata(&record).ok()?;
    if !meta.file_type().is_file() || meta.uid() != unsafe { geteuid() } || meta.mode() & 0o077 != 0 || meta.len() > 4096 { return None; }
    let file = File::open(&record).ok()?;
    let opened = file.metadata().ok()?;
    if opened.dev() != meta.dev() || opened.ino() != meta.ino() { return None; }
    let record: Value = serde_json::from_reader(file.take(4097)).ok()?;
    if record.get("sessionId")?.as_str()? != session || record.get("token")?.as_str()? != token { return None; }
    let created = record.get("createdAt")?.as_u64()?;
    let now = SystemTime::now().duration_since(UNIX_EPOCH).ok()?.as_millis();
    if u128::from(created) > now || now - u128::from(created) > 60_000 { return None; }
    let dir = socket_dir(token)?;
    let metadata = fs::symlink_metadata(&dir).ok()?;
    if !metadata.file_type().is_dir() || metadata.uid() != unsafe { geteuid() } || metadata.mode() & 0o077 != 0 { return None; }
    let socket = dir.join("socket");
    let metadata = fs::symlink_metadata(&socket).ok()?;
    if !metadata.file_type().is_socket() || metadata.uid() != unsafe { geteuid() } { return None; }
    let stream = UnixStream::connect(socket).ok()?;
    if !peer_is_owner(&stream) { return None; }
    stream.set_read_timeout(Some(IO_TIMEOUT)).ok()?;
    stream.set_write_timeout(Some(IO_TIMEOUT)).ok()?;
    Some(stream)
}

/// Complete, current previews; callers must not truncate approval details.
pub fn previews(session: &str) -> Vec<Value> {
    previews_for(Provider::Claude, session)
}
pub fn codex_previews(session: &str) -> Vec<Value> {
    previews_for(Provider::Codex, session)
}

/// A preview that can prove its scan did not omit a matching registry entry.
/// A transiently unreachable entry is reported as an error, never as empty.
pub fn strict_previews(session: &str, codex: bool) -> Result<Vec<Value>, String> {
    let provider = if codex { Provider::Codex } else { Provider::Claude };
    if !valid_session(session) { return Err("승인 대화 식별자를 확인할 수 없습니다".into()); }
    let root = crate::agent_hook::registry().ok_or("승인 목록을 확인할 수 없습니다")?;
    let prefix = format!("approval-{}-{session}-", provider.name());
    let inventory = || -> Result<Vec<String>, String> {
        let mut names = Vec::new();
        let entries = fs::read_dir(&root).map_err(|_| "승인 목록을 읽을 수 없습니다")?;
        for (index, entry) in entries.enumerate() {
            if index >= REGISTRY_SCAN_LIMIT { return Err("승인 목록이 너무 큽니다".into()); }
            let name = entry.map_err(|_| "승인 목록을 읽을 수 없습니다")?.file_name();
            let Some(name) = name.to_str() else { return Err("승인 목록 이름을 확인할 수 없습니다".into()); };
            if !name.starts_with(&prefix) { continue; }
            let token = name.strip_prefix(&prefix).and_then(|name| name.strip_suffix(".json"))
                .filter(|token| valid_token(token)).ok_or("승인 항목을 확인할 수 없습니다")?;
            names.push(token.to_owned());
        }
        names.sort();
        if names.len() > 8 { return Err("승인 요청이 너무 많습니다".into()); }
        Ok(names)
    };
    let tokens = inventory()?;
    let mut previews = Vec::new();
    for token in &tokens {
        let mut stream = connect(provider, session, token).ok_or("승인 요청의 연결을 확인할 수 없습니다")?;
        write_message(&mut stream, &json!({"action":"preview","token":token})).ok_or("승인 요청을 읽을 수 없습니다")?;
        let reply = read_message(&stream).ok_or("승인 요청을 읽을 수 없습니다")?;
        let request = reply.get("request").filter(|value| value.is_object()).ok_or("승인 요청 형식을 확인할 수 없습니다")?;
        previews.push(json!({"token":token,"request":request}));
    }
    if inventory()? != tokens { return Err("조회 중 승인 요청이 변경됐습니다".into()); }
    Ok(previews)
}
fn previews_for(provider: Provider, session: &str) -> Vec<Value> {
    if !valid_session(session) { return Vec::new(); }
    let Some(root) = crate::agent_hook::registry() else { return Vec::new(); };
    let Ok(entries) = fs::read_dir(root) else { return Vec::new(); };
    let prefix = format!("approval-{}-{session}-", provider.name());
    let mut previews = Vec::new();
    for entry in entries.flatten().take(REGISTRY_SCAN_LIMIT) {
        let name = entry.file_name();
        let Some(name) = name.to_str() else { continue; };
        let Some(token) = name.strip_prefix(&prefix).and_then(|name| name.strip_suffix(".json")) else { continue; };
        let Some(mut stream) = connect(provider, session, token) else { continue; };
        if write_message(&mut stream, &json!({"action":"preview","token":token})).is_none() { continue; }
        let Some(reply) = read_message(&stream) else { continue; };
        let Some(request) = reply.get("request").filter(|request| request.is_object()) else { continue; };
        previews.push(json!({"token":token,"request":request}));
        if previews.len() == 8 { break; }
    }
    previews
}

/// A submitted decision is tied to the exact preview; never retry a claim.
pub fn decide(session: &str, token: &str, shown: &Value, decision: &str) -> Result<Value, String> {
    decide_for(Provider::Claude, session, token, shown, decision)
}
pub fn decide_codex(session: &str, token: &str, shown: &Value, decision: &str) -> Result<Value, String> {
    decide_for(Provider::Codex, session, token, shown, decision)
}
fn decide_for(provider: Provider, session: &str, token: &str, shown: &Value, decision: &str) -> Result<Value, String> {
    if !matches!(decision, "allow" | "deny") || !shown.is_object()
        || serde_json::to_vec(shown).map_or(true, |data| data.len() > 32_768) {
        return Err("승인 요청 내용을 확인할 수 없습니다".into());
    }
    let message = json!({"action":"decision","token":token,"request":shown,"decision":decision});
    send_claim(provider, session, token, &message)
}

pub fn answer(session: &str, token: &str, shown: &Value, answers: &Value) -> Result<Value, String> {
    if question_response(shown, answers).is_none() { return Err("질문과 답변을 확인할 수 없습니다".into()); }
    let message = json!({"action":"answer","token":token,"request":shown,"answers":answers});
    send_claim(Provider::Claude, session, token, &message)
}

/// Release the waiter without granting or denying; Claude handles the request.
pub fn release(session: &str, token: &str, shown: &Value) -> Result<Value, String> {
    release_for(Provider::Claude, session, token, shown)
}
pub fn release_codex(session: &str, token: &str, shown: &Value) -> Result<Value, String> {
    release_for(Provider::Codex, session, token, shown)
}
fn release_for(provider: Provider, session: &str, token: &str, shown: &Value) -> Result<Value, String> {
    if !shown.is_object() || serde_json::to_vec(shown).map_or(true, |data| data.len() > 32_768) {
        return Err("요청 내용을 확인할 수 없습니다".into());
    }
    send_claim(provider, session, token, &json!({"action":"release","token":token,"request":shown}))
}

fn send_claim(provider: Provider, session: &str, token: &str, message: &Value) -> Result<Value, String> {
    let mut stream = connect(provider, session, token).ok_or("요청이 만료되었거나 연결할 수 없습니다")?;
    if write_message(&mut stream, message).is_none() { return Ok(json!({"status":"unknown"})); }
    let response = read_message(&stream);
    Ok(json!({"status":if response.as_ref().and_then(|value| value.get("status")).and_then(Value::as_str) == Some("claimed") {"claimed"} else {"unknown"}}))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rejects_untrusted_paths_and_wrong_request_types() {
        let root = Path::new("/tmp/root");
        assert!(registry_path(root, Provider::Claude, "../other", "0123456789abcdef0123456789abcdef").is_none());
        assert!(socket_dir("../../bad").is_none());
        assert!(wait_for_decision("bad", &json!({})).is_none());
        assert!(decide("bad", "bad", &json!(null), "allow").is_err());
    }

    #[test]
    fn codex_permission_reply_does_not_use_claude_updated_input() {
        let allow = codex_hook_response(Decision::Allow);
        assert_eq!(allow["hookSpecificOutput"]["decision"], json!({"behavior":"allow"}));
        let deny = codex_hook_response(Decision::Deny);
        assert_eq!(deny["hookSpecificOutput"]["decision"]["behavior"], "deny");
        assert!(deny["hookSpecificOutput"]["decision"]["message"].is_string());
    }

    #[test]
    fn question_responses_cover_every_original_question() {
        let request = json!({"tool_name":"AskUserQuestion", "tool_input":{"questions":[
            {"question":"어느 색?","options":[{"label":"파랑"}],"multiSelect":false},
            {"question":"형식?","options":[{"label":"PNG"},{"label":"JPG"}],"multiSelect":true}
        ]}});
        let result = question_response(&request, &json!([["파랑"],["PNG","JPG"]])).unwrap();
        assert_eq!(result["hookSpecificOutput"]["decision"]["updatedInput"]["answers"], json!({"어느 색?":"파랑","형식?":"PNG, JPG"}));
        assert!(question_response(&request, &json!([["파랑"]])).is_none());
        assert!(question_response(&request, &json!([["파랑","빨강"],["PNG"]])).is_none());
        assert!(question_response(&request, &json!([["파랑"],[]])).is_none());
        let duplicate = json!({"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"같음"},{"question":"같음"}]}});
        assert!(question_form(&duplicate).is_none());
        let secret = json!({"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"암호","isSecret":true}]}});
        assert!(question_form(&secret).is_none());
        let snake = json!({"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"형식?","multi_select":true}]}});
        assert!(question_response(&snake, &json!([["PNG", "JPG"]])).is_some());
        let conflict = json!({"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"형식?","multiSelect":false,"multi_select":true}]}});
        assert!(question_form(&conflict).is_none());
        let duplicate_options = json!({"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"형식?","options":[{"label":"PNG"},{"label":"PNG"}]}]}});
        assert!(question_form(&duplicate_options).is_none());
    }

    #[test]
    fn only_matching_terminal_events_retire_a_request() {
        let request = json!({"tool_name":"Bash","tool_input":{"command":"first"}});
        assert!(event_settles_request(&request, &json!({"event":"PostToolUse","toolName":"Bash","toolInput":{"command":"first"}})));
        assert!(!event_settles_request(&request, &json!({"event":"PostToolUse","toolName":"Bash","toolInput":{"command":"second"}})));
        assert!(!event_settles_request(&request, &json!({"event":"PreToolUse","toolName":"Bash","toolInput":{"command":"first"}})));
        let identified = json!({"tool_name":"Bash","tool_use_id":"one","tool_input":{"command":"first"}});
        assert!(!event_settles_request(&identified, &json!({"event":"PostToolUse","toolName":"Bash","toolCallId":"two","toolInput":{"command":"first"}})));
        assert!(event_settles_request(&request, &json!({"event":"SessionEnd"})));
        let question = json!({"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"계속?"}]}});
        assert!(event_settles_request(&question, &json!({"event":"PostToolUse","toolName":"AskUserQuestion","toolInput":{"questions":[{"question":"계속?"}],"answers":{"계속?":"네"}}})));
    }
}
