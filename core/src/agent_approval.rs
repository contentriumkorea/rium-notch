//! Construction of one-request approval replies. The live connection owns
//! request correlation and must never reuse a response for another request.
use serde_json::{json, Value};
use std::collections::HashMap;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Decision { Allow, Deny }

struct PendingApproval {
    session: String,
    turn: String,
    request: Value,
    started: u64,
    deadline: u64,
}

/// In-memory request ownership for a future persistent app-server connection.
/// Times must come from the same monotonic clock; IDs are opaque to this type.
#[derive(Default)]
pub struct PendingApprovals {
    entries: HashMap<String, PendingApproval>,
    completed: HashMap<(String, String, String), u64>,
}

/// One instance per engine connection. Its owner must serialize calls and
/// writes to the engine in the same event loop; a returned reply is a claim,
/// not proof that the engine received or accepted it.
#[derive(Default)]
pub struct ApprovalWire {
    pending: PendingApprovals,
    claimed_ids: HashMap<String, ()>,
}

impl ApprovalWire {
    pub fn register(&mut self, token: &str, session: &str, turn: &str, request: Value, now: u64, ttl_ms: u64) -> bool {
        let Some(id) = request.get("id") else { return false; };
        if self.claimed_ids.contains_key(&id.to_string()) || self.claimed_ids.len() >= 256
            || self.pending.entries.values().any(|entry| entry.request.get("id") == Some(id)) { return false; }
        self.pending.insert(token, session, turn, request, now, ttl_ms)
    }

    pub fn previews(&self, now: u64) -> Vec<Value> { self.pending.previews(now) }
    pub fn pending_count(&self) -> usize { self.pending.entries.len() }

    /// False means a previously claimed reply must not also reach the engine.
    pub fn forward_native(&mut self, message: &Value) -> bool {
        if message.get("method").is_none() {
            if let Some(id) = message.get("id") {
                if self.claimed_ids.contains_key(&id.to_string()) { return false; }
            }
            self.pending.observe_native_reply(message);
        }
        true
    }

    pub fn observe_server(&mut self, message: &Value) { self.pending.observe_server_event(message); }

    pub fn forget_session(&mut self, session: &str) { self.pending.cancel_session(session); }

    pub fn claim(&mut self, token: &str, session: &str, turn: &str, now: u64, decision: Decision) -> Option<Value> {
        if self.claimed_ids.len() >= 256 { return None; }
        let id = self.pending.entries.get(token)?.request.get("id")?.to_string();
        if self.claimed_ids.contains_key(&id) { return None; }
        let response = self.pending.resolve(token, session, turn, now, decision)?;
        self.claimed_ids.insert(id, ());
        Some(response)
    }

    pub fn claim_question(&mut self, token: &str, session: &str, turn: &str, now: u64, answers: &Value) -> Option<Value> {
        if self.claimed_ids.len() >= 256 { return None; }
        let id = self.pending.entries.get(token)?.request.get("id")?.to_string();
        if self.claimed_ids.contains_key(&id) { return None; }
        let response = self.pending.resolve_question(token, session, turn, now, answers)?;
        self.claimed_ids.insert(id, ());
        Some(response)
    }
}

impl PendingApprovals {
    pub fn insert(&mut self, token: &str, session: &str, turn: &str, request: Value, now: u64, ttl_ms: u64) -> bool {
        fn valid(value: &str) -> bool {
            !value.is_empty() && value.len() <= 256 && value.bytes().all(|c| c.is_ascii_alphanumeric() || matches!(c, b'-' | b'_' | b'.'))
        }
        self.entries.retain(|_, entry| now <= entry.deadline);
        self.completed.retain(|_, deadline| now <= *deadline);
        if !valid(token) || !valid(session) || (!turn.is_empty() && !valid(turn)) || !(1..=300_000).contains(&ttl_ms)
            || self.entries.len() >= 64 || self.completed.len() >= 256 || self.entries.contains_key(token) { return false; }
        let Some(deadline) = now.checked_add(ttl_ms) else { return false; };
        let Some(params) = request.get("params") else { return false; };
        let request_turn = match params.get("turnId") {
            None | Some(Value::Null) => "",
            Some(Value::String(id)) => id.as_str(),
            _ => return false,
        };
        if params.get("threadId").and_then(Value::as_str) != Some(session)
            || request_turn != turn
            || request_preview(&request).is_none()
            || self.entries.values().any(|entry| entry.session == session && entry.turn == turn && entry.request.get("id") == request.get("id"))
            || self.completed.contains_key(&(session.to_owned(), turn.to_owned(), request["id"].to_string())) { return false; }
        self.entries.insert(token.to_owned(), PendingApproval { session: session.to_owned(), turn: turn.to_owned(), request, started: now, deadline });
        true
    }

