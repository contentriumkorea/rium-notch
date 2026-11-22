//! LRCLIB lookup, requested only after the user enables lyrics.
use serde_json::{json, Value};
use std::io::Write;
use std::process::{Command, Stdio};
use std::ffi::{c_char, CString};

fn lrc_timestamp(value: &str) -> Option<f64> {
    let (minutes, seconds) = value.split_once(':')?;
    if !(1..=3).contains(&minutes.len()) || !minutes.bytes().all(|b| b.is_ascii_digit()) { return None; }
    let (whole, fraction) = match seconds.split_once('.') { Some((whole, fraction)) => (whole, Some(fraction)), None => (seconds, None) };
    if whole.len() != 2 || !whole.bytes().all(|b| b.is_ascii_digit())
        || fraction.is_some_and(|part| part.is_empty() || part.len() > 3 || !part.bytes().all(|b| b.is_ascii_digit())) { return None; }
    let seconds: f64 = seconds.parse().ok()?;
    if seconds >= 60.0 { return None; }
    Some(minutes.parse::<f64>().ok()? * 60.0 + seconds)
}

/// Timed lyrics preserve duplicate timestamps in source order; blank timed
/// lines are retained because they mark instrumental gaps.
fn parse_lines(synced: &str, plain: &str) -> Vec<Value> {
    let mut timed = Vec::<(f64, String)>::new();
    let mut expanded_bytes = 0usize;
    for line in synced.split(['\r', '\n', '\u{000b}', '\u{000c}', '\u{0085}', '\u{2028}', '\u{2029}']) {
        let mut remaining = line;
        let mut timestamps = Vec::new();
        while let Some(rest) = remaining.strip_prefix('[') {
            let Some(end) = rest.find(']') else { break; };
            let Some(time) = lrc_timestamp(&rest[..end]) else { break; };
            timestamps.push(time);
            remaining = &rest[end + 1..];
        }
        let text = remaining.trim();
        for time in timestamps {
            expanded_bytes = expanded_bytes.saturating_add(text.len());
            if timed.len() >= 20_000 || expanded_bytes > 2_000_000 { return Vec::new(); }
            timed.push((time, text.to_owned()));
        }
    }
    if timed.iter().any(|(_, text)| !text.is_empty()) {
        timed.sort_by(|a, b| a.0.total_cmp(&b.0));
        return timed.into_iter().enumerate().map(|(id, (time, text))| json!({"id":id,"time":time,"text":text})).collect();
    }
    plain.split(['\r', '\n', '\u{000b}', '\u{000c}', '\u{0085}', '\u{2028}', '\u{2029}']).map(str::trim).filter(|line| !line.is_empty())
        .enumerate().map(|(id, text)| json!({"id":id,"time":null,"text":text})).collect()
}

