//! Local now-playing bridge via the bundled BSD-licensed MediaRemote Adapter.
use serde_json::{json, Value};
use std::process::{Command, Stdio};
use std::io::{self, Read};
use std::sync::mpsc::{self, Receiver, RecvTimeoutError};
use std::thread;
use std::time::{Duration, Instant};

fn command_id(action: &str) -> Option<&'static str> {
    match action { "previous" => Some("5"), "toggle" => Some("2"), "next" => Some("4"), _ => None }
}
fn valid_bundle_identifier(id: &str) -> bool {
    !id.is_empty() && id.len() <= 255 && id.contains('.')
        && id.bytes().all(|c| c.is_ascii_alphanumeric() || matches!(c, b'.' | b'-' | b'_'))
}
fn bundle_identifier(value: Option<&Value>) -> Option<&str> {
    value.and_then(Value::as_str).filter(|id| valid_bundle_identifier(id))
}
fn track_identifier(value: Option<&Value>) -> Option<&str> {
    value.and_then(Value::as_str).filter(|id| !id.is_empty() && id.len() <= 512 && !id.chars().any(char::is_control))
}
fn playback_position(value: Option<&Value>) -> Option<&Value> {
    value.filter(|v| v.as_f64().is_some_and(|position| position.is_finite() && position >= 0.0))
}
fn process_id(value: Option<&Value>) -> Option<u32> {
    value.and_then(Value::as_u64).and_then(|pid| i32::try_from(pid).ok()).filter(|pid| *pid > 1).map(|pid| pid as u32)
}

fn process_belongs_to(mut process: u32, source: u32, parent: impl Fn(u32) -> Option<u32>) -> Option<bool> {
    for _ in 0..32 {
        if process == source { return Some(true); }
        if process <= 1 { return Some(false); }
        let next = parent(process)?;
        if next == process { return None; }
        process = next;
    }
    None
}

#[no_mangle]
pub extern "C" fn rium_media_output_activity(source: u32) -> i32 {
    use crate::process_identity::process_parent;
    if process_parent(source).is_none() { return -1; }
    let Some(processes) = crate::volume::possibly_emitting_processes() else { return -1; };
    let mut activity = 0;
    for (pid, running) in processes {
        match (process_belongs_to(pid, source, process_parent), running) {
            (Some(true), Some(true)) => return 1,
            (Some(false), _) => (),
            _ => activity = -1,
        }
    }
    activity
}

#[no_mangle]
pub extern "C" fn rium_media_playhead_restarted(before: f64, after: f64) -> i32 {
    i32::from(before.is_finite() && (0.0..2.0).contains(&after) && before - after > 1.0)
}

#[no_mangle]
pub extern "C" fn rium_media_seek_position_matches(
    target: f64, position: f64, since_request: f64, rate: f64, duration: f64,
) -> i32 {
    if ![target, position, since_request, rate, duration].iter().all(|value| value.is_finite())
        || target < 0.0 || position < 0.0 || since_request < 0.0 || duration < 0.0
    {
        return 0;
    }
    let end = if duration > 0.0 { duration } else { f64::INFINITY };
    let start = target.min(end);
    let projected = target + since_request * rate;
    if !projected.is_finite() { return 0; }
    let advanced = projected.clamp(0.0, end);
    // shortcut: allow one second for coarse player seeks until exact acknowledgements are available.
    i32::from((start.min(advanced) - 1.0..=start.max(advanced) + 1.0).contains(&position))
}

#[no_mangle]
pub extern "C" fn rium_media_output_hides_light(activity: i32, seconds_since_output: f64, was_hidden: i32) -> i32 {
    match activity {
        1 => 0,
        0 => i32::from(seconds_since_output.is_finite() && seconds_since_output > 1.5),
        _ => i32::from(was_hidden == 1),
    }
}