    /// Only the owning UI should receive these local previews; request details
    /// can contain commands or paths and must not be logged or sent elsewhere.
    pub fn previews(&self, now: u64) -> Vec<Value> {
        let mut visible: Vec<_> = self.entries.iter().filter(|(_, entry)| now >= entry.started && now <= entry.deadline).collect();
        visible.sort_unstable_by(|a, b| a.1.started.cmp(&b.1.started).then_with(|| a.0.cmp(b.0)));
        visible.into_iter().filter_map(|(token, entry)| {
            let mut preview = request_preview(&entry.request)?;
            let object = preview.as_object_mut()?;
            object.insert("token".into(), json!(token));
            object.insert("sessionId".into(), json!(entry.session));
            object.insert("turnId".into(), json!(entry.turn));
            Some(preview)
        }).collect()
    }

    /// Consume exactly one still-current request only after a valid response is built.
    pub fn resolve(&mut self, token: &str, session: &str, turn: &str, now: u64, decision: Decision) -> Option<Value> {
        let entry = self.entries.get(token)?;
        if entry.session != session || entry.turn != turn || now < entry.started || now > entry.deadline { return None; }
        let response = codex_response(&entry.request, decision)?;
        let key = (entry.session.clone(), entry.turn.clone(), entry.request["id"].to_string());
        let deadline = entry.deadline;
        self.entries.remove(token);
        self.completed.insert(key, deadline);
        Some(response)
    }

    pub fn resolve_question(&mut self, token: &str, session: &str, turn: &str, now: u64, answers: &Value) -> Option<Value> {
        let entry = self.entries.get(token)?;
        if entry.session != session || entry.turn != turn || now < entry.started || now > entry.deadline { return None; }
        let response = codex_question_response(&entry.request, answers)?;
        let key = (entry.session.clone(), entry.turn.clone(), entry.request["id"].to_string());
        let deadline = entry.deadline;
        self.entries.remove(token);
        self.completed.insert(key, deadline);
        Some(response)
    }

    pub fn cancel(&mut self, token: &str) {
        if let Some(entry) = self.entries.remove(token) {
            self.completed.insert((entry.session, entry.turn, entry.request["id"].to_string()), entry.deadline);
        }
    }

    fn cancel_session(&mut self, session: &str) {
        let tokens: Vec<String> = self.entries.iter().filter(|(_, entry)| entry.session == session)
            .map(|(token, _)| token.clone()).collect();
        for token in tokens { self.cancel(&token); }
    }

    /// Observe only responses from the owning client, on this connection.
    /// The native UI can answer before the notch; never answer it twice.
    pub fn observe_native_reply(&mut self, message: &Value) {
        if message.get("method").is_some() { return; }
        let Some(id) = message.get("id").filter(|id| id.is_number() || id.is_string()) else { return; };
        let tokens: Vec<String> = self.entries.iter().filter(|(_, entry)| entry.request.get("id") == Some(id))
            .map(|(token, _)| token.clone()).collect();
        for token in tokens { self.cancel(&token); }
    }

    /// Clear requests when the provider resolves them elsewhere or ends the turn.
    pub fn observe_server_event(&mut self, message: &Value) {
        let Some(method) = message.get("method").and_then(Value::as_str) else { return; };
        let Some(params) = message.get("params") else { return; };
        let Some(session) = params.get("threadId").and_then(Value::as_str) else { return; };
        let tokens: Vec<String> = self.entries.iter().filter(|(_, entry)| {
            if entry.session != session { return false; }
            match method {
                "serverRequest/resolved" => params.get("requestId").is_some_and(|id| entry.request.get("id") == Some(id)),
                "turn/completed" => entry.turn.is_empty() || params.pointer("/turn/id").and_then(Value::as_str) == Some(entry.turn.as_str()),
                _ => false,
            }
        }).map(|(token, _)| token.clone()).collect();
        for token in tokens { self.cancel(&token); }
    }
}

