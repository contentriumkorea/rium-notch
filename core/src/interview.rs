//! In-memory interview transcript. Audio and text are not persisted here.

use serde_json::json;
use std::collections::VecDeque;
use std::ffi::{c_char, CString};

const MAX_LINE_BYTES: usize = 8192;
const MAX_LINES: usize = 300;

#[derive(Clone, Copy, PartialEq, Eq)]
enum Speaker { Me, Them }

impl Speaker {
    fn from_code(code: i32) -> Option<Self> {
        match code { 0 => Some(Self::Me), 1 => Some(Self::Them), _ => None }
    }
    fn name(self) -> &'static str { match self { Self::Me => "me", Self::Them => "them" } }
    fn index(self) -> usize { match self { Self::Me => 0, Self::Them => 1 } }
}

struct Line { id: u64, speaker: Speaker, text: String }

pub struct InterviewTranscript {
    lines: VecDeque<Line>,
    partials: [String; 2],
    next_id: u64,
}

impl InterviewTranscript {
    fn new() -> Self { Self { lines: VecDeque::new(), partials: [String::new(), String::new()], next_id: 1 } }

    fn set_partial(&mut self, speaker: Speaker, text: &str) -> bool {
        if text.len() > MAX_LINE_BYTES || text.contains('\0') { return false; }
        self.partials[speaker.index()] = text.to_owned();
        true
    }

    fn finish(&mut self, speaker: Speaker) -> bool {
        let partial = &self.partials[speaker.index()];
        let text = partial.trim();
        if text.is_empty() { self.partials[speaker.index()].clear(); return true; }
        let Some(next) = self.next_id.checked_add(1) else { return false; };
        self.lines.push_back(Line { id: self.next_id, speaker, text: text.to_owned() });
        self.next_id = next;
        self.partials[speaker.index()].clear();
        if self.lines.len() > MAX_LINES { self.lines.pop_front(); }
        true
    }

    fn snapshot(&self) -> Option<CString> {
        let lines: Vec<_> = self.lines.iter().map(|line| json!({"id":line.id,"speaker":line.speaker.name(),"text":line.text.as_str()})).collect();
        CString::new(json!({"lines":lines,"mePartial":self.partials[0].as_str(),"themPartial":self.partials[1].as_str()}).to_string()).ok()
    }
}

/// The handle is confined to one caller queue; it must not be used concurrently.
#[no_mangle]
pub extern "C" fn rium_interview_transcript_new() -> *mut InterviewTranscript {
    Box::into_raw(Box::new(InterviewTranscript::new()))
}

#[no_mangle]
pub unsafe extern "C" fn rium_interview_transcript_free(handle: *mut InterviewTranscript) {
    if !handle.is_null() { drop(Box::from_raw(handle)); }
}

#[no_mangle]
pub unsafe extern "C" fn rium_interview_transcript_partial(handle: *mut InterviewTranscript, speaker: i32,
    bytes: *const u8, length: usize) -> i32 {
    if handle.is_null() || length > MAX_LINE_BYTES || (length > 0 && bytes.is_null()) { return -1; }
    let Some(speaker) = Speaker::from_code(speaker) else { return -1; };
    let data = if length == 0 { &[] } else { std::slice::from_raw_parts(bytes, length) };
    let Ok(text) = std::str::from_utf8(data) else { return -1; };
    if (*handle).set_partial(speaker, text) { 0 } else { -1 }
}

#[no_mangle]
pub unsafe extern "C" fn rium_interview_transcript_finish(handle: *mut InterviewTranscript, speaker: i32) -> i32 {
    if handle.is_null() { return -1; }
    let Some(speaker) = Speaker::from_code(speaker) else { return -1; };
    if (*handle).finish(speaker) { 0 } else { -1 }
}

#[no_mangle]
pub unsafe extern "C" fn rium_interview_transcript_snapshot(handle: *const InterviewTranscript) -> *mut c_char {
    if handle.is_null() { return std::ptr::null_mut(); }
    (*handle).snapshot().map(CString::into_raw).unwrap_or(std::ptr::null_mut())
}

#[no_mangle]
pub unsafe extern "C" fn rium_interview_transcript_free_string(value: *mut c_char) {
    if !value.is_null() { drop(CString::from_raw(value)); }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn separates_partials_and_finishes_only_once() {
        let mut transcript = InterviewTranscript::new();
        assert!(transcript.set_partial(Speaker::Me, " 안녕하세요 "));
        assert!(transcript.set_partial(Speaker::Them, "질문"));
        assert!(transcript.finish(Speaker::Me));
        assert!(transcript.finish(Speaker::Me));
        assert_eq!(transcript.lines.len(), 1);
        assert_eq!(transcript.lines[0].text, "안녕하세요");
        assert_eq!(transcript.partials[Speaker::Them.index()], "질문");
        assert!(!transcript.set_partial(Speaker::Me, &"가".repeat(MAX_LINE_BYTES)));
    }

    #[test]
    fn bounds_history_without_reusing_ids() {
        let mut transcript = InterviewTranscript::new();
        for _ in 0..=MAX_LINES {
            assert!(transcript.set_partial(Speaker::Them, "한 줄"));
            assert!(transcript.finish(Speaker::Them));
        }
        assert_eq!(transcript.lines.len(), MAX_LINES);
        assert_eq!(transcript.lines.front().unwrap().id, 2);
        assert_eq!(transcript.lines.back().unwrap().id, (MAX_LINES + 1) as u64);
    }
}
