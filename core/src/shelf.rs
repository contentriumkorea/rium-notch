//! Shelf stores file references only; it never moves or deletes the files.
use std::ffi::{c_char, CStr, CString};
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt};
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};
use std::time::{SystemTime, UNIX_EPOCH};

const LIMIT: usize = 100;
static SHELF: OnceLock<Mutex<Result<Shelf, String>>> = OnceLock::new();
#[derive(Clone)]
struct Shelf { path: PathBuf, items: Vec<String> }

fn valid(path: &str) -> bool { !path.is_empty() && path.len() <= 4096 && Path::new(path).is_absolute() }
fn shelf_path() -> Result<PathBuf, String> {
    if let Some(root) = std::env::var_os("RIUM_SHELF_TEST_ROOT") { return Ok(PathBuf::from(root).join("shelf.json")); }
    let home = std::env::var_os("HOME").ok_or("home unavailable")?;
    Ok(PathBuf::from(home).join("Library/Application Support/Rium Notch/shelf.json"))
}
impl Shelf {
    fn load(path: PathBuf) -> Result<Self, String> {
        if let Some(parent) = path.parent() {
            if let Ok(meta) = fs::symlink_metadata(parent) {
                if meta.file_type().is_symlink() || !meta.is_dir() { return Err("invalid shelf directory".into()); }
            }
        }
        let items = match fs::symlink_metadata(&path) {
            Ok(meta) if meta.file_type().is_symlink() || !meta.is_file() || meta.len() > 1_000_000 => return Err("invalid shelf file".into()),
            Ok(_) => {
                let bytes = fs::read(&path).map_err(|_| "cannot read shelf")?;
                let items: Vec<String> = serde_json::from_slice(&bytes).map_err(|_| "invalid shelf data")?;
                if items.len() > LIMIT || items.iter().any(|s| !valid(s)) { return Err("invalid shelf entries".into()); }
                items
            },
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Vec::new(),
            Err(_) => return Err("cannot inspect shelf".into()),
        };
        Ok(Self { path, items })
    }
    fn save(&self) -> Result<(), String> {
        let dir = self.path.parent().ok_or("invalid shelf directory")?;
        fs::DirBuilder::new().recursive(true).mode(0o700).create(dir).map_err(|_| "cannot create shelf directory")?;
        if fs::symlink_metadata(dir).map_err(|_| "cannot inspect shelf directory")?.file_type().is_symlink() { return Err("invalid shelf directory".into()); }
        let nanos = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_nanos();
        let temp = dir.join(format!(".shelf-{}-{nanos}.tmp", std::process::id()));
        let result = (|| {
            let mut file = OpenOptions::new().write(true).create_new(true).mode(0o600).open(&temp).map_err(|_| "cannot write shelf")?;
            serde_json::to_writer(&mut file, &self.items).map_err(|_| "cannot serialize shelf")?;
            file.flush().and_then(|_| file.sync_all()).map_err(|_| "cannot flush shelf")?;
            fs::rename(&temp, &self.path).map_err(|_| "cannot save shelf")?;
            Ok(())
        })();
        if result.is_err() { let _ = fs::remove_file(temp); }
        result
    }
    fn change(&mut self, path: &str, adding: bool) -> Result<bool, String> {
        if !valid(path) { return Err("invalid file path".into()); }
        let original = self.items.clone();
        self.items.retain(|item| item != path);
        if adding { self.items.insert(0, path.to_string()); self.items.truncate(LIMIT); }
        if self.items == original { return Ok(false); }
        if let Err(error) = self.save() { self.items = original; return Err(error); }
        Ok(true)
    }
}
fn shelf() -> &'static Mutex<Result<Shelf, String>> {
    SHELF.get_or_init(|| Mutex::new(shelf_path().and_then(Shelf::load)))
}
unsafe fn change(path: *const c_char, adding: bool) -> i32 {
    if path.is_null() { return -1; }
    let Ok(value) = CStr::from_ptr(path).to_str() else { return -1; };
    let mut guard = shelf().lock().unwrap_or_else(|e| e.into_inner());
    let Ok(shelf) = guard.as_mut() else { return -2; };
    match shelf.change(value, adding) { Ok(true) => 1, Ok(false) => 0, Err(_) => -2 }
}
#[no_mangle]
pub unsafe extern "C" fn rium_shelf_add(path: *const c_char) -> i32 { change(path, true) }
#[no_mangle]
pub unsafe extern "C" fn rium_shelf_remove(path: *const c_char) -> i32 { change(path, false) }
#[no_mangle]
pub extern "C" fn rium_shelf_json() -> *mut c_char {
    let guard = shelf().lock().unwrap_or_else(|e| e.into_inner());
    let result = match guard.as_ref() { Ok(s) => serde_json::json!({"items":s.items}), Err(_) => serde_json::json!({"error":"보관함을 읽을 수 없습니다"}) };
    CString::new(result.to_string()).expect("JSON contains no NUL").into_raw()
}
#[no_mangle]
pub unsafe extern "C" fn rium_shelf_free(value: *mut c_char) { if !value.is_null() { drop(CString::from_raw(value)); } }

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn stores_references_and_preserves_files() {
        let root = std::env::temp_dir().join(format!("rium-shelf-test-{}-{}", std::process::id(), SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos()));
        fs::create_dir(&root).unwrap();
        let file = root.join("original.txt"); fs::write(&file, b"original").unwrap();
        let mut shelf = Shelf::load(root.join("store/shelf.json")).unwrap();
        let path = file.to_str().unwrap();
        assert!(shelf.change(path, true).unwrap());
        assert_eq!(Shelf::load(shelf.path.clone()).unwrap().items, vec![path]);
        assert!(shelf.change(path, false).unwrap());
        assert_eq!(fs::read(file).unwrap(), b"original");
        assert!(shelf.change("relative", true).is_err());
        fs::remove_dir_all(root).unwrap();
    }
}