pub(crate) fn request_preview(request: &Value) -> Option<Value> {
    if let Some(mut preview) = approval_preview(request) {
        preview.as_object_mut()?.insert("kind".into(), json!("approval"));
        return Some(preview);
    }
    let form = codex_question_form(request)?;
    Some(json!({"kind":"question", "method":"item/tool/requestUserInput", "details":request["params"], "questions":form}))
}

/// Preserve the complete question form; unsupported or secret forms remain
/// exclusively with the Desktop client.
fn codex_question_form(request: &Value) -> Option<Vec<Value>> {
    if request.get("method")?.as_str()? != "item/tool/requestUserInput" { return None; }
    let id = request.get("id")?;
    if !(id.is_number() || id.as_str().is_some_and(|id| !id.is_empty() && id.len() <= 256)) { return None; }
    let params = request.get("params")?.as_object()?;
    if serde_json::to_vec(params).ok()?.len() > 32_768 { return None; }
    let questions = params.get("questions")?.as_array()?;
    if questions.is_empty() || questions.len() > 3 { return None; }
    let mut ids = std::collections::HashSet::new();
    let mut form = Vec::new();
    for question in questions {
        let id = question.get("id")?.as_str()?;
        let text = question.get("question")?.as_str()?;
        if ["isSecret", "is_secret", "multiSelect", "multi_select", "isOther"].iter()
            .any(|key| question.get(*key).is_some_and(|value| !value.is_boolean())) { return None; }
        if id.trim().is_empty() || id.len() > 200 || !ids.insert(id)
            || text.trim().is_empty() || text.len() > 4000
            || question.get("isSecret").and_then(Value::as_bool) == Some(true)
            || question.get("is_secret").and_then(Value::as_bool) == Some(true)
            || question.get("multiSelect").and_then(Value::as_bool) == Some(true)
            || question.get("multi_select").and_then(Value::as_bool) == Some(true) { return None; }
        let mut options = Vec::new();
        if let Some(raw_options) = question.get("options").filter(|value| !value.is_null()) {
            let raw_options = raw_options.as_array()?;
            if raw_options.len() > 20 { return None; }
            for option in raw_options {
                let label = option.get("label")?.as_str()?;
                if label.trim().is_empty() || label.len() > 1000 { return None; }
                options.push(label);
            }
        }
        form.push(json!({"id":id,"question":text,"options":options,"isOther":question.get("isOther").and_then(Value::as_bool).unwrap_or(false)}));
    }
    Some(form)
}

pub fn codex_question_response(request: &Value, answers: &Value) -> Option<Value> {
    let form = codex_question_form(request)?;
    let answers = answers.as_array()?;
    if answers.len() != form.len() { return None; }
    let mut mapped = serde_json::Map::new();
    for (question, values) in form.iter().zip(answers) {
        let values = values.as_array()?;
        if values.len() != 1 { return None; }
        let value = values[0].as_str()?;
        if value.trim().is_empty() || value.len() > 2000 { return None; }
        let options = question.get("options")?.as_array()?;
        if !options.is_empty() && question["isOther"] != true && !options.iter().any(|option| option.as_str() == Some(value)) { return None; }
        mapped.insert(question["id"].as_str()?.to_owned(), json!({"answers":[value]}));
    }
    Some(json!({"id":request["id"],"result":{"answers":mapped}}))
}

/// Keep all provider parameters for display, or reject the preview instead of
/// silently truncating details that could change a user's decision.
pub fn approval_preview(request: &Value) -> Option<Value> {
    let method = request.get("method")?.as_str()?;
    let params = request.get("params")?.as_object()?;
    if serde_json::to_vec(params).ok()?.len() > 32_768 { return None; }
    let can_allow = codex_response(request, Decision::Allow).is_some();
    let can_deny = codex_response(request, Decision::Deny).is_some();
    if !can_allow && !can_deny { return None; }
    Some(json!({"method":method,"details":params,"canAllow":can_allow,"canDeny":can_deny}))
}

