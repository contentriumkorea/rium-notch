//! Bounded, fail-closed compatibility checks for the Desktop protocol examples.
//! Unsupported schema keywords or regex syntax never qualify a new version.
use regex::RegexBuilder;
use serde_json::{json, Value};

fn examples() -> Vec<(&'static str, Vec<Value>)> {
    let thread = "019fed43-f1c3-7550-974c-d48ffb9f732a";
    let requests = vec![
        json!({"id":1,"method":"initialize","params":{"clientInfo":{"name":"rium_compatibility","version":"1"},"capabilities":{"experimentalApi":true}}}),
        json!({"id":1,"method":"thread/loaded/list","params":{}}),
        json!({"id":1,"method":"thread/read","params":{"threadId":thread,"includeTurns":false}}),
        json!({"id":1,"method":"thread/turns/list","params":{"threadId":thread,"limit":2,"sortDirection":"desc","itemsView":"notLoaded"}}),
        json!({"id":1,"method":"turn/start","params":{"threadId":thread,"input":[{"type":"text","text":"fixture","text_elements":[]}]}}),
        json!({"id":1,"method":"turn/steer","params":{"threadId":thread,"expectedTurnId":"turn","input":[{"type":"text","text":"fixture","text_elements":[]}]}}),
    ];
    let server_requests = vec![
        json!({"id":1,"method":"item/commandExecution/requestApproval","params":{"itemId":"item","startedAtMs":1,"threadId":thread,"turnId":"turn","command":"fixture"}}),
        json!({"id":1,"method":"item/fileChange/requestApproval","params":{"itemId":"item","startedAtMs":1,"threadId":thread,"turnId":"turn"}}),
        json!({"id":1,"method":"item/permissions/requestApproval","params":{"cwd":"/tmp","itemId":"item","startedAtMs":1,"permissions":{},"threadId":thread,"turnId":"turn"}}),
        json!({"id":1,"method":"mcpServer/elicitation/request","params":{"serverName":"cua_repl","threadId":thread,"mode":"form","message":"fixture","requestedSchema":{"type":"object","properties":{}},"_meta":{"codex_approval_kind":"mcp_tool_call"}}}),
        json!({"id":1,"method":"item/tool/requestUserInput","params":{"isBlocking":true,"itemId":"item","threadId":thread,"turnId":"turn","questions":[{"id":"q","header":"Fixture","question":"Fixture?","options":[{"label":"A","description":"Fixture"}]}]}}),
    ];
    vec![
        ("ClientRequest", requests),
        ("ServerRequest", server_requests),
        ("ServerNotification", vec![json!({"method":"serverRequest/resolved","params":{"requestId":1,"threadId":thread}})]),
        ("CommandExecutionRequestApprovalResponse", vec![json!({"decision":"accept"}), json!({"decision":"decline"})]),
        ("FileChangeRequestApprovalResponse", vec![json!({"decision":"accept"}), json!({"decision":"decline"})]),
        ("PermissionsRequestApprovalResponse", vec![json!({"permissions":{},"scope":"turn"})]),
        ("McpServerElicitationRequestResponse", vec![json!({"action":"accept","content":{}}), json!({"action":"decline","content":null})]),
        ("ToolRequestUserInputResponse", vec![json!({"answers":{"q":{"answers":["A"]}}})]),
    ]
}

fn supported_keyword(key: &str) -> bool {
    matches!(key, "$schema" | "$id" | "$defs" | "definitions" | "$ref" | "title" | "description"
        | "default" | "examples" | "deprecated" | "readOnly" | "writeOnly" | "format" | "type"
        | "allOf" | "anyOf" | "oneOf" | "enum" | "const" | "properties" | "required"
        | "additionalProperties" | "items" | "minItems" | "maxItems" | "minLength" | "maxLength"
        | "pattern" | "minimum" | "maximum")
}
fn matches_type(kind: &str, value: &Value) -> bool {
    match kind {
        "null" => value.is_null(), "boolean" => value.is_boolean(), "object" => value.is_object(),
        "array" => value.is_array(), "string" => value.is_string(), "number" => value.is_number(),
        "integer" => value.as_i64().is_some() || value.as_u64().is_some()
            || value.as_f64().is_some_and(|number| number.is_finite() && number.fract() == 0.0),
        _ => false,
    }
}

fn pattern_matches(pattern: &str, value: &str) -> bool {
    // shortcut: Rust and JavaScript regex differ; reject non-ASCII and special
    // groups until an ECMAScript-compatible engine is available.
    if pattern.len() > 1024 || !pattern.is_ascii() || !value.is_ascii()
        || pattern.replace("(?:", "").contains("(?") || pattern.contains("\\p") || pattern.contains("\\P")
        || pattern.contains("&&") || pattern.contains("~~") || pattern.contains("--") { return false; }
    let mut escaped = false;
    let mut in_class = false;
    for character in pattern.chars() {
        if escaped {
            if !matches!(character, 'd' | 'D' | 's' | 'S' | 'w' | 'W' | 'b' | 'B' | '.' | '*' | '+' | '?' | '^' | '$' | '(' | ')' | '[' | ']' | '{' | '}' | '|' | '\\' | '/' | '-') { return false; }
            escaped = false;
        } else if character == '\\' { escaped = true; }
        else if character == '[' { if in_class { return false; } in_class = true; }
        else if character == ']' { if !in_class { return false; } in_class = false; }
    }
    if escaped || in_class { return false; }
    RegexBuilder::new(pattern).size_limit(1_000_000).dfa_size_limit(1_000_000).build()
        .is_ok_and(|regex| regex.is_match(value))
}

