//! Bounded clipboard history with private local persistence. Acquisition is opt-in.
use std::collections::VecDeque;
use std::ffi::{c_char, CStr, CString};
use std::fs::{self, DirBuilder, File, OpenOptions};
use std::io::{self, Read, Write};
use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;

const LIMIT: usize = 50;
const MAX_TEXT_BYTES: usize = 100_000;
const MAX_IMAGE_BYTES: usize = 8 * 1024 * 1024;
const MAX_TOTAL_BYTES: usize = 32 * 1024 * 1024;

#[derive(Clone)]
struct Entry { id: u64, kind: String, bytes: Vec<u8> }
#[derive(Clone)]
struct History { entries: VecDeque<Entry>, next_id: u64 }
static HISTORY: Mutex<History> = Mutex::new(History { entries: VecDeque::new(), next_id: 1 });
static NEXT_FILE: AtomicU64 = AtomicU64::new(1);
const MAGIC: &[u8; 6] = b"RCLP1\0";
const MAX_ARCHIVE: u64 = (MAX_TOTAL_BYTES + LIMIT * 5 + 10) as u64;

fn add(history: &mut History, kind: &str, bytes: &[u8]) -> bool {
    if bytes.is_empty() { return false; }
    match kind {
        "text" => match std::str::from_utf8(bytes) {
            Ok(s) if !s.trim().is_empty() && bytes.len() <= MAX_TEXT_BYTES => (),
            _ => return false,
        },
        "files" => {
            if bytes.len() > MAX_TEXT_BYTES { return false; }
            let valid = serde_json::from_slice::<Vec<String>>(bytes)
                .map(|v| !v.is_empty() && v.len() <= 100 && v.iter().all(|s| s.starts_with("file:")))
                .unwrap_or(false);
            if !valid { return false; }
        },
        "image/png" | "image/tiff" if bytes.len() <= MAX_IMAGE_BYTES => (),
        _ => return false,
    }
    if history.entries.front().is_some_and(|e| e.kind == kind && e.bytes == bytes) { return false; }
    history.entries.retain(|e| e.kind != kind || e.bytes != bytes);
    let id = history.next_id;
    let Some(next_id) = id.checked_add(1) else { return false; };
    history.next_id = next_id;
    history.entries.push_front(Entry { id, kind: kind.to_owned(), bytes: bytes.to_vec() });
    let mut total: usize = history.entries.iter().map(|e| e.bytes.len()).sum();
    while history.entries.len() > LIMIT || total > MAX_TOTAL_BYTES {
        if let Some(entry) = history.entries.pop_back() { total -= entry.bytes.len(); } else { break; }
    }
    true
}

/// `kind` must be a valid C string; `bytes` must address `len` readable bytes.
#[no_mangle]
pub unsafe extern "C" fn rium_clipboard_add_record(kind: *const c_char, bytes: *const u8, len: usize) -> bool {
    if kind.is_null() || bytes.is_null() || len == 0 || len > MAX_IMAGE_BYTES { return false; }
    let Ok(kind) = CStr::from_ptr(kind).to_str() else { return false; };
    add(&mut HISTORY.lock().unwrap_or_else(|e| e.into_inner()), kind, std::slice::from_raw_parts(bytes, len))
}

/// The caller owns the returned metadata JSON and must call `rium_clipboard_free`.
#[no_mangle]
pub extern "C" fn rium_clipboard_json() -> *mut c_char {
    let history = HISTORY.lock().unwrap_or_else(|e| e.into_inner());
    let metadata: Vec<_> = history.entries.iter().map(|e| serde_json::json!({"id":e.id,"kind":e.kind,"size":e.bytes.len()})).collect();
    CString::new(serde_json::to_string(&metadata).unwrap_or_else(|_| "[]".into())).expect("JSON contains no raw NUL").into_raw()
}

