//! Private script storage and teleprompter scroll calculations.
use std::ffi::{c_char, CStr, CString};
use std::fs::{self, DirBuilder, OpenOptions};
use std::io::{self, Read, Write};
use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

const MAX_SCRIPT: usize = 1_048_576;
static NEXT_FILE: AtomicU64 = AtomicU64::new(1);

#[no_mangle]
pub extern "C" fn rium_teleprompter_wheel_delta(vertical: f64, precise: i32) -> f64 {
    let shift = -vertical * if precise == 1 { 0.8 } else { 6.0 };
    if shift.is_finite() { shift } else { 0.0 }
}

#[no_mangle]
pub extern "C" fn rium_teleprompter_scroll_position(offset: f64, shift: f64, limit: f64) -> f64 {
    if !limit.is_finite() || limit < 0.0 {
        return 0.0;
    }
    let offset = if offset.is_finite() { offset.clamp(0.0, limit) } else { 0.0 };
    let shift = if shift.is_finite() { shift } else { 0.0 };
    (offset + shift).clamp(0.0, limit)
}

fn save(root: &Path, bytes: &[u8]) -> io::Result<()> {
    if bytes.len() > MAX_SCRIPT || std::str::from_utf8(bytes).is_err() {
        return Err(io::Error::new(io::ErrorKind::InvalidInput, "invalid script"));
    }
    DirBuilder::new().recursive(true).mode(0o700).create(root)?;
    let name = format!(".teleprompter-{}-{}.tmp", std::process::id(), NEXT_FILE.fetch_add(1, Ordering::Relaxed));
    let temporary = root.join(name);
    let mut file = OpenOptions::new().write(true).create_new(true).mode(0o600).open(&temporary)?;
    let result = (|| {
        file.write_all(bytes)?;
        file.sync_all()?;
        fs::rename(&temporary, root.join("teleprompter.txt"))
    })();
    if result.is_err() { let _ = fs::remove_file(temporary); }
    result
}
fn load(root: &Path) -> io::Result<Vec<u8>> {
    let file = match fs::File::open(root.join("teleprompter.txt")) {
        Ok(file) => file,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(Vec::new()),
        Err(error) => return Err(error),
    };
    let mut bytes = Vec::new();
    file.take((MAX_SCRIPT + 1) as u64).read_to_end(&mut bytes)?;
    if bytes.len() > MAX_SCRIPT || std::str::from_utf8(&bytes).is_err() {
        return Err(io::Error::new(io::ErrorKind::InvalidData, "invalid saved script"));
    }
    Ok(bytes)
}
fn chapters(text: &str) -> Vec<(String, usize)> {
    let mut result = Vec::new();
    let mut utf16_offset = 0usize;
    for line in text.split_inclusive('\n') {
        let trimmed = line.trim();
        if trimmed.starts_with('#') {
            let title = trimmed.trim_start_matches('#').trim();
            if !title.is_empty() && result.len() < 1000 {
                result.push((title.chars().take(120).collect(), utf16_offset));
            }
        }
        utf16_offset += line.encode_utf16().count();
    }
    result
}
unsafe fn root_path(path: *const c_char) -> Option<PathBuf> {
    if path.is_null() { return None; }
    let value = CStr::from_ptr(path).to_str().ok()?;
    if value.is_empty() { return None; }
    Some(PathBuf::from(value))
}
#[no_mangle]
pub unsafe extern "C" fn rium_teleprompter_save(path: *const c_char, bytes: *const u8, len: usize) -> i32 {
    let Some(root) = root_path(path) else { return -1; };
    if len > MAX_SCRIPT || (bytes.is_null() && len != 0) { return -2; }
    let value = if len == 0 { &[] } else { std::slice::from_raw_parts(bytes, len) };
    match save(&root, value) { Ok(()) => 0, Err(e) if e.kind() == io::ErrorKind::InvalidInput => -2, Err(_) => -1 }
}
/// An empty or missing script returns a valid zero-length allocation.
#[no_mangle]
pub unsafe extern "C" fn rium_teleprompter_load(path: *const c_char, len: *mut usize) -> *mut u8 {
    if len.is_null() { return std::ptr::null_mut(); }
    *len = 0;
    let Some(root) = root_path(path) else { return std::ptr::null_mut(); };
    let Ok(bytes) = load(&root) else { return std::ptr::null_mut(); };
    let bytes = bytes.into_boxed_slice();
    *len = bytes.len();
    Box::into_raw(bytes) as *mut u8
}
#[no_mangle]
pub unsafe extern "C" fn rium_teleprompter_free(ptr: *mut u8, len: usize) {
    if !ptr.is_null() { drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(ptr, len))); }
}
/// Returns heading titles and UTF-16 offsets as owned JSON.
#[no_mangle]
pub unsafe extern "C" fn rium_teleprompter_chapters(bytes: *const u8, len: usize) -> *mut c_char {
    if len > MAX_SCRIPT || (bytes.is_null() && len != 0) { return std::ptr::null_mut(); }
    let data = if len == 0 { &[] } else { std::slice::from_raw_parts(bytes, len) };
    let Ok(text) = std::str::from_utf8(data) else { return std::ptr::null_mut(); };
    let items: Vec<_> = chapters(text).into_iter().map(|(title, offset)| serde_json::json!({"title":title,"offset":offset})).collect();
    CString::new(serde_json::to_string(&items).unwrap_or_else(|_| "[]".into())).unwrap().into_raw()
}
#[no_mangle]
pub unsafe extern "C" fn rium_teleprompter_free_string(ptr: *mut c_char) {
    if !ptr.is_null() { drop(CString::from_raw(ptr)); }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;

    #[test]
    fn wheel_nudges_match_the_input_units_and_stop_at_script_edges() {
        assert_eq!(rium_teleprompter_wheel_delta(-10.0, 1), 8.0);
        assert_eq!(rium_teleprompter_wheel_delta(2.0, 0), -12.0);
        assert_eq!(rium_teleprompter_wheel_delta(f64::NAN, 1), 0.0);
        assert_eq!(rium_teleprompter_scroll_position(5.0, -12.0, 200.0), 0.0);
        assert_eq!(rium_teleprompter_scroll_position(196.0, 8.0, 200.0), 200.0);
        assert_eq!(rium_teleprompter_scroll_position(2.3, 0.25, 200.0), 2.55);
    }
    #[test]
    fn saves_privately_without_destroying_previous_on_invalid_write() {
        let root = std::env::temp_dir().join(format!("rium-prompt-test-{}-{}", std::process::id(), NEXT_FILE.fetch_add(1, Ordering::Relaxed)));
        assert_eq!(load(&root).unwrap(), b"");
        save(&root, "첫 번째 원고".as_bytes()).unwrap();
        assert_eq!(load(&root).unwrap(), "첫 번째 원고".as_bytes());
        assert_eq!(fs::metadata(root.join("teleprompter.txt")).unwrap().permissions().mode() & 0o777, 0o600);
        assert!(save(&root, &vec![b'x'; MAX_SCRIPT + 1]).is_err());
        assert!(save(&root, &[0xff]).is_err());
        assert_eq!(load(&root).unwrap(), "첫 번째 원고".as_bytes());
        save(&root, b"").unwrap(); assert!(load(&root).unwrap().is_empty());
        fs::remove_dir_all(root).unwrap();
    }
    #[test]
    fn finds_markdown_chapters_with_utf16_offsets() {
        let text = "# 시작\n🙂 본문\n  ## 두 번째\r\n본문\n### \n";
        let found = chapters(text);
        assert_eq!(found.len(), 2);
        assert_eq!(found[0], ("시작".to_string(), 0));
        assert_eq!(found[1], ("두 번째".to_string(), "# 시작\n🙂 본문\n".encode_utf16().count()));
        assert!(chapters("일반 원고\n본문").is_empty());
    }
}