fn accepts(schema: &Value, value: &Value, root: &Value, depth: usize, budget: &mut usize) -> bool {
    if depth > 80 || *budget == 0 { return false; }
    *budget -= 1;
    if let Some(allowed) = schema.as_bool() { return allowed; }
    let Some(fields) = schema.as_object() else { return false; };
    if fields.keys().any(|key| !supported_keyword(key)) { return false; }
    if let Some(reference) = fields.get("$ref") {
        let Some(pointer) = reference.as_str().and_then(|value| value.strip_prefix('#')) else { return false; };
        if !pointer.starts_with('/') || !root.pointer(pointer).is_some_and(|target| accepts(target, value, root, depth + 1, budget)) { return false; }
    }
    for (name, mode) in [("allOf", 0), ("anyOf", 1), ("oneOf", 2)] {
        if let Some(raw) = fields.get(name) {
            let Some(schemas) = raw.as_array().filter(|schemas| !schemas.is_empty()) else { return false; };
            let mut matches = 0;
            for item in schemas { if accepts(item, value, root, depth + 1, budget) { matches += 1; } }
            if (mode == 0 && matches != schemas.len()) || (mode == 1 && matches == 0) || (mode == 2 && matches != 1) { return false; }
        }
    }
    if let Some(raw) = fields.get("enum") {
        if !raw.as_array().is_some_and(|items| items.contains(value)) { return false; }
    }
    if fields.get("const").is_some_and(|constant| constant != value) { return false; }
    if let Some(raw) = fields.get("type") {
        let matches = if let Some(kind) = raw.as_str() { matches_type(kind, value) }
            else if let Some(kinds) = raw.as_array().filter(|kinds| !kinds.is_empty()) {
                kinds.iter().all(|kind| kind.as_str().is_some_and(|kind| matches!(kind, "null" | "boolean" | "object" | "array" | "string" | "number" | "integer")))
                    && kinds.iter().any(|kind| kind.as_str().is_some_and(|kind| matches_type(kind, value)))
            } else { false };
        if !matches { return false; }
    }
    if let Some(object) = value.as_object() {
        let properties = match fields.get("properties") {
            Some(raw) => match raw.as_object() { Some(properties) => Some(properties), None => return false }, None => None,
        };
        if let Some(required) = fields.get("required") {
            let Some(required) = required.as_array() else { return false; };
            if required.iter().any(|key| key.as_str().map_or(true, |key| !object.contains_key(key))) { return false; }
        }
        for (key, item) in object {
            if let Some(property) = properties.and_then(|properties| properties.get(key)) {
                if !accepts(property, item, root, depth + 1, budget) { return false; }
            } else if let Some(extra) = fields.get("additionalProperties") {
                if !accepts(extra, item, root, depth + 1, budget) { return false; }
            }
        }
    }
    if let Some(array) = value.as_array() {
        if fields.get("minItems").is_some_and(|n| n.as_u64().map_or(true, |n| array.len() < n as usize))
            || fields.get("maxItems").is_some_and(|n| n.as_u64().map_or(true, |n| array.len() > n as usize)) { return false; }
        if let Some(items) = fields.get("items") {
            if array.iter().any(|item| !accepts(items, item, root, depth + 1, budget)) { return false; }
        }
    }
    if let Some(text) = value.as_str() {
        let length = text.encode_utf16().count();
        if fields.get("minLength").is_some_and(|n| n.as_u64().map_or(true, |n| length < n as usize))
            || fields.get("maxLength").is_some_and(|n| n.as_u64().map_or(true, |n| length > n as usize)) { return false; }
        if fields.get("pattern").is_some_and(|pattern| pattern.as_str().map_or(true, |pattern| !pattern_matches(pattern, text))) { return false; }
    }
    if let Some(number) = value.as_f64() {
        if fields.get("minimum").is_some_and(|minimum| minimum.as_f64().map_or(true, |minimum| number < minimum))
            || fields.get("maximum").is_some_and(|maximum| maximum.as_f64().map_or(true, |maximum| number > maximum)) { return false; }
    }
    true
}

/// The caller supplies generated schema documents; this function runs no CLI.
pub fn validate_schemas(mut read_schema: impl FnMut(&str) -> Option<Value>) -> bool {
    for (name, values) in examples() {
        let Some(schema) = read_schema(name) else { return false; };
        if serde_json::to_vec(&schema).map_or(true, |data| data.len() > 16 * 1024 * 1024) { return false; }
        for value in values {
            let mut budget = 50_000;
            if !accepts(&schema, &value, &schema, 0, &mut budget) { return false; }
        }
    }
    true
}

#[cfg(test)]
mod tests {
    use super::*;
    fn check(schema: &Value, value: &Value) -> bool { accepts(schema, value, schema, 0, &mut 50_000) }
    #[test]
    fn validates_references_objects_and_choice() {
        let schema = json!({"$defs":{"name":{"type":"string","pattern":"^[A-Z]+$"}},"type":"object",
            "properties":{"name":{"$ref":"#/$defs/name"},"mode":{"enum":["a","b"]}},
            "required":["name","mode"],"additionalProperties":false});
        assert!(check(&schema, &json!({"name":"ABC","mode":"a"})));
        assert!(!check(&schema, &json!({"name":"ABC","mode":"c"})));
        assert!(!check(&schema, &json!({"name":"ABC","mode":"a","extra":1})));
    }
    #[test]
    fn unknown_features_and_bad_patterns_fail_closed() {
        assert!(!check(&json!({"type":"string","not":{"const":"x"}}), &json!("y")));
        assert!(!check(&json!({"type":"string","pattern":"(?=x)x"}), &json!("x")));
        assert!(!check(&json!({"type":"string","pattern":"\\z"}), &json!("z")));
        assert!(!check(&json!({"type":["string","unsupported"]}), &json!("x")));
        assert!(!validate_schemas(|_| None));
    }
}
