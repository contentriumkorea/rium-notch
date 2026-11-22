//! Explicit, isolated Desktop protocol qualification. No account or existing
//! Codex session is opened; callers decide whether to persist the receipt.
use crate::desktop_launcher::{info_digest, stamp, CONTRACT};
use serde_json::{json, Value};
use std::fs::{self, DirBuilder, File};
use std::io::{BufRead, BufReader, Read, Write};
use std::os::unix::fs::{DirBuilderExt, MetadataExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc;
use std::thread;
use std::time::{Duration, Instant};

extern "C" { fn geteuid() -> u32; }
const SCHEMA_LIMIT: u64 = 16 * 1024 * 1024;

struct Temporary(PathBuf);
impl Drop for Temporary { fn drop(&mut self) { let _ = fs::remove_dir_all(&self.0); } }
struct ManagedChild(Child);
impl Drop for ManagedChild { fn drop(&mut self) { let _ = self.0.kill(); let _ = self.0.wait(); } }

fn temporary() -> Option<Temporary> {
    let mut random = [0u8; 16];
    File::open("/dev/urandom").ok()?.read_exact(&mut random).ok()?;
    let token: String = random.iter().map(|value| format!("{value:02x}")).collect();
    let path = std::env::temp_dir().join(format!("rium-codex-check-{token}"));
    DirBuilder::new().mode(0o700).create(&path).ok()?;
    Some(Temporary(path))
}

fn wait(child: &mut Child, timeout: Duration, shutdown: &AtomicBool) -> Option<bool> {
    let deadline = Instant::now() + timeout;
    loop {
        if shutdown.load(Ordering::Relaxed) || Instant::now() >= deadline { return None; }
        match child.try_wait() {
            Ok(Some(status)) => return Some(status.success()),
            Ok(None) => thread::sleep(Duration::from_millis(20)),
            Err(_) => return None,
        }
    }
}

fn local_command(program: &Path, args: &[&std::ffi::OsStr], timeout: Duration, shutdown: &AtomicBool) -> Option<Vec<u8>> {
    let child = Command::new(program).args(args).env_clear().env("PATH", "/usr/bin:/bin:/usr/sbin:/sbin")
        .stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::null()).spawn().ok()?;
    let mut child = ManagedChild(child);
    let output = child.0.stdout.take()?;
    let (tx, rx) = mpsc::sync_channel(1);
    thread::spawn(move || { let mut bytes = Vec::new(); let _ = output.take(8193).read_to_end(&mut bytes); let _ = tx.send(bytes); });
    if wait(&mut child.0, timeout, shutdown)? != true { return None; }
    let bytes = rx.recv_timeout(Duration::from_millis(200)).ok()?;
    (bytes.len() <= 8192).then_some(bytes)
}

fn isolated(program: &Path, root: &Path) -> Command {
    let mut command = Command::new(program);
    command.env_clear().env("PATH", "/usr/bin:/bin:/usr/sbin:/sbin")
        .env("HOME", root).env("CODEX_HOME", root).env("TMPDIR", root).env("CODEX_CLI_PATH", program);
    command
}

fn read_schema(directory: &Path, name: &str) -> Option<Value> {
    if !name.bytes().all(|byte| byte.is_ascii_alphanumeric()) { return None; }
    let path = directory.join(format!("{name}.json"));
    let meta = fs::symlink_metadata(&path).ok()?;
    if !meta.file_type().is_file() || meta.uid() != unsafe { geteuid() } || meta.len() > SCHEMA_LIMIT { return None; }
    let file = File::open(path).ok()?;
    let opened = file.metadata().ok()?;
    if meta.dev() != opened.dev() || meta.ino() != opened.ino() { return None; }
    serde_json::from_reader(file.take(SCHEMA_LIMIT + 1)).ok()
}

fn schema_probe(binary: &Path, root: &Path, shutdown: &AtomicBool) -> bool {
    let directory = root.join("schema");
    let mut command = isolated(binary, root);
    command.args(["app-server", "generate-json-schema", "--experimental", "--out"])
        .arg(&directory).stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null());
    let Ok(child) = command.spawn() else { return false; };
    let mut child = ManagedChild(child);
    if wait(&mut child.0, Duration::from_secs(15), shutdown) != Some(true) { return false; }
    let Ok(meta) = fs::symlink_metadata(&directory) else { return false; };
    if !meta.file_type().is_dir() || meta.uid() != unsafe { geteuid() } { return false; }
    crate::desktop_schema::validate_schemas(|name| read_schema(&directory, name))
}

fn handshake_response(message: &Value) -> Option<bool> {
    if message.get("id").and_then(Value::as_u64) != Some(1) { return None; }
    Some(message.get("error").is_none() && message.pointer("/result/userAgent").and_then(Value::as_str).is_some())
}

