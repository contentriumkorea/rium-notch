//! Best-effort recognition of macOS AirDrop quarantine metadata.
use std::ffi::{c_char, c_int, c_void, CStr};

extern "C" {
    fn getxattr(path: *const c_char, name: *const c_char, value: *mut c_void, size: usize, position: u32, options: c_int) -> isize;
}
fn is_airdrop_quarantine(value: &[u8]) -> bool {
    let Ok(text) = std::str::from_utf8(value) else { return false; };
    text.trim_end_matches('\0').split(';').nth(2).map(|agent| agent.eq_ignore_ascii_case("sharingd")).unwrap_or(false)
}

// Unified logging may redact a field as an unquoted placeholder.
fn send_payload(text: &str) -> Option<serde_json::Value> {
    let parse = |input: &str| serde_json::Deserializer::from_str(input)
        .into_iter::<serde_json::Value>().next().and_then(Result::ok);
    if let Some(value) = parse(text) { return Some(value); }
    let bytes = text.as_bytes();
    let mut result = Vec::with_capacity(bytes.len());
    let (mut quoted, mut escaped, mut changed, mut i) = (false, false, false, 0);
    while i < bytes.len() {
        if !quoted && bytes[i..].starts_with(b"<private>") {
            result.extend_from_slice(b"null"); i += 9; changed = true; continue;
        }
        let byte = bytes[i];
        if quoted && escaped { escaped = false; }
        else if quoted && byte == b'\\' { escaped = true; }
        else if byte == b'"' { quoted = !quoted; }
        result.push(byte); i += 1;
    }
    if !changed { return None; }
    parse(std::str::from_utf8(&result).ok()?)
}

fn send_result(message: &str) -> Option<(bool, Option<String>)> {
    if message.len() > 65_536 { return None; }
    let (_, tail) = message.split_once("AirDrop.TransferResult")?;
    let start = tail.find('{')?;
    let value = send_payload(&tail[start..])?;
    let sender = value.get("sender")?;
    if sender.as_i64() != Some(1) && sender.as_str() != Some("1") { return None; }
    let success = match value.get("success")? {
        serde_json::Value::Bool(value) => *value,
        serde_json::Value::String(value) if value == "true" => true,
        serde_json::Value::String(value) if value == "false" => false,
        _ => return None,
    };
    let bundle = value.get("bundleID").and_then(serde_json::Value::as_str)
        .filter(|value| !value.is_empty() && value.len() <= 255 && value.bytes().all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'-' | b'_')))
        .map(str::to_owned);
    Some((success, bundle))
}

/// Returns 0 for an unrelated message, 1 for failure, 2 for success, or -1 for invalid buffers.
#[no_mangle]
pub unsafe extern "C" fn rium_airdrop_send_result(input: *const u8, len: usize, bundle: *mut u8, capacity: usize) -> i32 {
    if input.is_null() || bundle.is_null() || capacity < 256 || len > 65_536 { return -1; }
    *bundle = 0;
    let Ok(message) = std::str::from_utf8(std::slice::from_raw_parts(input, len)) else { return 0; };
    let Some((success, source)) = send_result(message) else { return 0; };
    if let Some(source) = source {
        std::ptr::copy_nonoverlapping(source.as_ptr(), bundle, source.len());
        *bundle.add(source.len()) = 0;
    }
    if success { 2 } else { 1 }
}

/// Monotonic receive-candidate lifecycle: wait=0, classify=1, discard=2.
/// An active receive is retained even after the normal discovery timeout.
fn pending_decision(first_seen: f64, now: f64, exists: bool, receiving: bool) -> Option<i32> {
    if !first_seen.is_finite() || !now.is_finite() { return None; }
    if !exists { return Some(2); }
    if receiving { return Some(0); }
    let elapsed = (now - first_seen).max(0.0);
    Some(if elapsed > 60.0 { 2 } else if elapsed < 1.0 { 0 } else { 1 })
}