fn parse(data: &[u8]) -> Result<Value, String> {
    let value: Value = serde_json::from_slice(data).map_err(|_| "재생 정보를 읽을 수 없습니다")?;
    // A missing snapshot must bypass the skip wait for a partially populated track.
    if value.is_null() { return Ok(json!({"snapshotEmpty":true})); }
    if !value.is_object() { return Err("재생 정보 형식이 올바르지 않습니다".into()); }
    let content_id = track_identifier(value.get("contentItemIdentifier"));
    let unique_id = track_identifier(value.get("uniqueIdentifier"));
    Ok(json!({"title":value.get("title"),"artist":value.get("artist"),"album":value.get("album"),
        "playing":value.get("playing"),"playbackRate":value.get("playbackRate").filter(|v|v.is_number()),"duration":value.get("duration"),"elapsedTime":playback_position(value.get("elapsedTimeNow")).or_else(||playback_position(value.get("elapsedTime"))),
        "positionObservedUptime":playback_position(value.get("elapsedTimeNow")).and_then(|_| playback_position(value.get("positionObservedUptime"))),
        "artworkData":value.get("artworkData"),"artworkMimeType":value.get("artworkMimeType"),
        "trackIdentifier":content_id.or(unique_id),
        "trackIdentifierKind":if content_id.is_some() { Some("content") } else if unique_id.is_some() { Some("unique") } else { None },
        "processIdentifier":process_id(value.get("processIdentifier")),
        "bundleIdentifier":bundle_identifier(value.get("bundleIdentifier")),
        "parentApplicationBundleIdentifier":bundle_identifier(value.get("parentApplicationBundleIdentifier"))}))
}
fn seek_micros(seconds: &str) -> Result<u64, String> {
    let value = seconds.parse::<f64>().map_err(|_| "재생 위치가 올바르지 않습니다")?;
    if !value.is_finite() || !(0.0..=604_800.0).contains(&value) { return Err("재생 위치가 올바르지 않습니다".into()); }
    Ok((value * 1_000_000.0).round() as u64)
}
fn receive_output(reader: Receiver<io::Result<Vec<u8>>>, deadline: Instant) -> Result<Vec<u8>, String> {
    match reader.recv_timeout(deadline.saturating_duration_since(Instant::now())) {
        Ok(Ok(bytes)) => Ok(bytes),
        Err(RecvTimeoutError::Timeout) => Err("재생 응답 시간이 초과되었습니다".into()),
        _ => Err("재생 응답을 읽을 수 없습니다".into()),
    }
}

fn run_adapter(mut command: Command, deadline: Instant) -> Result<Vec<u8>, String> {
    if Instant::now() >= deadline { return Err("재생 응답 시간이 초과되었습니다".into()); }
    let mut child = command.stdout(Stdio::piped()).stderr(Stdio::null()).spawn()
        .map_err(|_| "재생 도구를 실행할 수 없습니다")?;
    let stdout = child.stdout.take().ok_or("재생 응답을 열 수 없습니다")?;
    let (sender, reader) = mpsc::sync_channel(1);
    thread::spawn(move || {
        let mut bytes = Vec::new();
        let result = stdout.take(2_000_001).read_to_end(&mut bytes).map(|_| bytes);
        let _ = sender.send(result);
    });
    loop {
        match child.try_wait() {
            Ok(Some(_)) => break,
            Ok(None) if Instant::now() < deadline => thread::sleep(Duration::from_millis(40)),
            _ => { let _ = child.kill(); let _ = child.wait(); return Err("재생 응답 시간이 초과되었습니다".into()); }
        }
    }
    let status = child.wait().map_err(|_| "재생 응답을 읽을 수 없습니다")?;
    if !status.success() { return Err("현재 재생 정보를 사용할 수 없습니다".into()); }
    // A descendant may keep stdout open even after the adapter itself exits.
    receive_output(reader, deadline)
}

fn confirm_player(data: &Value, expected: &str) -> Result<(), String> {
    let owner = bundle_identifier(data.get("parentApplicationBundleIdentifier"))
        .or_else(|| bundle_identifier(data.get("bundleIdentifier")));
    if owner == Some(expected) { return Ok(()); }
    Err("재생 앱이 바뀌었거나 확인되지 않아 명령을 취소했습니다.".into())
}

fn confirm_seek_range(data: &Value, position_micros: u64) -> Result<(), String> {
    let duration = data.get("duration").and_then(Value::as_f64)
        .filter(|duration| duration.is_finite() && *duration > 0.0)
        .ok_or("현재 미디어의 전체 길이를 확인할 수 없어 위치 이동을 취소했습니다.")?;
    if position_micros as f64 <= (duration * 1_000_000.0).round() { return Ok(()); }
    Err("요청한 위치가 현재 미디어의 재생 범위를 벗어나 이동을 취소했습니다.".into())
}