/// The buffers must remain valid for their declared lengths during this call.
/// Returns an owned UTF-8 JSON string, released with `rium_lyrics_free`.
#[no_mangle]
pub unsafe extern "C" fn rium_lyrics_parse(synced: *const u8, synced_len: usize, plain: *const u8, plain_len: usize) -> *mut c_char {
    unsafe fn bytes<'a>(ptr: *const u8, len: usize) -> Option<&'a str> {
        if len == 0 { return Some(""); }
        if ptr.is_null() || len > 150_000 { return None; }
        std::str::from_utf8(std::slice::from_raw_parts(ptr, len)).ok()
    }
    let Some(synced) = bytes(synced, synced_len) else { return std::ptr::null_mut(); };
    let Some(plain) = bytes(plain, plain_len) else { return std::ptr::null_mut(); };
    match CString::new(Value::Array(parse_lines(synced, plain)).to_string()) {
        Ok(value) => value.into_raw(), Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub unsafe extern "C" fn rium_lyrics_free(value: *mut c_char) {
    if !value.is_null() { drop(CString::from_raw(value)); }
}

fn encoded(value: &str) -> String {
    let mut out = String::new();
    for b in value.as_bytes() {
        if b.is_ascii_alphanumeric() || b"-._~".contains(b) { out.push(*b as char); }
        else { out.push_str(&format!("%{b:02X}")); }
    }
    out
}
fn parse(data: &[u8]) -> Result<Value, String> {
    let v: Value = serde_json::from_slice(data).map_err(|_| "가사 응답을 읽을 수 없습니다")?;
    if !v.is_object() { return Err("가사 응답 형식이 올바르지 않습니다".into()); }
    let text = |key: &str| v.get(key).and_then(Value::as_str).filter(|s| s.len() <= 150_000);
    Ok(json!({"synced":text("syncedLyrics"),"plain":text("plainLyrics"),"instrumental":v.get("instrumental").and_then(Value::as_bool).unwrap_or(false)}))
}
pub fn lookup(title: &str, artist: &str, duration: Option<f64>) -> Result<Value, String> {
    let title = title.trim(); let artist = artist.trim();
    if title.is_empty() || artist.is_empty() || title.len() > 1024 || artist.len() > 1024 { return Err("곡 제목과 아티스트를 확인할 수 없습니다".into()); }
    let mut url = format!("https://lrclib.net/api/get?track_name={}&artist_name={}", encoded(title), encoded(artist));
    if let Some(value) = duration.filter(|v|v.is_finite() && *v >= 1.0 && *v <= 3600.0) { url.push_str(&format!("&duration={}", value.round() as u32)); }
    // Track metadata is passed through stdin, not the process argument list.
    let mut child = Command::new("/usr/bin/curl")
        .args(["--config", "-", "--silent", "--show-error", "--max-time", "12", "--max-filesize", "1000000", "--user-agent", "RiumNotch/0.1 (https://contentrium.com)", "--write-out", "\n%{http_code}"])
        .stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::null()).spawn().map_err(|_| "가사 연결을 시작할 수 없습니다")?;
    let input_result = child.stdin.take().ok_or("가사 요청을 만들 수 없습니다")?.write_all(format!("url = \"{url}\"\n").as_bytes());
    if input_result.is_err() { let _ = child.kill(); let _ = child.wait(); return Err("가사 요청을 보낼 수 없습니다".into()); }
    let output = child.wait_with_output().map_err(|_| "가사 응답을 읽을 수 없습니다")?;
    if !output.status.success() || output.stdout.len() > 1_000_005 { return Err("가사 서비스에 연결할 수 없습니다".into()); }
    let split = output.stdout.iter().rposition(|b| *b == b'\n').ok_or("가사 응답을 읽을 수 없습니다")?;
    match &output.stdout[split + 1..] {
        b"200" => parse(&output.stdout[..split]),
        b"404" => Ok(json!({"notFound":true})),
        b"429" => Err("가사 요청이 제한되었습니다. 나중에 다시 시도해 주세요".into()),
        _ => Err("가사 서비스에 연결할 수 없습니다".into()),
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn timed_lines_sort_and_preserve_repeated_times_and_gaps() {
        let rows = parse_lines("[00:04.20][00:01.00]안녕\n[00:01.00]둘째\n[00:03.00]\n[00:70.00]무효", "대체 가사");
        assert_eq!(rows.len(), 4);
        assert_eq!(rows[0]["time"], 1.0); assert_eq!(rows[0]["text"], "안녕");
        assert_eq!(rows[1]["time"], 1.0); assert_eq!(rows[1]["text"], "둘째");
        assert_eq!(rows[2]["time"], 3.0); assert_eq!(rows[2]["text"], "");
        assert_eq!(rows[3]["time"], 4.2);
        assert_eq!(parse_lines("[00:01.00]", "한 줄\r\n두 줄"), json!([
            {"id":0,"time":null,"text":"한 줄"}, {"id":1,"time":null,"text":"두 줄"}
        ]).as_array().unwrap().clone());
        assert!(lrc_timestamp("12:60.0").is_none());
        assert!(lrc_timestamp("1:01.1234").is_none());
    }
    #[test]
    fn encodes_metadata_and_filters_response() {
        assert_eq!(encoded("a &한"), "a%20%26%ED%95%9C");
        let v = parse(br#"{"syncedLyrics":"[00:01.00]line","plainLyrics":"line","instrumental":false,"extra":"omit"}"#).unwrap();
        assert_eq!(v["synced"], "[00:01.00]line"); assert!(v.get("extra").is_none());
        assert!(parse(b"[]").is_err());
        assert!(lookup("", "artist", None).is_err());
    }
}