/// Returns no response for unknown methods or unsupported decision sets.
/// A positive answer is scoped to the current request, never a saved rule.
pub fn codex_response(request: &Value, decision: Decision) -> Option<Value> {
    let method = request.get("method")?.as_str()?;
    let id = request.get("id")?;
    if !(id.is_number() || id.as_str().is_some_and(|id| !id.is_empty() && id.len() <= 256)) { return None; }
    let params = request.get("params")?.as_object()?;
    let result = match method {
        "item/commandExecution/requestApproval" => {
            let available = match params.get("availableDecisions") {
                None | Some(Value::Null) => None,
                Some(Value::Array(values)) if values.len() <= 32 => Some(values),
                _ => return None,
            };
            let permits = |name: &str| available.map_or(true, |items| items.is_empty() || items.iter().any(|item| item.as_str() == Some(name)));
            let value = match decision {
                Decision::Allow if permits("accept") => "accept",
                Decision::Deny if permits("decline") => "decline",
                Decision::Deny if permits("cancel") => "cancel",
                _ => return None,
            };
            json!({"decision":value})
        }
        "item/fileChange/requestApproval" => json!({"decision":if decision == Decision::Allow { "accept" } else { "decline" }}),
        "item/permissions/requestApproval" => {
            let requested = params.get("permissions")?.as_object()?;
            json!({"permissions":if decision == Decision::Allow { Value::Object(requested.clone()) } else { json!({}) },"scope":"turn"})
        }
        "mcpServer/elicitation/request" => {
            let server = params.get("serverName")?.as_str()?;
            let meta = params.get("_meta")?.as_object()?;
            let schema = params.get("requestedSchema")?.as_object()?;
            if params.get("mode").and_then(Value::as_str) != Some("form")
                || !matches!(server, "cua_repl" | "node_repl" | "browser" | "browser-use" | "computer-use")
                || meta.get("codex_approval_kind").and_then(Value::as_str) != Some("mcp_tool_call")
                || meta.get("riskLevel").and_then(Value::as_str) == Some("high")
                || schema.get("type").and_then(Value::as_str) != Some("object")
                || !schema.get("properties")?.as_object()?.is_empty()
                || schema.get("required").is_some_and(|value| !value.as_array().is_some_and(Vec::is_empty)) { return None; }
            if decision == Decision::Allow { json!({"action":"accept","content":{}}) }
            else { json!({"action":"decline","content":null}) }
        }
        "execCommandApproval" | "applyPatchApproval" => {
            let value = match decision {
                Decision::Allow => json!("approved"),
                Decision::Deny => json!({"denied":{"rejection":"Rium Notch에서 거절됨"}}),
            };
            json!({"decision":value})
        }
        _ => return None,
    };
    Some(json!({"id":id,"result":result}))
}

