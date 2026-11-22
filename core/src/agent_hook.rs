//! Non-blocking Codex hook. Record only an exact session/process association;
//! never read or persist prompts, commands, answers or tool arguments.
use serde_json::{json, Value};
use std::collections::HashMap;
use std::env;
use std::fs::{self, DirBuilder, OpenOptions};
use std::io::{self, Read, Write};
use std::os::unix::fs::{DirBuilderExt, MetadataExt, OpenOptionsExt};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::mpsc;
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

#[repr(C)]
struct PollFd { fd: i32, events: i16, revents: i16 }
extern "C" { fn getppid() -> i32; fn geteuid() -> u32; fn poll(fds: *mut PollFd, count: u32, timeout: i32) -> i32; }
fn valid_id(id: &str) -> bool {
    id.len() == 36 && id.bytes().enumerate().all(|(i, c)| if [8, 13, 18, 23].contains(&i) { c == b'-' } else { c.is_ascii_hexdigit() })
}
fn parent_agent(name: &str) -> Option<u32> {
    let mut child = Command::new("/bin/ps").args(["-axo", "pid=,ppid=,comm="])
        .stdout(Stdio::piped()).stderr(Stdio::null()).spawn().ok()?;
    let Some(output) = child.stdout.take() else { let _ = child.kill(); let _ = child.wait(); return None; };
    let (tx, rx) = mpsc::channel();
    thread::spawn(move || { let mut data = Vec::new(); let _ = output.take(2_000_000).read_to_end(&mut data); let _ = tx.send(data); });
    let deadline = Instant::now() + Duration::from_millis(1500);
    loop {
        match child.try_wait() {
            Ok(Some(status)) if status.success() => break,
            Ok(None) if Instant::now() < deadline => thread::sleep(Duration::from_millis(20)),
            _ => { let _ = child.kill(); let _ = child.wait(); return None; }
        }
    }
    let data = rx.recv_timeout(Duration::from_millis(200)).ok()?;
    let text = String::from_utf8(data).ok()?;
    let mut tree = HashMap::new();
    for line in text.lines() {
        let Some((pid, rest)) = line.trim_start().split_once(char::is_whitespace) else { continue; };
        let Some((parent, command)) = rest.trim_start().split_once(char::is_whitespace) else { continue; };
        if let (Ok(pid), Ok(parent)) = (pid.parse::<u32>(), parent.parse::<u32>()) {
            tree.insert(pid, (parent, command.trim().to_owned()));
        }
    }
    let mut pid = unsafe { getppid() }.max(0) as u32;
    for _ in 0..16 {
        let (parent, command) = tree.get(&pid)?;
        if Path::new(command).file_name().and_then(|s| s.to_str()) == Some(name) { return Some(pid); }
        if *parent <= 1 || *parent == pid { break; }
        pid = *parent;
    }
    None
}
fn read_hook_input() -> Option<Vec<u8>> {
    let deadline = Instant::now() + Duration::from_millis(500);
    let mut input = io::stdin().lock();
    let mut data = Vec::new();
    loop {
        let remaining = deadline.saturating_duration_since(Instant::now());
        if remaining.is_zero() { break; }
        let timeout = remaining.as_millis().max(1).min(500) as i32;
        let mut descriptor = PollFd { fd: 0, events: 1, revents: 0 };
        let ready = unsafe { poll(&mut descriptor, 1, timeout) };
        if ready < 0 { return None; }
        if ready == 0 { break; }
        if descriptor.revents & (1 | 16) == 0 { return None; }
        let mut chunk = [0u8; 8192];
        let count = input.read(&mut chunk).ok()?;
        if count == 0 { break; }
        if data.len() + count > 262_144 { return None; }
        data.extend_from_slice(&chunk[..count]);
    }
    Some(data)
}
pub(crate) fn registry() -> Option<PathBuf> {
    let root = PathBuf::from(env::var_os("HOME")?).join("Library/Application Support/Rium Notch/agent-sessions");
    if !root.exists() { DirBuilder::new().recursive(true).mode(0o700).create(&root).ok()?; }
    let metadata = fs::symlink_metadata(&root).ok()?;
    if !metadata.file_type().is_dir() || metadata.uid() != unsafe { geteuid() } || metadata.mode() & 0o077 != 0 { return None; }
    Some(root)
}
pub fn record(event: &str) -> Option<()> {
    record_for(event, false)
}

