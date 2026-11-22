//! Reversible file stage for an explicitly requested Desktop integration.
//! It never modifies launchctl or any Codex bundle.
use crate::desktop_setup::{Paths, Plan, MARKER, OWNER};
use serde_json::Value;
use std::fs::{self, DirBuilder, File, OpenOptions};
use std::io::{Read, Write};
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::{DirBuilderExt, MetadataExt, OpenOptionsExt, PermissionsExt};
use std::os::unix::io::AsRawFd;
use std::path::{Path, PathBuf};

extern "C" {
    fn geteuid() -> u32;
    fn renamex_np(from: *const std::ffi::c_char, to: *const std::ffi::c_char, flags: u32) -> i32;
    fn flock(fd: i32, operation: i32) -> i32;
}
const FILE_LIMIT: u64 = 1_048_576;
const RENAME_SWAP: u32 = 0x00000002;
const RENAME_EXCL: u32 = 0x00000004;

#[derive(Clone, PartialEq, Eq)]
struct Snapshot { bytes: Vec<u8>, mode: u32, device: u64, inode: u64 }

fn current(path: &Path) -> Result<Option<Snapshot>, &'static str> {
    let meta = match fs::symlink_metadata(path) {
        Ok(meta) => meta,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(_) => return Err("file_unavailable"),
    };
    if !meta.file_type().is_file() || meta.uid() != unsafe { geteuid() } || meta.len() > FILE_LIMIT { return Err("file_conflict"); }
    let file = File::open(path).map_err(|_| "file_unavailable")?;
    let opened = file.metadata().map_err(|_| "file_unavailable")?;
    if opened.dev() != meta.dev() || opened.ino() != meta.ino() { return Err("file_changed"); }
    let mut bytes = Vec::new();
    file.take(FILE_LIMIT + 1).read_to_end(&mut bytes).map_err(|_| "file_unavailable")?;
    if bytes.len() as u64 > FILE_LIMIT { return Err("file_conflict"); }
    Ok(Some(Snapshot { bytes, mode: meta.mode() & 0o777, device: meta.dev(), inode: meta.ino() }))
}

fn owned_receipt(bytes: &[u8]) -> bool {
    serde_json::from_slice::<Value>(bytes).ok().and_then(|value| value.get("owner").and_then(Value::as_str).map(str::to_owned)).as_deref() == Some(OWNER)
}
fn owned_launcher(bytes: &[u8]) -> bool {
    std::str::from_utf8(bytes).ok().is_some_and(|text| text.starts_with(&format!("#!/bin/sh\n# {MARKER}\n")))
}
fn owned_agent(bytes: &[u8]) -> bool {
    std::str::from_utf8(bytes).ok().is_some_and(|text| text.starts_with(&format!("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!-- {MARKER} -->\n")) && text.contains(OWNER))
}

fn ensure_directory(path: &Path) -> Result<(), &'static str> {
    DirBuilder::new().recursive(true).mode(0o700).create(path).map_err(|_| "directory_unavailable")?;
    let meta = fs::symlink_metadata(path).map_err(|_| "directory_unavailable")?;
    if !meta.file_type().is_dir() || meta.uid() != unsafe { geteuid() } || meta.mode() & 0o022 != 0 { return Err("directory_conflict"); }
    Ok(())
}

// Keeping the descriptor open holds the lock; a crash releases it without a
// stale directory preventing the next setup attempt.
struct Lock { _file: File }
fn lock(path: &Path) -> Result<Lock, &'static str> {
    const O_NOFOLLOW: i32 = 0x00000100;
    const O_CLOEXEC: i32 = 0x01000000;
    const LOCK_EX_NB: i32 = 0x02 | 0x04;
    let file = OpenOptions::new().read(true).write(true).create(true).mode(0o600)
        .custom_flags(O_NOFOLLOW | O_CLOEXEC).open(path).map_err(|_| "setup_busy")?;
    let opened = file.metadata().map_err(|_| "setup_busy")?;
    let named = fs::symlink_metadata(path).map_err(|_| "setup_busy")?;
    if !opened.file_type().is_file() || !named.file_type().is_file() || opened.uid() != unsafe { geteuid() }
        || opened.mode() & 0o077 != 0 || opened.dev() != named.dev() || opened.ino() != named.ino() { return Err("setup_busy"); }
    if unsafe { flock(file.as_raw_fd(), LOCK_EX_NB) } != 0 { return Err("setup_busy"); }
    let latest = fs::symlink_metadata(path).map_err(|_| "setup_busy")?;
    if latest.dev() != opened.dev() || latest.ino() != opened.ino() || !latest.file_type().is_file() { return Err("setup_busy"); }
    Ok(Lock { _file: file })
}

