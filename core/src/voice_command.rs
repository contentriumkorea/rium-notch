//! Keyword recognition for voice answers. This module never opens a microphone
//! and never sends an agent decision; its caller must validate the live request.

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum VoiceCommand { Allow, Deny, Open }

fn words(text: &str) -> Vec<String> {
    text.split(|c: char| !c.is_alphanumeric())
        .filter(|word| !word.is_empty())
        .map(str::to_lowercase)
        .collect()
}

/// Match comma-separated words or phrases at word boundaries. The most recent
/// matching phrase wins; an equally specific conflicting match is rejected.
pub fn classify(transcript: &str, allow: &str, deny: &str, open: &str) -> Option<VoiceCommand> {
    if transcript.len() > 16_384 || [allow, deny, open].iter().any(|list| list.len() > 4_096) { return None; }
    let tokens = words(transcript);
    if tokens.len() > 2_048 { return None; }
    let mut best: Option<(usize, usize, VoiceCommand)> = None;
    let mut ambiguous = false;
    for (command, list) in [(VoiceCommand::Allow, allow), (VoiceCommand::Deny, deny), (VoiceCommand::Open, open)] {
        for phrase in list.split(',').take(100) {
            let pattern = words(phrase);
            if pattern.is_empty() || pattern.len() > 16 || pattern.len() > tokens.len() { continue; }
            for start in 0..=tokens.len() - pattern.len() {
                let end = start + pattern.len();
                if tokens[start..end] != pattern { continue; }
                match best {
                    Some((old_end, old_length, _)) if end < old_end || (end == old_end && pattern.len() < old_length) => {},
                    Some((old_end, old_length, old_command)) if end == old_end && pattern.len() == old_length => {
                        if old_command != command { ambiguous = true; }
                    },
                    _ => { best = Some((end, pattern.len(), command)); ambiguous = false; }
                }
            }
        }
    }
    if ambiguous { None } else { best.map(|(_, _, command)| command) }
}

/// For a live approval, accept only a complete configured phrase. A keyword
/// embedded in a negation or another sentence must not trigger a decision.
pub fn classify_exact(transcript: &str, allow: &str, deny: &str, open: &str) -> Option<VoiceCommand> {
    if transcript.len() > 16_384 || [allow, deny, open].iter().any(|list| list.len() > 4_096) { return None; }
    let tokens = words(transcript);
    if tokens.is_empty() || tokens.len() > 16 { return None; }
    let mut found = None;
    for (command, list) in [(VoiceCommand::Allow, allow), (VoiceCommand::Deny, deny), (VoiceCommand::Open, open)] {
        for phrase in list.split(',').take(100) {
            if words(phrase) != tokens { continue; }
            if found.is_some_and(|previous| previous != command) { return None; }
            found = Some(command);
        }
    }
    found
}

/// UTF-8 byte buffers are borrowed for this call and never stored. Returns
/// 0 for no match, 1 for allow, 2 for deny, 3 for open and -1 for bad input.
#[no_mangle]
pub unsafe extern "C" fn rium_voice_classify(transcript: *const u8, transcript_len: usize,
    allow: *const u8, allow_len: usize, deny: *const u8, deny_len: usize,
    open: *const u8, open_len: usize) -> i32 {
    unsafe fn text<'a>(ptr: *const u8, len: usize, max: usize) -> Option<&'a str> {
        if len > max || (ptr.is_null() && len > 0) { return None; }
        let bytes = if len == 0 { &[] } else { std::slice::from_raw_parts(ptr, len) };
        std::str::from_utf8(bytes).ok()
    }
    let Some(transcript) = text(transcript, transcript_len, 16_384) else { return -1; };
    let Some(allow) = text(allow, allow_len, 4_096) else { return -1; };
    let Some(deny) = text(deny, deny_len, 4_096) else { return -1; };
    let Some(open) = text(open, open_len, 4_096) else { return -1; };
    match classify_exact(transcript, allow, deny, open) {
        None => 0, Some(VoiceCommand::Allow) => 1, Some(VoiceCommand::Deny) => 2, Some(VoiceCommand::Open) => 3,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn last_whole_phrase_wins_and_conflicts_are_rejected() {
        let lists = ("네, yes, 진행해", "아니요, no, 취소", "열어, open");
        assert_eq!(classify("no, 네!", lists.0, lists.1, lists.2), Some(VoiceCommand::Allow));
        assert_eq!(classify("네, 아니요", lists.0, lists.1, lists.2), Some(VoiceCommand::Deny));
        assert_eq!(classify("열어 주세요", lists.0, lists.1, lists.2), Some(VoiceCommand::Open));
        assert_eq!(classify("yesterday", lists.0, lists.1, lists.2), None);
        assert_eq!(classify("go", "go", "go", "open"), None);
        assert_eq!(classify("do not go", "go", "not go", "open"), Some(VoiceCommand::Deny));
    }
    #[test]
    fn live_approval_requires_an_unambiguous_complete_phrase() {
        assert_eq!(classify_exact("허용!", "허용", "거절", "열어"), Some(VoiceCommand::Allow));
        assert_eq!(classify_exact("do not allow", "allow", "deny", "open"), None);
        assert_eq!(classify_exact("allow", "allow", "allow", "open"), None);
        assert_eq!(classify_exact("", "", "거절", "열어"), None);
    }
}
