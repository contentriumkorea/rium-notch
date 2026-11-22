//! Per-turn assistant message aggregation for Codex app-server notifications.
use regex::Regex;
use serde_json::{json, Value};
use std::ffi::{c_char, CString};
use std::sync::OnceLock;

const MAX_ITEMS: usize = 128;
const MAX_TEXT_BYTES: usize = 512 * 1024;

fn spoken_text(text: &str) -> String {
    static LINK: OnceLock<Regex> = OnceLock::new();
    static URL: OnceLock<Regex> = OnceLock::new();
    static PREFIX: OnceLock<Regex> = OnceLock::new();
    static FORMAT: OnceLock<Regex> = OnceLock::new();
    static PICTOGRAPH: OnceLock<Regex> = OnceLock::new();
    let pictograph = PICTOGRAPH.get_or_init(|| Regex::new(r"[\p{Emoji_Presentation}\p{Emoji_Modifier}\p{Extended_Pictographic}]").expect("fixed pictograph pattern"));
    let mut plain = String::with_capacity(text.len());
    for character in text.chars() {
        let code = character as u32;
        let special = matches!(code, 0x200d | 0xfe0f | 0x20e3 | 0x1f1e6..=0x1f1ff);
        let mut encoded = [0; 4];
        if special || (code > 0x21ff && pictograph.is_match(character.encode_utf8(&mut encoded))) { continue; }
        plain.push(character);
    }
    let links = LINK.get_or_init(|| Regex::new(r"\[([^\]]+)\]\([^)]*\)").expect("fixed link pattern"));
    let urls = URL.get_or_init(|| Regex::new(r"https?://\S+").expect("fixed URL pattern"));
    let prefixes = PREFIX.get_or_init(|| Regex::new(r"^\s*(#{1,6}|[-*•]|\d+\.)\s+").expect("fixed prefix pattern"));
    let format = FORMAT.get_or_init(|| Regex::new(r"[*_`]+").expect("fixed format pattern"));
    let text = links.replace_all(&plain, "$1");
    let text = urls.replace_all(&text, "");
    let text = prefixes.replace(&text, "");
    let text = format.replace_all(&text, "");
    text.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// Tracks the already-spoken prefix of one streamed assistant message.
#[derive(Default)]
pub struct SpeechChunks {
    text: String,
    committed: usize,
    invalidated: bool,
}

impl SpeechChunks {
    fn consume(&mut self, text: &str, complete: bool) -> Option<Vec<String>> {
        if self.invalidated || text.len() > MAX_TEXT_BYTES { return None; }
        if !text.starts_with(&self.text[..self.committed]) {
            self.invalidated = true;
            return None;
        }
        self.text = text.to_owned();
        let mut output = Vec::new();
        loop {
            let tail = &self.text[self.committed..];
            let mut comma = None;
            let mut boundary = None;
            for (count, (index, character)) in tail.char_indices().enumerate() {
                let after = index + character.len_utf8();
                let next = tail[after..].chars().next();
                let numeric_list = character == '.' && !tail[..index].trim().is_empty()
                    && tail[..index].trim().chars().all(|value| value.is_ascii_digit());
                if character == '\n' || (!numeric_list && matches!(character, '.' | '!' | '?' | '…' | ';' | ':')
                    && next.is_some_and(char::is_whitespace)) {
                    boundary = Some(after);
                    break;
                }
                if character == ',' && next.is_some_and(char::is_whitespace) { comma = Some(after); }
                if count + 1 >= 160 && comma.is_some() { boundary = comma; break; }
            }
            let Some(end) = boundary.or_else(|| if complete && !tail.is_empty() { Some(tail.len()) } else { None }) else { break; };
            let sentence = spoken_text(tail[..end].trim());
            if sentence.chars().any(char::is_alphanumeric) { output.push(sentence); }
            self.committed += end;
        }
        Some(output)
    }
}

#[no_mangle]
pub extern "C" fn rium_assistant_speech_chunks_new() -> *mut SpeechChunks {
    Box::into_raw(Box::new(SpeechChunks::default()))
}

#[no_mangle]
pub unsafe extern "C" fn rium_assistant_speech_chunks_consume(state: *mut SpeechChunks, data: *const u8, len: usize, complete: i32) -> *mut c_char {
    if state.is_null() || data.is_null() || len > MAX_TEXT_BYTES || !(0..=1).contains(&complete) { return std::ptr::null_mut(); }
    let Ok(text) = std::str::from_utf8(std::slice::from_raw_parts(data, len)) else { return std::ptr::null_mut(); };
    let result = match (*state).consume(text, complete == 1) {
        Some(chunks) => json!({"chunks": chunks, "invalidated": false}),
        None => json!({"chunks": [], "invalidated": true}),
    };
    CString::new(result.to_string()).map_or(std::ptr::null_mut(), CString::into_raw)
}

#[no_mangle]
pub unsafe extern "C" fn rium_assistant_speech_chunks_free(state: *mut SpeechChunks) {
    if !state.is_null() { drop(Box::from_raw(state)); }
}

#[derive(Debug, PartialEq, Eq)]
pub struct AssistantMessage {
    pub id: String,
    pub text: String,
    complete: bool,
}

#[no_mangle]
pub unsafe extern "C" fn rium_assistant_stream_new(thread: *const u8, thread_len: usize, turn: *const u8, turn_len: usize) -> *mut AssistantStream {
    if thread.is_null() || turn.is_null() || thread_len == 0 || turn_len == 0 || thread_len > 256 || turn_len > 256 { return std::ptr::null_mut(); }
    let Ok(thread) = std::str::from_utf8(std::slice::from_raw_parts(thread, thread_len)) else { return std::ptr::null_mut(); };
    let Ok(turn) = std::str::from_utf8(std::slice::from_raw_parts(turn, turn_len)) else { return std::ptr::null_mut(); };
    AssistantStream::new(thread, turn).map_or(std::ptr::null_mut(), |stream| Box::into_raw(Box::new(stream)))
}

/// Caller frees the returned JSON with rium_assistant_string_free.
#[no_mangle]
pub unsafe extern "C" fn rium_assistant_stream_consume(stream: *mut AssistantStream, data: *const u8, len: usize) -> *mut c_char {
    if stream.is_null() || data.is_null() || len == 0 || len > 2 * 1024 * 1024 { return std::ptr::null_mut(); }
    let Ok(event) = serde_json::from_slice::<Value>(std::slice::from_raw_parts(data, len)) else { return std::ptr::null_mut(); };
    let stream = &mut *stream;
    let result = match stream.consume(&event) {
        Ok(changed) => {
            let outcome = match stream.outcome { Some(TurnOutcome::Completed) => "completed", Some(TurnOutcome::Failed) => "failed", Some(TurnOutcome::Interrupted) => "interrupted", None => "" };
            let messages: Vec<_> = stream.messages.iter().map(|message| json!({"id": &message.id, "text": &message.text, "complete": message.complete})).collect();
            let tool_started = changed && event.get("method").and_then(Value::as_str) == Some("item/started");
            json!({"changed": changed, "messages": messages, "outcome": outcome, "toolRunning": !stream.active_tools.is_empty(), "toolStarted": tool_started})
        }
        Err(error) => json!({"error": error}),
    };
    CString::new(result.to_string()).map_or(std::ptr::null_mut(), CString::into_raw)
}

#[no_mangle]
pub unsafe extern "C" fn rium_assistant_stream_free(stream: *mut AssistantStream) {
    if !stream.is_null() { drop(Box::from_raw(stream)); }
}

#[no_mangle]
pub unsafe extern "C" fn rium_assistant_string_free(value: *mut c_char) {
    if !value.is_null() { drop(CString::from_raw(value)); }
}

#[no_mangle]
pub unsafe extern "C" fn rium_assistant_request_preview(data: *const u8, len: usize) -> *mut c_char {
    if data.is_null() || len == 0 || len > 65_536 { return std::ptr::null_mut(); }
    let Ok(request) = serde_json::from_slice::<Value>(std::slice::from_raw_parts(data, len)) else { return std::ptr::null_mut(); };
    let Some(preview) = crate::agent_approval::request_preview(&request) else { return std::ptr::null_mut(); };
    CString::new(preview.to_string()).map_or(std::ptr::null_mut(), CString::into_raw)
}

/// action: 0 = deny, 1 = allow, 2 = submit the supplied question answers.
#[no_mangle]
pub unsafe extern "C" fn rium_assistant_request_response(data: *const u8, len: usize, action: i32, answers: *const u8, answers_len: usize) -> *mut c_char {
    if data.is_null() || len == 0 || len > 65_536 || answers_len > 65_536 { return std::ptr::null_mut(); }
    let Ok(request) = serde_json::from_slice::<Value>(std::slice::from_raw_parts(data, len)) else { return std::ptr::null_mut(); };
    let response = match action {
        0 => crate::agent_approval::codex_response(&request, crate::agent_approval::Decision::Deny),
        1 => crate::agent_approval::codex_response(&request, crate::agent_approval::Decision::Allow),
        2 if !answers.is_null() && answers_len > 0 => serde_json::from_slice::<Value>(std::slice::from_raw_parts(answers, answers_len)).ok()
            .and_then(|value| crate::agent_approval::codex_question_response(&request, &value)),
        _ => None,
    };
    response.and_then(|value| CString::new(value.to_string()).ok()).map_or(std::ptr::null_mut(), CString::into_raw)
}

fn recovered_turn(input: &Value) -> Option<Value> {
    let thread_id = identifier(input.get("threadId")?.as_str())?;
    let turn_id = identifier(input.get("turnId").and_then(Value::as_str));
    let client_id = identifier(input.get("clientId").and_then(Value::as_str));
    if turn_id.is_none() && client_id.is_none() { return None; }
    let thread = input.pointer("/response/thread")?;
    if thread.get("id")?.as_str()? != thread_id || thread.pointer("/status/type")?.as_str()? != "idle" { return None; }
    let turns = thread.get("turns")?.as_array()?;
    if turn_id.is_none() && turns.iter().any(|turn| turn.get("items").and_then(Value::as_array).is_none()
        || turn.get("itemsView").is_some_and(|view| view.as_str() != Some("full"))) { return None; }
    if turn_id.is_none() && turns.iter().flat_map(|turn| turn.get("items").and_then(Value::as_array).into_iter().flatten())
        .filter(|item| item.get("type").and_then(Value::as_str) == Some("userMessage") && item.get("clientId").and_then(Value::as_str) == client_id).count() != 1 { return None; }
    let mut matching = turns.iter().filter(|turn| {
        if let Some(id) = turn_id { return turn.get("id").and_then(Value::as_str) == Some(id); }
        turn.get("items").and_then(Value::as_array).is_some_and(|items| items.iter().filter(|item| {
            item.get("type").and_then(Value::as_str) == Some("userMessage") && item.get("clientId").and_then(Value::as_str) == client_id
        }).count() == 1)
    });
    let turn = matching.next()?;
    if matching.next().is_some() { return None; }
    let recovered_id = identifier(turn.get("id").and_then(Value::as_str))?;
    let outcome = turn.get("status")?.as_str()?;
    if !matches!(outcome, "completed" | "failed" | "interrupted") { return None; }
    // Older app-server versions omit itemsView when includeTurns is true.
    if turn.get("itemsView").is_some_and(|view| view.as_str() != Some("full")) { return None; }
    let items = turn.get("items")?.as_array()?;
    let mut messages = Vec::new();
    let mut ids = std::collections::HashSet::new();
    let mut total = 0usize;
    for item in items.iter().filter(|item| item.get("type").and_then(Value::as_str) == Some("agentMessage")) {
        let id = identifier(item.get("id").and_then(Value::as_str))?;
        let text = item.get("text")?.as_str()?;
        total = total.checked_add(text.len())?;
        if !ids.insert(id) || messages.len() >= MAX_ITEMS || total > MAX_TEXT_BYTES { return None; }
        messages.push(json!({"id":id,"text":text}));
    }
    Some(json!({"turnId":recovered_id,"outcome":outcome,"messages":messages}))
}

#[no_mangle]
pub unsafe extern "C" fn rium_assistant_recover_turn(data: *const u8, len: usize) -> *mut c_char {
    if data.is_null() || len == 0 || len > 2 * 1024 * 1024 { return std::ptr::null_mut(); }
    let Ok(input) = serde_json::from_slice::<Value>(std::slice::from_raw_parts(data, len)) else { return std::ptr::null_mut(); };
    recovered_turn(&input).and_then(|value| CString::new(value.to_string()).ok()).map_or(std::ptr::null_mut(), CString::into_raw)
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TurnOutcome { Completed, Failed, Interrupted }

pub struct AssistantStream {
    thread: String,
    turn: String,
    pub messages: Vec<AssistantMessage>,
    pub outcome: Option<TurnOutcome>,
    active_tools: std::collections::HashSet<String>,
    completed_tools: std::collections::VecDeque<String>,
}

fn identifier(value: Option<&str>) -> Option<&str> {
    value.filter(|value| !value.is_empty() && value.len() <= 256)
}

impl AssistantStream {
    pub fn new(thread: &str, turn: &str) -> Option<Self> {
        identifier(Some(thread))?;
        identifier(Some(turn))?;
        Some(Self { thread: thread.into(), turn: turn.into(), messages: Vec::new(), outcome: None,
                    active_tools: std::collections::HashSet::new(), completed_tools: std::collections::VecDeque::new() })
    }

    /// Returns true only when an event changed this turn's visible state.
    pub fn consume(&mut self, event: &Value) -> Result<bool, &'static str> {
        if self.outcome.is_some() { return Ok(false); }
        let Some(method) = event.get("method").and_then(Value::as_str) else { return Ok(false); };
        let params = &event["params"];
        if params.get("threadId").and_then(Value::as_str) != Some(self.thread.as_str()) { return Ok(false); }
        if method == "turn/completed" {
            let turn = &params["turn"];
            if turn.get("id").and_then(Value::as_str) != Some(self.turn.as_str()) { return Ok(false); }
            self.outcome = Some(match turn.get("status").and_then(Value::as_str) {
                Some("completed") => TurnOutcome::Completed,
                Some("failed") => TurnOutcome::Failed,
                Some("interrupted") => TurnOutcome::Interrupted,
                _ => return Err("알 수 없는 작업 종료 상태입니다"),
            });
            if self.outcome == Some(TurnOutcome::Completed) {
                for message in &mut self.messages { message.complete = true; }
            }
            self.active_tools.clear(); self.completed_tools.clear();
            return Ok(true);
        }
        if params.get("turnId").and_then(Value::as_str) != Some(self.turn.as_str()) { return Ok(false); }
        if matches!(method, "item/started" | "item/completed")
            && matches!(params.pointer("/item/type").and_then(Value::as_str),
                Some("commandExecution" | "fileChange" | "mcpToolCall" | "dynamicToolCall" | "webSearch" | "collabAgentToolCall")) {
            let Some(id) = identifier(params.pointer("/item/id").and_then(Value::as_str)) else { return Ok(false); };
            if method == "item/completed" {
                let removed = self.active_tools.remove(id);
                if !self.completed_tools.iter().any(|completed| completed == id) {
                    // shortcut: very old completions can be replayed after 128 newer tools; raise the bound if observed.
                    if self.completed_tools.len() == MAX_ITEMS { self.completed_tools.pop_front(); }
                    self.completed_tools.push_back(id.to_owned());
                }
                return Ok(removed);
            }
            if self.completed_tools.iter().any(|completed| completed == id)
                || self.active_tools.contains(id) || self.active_tools.len() >= MAX_ITEMS { return Ok(false); }
            self.active_tools.insert(id.to_owned());
            return Ok(true);
        }
        let (id, text, completed) = match method {
            "item/agentMessage/delta" => (identifier(params.get("itemId").and_then(Value::as_str)), params.get("delta").and_then(Value::as_str), false),
            "item/completed" if params.pointer("/item/type").and_then(Value::as_str) == Some("agentMessage") =>
                (identifier(params.pointer("/item/id").and_then(Value::as_str)), params.pointer("/item/text").and_then(Value::as_str), true),
            _ => return Ok(false),
        };
        let (Some(id), Some(text)) = (id, text) else { return Ok(false); };
        let index = self.messages.iter().position(|message| message.id == id);
        if index.is_none() && self.messages.len() >= MAX_ITEMS { return Err("응답 항목이 너무 많습니다"); }
        if index.is_some_and(|index| self.messages[index].complete) { return Ok(false); }
        let total: usize = self.messages.iter().map(|message| message.text.len()).sum();
        let prior = index.map_or(0, |index| self.messages[index].text.len());
        let next = if completed { total.saturating_sub(prior).saturating_add(text.len()) } else { total.saturating_add(text.len()) };
        if next > MAX_TEXT_BYTES { return Err("응답 내용이 너무 깁니다"); }
        let index = match index {
            Some(index) => index,
            None => { self.messages.push(AssistantMessage { id: id.into(), text: String::new(), complete: false }); self.messages.len() - 1 }
        };
        let message = &mut self.messages[index];
        if completed { message.text.clear(); message.text.push_str(text); message.complete = true; }
        else { message.text.push_str(text); }
        Ok(true)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn spoken_text_cleans_links_urls_lists_and_pictographs() {
        assert_eq!(spoken_text("## **안내** [문서](https://example.com/a) 😊"), "안내 문서");
        assert_eq!(spoken_text("1. 경로 https://example.com 확인"), "경로 확인");
        assert_eq!(spoken_text("숫자 123과 금액 1,000원 👍🏽"), "숫자 123과 금액 1,000원");
        assert_eq!(spoken_text("가족 👨‍👩‍👧‍👦 좋아요 🇰🇷"), "가족 좋아요");
        let mut list = SpeechChunks::default();
        assert_eq!(list.consume("1. 첫 항목", false), Some(vec![]));
        assert_eq!(list.consume("1. 첫 항목. 다음", false), Some(vec!["첫 항목.".into()]));
        let mut pictographs = SpeechChunks::default();
        assert_eq!(pictographs.consume("😊", true), Some(vec![]));
    }

    #[test]
    fn speech_chunks_stream_once_and_reject_rewritten_spoken_prefix() {
        let mut chunks = SpeechChunks::default();
        assert_eq!(chunks.consume("첫 문장입니다.", false), Some(vec![]));
        assert_eq!(chunks.consume("첫 문장입니다. 다음", false), Some(vec!["첫 문장입니다.".into()]));
        assert_eq!(chunks.consume("첫 문장입니다. 다음", false), Some(vec![]));
        assert_eq!(chunks.consume("첫 문장입니다. 다음 문장!", true), Some(vec!["다음 문장!".into()]));
        assert_eq!(chunks.consume("첫 문장이 수정됨. 다음 문장!", true), None);
        assert_eq!(chunks.consume("첫 문장입니다. 다음 문장!", true), None);
        let mut lines = SpeechChunks::default();
        assert_eq!(lines.consume("첫 줄\n두 번째", false), Some(vec!["첫 줄".into()]));
        assert_eq!(lines.consume("첫 줄\n두 번째", true), Some(vec!["두 번째".into()]));
        let mut decimal = SpeechChunks::default();
        assert_eq!(decimal.consume("3.14 입니다", false), Some(vec![]));
        assert_eq!(decimal.consume("3.14 입니다", true), Some(vec!["3.14 입니다".into()]));
        let mut rewritten = SpeechChunks::default();
        assert_eq!(rewritten.consume("초안", false), Some(vec![]));
        assert_eq!(rewritten.consume("완성된 문장", true), Some(vec!["완성된 문장".into()]));
        let mut long = SpeechChunks::default();
        let prefix = "가".repeat(80) + ", ";
        let text = prefix.clone() + &"나".repeat(80);
        assert_eq!(long.consume(&text, false), Some(vec![prefix.trim().to_owned()]));
    }

    #[test]
    fn ffi_reports_each_valid_new_tool_start() {
        let stream = Box::into_raw(Box::new(AssistantStream::new("thread", "turn").unwrap()));
        let read = |event: Value| unsafe {
            let bytes = event.to_string().into_bytes();
            let output = rium_assistant_stream_consume(stream, bytes.as_ptr(), bytes.len());
            assert!(!output.is_null());
            let result: Value = serde_json::from_str(std::ffi::CStr::from_ptr(output).to_str().unwrap()).unwrap();
            rium_assistant_string_free(output);
            result
        };
        let start = |thread, id| json!({"method":"item/started","params":{"threadId":thread,"turnId":"turn","item":{"id":id,"type":"webSearch"}}});
        assert_eq!(read(start("other", "a"))["toolStarted"], false);
        assert_eq!(read(start("thread", "a"))["toolStarted"], true);
        assert_eq!(read(start("thread", "a"))["toolStarted"], false);
        assert_eq!(read(start("thread", "b"))["toolStarted"], true);
        unsafe { rium_assistant_stream_free(stream); }
    }

    #[test]
    fn tracks_only_matching_active_tools_and_clears_on_completion() {
        let mut stream = AssistantStream::new("thread", "turn").unwrap();
        let tool = |method: &str, thread: &str, turn: &str, id: &str, kind: &str| json!({"method":method,"params":{"threadId":thread,"turnId":turn,"item":{"id":id,"type":kind}}});
        assert!(!stream.consume(&tool("item/started", "other", "turn", "a", "commandExecution")).unwrap());
        assert!(!stream.consume(&tool("item/started", "thread", "other", "a", "commandExecution")).unwrap());
        assert!(!stream.consume(&tool("item/started", "thread", "turn", "a", "agentMessage")).unwrap());
        assert!(stream.consume(&tool("item/started", "thread", "turn", "a", "commandExecution")).unwrap());
        assert!(!stream.consume(&tool("item/started", "thread", "turn", "a", "commandExecution")).unwrap());
        assert!(stream.consume(&tool("item/started", "thread", "turn", "b", "mcpToolCall")).unwrap());
        assert!(stream.consume(&tool("item/completed", "thread", "turn", "a", "commandExecution")).unwrap());
        assert!(!stream.consume(&tool("item/started", "thread", "turn", "a", "commandExecution")).unwrap());
        assert!(!stream.consume(&tool("item/completed", "thread", "turn", "early", "webSearch")).unwrap());
        assert!(!stream.consume(&tool("item/started", "thread", "turn", "early", "webSearch")).unwrap());
        assert_eq!(stream.active_tools.len(), 1);
        assert!(stream.consume(&json!({"method":"turn/completed","params":{"threadId":"thread","turn":{"id":"turn","status":"completed"}}})).unwrap());
        assert!(stream.active_tools.is_empty() && stream.completed_tools.is_empty());
        assert!(!stream.consume(&tool("item/started", "thread", "turn", "c", "webSearch")).unwrap());
        let mut bounded = AssistantStream::new("thread", "turn").unwrap();
        for index in 0..=MAX_ITEMS {
            assert!(!bounded.consume(&tool("item/completed", "thread", "turn", &index.to_string(), "webSearch")).unwrap());
        }
        assert_eq!(bounded.completed_tools.len(), MAX_ITEMS);
        assert!(!bounded.consume(&tool("item/started", "thread", "turn", &MAX_ITEMS.to_string(), "webSearch")).unwrap());
        assert!(bounded.consume(&tool("item/started", "thread", "turn", "0", "webSearch")).unwrap());
    }

    #[test]
    fn isolates_turns_and_reconciles_stream_with_final_message() {
        let mut stream = AssistantStream::new("thread", "turn").unwrap();
        let delta = |thread, turn, item, text| json!({"method":"item/agentMessage/delta", "params":{"threadId":thread,"turnId":turn,"itemId":item,"delta":text}});
        assert!(!stream.consume(&delta("other", "turn", "one", "wrong")).unwrap());
        assert!(!stream.consume(&delta("thread", "old", "one", "wrong")).unwrap());
        assert!(stream.consume(&delta("thread", "turn", "one", "안")).unwrap());
        assert!(stream.consume(&delta("thread", "turn", "one", "녕")).unwrap());
        assert!(stream.consume(&json!({"method":"item/completed","params":{"threadId":"thread","turnId":"turn","item":{"type":"agentMessage","id":"one","text":"안녕!"}}})).unwrap());
        assert_eq!(stream.messages[0].text, "안녕!");
        assert!(!stream.consume(&delta("thread", "turn", "one", "duplicate")).unwrap());
        assert!(stream.consume(&json!({"method":"turn/completed","params":{"threadId":"thread","turn":{"id":"turn","status":"failed"}}})).unwrap());
        assert_eq!(stream.outcome, Some(TurnOutcome::Failed));
        assert!(!stream.consume(&delta("thread", "turn", "two", "late")).unwrap());
    }

    #[test]
    fn rejects_oversized_content_without_changing_the_message() {
        let mut stream = AssistantStream::new("thread", "turn").unwrap();
        let event = |text: &str| json!({"method":"item/agentMessage/delta","params":{"threadId":"thread","turnId":"turn","itemId":"one","delta":text}});
        stream.consume(&event("ok")).unwrap();
        assert!(stream.consume(&event(&"x".repeat(MAX_TEXT_BYTES))).is_err());
        assert_eq!(stream.messages[0].text, "ok");
        assert!(AssistantStream::new("", "turn").is_none());
    }

    #[test]
    fn completed_turn_finalizes_streamed_messages_but_failure_keeps_them_partial() {
        let delta = json!({"method":"item/agentMessage/delta","params":{"threadId":"thread","turnId":"turn","itemId":"one","delta":"hello"}});
        for (status, expected) in [("completed", true), ("failed", false), ("interrupted", false)] {
            let mut stream = AssistantStream::new("thread", "turn").unwrap();
            stream.consume(&delta).unwrap();
            assert!(!stream.messages[0].complete);
            stream.consume(&json!({"method":"turn/completed","params":{"threadId":"thread","turn":{"id":"turn","status":status}}})).unwrap();
            assert_eq!(stream.messages[0].complete, expected);
            assert_eq!(stream.messages[0].text, "hello");
        }
    }

    #[test]
    fn ffi_returns_owned_snapshot_for_one_matching_turn() {
        unsafe {
            let handle = rium_assistant_stream_new(b"thread".as_ptr(), 6, b"turn".as_ptr(), 4);
            assert!(!handle.is_null());
            let event = br#"{"method":"item/agentMessage/delta","params":{"threadId":"thread","turnId":"turn","itemId":"one","delta":"hello"}}"#;
            let snapshot = rium_assistant_stream_consume(handle, event.as_ptr(), event.len());
            assert!(!snapshot.is_null());
            let data: Value = serde_json::from_slice(std::ffi::CStr::from_ptr(snapshot).to_bytes()).unwrap();
            assert_eq!(data["messages"][0]["text"], "hello");
            assert_eq!(data["messages"][0]["complete"], false);
            rium_assistant_string_free(snapshot);
            let completed = br#"{"method":"item/completed","params":{"threadId":"thread","turnId":"turn","item":{"type":"agentMessage","id":"one","text":"hello"}}}"#;
            let snapshot = rium_assistant_stream_consume(handle, completed.as_ptr(), completed.len());
            assert!(!snapshot.is_null());
            let data: Value = serde_json::from_slice(std::ffi::CStr::from_ptr(snapshot).to_bytes()).unwrap();
            assert_eq!(data["messages"][0]["complete"], true);
            rium_assistant_string_free(snapshot);
            rium_assistant_stream_free(handle);
        }
    }

    #[test]
    fn ffi_request_decisions_use_the_original_validation() {
        unsafe {
            let request = br#"{"id":7,"method":"item/commandExecution/requestApproval","params":{"availableDecisions":["cancel"]}}"#;
            let preview = rium_assistant_request_preview(request.as_ptr(), request.len());
            assert!(!preview.is_null());
            let value: Value = serde_json::from_slice(std::ffi::CStr::from_ptr(preview).to_bytes()).unwrap();
            assert_eq!(value["canAllow"], false);
            assert_eq!(value["canDeny"], true);
            rium_assistant_string_free(preview);
            assert!(rium_assistant_request_response(request.as_ptr(), request.len(), 1, std::ptr::null(), 0).is_null());
            let reply = rium_assistant_request_response(request.as_ptr(), request.len(), 0, std::ptr::null(), 0);
            assert!(!reply.is_null());
            let value: Value = serde_json::from_slice(std::ffi::CStr::from_ptr(reply).to_bytes()).unwrap();
            assert_eq!(value["result"]["decision"], "cancel");
            rium_assistant_string_free(reply);
        }
    }

    #[test]
    fn recovery_requires_the_exact_complete_idle_turn() {
        let mut input = json!({"threadId":"thread","turnId":"turn","response":{"thread":{"id":"thread","status":{"type":"idle"},"turns":[{"id":"turn","status":"completed","itemsView":"full","items":[{"type":"agentMessage","id":"one","text":"answer"}]}]}}});
        assert_eq!(recovered_turn(&input).unwrap()["messages"][0]["text"], "answer");
        input["response"]["thread"]["turns"][0]["itemsView"] = json!("summary");
        assert!(recovered_turn(&input).is_none());
        input["response"]["thread"]["turns"][0]["itemsView"] = json!("full");
        input["response"]["thread"]["status"]["type"] = json!("active");
        assert!(recovered_turn(&input).is_none());
        input["response"]["thread"]["status"]["type"] = json!("idle");
        input["turnId"] = json!("different");
        assert!(recovered_turn(&input).is_none());
    }

    #[test]
    fn recovery_without_turn_id_requires_unique_client_id_and_full_items() {
        let mut input = json!({"threadId":"thread","clientId":"client","response":{"thread":{"id":"thread","status":{"type":"idle"},"turns":[{"id":"turn","status":"completed","itemsView":"full","items":[{"type":"userMessage","clientId":"client"},{"type":"agentMessage","id":"answer","text":"done"}]}]}}});
        assert_eq!(recovered_turn(&input).unwrap()["turnId"], "turn");
        input["clientId"] = json!("other");
        assert!(recovered_turn(&input).is_none());
        input["clientId"] = json!("client");
        input["response"]["thread"]["turns"].as_array_mut().unwrap().push(json!({"id":"other","status":"completed","itemsView":"full","items":[{"type":"userMessage","clientId":"client"}]}));
        assert!(recovered_turn(&input).is_none());
        input["response"]["thread"]["turns"].as_array_mut().unwrap().pop();
        input["response"]["thread"]["turns"][0]["itemsView"] = json!("summary");
        assert!(recovered_turn(&input).is_none());
    }

}