fn random_suffix() -> Result<String, &'static str> {
    let mut bytes = [0u8; 16];
    File::open("/dev/urandom").and_then(|mut file| file.read_exact(&mut bytes)).map_err(|_| "random_unavailable")?;
    Ok(bytes.iter().map(|byte| format!("{byte:02x}")).collect())
}

struct Holding { directory: PathBuf, preserve: bool }
impl Drop for Holding {
    fn drop(&mut self) {
        if !self.preserve { let _ = fs::remove_file(self.directory.join("file")); let _ = fs::remove_dir(&self.directory); }
    }
}
fn rename_atomic(from: &Path, to: &Path, flags: u32) -> bool {
    let Ok(from) = std::ffi::CString::new(from.as_os_str().as_bytes()) else { return false; };
    let Ok(to) = std::ffi::CString::new(to.as_os_str().as_bytes()) else { return false; };
    unsafe { renamex_np(from.as_ptr(), to.as_ptr(), flags) == 0 }
}

fn replace(path: &Path, expected: &Option<Snapshot>, bytes: &[u8], mode: u32) -> Result<(), &'static str> {
    if bytes.len() as u64 > FILE_LIMIT { return Err("file_too_large"); }
    let parent = path.parent().ok_or("path_invalid")?;
    let directory = parent.join(format!(".rium-stage-{}", random_suffix()?));
    DirBuilder::new().mode(0o700).create(&directory).map_err(|_| "file_unavailable")?;
    let mut holding = Holding { directory, preserve: false };
    let temporary = holding.directory.join("file");
    let mut file = OpenOptions::new().write(true).create_new(true).mode(mode).open(&temporary).map_err(|_| "file_unavailable")?;
    let written = file.write_all(bytes).and_then(|_| file.set_permissions(fs::Permissions::from_mode(mode))).and_then(|_| file.sync_all());
    drop(file);
    if written.is_err() { return Err("file_unavailable"); }
    let staged = current(&temporary)?.ok_or("file_unavailable")?;
    match current(path) {
        Ok(value) if value.as_ref() == expected.as_ref() => {},
        Ok(_) => return Err("file_changed"),
        Err(error) => return Err(error),
    }
    if expected.is_none() {
        return if rename_atomic(&temporary, path, RENAME_EXCL) { Ok(()) } else { Err("file_changed") };
    }
    if !rename_atomic(&temporary, path, RENAME_SWAP) { return Err("atomic_swap_unavailable"); }
    holding.preserve = true;
    if current(&temporary).ok().flatten().as_ref() == expected.as_ref() {
        holding.preserve = false;
        return Ok(());
    }
    if current(path).ok().flatten().as_ref() == Some(&staged) && rename_atomic(&temporary, path, RENAME_SWAP)
        && current(&temporary).ok().flatten().as_ref() == Some(&staged) {
        holding.preserve = false;
        return Err("file_changed");
    }
    Err("recovery_required")
}