pub fn request(action: &str, position: Option<&str>, expected_player: Option<&str>) -> Result<Value, String> {
    let executable = std::env::current_exe().map_err(|_| "재생 도구를 찾을 수 없습니다")?;
    let root = executable.parent().ok_or("재생 도구 경로가 올바르지 않습니다")?.join("../Resources/mediaremote-adapter");
    let script = root.join("mediaremote-adapter.pl");
    let framework = root.join("MediaRemoteAdapter.framework");
    if !script.is_file() || !framework.is_dir() { return Err("재생 도구가 없습니다".into()); }
    let adapter = || {
        let mut command = Command::new("/usr/bin/perl");
        command.arg(&script).arg(&framework);
        command
    };
    let seek = if action == "seek" { Some(seek_micros(position.ok_or("재생 위치가 필요합니다")?)?) } else { None };
    let mut command = adapter();
    if action == "get" { command.args(["get", "--now", "--allow-missing-title"]); }
    else if let Some(position) = seek {
        command.arg("seek").arg(position.to_string());
    } else { command.args(["send", command_id(action).ok_or("지원하지 않는 재생 명령입니다")?]); }
    let deadline = Instant::now() + Duration::from_secs(8);
    let expected = expected_player.filter(|_| action != "get");
    if expected.is_some_and(|id| !valid_bundle_identifier(id)) { return Err("재생 앱 식별자가 올바르지 않습니다".into()); }
    if expected.is_some() || seek.is_some() {
        // The player or its reported duration can change after the user clicks.
        let mut snapshot = adapter();
        snapshot.args(["get", "--allow-missing-title", "--no-artwork"]);
        let data = parse(&run_adapter(snapshot, deadline)?)?;
        if let Some(id) = expected { confirm_player(&data, id)?; }
        if let Some(position) = seek { confirm_seek_range(&data, position)?; }
    }
    let bytes = run_adapter(command, deadline)?;
    if action == "get" { if bytes.len() > 2_000_000 { return Err("재생 응답이 너무 큽니다".into()); } parse(&bytes) }
    else { Ok(json!({"sent":true})) }
}

#[cfg(test)]
mod tests {
    #[test]
    fn matching_seek_accepts_rounded_and_projected_positions() {
        use super::rium_media_seek_position_matches as matches;
        assert_eq!(matches(70.0, 21.0, 0.5, 1.0, 120.0), 0);
        assert_eq!(matches(70.0, 72.2, 0.7, 2.0, 120.0), 1);
        assert_eq!(matches(70.0, 68.2, 0.5, -2.0, 120.0), 1);
        assert_eq!(matches(119.5, 120.0, 1.0, 2.0, 120.0), 1);
        assert_eq!(matches(70.0, 70.0, -0.1, 1.0, 120.0), 0);
        assert_eq!(matches(70.0, f64::NAN, 0.5, 1.0, 120.0), 0);
    }

    #[test]
    fn same_track_restart_requires_a_known_reset_near_the_start() {
        use super::rium_media_playhead_restarted;
        assert_eq!(rium_media_playhead_restarted(80.0, 0.6), 1);
        assert_eq!(rium_media_playhead_restarted(2.4, 0.5), 1);
        for (before, after) in [(80.0, 81.0), (80.0, 2.0), (2.5, 1.5), (1.5, 1.7), (f64::INFINITY, 0.0), (80.0, -1.0), (80.0, f64::NAN)] {
            assert_eq!(rium_media_playhead_restarted(before, after), 0);
        }
    }

