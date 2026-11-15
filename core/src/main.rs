use serde_json::{json, Value};
use std::env;
use std::fs::{self, OpenOptions};
use std::io::{self, BufRead, BufReader, Read, Write};
use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::mpsc::{self, Receiver, RecvTimeoutError};
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread;
use std::time::{Duration, Instant};

// Process::terminate() sends SIGTERM. Record it in the signal handler and
// unwind normally so Server::drop terminates and waits for its Codex child.
// The handler performs no allocation, locking, logging or process control.
static SHUTDOWN: AtomicBool = AtomicBool::new(false);
extern "C" fn request_shutdown(_: i32) { SHUTDOWN.store(true, Ordering::Relaxed); }
extern "C" { fn signal(sig: i32, handler: extern "C" fn(i32)) -> usize; }
fn install_shutdown_handler() { unsafe { signal(15, request_shutdown); } }

fn emit(v: Value) {
    println!("{v}");
    let _ = io::stdout().flush();
}
fn root() -> Result<PathBuf, String> {
    if let Some(test_root) = env::var_os("MENUBAR_TEST_ROOT") { return Ok(PathBuf::from(test_root)); }
    let user_home = env::var_os("HOME").ok_or("사용자 홈 폴더를 찾을 수 없습니다")?;
    Ok(PathBuf::from(user_home).join("Library/Application Support/MenuBarWorkspace/accounts"))
}
fn ensure_root() -> Result<PathBuf, String> {
    let path = root()?;
    fs::DirBuilder::new().recursive(true).mode(0o700).create(&path).map_err(|_| "계정 폴더를 만들 수 없습니다")?;
    fs::set_permissions(&path, fs::Permissions::from_mode(0o700)).map_err(|_| "계정 폴더 권한을 설정할 수 없습니다")?;
    Ok(path)
}
fn valid_id(id: &str) -> bool {
    id.len() == 36 && id.chars().enumerate().all(|(i,c)| if [8,13,18,23].contains(&i) { c == '-' } else { c.is_ascii_hexdigit() })
}
fn profile(id: &str) -> Result<PathBuf, String> {
    if !valid_id(id) { return Err("잘못된 계정 식별자입니다".into()); }
    let p = root()?.join(id);
    let m = fs::symlink_metadata(&p).map_err(|_| "계정을 찾을 수 없습니다")?;
    if !m.is_dir() || m.file_type().is_symlink() { return Err("계정 폴더가 올바르지 않습니다".into()); }
    Ok(p)
}
fn read_profile(id: &str) -> Result<Value, String> {
    let path = profile(id)?.join("profile.json");
    let data = fs::read(path).map_err(|_| "계정 정보를 읽을 수 없습니다")?;
    let v: Value = serde_json::from_slice(&data).map_err(|_| "계정 정보 형식이 올바르지 않습니다")?;
    Ok(json!({"id":id,"name":v.get("name").and_then(Value::as_str).unwrap_or("Codex 계정")}))
}
fn create(name: &str) -> Result<Value, String> {
    let name = name.trim();
    if name.is_empty() || name.chars().count() > 60 { return Err("계정 이름은 1~60자로 입력해 주세요".into()); }
    let root = ensure_root()?;
    let out = Command::new("/usr/bin/uuidgen").output().map_err(|_| "계정 식별자를 만들 수 없습니다")?;
    let id = String::from_utf8_lossy(&out.stdout).trim().to_lowercase();
    if !out.status.success() || !valid_id(&id) { return Err("계정 식별자를 만들 수 없습니다".into()); }
    let dir = root.join(&id);
    fs::DirBuilder::new().mode(0o700).create(&dir).map_err(|_| "계정 폴더를 만들 수 없습니다")?;
    let result = (|| {
        let mut f = OpenOptions::new().write(true).create_new(true).mode(0o600).open(dir.join("profile.json")).map_err(|_| "계정 정보를 저장할 수 없습니다")?;
        write!(f, "{}", json!({"name":name})).map_err(|_| "계정 정보를 저장할 수 없습니다")?;
        Ok(json!({"id":id,"name":name}))
    })();
    if result.is_err() { let _ = fs::remove_dir_all(&dir); }
    result
}
fn rename(id: &str, name: &str) -> Result<Value, String> {
    let name = name.trim();
    if name.is_empty() || name.chars().count() > 60 { return Err("계정 이름은 1~60자로 입력해 주세요".into()); }
    let dir = profile(id)?;
    let existing = fs::read(dir.join("profile.json")).map_err(|_| "계정 정보를 읽을 수 없습니다")?;
    let mut data: Value = serde_json::from_slice(&existing).map_err(|_| "계정 정보 형식이 올바르지 않습니다")?;
    data.as_object_mut().ok_or("계정 정보 형식이 올바르지 않습니다")?.insert("name".into(), json!(name));
    let uuid = Command::new("/usr/bin/uuidgen").output().map_err(|_| "계정 이름을 저장할 수 없습니다")?;
    let suffix = String::from_utf8_lossy(&uuid.stdout).trim().to_lowercase();
    if !uuid.status.success() || !valid_id(&suffix) { return Err("계정 이름을 저장할 수 없습니다".into()); }
    let temp = dir.join(format!(".profile-{suffix}.tmp"));
    let mut f = OpenOptions::new().write(true).create_new(true).mode(0o600).open(&temp).map_err(|_| "계정 이름을 저장할 수 없습니다")?;
    let result = (|| {
        write!(f,"{data}").and_then(|_|f.sync_all()).map_err(|_| "계정 이름을 저장할 수 없습니다")?;
        fs::rename(&temp,dir.join("profile.json")).map_err(|_| "계정 이름을 저장할 수 없습니다")
    })();
    if result.is_err() { let _ = fs::remove_file(&temp); }
    result?;
    Ok(json!({"id":id,"name":name}))
}
fn list() -> Result<Value, String> {
    let root = ensure_root()?;
    let mut profiles = Vec::new();
    for ent in fs::read_dir(root).map_err(|_| "계정 목록을 읽을 수 없습니다")? {
        let ent=ent.map_err(|_| "계정 목록을 읽을 수 없습니다")?;
        if let Some(id) = ent.file_name().to_str() {
            if valid_id(id) {
                profiles.push(read_profile(id).unwrap_or_else(|_|json!({"id":id,"name":"계정 정보 확인 필요","profileError":true})));
            }
        }
    }
    profiles.sort_by_key(|a| a["name"].as_str().unwrap_or("").to_lowercase());
    Ok(json!(profiles))
}
fn binary() -> Result<PathBuf, String> {
    if let Some(p) = env::var_os("MENUBAR_CODEX_BIN") { return Ok(PathBuf::from(p)); }
    for p in ["/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex", "/Applications/Codex.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"] {
        if Path::new(p).is_file() { return Ok(PathBuf::from(p)); }
    }
    Err("Codex CLI를 찾을 수 없습니다. 공식 Codex 앱 또는 CLI를 설치해 주세요".into())
}
struct Server { child: Child, input: ChildStdin, incoming: Receiver<Value>, pending: Vec<Value> }
fn usage_window(v: &Value) -> Value {
    if !v.is_object() { return Value::Null; }
    json!({"usedPercent":v.get("usedPercent"),"windowDurationMins":v.get("windowDurationMins"),"resetsAt":v.get("resetsAt")})
}
fn individual_limit(v: &Value) -> Value {
    if !v.is_object() { return Value::Null; }
    json!({"remainingPercent":v.get("remainingPercent").and_then(Value::as_i64).filter(|v| (0..=100).contains(v)),"resetsAt":v.get("resetsAt").and_then(Value::as_i64)})
}
fn normalize_usage(limits: &Value) -> Result<Value, String> {
    let legacy = limits.get("rateLimits").filter(|v| v.is_object()).ok_or("Codex 사용량 응답 형식이 올바르지 않습니다")?;
    let credits = legacy.get("credits").filter(|v|v.is_object()).map(|c|json!({"hasCredits":c.get("hasCredits"),"unlimited":c.get("unlimited"),"balance":c.get("balance")})).unwrap_or(Value::Null);
    let legacy_id = legacy.get("limitId").and_then(Value::as_str);
    let mut buckets = Vec::new();
    if let Some(map) = limits.get("rateLimitsByLimitId").and_then(Value::as_object) {
        let mut entries: Vec<_> = map.iter().collect();
        entries.sort_by_key(|(id, _)| *id);
        for (id, value) in entries {
            if !value.is_object() || legacy_id == Some(id.as_str()) || legacy_id.is_some() && legacy_id == value.get("limitId").and_then(Value::as_str) { continue; }
            buckets.push(json!({"id":id,"name":value.get("limitName"),"model":value.get("normalModelSlug"),"primary":usage_window(&value["primary"]),"secondary":usage_window(&value["secondary"]),"spendControlReached":value.get("spendControlReached").and_then(Value::as_bool),"rateLimitReachedType":value.get("rateLimitReachedType").and_then(Value::as_str),"individualLimit":individual_limit(&value["individualLimit"])}));
        }
    }
    Ok(json!({"primary":usage_window(&legacy["primary"]),"secondary":usage_window(&legacy["secondary"]),"credits":credits,"ordinaryUsageAllowed":limits.get("ordinaryUsageAllowed").and_then(Value::as_bool),"spendControlReached":legacy.get("spendControlReached").and_then(Value::as_bool),"rateLimitReachedType":legacy.get("rateLimitReachedType").and_then(Value::as_str),"individualLimit":individual_limit(&legacy["individualLimit"]),"resetCreditsAvailable":limits.pointer("/rateLimitResetCredits/availableCount").and_then(Value::as_u64),"buckets":buckets}))
}
impl Drop for Server { fn drop(&mut self) { let _ = self.child.kill(); let _ = self.child.wait(); } }
impl Server {
    fn start(home: &Path) -> Result<Self, String> {
        let mut cmd = Command::new(binary()?);
        cmd.args(["app-server", "--listen", "stdio://", "-c", "cli_auth_credentials_store=\"keyring\""])
            .current_dir(home).env("CODEX_HOME",home)
            .stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::null());
        for (key,_) in env::vars_os() {
            let k = key.to_string_lossy();
            if (k.starts_with("CODEX_") && k != "CODEX_HOME") || k.starts_with("OPENAI_") || k == "CHATGPT_BASE_URL" { cmd.env_remove(key); }
        }
        let mut child = cmd.spawn().map_err(|_| "Codex 서버를 실행할 수 없습니다")?;
        let input = child.stdin.take().ok_or("Codex 입력을 열 수 없습니다")?;
        let output = child.stdout.take().ok_or("Codex 출력을 열 수 없습니다")?;
        let (tx, rx) = mpsc::channel();
        thread::spawn(move || for line in BufReader::new(output).lines() {
            match line { Ok(s) => if let Ok(v) = serde_json::from_str::<Value>(&s) { if tx.send(v).is_err() { break; } }, Err(_) => break }
        });
        let mut s = Self { child, input, incoming:rx, pending:Vec::new() };
        s.send(json!({"id":1,"method":"initialize","params":{"clientInfo":{"name":"menu_bar_workspace","title":"Menu Bar Workspace","version":env!("CARGO_PKG_VERSION")}}}))?;
        s.response(1,Duration::from_secs(15))?;
        s.send(json!({"method":"initialized","params":{}}))?;
        Ok(s)
    }
    fn send(&mut self, v: Value) -> Result<(),String> {
        writeln!(self.input,"{v}").and_then(|_|self.input.flush()).map_err(|_| "Codex 서버와 통신할 수 없습니다".into())
    }
    fn wait<F:Fn(&Value)->bool>(&mut self, predicate:F, timeout:Duration) -> Result<Value,String> {
        if SHUTDOWN.load(Ordering::Relaxed) { return Err("종료 중입니다".into()); }
        if let Some(i) = self.pending.iter().position(&predicate) { return Ok(self.pending.remove(i)); }
        let end = Instant::now() + timeout;
        loop {
            let left = end.saturating_duration_since(Instant::now());
            if left.is_zero() { return Err("Codex 응답 시간이 초과되었습니다".into()); }
            if SHUTDOWN.load(Ordering::Relaxed) { return Err("종료 중입니다".into()); }
            let msg = match self.incoming.recv_timeout(left.min(Duration::from_millis(100))) {
                Ok(msg) => msg,
                Err(RecvTimeoutError::Timeout) => continue,
                Err(RecvTimeoutError::Disconnected) => return Err("Codex 서버가 응답하지 않습니다".into()),
            };
            if predicate(&msg) { return Ok(msg); }
            if self.pending.len() < 256 { self.pending.push(msg); }
        }
    }
    fn response(&mut self, id:u64, timeout:Duration) -> Result<Value,String> {
        let msg=self.wait(|m|m.get("id").and_then(Value::as_u64)==Some(id),timeout)?;
        if msg.get("error").is_some() { return Err("Codex 요청이 실패했습니다. 로그인 상태 또는 네트워크를 확인해 주세요".into()); }
        msg.get("result").cloned().ok_or_else(|| "Codex 응답 형식이 올바르지 않습니다".into())
    }
    fn read(&mut self) -> Result<Value,String> {
        self.send(json!({"id":4,"method":"account/read","params":{"refreshToken":false}}))?;
        let a=self.response(4,Duration::from_secs(20))?;
        let account=a.get("account").cloned().unwrap_or(Value::Null);
        if account.is_null() { return Ok(json!({"status":"disconnected"})); }
        if account.get("type").and_then(Value::as_str)!=Some("chatgpt") { return Ok(json!({"status":"unsupported"})); }
        self.send(json!({"id":5,"method":"account/rateLimits/read","params":{}}))?;
        let limits=self.response(5,Duration::from_secs(30))?;
        let mut result = normalize_usage(&limits)?;
        result["status"] = json!("connected");
        Ok(result)
    }
}