// Move into a private directory before checking; a racing replacement is kept
// in that directory if it cannot be restored without overwriting another file.
fn remove_if_unchanged(path: &Path, expected: &Snapshot) -> bool {
    let Some(parent) = path.parent() else { return false; };
    let Ok(suffix) = random_suffix() else { return false; };
    let holding = parent.join(format!(".rium-recovery-{suffix}"));
    if DirBuilder::new().mode(0o700).create(&holding).is_err() { return false; }
    let moved = holding.join("file");
    if fs::rename(path, &moved).is_err() { let _ = fs::remove_dir(&holding); return false; }
    if current(&moved).ok().flatten().as_ref() == Some(expected) {
        let removed = fs::remove_file(&moved).is_ok();
        if removed { let _ = fs::remove_dir(&holding); }
        return removed;
    }
    if fs::hard_link(&moved, path).is_ok() {
        let _ = fs::remove_file(&moved);
        let _ = fs::remove_dir(&holding);
    }
    false
}

struct Entry { path: PathBuf, old: Option<Snapshot>, new: Vec<u8>, mode: u32 }

pub struct SetupLock { lock: Lock, root: PathBuf, agent_root: PathBuf }
pub struct Baseline { receipt: Option<Snapshot>, launcher: Option<Snapshot>, agent: Option<Snapshot> }

/// Hold this through qualification and environment changes so another Rium
/// setup or opt-out cannot race a long-running compatibility probe.
pub fn acquire(root: &Path, agent_root: &Path) -> Result<SetupLock, &'static str> {
    ensure_directory(root)?;
    ensure_directory(agent_root)?;
    let guard = lock(&root.join(".maintenance.lock"))?;
    Ok(SetupLock { lock: guard, root: root.to_owned(), agent_root: agent_root.to_owned() })
}

/// Until retained, dropping this stage restores only files that still contain
/// its bytes; a racing file is preserved in a private recovery directory.
pub struct StagedFiles { _lock: Lock, entries: Vec<Entry>, applied: usize, retained: bool }
impl StagedFiles {
    pub fn retain(mut self) { self.retained = true; }
    pub fn abort(mut self) -> Result<(), &'static str> {
        let restored = self.rollback();
        self.retained = true;
        if restored { Ok(()) } else { Err("rollback_incomplete") }
    }
    fn rollback(&mut self) -> bool {
        let mut restored = true;
        for entry in self.entries[..self.applied].iter().rev() {
            let now = match current(&entry.path) {
                Ok(Some(now)) => now,
                Ok(None) if entry.old.is_none() => continue,
                _ => { restored = false; continue; }
            };
            if now.bytes != entry.new || now.mode != entry.mode { restored = false; continue; }
            match &entry.old {
                Some(old) => if replace(&entry.path, &Some(now), &old.bytes, old.mode).is_err() { restored = false; },
                None => if !remove_if_unchanged(&entry.path, &now) { restored = false; },
            }
        }
        self.applied = 0;
        restored
    }
}
impl Drop for StagedFiles { fn drop(&mut self) { if !self.retained { let _ = self.rollback(); } } }

/// Stage owned files only after qualification has succeeded. Caller must keep
/// the returned guard until it has decided whether the stage can be retained.
pub fn stage(plan: &Plan) -> Result<StagedFiles, &'static str> {
    let root = plan.receipt_path.parent().ok_or("path_invalid")?;
    let agent_root = plan.agent_path.parent().ok_or("path_invalid")?;
    acquire(root, agent_root)?.stage(plan)
}

impl SetupLock {
  pub fn matches_launcher(&self, plan: &Plan) -> bool {
    if plan.launcher_path.parent() != Some(self.root.as_path()) { return false; }
    launcher_matches(plan)
  }