/// Returns an owned copy of a record; free it with `rium_clipboard_free_data`.
#[no_mangle]
pub unsafe extern "C" fn rium_clipboard_copy_data(id: u64, len: *mut usize) -> *mut u8 {
    if len.is_null() { return std::ptr::null_mut(); }
    *len = 0;
    let history = HISTORY.lock().unwrap_or_else(|e| e.into_inner());
    let Some(entry) = history.entries.iter().find(|e| e.id == id) else { return std::ptr::null_mut(); };
    let copy = entry.bytes.clone().into_boxed_slice();
    *len = copy.len();
    Box::into_raw(copy) as *mut u8
}

#[no_mangle]
pub unsafe extern "C" fn rium_clipboard_free_data(ptr: *mut u8, len: usize) {
    if !ptr.is_null() { drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(ptr, len))); }
}
#[no_mangle]
pub unsafe extern "C" fn rium_clipboard_free(value: *mut c_char) {
    if !value.is_null() { drop(CString::from_raw(value)); }
}
#[no_mangle]
pub extern "C" fn rium_clipboard_clear() { HISTORY.lock().unwrap_or_else(|e| e.into_inner()).entries.clear(); }

fn archive(history: &History) -> Vec<u8> {
    let mut out = Vec::new(); out.extend_from_slice(MAGIC);
    out.extend_from_slice(&(history.entries.len() as u32).to_le_bytes());
    for entry in &history.entries {
        let kind = match entry.kind.as_str() { "text" => 1, "files" => 2, "image/png" => 3, "image/tiff" => 4, _ => unreachable!() };
        out.push(kind); out.extend_from_slice(&(entry.bytes.len() as u32).to_le_bytes()); out.extend_from_slice(&entry.bytes);
    }
    out
}
fn unarchive(bytes: &[u8]) -> io::Result<History> {
    let bad = || io::Error::new(io::ErrorKind::InvalidData, "invalid clipboard archive");
    if bytes.len() < 10 || &bytes[..6] != MAGIC || bytes.len() as u64 > MAX_ARCHIVE { return Err(bad()); }
    let count = u32::from_le_bytes(bytes[6..10].try_into().map_err(|_| bad())?) as usize;
    if count > LIMIT { return Err(bad()); }
    let mut offset = 10usize; let mut entries = Vec::new(); let mut total = 0usize;
    for _ in 0..count {
        let header = bytes.get(offset..offset + 5).ok_or_else(bad)?; offset += 5;
        let kind = match header[0] { 1 => "text", 2 => "files", 3 => "image/png", 4 => "image/tiff", _ => return Err(bad()) };
        let len = u32::from_le_bytes(header[1..5].try_into().map_err(|_| bad())?) as usize;
        total = total.checked_add(len).ok_or_else(bad)?;
        if total > MAX_TOTAL_BYTES || len > MAX_IMAGE_BYTES { return Err(bad()); }
        let end = offset.checked_add(len).ok_or_else(bad)?;
        entries.push((kind, bytes.get(offset..end).ok_or_else(bad)?)); offset = end;
    }
    if offset != bytes.len() { return Err(bad()); }
    let mut history = History { entries: VecDeque::new(), next_id: 1 };
    for (kind, content) in entries.into_iter().rev() { if !add(&mut history, kind, content) { return Err(bad()); } }
    Ok(history)
}
fn save(root: &Path, history: &History) -> io::Result<()> {
    DirBuilder::new().recursive(true).mode(0o700).create(root)?;
    let temporary = root.join(format!(".clipboard-{}-{}.tmp", std::process::id(), NEXT_FILE.fetch_add(1, Ordering::Relaxed)));
    let mut file = OpenOptions::new().write(true).create_new(true).mode(0o600).open(&temporary)?;
    let result = (|| { file.write_all(&archive(history))?; file.sync_all()?; fs::rename(&temporary, root.join("clipboard.bin")) })();
    if result.is_err() { let _ = fs::remove_file(temporary); }
    result
}
fn load(root: &Path) -> io::Result<History> {
    let path = root.join("clipboard.bin");
    match fs::symlink_metadata(&path) {
        Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(History { entries: VecDeque::new(), next_id: 1 }),
        Err(e) => return Err(e),
        Ok(meta) if !meta.file_type().is_file() || meta.len() > MAX_ARCHIVE => return Err(io::Error::new(io::ErrorKind::InvalidData, "invalid clipboard file")),
        Ok(_) => (),
    }
    let mut bytes = Vec::new(); File::open(path)?.take(MAX_ARCHIVE + 1).read_to_end(&mut bytes)?;
    unarchive(&bytes)
}
unsafe fn root_path(path: *const c_char) -> Option<PathBuf> {
    if path.is_null() { return None; }
    let path = CStr::from_ptr(path).to_str().ok()?;
    if path.is_empty() { None } else { Some(PathBuf::from(path)) }
}
#[no_mangle]
pub unsafe extern "C" fn rium_clipboard_save(path: *const c_char) -> i32 {
    let Some(root) = root_path(path) else { return -1; };
    let snapshot = HISTORY.lock().unwrap_or_else(|e| e.into_inner()).clone();
    if save(&root, &snapshot).is_ok() { 0 } else { -1 }
}
#[no_mangle]
pub unsafe extern "C" fn rium_clipboard_load(path: *const c_char) -> i32 {
    let Some(root) = root_path(path) else { return -1; };
    let Ok(history) = load(&root) else { return -1; };
    *HISTORY.lock().unwrap_or_else(|e| e.into_inner()) = history; 0
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;
    #[test]
    fn typed_records_are_bounded_deduplicated_and_recent_first() {
        let mut h = History { entries: VecDeque::new(), next_id: 1 };
        assert!(!add(&mut h, "text", b"  "));
        assert!(!add(&mut h, "files", br#"["https://example.com"]"#));
        assert!(add(&mut h, "files", br#"["file:///tmp/example"]"#));
        assert!(add(&mut h, "image/png", &[1, 2, 3]));
        assert!(!add(&mut h, "image/png", &[1, 2, 3]));
        assert!(!add(&mut h, "image/png", &vec![0; MAX_IMAGE_BYTES + 1]));
        for i in 0..55 { assert!(add(&mut h, "text", i.to_string().as_bytes())); }
        assert_eq!(h.entries.len(), 50);
        assert_eq!(h.entries.front().unwrap().bytes, b"54");
        assert!(add(&mut h, "text", b"10"));
        assert_eq!(h.entries.iter().filter(|e| e.bytes == b"10").count(), 1);
        let mut h = History { entries: VecDeque::new(), next_id: 1 };
        for i in 0..5 { assert!(add(&mut h, "image/png", &vec![i; MAX_IMAGE_BYTES])); }
        assert_eq!(h.entries.len(), 4);
    }
    #[test]
    fn private_archive_round_trips_and_rejects_corruption() {
        let root = std::env::temp_dir().join(format!("rium-clipboard-store-{}-{}", std::process::id(), NEXT_FILE.fetch_add(1, Ordering::Relaxed)));
        let mut history = History { entries: VecDeque::new(), next_id: 1 };
        assert!(add(&mut history, "text", "첫 기록".as_bytes()));
        assert!(add(&mut history, "files", br#"["file:///tmp/test"]"#));
        assert!(add(&mut history, "image/png", &[1, 2, 3]));
        save(&root, &history).unwrap();
        assert_eq!(fs::metadata(root.join("clipboard.bin")).unwrap().permissions().mode() & 0o777, 0o600);
        let restored = load(&root).unwrap();
        assert_eq!(restored.entries.len(), 3);
        assert_eq!(restored.entries[0].kind, "image/png"); assert_eq!(restored.entries[2].bytes, "첫 기록".as_bytes());
        let mut bad = archive(&history); bad.pop(); assert!(unarchive(&bad).is_err());
        bad = archive(&history); bad.push(0); assert!(unarchive(&bad).is_err());
        fs::remove_dir_all(root).unwrap();
    }
}
