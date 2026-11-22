//! Preparation for an opt-in Desktop launcher. Building a plan is pure; it
//! does not create files, set launch environment variables, or quit Codex.
use serde_json::{json, Value};
use std::fs::{self, File};
use std::io::{Read, Seek, SeekFrom};
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};

pub(crate) const OWNER: &str = "app.rium.notch.codex-desktop";
pub(crate) const MARKER: &str = "Rium Notch Codex Desktop launcher v1";

pub struct Plan {
    pub receipt_path: PathBuf,
    pub launcher_path: PathBuf,
    pub agent_path: PathBuf,
    pub receipt: Value,
    pub launcher: String,
    pub agent: String,
}

pub struct Paths { pub root: PathBuf, pub receipt: PathBuf, pub launcher: PathBuf, pub agent: PathBuf }

pub fn paths(home: &Path) -> Result<Paths, &'static str> {
    let home = Path::new(path_text(home).ok_or("home_invalid")?);
    let root = home.join("Library/Application Support/Rium Notch/CodexDesktop");
    Ok(Paths { receipt: root.join("connection.json"), launcher: root.join("codex-launcher"),
        agent: home.join("Library/LaunchAgents/app.rium.notch.codex-desktop.plist"), root })
}

fn path_text(path: &Path) -> Option<&str> {
    let text = path.to_str()?;
    (path.is_absolute() && text.len() <= 4096 && !text.chars().any(char::is_control)).then_some(text)
}
fn shell_quote(value: &str) -> String { format!("'{}'", value.replace('\'', "'\\''")) }
fn xml(value: &str) -> String {
    value.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;").replace('"', "&quot;").replace('\'', "&apos;")
}

fn asar_supports_override(reader: &mut (impl Read + Seek), length: u64) -> bool {
    let mut header = [0u8; 16];
    if reader.read_exact(&mut header).is_err() { return false; }
    let header_length = u32::from_le_bytes([header[4], header[5], header[6], header[7]]) as u64;
    let json_length = u32::from_le_bytes([header[12], header[13], header[14], header[15]]) as u64;
    if json_length == 0 || json_length > 16 * 1024 * 1024 { return false; }
    let Some(data_offset) = 8u64.checked_add(header_length) else { return false; };
    if 16u64.checked_add(json_length).map_or(true, |end| end > data_offset || end > length) { return false; }
    let mut bytes = vec![0u8; json_length as usize];
    if reader.read_exact(&mut bytes).is_err() { return false; }
    let Ok(header) = serde_json::from_slice::<Value>(&bytes) else { return false; };
    let Some(files) = header.pointer("/files/.vite/files/build/files").and_then(Value::as_object) else { return false; };
    const NEEDLE: &[u8] = b"CODEX_CLI_PATH";
    for (_, file) in files.iter().filter(|(name, _)| name.starts_with("main-") && name.ends_with(".js")).take(128) {
        let Some(offset) = file.get("offset").and_then(Value::as_str).and_then(|offset| offset.parse::<u64>().ok()) else { continue; };
        let Some(size) = file.get("size").and_then(Value::as_u64).filter(|size| *size <= 64 * 1024 * 1024) else { continue; };
        let Some(start) = data_offset.checked_add(offset) else { continue; };
        if start.checked_add(size).map_or(true, |end| end > length) || reader.seek(SeekFrom::Start(start)).is_err() { continue; }
        let mut remaining = size;
        let mut carry = Vec::new();
        let mut chunk = [0u8; 16_384];
        while remaining > 0 {
            let take = remaining.min(chunk.len() as u64) as usize;
            if reader.read_exact(&mut chunk[..take]).is_err() { break; }
            carry.extend_from_slice(&chunk[..take]);
            if carry.windows(NEEDLE.len()).any(|window| window == NEEDLE) { return true; }
            if carry.len() >= NEEDLE.len() {
                let trim = carry.len() - (NEEDLE.len() - 1);
                carry.drain(..trim);
            }
            remaining -= take as u64;
        }
    }
    false
}

/// Checks only whether the shipped Desktop bundle refers to the override.
/// Protocol compatibility and signature checks are separate requirements.
pub fn app_supports_cli_override(app: &Path) -> bool {
    let path = app.join("Contents/Resources/app.asar");
    let Ok(meta) = fs::symlink_metadata(&path) else { return false; };
    if !meta.file_type().is_file() { return false; }
    let Ok(mut file) = File::open(&path) else { return false; };
    let Ok(opened) = file.metadata() else { return false; };
    if opened.dev() != meta.dev() || opened.ino() != meta.ino() { return false; }
    let supported = asar_supports_override(&mut file, opened.len());
    let unchanged = |latest: &fs::Metadata| latest.file_type().is_file() && latest.dev() == opened.dev() && latest.ino() == opened.ino()
        && latest.len() == opened.len() && latest.mtime() == opened.mtime() && latest.mtime_nsec() == opened.mtime_nsec()
        && latest.ctime() == opened.ctime() && latest.ctime_nsec() == opened.ctime_nsec();
    supported && file.metadata().is_ok_and(|latest| unchanged(&latest))
        && fs::symlink_metadata(&path).is_ok_and(|latest| unchanged(&latest))
}

/// Never replace an environment override already selected by another tool.
pub fn can_use_override(current: &str, launcher: &Path) -> bool {
    current.is_empty() || path_text(launcher).is_some_and(|ours| current == ours)
}