#[no_mangle]
pub extern "C" fn rium_airdrop_pending_decision(first_seen: f64, now: f64, exists: i32, receiving: i32) -> i32 {
    if !(0..=1).contains(&exists) || !(0..=1).contains(&receiving) { return -1; }
    pending_decision(first_seen, now, exists == 1, receiving == 1).unwrap_or(-1)
}

#[no_mangle]
pub extern "C" fn rium_airdrop_receive_settle_seconds() -> f64 {
    0.4
}

#[no_mangle]
pub extern "C" fn rium_airdrop_landed_preview_seconds(extends_landed_preview: i32) -> f64 {
    if extends_landed_preview != 0 { 3.2 } else { 3.0 }
}

/// Returns 1 for a sharingd quarantine marker, 0 otherwise and -1 on error.
/// The caller must supply a valid NUL-terminated absolute path.
#[no_mangle]
pub unsafe extern "C" fn rium_is_airdrop_file(path: *const c_char) -> i32 {
    if path.is_null() { return -1; }
    let Ok(value) = CStr::from_ptr(path).to_str() else { return -1; };
    if !std::path::Path::new(value).is_absolute() { return -1; }
    let mut buffer = [0u8; 4096];
    // XATTR_NOFOLLOW prevents inspection of a symlink's target.
    let count = getxattr(path, b"com.apple.quarantine\0".as_ptr().cast(), buffer.as_mut_ptr().cast(), buffer.len(), 0, 1);
    if count < 0 { return -1; }
    i32::from(is_airdrop_quarantine(&buffer[..count as usize]))
}

// shortcut: the reference averages its known transfer values; byte-weighting
// and behavior for indeterminate transfers are not established.
fn receiving_fraction(values: &[f64]) -> Option<f64> {
    if values.is_empty() || values.len() > 4096 || values.iter().any(|value| !value.is_finite() || *value < 0.0) { return None; }
    Some(values.iter().map(|value| value.min(1.0)).sum::<f64>() / values.len() as f64)
}

/// Returns 1 and writes the average only when every active transfer has a
/// known fraction; 0 means indeterminate and -1 indicates an invalid buffer.
#[no_mangle]
pub unsafe extern "C" fn rium_airdrop_receiving_fraction(values: *const f64, len: usize, output: *mut f64) -> i32 {
    if output.is_null() || len > 4096 || (len > 0 && values.is_null()) { return -1; }
    let values = if len == 0 { &[] } else { std::slice::from_raw_parts(values, len) };
    match receiving_fraction(values) {
        Some(fraction) => { *output = fraction; 1 }
        None => 0,
    }
}

/// Coalesce files delivered together when macOS does not provide a shared transfer ID.
#[no_mangle]
pub extern "C" fn rium_airdrop_receive_wave_due(since_previous: f64) -> i32 {
    i32::from(since_previous.is_finite() && since_previous >= 0.4)
}

/// The reference uses an 8% arc while transfer progress is unavailable.
#[no_mangle]
pub extern "C" fn rium_airdrop_preview_progress(fraction: f64) -> f64 {
    if !fraction.is_finite() || fraction < 0.0 { 0.08 } else { fraction.min(1.0) }
}

// The receiving glyph is authored on a 24-point square; paired values are
// endpoints and Bézier controls in drawing order.
const RECEIVE_GLYPH_POINTS: [f64; 42] = [
    4.5, 13.3, 11.0, 20.3, 4.5, 18.7, 5.9, 20.3,
    13.0, 20.3, 19.5, 13.3, 18.1, 20.3, 19.5, 18.7,
    16.3, 15.1, 7.7, 15.1, 12.0, 3.7, 12.0, 14.2,
    8.1, 10.5, 11.4, 14.1, 9.5, 11.9, 10.4, 13.1,
    12.6, 14.1, 12.0, 14.7, 15.9, 10.5, 13.6, 13.1, 14.5, 11.9,
];
const SEND_GLYPH_ARROW: [f64; 22] = [
    12.0, 14.5, 12.0, 4.5, 8.1, 8.1, 11.4, 4.5, 9.5, 6.7, 10.4, 5.5,
    12.6, 4.5, 12.0, 3.9, 15.9, 8.1, 13.6, 5.5, 14.5, 6.7,
];

