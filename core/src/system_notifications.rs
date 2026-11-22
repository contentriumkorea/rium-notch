//! Read-only access to the local macOS notification database.
//! Its schema is private and may change; failures are returned to the caller.
use serde_json::{json, Value};
use std::ffi::{c_char, c_double, c_int, c_void, CStr, CString};
use std::ptr;

#[no_mangle]
pub extern "C" fn rium_home_notification_display_nanoseconds() -> u64 {
    6_000_000_000
}

#[link(name = "sqlite3")]
extern "C" {
    fn sqlite3_open_v2(path: *const c_char, db: *mut *mut c_void, flags: c_int, vfs: *const c_char) -> c_int;
    fn sqlite3_close_v2(db: *mut c_void) -> c_int;
    fn sqlite3_busy_timeout(db: *mut c_void, milliseconds: c_int) -> c_int;
    fn sqlite3_prepare_v2(db: *mut c_void, sql: *const c_char, len: c_int, stmt: *mut *mut c_void, tail: *mut *const c_char) -> c_int;
    fn sqlite3_finalize(stmt: *mut c_void) -> c_int;
    fn sqlite3_bind_double(stmt: *mut c_void, index: c_int, value: c_double) -> c_int;
    fn sqlite3_bind_int64(stmt: *mut c_void, index: c_int, value: i64) -> c_int;
    fn sqlite3_step(stmt: *mut c_void) -> c_int;
    fn sqlite3_column_int64(stmt: *mut c_void, column: c_int) -> i64;
    fn sqlite3_column_double(stmt: *mut c_void, column: c_int) -> c_double;
    fn sqlite3_column_text(stmt: *mut c_void, column: c_int) -> *const u8;
    fn sqlite3_column_blob(stmt: *mut c_void, column: c_int) -> *const c_void;
    fn sqlite3_column_bytes(stmt: *mut c_void, column: c_int) -> c_int;
}

struct Database(*mut c_void);
impl Drop for Database { fn drop(&mut self) { unsafe { sqlite3_close_v2(self.0); } } }
struct Statement(*mut c_void);
impl Drop for Statement { fn drop(&mut self) { unsafe { sqlite3_finalize(self.0); } } }

fn hex(data: &[u8]) -> String {
    const DIGITS: &[u8; 16] = b"0123456789abcdef";
    let mut result = String::with_capacity(data.len() * 2);
    for &byte in data { result.push(DIGITS[(byte >> 4) as usize] as char); result.push(DIGITS[(byte & 15) as usize] as char); }
    result
}

fn read(path: &CStr, after_time: f64, after_id: i64) -> Result<Value, &'static str> {
    if !after_time.is_finite() || after_id < 0 { return Err("알림 기준이 올바르지 않습니다"); }
    unsafe {
        let mut raw = ptr::null_mut();
        let status = sqlite3_open_v2(path.as_ptr(), &mut raw, 1 | 0x8000, ptr::null());
        let db = Database(raw);
        if status != 0 || db.0.is_null() { return Err("시스템 알림 데이터에 접근할 수 없습니다"); }
        sqlite3_busy_timeout(db.0, 200);
        let baseline = after_time < 0.0;
        let sql = if baseline {
            c"SELECT delivered_date, rec_id, NULL, NULL FROM record WHERE delivered_date > 0 ORDER BY delivered_date DESC, rec_id DESC LIMIT 1"
        } else {
            c"SELECT r.delivered_date, r.rec_id, a.identifier, r.data FROM record r LEFT JOIN app a ON a.app_id=r.app_id WHERE r.delivered_date > 0 AND (r.delivered_date > ?1 OR (r.delivered_date = ?1 AND r.rec_id > ?2)) ORDER BY r.delivered_date, r.rec_id LIMIT 17"
        };
        let mut raw_stmt = ptr::null_mut();
        if sqlite3_prepare_v2(db.0, sql.as_ptr(), -1, &mut raw_stmt, ptr::null_mut()) != 0 || raw_stmt.is_null() {
            return Err("이 macOS의 알림 형식을 읽을 수 없습니다");
        }
        let stmt = Statement(raw_stmt);
        if !baseline && (sqlite3_bind_double(stmt.0, 1, after_time) != 0 || sqlite3_bind_int64(stmt.0, 2, after_id) != 0) {
            return Err("시스템 알림을 조회할 수 없습니다");
        }
        let mut time = if baseline { 0.0 } else { after_time };
        let mut id = if baseline { 0 } else { after_id };
        let mut rows = Vec::new();
        let mut scanned = 0;
        let mut has_more = false;
        loop {
            match sqlite3_step(stmt.0) {
                101 => break,
                100 => {},
                _ => return Err("시스템 알림을 조회할 수 없습니다"),
            }
            if !baseline && scanned == 16 { has_more = true; break; }
            scanned += 1;
            let next_time = sqlite3_column_double(stmt.0, 0);
            let next_id = sqlite3_column_int64(stmt.0, 1);
            if !next_time.is_finite() || next_time <= 0.0 || next_id < 0 { return Err("시스템 알림의 시간 형식이 올바르지 않습니다"); }
            time = next_time; id = next_id;
            if baseline { continue; }
            let source_ptr = sqlite3_column_text(stmt.0, 2);
            let source_len = sqlite3_column_bytes(stmt.0, 2);
            let source = if !source_ptr.is_null() && (0..=512).contains(&source_len) {
                String::from_utf8_lossy(std::slice::from_raw_parts(source_ptr, source_len as usize)).into_owned()
            } else { String::new() };
            let payload_ptr = sqlite3_column_blob(stmt.0, 3);
            let payload_len = sqlite3_column_bytes(stmt.0, 3);
            if payload_ptr.is_null() || !(1..=65536).contains(&payload_len) { continue; }
            let data = std::slice::from_raw_parts(payload_ptr.cast::<u8>(), payload_len as usize);
            rows.push(json!({"id": id, "time": time, "source": source, "payload": hex(data)}));
        }
        Ok(json!({"time":time,"id":id,"items":rows,"hasMore":has_more}))
    }
}