  pub fn stage(self, plan: &Plan) -> Result<StagedFiles, &'static str> {
    let baseline = self.baseline_paths(&plan.receipt_path, &plan.launcher_path, &plan.agent_path)?;
    self.stage_checked(plan, baseline)
  }

  fn baseline_paths(&self, receipt_path: &Path, launcher_path: &Path, agent_path: &Path) -> Result<Baseline, &'static str> {
    if receipt_path.parent() != Some(self.root.as_path()) || launcher_path.parent() != Some(self.root.as_path())
        || agent_path.parent() != Some(self.agent_root.as_path()) { return Err("path_invalid"); }
    let receipt = current(receipt_path)?;
    let launcher = current(launcher_path)?;
    let agent = current(agent_path)?;
    if receipt.as_ref().is_some_and(|file| !owned_receipt(&file.bytes))
        || launcher.as_ref().is_some_and(|file| !owned_launcher(&file.bytes))
        || agent.as_ref().is_some_and(|file| !owned_agent(&file.bytes)) { return Err("file_conflict"); }
    Ok(Baseline { receipt, launcher, agent })
  }

  pub fn baseline(&self, paths: &Paths) -> Result<Baseline, &'static str> {
    self.baseline_paths(&paths.receipt, &paths.launcher, &paths.agent)
  }

  pub fn stage_checked(self, plan: &Plan, baseline: Baseline) -> Result<StagedFiles, &'static str> {
    if plan.receipt_path.parent() != Some(self.root.as_path()) || plan.launcher_path.parent() != Some(self.root.as_path())
        || plan.agent_path.parent() != Some(self.agent_root.as_path()) { return Err("path_invalid"); }
    if current(&plan.receipt_path)?.as_ref() != baseline.receipt.as_ref() || current(&plan.launcher_path)?.as_ref() != baseline.launcher.as_ref()
        || current(&plan.agent_path)?.as_ref() != baseline.agent.as_ref() { return Err("file_changed"); }
    let mut receipt_data = serde_json::to_vec_pretty(&plan.receipt).map_err(|_| "receipt_invalid")?;
    receipt_data.push(b'\n');
    let entries = vec![
        Entry { path: plan.launcher_path.clone(), old: baseline.launcher, new: plan.launcher.as_bytes().to_vec(), mode: 0o700 },
        Entry { path: plan.agent_path.clone(), old: baseline.agent, new: plan.agent.as_bytes().to_vec(), mode: 0o600 },
        Entry { path: plan.receipt_path.clone(), old: baseline.receipt, new: receipt_data, mode: 0o600 },
    ];
    let mut staged = StagedFiles { _lock: self.lock, entries, applied: 0, retained: false };
    for index in 0..staged.entries.len() {
        let entry = &staged.entries[index];
        if let Err(error) = replace(&entry.path, &entry.old, &entry.new, entry.mode) {
            let restored = staged.rollback();
            staged.retained = true;
            return Err(if restored { error } else { "rollback_incomplete" });
        }
        staged.applied = index + 1;
    }
    Ok(staged)
  }

  /// Disable the receipt first so a remaining launcher always falls back to
  /// the official CLI, then remove only our unchanged login item.
  pub fn disable(&self, paths: &Paths) -> Result<bool, &'static str> {
    if paths.receipt.parent() != Some(self.root.as_path()) || paths.agent.parent() != Some(self.agent_root.as_path()) { return Err("path_invalid"); }
    let receipt = current(&paths.receipt)?;
    if receipt.as_ref().is_some_and(|file| !owned_receipt(&file.bytes)) { return Err("file_conflict"); }
    if let Some(receipt) = &receipt {
        let mut value: Value = serde_json::from_slice(&receipt.bytes).map_err(|_| "file_conflict")?;
        value.as_object_mut().ok_or("file_conflict")?.insert("enabled".into(), Value::Bool(false));
        let mut bytes = serde_json::to_vec_pretty(&value).map_err(|_| "file_conflict")?;
        bytes.push(b'\n');
        replace(&paths.receipt, &Some(receipt.clone()), &bytes, 0o600)?;
    }
    let agent = current(&paths.agent)?;
    if agent.as_ref().is_some_and(|file| !owned_agent(&file.bytes)) { return Err("file_conflict"); }
    if let Some(agent) = &agent {
        if !remove_if_unchanged(&paths.agent, agent) { return Err("recovery_required"); }
    }
    Ok(receipt.is_some() || agent.is_some())
  }
}