    use super::*;
    #[test]
    fn player_check_requires_the_observed_owner() {
        let data = parse(br#"{"bundleIdentifier":"test.helper","parentApplicationBundleIdentifier":"test.player"}"#).unwrap();
        assert!(confirm_player(&data, "test.player").is_ok());
        assert!(confirm_player(&data, "test.helper").is_err());
        assert!(confirm_player(&data, "other.player").is_err());
        let direct = parse(br#"{"bundleIdentifier":"test.player"}"#).unwrap();
        assert!(confirm_player(&direct, "test.player").is_ok());
        assert!(confirm_player(&parse(b"null").unwrap(), "test.player").is_err());
    }
    #[test]
    fn seek_uses_current_duration_and_preserves_the_rounded_endpoint() {
        for duration in [Value::Null, json!("18"), json!(0), json!(-18)] {
            assert!(confirm_seek_range(&json!({"duration": duration}), 0).is_err());
        }
        let shorter = json!({"duration":18.1234567,"playing":false});
        let endpoint = seek_micros("18.1234567").unwrap();
        assert!(confirm_seek_range(&shorter, 0).is_ok());
        assert!(confirm_seek_range(&shorter, endpoint).is_ok());
        assert!(confirm_seek_range(&shorter, endpoint + 1).is_err());
        assert!(confirm_seek_range(&shorter, seek_micros("64").unwrap()).is_err());
    }
    #[test]
    fn output_detection_checks_descendants_and_keeps_unknown_or_silent_video() {
        let parent = |pid| match pid { 12 => Some(11), 11 => Some(10), 10 => Some(1), 99 => Some(99), _ => None };
        assert_eq!(process_belongs_to(12, 10, parent), Some(true));
        assert_eq!(process_belongs_to(10, 12, parent), Some(false));
        assert_eq!(process_belongs_to(99, 12, parent), None);
        assert_eq!(process_belongs_to(98, 12, parent), None);
        assert_eq!(rium_media_output_activity(0), -1);
        for (activity, elapsed, previous, expected) in [
            (0, -1.0, 0, 0), (0, 1.5, 0, 0), (0, 1.501, 0, 1), (1, 4.0, 1, 0),
            (-1, 4.0, 0, 0), (-1, 4.0, 1, 1), (0, f64::NAN, 0, 0),
        ] {
            assert_eq!(rium_media_output_hides_light(activity, elapsed, previous), expected);
        }
        assert_eq!(parse(br#"{"processIdentifier":123}"#).unwrap()["processIdentifier"], 123);
        for input in [br#"{"processIdentifier":-12}"#.as_slice(), br#"{"processIdentifier":1}"#, br#"{"processIdentifier":2147483648}"#, br#"{"processIdentifier":"12"}"#] {
            assert!(parse(input).unwrap()["processIdentifier"].is_null());
        }
    }

    #[test]
    fn output_collection_obeys_the_existing_deadline() {
        let (sender, receiver) = mpsc::sync_channel(1);
        sender.send(Ok(vec![1, 2])).unwrap();
        assert_eq!(receive_output(receiver, Instant::now()).unwrap(), vec![1, 2]);
        let (_sender, receiver) = mpsc::sync_channel(1);
        assert_eq!(receive_output(receiver, Instant::now()).unwrap_err(), "재생 응답 시간이 초과되었습니다");
        let (sender, receiver) = mpsc::sync_channel(1);
        drop(sender);
        assert_eq!(receive_output(receiver, Instant::now()).unwrap_err(), "재생 응답을 읽을 수 없습니다");
    }

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
        let invalid_estimate = parse(br#"{"elapsedTime":12,"elapsedTimeNow":-1}"#).unwrap();
        assert_eq!(invalid_estimate["elapsedTime"], 12);
        assert_eq!(parse(br#"{"elapsedTime":12,"elapsedTimeNow":0}"#).unwrap()["elapsedTime"], 0);
        assert!(parse(br#"{"elapsedTime":-1,"elapsedTimeNow":"invalid"}"#).unwrap()["elapsedTime"].is_null());
        assert_eq!(parse(br#"{"elapsedTimeNow":19,"positionObservedUptime":120}"#).unwrap()["positionObservedUptime"], 120);
        assert!(parse(br#"{"elapsedTime":12,"elapsedTimeNow":-1,"positionObservedUptime":120}"#).unwrap()["positionObservedUptime"].is_null());
        assert!(parse(br#"{"elapsedTimeNow":19,"positionObservedUptime":-1}"#).unwrap()["positionObservedUptime"].is_null());
        assert_eq!(parse(br#"{"playbackRate":1.5}"#).unwrap()["playbackRate"], 1.5);
        assert!(parse(br#"{"playbackRate":"fast"}"#).unwrap()["playbackRate"].is_null());
        assert_eq!(parse(br#"{"contentItemIdentifier":"track-2","uniqueIdentifier":"fallback"}"#).unwrap()["trackIdentifier"], "track-2");
        assert_eq!(parse(br#"{"contentItemIdentifier":"track-2"}"#).unwrap()["trackIdentifierKind"], "content");
        assert_eq!(parse(br#"{"contentItemIdentifier":"","uniqueIdentifier":"fallback"}"#).unwrap()["trackIdentifier"], "fallback");
        assert_eq!(parse(br#"{"uniqueIdentifier":"fallback"}"#).unwrap()["trackIdentifierKind"], "unique");
        assert!(parse(br#"{"contentItemIdentifier":"invalid\nidentifier"}"#).unwrap()["trackIdentifier"].is_null());
        let source = parse(br#"{"bundleIdentifier":"com.example.player.helper","parentApplicationBundleIdentifier":"com.example.player"}"#).unwrap();
        assert_eq!(source["bundleIdentifier"], "com.example.player.helper");
        assert_eq!(source["parentApplicationBundleIdentifier"], "com.example.player");
        let invalid = parse(br#"{"bundleIdentifier":"../not an app","parentApplicationBundleIdentifier":123}"#).unwrap();
        assert!(invalid["bundleIdentifier"].is_null() && invalid["parentApplicationBundleIdentifier"].is_null());
        let empty = parse(b"null").unwrap();
        assert_eq!(empty, json!({"snapshotEmpty":true}));
        let paused = parse(br#"{"processIdentifier":42,"playing":false}"#).unwrap();
        assert_eq!(paused["playing"], false);
        assert!(paused.get("snapshotEmpty").is_none());
        assert!(parse(b"[]").is_err());
    }
    #[test]
    fn seek_uses_microseconds_and_rejects_invalid_positions() {
        assert_eq!(seek_micros("1.25").unwrap(), 1_250_000);
        assert_eq!(seek_micros("0").unwrap(), 0);
        for value in ["-1", "NaN", "inf", "604801", "invalid"] { assert!(seek_micros(value).is_err()); }
    }
}
