//! Recheck the complete visible approval against the current request sources.
use serde_json::{json, Value};

pub fn submit(session: &str, channel: &str, shown: &Value, decision: &str) -> Result<Value, String> {
    if !matches!(channel, "claude" | "codex" | "desktop") || !matches!(decision, "allow" | "deny") || !shown.is_object() {
        return Err("음성 승인 요청을 확인할 수 없습니다".into());
    }
    let claude = channel == "claude";
    let hook = crate::claude_permission::strict_previews(session, !claude)?;
    let desktop = if claude { Vec::new() } else {
        let reply = crate::desktop_client::strict_previews(session)?;
        reply.get("requests").and_then(Value::as_array).ok_or("Desktop 요청을 확인할 수 없습니다")?.clone()
    };
    if hook.len() + desktop.len() != 1 { return Err("승인 대상이 변경되었거나 여러 개입니다".into()); }
    if channel == "desktop" {
        if desktop.first() != Some(shown) { return Err("표시한 Desktop 요청이 변경됐습니다".into()); }
        let request = shown.get("shown").filter(|value| value.is_object()).ok_or("Desktop 요청을 확인할 수 없습니다")?;
        if request.get("kind").and_then(Value::as_str) == Some("question") { return Err("질문에는 승인 음성을 사용할 수 없습니다".into()); }
        let allowed = if decision == "allow" { "canAllow" } else { "canDeny" };
        if request.get(allowed).and_then(Value::as_bool) != Some(true) { return Err("이 요청에 해당 응답을 사용할 수 없습니다".into()); }
        return crate::desktop_client::respond(session,
            shown.get("connection").and_then(Value::as_str).unwrap_or(""),
            shown.get("workspace").and_then(Value::as_str).unwrap_or(""), request, "approval", &json!(decision));
    }
    if hook.first() != Some(shown) { return Err("표시한 승인 요청이 변경됐습니다".into()); }
    let request = shown.get("request").filter(|value| value.is_object()).ok_or("승인 요청을 확인할 수 없습니다")?;
    if request.get("tool_name").and_then(Value::as_str) == Some("AskUserQuestion") { return Err("질문에는 승인 음성을 사용할 수 없습니다".into()); }
    let token = shown.get("token").and_then(Value::as_str).ok_or("승인 식별자를 확인할 수 없습니다")?;
    if claude { crate::claude_permission::decide(session, token, request, decision) }
    else { crate::claude_permission::decide_codex(session, token, request, decision) }
}