pub fn launcher_matches(plan: &Plan) -> bool {
    current(&plan.launcher_path).ok().flatten().is_some_and(|file| {
        file.mode == 0o700 && file.bytes == plan.launcher.as_bytes() && owned_launcher(&file.bytes)
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    #[test]
    fn unrelated_files_are_not_recognized_as_owned() {
        assert!(!owned_receipt(br#"{"owner":"other"}"#));
        assert!(!owned_launcher(b"#!/bin/sh\necho hello\n"));
        assert!(!owned_agent(b"<plist/>"));
        assert!(owned_receipt(format!("{{\"owner\":\"{OWNER}\"}}").as_bytes()));
    }
    #[test]
    fn rollback_preserves_a_foreign_edit_and_removes_unchanged_new_files() {
        let root = std::env::temp_dir().join(format!("rium-stage-test-{}", random_suffix().unwrap()));
        fs::create_dir(&root).unwrap();
        let receipt = json!({"enabled":true,"validated":true,"contract":crate::desktop_launcher::CONTRACT,
            "binary":"/Applications/Codex.app/Contents/Resources/codex", "appInfo":"/Applications/Codex.app/Contents/Info.plist"});
        let plan = crate::desktop_setup::plan(&root, Path::new("/Applications/Rium.app/Contents/MacOS/rium-notch-core"),
            Path::new("/Applications/Codex.app"), receipt).unwrap();
        let files = stage(&plan).unwrap();
        fs::write(&plan.launcher_path, b"a later edit").unwrap();
        assert!(files.abort().is_err());
        assert_eq!(fs::read(&plan.launcher_path).unwrap(), b"a later edit".to_vec());
        assert!(!plan.receipt_path.exists());
        assert!(!plan.agent_path.exists());
        fs::remove_dir_all(root).unwrap();
    }
    #[test]
    fn replacement_rejects_a_changed_or_unexpected_file() {
        let root = std::env::temp_dir().join(format!("rium-replace-test-{}", random_suffix().unwrap()));
        fs::create_dir(&root).unwrap();
        let path = root.join("config");
        fs::write(&path, b"original").unwrap();
        let before = current(&path).unwrap();
        fs::write(&path, b"changed elsewhere").unwrap();
        assert_eq!(replace(&path, &before, b"ours", 0o600), Err("file_changed"));
        assert_eq!(replace(&path, &None, b"ours", 0o600), Err("file_changed"));
        assert_eq!(fs::read(&path).unwrap(), b"changed elsewhere".to_vec());
        fs::remove_dir_all(root).unwrap();
    }
    #[test]
    fn lock_is_reusable_after_the_owner_drops_it() {
        let root = std::env::temp_dir().join(format!("rium-lock-test-{}", random_suffix().unwrap()));
        fs::create_dir(&root).unwrap();
        let path = root.join("lock");
        let first = lock(&path).unwrap();
        assert!(lock(&path).is_err());
        drop(first);
        assert!(lock(&path).is_ok());
        fs::remove_dir_all(root).unwrap();
    }
    #[test]
    fn disable_turns_off_receipt_and_removes_only_our_login_item() {
        let root = std::env::temp_dir().join(format!("rium-disable-test-{}", random_suffix().unwrap()));
        fs::create_dir(&root).unwrap();
        let receipt = json!({"enabled":true,"validated":true,"contract":crate::desktop_launcher::CONTRACT,
            "binary":"/Applications/Codex.app/Contents/Resources/codex", "appInfo":"/Applications/Codex.app/Contents/Info.plist"});
        let plan = crate::desktop_setup::plan(&root, Path::new("/Applications/Rium.app/Contents/MacOS/rium-notch-core"),
            Path::new("/Applications/Codex.app"), receipt).unwrap();
        stage(&plan).unwrap().retain();
        let paths = crate::desktop_setup::paths(&root).unwrap();
        let guard = acquire(&paths.root, paths.agent.parent().unwrap()).unwrap();
        assert!(guard.disable(&paths).unwrap());
        let saved: Value = serde_json::from_slice(&fs::read(&paths.receipt).unwrap()).unwrap();
        assert_eq!(saved["enabled"], false);
        assert!(!paths.agent.exists());
        assert!(paths.launcher.exists());
        drop(guard);
        fs::remove_dir_all(root).unwrap();
    }
}