/// The receipt must come from the explicit isolated qualification, not from a
/// version string or a user-provided list of approved versions.
pub fn plan(home: &Path, core: &Path, app: &Path, mut receipt: Value) -> Result<Plan, &'static str> {
    path_text(home).ok_or("home_invalid")?;
    let core_text = path_text(core).ok_or("core_invalid")?;
    path_text(app).ok_or("app_invalid")?;
    if ["/tmp/", "/private/tmp/", "/Volumes/"].iter().any(|prefix| core_text.starts_with(prefix))
        || core_text.contains("/AppTranslocation/") { return Err("core_unstable"); }
    if core.file_name().and_then(|name| name.to_str()) != Some("rium-notch-core") { return Err("core_invalid"); }
    if receipt.get("enabled").and_then(Value::as_bool) != Some(true)
        || receipt.get("validated").and_then(Value::as_bool) != Some(true)
        || receipt.get("contract").and_then(Value::as_str) != Some(crate::desktop_launcher::CONTRACT) { return Err("qualification_missing"); }
    let binary = receipt.get("binary").and_then(Value::as_str).map(Path::new).ok_or("qualification_missing")?;
    let info = receipt.get("appInfo").and_then(Value::as_str).map(Path::new).ok_or("qualification_missing")?;
    let binary_text = path_text(binary).ok_or("binary_invalid")?;
    if !binary.starts_with(app.join("Contents/Resources")) || info != app.join("Contents/Info.plist") { return Err("app_mismatch"); }
    let Paths { receipt: receipt_path, launcher: launcher_path, agent: agent_path, .. } = paths(home)?;
    let receipt_text = path_text(&receipt_path).ok_or("path_invalid")?;
    let launcher_text = path_text(&launcher_path).ok_or("path_invalid")?;
    let agent_label = OWNER;
    let mut launcher = format!("#!/bin/sh\n# {MARKER}\nif [ -x {} ]; then\n  exec {} desktop-launcher --binary {} --receipt {} -- \"$@\"\nfi\n",
        shell_quote(core_text), shell_quote(core_text), shell_quote(binary_text), shell_quote(receipt_text));
    let candidates = [binary.to_path_buf(), app.join("Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"),
        app.join("Contents/Resources/codex"), app.join("Contents/Resources/bin/codex")];
    for candidate in candidates {
        let candidate = path_text(&candidate).ok_or("path_invalid")?;
        let quoted = shell_quote(candidate);
        launcher.push_str(&format!("if [ -x {quoted} ]; then\n  export CODEX_CLI_PATH={quoted}\n  exec {quoted} \"$@\"\nfi\n"));
    }
    launcher.push_str("exit 127\n");
    let agent = format!("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!-- {MARKER} -->\n<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\"><dict><key>Label</key><string>{}</string><key>ProgramArguments</key><array><string>{}</string><string>desktop-restore</string><string>{}</string><string>{}</string></array><key>RunAtLoad</key><true/></dict></plist>\n",
        xml(agent_label), xml(core_text), xml(receipt_text), xml(launcher_text));
    let object = receipt.as_object_mut().ok_or("qualification_missing")?;
    object.insert("owner".into(), json!(OWNER));
    object.insert("launcher".into(), json!(launcher_text));
    object.insert("core".into(), json!(core_text));
    Ok(Plan { receipt_path, launcher_path, agent_path, receipt, launcher, agent })
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn quotes_paths_and_preserves_foreign_overrides() {
        let home = Path::new("/Users/example");
        let core = Path::new("/Applications/Rium 'Notch'.app/Contents/MacOS/rium-notch-core");
        let app = Path::new("/Applications/Codex.app");
        let receipt = json!({"enabled":true,"validated":true,"contract":crate::desktop_launcher::CONTRACT,
            "binary":"/Applications/Codex.app/Contents/Resources/codex", "appInfo":"/Applications/Codex.app/Contents/Info.plist"});
        let plan = plan(home, core, app, receipt).unwrap();
        assert!(plan.launcher.contains("Rium '\\''Notch'\\''"));
        assert!(plan.agent.contains("Rium &apos;Notch&apos;"));
        assert!(can_use_override("", &plan.launcher_path));
        assert!(!can_use_override("/other/tool", &plan.launcher_path));
    }
    #[test]
    fn asar_scan_is_bounded_to_the_main_bundle_entry() {
        fn archive(payload: &[u8]) -> Vec<u8> {
            let header = json!({"files":{".vite":{"files":{"build":{"files":{"main-a.js":{"offset":"0","size":payload.len()}}}}}}});
            let data = serde_json::to_vec(&header).unwrap();
            let mut bytes = vec![0u8; 16];
            bytes[4..8].copy_from_slice(&((8 + data.len()) as u32).to_le_bytes());
            bytes[12..16].copy_from_slice(&(data.len() as u32).to_le_bytes());
            bytes.extend_from_slice(&data); bytes.extend_from_slice(payload); bytes
        }
        let good = archive(b"prefix CODEX_CLI_PATH suffix");
        let bad = archive(b"no override here");
        assert!(asar_supports_override(&mut std::io::Cursor::new(&good), good.len() as u64));
        assert!(!asar_supports_override(&mut std::io::Cursor::new(&bad), bad.len() as u64));
        assert!(!asar_supports_override(&mut std::io::Cursor::new(&good[..8]), 8));
    }
}