/// Claude requires the original tool input on allow. A missing decision or
/// invalid input produces no hook output, leaving its own prompt in control.
pub fn claude_hook_response(tool_input: &Value, decision: Option<Decision>) -> Option<Value> {
    let input = tool_input.as_object()?;
    let result = match decision? {
        Decision::Allow => json!({"behavior":"allow","updatedInput":input}),
        Decision::Deny => json!({"behavior":"deny","message":"Rium Notch에서 거절됨"}),
    };
    Some(json!({"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":result}}))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn codex_decisions_stay_scoped_and_obey_available_choices() {
        let mut request = json!({"id":7,"method":"item/commandExecution/requestApproval",
            "params":{"availableDecisions":["accept","decline"]}});
        assert_eq!(codex_response(&request, Decision::Allow), Some(json!({"id":7,"result":{"decision":"accept"}})));
        request["params"]["availableDecisions"] = json!(["acceptForSession", "cancel"]);
        assert_eq!(codex_response(&request, Decision::Allow), None);
        assert_eq!(codex_response(&request, Decision::Deny), Some(json!({"id":7,"result":{"decision":"cancel"}})));
        request["params"]["availableDecisions"] = json!(["acceptForSession"]);
        assert_eq!(codex_response(&request, Decision::Deny), None);
    }

    #[test]
    fn permission_profiles_and_claude_inputs_are_not_broadened() {
        let permissions = json!({"network":{"enabled":true},"fileSystem":{"write":["/tmp/example"]}});
        let request = json!({"id":"a","method":"item/permissions/requestApproval","params":{"permissions":permissions}});
        let result = codex_response(&request, Decision::Allow).unwrap();
        assert_eq!(result["result"]["permissions"], request["params"]["permissions"]);
        assert_eq!(result["result"]["scope"], "turn");
        assert_eq!(codex_response(&request, Decision::Deny).unwrap()["result"]["permissions"], json!({}));
        let input = json!({"command":"echo hello"});
        assert_eq!(claude_hook_response(&input, Some(Decision::Allow)).unwrap()["hookSpecificOutput"]["decision"]["updatedInput"], input);
        assert_eq!(claude_hook_response(&input, None), None);
        assert_eq!(claude_hook_response(&json!("invalid"), Some(Decision::Allow)), None);
    }

    #[test]
    fn file_and_legacy_methods_have_distinct_shapes() {
        let file = json!({"id":1,"method":"item/fileChange/requestApproval","params":{}});
        assert_eq!(codex_response(&file, Decision::Deny).unwrap()["result"], json!({"decision":"decline"}));
        let legacy = json!({"id":2,"method":"execCommandApproval","params":{}});
        assert_eq!(codex_response(&legacy, Decision::Allow).unwrap()["result"], json!({"decision":"approved"}));
        assert!(codex_response(&json!({"id":3,"method":"unknown","params":{}}), Decision::Allow).is_none());
    }

    #[test]
    fn pending_requests_do_not_cross_turns_and_are_one_shot() {
        let mut pending = PendingApprovals::default();
        let request = json!({"id":7,"method":"item/fileChange/requestApproval",
            "params":{"threadId":"session-a","turnId":"turn-a"}});
        assert!(pending.insert("token-a", "session-a", "turn-a", request.clone(), 100, 500));
        assert!(!pending.insert("token-a", "session-a", "turn-a", request.clone(), 100, 500));
        assert!(!pending.insert("different-token", "session-a", "turn-a", request.clone(), 100, 500));
        assert!(pending.resolve("token-a", "session-b", "turn-a", 101, Decision::Allow).is_none());
        assert!(pending.resolve("token-a", "session-a", "turn-b", 101, Decision::Allow).is_none());
        assert!(pending.resolve("token-a", "session-a", "turn-a", 99, Decision::Allow).is_none());
        assert!(pending.resolve("token-a", "session-a", "turn-a", 101, Decision::Allow).is_some());
        assert!(pending.resolve("token-a", "session-a", "turn-a", 102, Decision::Allow).is_none());
        assert!(!pending.insert("token-b", "session-a", "turn-a", request.clone(), 102, 500));
        let mut other = request; other["id"] = json!(8);
        assert!(pending.insert("token-b", "session-a", "turn-a", other, 102, 500));
        assert!(pending.resolve("token-b", "session-a", "turn-a", 603, Decision::Allow).is_none());
    }

    #[test]
    fn cancelled_request_cannot_be_reinserted_before_expiry() {
        let mut pending = PendingApprovals::default();
        let request = json!({"id":1,"method":"item/fileChange/requestApproval",
            "params":{"threadId":"s","turnId":"t"}});
        assert!(pending.insert("one", "s", "t", request.clone(), 100, 100));
        pending.cancel("one");
        assert!(!pending.insert("two", "s", "t", request, 150, 100));
    }

    #[test]
    fn native_and_server_resolutions_clear_only_matching_requests() {
        let mut pending = PendingApprovals::default();
        let request = |id, session: &str, turn: &str| json!({"id":id,"method":"item/fileChange/requestApproval",
            "params":{"threadId":session,"turnId":turn}});
        assert!(pending.insert("one", "s", "t", request(1, "s", "t"), 1, 100));
        assert!(pending.insert("two", "s", "u", request(2, "s", "u"), 1, 100));
        assert!(pending.insert("three", "x", "v", request(3, "x", "v"), 1, 100));
        pending.observe_server_event(&json!({"method":"serverRequest/resolved","params":{"threadId":"wrong","requestId":1}}));
        pending.observe_native_reply(&json!({"id":1,"result":{"decision":"accept"}}));
        assert!(pending.resolve("one", "s", "t", 2, Decision::Deny).is_none());
        pending.observe_server_event(&json!({"method":"turn/completed","params":{"threadId":"s","turn":{"id":"u"}}}));
        assert!(pending.resolve("two", "s", "u", 2, Decision::Allow).is_none());
        assert!(pending.resolve("three", "x", "v", 2, Decision::Allow).is_some());
    }

    #[test]
    fn previews_are_complete_bounded_and_expire() {
        let mut pending = PendingApprovals::default();
        let request = json!({"id":1,"method":"item/commandExecution/requestApproval",
            "params":{"threadId":"s","turnId":"t","command":"echo hello",
                "additionalPermissions":{"network":{"enabled":true}},"availableDecisions":["accept","decline"]}});
        assert!(pending.insert("one", "s", "t", request.clone(), 100, 500));
        let preview = pending.previews(101);
        assert_eq!(preview.len(), 1);
        assert_eq!(preview[0]["details"], request["params"]);
        assert_eq!(preview[0]["canAllow"], true);
        assert!(pending.previews(601).is_empty());
        let mut oversized = request; oversized["params"]["command"] = json!("x".repeat(32_769));
        assert!(approval_preview(&oversized).is_none());
    }

    #[test]
    fn wire_keeps_one_winner_when_notch_and_native_both_answer() {
        let request = |id| json!({"id":id,"method":"item/fileChange/requestApproval",
            "params":{"threadId":"s","turnId":"t"}});
        let mut wire = ApprovalWire::default();
        assert!(wire.register("one", "s", "t", request(1), 1, 100));
        assert!(wire.claim("one", "s", "t", 2, Decision::Allow).is_some());
        assert!(!wire.forward_native(&json!({"id":1,"result":{"decision":"decline"}})));
        assert!(!wire.register("again", "s", "t", request(1), 3, 100));
        assert!(wire.register("two", "s", "t", request(2), 3, 100));
        assert!(wire.forward_native(&json!({"id":2,"result":{"decision":"decline"}})));
        assert!(wire.claim("two", "s", "t", 4, Decision::Allow).is_none());
    }

    #[test]
    fn native_questions_preserve_form_and_share_the_one_winner_rule() {
        let request = json!({"id":17,"method":"item/tool/requestUserInput", "params":{"threadId":"s","turnId":"t","questions":[
            {"id":"color","question":"색상?","isOther":false,"options":[{"label":"파랑","description":"짙은 파랑"}]},
            {"id":"note","question":"메모?","isOther":true,"options":[]}
        ]}});
        let mut wire = ApprovalWire::default();
        assert!(wire.register("question", "s", "t", request.clone(), 1, 100));
        assert_eq!(wire.previews(2)[0]["details"], request["params"]);
        assert!(wire.claim_question("question", "s", "t", 2, &json!([["빨강"],["hello"]])).is_none());
        let reply = wire.claim_question("question", "s", "t", 2, &json!([["파랑"],["hello"]])).unwrap();
        assert_eq!(reply["result"]["answers"], json!({"color":{"answers":["파랑"]},"note":{"answers":["hello"]}}));
        assert!(!wire.forward_native(&json!({"id":17,"result":{"answers":{}}})));
        assert!(wire.claim_question("question", "s", "t", 3, &json!([["파랑"],["hello"]])).is_none());
        let mut unsupported = request; unsupported["params"]["questions"][0]["isSecret"] = json!(true);
        assert!(codex_question_form(&unsupported).is_none());
    }

    #[test]
    fn native_elicitation_is_limited_to_empty_known_low_risk_forms() {
        let mut request = json!({"id":1,"method":"mcpServer/elicitation/request","params":{
            "threadId":"s", "mode":"form", "serverName":"cua_repl", "_meta":{"codex_approval_kind":"mcp_tool_call"},
            "requestedSchema":{"type":"object","properties":{},"required":[]}}});
        assert_eq!(codex_response(&request, Decision::Allow).unwrap()["result"], json!({"action":"accept","content":{}}));
        request["params"]["_meta"]["riskLevel"] = json!("high");
        assert!(codex_response(&request, Decision::Allow).is_none());
        request["params"]["_meta"]["riskLevel"] = json!("low");
        request["params"]["requestedSchema"]["properties"]["value"] = json!({"type":"string"});
        assert!(codex_response(&request, Decision::Allow).is_none());
    }
}