pub fn record_claude(event: &str) -> Option<()> {
    record_for(event, true)
}

fn record_for(event: &str, claude: bool) -> Option<()> {
    if !matches!(event, "SessionStart" | "SessionEnd" | "UserPromptSubmit" | "PreToolUse" | "PostToolUse" | "PostToolUseFailure" | "PermissionDenied" | "PermissionRequest" | "Stop") { return None; }
    let input = read_hook_input()?;
    let value: Value = serde_json::from_slice(&input).ok()?;
    record_value(event, claude, &value)?;
    if claude {
        if let Some(session) = value.get("session_id").and_then(Value::as_str) {
            crate::claude_permission::notify_terminal(session, event, &value);
        }
    } else if let Some(session) = value.get("session_id").and_then(Value::as_str) {
        crate::claude_permission::notify_codex_terminal(session, event, &value);
    }
    Some(())
}

pub(crate) fn codex_question_tool(name: &str) -> bool {
    matches!(name, "request_user_input" | "request_user_input_async")
}

fn is_question_tool(claude: bool, name: &str) -> bool {
    if claude { name == "AskUserQuestion" } else { codex_question_tool(name) }
}

fn record_value(event: &str, claude: bool, value: &Value) -> Option<()> {
    let id = value.get("session_id").and_then(Value::as_str).filter(|id| valid_id(id))?;
    let cwd = value.get("cwd").and_then(Value::as_str).filter(|cwd| Path::new(cwd).is_absolute() && cwd.len() <= 4096)?;
    let pid = parent_agent(if claude { "claude" } else { "codex" })?;
    let root = registry()?;
    let now = SystemTime::now().duration_since(UNIX_EPOCH).ok()?.as_millis().min(u64::MAX as u128) as u64;
    let state = if matches!(event, "SessionEnd" | "Stop") { "stopped" } else { "active" };
    let question = value.get("tool_name").and_then(Value::as_str).is_some_and(|name| is_question_tool(claude, name));
    let mut data = json!({"sessionId":id,"pid":pid,"cwd":cwd,"state":state,
                      "eventName":event,"awaitingPermission":event == "PermissionRequest" && !question,
                      "awaitingQuestion":event == "PermissionRequest" && question,"updatedAt":now});
    if let Some(identity) = crate::process_identity::process_identity(pid).filter(|identity|
        identity.uid == unsafe { geteuid() } && identity.name == if claude { "claude" } else { "codex" }) {
        data["pidStartSec"] = json!(identity.start_sec);
        data["pidStartUsec"] = json!(identity.start_usec);
    }
    let key = if claude { format!("claude-{id}") } else { id.to_owned() };
    let destination = root.join(format!("{key}.json"));
    let temporary = root.join(format!(".{key}.{}.tmp", std::process::id()));
    let mut file = OpenOptions::new().write(true).create_new(true).mode(0o600).open(&temporary).ok()?;
    if writeln!(file, "{data}").and_then(|_| file.sync_all()).is_err() { let _ = fs::remove_file(&temporary); return None; }
    drop(file);
    if fs::rename(&temporary, destination).is_err() { let _ = fs::remove_file(&temporary); return None; }
    Some(())
}

/// The active permission hook is separate from passive monitoring. If the
/// user does not answer or the local connection fails, emit no decision.
pub fn claude_permission_hook() -> Option<()> {
    let input = read_hook_input()?;
    let value: Value = serde_json::from_slice(&input).ok()?;
    record_value("PermissionRequest", true, &value)?;
    let session = value.get("session_id")?.as_str()?;
    let response = crate::claude_permission::wait_for_decision(session, &value)?;
    let mut output = io::stdout().lock();
    serde_json::to_writer(&mut output, &response).ok()?;
    writeln!(output).ok()?;
    output.flush().ok()?;
    Some(())
}

pub fn codex_permission_hook() -> Option<()> {
    let input = read_hook_input()?;
    let value: Value = serde_json::from_slice(&input).ok()?;
    record_value("PermissionRequest", false, &value)?;
    let session = value.get("session_id")?.as_str()?;
    let response = crate::claude_permission::wait_for_codex_decision(session, &value)?;
    let mut output = io::stdout().lock();
    serde_json::to_writer(&mut output, &response).ok()?;
    writeln!(output).ok()?;
    output.flush().ok()?;
    Some(())
}

