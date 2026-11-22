//! Explicit Desktop integration activation. No current session is restarted.
use crate::desktop_setup::{self, Paths, OWNER};
use crate::desktop_setup_files::{self, StagedFiles};
use serde_json::{json, Value};
use std::ffi::OsStr;
use std::fs;
use std::io::Read;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc;
use std::thread;
use std::time::{Duration, Instant};

fn home() -> Result<PathBuf, &'static str> {
    let path = std::env::var_os("HOME").map(PathBuf::from).ok_or("home_unavailable")?;
    fs::canonicalize(path).map_err(|_| "home_unavailable")
}
fn launchctl(args: &[&OsStr], shutdown: &AtomicBool) -> Result<String, &'static str> {
    let mut child = Command::new("/bin/launchctl").args(args).stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::null())
        .spawn().map_err(|_| "launchctl_unavailable")?;
    let Some(output) = child.stdout.take() else { let _ = child.kill(); let _ = child.wait(); return Err("launchctl_unavailable"); };
    let (tx, rx) = mpsc::sync_channel(1);
    thread::spawn(move || { let mut data = Vec::new(); let _ = output.take(4097).read_to_end(&mut data); let _ = tx.send(data); });
    let deadline = Instant::now() + Duration::from_secs(4);
    let status = loop {
        if shutdown.load(Ordering::Relaxed) || Instant::now() >= deadline {
            let _ = child.kill(); let _ = child.wait(); return Err("launchctl_unknown");
        }
        match child.try_wait() {
            Ok(Some(status)) => break status,
            Ok(None) => thread::sleep(Duration::from_millis(20)),
            Err(_) => { let _ = child.kill(); let _ = child.wait(); return Err("launchctl_unknown"); }
        }
    };
    if !status.success() { return Err("launchctl_failed"); }
    let bytes = rx.recv_timeout(Duration::from_millis(200)).map_err(|_| "launchctl_unknown")?;
    if bytes.len() > 4096 { return Err("launchctl_unknown"); }
    let text = String::from_utf8(bytes).map_err(|_| "launchctl_unknown")?;
    Ok(text.trim_end_matches(|character| character == '\r' || character == '\n').to_owned())
}
fn current_override(shutdown: &AtomicBool) -> Result<String, &'static str> {
    launchctl(&[OsStr::new("getenv"), OsStr::new("CODEX_CLI_PATH")], shutdown)
}
fn set_override(path: &Path, shutdown: &AtomicBool) -> Result<(), &'static str> {
    launchctl(&[OsStr::new("setenv"), OsStr::new("CODEX_CLI_PATH"), path.as_os_str()], shutdown).map(|_| ())
}
fn unset_override(shutdown: &AtomicBool) -> Result<(), &'static str> {
    launchctl(&[OsStr::new("unsetenv"), OsStr::new("CODEX_CLI_PATH")], shutdown).map(|_| ())
}
fn core() -> Result<PathBuf, &'static str> {
    let path = fs::canonicalize(std::env::current_exe().map_err(|_| "core_unavailable")?).map_err(|_| "core_unavailable")?;
    let macos = path.parent().filter(|dir| dir.file_name() == Some(OsStr::new("MacOS"))).ok_or("core_unstable")?;
    let contents = macos.parent().filter(|dir| dir.file_name() == Some(OsStr::new("Contents"))).ok_or("core_unstable")?;
    if contents.parent().and_then(Path::extension) != Some(OsStr::new("app")) { return Err("core_unstable"); }
    Ok(path)
}
fn binary(app: &Path) -> Result<PathBuf, &'static str> {
    ["Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex", "Contents/Resources/codex", "Contents/Resources/bin/codex"]
        .iter().filter_map(|relative| fs::canonicalize(app.join(relative)).ok())
        .find(|path| fs::metadata(path).is_ok_and(|meta| meta.is_file() && meta.permissions().mode() & 0o111 != 0))
        .ok_or("binary_missing")
}
fn acquire(paths: &Paths) -> Result<desktop_setup_files::SetupLock, &'static str> {
    desktop_setup_files::acquire(&paths.root, paths.agent.parent().ok_or("path_invalid")?)
}
fn abort(stage: StagedFiles, error: &'static str) -> Result<Value, &'static str> {
    if stage.abort().is_err() { Err("rollback_incomplete") } else { Err(error) }
}

/// Called only from an explicit settings action, never at application startup.
pub fn enable(app: &Path, shutdown: &AtomicBool) -> Result<Value, &'static str> {
    let home = home()?;
    let paths = desktop_setup::paths(&home)?;
    let guard = acquire(&paths)?;
    let baseline = guard.baseline(&paths)?;
    let initial = current_override(shutdown)?;
    if !desktop_setup::can_use_override(&initial, &paths.launcher) { return Err("override_conflict"); }
    let app = fs::canonicalize(app).map_err(|_| "app_missing")?;
    let core = core()?;
    let binary = binary(&app)?;
    let info = app.join("Contents/Info.plist");
    if !desktop_setup::app_supports_cli_override(&app) { return Err("override_unsupported"); }
    let receipt = crate::desktop_qualification::qualify(&binary, &info, shutdown)?;
    if shutdown.load(Ordering::Relaxed) || !desktop_setup::app_supports_cli_override(&app) { return Err("update_in_progress"); }
    if current_override(shutdown)? != initial { return Err("override_conflict"); }
    let plan = desktop_setup::plan(&home, &core, &app, receipt)?;
    let stage = guard.stage_checked(&plan, baseline)?;
    if !crate::desktop_launcher::compatible(&binary, &paths.receipt) || !desktop_setup::app_supports_cli_override(&app) {
        return abort(stage, "update_in_progress");
    }
    match current_override(shutdown) {
        Ok(current) if current == initial => {},
        _ => return abort(stage, "override_conflict"),
    }
    let launcher = paths.launcher.to_str().ok_or("path_invalid")?;
    let applied = set_override(&paths.launcher, shutdown);
    let after = current_override(shutdown);
    match (applied, after) {
        (Ok(()), Ok(current)) if current == launcher => {
            stage.retain(); Ok(json!({"status":"restart_required"}))
        }
        (_, Ok(current)) if current != launcher => abort(stage, "override_conflict"),
        _ => {
            // A lost launchctl acknowledgment may still have set the path. Keep
            // the launcher and receipt so an unknown outcome cannot break it.
            stage.retain(); Ok(json!({"status":"unknown"}))
        }
    }
}

