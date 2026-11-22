//! State for a single Desktop <-> App Server connection. It never attaches to
//! or starts a process by itself. The eventual transport must serialize every
//! call and every engine write in one event loop, including notch responses.
use crate::agent_approval::{ApprovalWire, Decision};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::fs::{self, File};
use std::io::Read;
use std::path::{Path, PathBuf};

const MAX_FRAME: usize = 16 * 1024 * 1024;
const MAX_CLIENT_REQUESTS: usize = 16_384;
const REQUEST_TTL_MS: u64 = 300_000;
const IDLE_STATUS_TTL_MS: u64 = 30_000;

struct ClientRequest { original_id: Value, method: String, thread_id: Option<String> }

struct DesktopThread {
    cwd: PathBuf,
    generating: Option<(bool, u64)>,
}

impl DesktopThread {
    fn current_generation_state(&self, now_ms: u64) -> Option<bool> {
        self.generating.filter(|(active, observed)| {
            *active || now_ms.checked_sub(*observed).is_some_and(|age| age <= IDLE_STATUS_TTL_MS)
        }).map(|(active, _)| active)
    }
}

/// A claim is only a response ready for the owning transport to write. It is
/// not evidence that App Server received or accepted the response.
pub struct DesktopBridge {
    prefix: String,
    sequence: u64,
    pending_client: HashMap<String, ClientRequest>,
    threads: HashMap<String, DesktopThread>,
    read_threads: HashMap<String, (PathBuf, u64)>,
    initialize_accepted: bool,
    initialized: bool,
    revision: u64,
    approvals: ApprovalWire,
}

impl DesktopBridge {
    pub fn new() -> Option<Self> {
        let mut nonce = [0u8; 16];
        File::open("/dev/urandom").ok()?.read_exact(&mut nonce).ok()?;
        let nonce: String = nonce.iter().map(|value| format!("{value:02x}")).collect();
        Self::with_nonce(&nonce)
    }

    fn with_nonce(nonce: &str) -> Option<Self> {
        if nonce.len() != 32 || !nonce.bytes().all(|byte| byte.is_ascii_hexdigit() && !byte.is_ascii_uppercase()) { return None; }
        Some(Self {
            prefix: format!("rium-{nonce}:"), sequence: 0, pending_client: HashMap::new(),
            threads: HashMap::new(), read_threads: HashMap::new(), initialize_accepted: false, initialized: false, revision: 0,
            approvals: ApprovalWire::default(),
        })
    }

    fn next_id(&mut self, kind: &str) -> Option<String> {
        self.sequence = self.sequence.checked_add(1)?;
        Some(format!("{}{kind}:{}", self.prefix, self.sequence))
    }

    pub fn ready(&self) -> bool { self.initialize_accepted && self.initialized }
    pub fn revision(&self) -> u64 { self.revision }
    fn changed(&mut self) { self.revision = self.revision.wrapping_add(1); }

    pub fn sessions(&self) -> Vec<Value> {
        if !self.ready() { return Vec::new(); }
        let mut sessions: Vec<_> = self.threads.iter().map(|(id, thread)| json!({"sessionId":id,"workspace":thread.cwd})).collect();
        sessions.sort_by(|a, b| a["sessionId"].as_str().cmp(&b["sessionId"].as_str()));
        sessions
    }

    /// Only metadata leaves this method; approval commands and question text
    /// stay inside the owning connection until the user opens the request.
    pub fn activity(&self, now_ms: u64) -> Vec<Value> {
        if !self.ready() { return Vec::new(); }
        let mut pending: HashMap<String, &str> = HashMap::new();
        for preview in self.approvals.previews(now_ms) {
            let Some(session) = preview.get("sessionId").and_then(Value::as_str) else { continue; };
            let kind = if preview.get("kind").and_then(Value::as_str) == Some("approval") { "approval" } else { "question" };
            let value = pending.entry(session.to_owned()).or_insert(kind);
            if kind == "approval" { *value = kind; }
        }
        let mut sessions: Vec<_> = self.threads.iter().map(|(id, thread)| {
            let project: String = thread.cwd.file_name().and_then(|name| name.to_str()).unwrap_or("Codex")
                .chars().filter(|character| !character.is_control()).take(80).collect();
            json!({"sessionId":id,"project":if project.is_empty() { "Codex" } else { &project },
                   "pending":pending.get(id),"generating":thread.current_generation_state(now_ms)})
        }).collect();
        sessions.sort_by(|a, b| a["sessionId"].as_str().cmp(&b["sessionId"].as_str()));
        sessions
    }