/// Merge Rium's passive handlers into the existing Codex hooks file. The
/// caller must invoke this explicitly; no feature flags or other files change.
pub fn install() -> Result<Value, String> {
    install_codex_mode(false)
}

pub fn install_codex_permission() -> Result<Value, String> {
    install_codex_mode(true)
}

fn codex_command(quoted: &str, event: &str, marker: &str, active_permission: bool) -> Value {
    let active = active_permission && event == "PermissionRequest";
    let command = if active { format!("{quoted} codex-permission-hook {marker}") }
        else { format!("{quoted} agent-hook {event} {marker}") };
    json!({"type":"command", "command":command, "timeout":if active { 65 } else { 3 }})
}

fn install_codex_mode(active_permission: bool) -> Result<Value, String> {
    let codex_home = env::var_os("CODEX_HOME").map(PathBuf::from)
        .or_else(|| env::var_os("HOME").map(|home| PathBuf::from(home).join(".codex")))
        .ok_or("Codex 설정 폴더를 찾을 수 없습니다")?;
    if !codex_home.is_dir() { return Err("Codex 설정 폴더를 찾을 수 없습니다".into()); }
    let path = codex_home.join("hooks.json");
    let original = match fs::symlink_metadata(&path) {
        Ok(meta) if meta.file_type().is_file() && meta.uid() == unsafe { geteuid() } && meta.len() <= 1_048_576 =>
            Some(fs::read(&path).map_err(|_| "Codex 훅 설정을 읽을 수 없습니다")?),
        Err(error) if error.kind() == io::ErrorKind::NotFound => None,
        _ => return Err("Codex 훅 설정 파일을 안전하게 확인할 수 없습니다".into()),
    };
    let mut config: Value = match &original {
        Some(bytes) => serde_json::from_slice(bytes).map_err(|_| "Codex 훅 설정 형식을 확인해 주세요")?,
        None => json!({}),
    };
    const MARKER: &str = "# rium-notch-codex-hook-v1";
    strip_owned_hooks(&mut config, MARKER).map_err(str::to_owned)?;
    let object = config.as_object_mut().ok_or("Codex 훅 설정 형식을 확인해 주세요")?;
    if !object.contains_key("hooks") { object.insert("hooks".into(), json!({})); }
    let hooks = object.get_mut("hooks").and_then(Value::as_object_mut).ok_or("Codex 훅 목록 형식을 확인해 주세요")?;
    let executable = env::current_exe().map_err(|_| "Rium Notch 실행 파일을 찾을 수 없습니다")?;
    if executable.file_name().and_then(|value| value.to_str()) != Some("rium-notch-core") { return Err("Rium Notch 실행 파일을 확인할 수 없습니다".into()); }
    let executable = executable.to_str().ok_or("실행 파일 경로를 읽을 수 없습니다")?;
    // POSIX single-quote escaping keeps a path with spaces or quotes literal.
    let quoted = format!("'{}'", executable.replace('\'', "'\\''"));
    for event in ["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop"] {
        let entry = hooks.entry(event.to_owned()).or_insert_with(|| json!([]));
        let handlers = entry.as_array_mut().ok_or("기존 Codex 훅 목록 형식을 확인해 주세요")?;
        let command = codex_command(&quoted, event, MARKER, active_permission);
        let handler = if matches!(event, "PreToolUse" | "PostToolUse" | "PermissionRequest") {
            json!({"matcher":"*","hooks":[command]})
        } else { json!({"hooks":[command]}) };
        handlers.push(handler);
    }
    let mut data = serde_json::to_vec_pretty(&config).map_err(|_| "Codex 훅 설정을 만들 수 없습니다")?;
    data.push(b'\n');
    if original.as_deref() == Some(data.as_slice()) { return Ok(json!({"installed":true,"changed":false})); }
    let current = match fs::read(&path) { Ok(bytes) => Some(bytes), Err(error) if error.kind() == io::ErrorKind::NotFound => None, Err(_) => return Err("Codex 훅 설정을 다시 확인할 수 없습니다".into()) };
    if current != original { return Err("Codex 훅 설정이 변경되어 저장하지 않았습니다. 다시 시도해 주세요".into()); }
    if let Some(bytes) = &original {
        let stamp = SystemTime::now().duration_since(UNIX_EPOCH).map_err(|_| "시스템 시간을 확인할 수 없습니다")?.as_millis();
        let backup = codex_home.join(format!("hooks.json.before-rium-{stamp}-{}", std::process::id()));
        let mut file = OpenOptions::new().write(true).create_new(true).mode(0o600).open(backup).map_err(|_| "기존 훅 설정을 보관할 수 없습니다")?;
        file.write_all(bytes).and_then(|_| file.sync_all()).map_err(|_| "기존 훅 설정을 보관할 수 없습니다")?;
    }
    let temporary = codex_home.join(format!(".rium-hooks-{}.tmp", std::process::id()));
    let mut file = OpenOptions::new().write(true).create_new(true).mode(0o600).open(&temporary).map_err(|_| "Codex 훅 설정을 저장할 수 없습니다")?;
    if file.write_all(&data).and_then(|_| file.sync_all()).is_err() {
        let _ = fs::remove_file(&temporary); return Err("Codex 훅 설정을 저장할 수 없습니다".into());
    }
    drop(file);
    let latest = match fs::read(&path) { Ok(bytes) => Some(bytes), Err(error) if error.kind() == io::ErrorKind::NotFound => None, Err(_) => { let _ = fs::remove_file(&temporary); return Err("Codex 훅 설정을 다시 확인할 수 없습니다".into()); } };
    if latest != original { let _ = fs::remove_file(&temporary); return Err("Codex 훅 설정이 변경되어 저장하지 않았습니다. 다시 시도해 주세요".into()); }
    if fs::rename(&temporary, &path).is_err() { let _ = fs::remove_file(&temporary); return Err("Codex 훅 설정을 저장할 수 없습니다".into()); }
    Ok(json!({"installed":true,"changed":true}))
}

