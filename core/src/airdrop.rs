//! Best-effort recognition of macOS AirDrop quarantine metadata.
use std::ffi::{c_char, c_int, c_void, CStr};

extern "C" {
    fn getxattr(path: *const c_char, name: *const c_char, value: *mut c_void, size: usize, position: u32, options: c_int) -> isize;
}
fn is_airdrop_quarantine(value: &[u8]) -> bool {
    let Ok(text) = std::str::from_utf8(value) else { return false; };
    text.trim_end_matches('\0').split(';').nth(2).map(|agent| agent.eq_ignore_ascii_case("sharingd")).unwrap_or(false)
}
/// Returns 1 for a sharingd quarantine marker, 0 otherwise and -1 on error.
/// The caller must supply a valid NUL-terminated absolute path.
#[no_mangle]
pub unsafe extern "C" fn rium_is_airdrop_file(path: *const c_char) -> i32 {
    if path.is_null() { return -1; }
    let Ok(value) = CStr::from_ptr(path).to_str() else { return -1; };
    if !std::path::Path::new(value).is_absolute() { return -1; }
    let mut buffer = [0u8; 4096];
    // XATTR_NOFOLLOW prevents inspection of a symlink's target.
    let count = getxattr(path, b"com.apple.quarantine\0".as_ptr().cast(), buffer.as_mut_ptr().cast(), buffer.len(), 0, 1);
    if count < 0 { return -1; }
    i32::from(is_airdrop_quarantine(&buffer[..count as usize]))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn identifies_quarantine_agent_without_guessing_from_filename() {
        assert!(is_airdrop_quarantine(b"0083;abcdef;sharingd;1234"));
        assert!(is_airdrop_quarantine(b"0083;abcdef;SharingD;1234\0"));
        assert!(!is_airdrop_quarantine(b"0083;abcdef;Safari;sharingd"));
        assert!(!is_airdrop_quarantine(b"sharingd"));
        assert!(!is_airdrop_quarantine(&[0xff]));
    }
}