fn initialize_probe(binary: &Path, root: &Path, shutdown: &AtomicBool) -> bool {
    let mut command = isolated(binary, root);
    command.args(["app-server", "--listen", "stdio://"]).stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::null());
    let Ok(child) = command.spawn() else { return false; };
    let mut child = ManagedChild(child);
    let Some(mut input) = child.0.stdin.take() else { return false; };
    let Some(output) = child.0.stdout.take() else { return false; };
    let (tx, rx) = mpsc::sync_channel(16);
    thread::spawn(move || {
        let mut reader = BufReader::new(output);
        loop {
            let mut bytes = Vec::new();
            match (&mut reader).take(1_048_577).read_until(b'\n', &mut bytes) {
                Ok(0) | Err(_) => break,
                Ok(_) if bytes.len() > 1_048_576 || bytes.last() != Some(&b'\n') => break,
                Ok(_) => if tx.send(bytes).is_err() { break; },
            }
        }
    });
    let initialize = json!({"id":1,"method":"initialize","params":{"clientInfo":{"name":"rium_compatibility","version":"1"},"capabilities":{"experimentalApi":true}}});
    if writeln!(input, "{initialize}").and_then(|_| input.flush()).is_err() { return false; }
    let deadline = Instant::now() + Duration::from_secs(8);
    while Instant::now() < deadline && !shutdown.load(Ordering::Relaxed) {
        if child.0.try_wait().ok().flatten().is_some() { return false; }
        match rx.recv_timeout(Duration::from_millis(50)) {
            Ok(line) => {
                let Ok(message) = serde_json::from_slice::<Value>(&line) else { continue; };
                let Some(accepted) = handshake_response(&message) else { continue; };
                if !accepted { return false; }
                return writeln!(input, "{}", json!({"method":"initialized"})).and_then(|_| input.flush()).is_ok();
            }
            Err(mpsc::RecvTimeoutError::Timeout) => continue,
            Err(mpsc::RecvTimeoutError::Disconnected) => return false,
        }
    }
    false
}

/// Run only after the user selects Desktop integration. The returned receipt is
/// not written here; installation must still recheck ownership and conflicts.
pub fn qualify(binary: &Path, info: &Path, shutdown: &AtomicBool) -> Result<Value, &'static str> {
    let binary = fs::canonicalize(binary).map_err(|_| "binary_missing")?;
    let info = fs::canonicalize(info).map_err(|_| "app_missing")?;
    let contents = info.parent().filter(|path| path.file_name().is_some_and(|name| name == std::ffi::OsStr::new("Contents"))).ok_or("app_invalid")?;
    if info.file_name().map_or(true, |name| name != std::ffi::OsStr::new("Info.plist")) { return Err("app_invalid"); }
    let app = contents.parent().ok_or("app_invalid")?;
    let resources = fs::canonicalize(contents.join("Resources")).map_err(|_| "app_invalid")?;
    if !binary.starts_with(&resources) { return Err("binary_mismatch"); }
    let binary_meta = fs::metadata(&binary).map_err(|_| "binary_missing")?;
    if !binary_meta.is_file() || binary_meta.permissions().mode() & 0o111 == 0 { return Err("binary_invalid"); }
    let binary_stamp = stamp(&binary_meta);
    let (info_stamp, info_hash) = info_digest(&info).ok_or("app_invalid")?;
    let bundle = local_command(Path::new("/usr/bin/plutil"), &["-extract".as_ref(), "CFBundleIdentifier".as_ref(), "raw".as_ref(), "-o".as_ref(), "-".as_ref(), info.as_os_str()], Duration::from_secs(5), shutdown).ok_or("app_invalid")?;
    if std::str::from_utf8(&bundle).ok().map(str::trim) != Some("com.openai.codex") { return Err("app_invalid"); }
    local_command(Path::new("/usr/bin/codesign"), &["--verify".as_ref(), "--deep".as_ref(), "--strict".as_ref(), app.as_os_str()], Duration::from_secs(15), shutdown).ok_or("signature_invalid")?;
    let root = temporary().ok_or("temporary_unavailable")?;
    if !schema_probe(&binary, &root.0, shutdown) || !initialize_probe(&binary, &root.0, shutdown) { return Err("protocol_unverified"); }
    let latest_binary = fs::metadata(&binary).map_err(|_| "update_in_progress")?;
    let latest_info = info_digest(&info).ok_or("update_in_progress")?;
    if stamp(&latest_binary) != binary_stamp || latest_info != (info_stamp.clone(), info_hash.clone()) { return Err("update_in_progress"); }
    let binary_text = binary.to_str().ok_or("binary_invalid")?;
    let info_text = info.to_str().ok_or("app_invalid")?;
    Ok(json!({"enabled":true,"validated":true,"contract":CONTRACT,"binary":binary_text,"binaryStamp":binary_stamp,
              "appInfo":info_text,"appInfoStamp":info_stamp,"appInfoHash":info_hash}))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn only_the_matching_successful_initialize_reply_qualifies() {
        assert_eq!(handshake_response(&json!({"id":1,"result":{"userAgent":"fixture"}})), Some(true));
        assert_eq!(handshake_response(&json!({"id":2,"result":{"userAgent":"fixture"}})), None);
        assert_eq!(handshake_response(&json!({"id":1,"error":{"message":"no"}})), Some(false));
        assert_eq!(handshake_response(&json!({"id":1,"result":{}})), Some(false));
        assert!(read_schema(Path::new("/unused"), "../outside").is_none());
    }
}