/// The ordinary status integration keeps Claude's own prompt authoritative.
pub fn install_claude() -> Result<Value, String> {
    install_claude_mode(false)
}

/// A separate, explicitly selected mode lets the notch answer one request.
pub fn install_claude_permission() -> Result<Value, String> {
    install_claude_mode(true)
}

fn claude_command(quoted: &str, event: &str, marker: &str, active_permission: bool) -> Value {
    let active = active_permission && event == "PermissionRequest";
    let command = if active { format!("{quoted} claude-permission-hook {marker}") }
        else { format!("{quoted} claude-hook {event} {marker}") };
    json!({"type":"command", "command":command, "timeout":if active { 65 } else { 3 }})
}

fn install_claude_mode(active_permission: bool) -> Result<Value, String> {
    let home = env::var_os("CLAUDE_CONFIG_DIR").map(PathBuf::from)
        .or_else(|| env::var_os("HOME").map(|home| PathBuf::from(home).join(".claude")))
        .ok_or("Claude 설정 폴더를 찾을 수 없습니다")?;
    let directory = fs::symlink_metadata(&home).map_err(|_| "Claude 설정 폴더를 찾을 수 없습니다")?;
    if !directory.file_type().is_dir() || directory.uid() != unsafe { geteuid() } { return Err("Claude 설정 폴더를 확인할 수 없습니다".into()); }
    let path = home.join("settings.json");
    let original = match fs::symlink_metadata(&path) {
        Ok(meta) if meta.file_type().is_file() && meta.uid() == unsafe { geteuid() } && meta.len() <= 1_048_576 =>
            Some(fs::read(&path).map_err(|_| "Claude 설정을 읽을 수 없습니다")?),
        Err(error) if error.kind() == io::ErrorKind::NotFound => None,
        _ => return Err("Claude 설정 파일을 안전하게 확인할 수 없습니다".into()),
    };
    let mut config: Value = match &original {
        Some(data) => serde_json::from_slice(data).map_err(|_| "Claude 설정 형식을 확인해 주세요")?,
        None => json!({}),
    };
    const MARKER: &str = "# rium-notch-claude-hook-v1";
    strip_owned_hooks(&mut config, MARKER).map_err(str::to_owned)?;
    let object = config.as_object_mut().ok_or("Claude 설정 형식을 확인해 주세요")?;
    if !object.contains_key("hooks") { object.insert("hooks".into(), json!({})); }
    let hooks = object.get_mut("hooks").and_then(Value::as_object_mut).ok_or("Claude 훅 목록 형식을 확인해 주세요")?;
    let executable = env::current_exe().map_err(|_| "Rium Notch 실행 파일을 찾을 수 없습니다")?;
    if executable.file_name().and_then(|value| value.to_str()) != Some("rium-notch-core") { return Err("Rium Notch 실행 파일을 확인할 수 없습니다".into()); }
    let executable = executable.to_str().ok_or("실행 파일 경로를 읽을 수 없습니다")?;
    let quoted = format!("'{}'", executable.replace('\'', "'\\''"));
    for event in ["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionDenied", "PermissionRequest", "Stop"] {
        let handlers = hooks.entry(event.to_owned()).or_insert_with(|| json!([])).as_array_mut().ok_or("기존 Claude 훅 목록 형식을 확인해 주세요")?;
        let command = claude_command(&quoted, event, MARKER, active_permission);
        let handler = if matches!(event, "PreToolUse" | "PostToolUse" | "PostToolUseFailure" | "PermissionDenied" | "PermissionRequest") {
            json!({"matcher":"*","hooks":[command]})
        } else { json!({"hooks":[command]}) };
        handlers.push(handler);
    }
    let mut data = serde_json::to_vec_pretty(&config).map_err(|_| "Claude 설정을 만들 수 없습니다")?;
    data.push(b'\n');
    if original.as_deref() == Some(data.as_slice()) { return Ok(json!({"installed":true,"changed":false})); }
    let current = match fs::read(&path) { Ok(bytes) => Some(bytes), Err(error) if error.kind() == io::ErrorKind::NotFound => None, Err(_) => return Err("Claude 설정을 다시 확인할 수 없습니다".into()) };
    if current != original { return Err("Claude 설정이 변경되어 저장하지 않았습니다. 다시 시도해 주세요".into()); }
    if let Some(bytes) = &original {
        let stamp = SystemTime::now().duration_since(UNIX_EPOCH).map_err(|_| "시스템 시간을 확인할 수 없습니다")?.as_millis();
        let backup = home.join(format!("settings.json.before-rium-{stamp}-{}", std::process::id()));
        let mut file = OpenOptions::new().write(true).create_new(true).mode(0o600).open(backup).map_err(|_| "기존 Claude 설정을 보관할 수 없습니다")?;
        file.write_all(bytes).and_then(|_| file.sync_all()).map_err(|_| "기존 Claude 설정을 보관할 수 없습니다")?;
    }
    let temporary = home.join(format!(".rium-claude-settings-{}.tmp", std::process::id()));
    let mut file = OpenOptions::new().write(true).create_new(true).mode(0o600).open(&temporary).map_err(|_| "Claude 설정을 저장할 수 없습니다")?;
    if file.write_all(&data).and_then(|_| file.sync_all()).is_err() {
        let _ = fs::remove_file(&temporary); return Err("Claude 설정을 저장할 수 없습니다".into());
    }
    drop(file);
    let latest = match fs::read(&path) { Ok(bytes) => Some(bytes), Err(error) if error.kind() == io::ErrorKind::NotFound => None, Err(_) => { let _ = fs::remove_file(&temporary); return Err("Claude 설정을 다시 확인할 수 없습니다".into()); } };
    if latest != original { let _ = fs::remove_file(&temporary); return Err("Claude 설정이 변경되어 저장하지 않았습니다. 다시 시도해 주세요".into()); }
    if fs::rename(&temporary, &path).is_err() { let _ = fs::remove_file(&temporary); return Err("Claude 설정을 저장할 수 없습니다".into()); }
    Ok(json!({"installed":true,"changed":true}))
}

