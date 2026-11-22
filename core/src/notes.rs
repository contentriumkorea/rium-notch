//! Private storage for the notch's notes library.
use serde_json::Value;
use std::collections::HashSet;
use std::ffi::{c_char, CStr};
use std::fs::{self, DirBuilder, OpenOptions};
use std::io::{self, Read, Write};
use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

// shortcut: limits are protective Rium defaults; reference limits are unknown.
const MAX_FILE: usize = 4 * 1024 * 1024;
const MAX_NOTES: usize = 500;
static NEXT_FILE: AtomicU64 = AtomicU64::new(1);

#[no_mangle]
pub extern "C" fn rium_notes_save_delay() -> f64 { 0.35 }

fn valid_id(id: &str) -> bool {
    id.len() == 36 && id.bytes().enumerate().all(|(i, ch)| {
        if [8, 13, 18, 23].contains(&i) { ch == b'-' } else { ch.is_ascii_hexdigit() }
    })
}

fn valid_notes(bytes: &[u8]) -> bool {
    if bytes.len() > MAX_FILE { return false; }
    let Ok(value) = serde_json::from_slice::<Value>(bytes) else { return false; };
    let Some(entries) = value.as_array() else { return false; };
    if entries.len() > MAX_NOTES { return false; }
    let mut ids = HashSet::new();
    entries.iter().all(|entry| {
        let Some(obj) = entry.as_object() else { return false; };
        let Some(id) = obj.get("id").and_then(Value::as_str) else { return false; };
        valid_id(id) && ids.insert(id.to_ascii_lowercase())
            && obj.get("title").and_then(Value::as_str).is_some_and(|v| v.len() <= 8192)
            && obj.get("text").and_then(Value::as_str).is_some_and(|v| v.len() <= 1_048_576)
            && obj.get("createdAt").and_then(Value::as_f64).is_some_and(f64::is_finite)
            && obj.get("updatedAt").and_then(Value::as_f64).is_some_and(f64::is_finite)
    })
}

fn load(root: &Path) -> io::Result<Vec<u8>> {
    let file = match fs::File::open(root.join("notes.json")) {
        Ok(file) => file,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(b"[]".to_vec()),
        Err(error) => return Err(error),
    };
    let mut bytes = Vec::new();
    file.take((MAX_FILE + 1) as u64).read_to_end(&mut bytes)?;
    if !valid_notes(&bytes) { return Err(io::Error::new(io::ErrorKind::InvalidData, "invalid notes")); }
    Ok(bytes)
}

fn save(root: &Path, bytes: &[u8]) -> io::Result<()> {
    if !valid_notes(bytes) { return Err(io::Error::new(io::ErrorKind::InvalidInput, "invalid notes")); }
    DirBuilder::new().recursive(true).mode(0o700).create(root)?;
    let temporary = root.join(format!(".notes-{}-{}.tmp", std::process::id(), NEXT_FILE.fetch_add(1, Ordering::Relaxed)));
    let mut file = OpenOptions::new().write(true).create_new(true).mode(0o600).open(&temporary)?;
    let result = (|| { file.write_all(bytes)?; file.sync_all()?; fs::rename(&temporary, root.join("notes.json")) })();
    if result.is_err() { let _ = fs::remove_file(temporary); }
    result
}

unsafe fn root_path(path: *const c_char) -> Option<PathBuf> {
    if path.is_null() { return None; }
    let value = CStr::from_ptr(path).to_str().ok()?;
    if value.is_empty() { None } else { Some(PathBuf::from(value)) }
}

#[no_mangle]
pub unsafe extern "C" fn rium_notes_load(path: *const c_char, len: *mut usize) -> *mut u8 {
    if len.is_null() { return std::ptr::null_mut(); }
    *len = 0;
    let Some(root) = root_path(path) else { return std::ptr::null_mut(); };
    let Ok(bytes) = load(&root) else { return std::ptr::null_mut(); };
    let bytes = bytes.into_boxed_slice();
    *len = bytes.len();
    Box::into_raw(bytes) as *mut u8
}

#[no_mangle]
pub unsafe extern "C" fn rium_notes_save(path: *const c_char, bytes: *const u8, len: usize) -> i32 {
    let Some(root) = root_path(path) else { return -1; };
    if len > MAX_FILE || bytes.is_null() { return -2; }
    let data = std::slice::from_raw_parts(bytes, len);
    match save(&root, data) { Ok(()) => 0, Err(e) if e.kind() == io::ErrorKind::InvalidInput => -2, Err(_) => -1 }
}

#[no_mangle]
pub unsafe extern "C" fn rium_notes_free(ptr: *mut u8, len: usize) {
    if !ptr.is_null() { drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(ptr, len))); }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn checks_structure_and_duplicate_identifiers() {
        let valid = br#"[{"id":"12345678-1234-1234-1234-123456789abc","title":"a","text":"b","createdAt":1,"updatedAt":2}]"#;
        assert!(valid_notes(valid));
        assert!(!valid_notes(br#"[{"id":"bad","title":"a","text":"b","createdAt":1,"updatedAt":2}]"#));
        let repeated = format!("[{},{}]", std::str::from_utf8(&valid[1..valid.len()-1]).unwrap(), std::str::from_utf8(&valid[1..valid.len()-1]).unwrap());
        assert!(!valid_notes(repeated.as_bytes()));
        assert!(!valid_notes(b"[broken]"));
    }

    #[test]
    fn invalid_write_does_not_replace_saved_notes() {
        let root = std::env::temp_dir().join(format!("rium-notes-{}-{}", std::process::id(), NEXT_FILE.fetch_add(1, Ordering::Relaxed)));
        assert_eq!(load(&root).unwrap(), b"[]".to_vec());
        let data = br#"[{"id":"12345678-1234-1234-1234-123456789abc","title":"a","text":"b","createdAt":1,"updatedAt":2}]"#;
        save(&root, data).unwrap();
        assert!(save(&root, b"not valid json").is_err());
        assert_eq!(load(&root).unwrap(), data.to_vec());
        fs::remove_dir_all(root).unwrap();
    }
}
