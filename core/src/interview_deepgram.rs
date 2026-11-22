//! Assemble Deepgram streaming results in memory; neither audio nor text is persisted.
use serde_json::{json, Value};
use std::ffi::{c_char, CString};

const MAX_MESSAGE: usize = 65_536;
// Keep the assembled text within the interview transcript's per-line limit.
const MAX_UTTERANCE: usize = 8_192;

#[derive(Debug, PartialEq, Eq)]
enum Update { Ignore, Text { text: String, finished: bool }, Error }

#[derive(Default)]
pub struct DeepgramUtterance { committed: String, interim: String }

impl DeepgramUtterance {
    fn push(&mut self, message: &[u8]) -> Update {
        if message.len() > MAX_MESSAGE { return Update::Error; }
        let Ok(value) = serde_json::from_slice::<Value>(message) else { return Update::Error; };
        match value.get("type").and_then(Value::as_str) {
            Some("Results") => (),
            Some("Error") => return Update::Error,
            Some(_) => return Update::Ignore,
            None => return Update::Error,
        }
        let Some(is_final) = value.get("is_final").and_then(Value::as_bool) else { return Update::Error; };
        let Some(speech_final) = value.get("speech_final").and_then(Value::as_bool) else { return Update::Error; };
        let Some(fragment) = value.pointer("/channel/alternatives/0/transcript").and_then(Value::as_str) else { return Update::Error; };
        let fragment = fragment.trim();
        if fragment.contains('\0') { return Update::Error; }
        // A segment may finalize empty before the utterance itself ends.
        let fragment = if (is_final || speech_final) && fragment.is_empty() { self.interim.as_str() } else { fragment };
        let separator = usize::from(!self.committed.is_empty() && !fragment.is_empty());
        if self.committed.len().saturating_add(separator).saturating_add(fragment.len()) > MAX_UTTERANCE { return Update::Error; }
        let mut text = self.committed.clone();
        if separator != 0 { text.push(' '); }
        text.push_str(fragment);
        if is_final { self.committed = text.clone(); self.interim.clear(); }
        else { self.interim = fragment.to_owned(); }
        if speech_final { self.committed.clear(); self.interim.clear(); }
        if text.is_empty() { Update::Ignore } else { Update::Text { text, finished: speech_final } }
    }
}

/// Handles are confined to a single caller queue and must not be used concurrently.
#[no_mangle]
pub extern "C" fn rium_deepgram_new() -> *mut DeepgramUtterance {
    Box::into_raw(Box::new(DeepgramUtterance::default()))
}

#[no_mangle]
pub unsafe extern "C" fn rium_deepgram_free(handle: *mut DeepgramUtterance) {
    if !handle.is_null() { drop(Box::from_raw(handle)); }
}

/// Caller frees the returned JSON using rium_deepgram_free_string.
#[no_mangle]
pub unsafe extern "C" fn rium_deepgram_push(handle: *mut DeepgramUtterance, bytes: *const u8, length: usize) -> *mut c_char {
    if handle.is_null() || bytes.is_null() || length > MAX_MESSAGE { return std::ptr::null_mut(); }
    let result = (*handle).push(std::slice::from_raw_parts(bytes, length));
    let result = match result {
        Update::Ignore => json!({"type":"ignored"}),
        Update::Error => json!({"type":"error"}),
        Update::Text { text, finished } => json!({"type":"text", "text":text, "finished":finished}),
    };
    CString::new(result.to_string()).map(CString::into_raw).unwrap_or(std::ptr::null_mut())
}

#[no_mangle]
pub unsafe extern "C" fn rium_deepgram_free_string(value: *mut c_char) {
    if !value.is_null() { drop(CString::from_raw(value)); }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn result(text: &str, is_final: bool, speech_final: bool) -> Vec<u8> {
        json!({"type":"Results", "is_final":is_final, "speech_final":speech_final,
            "channel":{"alternatives":[{"transcript":text}]}}).to_string().into_bytes()
    }

    #[test]
    fn combines_final_segments_and_replaces_interim() {
        let mut state = DeepgramUtterance::default();
        assert_eq!(state.push(&result("안녕", false, false)), Update::Text { text:"안녕".into(), finished:false });
        assert_eq!(state.push(&result("안녕하세요", true, false)), Update::Text { text:"안녕하세요".into(), finished:false });
        assert_eq!(state.push(&result("오늘", false, false)), Update::Text { text:"안녕하세요 오늘".into(), finished:false });
        assert_eq!(state.push(&result("오늘 날씨", false, false)), Update::Text { text:"안녕하세요 오늘 날씨".into(), finished:false });
        assert_eq!(state.push(&result("오늘 날씨", true, true)), Update::Text { text:"안녕하세요 오늘 날씨".into(), finished:true });
        assert_eq!(state.push(&result("다음", true, true)), Update::Text { text:"다음".into(), finished:true });
    }

    #[test]
    fn empty_final_and_invalid_messages_are_bounded() {
        let mut state = DeepgramUtterance::default();
        assert_eq!(state.push(&result("확정", true, false)), Update::Text { text:"확정".into(), finished:false });
        assert_eq!(state.push(&result("", true, true)), Update::Text { text:"확정".into(), finished:true });
        assert_eq!(state.push(&result("", true, true)), Update::Ignore);
        assert_eq!(state.push(&result("마지막", false, false)), Update::Text { text:"마지막".into(), finished:false });
        assert_eq!(state.push(&result("", true, true)), Update::Text { text:"마지막".into(), finished:true });
        assert_eq!(state.push(&result("내일", false, false)), Update::Text { text:"내일".into(), finished:false });
        assert_eq!(state.push(&result("", true, false)), Update::Text { text:"내일".into(), finished:false });
        assert_eq!(state.push(&result("", true, true)), Update::Text { text:"내일".into(), finished:true });
        assert_eq!(state.push(br#"{"type":"Metadata"}"#), Update::Ignore);
        assert_eq!(state.push(br#"{"type":"Error"}"#), Update::Error);
        assert_eq!(state.push(b"not json"), Update::Error);
        assert_eq!(state.push(&result(&"x".repeat(MAX_UTTERANCE + 1), false, false)), Update::Error);
    }
}
