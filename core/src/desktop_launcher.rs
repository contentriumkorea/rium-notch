//! Future opt-in Codex launcher. Ordinary commands and unknown versions always
//! exec the official executable directly. This module never installs itself.
use serde_json::{json, Value};
use std::ffi::{OsStr, OsString};
use std::fs::{self, File, Metadata};
use std::io::Read;
use std::os::unix::fs::{MetadataExt, PermissionsExt};
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::AtomicBool;

extern "C" {
    fn geteuid() -> u32;
    fn CC_SHA256(data: *const std::ffi::c_void, len: u32, output: *mut u8) -> *mut u8;
}
pub(crate) const CONTRACT: &str = "rium-desktop-stdio-v1";

fn takes_value(option: &str) -> bool {
    matches!(option, "-c" | "--config" | "--enable" | "--disable" | "--listen" | "--code-mode-host"
        | "--ws-auth" | "--ws-token-file" | "--ws-token-sha256" | "--ws-shared-secret-file"
        | "--ws-issuer" | "--ws-audience" | "--ws-max-clock-skew-seconds")
}

/// Only the Desktop's stdio App Server is eligible for mediation. Unknown
/// subcommands, malformed options and non-UTF8 arguments use the official CLI.
pub fn is_desktop_server(args: &[OsString]) -> bool {
    let Some(args) = args.iter().map(|arg| arg.to_str()).collect::<Option<Vec<_>>>() else { return false; };
    if args.iter().any(|arg| matches!(*arg, "--help" | "-h" | "--version" | "-V")) { return false; }
    let mut i = 0;
    while i < args.len() && args[i].starts_with('-') {
        if args[i] == "--listen" || args[i].starts_with("--listen=") { return false; }
        if takes_value(args[i]) { i += 1; if i >= args.len() { return false; } }
        i += 1;
    }
    if args.get(i) != Some(&"app-server") { return false; }
    i += 1;
    while i < args.len() {
        let arg = args[i];
        if !arg.starts_with('-') || arg == "--" { return false; }
        if let Some(value) = arg.strip_prefix("--listen=") {
            if value != "stdio://" { return false; }
        } else if takes_value(arg) {
            i += 1;
            let Some(value) = args.get(i) else { return false; };
            if arg == "--listen" && *value != "stdio://" { return false; }
        }
        i += 1;
    }
    true
}

pub(crate) fn stamp(metadata: &Metadata) -> Value {
    // APFS device identifiers can change on remount; inode, length and both
    // modification/change timestamps detect an ordinary replacement.
    json!({"inode":metadata.ino(),"size":metadata.len(),"mtime":metadata.mtime(),"mtimeNs":metadata.mtime_nsec(),
           "ctime":metadata.ctime(),"ctimeNs":metadata.ctime_nsec()})
}

pub(crate) fn info_digest(path: &Path) -> Option<(Value, String)> {
    let file = File::open(path).ok()?;
    let metadata = file.metadata().ok()?;
    if !metadata.is_file() || metadata.len() > 1_048_576 { return None; }
    let mut bytes = Vec::new();
    (&file).take(1_048_577).read_to_end(&mut bytes).ok()?;
    if bytes.len() as u64 != metadata.len() || stamp(&file.metadata().ok()?) != stamp(&metadata)
        || stamp(&fs::metadata(path).ok()?) != stamp(&metadata) { return None; }
    let mut digest = [0u8; 32];
    if unsafe { CC_SHA256(bytes.as_ptr().cast(), bytes.len() as u32, digest.as_mut_ptr()) }.is_null() { return None; }
    Some((stamp(&metadata), digest.iter().map(|byte| format!("{byte:02x}")).collect()))
}

pub(crate) fn read_receipt(receipt: &Path) -> Option<Value> {
    if !receipt.is_absolute() { return None; }
    let meta = fs::symlink_metadata(receipt).ok()?;
    if !meta.file_type().is_file() || meta.uid() != unsafe { geteuid() } || meta.mode() & 0o077 != 0 || meta.len() > 65_536 { return None; }
    let file = File::open(receipt).ok()?;
    let opened = file.metadata().ok()?;
    if opened.dev() != meta.dev() || opened.ino() != meta.ino() { return None; }
    serde_json::from_reader(file.take(65_537)).ok()
}

pub(crate) fn compatible(binary: &Path, receipt: &Path) -> bool {
    let Some(value) = read_receipt(receipt) else { return false; };
    if value.get("enabled").and_then(Value::as_bool) != Some(true)
        || value.get("contract").and_then(Value::as_str) != Some(CONTRACT)
        || value.get("validated").and_then(Value::as_bool) != Some(true) { return false; }
    let Ok(binary) = fs::canonicalize(binary) else { return false; };
    if value.get("binary").and_then(Value::as_str).map(Path::new) != Some(binary.as_path()) { return false; }
    let Some(info) = value.get("appInfo").and_then(Value::as_str).map(Path::new).filter(|path| path.is_absolute()) else { return false; };
    let Ok(canonical_info) = fs::canonicalize(info) else { return false; };
    if canonical_info != info { return false; }
    let Ok(binary_meta) = fs::metadata(&binary) else { return false; };
    let Some((info_stamp, info_hash)) = info_digest(info) else { return false; };
    binary_meta.is_file() && value.get("binaryStamp") == Some(&stamp(&binary_meta))
        && value.get("appInfoStamp") == Some(&info_stamp) && value.get("appInfoHash").and_then(Value::as_str) == Some(info_hash.as_str())
        && fs::metadata(&binary).is_ok_and(|latest| stamp(&latest) == stamp(&binary_meta))
}