fn owned_receipt(paths: &Paths) -> Option<Value> {
    let value = crate::desktop_launcher::read_receipt(&paths.receipt)?;
    if value.get("owner").and_then(Value::as_str) != Some(OWNER)
        || value.get("launcher").and_then(Value::as_str).map(Path::new) != Some(paths.launcher.as_path()) { return None; }
    Some(value)
}

/// Read-only status; never probes the CLI or changes launch environment.
pub fn status(shutdown: &AtomicBool) -> Result<Value, &'static str> {
    let home = home()?;
    let paths = desktop_setup::paths(&home)?;
    match crate::desktop_launcher::read_receipt(&paths.receipt) {
        Some(value) if value.get("owner").and_then(Value::as_str) != Some(OWNER) => return Ok(json!({"status":"file_conflict"})),
        None if fs::symlink_metadata(&paths.receipt).is_ok() => return Ok(json!({"status":"file_conflict"})),
        _ => {},
    }
    let Some(receipt) = owned_receipt(&paths) else { return Ok(json!({"status":"disabled"})); };
    if receipt.get("enabled").and_then(Value::as_bool) != Some(true) { return Ok(json!({"status":"disabled"})); }
    let current = current_override(shutdown)?;
    if !desktop_setup::can_use_override(&current, &paths.launcher) { return Ok(json!({"status":"conflict"})); }
    let info = receipt.get("appInfo").and_then(Value::as_str).map(Path::new).ok_or("file_conflict")?;
    let app = info.parent().and_then(Path::parent).ok_or("file_conflict")?;
    let binary = receipt.get("binary").and_then(Value::as_str).map(Path::new).ok_or("file_conflict")?;
    let plan = desktop_setup::plan(&home, &core()?, app, receipt.clone())?;
    if !desktop_setup_files::launcher_matches(&plan) || !crate::desktop_launcher::compatible(binary, &paths.receipt) {
        return Ok(json!({"status":"update_required"}));
    }
    Ok(json!({"status":if current.is_empty() { "restore_required" } else { "configured" }}))
}

/// Disable mediation before unsetting our override. A foreign override stays.
pub fn disable(shutdown: &AtomicBool) -> Result<Value, &'static str> {
    let home = home()?;
    let paths = desktop_setup::paths(&home)?;
    let guard = acquire(&paths)?;
    let ours = owned_receipt(&paths).is_some();
    let file_result = guard.disable(&paths);
    let launcher = paths.launcher.to_str().ok_or("path_invalid")?;
    let environment_result = match current_override(shutdown) {
        Ok(current) if ours && current == launcher => unset_override(shutdown),
        Ok(current) if !ours && current == launcher => Err("override_conflict"),
        Ok(_) => Ok(()),
        Err(error) => Err(error),
    };
    if let Err(error) = file_result { return Err(error); }
    if environment_result == Err("override_conflict") { return Ok(json!({"status":"conflict"})); }
    if environment_result.is_err() { return Ok(json!({"status":"unknown"})); }
    Ok(json!({"status":"disabled"}))
}

/// Login restoration only uses the exact existing, still-compatible setup.
pub fn restore(receipt_path: &Path, launcher_path: &Path, shutdown: &AtomicBool) -> Result<Value, &'static str> {
    let home = home()?;
    let paths = desktop_setup::paths(&home)?;
    if receipt_path != paths.receipt || launcher_path != paths.launcher { return Err("path_invalid"); }
    let Some(receipt) = owned_receipt(&paths) else { return Ok(json!({"status":"disabled"})); };
    if receipt.get("enabled").and_then(Value::as_bool) != Some(true) { return Ok(json!({"status":"disabled"})); }
    let guard = acquire(&paths)?;
    let receipt = owned_receipt(&paths).ok_or("file_changed")?;
    if receipt.get("enabled").and_then(Value::as_bool) != Some(true) { return Ok(json!({"status":"disabled"})); }
    let info = receipt.get("appInfo").and_then(Value::as_str).map(Path::new).ok_or("file_conflict")?;
    let app = info.parent().and_then(Path::parent).ok_or("file_conflict")?;
    let binary = receipt.get("binary").and_then(Value::as_str).map(Path::new).ok_or("file_conflict")?;
    let plan = desktop_setup::plan(&home, &core()?, app, receipt.clone())?;
    if !guard.matches_launcher(&plan) || !crate::desktop_launcher::compatible(binary, &paths.receipt)
        || !desktop_setup::app_supports_cli_override(app) {
        return Ok(json!({"status":"update_required"}));
    }
    let current = current_override(shutdown)?;
    if !desktop_setup::can_use_override(&current, &paths.launcher) { return Ok(json!({"status":"conflict"})); }
    if current.is_empty() {
        set_override(&paths.launcher, shutdown)?;
        if current_override(shutdown)? != paths.launcher.to_str().ok_or("path_invalid")? { return Ok(json!({"status":"conflict"})); }
    }
    Ok(json!({"status":"ready"}))
}
