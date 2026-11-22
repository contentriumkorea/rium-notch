//! Bounded clipboard history with private local persistence. Acquisition is opt-in.
use std::collections::VecDeque;
use std::ffi::{c_char, CStr, CString};
use std::fs::{self, DirBuilder, File, OpenOptions};
use std::io::{self, BufWriter, Read, Write};
use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{SystemTime, UNIX_EPOCH};

#[no_mangle]
pub extern "C" fn rium_clipboard_preview_duration() -> f64 { 1.8 }

#[no_mangle]
pub extern "C" fn rium_clipboard_paste_handoff_delay() -> f64 { 0.12 }

/// A nonempty input points to `count` visible record IDs in display order.
#[no_mangle]
pub unsafe extern "C" fn rium_clipboard_preview_id(ids: *const u64, count: usize, selected: u64) -> u64 {
    if ids.is_null() || count == 0 { return 0; }
    let ids = std::slice::from_raw_parts(ids, count);
    if ids.contains(&selected) { selected } else { ids[0] }
}

#[no_mangle]
pub extern "C" fn rium_clipboard_can_return_focus(saved: i32, frontmost: i32, focused: i32, own: i32) -> i32 {
    let own_is_active = frontmost == own && (focused == 0 || focused == own || focused == saved);
    let notch_is_key = frontmost == saved && focused == own;
    i32::from(own > 0 && saved > 0 && saved != own && (own_is_active || notch_is_key))
}

const LIMIT: usize = 50;
const MAX_TEXT_BYTES: usize = 100_000;
const MAX_IMAGE_BYTES: usize = 8 * 1024 * 1024;
const MAX_TOTAL_BYTES: usize = 32 * 1024 * 1024;

#[derive(Clone)]
struct Entry { id: u64, kind: String, bytes: Arc<[u8]>, pinned: bool, copied_at_ms: Option<u64> }
#[derive(Clone)]
struct History { entries: VecDeque<Entry>, next_id: u64 }
static HISTORY: Mutex<History> = Mutex::new(History { entries: VecDeque::new(), next_id: 1 });
static NEXT_FILE: AtomicU64 = AtomicU64::new(1);
const MAGIC_V1: &[u8; 6] = b"RCLP1\0";
const MAGIC_V2: &[u8; 6] = b"RCLP2\0";
const MAX_ARCHIVE: u64 = (MAX_TOTAL_BYTES + LIMIT * 14 + 10) as u64;
const MAX_DATE_MS: u64 = 253_402_300_799_999;

fn add(history: &mut History, kind: &str, bytes: &[u8]) -> bool {
    let now = SystemTime::now().duration_since(UNIX_EPOCH).ok()
        .and_then(|duration| u64::try_from(duration.as_millis()).ok()).filter(|time| *time > 0 && *time <= MAX_DATE_MS);
    add_at(history, kind, bytes, now, false)
}