#[no_mangle]
pub unsafe extern "C" fn rium_system_notifications_read(path: *const c_char, after_time: f64, after_id: i64) -> *mut c_char {
    if path.is_null() { return ptr::null_mut(); }
    let value = read(CStr::from_ptr(path), after_time, after_id).unwrap_or_else(|error| json!({"error":error}));
    CString::new(value.to_string()).map(CString::into_raw).unwrap_or(ptr::null_mut())
}

#[no_mangle]
pub unsafe extern "C" fn rium_system_notifications_free(value: *mut c_char) {
    if !value.is_null() { drop(CString::from_raw(value)); }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::ffi::OsStrExt;
    #[test]
    fn validates_cursor_and_hex() {
        assert_eq!(hex(&[0, 15, 16, 255]), "000f10ff");
        let path = c"/nonexistent/rium-notifications";
        assert!(read(path, f64::NAN, 0).is_err());
        assert!(read(path, 0.0, -1).is_err());
        assert!(read(path, -1.0, 0).is_err());
    }
    #[test]
    fn reads_only_new_delivered_records_and_preserves_order() {
        let unique = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos();
        let dir = std::env::temp_dir().join(format!("rium-notification-test-{}-{unique}", std::process::id()));
        std::fs::create_dir(&dir).unwrap();
        let db = dir.join("db");
        let sql = "CREATE TABLE app(app_id INTEGER PRIMARY KEY,identifier TEXT); CREATE TABLE record(rec_id INTEGER PRIMARY KEY,app_id INTEGER,delivered_date REAL,data BLOB); INSERT INTO app VALUES(1,'example.test'); INSERT INTO record VALUES(1,1,100,X'0102'); INSERT INTO record VALUES(2,1,NULL,X'03');";
        assert!(std::process::Command::new("/usr/bin/sqlite3").arg(&db).arg(sql).status().unwrap().success());
        let path = CString::new(db.as_os_str().as_bytes()).unwrap();
        let baseline = read(&path, -1.0, 0).unwrap();
        assert_eq!(baseline["time"], 100.0);
        assert_eq!(baseline["id"], 1);
        assert!(baseline["items"].as_array().unwrap().is_empty());
        let sql = "UPDATE record SET delivered_date=101 WHERE rec_id=2; INSERT INTO record VALUES(3,1,101,X'0405');";
        assert!(std::process::Command::new("/usr/bin/sqlite3").arg(&db).arg(sql).status().unwrap().success());
        let next = read(&path, 100.0, 1).unwrap();
        assert_eq!(next["items"].as_array().unwrap().len(), 2);
        assert_eq!(next["items"][0]["id"], 2);
        assert_eq!(next["items"][0]["time"], 101.0);
        assert_eq!(next["items"][1]["payload"], "0405");
        assert_eq!(next["time"], 101.0);
        assert_eq!(next["id"], 3);
        assert!(read(&path, 101.0, 3).unwrap()["items"].as_array().unwrap().is_empty());
        let sql = "WITH RECURSIVE n(x) AS (SELECT 4 UNION ALL SELECT x+1 FROM n WHERE x<20) INSERT INTO record SELECT x,1,102,CASE WHEN x=4 THEN NULL ELSE X'04' END FROM n;";
        assert!(std::process::Command::new("/usr/bin/sqlite3").arg(&db).arg(sql).status().unwrap().success());
        let batch = read(&path, 101.0, 3).unwrap();
        assert_eq!(batch["id"], 19);
        assert_eq!(batch["items"].as_array().unwrap().len(), 15);
        assert_eq!(batch["hasMore"], true);
        let remainder = read(&path, 102.0, 19).unwrap();
        assert_eq!(remainder["id"], 20);
        assert_eq!(remainder["items"].as_array().unwrap().len(), 1);
        assert_eq!(remainder["hasMore"], false);
        let sql = "DELETE FROM record WHERE rec_id=20; INSERT INTO record VALUES(20,1,103,X'05');";
        assert!(std::process::Command::new("/usr/bin/sqlite3").arg(&db).arg(sql).status().unwrap().success());
        let reused = read(&path, 102.0, 20).unwrap();
        assert_eq!(reused["items"][0]["id"], 20);
        assert_eq!(reused["items"][0]["time"], 103.0);
        std::fs::remove_dir_all(dir).unwrap();
    }
}