// Remove only commands bearing our exact marker, including in a handler that
// also contains other tools. Preserve unrecognized entries and other settings.
fn strip_owned_hooks(config: &mut Value, marker: &str) -> Result<bool, &'static str> {
    let object = config.as_object_mut().ok_or("설정 파일 형식을 확인해 주세요")?;
    let Some(value) = object.get_mut("hooks") else { return Ok(false); };
    let hooks = value.as_object_mut().ok_or("훅 목록 형식을 확인해 주세요")?;
    let mut changed = false;
    hooks.retain(|_, value| {
        let Some(handlers) = value.as_array_mut() else { return true; };
        let mut changed_event = false;
        handlers.retain_mut(|handler| {
            let Some(commands) = handler.get_mut("hooks").and_then(Value::as_array_mut) else { return true; };
            let old_count = commands.len();
            commands.retain(|command| !command.get("command").and_then(Value::as_str).is_some_and(|s| s.ends_with(marker)));
            let removed = commands.len() != old_count;
            let empty = commands.is_empty();
            changed_event |= removed;
            if !removed || !empty { return true; }
            // Keep an emptied handler if it also carries fields we did not create.
            handler.as_object().is_some_and(|object| object.keys().any(|key| key != "hooks" && key != "matcher"))
        });
        changed |= changed_event;
        !(changed_event && handlers.is_empty())
    });
    if changed && hooks.is_empty() { object.remove("hooks"); }
    Ok(changed)
}