#[cfg(test)]
mod usage_tests {
    use super::*;
    #[test]
    fn multiple_buckets_keep_unknown_values_and_backend_restrictions() {
        let value = json!({"ordinaryUsageAllowed":false,"rateLimits":{"limitId":"codex","primary":{"usedPercent":0,"resetsAt":null}},"rateLimitsByLimitId":{"codex":{"limitId":"codex"},"other":{"limitName":"Extra","primary":null,"spendControlReached":true}}});
        let result = normalize_usage(&value).unwrap();
        assert_eq!(result["ordinaryUsageAllowed"], false);
        assert_eq!(result["primary"]["usedPercent"], 0);
        assert!(result["primary"]["resetsAt"].is_null());
        assert_eq!(result["buckets"].as_array().unwrap().len(), 1);
        assert_eq!(result["buckets"][0]["id"], "other");
        assert!(result["buckets"][0]["primary"].is_null());
        assert_eq!(result["buckets"][0]["spendControlReached"], true);
    }
    #[test]
    fn legacy_and_missing_responses_are_handled_without_inventing_usage() {
        let result = normalize_usage(&json!({"rateLimits":{"primary":null}})).unwrap();
        assert!(result["ordinaryUsageAllowed"].is_null());
        assert!(result["primary"].is_null());
        assert!(result["buckets"].as_array().unwrap().is_empty());
        assert!(normalize_usage(&json!({})).is_err());
    }
    #[test]
    fn explicit_restriction_details_and_missing_values_survive() {
        let value = json!({"rateLimits":{"rateLimitReachedType":"workspace_member_usage_limit_reached","individualLimit":{"remainingPercent":13,"resetsAt":123}},"rateLimitResetCredits":{"availableCount":2},"rateLimitsByLimitId":{"extra":{"rateLimitReachedType":"rate_limit_reached","individualLimit":{"remainingPercent":-1}}}});
        let result = normalize_usage(&value).unwrap();
        assert_eq!(result["rateLimitReachedType"], "workspace_member_usage_limit_reached");
        assert_eq!(result["individualLimit"]["remainingPercent"], 13);
        assert_eq!(result["resetCreditsAvailable"], 2);
        assert_eq!(result["buckets"][0]["rateLimitReachedType"], "rate_limit_reached");
        assert!(result["buckets"][0]["individualLimit"]["remainingPercent"].is_null());
        let missing = normalize_usage(&json!({"rateLimits":{}})).unwrap();
        assert!(missing["individualLimit"].is_null() && missing["resetCreditsAvailable"].is_null());
    }
}
fn login(id:&str) -> Result<Value,String> {
    let mut s=Server::start(&profile(id)?)?;
    s.send(json!({"id":2,"method":"account/login/start","params":{"type":"chatgpt"}}))?;
    let r=s.response(2,Duration::from_secs(20))?;
    let url=r.get("authUrl").and_then(Value::as_str).ok_or("로그인 주소를 받지 못했습니다")?;
    if !url.starts_with("https://auth.openai.com/") { return Err("예상하지 못한 로그인 주소입니다".into()); }
    let login_id=r.get("loginId").cloned().ok_or("로그인 식별자를 받지 못했습니다")?;
    emit(json!({"event":"login_url","url":url}));
    let event=s.wait(|m|m.get("method").and_then(Value::as_str)==Some("account/login/completed") && m["params"]["loginId"]==login_id,Duration::from_secs(180))?;
    if event["params"]["success"].as_bool()!=Some(true) { return Err("로그인이 취소되었거나 실패했습니다".into()); }
    s.read()
}
fn remove(id:&str) -> Result<Value,String> {
    let dir=profile(id)?;
    let mut s=Server::start(&dir)?;
    s.send(json!({"id":6,"method":"account/logout","params":{}}))?;
    s.response(6,Duration::from_secs(20))?;
    drop(s);
    fs::remove_dir_all(dir).map_err(|_| "계정은 로그아웃했지만 로컬 정보 삭제에 실패했습니다")?;
    Ok(json!({"removed":true}))
}
fn main() {
    install_shutdown_handler();
    let args:Vec<String>=env::args().collect();
    let result = match args.get(1).map(String::as_str) {
        Some("list") => list(),
        Some("create") => create(args.get(2).map(String::as_str).unwrap_or("")),
        Some("rename") => rename(args.get(2).map(String::as_str).unwrap_or(""),args.get(3).map(String::as_str).unwrap_or("")),
        Some("login") => login(args.get(2).map(String::as_str).unwrap_or("")),
        Some("refresh") => profile(args.get(2).map(String::as_str).unwrap_or("")).and_then(|p|Server::start(&p)).and_then(|mut s|s.read()),
        Some("remove") => remove(args.get(2).map(String::as_str).unwrap_or("")),
        Some("weather") => {
            let lat = args.get(2).and_then(|s| s.parse::<f64>().ok());
            let lon = args.get(3).and_then(|s| s.parse::<f64>().ok());
            match (lat, lon) {
                (Some(lat), Some(lon)) => rium_notch_core::weather::forecast(lat, lon),
                _ => Err("날씨 위치가 올바르지 않습니다".into()),
            }
        },
        Some("media") => rium_notch_core::media::request(args.get(2).map(String::as_str).unwrap_or("get"), args.get(3).map(String::as_str)),
        Some("lyrics") => {
            let mut input = Vec::new();
            match io::stdin().lock().take(4097).read_to_end(&mut input) {
                Ok(_) if input.len() <= 4096 => match serde_json::from_slice::<Value>(&input) {
                    Ok(v) => rium_notch_core::lyrics::lookup(v["title"].as_str().unwrap_or(""), v["artist"].as_str().unwrap_or(""), v["duration"].as_f64()),
                    Err(_) => Err("가사 요청을 읽을 수 없습니다".into()),
                },
                _ => Err("가사 요청을 읽을 수 없습니다".into()),
            }
        },
        Some("agents") => rium_notch_core::agents::recent(),
        _ => Err("지원하지 않는 명령입니다".into()),
    };
    match result { Ok(v)=>emit(json!({"event":"result","data":v})), Err(e)=>{emit(json!({"event":"error","message":e})); std::process::exit(1)} }
}
