//! Private, atomic storage for the personal assistant conversation.
use serde_json::{json, Value};
use std::collections::HashSet;
use std::ffi::{c_char, CStr};
use std::fs::{self, DirBuilder, OpenOptions};
use std::io::{self, Read, Write};
use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

// shortcut: storage limits are provisional until the reference limits are recovered.
const MAX_FILE: usize = 4 * 1024 * 1024;
const MAX_MESSAGES: usize = 1000;
static NEXT_FILE: AtomicU64 = AtomicU64::new(1);

fn valid_uuid(id: &str) -> bool {
    id.len() == 36 && id.bytes().enumerate().all(|(index, byte)| {
        if [8, 13, 18, 23].contains(&index) { byte == b'-' } else { byte.is_ascii_hexdigit() }
    })
}

fn valid_optional_id(value: Option<&Value>) -> bool {
    value.map_or(true, |value| value.is_null() || value.as_str().is_some_and(|id| !id.is_empty() && id.len() <= 256))
}

fn valid_conversation(value: &Value) -> bool {
    if !matches!(value.get("outcome").and_then(Value::as_str), Some("none" | "running" | "completed" | "failed" | "interrupted" | "unknown")) { return false; }
    if !value.get("draft").and_then(Value::as_str).is_some_and(|draft| draft.len() <= 524_288) { return false; }
    if !valid_optional_id(value.get("threadId")) || !valid_optional_id(value.get("turnId")) { return false; }
    if value.get("turnId").and_then(Value::as_str).is_some() && value.get("threadId").and_then(Value::as_str).is_none() { return false; }
    let Some(messages) = value.get("messages").and_then(Value::as_array) else { return false; };
    if messages.len() > MAX_MESSAGES { return false; }
    if !messages.is_empty() && !value.get("threadId").and_then(Value::as_str).is_some_and(|id| !id.is_empty()) { return false; }
    let mut ids = HashSet::new();
    messages.iter().all(|message| {
        let Some(id) = message.get("id").and_then(Value::as_str) else { return false; };
        valid_uuid(id) && ids.insert(id.to_ascii_lowercase())
            && matches!(message.get("role").and_then(Value::as_str), Some("user" | "assistant"))
            && valid_optional_id(message.get("turnId")) && valid_optional_id(message.get("itemId")) && valid_optional_id(message.get("clientId"))
            && (message.get("itemId").and_then(Value::as_str).is_none() || message.get("turnId").and_then(Value::as_str).is_some())
            && message.get("text").and_then(Value::as_str).is_some_and(|text| text.len() <= 524_288)
    })
}

fn valid_history(data: &[u8]) -> bool {
    if data.len() > MAX_FILE { return false; }
    let Ok(value) = serde_json::from_slice::<Value>(data) else { return false; };
    if value.get("version").and_then(Value::as_u64) != Some(1) || !valid_conversation(&value) { return false; }
    let Some(archive) = value.get("conversations") else { return true; };
    let Some(archive) = archive.as_array() else { return false; };
    let Some(active) = value.get("activeId").and_then(Value::as_str).filter(|id| valid_uuid(id)) else { return false; };
    let mut ids = HashSet::new();
    ids.insert(active.to_ascii_lowercase());
    let mut threads = HashSet::new();
    if let Some(thread) = value.get("threadId").and_then(Value::as_str) { threads.insert(thread.to_owned()); }
    archive.len() <= 50 && archive.iter().all(|entry| {
        entry.get("id").and_then(Value::as_str).is_some_and(|id| valid_uuid(id) && ids.insert(id.to_ascii_lowercase()))
            && valid_conversation(entry)
            && entry.get("threadId").and_then(Value::as_str).map_or(true, |thread| threads.insert(thread.to_owned()))
            && !matches!(entry.get("outcome").and_then(Value::as_str), Some("running" | "unknown"))
    })
}

fn load(root: &Path) -> io::Result<Vec<u8>> {
    let file = match fs::File::open(root.join("assistant-history.json")) {
        Ok(file) => file,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(json!({"version":1,"threadId":null,"outcome":"none","draft":"","messages":[]}).to_string().into_bytes()),
        Err(error) => return Err(error),
    };
    let mut bytes = Vec::new();
    file.take((MAX_FILE + 1) as u64).read_to_end(&mut bytes)?;
    if !valid_history(&bytes) { return Err(io::Error::new(io::ErrorKind::InvalidData, "invalid assistant history")); }
    Ok(bytes)
}