pub fn uninstall_codex() -> Result<Value, String> { uninstall_hooks(false) }
pub fn uninstall_claude() -> Result<Value, String> { uninstall_hooks(true) }

fn uninstall_hooks(claude: bool) -> Result<Value, String> {
    let directory = if claude {
        env::var_os("CLAUDE_CONFIG_DIR").map(PathBuf::from)
            .or_else(|| env::var_os("HOME").map(|home| PathBuf::from(home).join(".claude")))
    } else {
        env::var_os("CODEX_HOME").map(PathBuf::from)
            .or_else(|| env::var_os("HOME").map(|home| PathBuf::from(home).join(".codex")))
    }.ok_or("설정 폴더를 찾을 수 없습니다")?;
    let dir = fs::symlink_metadata(&directory).map_err(|_| "설정 폴더를 찾을 수 없습니다")?;
    if !dir.file_type().is_dir() || dir.uid() != unsafe { geteuid() } { return Err("설정 폴더를 확인할 수 없습니다".into()); }
    let filename = if claude { "settings.json" } else { "hooks.json" };
    let marker = if claude { "# rium-notch-claude-hook-v1" } else { "# rium-notch-codex-hook-v1" };
    let path = directory.join(filename);
    let meta = match fs::symlink_metadata(&path) {
        Ok(meta) if meta.file_type().is_file() && meta.uid() == unsafe { geteuid() } && meta.len() <= 1_048_576 => meta,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(json!({"installed":false,"changed":false})),
        _ => return Err("설정 파일을 안전하게 확인할 수 없습니다".into()),
    };
    let file = fs::File::open(&path).map_err(|_| "설정을 읽을 수 없습니다")?;
    let opened = file.metadata().map_err(|_| "설정 파일을 확인할 수 없습니다")?;
    if !opened.file_type().is_file() || opened.dev() != meta.dev() || opened.ino() != meta.ino() || opened.uid() != meta.uid() {
        return Err("설정이 변경되어 연동을 해제하지 않았습니다. 다시 시도해 주세요".into());
    }
    let mut original = Vec::new();
    file.take(1_048_577).read_to_end(&mut original).map_err(|_| "설정을 읽을 수 없습니다")?;
    if original.len() > 1_048_576 { return Err("설정 파일이 너무 큽니다".into()); }
    let mut config: Value = serde_json::from_slice(&original).map_err(|_| "설정 파일 형식을 확인해 주세요")?;
    if !strip_owned_hooks(&mut config, marker).map_err(str::to_owned)? { return Ok(json!({"installed":false,"changed":false})); }
    let mut data = serde_json::to_vec_pretty(&config).map_err(|_| "설정을 만들 수 없습니다")?;
    data.push(b'\n');
    let unchanged = || -> bool {
        let Ok(current) = fs::symlink_metadata(&path) else { return false; };
        if !current.file_type().is_file() || current.dev() != meta.dev() || current.ino() != meta.ino() || current.uid() != meta.uid() { return false; }
        let Ok(file) = fs::File::open(&path) else { return false; };
        let Ok(opened) = file.metadata() else { return false; };
        if opened.dev() != meta.dev() || opened.ino() != meta.ino() { return false; }
        let mut bytes = Vec::new();
        file.take(1_048_577).read_to_end(&mut bytes).is_ok() && bytes == original
    };
    if !unchanged() { return Err("설정이 변경되어 연동을 해제하지 않았습니다. 다시 시도해 주세요".into()); }
    let stamp = SystemTime::now().duration_since(UNIX_EPOCH).map_err(|_| "시스템 시간을 확인할 수 없습니다")?.as_millis();
    let backup = directory.join(format!("{filename}.before-rium-remove-{stamp}-{}", std::process::id()));
    let mut file = OpenOptions::new().write(true).create_new(true).mode(0o600).open(backup).map_err(|_| "기존 설정을 보관할 수 없습니다")?;
    file.write_all(&original).and_then(|_| file.sync_all()).map_err(|_| "기존 설정을 보관할 수 없습니다")?;
    let temporary = directory.join(format!(".rium-remove-{stamp}-{}.tmp", std::process::id()));
    let mut file = OpenOptions::new().write(true).create_new(true).mode(0o600).open(&temporary).map_err(|_| "설정을 저장할 수 없습니다")?;
    if file.write_all(&data).and_then(|_| file.sync_all()).is_err() {
        let _ = fs::remove_file(&temporary); return Err("설정을 저장할 수 없습니다".into());
    }
    drop(file);
    if !unchanged() { let _ = fs::remove_file(&temporary); return Err("설정이 변경되어 연동을 해제하지 않았습니다. 다시 시도해 주세요".into()); }
    if fs::rename(&temporary, &path).is_err() { let _ = fs::remove_file(&temporary); return Err("설정을 저장할 수 없습니다".into()); }
    Ok(json!({"installed":false,"changed":true}))
}