/// Writes the complete receiving glyph point set into a buffer of at least 42 doubles.
#[no_mangle]
pub unsafe extern "C" fn rium_airdrop_receive_glyph(output: *mut f64, capacity: usize) -> i32 {
    if output.is_null() || capacity < RECEIVE_GLYPH_POINTS.len() { return -1; }
    std::ptr::copy_nonoverlapping(RECEIVE_GLYPH_POINTS.as_ptr(), output, RECEIVE_GLYPH_POINTS.len());
    RECEIVE_GLYPH_POINTS.len() as i32
}

#[no_mangle]
pub unsafe extern "C" fn rium_airdrop_send_glyph(output: *mut f64, capacity: usize) -> i32 {
    if output.is_null() || capacity < RECEIVE_GLYPH_POINTS.len() { return -1; }
    std::ptr::copy_nonoverlapping(RECEIVE_GLYPH_POINTS.as_ptr(), output, 20);
    std::ptr::copy_nonoverlapping(SEND_GLYPH_ARROW.as_ptr(), output.add(20), SEND_GLYPH_ARROW.len());
    RECEIVE_GLYPH_POINTS.len() as i32
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn identifies_quarantine_agent_without_guessing_from_filename() {
        assert!(is_airdrop_quarantine(b"0083;abcdef;sharingd;1234"));
        assert!(is_airdrop_quarantine(b"0083;abcdef;SharingD;1234\0"));
        assert!(!is_airdrop_quarantine(b"0083;abcdef;Safari;sharingd"));
        assert!(!is_airdrop_quarantine(b"sharingd"));
        assert!(!is_airdrop_quarantine(&[0xff]));
    }
    #[test]
    fn send_result_requires_explicit_outgoing_result_and_filters_source() {
        assert_eq!(send_result(r#"AirDrop.TransferResult { "sender" : 1, "success" : true, "bundleID" : "com.example.app" }"#),
                   Some((true, Some("com.example.app".to_owned()))));
        assert_eq!(send_result(r#"AirDrop.TransferResult {"sender":"1","success":"false"}"#), Some((false, None)));
        assert_eq!(send_result(r#"AirDrop.TransferResult {"sender":0,"success":true}"#), None);
        assert_eq!(send_result(r#"AirDrop.TransferResult {"sender":1}"#), None);
        assert_eq!(send_result(r#"AirDrop.TransferResult {"sender":1,"success":"unknown"}"#), None);
        assert_eq!(send_result(r#"other {"sender":1,"success":true}"#), None);
        assert_eq!(send_result(r#"AirDrop.TransferResult {"sender":1,"success":true,"bundleID":"<private>"}"#), Some((true, None)));
        assert_eq!(send_result(r#"AirDrop.TransferResult {"sender":1,"success":true,"bundleID":<private>}"#), Some((true, None)));
        assert_eq!(send_result(r#"AirDrop.TransferResult {"sender":1,"success":false,"note":"\"<private>","bundleID":<private>}"#), Some((false, None)));
        assert_eq!(send_result(r#"AirDrop.TransferResult {"sender":<private>,"success":true}"#), None);
        assert_eq!(send_result(r#"AirDrop.TransferResult {"sender":1,"success":<private>}"#), None);
        let message = br#"AirDrop.TransferResult {"sender":1,"success":true,"bundleID":"com.example"}"#;
        let mut bundle = [0u8; 256];
        unsafe {
            assert_eq!(rium_airdrop_send_result(message.as_ptr(), message.len(), bundle.as_mut_ptr(), bundle.len()), 2);
            assert_eq!(&bundle[..12], b"com.example\0");
            assert_eq!(rium_airdrop_send_result(message.as_ptr(), message.len(), bundle.as_mut_ptr(), 255), -1);
            assert_eq!(rium_airdrop_send_result(std::ptr::null(), 0, bundle.as_mut_ptr(), bundle.len()), -1);
        }
    }
    #[test]
    fn simultaneous_receiving_is_indeterminate_until_every_fraction_is_known() {
        assert_eq!(receiving_fraction(&[]), None);
        assert_eq!(receiving_fraction(&[0.2, -1.0]), None);
        assert_eq!(receiving_fraction(&[0.2, f64::NAN]), None);
        assert_eq!(receiving_fraction(&[0.25, 0.75]), Some(0.5));
        assert_eq!(receiving_fraction(&[1.5, 0.5]), Some(0.75));
    }
    #[test]
    fn receive_wave_groups_simultaneous_completions() {
        assert_eq!(rium_airdrop_receive_wave_due(0.0), 0);
        assert_eq!(rium_airdrop_receive_wave_due(0.399), 0);
        assert_eq!(rium_airdrop_receive_wave_due(0.4), 1);
        assert_eq!(rium_airdrop_receive_wave_due(f64::NAN), 0);
    }
    #[test]
    fn preview_progress_keeps_unknown_distinct_from_zero() {
        assert_eq!(rium_airdrop_preview_progress(-1.0), 0.08);
        assert_eq!(rium_airdrop_preview_progress(f64::NAN), 0.08);
        assert_eq!(rium_airdrop_preview_progress(0.0), 0.0);
        assert_eq!(rium_airdrop_preview_progress(0.5), 0.5);
        assert_eq!(rium_airdrop_preview_progress(2.0), 1.0);
    }
    #[test]
    fn receiving_glyph_has_bounded_points_and_checks_output_capacity() {
        let mut output = [0.0; 43];
        output[42] = 42.0;
        unsafe {
            assert_eq!(rium_airdrop_receive_glyph(output.as_mut_ptr(), 41), -1);
            assert_eq!(rium_airdrop_receive_glyph(std::ptr::null_mut(), 42), -1);
            assert_eq!(rium_airdrop_receive_glyph(output.as_mut_ptr(), 42), 42);
        }
        assert_eq!(&output[..2], &[4.5, 13.3]);
        assert_eq!(&output[20..24], &[12.0, 3.7, 12.0, 14.2]);
        assert!(output[..42].iter().all(|value| (0.0..=24.0).contains(value)));
        assert_eq!(output[42], 42.0);
    }
    #[test]
    fn sending_glyph_preserves_tray_and_points_up() {
        let mut receive = [0.0; 42];
        let mut send = [0.0; 42];
        unsafe {
            assert_eq!(rium_airdrop_receive_glyph(receive.as_mut_ptr(), 42), 42);
            assert_eq!(rium_airdrop_send_glyph(send.as_mut_ptr(), 42), 42);
            assert_eq!(rium_airdrop_send_glyph(send.as_mut_ptr(), 41), -1);
            assert_eq!(rium_airdrop_send_glyph(std::ptr::null_mut(), 42), -1);
        }
        assert_eq!(&receive[..20], &send[..20]);
        assert_eq!(&send[20..24], &[12.0, 14.5, 12.0, 4.5]);
        assert!(send.iter().all(|value| (0.0..=24.0).contains(value)));
    }
    #[test]
    fn pending_receive_waits_for_progress_and_expires_only_after_completion() {
        assert_eq!(pending_decision(10.0, 10.5, true, false), Some(0));
        assert_eq!(pending_decision(10.0, 11.0, true, false), Some(1));
        assert_eq!(pending_decision(10.0, 70.0, true, false), Some(1));
        assert_eq!(pending_decision(10.0, 70.1, true, false), Some(2));
        assert_eq!(pending_decision(10.0, 100.0, true, true), Some(0));
        assert_eq!(pending_decision(10.0, 11.0, false, true), Some(2));
        assert_eq!(pending_decision(f64::NAN, 11.0, true, false), None);
    }
}
