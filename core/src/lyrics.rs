//! LRCLIB lookup, requested only after the user enables lyrics.
use serde_json::{json, Value};
use std::io::Write;
use std::process::{Command, Stdio};

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
    fn encodes_metadata_and_filters_response() {
        assert_eq!(encoded("a &한"), "a%20%26%ED%95%9C");
        let v = parse(br#"{"syncedLyrics":"[00:01.00]line","plainLyrics":"line","instrumental":false,"extra":"omit"}"#).unwrap();
        assert_eq!(v["synced"], "[00:01.00]line"); assert!(v.get("extra").is_none());
        assert!(parse(b"[]").is_err());
        assert!(lookup("", "artist", None).is_err());
    }
}