fn save(root: &Path, data: &[u8]) -> io::Result<()> {
    if !valid_history(data) { return Err(io::Error::new(io::ErrorKind::InvalidInput, "invalid assistant history")); }
    DirBuilder::new().recursive(true).mode(0o700).create(root)?;
    let temporary = root.join(format!(".assistant-history-{}-{}.tmp", std::process::id(), NEXT_FILE.fetch_add(1, Ordering::Relaxed)));
    let mut file = OpenOptions::new().write(true).create_new(true).mode(0o600).open(&temporary)?;
    let result = (|| { file.write_all(data)?; file.sync_all()?; fs::rename(&temporary, root.join("assistant-history.json")) })();
    if result.is_err() { let _ = fs::remove_file(temporary); }
    result
}

unsafe fn root_path(path: *const c_char) -> Option<PathBuf> {
    if path.is_null() { return None; }
    let path = CStr::from_ptr(path).to_str().ok()?;
    if path.is_empty() { None } else { Some(PathBuf::from(path)) }
}

#[no_mangle]
pub unsafe extern "C" fn rium_assistant_history_load(path: *const c_char, length: *mut usize) -> *mut u8 {
    if length.is_null() { return std::ptr::null_mut(); }
    *length = 0;
    let Some(root) = root_path(path) else { return std::ptr::null_mut(); };
    let Ok(data) = load(&root) else { return std::ptr::null_mut(); };
    let data = data.into_boxed_slice(); *length = data.len(); Box::into_raw(data) as *mut u8
}

#[no_mangle]
pub unsafe extern "C" fn rium_assistant_history_save(path: *const c_char, data: *const u8, length: usize) -> i32 {
    let Some(root) = root_path(path) else { return -1; };
    if data.is_null() || length > MAX_FILE { return -2; }
    match save(&root, std::slice::from_raw_parts(data, length)) { Ok(()) => 0, Err(error) if error.kind() == io::ErrorKind::InvalidInput => -2, Err(_) => -1 }
}

#[no_mangle]
pub unsafe extern "C" fn rium_assistant_history_free(data: *mut u8, length: usize) {
    if !data.is_null() { drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(data, length))); }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn invalid_data_cannot_replace_existing_history() {
        let root = std::env::temp_dir().join(format!("rium-assistant-history-{}-{}", std::process::id(), NEXT_FILE.fetch_add(1, Ordering::Relaxed)));
        assert!(valid_history(&load(&root).unwrap()));
        let data = json!({"version":1,"threadId":"thread","outcome":"failed","draft":"draft","messages":[{"id":"12345678-1234-1234-1234-123456789abc","role":"user","text":"hello"}]}).to_string();
        save(&root, data.as_bytes()).unwrap();
        assert!(save(&root, br#"{"version":1,"messages":[]}"#).is_err());
        let mut detached: Value = serde_json::from_str(&data).unwrap(); detached["threadId"] = Value::Null;
        assert!(!valid_history(detached.to_string().as_bytes()));
        let mut recoverable: Value = serde_json::from_str(&data).unwrap();
        recoverable["outcome"] = json!("unknown"); recoverable["turnId"] = json!("turn");
        recoverable["messages"][0]["turnId"] = json!("turn");
        assert!(valid_history(recoverable.to_string().as_bytes()));
        recoverable["messages"][0]["itemId"] = json!("item"); recoverable["messages"][0]["turnId"] = Value::Null;
        assert!(!valid_history(recoverable.to_string().as_bytes()));
        let mut multiple: Value = serde_json::from_str(&data).unwrap();
        multiple["activeId"] = json!("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
        multiple["conversations"] = json!([{"id":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","threadId":"other","outcome":"completed","draft":"","messages":[]}]);
        assert!(valid_history(multiple.to_string().as_bytes()));
        multiple["conversations"][0]["id"] = multiple["activeId"].clone();
        assert!(!valid_history(multiple.to_string().as_bytes()));
        multiple["conversations"][0]["id"] = json!("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");
        multiple["conversations"][0]["outcome"] = json!("unknown");
        assert!(!valid_history(multiple.to_string().as_bytes()));
        multiple["conversations"][0]["outcome"] = json!("completed");
        multiple["conversations"][0]["threadId"] = json!("thread");
        assert!(!valid_history(multiple.to_string().as_bytes()));
        assert_eq!(load(&root).unwrap().as_slice(), data.as_bytes());
        fs::remove_dir_all(root).unwrap();
    }
}