#[cfg(test)]
mod claude_command_tests {
    use super::*;
    #[test]
    fn question_tools_are_classified_by_provider() {
        assert!(is_question_tool(true, "AskUserQuestion"));
        assert!(is_question_tool(false, "request_user_input"));
        assert!(is_question_tool(false, "request_user_input_async"));
        assert!(!is_question_tool(false, "exec_command"));
        assert!(!is_question_tool(true, "request_user_input"));
    }
    #[test]
    fn active_mode_changes_only_permission_hook_and_timeout() {
        let passive = claude_command("'core'", "PermissionRequest", "# marker", false);
        let active = claude_command("'core'", "PermissionRequest", "# marker", true);
        assert_eq!(passive["command"], "'core' claude-hook PermissionRequest # marker");
        assert_eq!(passive["timeout"], 3);
        assert_eq!(active["command"], "'core' claude-permission-hook # marker");
        assert_eq!(active["timeout"], 65);
        assert_eq!(claude_command("'core'", "PreToolUse", "# marker", true),
                   claude_command("'core'", "PreToolUse", "# marker", false));
        assert_eq!(codex_command("'core'", "PermissionRequest", "# marker", true)["command"], "'core' codex-permission-hook # marker");
        assert_eq!(codex_command("'core'", "PreToolUse", "# marker", true),
                   codex_command("'core'", "PreToolUse", "# marker", false));
    }
    #[test]
    fn removal_preserves_unowned_and_mixed_handlers() {
        let marker = "# rium-notch-codex-hook-v1";
        let mut config = json!({"other":true,"hooks":{
            "Stop":[{"hooks":[{"command":"other"},{"command":format!("rium {marker}")}],"matcher":"*"}],
            "SessionStart":[{"hooks":[{"command":format!("rium {marker}")}]}],
            "UserPromptSubmit":[{"hooks":[{"command":format!("rium {marker}")}],"custom":"keep"}],
            "Unrecognized":{"keep":true}
        }});
        assert!(strip_owned_hooks(&mut config, marker).unwrap());
        assert_eq!(config["other"], true);
        assert_eq!(config["hooks"]["Stop"][0]["hooks"], json!([{"command":"other"}]));
        assert_eq!(config["hooks"]["Stop"][0]["matcher"], "*");
        assert!(config["hooks"].get("SessionStart").is_none());
        assert_eq!(config["hooks"]["UserPromptSubmit"][0]["custom"], "keep");
        assert_eq!(config["hooks"]["UserPromptSubmit"][0]["hooks"], json!([]));
        assert_eq!(config["hooks"]["Unrecognized"]["keep"], true);
        assert!(!strip_owned_hooks(&mut config, marker).unwrap());
    }
}
