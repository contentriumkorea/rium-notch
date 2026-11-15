//! Local now-playing bridge via the bundled BSD-licensed MediaRemote Adapter.
use serde_json::{json, Value};
use std::process::{Command, Stdio};
use std::io::Read;
use std::thread;
use std::time::{Duration, Instant};

fn command_id(action: &str) -> Option<&'static str> {
    match action { "previous" => Some("5"), "toggle" => Some("2"), "next" => Some("4"), _ => None }
}
fn parse(data: &[u8]) -> Result<Value, String> {
    let value: Value = serde_json::from_slice(data).map_err(|_| "재생 정보를 읽을 수 없습니다")?;
    // MediaRemote Adapter returns JSON null when there is no active player.
    // Treat that as an empty result, while retaining errors for other shapes.
    let value = if value.is_null() { json!({}) } else { value };
    if !value.is_object() { return Err("재생 정보 형식이 올바르지 않습니다".into()); }
    Ok(json!({"title":value.get("title"),"artist":value.get("artist"),"album":value.get("album"),
        "playing":value.get("playing"),"duration":value.get("duration"),"elapsedTime":value.get("elapsedTimeNow").filter(|v|v.is_number()).or_else(||value.get("elapsedTime")),
        "artworkData":value.get("artworkData"),"artworkMimeType":value.get("artworkMimeType")}))
}
fn seek_micros(seconds: &str) -> Result<u64, String> {
    let value = seconds.parse::<f64>().map_err(|_| "재생 위치가 올바르지 않습니다")?;
    if !value.is_finite() || !(0.0..=604_800.0).contains(&value) { return Err("재생 위치가 올바르지 않습니다".into()); }
    Ok((value * 1_000_000.0).round() as u64)
}
pub fn request(action: &str, position: Option<&str>) -> Result<Value, String> {
    let seek = if action == "seek" { Some(seek_micros(position.ok_or("재생 위치가 필요합니다")?)?) } else { None };
    let executable = std::env::current_exe().map_err(|_| "재생 도구를 찾을 수 없습니다")?;
    let root = executable.parent().ok_or("재생 도구 경로가 올바르지 않습니다")?.join("../Resources/mediaremote-adapter");
    let script = root.join("mediaremote-adapter.pl"); let framework = root.join("MediaRemoteAdapter.framework");
    if !script.is_file() || !framework.is_dir() { return Err("재생 도구가 없습니다".into()); }
    let mut command = Command::new("/usr/bin/perl");
    command.arg(script).arg(framework);
    if action == "get" { command.args(["get", "--now"]); }
    else if let Some(position) = seek { command.arg("seek").arg(position.to_string()); }
    else { command.args(["send", command_id(action).ok_or("지원하지 않는 재생 명령입니다")?]); }
    let mut child = command.stdout(Stdio::piped()).stderr(Stdio::null()).spawn().map_err(|_| "재생 도구를 실행할 수 없습니다")?;
    let stdout = child.stdout.take().ok_or("재생 응답을 열 수 없습니다")?;
    let reader = thread::spawn(move || {
        let mut bytes = Vec::new();
        let result = stdout.take(2_000_001).read_to_end(&mut bytes);
        result.map(|_| bytes)
    });
    let deadline = Instant::now() + Duration::from_secs(8);
    loop {
        match child.try_wait() {
            Ok(Some(_)) => break,
            Ok(None) if Instant::now() < deadline => thread::sleep(Duration::from_millis(40)),
            _ => { let _ = child.kill(); let _ = child.wait(); return Err("재생 응답 시간이 초과되었습니다".into()); }
        }
    }
    let status = child.wait().map_err(|_| "재생 응답을 읽을 수 없습니다")?;
    let bytes = reader.join().map_err(|_| "재생 응답을 읽을 수 없습니다")?.map_err(|_| "재생 응답을 읽을 수 없습니다")?;
    if !status.success() { return Err("현재 재생 정보를 사용할 수 없습니다".into()); }
    if action == "get" { if bytes.len() > 2_000_000 { return Err("재생 응답이 너무 큽니다".into()); } parse(&bytes) }
    else { Ok(json!({"sent":true})) }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn media_commands_are_explicit_and_metadata_is_filtered() {
        assert_eq!(command_id("previous"), Some("5"));
        assert_eq!(command_id("toggle"), Some("2"));
        assert_eq!(command_id("next"), Some("4"));
        assert_eq!(command_id("arbitrary"), None);
        let v = parse(br#"{"title":"Song","playing":true,"unrelated_secret":"omit"}"#).unwrap();
        assert_eq!(v["title"], "Song"); assert!(v.get("unrelated_secret").is_none());
        let current = parse(br#"{"elapsedTime":12,"elapsedTimeNow":19}"#).unwrap();
        assert_eq!(current["elapsedTime"], 19);
        let fallback = parse(br#"{"elapsedTime":12,"elapsedTimeNow":null}"#).unwrap();
        assert_eq!(fallback["elapsedTime"], 12);
        let empty = parse(b"null").unwrap();
        assert!(empty["title"].is_null() && empty["playing"].is_null());
        assert!(parse(b"[]").is_err());
    }
    #[test]
    fn seek_uses_microseconds_and_rejects_invalid_positions() {
        assert_eq!(seek_micros("1.25").unwrap(), 1_250_000);
        assert_eq!(seek_micros("0").unwrap(), 0);
        for value in ["-1", "NaN", "inf", "604801", "invalid"] { assert!(seek_micros(value).is_err()); }
    }
}