fn options(args: &[OsString]) -> Option<(PathBuf, Option<PathBuf>, &[OsString])> {
    let separator = args.iter().position(|arg| arg.as_os_str() == OsStr::new("--"))?;
    let mut binary = None;
    let mut receipt = None;
    let mut index = 0;
    while index < separator {
        let value = args.get(index + 1)?;
        if index + 1 >= separator { return None; }
        match args[index].to_str()? {
            "--binary" if binary.is_none() => binary = Some(PathBuf::from(value)),
            "--receipt" if receipt.is_none() => receipt = Some(PathBuf::from(value)),
            _ => return None,
        }
        index += 2;
    }
    let binary = binary.filter(|path| path.is_absolute())?;
    Some((binary, receipt, &args[separator + 1..]))
}

fn official_binary(requested: &Path, receipt: Option<&Path>) -> Option<PathBuf> {
    if let Ok(path) = fs::canonicalize(requested) {
        if fs::metadata(&path).is_ok_and(|meta| meta.is_file() && meta.permissions().mode() & 0o111 != 0) { return Some(path); }
    }
    let value = read_receipt(receipt?)?;
    let info = value.get("appInfo")?.as_str().map(Path::new)?.parent()?;
    if !info.is_absolute() || info.file_name()? != OsStr::new("Contents") { return None; }
    ["Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex", "Resources/codex", "Resources/bin/codex"]
        .iter().filter_map(|path| fs::canonicalize(info.join(path)).ok())
        .find(|path| fs::metadata(path).is_ok_and(|meta| meta.is_file() && meta.permissions().mode() & 0o111 != 0))
}

/// Returns only if starting the official CLI or bridge failed. The receipt is
/// created by a later explicit qualification workflow, not by this launcher.
pub fn run(args: &[OsString], shutdown: &AtomicBool) -> Result<i32, &'static str> {
    let (binary, receipt, cli_args) = options(args).ok_or("launcher_configuration_invalid")?;
    let binary = official_binary(&binary, receipt.as_deref()).ok_or("official_binary_missing")?;
    let metadata = fs::metadata(&binary).map_err(|_| "official_binary_missing")?;
    if !metadata.is_file() || metadata.permissions().mode() & 0o111 == 0
        || std::env::current_exe().ok().and_then(|path| fs::canonicalize(path).ok()).as_ref() == Some(&binary) {
        return Err("official_binary_invalid");
    }
    let use_bridge = is_desktop_server(cli_args) && receipt.as_ref().is_some_and(|path| compatible(&binary, path));
    if use_bridge {
        if let (Some(binary_text), Some(arguments)) = (binary.to_str(), cli_args.iter().map(|arg| arg.to_str()).collect::<Option<Vec<_>>>()) {
            let mut command = vec![binary_text.to_owned()];
            command.extend(arguments.into_iter().map(str::to_owned));
            match crate::desktop_transport::run_with_official_cli(&command, shutdown, Some(&binary)) {
                Ok(code) => return Ok(code),
                Err("random_unavailable" | "engine_start_failed") => {},
                Err(error) => return Err(error),
            }
        }
    }
    let error = Command::new(&binary).args(cli_args).env("CODEX_CLI_PATH", &binary).exec();
    let _ = error;
    Err("official_exec_failed")
}

#[cfg(test)]
mod tests {
    use super::*;
    fn args(values: &[&str]) -> Vec<OsString> { values.iter().map(OsString::from).collect() }
    #[test]
    fn only_stdio_app_server_is_eligible() {
        assert!(is_desktop_server(&args(&["app-server", "--listen", "stdio://"])));
        assert!(is_desktop_server(&args(&["-c", "x=y", "app-server", "--listen=stdio://"])));
        assert!(!is_desktop_server(&args(&["app-server", "proxy", "--sock", "/tmp/x"])));
        assert!(!is_desktop_server(&args(&["app-server", "--listen", "ws://127.0.0.1"])));
        assert!(!is_desktop_server(&args(&["app-server", "--listen"])));
        assert!(!is_desktop_server(&args(&["app-server", "--help"])));
    }
    #[test]
    fn launcher_requires_absolute_binary_and_separator() {
        assert!(options(&args(&["--binary", "codex", "--", "app-server"])).is_none());
        assert!(options(&args(&["--binary", "/a/codex", "app-server"])).is_none());
        assert!(options(&args(&["--binary", "/a/codex", "--", "app-server"])).is_some());
    }
}