fn add_at(history: &mut History, kind: &str, bytes: &[u8], copied_at_ms: Option<u64>, pinned: bool) -> bool {
    if bytes.is_empty() { return false; }
    if copied_at_ms.is_some_and(|time| time == 0 || time > MAX_DATE_MS) { return false; }
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
    if history.entries.front().is_some_and(|e| e.kind == kind && e.bytes.as_ref() == bytes) { return false; }
    let pinned = pinned || history.entries.iter().any(|entry| entry.kind == kind && entry.bytes.as_ref() == bytes && entry.pinned);
    let pinned_entries: Vec<_> = history.entries.iter().filter(|entry| entry.pinned && (entry.kind != kind || entry.bytes.as_ref() != bytes)).collect();
    let pinned_size: usize = pinned_entries.iter().map(|entry| entry.bytes.len()).sum();
    if pinned_entries.len() + 1 > LIMIT || pinned_size.saturating_add(bytes.len()) > MAX_TOTAL_BYTES { return false; }
    let id = history.next_id;
    let Some(next_id) = id.checked_add(1) else { return false; };
    history.entries.retain(|e| e.kind != kind || e.bytes.as_ref() != bytes);
    history.next_id = next_id;
    history.entries.push_front(Entry { id, kind: kind.to_owned(), bytes: Arc::from(bytes), pinned, copied_at_ms });
    let mut total: usize = history.entries.iter().map(|e| e.bytes.len()).sum();
    while history.entries.len() > LIMIT || total > MAX_TOTAL_BYTES {
        let Some(index) = history.entries.iter().rposition(|entry| !entry.pinned) else { break; };
        if let Some(entry) = history.entries.remove(index) { total -= entry.bytes.len(); }
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
    let metadata: Vec<_> = history.entries.iter().map(|e| serde_json::json!({"id":e.id,"kind":e.kind,"size":e.bytes.len(),"pinned":e.pinned,"copiedAtMs":e.copied_at_ms})).collect();
    CString::new(serde_json::to_string(&metadata).unwrap_or_else(|_| "[]".into())).expect("JSON contains no raw NUL").into_raw()
}

/// Returns an owned copy of a record; free it with `rium_clipboard_free_data`.
#[no_mangle]
pub unsafe extern "C" fn rium_clipboard_copy_data(id: u64, len: *mut usize) -> *mut u8 {
    if len.is_null() { return std::ptr::null_mut(); }
    *len = 0;
    let bytes = {
        let history = HISTORY.lock().unwrap_or_else(|e| e.into_inner());
        let Some(entry) = history.entries.iter().find(|e| e.id == id) else { return std::ptr::null_mut(); };
        Arc::clone(&entry.bytes)
    };
    let copy: Box<[u8]> = bytes.as_ref().into();
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
pub extern "C" fn rium_clipboard_clear() { clear(&mut HISTORY.lock().unwrap_or_else(|e| e.into_inner())); }
fn clear(history: &mut History) { history.entries.retain(|entry| entry.pinned); }

fn remove(history: &mut History, id: u64) -> bool {
    let Some(index) = history.entries.iter().position(|entry| entry.id == id) else { return false; };
    history.entries.remove(index).is_some()
}

#[no_mangle]
pub extern "C" fn rium_clipboard_remove(id: u64) -> bool {
    remove(&mut HISTORY.lock().unwrap_or_else(|e| e.into_inner()), id)
}

#[no_mangle]
pub extern "C" fn rium_clipboard_set_pinned(id: u64, pinned: bool) -> bool {
    let mut history = HISTORY.lock().unwrap_or_else(|e| e.into_inner());
    let Some(entry) = history.entries.iter_mut().find(|entry| entry.id == id) else { return false; };
    entry.pinned = pinned;
    true
}

fn write_archive(out: &mut impl Write, history: &History) -> io::Result<()> {
    out.write_all(MAGIC_V2)?;
    out.write_all(&(history.entries.len() as u32).to_le_bytes())?;
    for entry in &history.entries {
        let kind = match entry.kind.as_str() { "text" => 1, "files" => 2, "image/png" => 3, "image/tiff" => 4, _ => unreachable!() };
        out.write_all(&[kind])?;
        out.write_all(&(entry.bytes.len() as u32).to_le_bytes())?;
        out.write_all(&[u8::from(entry.pinned)])?;
        out.write_all(&entry.copied_at_ms.unwrap_or(0).to_le_bytes())?;
        out.write_all(&entry.bytes)?;
    }
    Ok(())
}
fn unarchive(bytes: &[u8]) -> io::Result<History> {
    let bad = || io::Error::new(io::ErrorKind::InvalidData, "invalid clipboard archive");
    if bytes.len() < 10 || bytes.len() as u64 > MAX_ARCHIVE { return Err(bad()); }
    let v2 = if &bytes[..6] == MAGIC_V2 { true } else if &bytes[..6] == MAGIC_V1 { false } else { return Err(bad()); };
    let count = u32::from_le_bytes(bytes[6..10].try_into().map_err(|_| bad())?) as usize;
    if count > LIMIT { return Err(bad()); }
    let mut offset = 10usize; let mut entries = Vec::new(); let mut total = 0usize;
    for _ in 0..count {
        let header = bytes.get(offset..offset + 5).ok_or_else(bad)?; offset += 5;
        let kind = match header[0] { 1 => "text", 2 => "files", 3 => "image/png", 4 => "image/tiff", _ => return Err(bad()) };
        let len = u32::from_le_bytes(header[1..5].try_into().map_err(|_| bad())?) as usize;
        let (pinned, copied_at_ms) = if v2 {
            let meta = bytes.get(offset..offset + 9).ok_or_else(bad)?; offset += 9;
            if meta[0] > 1 { return Err(bad()); }
            let time = u64::from_le_bytes(meta[1..9].try_into().map_err(|_| bad())?);
            if time > MAX_DATE_MS { return Err(bad()); }
            (meta[0] == 1, (time != 0).then_some(time))
        } else { (false, None) };
        total = total.checked_add(len).ok_or_else(bad)?;
        if total > MAX_TOTAL_BYTES || len > MAX_IMAGE_BYTES { return Err(bad()); }
        let end = offset.checked_add(len).ok_or_else(bad)?;
        entries.push((kind, bytes.get(offset..end).ok_or_else(bad)?, copied_at_ms, pinned)); offset = end;
    }
    if offset != bytes.len() { return Err(bad()); }
    let mut history = History { entries: VecDeque::new(), next_id: 1 };
    for (kind, content, time, pinned) in entries.into_iter().rev() { if !add_at(&mut history, kind, content, time, pinned) { return Err(bad()); } }
    Ok(history)
}
fn save(root: &Path, history: &History) -> io::Result<()> {
    DirBuilder::new().recursive(true).mode(0o700).create(root)?;
    let temporary = root.join(format!(".clipboard-{}-{}.tmp", std::process::id(), NEXT_FILE.fetch_add(1, Ordering::Relaxed)));
    let file = OpenOptions::new().write(true).create_new(true).mode(0o600).open(&temporary)?;
    let mut out = BufWriter::new(file);
    let result = (|| {
        write_archive(&mut out, history)?;
        out.flush()?;
        out.get_ref().sync_all()?;
        fs::rename(&temporary, root.join("clipboard-v2.bin"))
    })();
    if result.is_err() { let _ = fs::remove_file(temporary); }
    result
}
fn load(root: &Path) -> io::Result<History> {
    let modern = root.join("clipboard-v2.bin");
    let path = match fs::symlink_metadata(&modern) {
        Err(e) if e.kind() == io::ErrorKind::NotFound => root.join("clipboard.bin"),
        Err(e) => return Err(e),
        Ok(_) => modern,
    };
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
pub unsafe extern "C" fn rium_clipboard_save_after_clear(path: *const c_char) -> i32 {
    let Some(root) = root_path(path) else { return -1; };
    let snapshot = HISTORY.lock().unwrap_or_else(|e| e.into_inner()).clone();
    if save_after_clear(&root, &snapshot).is_ok() { 0 } else { -1 }
}
fn save_after_clear(root: &Path, snapshot: &History) -> io::Result<()> {
    save(root, snapshot)?;
    match fs::remove_file(root.join("clipboard.bin")) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error),
    }
}
#[no_mangle]
pub unsafe extern "C" fn rium_clipboard_load(path: *const c_char) -> i32 {
    let Some(root) = root_path(path) else { return -1; };
    let Ok(history) = load(&root) else { return -1; };
    *HISTORY.lock().unwrap_or_else(|e| e.into_inner()) = history; 0
}

#[cfg(test)]
mod tests {
    #[test]
    fn preview_keeps_visible_selection_or_uses_first_displayed_row() {
        let ids = [14, 9, 31];
        let resolve = |selected| unsafe { rium_clipboard_preview_id(ids.as_ptr(), ids.len(), selected) };
        assert_eq!(resolve(31), 31);
        assert_eq!(resolve(7), 14);
        assert_eq!(resolve(0), 14);
        assert_eq!(unsafe { rium_clipboard_preview_id(ids.as_ptr(), 0, 31) }, 0);
        assert_eq!(unsafe { rium_clipboard_preview_id(std::ptr::null(), 1, 31) }, 0);
    }

    #[test]
    fn history_paste_releases_the_notch_without_redirecting_an_external_focus() {
        use super::rium_clipboard_can_return_focus as can_return;
        assert_eq!(can_return(10, 30, 30, 30), 1);
        assert_eq!(can_return(10, 30, 0, 30), 1);
        assert_eq!(can_return(10, 10, 30, 30), 1);
        assert_eq!(can_return(10, 20, 30, 30), 0);
        assert_eq!(can_return(10, 30, 20, 30), 0);
        assert_eq!(can_return(30, 30, 30, 30), 0);
    }
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
        assert_eq!(h.entries.front().unwrap().bytes.as_ref(), b"54");
        assert!(add(&mut h, "text", b"10"));
        assert_eq!(h.entries.iter().filter(|e| e.bytes.as_ref() == b"10").count(), 1);
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
        let snapshot = history.clone();
        assert!(Arc::ptr_eq(&snapshot.entries[0].bytes, &history.entries[0].bytes));
        let id = history.entries[0].id;
        assert!(remove(&mut history, id));
        save(&root, &snapshot).unwrap();
        assert_eq!(fs::metadata(root.join("clipboard-v2.bin")).unwrap().permissions().mode() & 0o777, 0o600);
        let restored = load(&root).unwrap();
        assert_eq!(restored.entries.len(), 3);
        assert_eq!(restored.entries[0].kind, "image/png"); assert_eq!(restored.entries[2].bytes.as_ref(), "첫 기록".as_bytes());
        let mut bad = fs::read(root.join("clipboard-v2.bin")).unwrap();
        let last = bad.pop().unwrap(); assert!(unarchive(&bad).is_err());
        bad.extend_from_slice(&[last, 0]); assert!(unarchive(&bad).is_err());
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn legacy_archive_migrates_without_overwriting_and_preserves_pins() {
        let root = std::env::temp_dir().join(format!("rium-clipboard-migration-{}-{}", std::process::id(), NEXT_FILE.fetch_add(1, Ordering::Relaxed)));
        fs::create_dir(&root).unwrap();
        let mut legacy = MAGIC_V1.to_vec();
        legacy.extend_from_slice(&1u32.to_le_bytes());
        legacy.push(1); legacy.extend_from_slice(&3u32.to_le_bytes()); legacy.extend_from_slice(b"old");
        fs::write(root.join("clipboard.bin"), &legacy).unwrap();
        let mut history = load(&root).unwrap();
        assert_eq!(history.entries[0].copied_at_ms, None);
        history.entries[0].pinned = true;
        assert!(add_at(&mut history, "text", b"new", Some(1_700_000_000_000), false));
        save(&root, &history).unwrap();
        assert_eq!(fs::read(root.join("clipboard.bin")).unwrap(), legacy);
        let mut restored = load(&root).unwrap();
        assert_eq!(restored.entries[0].copied_at_ms, Some(1_700_000_000_000));
        assert!(restored.entries[1].pinned);
        clear(&mut restored);
        assert_eq!(restored.entries[0].bytes.as_ref(), b"old");
        save_after_clear(&root, &restored).unwrap();
        assert!(!root.join("clipboard.bin").exists());
        fs::write(root.join("clipboard-v2.bin"), b"bad").unwrap();
        assert!(load(&root).is_err());
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn bounded_history_never_evicts_pinned_entries() {
        let mut history = History { entries: VecDeque::new(), next_id: 1 };
        for index in 0..LIMIT {
            assert!(add_at(&mut history, "text", index.to_string().as_bytes(), Some(1), true));
        }
        assert!(!add_at(&mut history, "text", b"overflow", Some(1), false));
        assert_eq!(history.entries.len(), LIMIT);
        history.entries.back_mut().unwrap().pinned = false;
        assert!(add_at(&mut history, "text", b"new", Some(1), false));
        assert_eq!(history.entries.len(), LIMIT);
        assert_eq!(history.entries.iter().filter(|entry| entry.pinned).count(), LIMIT - 1);
    }

    #[test]
    fn remove_only_deletes_the_selected_entry_even_if_pinned() {
        let mut history = History { entries: VecDeque::new(), next_id: 1 };
        assert!(add_at(&mut history, "text", b"first", Some(1), true));
        let first = history.entries[0].id;
        assert!(add_at(&mut history, "text", b"second", Some(2), false));
        let second = history.entries[0].id;
        assert!(!remove(&mut history, u64::MAX));
        assert!(remove(&mut history, first));
        assert_eq!(history.entries.len(), 1);
        assert_eq!(history.entries[0].id, second);
        assert_eq!(history.entries[0].bytes.as_ref(), b"second");
        assert!(!remove(&mut history, first));
    }
}