    /// Input is one complete JSONL frame without its newline. Return None only
    /// for a late native reply already claimed by the notch. An error means
    /// the caller must report backpressure, not forward a colliding request.
    pub fn from_desktop(&mut self, line: &[u8]) -> Result<Option<Vec<u8>>, &'static str> {
        if line.len() > MAX_FRAME { return Err("frame_too_large"); }
        let Ok(mut message) = serde_json::from_slice::<Value>(line) else { return Ok(Some(line.to_vec())); };
        if message.get("method").is_none() {
            let before = self.approvals.pending_count();
            if !self.approvals.forward_native(&message) { return Ok(None); }
            if before != self.approvals.pending_count() { self.changed(); }
        }
        if message.get("method").and_then(Value::as_str) == Some("initialized") && !self.initialized {
            self.initialized = true; self.changed();
        }
        let Some(method) = message.get("method").and_then(Value::as_str).map(str::to_owned) else { return Ok(Some(line.to_vec())); };
        let Some(id) = message.get("id").cloned().filter(|id| id.is_number() || id.is_string()) else { return Ok(Some(line.to_vec())); };
        if self.pending_client.len() >= MAX_CLIENT_REQUESTS { return Err("request_queue_full"); }
        let next = self.next_id("desktop").ok_or("identifier_exhausted")?;
        let thread_id = if method == "thread/read" {
            message.pointer("/params/threadId").and_then(Value::as_str)
                .filter(|id| !id.is_empty() && id.len() <= 256).map(str::to_owned)
        } else { None };
        self.pending_client.insert(next.clone(), ClientRequest { original_id: id, method, thread_id });
        message["id"] = json!(next);
        serde_json::to_vec(&message).map(Some).map_err(|_| "invalid_frame")
    }

    /// Native server requests remain visible to Desktop. Only replies to IDs
    /// rewritten by this connection are mapped back to Desktop's original ID.
    pub fn from_server(&mut self, line: &[u8], now_ms: u64) -> Result<Option<Vec<u8>>, &'static str> {
        if line.len() > MAX_FRAME { return Err("frame_too_large"); }
        let Ok(mut message) = serde_json::from_slice::<Value>(line) else { return Ok(Some(line.to_vec())); };
        let before = self.approvals.pending_count();
        self.approvals.observe_server(&message);
        if before != self.approvals.pending_count() { self.changed(); }
        if message.get("method").is_none() {
            if let Some(id) = message.get("id").and_then(Value::as_str).filter(|id| id.starts_with(&self.prefix)) {
                let Some(client) = self.pending_client.remove(id) else { return Ok(None); };
                let ok = message.get("error").is_none();
                let was_ready = self.ready();
                if client.method == "initialize" { self.initialize_accepted = ok; }
                else if ok && self.initialize_accepted { self.initialized = true; }
                if was_ready != self.ready() { self.changed(); }
                if ok && matches!(client.method.as_str(), "thread/start" | "thread/resume") {
                    self.remember_thread(message.pointer("/result/thread"), now_ms);
                }
                if ok && client.method == "thread/read" {
                    if let Some(expected) = client.thread_id.as_deref() {
                        self.remember_read(expected, message.pointer("/result/thread"), now_ms);
                    }
                }
                message["id"] = client.original_id;
                return serde_json::to_vec(&message).map(Some).map_err(|_| "invalid_frame");
            }
        } else if self.ready() && message.get("id").is_some() {
            let session = message.pointer("/params/threadId").and_then(Value::as_str).map(str::to_owned);
            let turn = message.pointer("/params/turnId").and_then(Value::as_str).unwrap_or("").to_owned();
            if let Some(session) = session {
                if let Some(token) = self.next_id("native") {
                    // The token is local to this connection; it contains no request details.
                    if self.approvals.register(&token.replace(':', "."), &session, &turn, message.clone(), now_ms, REQUEST_TTL_MS) {
                        if !self.threads.contains_key(&session) {
                            if let Some((cwd, observed)) = self.read_threads.get(&session).cloned() {
                                if now_ms >= observed && now_ms - observed <= 30_000 {
                                    self.remember_thread(Some(&json!({"id":session,"cwd":cwd})), now_ms);
                                }
                            }
                        }
                        self.changed();
                    }
                }
            }
        }
        if self.ready() && message.get("id").is_none() {
            if let Some(thread) = message.pointer("/params/threadId").and_then(Value::as_str) {
                match message.get("method").and_then(Value::as_str) {
                    Some("thread/status/changed") => self.observe_generation_state(thread, message.pointer("/params/status/type").and_then(Value::as_str), now_ms),
                    Some("thread/closed") => self.observe_generation_state(thread, Some("notLoaded"), now_ms),
                    _ => (),
                }
            }
        }
        Ok(Some(line.to_vec()))
    }

    fn observe_generation_state(&mut self, id: &str, status: Option<&str>, now_ms: u64) {
        let Some(thread) = self.threads.get_mut(id) else { return; };
        let active = match status {
            Some("active") => Some(true),
            Some("idle" | "notLoaded" | "systemError") => Some(false),
            _ => None,
        };
        let previous = thread.current_generation_state(now_ms);
        thread.generating = active.map(|active| (active, now_ms));
        if active != previous { self.changed(); }
    }

    fn remember_read(&mut self, expected: &str, thread: Option<&Value>, now_ms: u64) {
        let Some(thread) = thread.filter(|thread| thread.get("id").and_then(Value::as_str) == Some(expected)) else {
            self.read_threads.remove(expected);
            if self.threads.remove(expected).is_some() { self.approvals.forget_session(expected); self.changed(); }
            return;
        };
        let cwd = thread.get("cwd").and_then(Value::as_str).filter(|cwd| Path::new(cwd).is_absolute())
            .and_then(|cwd| fs::canonicalize(cwd).ok()).filter(|cwd| cwd.is_dir());
        let Some(cwd) = cwd else {
            self.read_threads.remove(expected);
            if self.threads.remove(expected).is_some() { self.approvals.forget_session(expected); self.changed(); }
            return;
        };
        self.read_threads.retain(|_, (_, observed)| now_ms >= *observed && now_ms - *observed <= 30_000);
        if self.read_threads.len() >= 256 && !self.read_threads.contains_key(expected) { return; }
        self.read_threads.insert(expected.to_owned(), (cwd, now_ms));
        let request_on_connection = self.approvals.previews(now_ms).iter().any(|preview| preview.get("sessionId").and_then(Value::as_str) == Some(expected));
        if self.threads.contains_key(expected) || request_on_connection { self.remember_thread(Some(thread), now_ms); }
    }

    fn remember_thread(&mut self, thread: Option<&Value>, now_ms: u64) {
        let Some(thread) = thread else { return; };
        let Some(id) = thread.get("id").and_then(Value::as_str).filter(|id| !id.is_empty() && id.len() <= 256) else { return; };
        let cwd = thread.get("cwd").and_then(Value::as_str).filter(|cwd| Path::new(cwd).is_absolute())
            .and_then(|cwd| fs::canonicalize(cwd).ok()).filter(|cwd| cwd.is_dir());
        let Some(cwd) = cwd else {
            if self.threads.remove(id).is_some() { self.approvals.forget_session(id); self.changed(); }
            return;
        };
        if self.threads.len() >= 256 && !self.threads.contains_key(id) { return; }
        if self.threads.get(id).map(|known| &known.cwd) != Some(&cwd) {
            if self.threads.contains_key(id) { self.approvals.forget_session(id); }
            self.threads.insert(id.to_owned(), DesktopThread { cwd, generating: None });
            self.changed();
        }
        if let Some(status) = thread.pointer("/status/type").and_then(Value::as_str) {
            self.observe_generation_state(id, Some(status), now_ms);
        }
    }

    fn matches_thread(&self, session: &str, workspace: &Path) -> bool {
        self.ready() && self.threads.get(session).is_some_and(|known| {
            workspace.is_absolute() && fs::canonicalize(workspace).ok().is_some_and(|cwd| cwd == known.cwd)
        })
    }

    pub fn previews(&self, session: &str, workspace: &Path, now_ms: u64) -> Vec<Value> {
        if !self.matches_thread(session, workspace) { return Vec::new(); }
        self.approvals.previews(now_ms).into_iter()
            .filter(|preview| preview.get("sessionId").and_then(Value::as_str) == Some(session)).collect()
    }

    fn matches_preview(&self, session: &str, workspace: &Path, token: &str, now_ms: u64, shown: &Value) -> bool {
        self.previews(session, workspace, now_ms).iter().any(|preview| {
            preview.get("token").and_then(Value::as_str) == Some(token) && preview == shown
        })
    }

    pub fn claim_approval(&mut self, session: &str, workspace: &Path, token: &str, turn: &str, now_ms: u64, shown: &Value, decision: Decision) -> Option<Value> {
        if !self.matches_preview(session, workspace, token, now_ms, shown) { return None; }
        let result = self.approvals.claim(token, session, turn, now_ms, decision);
        if result.is_some() { self.changed(); }
        result
    }

    pub fn claim_question(&mut self, session: &str, workspace: &Path, token: &str, turn: &str, now_ms: u64, shown: &Value, answers: &Value) -> Option<Value> {
        if !self.matches_preview(session, workspace, token, now_ms, shown) { return None; }
        let result = self.approvals.claim_question(token, session, turn, now_ms, answers);
        if result.is_some() { self.changed(); }
        result
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn object(bytes: &[u8]) -> Value { serde_json::from_slice(bytes).unwrap() }

    #[test]
    fn desktop_ids_round_trip_and_unsolicited_notifications_pass_unchanged() {
        let mut bridge = DesktopBridge::with_nonce("0123456789abcdef0123456789abcdef").unwrap();
        let outbound = bridge.from_desktop(br#"{"id":12,"method":"initialize","params":{}}"#).unwrap().unwrap();
        let rewritten = object(&outbound)["id"].clone();
        assert_ne!(rewritten, json!(12));
        let response = serde_json::to_vec(&json!({"id":rewritten,"result":{}})).unwrap();
        assert_eq!(object(&bridge.from_server(&response, 1).unwrap().unwrap())["id"], json!(12));
        let notification = br#"{"method":"item/agentMessage/delta","params":{"delta":"hello"}}"#;
        assert_eq!(bridge.from_server(notification, 2).unwrap().unwrap(), notification.to_vec());
        assert!(!bridge.ready());
        bridge.from_desktop(br#"{"method":"initialized"}"#).unwrap();
        assert!(bridge.ready());
    }

    #[test]
    fn notch_and_desktop_never_both_reply_to_one_question() {
        let mut bridge = DesktopBridge::with_nonce("0123456789abcdef0123456789abcdef").unwrap();
        bridge.initialize_accepted = true; bridge.initialized = true;
        let workspace = fs::canonicalize(std::env::temp_dir()).unwrap();
        bridge.remember_thread(Some(&json!({"id":"session","cwd":workspace})), 0);
        let request = json!({"id":9,"method":"item/tool/requestUserInput","params":{"threadId":"session","turnId":"turn",
            "questions":[{"id":"q","question":"계속?","options":[{"label":"네"}]}]}});
        let raw = serde_json::to_vec(&request).unwrap();
        assert_eq!(bridge.from_server(&raw, 10).unwrap().unwrap(), raw);
        let activity = bridge.activity(11);
        assert_eq!(activity[0]["pending"], "question");
        assert!(!serde_json::to_string(&activity).unwrap().contains("계속?"));
        let preview = bridge.previews("session", &workspace, 11);
        let token = preview[0]["token"].as_str().unwrap();
        assert!(bridge.claim_question("session", &workspace, token, "turn", 12, &json!({}), &json!([["네"]])).is_none());
        assert!(bridge.claim_question("session", &workspace, token, "turn", 12, &preview[0], &json!([["네"]])).is_some());
        assert!(bridge.from_desktop(br#"{"id":9,"result":{"answers":{}}}"#).unwrap().is_none());
    }

    #[test]
    fn read_and_native_request_must_both_identify_the_same_thread() {
        let workspace = fs::canonicalize(std::env::temp_dir()).unwrap();
        let native = json!({"id":9,"method":"item/tool/requestUserInput","params":{"threadId":"session","turnId":"turn",
            "questions":[{"id":"q","question":"계속?","options":[{"label":"네"}]}]}});
        for read_first in [false, true] {
            let mut bridge = DesktopBridge::with_nonce("0123456789abcdef0123456789abcdef").unwrap();
            bridge.initialize_accepted = true; bridge.initialized = true;
            let read = json!({"id":2,"method":"thread/read","params":{"threadId":"session"}});
            let forwarded = bridge.from_desktop(&serde_json::to_vec(&read).unwrap()).unwrap().unwrap();
            let rewritten = object(&forwarded)["id"].clone();
            let response = json!({"id":rewritten,"result":{"thread":{"id":"session","cwd":workspace.to_string_lossy()}}});
            if read_first { bridge.from_server(&serde_json::to_vec(&response).unwrap(), 1).unwrap(); }
            assert!(bridge.sessions().is_empty());
            bridge.from_server(&serde_json::to_vec(&native).unwrap(), 2).unwrap();
            if !read_first {
                assert!(bridge.sessions().is_empty());
                bridge.from_server(&serde_json::to_vec(&response).unwrap(), 3).unwrap();
            }
            assert_eq!(bridge.sessions().len(), 1);
            assert_eq!(bridge.previews("session", &workspace, 4).len(), 1);
        }
    }

    #[test]
    fn status_for_the_owned_session_survives_quiet_work_then_expires_after_close() {
        let workspace = fs::canonicalize(std::env::temp_dir()).unwrap();
        let mut bridge = DesktopBridge::with_nonce("0123456789abcdef0123456789abcdef").unwrap();
        bridge.initialize_accepted = true;
        bridge.initialized = true;
        let start = bridge.from_desktop(br#"{"id":1,"method":"thread/resume"}"#).unwrap().unwrap();
        let response = json!({"id":object(&start)["id"],"result":{"thread":{
            "id":"known","cwd":workspace,"status":{"type":"active","activeFlags":[]}
        }}});
        bridge.from_server(&serde_json::to_vec(&response).unwrap(), 100).unwrap();
        assert_eq!(bridge.activity(120_000)[0]["generating"], true);

        let before_close = bridge.revision();
        let unknown = br#"{"method":"thread/status/changed","params":{"threadId":"other","status":{"type":"idle"}}}"#;
        assert_eq!(bridge.from_server(unknown, 120_001).unwrap().unwrap(), unknown);
        assert_eq!(bridge.revision(), before_close);

        let close = br#"{"method":"thread/closed","params":{"threadId":"known"}}"#;
        assert_eq!(bridge.from_server(close, 120_002).unwrap().unwrap(), close);
        assert_ne!(bridge.revision(), before_close);
        assert_eq!(bridge.activity(150_002)[0]["generating"], false);
        assert!(bridge.activity(150_003)[0]["generating"].is_null());

        let active = br#"{"method":"thread/status/changed","params":{"threadId":"known","status":{"type":"active","activeFlags":[]}}}"#;
        assert_eq!(bridge.from_server(active, 150_004).unwrap().unwrap(), active);
        assert_eq!(bridge.activity(200_000)[0]["generating"], true);
    }

    #[test]
    fn answered_or_mismatched_read_does_not_publish_a_request() {
        let workspace = fs::canonicalize(std::env::temp_dir()).unwrap();
        let mut bridge = DesktopBridge::with_nonce("0123456789abcdef0123456789abcdef").unwrap();
        bridge.initialize_accepted = true; bridge.initialized = true;
        let request = json!({"id":9,"method":"item/tool/requestUserInput","params":{"threadId":"session","turnId":"turn",
            "questions":[{"id":"q","question":"계속?","options":[{"label":"네"}]}]}});
        bridge.from_server(&serde_json::to_vec(&request).unwrap(), 1).unwrap();
        bridge.from_desktop(br#"{"id":9,"result":{"answers":{}}}"#).unwrap();
        let read = bridge.from_desktop(br#"{"id":2,"method":"thread/read","params":{"threadId":"session"}}"#).unwrap().unwrap();
        let id = object(&read)["id"].clone();
        let reply = json!({"id":id,"result":{"thread":{"id":"session","cwd":workspace.to_string_lossy()}}});
        bridge.from_server(&serde_json::to_vec(&reply).unwrap(), 2).unwrap();
        assert!(bridge.sessions().is_empty());
        assert!(bridge.previews("session", &workspace, 3).is_empty());
        let next = bridge.from_desktop(br#"{"id":3,"method":"thread/read","params":{"threadId":"session"}}"#).unwrap().unwrap();
        let id = object(&next)["id"].clone();
        let mismatched = json!({"id":id,"result":{"thread":{"id":"different","cwd":workspace.to_string_lossy()}}});
        bridge.from_server(&serde_json::to_vec(&mismatched).unwrap(), 4).unwrap();
        let mut new_request = request;
        new_request["id"] = json!(10);
        bridge.from_server(&serde_json::to_vec(&new_request).unwrap(), 5).unwrap();
        assert!(bridge.sessions().is_empty());
    }
}
