//! Direct controls verify a live Codex host and thread. When there is no
//! verified idle host, follow-ups use Codex's persistent local thread queue.
use serde_json::{json, Value};
use std::env;
use std::fs::{self, File};
use std::io::{BufRead, BufReader, Read, Write};
use std::os::unix::fs::{FileTypeExt, MetadataExt};
use std::path::{Path, PathBuf};
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::mpsc::{self, Receiver};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

extern "C" { fn geteuid() -> u32; }
const MAX_REPLY: u64 = 2 * 1024 * 1024;
const TIMEOUT: Duration = Duration::from_secs(4);
// shortcut: this matches the current bounded pending-question discovery window;
// the actual target is always checked against the live socket and thread.
const IDENTITY_MAX_AGE_MS: u128 = 24 * 60 * 60 * 1000;
fn valid_id(id: &str) -> bool {
    id.len() == 36 && id.bytes().enumerate().all(|(i, c)| if [8, 13, 18, 23].contains(&i) { c == b'-' } else { c.is_ascii_hexdigit() })
}
fn home() -> Result<PathBuf, String> {
    env::var_os("HOME").map(PathBuf::from).ok_or_else(|| "사용자 폴더를 찾을 수 없습니다".into())
}
fn newest_identity(mut candidates: Vec<(u64, u32, PathBuf)>) -> Option<(u32, PathBuf)> {
    candidates.sort_unstable_by(|a, b| b.0.cmp(&a.0));
    let (stamp, pid, cwd) = candidates.first()?.clone();
    if candidates.iter().skip(1).take_while(|candidate| candidate.0 == stamp)
        .any(|candidate| candidate.1 != pid || candidate.2 != cwd) { return None; }
    Some((pid, cwd))
}
fn identity(session: &str) -> Result<(u32, PathBuf), String> {
    let home = home()?;
    let mut candidates = Vec::new();
    let now = SystemTime::now().duration_since(UNIX_EPOCH).map_err(|_| "시스템 시간을 확인할 수 없습니다")?.as_millis();
    // Prefer the newest valid Rium or legacy hook rather than an older record
    // from a previous process. Equal-time conflicts must remain unresolved.
    for base in [home.join("Library/Application Support/Rium Notch/agent-sessions"),
                 home.join("Library/Application Support/NotchPilot/codex-sessions")] {
        let path = base.join(format!("{session}.json"));
        let Ok(metadata) = fs::symlink_metadata(&path) else { continue; };
        if !metadata.file_type().is_file() || metadata.uid() != unsafe { geteuid() } || metadata.len() > 65_536 { continue; }
        let Ok(file) = File::open(&path) else { continue; };
        let Ok(opened) = file.metadata() else { continue; };
        if !opened.file_type().is_file() || opened.uid() != metadata.uid()
            || opened.dev() != metadata.dev() || opened.ino() != metadata.ino() { continue; }
        let Ok(value) = serde_json::from_reader::<_, Value>(file.take(65_537)) else { continue; };
        if value.get("sessionId").and_then(Value::as_str) != Some(session) { continue; }
        let Some(updated) = value.get("updatedAt").and_then(Value::as_u64) else { continue; };
        if u128::from(updated) > now || now - u128::from(updated) > IDENTITY_MAX_AGE_MS { continue; }
        let Some(pid) = value.get("pid").and_then(Value::as_u64).filter(|pid| *pid > 1 && *pid <= u32::MAX as u64) else { continue; };
        let Some(cwd) = value.get("cwd").and_then(Value::as_str).filter(|path| Path::new(path).is_absolute()) else { continue; };
        let Ok(cwd) = fs::canonicalize(cwd) else { continue; };
        if cwd.is_dir() { candidates.push((updated, pid as u32, cwd)); }
    }
    newest_identity(candidates).ok_or_else(|| "이 대화의 실행 세션을 확인할 수 없습니다. Codex에서 직접 확인해 주세요".into())
}
fn socket_for(pid: u32) -> Result<PathBuf, String> {
    let base = env::var_os("CODEX_HOME").map(PathBuf::from).unwrap_or(home()?.join(".codex"));
    let path = base.join("app-server-control/app-server-control.sock");
    let meta = fs::symlink_metadata(&path).map_err(|_| "연결된 Codex 제어 통로가 없습니다")?;
    if !meta.file_type().is_socket() || meta.uid() != unsafe { geteuid() } { return Err("Codex 제어 통로를 확인할 수 없습니다".into()); }
    let mut child = Command::new("/usr/sbin/lsof").arg("-t").arg(&path).stdout(Stdio::piped()).stderr(Stdio::null())
        .spawn().map_err(|_| "Codex 세션 소유자를 확인할 수 없습니다")?;
    let Some(output) = child.stdout.take() else { let _ = child.kill(); let _ = child.wait(); return Err("Codex 세션 소유자를 확인할 수 없습니다".into()); };
    let (tx, rx) = mpsc::channel();
    thread::spawn(move || { let mut bytes = Vec::new(); let _ = output.take(65_536).read_to_end(&mut bytes); let _ = tx.send(bytes); });
    let deadline = Instant::now() + Duration::from_secs(2);
    let status = loop {
        match child.try_wait() {
            Ok(Some(status)) => break status,
            Ok(None) if Instant::now() < deadline => thread::sleep(Duration::from_millis(20)),
            _ => { let _ = child.kill(); let _ = child.wait(); return Err("Codex 세션 소유자를 확인할 수 없습니다".into()); }
        }
    };
    let output = rx.recv_timeout(Duration::from_millis(200)).unwrap_or_default();
    if !status.success() || !String::from_utf8_lossy(&output).lines().any(|line| line.trim().parse::<u32>().ok() == Some(pid)) {
        return Err("Codex 제어 통로가 이 대화의 실행 프로세스와 일치하지 않습니다".into());
    }
    Ok(path)
}
fn codex_binary() -> Result<PathBuf, String> {
    ["/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
     "/Applications/Codex.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
     "/Applications/Codex.app/Contents/Resources/codex"]
        .iter().map(PathBuf::from).find(|path| path.is_file()).ok_or_else(|| "Codex 실행 파일을 찾을 수 없습니다".into())
}
struct Proxy { child: Child, input: ChildStdin, replies: Receiver<Value>, sequence: u64 }
impl Drop for Proxy { fn drop(&mut self) { let _ = self.child.kill(); let _ = self.child.wait(); } }
impl Proxy {
    fn start(socket: &Path) -> Result<Self, String> {
        let mut command = Command::new(codex_binary()?);
        command.args(["app-server", "proxy", "--sock"]).arg(socket);
        Self::connect(command, false)
    }
    fn connect(mut command: Command, experimental: bool) -> Result<Self, String> {
        let mut child = command.stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::null()).spawn()
            .map_err(|_| "Codex 연결을 열 수 없습니다")?;
        let Some(input) = child.stdin.take() else {
            let _ = child.kill(); let _ = child.wait(); return Err("Codex 입력을 열 수 없습니다".into());
        };
        let Some(output) = child.stdout.take() else {
            let _ = child.kill(); let _ = child.wait(); return Err("Codex 출력을 열 수 없습니다".into());
        };
        let (tx, replies) = mpsc::sync_channel(64);
        thread::spawn(move || {
            let mut reader = BufReader::new(output);
            loop {
                let mut bytes = Vec::new();
                match (&mut reader).take(MAX_REPLY + 1).read_until(b'\n', &mut bytes) {
                    Ok(0) | Err(_) => break,
                    Ok(_) if bytes.len() as u64 > MAX_REPLY || bytes.last() != Some(&b'\n') => break,
                    Ok(_) => if let Ok(value) = serde_json::from_slice::<Value>(&bytes) { if tx.send(value).is_err() { break; } },
                }
            }
        });
        let mut proxy = Self { child, input, replies, sequence: 0 };
        let mut params = json!({"clientInfo":{"name":"rium_notch","version":"1.0.0"}});
        if experimental { params["capabilities"] = json!({"experimentalApi":true}); }
        proxy.request("initialize", params)?;
        proxy.write(json!({"method":"initialized"}))?;
        Ok(proxy)
    }
    fn write(&mut self, value: Value) -> Result<(), String> {
        writeln!(self.input, "{value}").and_then(|_| self.input.flush()).map_err(|_| "Codex 연결이 끊어졌습니다".into())
    }
    fn request(&mut self, method: &str, params: Value) -> Result<Value, String> {
        self.sequence += 1;
        let id = self.sequence;
        self.write(json!({"id":id,"method":method,"params":params}))?;
        let end = Instant::now() + TIMEOUT;
        loop {
            let remaining = end.saturating_duration_since(Instant::now());
            if remaining.is_zero() { return Err("Codex 응답 시간이 초과되었습니다".into()); }
            let response = self.replies.recv_timeout(remaining).map_err(|_| "Codex 응답을 확인할 수 없습니다")?;
            // Server requests can reuse numeric IDs; only method-free replies
            // belong to this client. Never answer server approval requests.
            if response.get("method").is_some() || response.get("id").and_then(Value::as_u64) != Some(id) { continue; }
            if response.get("error").is_some() { return Err("Codex가 요청을 거부했습니다".into()); }
            return response.get("result").cloned().ok_or_else(|| "Codex 응답 형식이 올바르지 않습니다".into());
        }
    }
}
fn idle_followup_proxy(session: &str) -> Option<Proxy> {
    let (pid, cwd) = identity(session).ok()?;
    let socket = socket_for(pid).ok()?;
    let mut proxy = Proxy::start(&socket).ok()?;
    let loaded = proxy.request("thread/loaded/list", json!({})).ok()?;
    if !loaded["data"].as_array()?.iter().any(|id| id.as_str() == Some(session)) { return None; }
    let read = proxy.request("thread/read", json!({"threadId":session,"includeTurns":false})).ok()?;
    let thread = &read["thread"];
    let matched_cwd = thread["cwd"].as_str().and_then(|path| fs::canonicalize(path).ok()).is_some_and(|path| path == cwd);
    if thread["id"].as_str() != Some(session) || !matched_cwd
        || thread.pointer("/status/type").and_then(Value::as_str) != Some("idle") { return None; }
    proxy.request("thread/resume", json!({"threadId":session})).ok()?;
    Some(proxy)
}

fn queue_followup(session: &str, text: &str, message_id: &str) -> Result<Value, String> {
    let mut command = Command::new(codex_binary()?);
    command.args(["app-server", "--listen", "stdio://"]);
    let mut proxy = Proxy::connect(command, true)?;
    let result = proxy.request("thread/queue/add", json!({"threadId":session, "clientUserMessageId":message_id,
        "input":[{"type":"text","text":text,"text_elements":[]}]}));
    let queued = result.as_ref().ok().is_some_and(|value| {
        let item = &value["queuedSubmission"];
        item["clientUserMessageId"].as_str() == Some(message_id)
            && item["id"].as_str().is_some_and(|id| !id.is_empty())
    });
    Ok(json!({"status":if queued {"queued"} else {"unknown"}}))
}

pub fn followup(session: &str, text: &str, message_id: &str) -> Result<Value, String> {
    let text = text.trim();
    if !valid_id(session) || !valid_id(message_id) || text.is_empty() || text.len() > 20_000 {
        return Err("대화 또는 메시지가 올바르지 않습니다".into());
    }
    let Some(mut proxy) = idle_followup_proxy(session) else { return queue_followup(session, text, message_id); };
    // Once bytes have been sent, a timeout or disconnect is not proof of
    // failure. Return unknown and never automatically retry a message.
    let result = proxy.request("turn/start", json!({"threadId":session,"input":[{"type":"text","text":text,"text_elements":[]}]}));
    let accepted = result.as_ref().ok().and_then(|result| result.pointer("/turn/id")).and_then(Value::as_str).is_some_and(|id| !id.is_empty());
    let _ = proxy.request("thread/unsubscribe", json!({"threadId":session}));
    Ok(json!({"status":if accepted {"accepted"} else {"unknown"}}))
}

/// Interrupt only the currently active turn in the verified existing session.
/// A missing or ambiguous identity/status fails closed; never signal a host.
pub fn interrupt(session: &str) -> Result<Value, String> {
    if !valid_id(session) { return Err("대화 식별자를 확인할 수 없습니다".into()); }
    let (pid, cwd) = identity(session)?;
    let socket = socket_for(pid)?;
    let mut proxy = Proxy::start(&socket)?;
    let loaded = proxy.request("thread/loaded/list", json!({}))?;
    if !loaded.get("data").and_then(Value::as_array).is_some_and(|ids| ids.iter().any(|id| id.as_str() == Some(session))) {
        return Err("이 Codex 서버에서 해당 대화를 찾을 수 없습니다".into());
    }
    let read = proxy.request("thread/read", json!({"threadId":session,"includeTurns":true}))?;
    let thread = &read["thread"];
    let matched_cwd = thread.get("cwd").and_then(Value::as_str).and_then(|path| fs::canonicalize(path).ok()).is_some_and(|path| path == cwd);
    if thread.get("id").and_then(Value::as_str) != Some(session) || !matched_cwd {
        return Err("대화와 작업 폴더가 일치하지 않습니다".into());
    }
    let turns = thread.get("turns").and_then(Value::as_array).ok_or("진행 중인 작업을 확인할 수 없습니다")?;
    let mut active = turns.iter().filter(|turn| turn.get("status").and_then(Value::as_str) == Some("inProgress"));
    let turn_id = active.next().and_then(|turn| turn.get("id")).and_then(Value::as_str)
        .filter(|id| !id.is_empty() && id.len() <= 256).ok_or("진행 중인 작업을 확인할 수 없습니다")?;
    if active.next().is_some() || thread.pointer("/status/type").and_then(Value::as_str) != Some("active") {
        return Err("현재 Codex 작업 상태를 확인할 수 없습니다".into());
    }
    // The turn can finish or change between reading and interrupting. The
    // server must reject a stale ID; do not retry against a different turn.
    let result = proxy.request("turn/interrupt", json!({"threadId":session,"turnId":turn_id}));
    Ok(json!({"status":if result.is_ok() {"accepted"} else {"unknown"}}))
}

fn encode_question_reply(question_id: &str, question: &str, answer: &str) -> String {
    let reply = json!([{"questionItemId":question_id,"question":question,"answer":answer.trim()}]);
    format!("<send_user_message_question_reply>\n{reply}\n</send_user_message_question_reply>")
}

/// Respond only to an async question still present in the verified engine's
/// live thread. Pending native approval requests are intentionally excluded.
pub fn answer(session: &str, question_id: &str, shown_question: &str, shown_options: &Value, answer: &str) -> Result<Value, String> {
    if !valid_id(session) || question_id.len() > 230 || shown_question.is_empty() || shown_question.len() > 4000
        || answer.trim().is_empty() || answer.len() > 2000
        || shown_question.contains("</send_user_message_question_reply>") || answer.contains("</send_user_message_question_reply>") {
        return Err("질문 또는 답변이 올바르지 않습니다".into());
    }
    let parsed: Value = serde_json::from_str(question_id).map_err(|_| "질문 식별자를 확인할 수 없습니다")?;
    let id = parsed.as_array().filter(|id| id.len() == 3).ok_or("질문 식별자를 확인할 수 없습니다")?;
    let (Some("request_user_input_async"), Some(call), Some(index)) = (id[0].as_str(), id[1].as_str(), id[2].as_u64()) else {
        return Err("이 질문은 Codex에서 직접 답변해 주세요".into());
    };
    if call.is_empty() || call.len() > 200 || index > 2 { return Err("질문 식별자를 확인할 수 없습니다".into()); }
    let (pid, cwd) = identity(session)?;
    let socket = socket_for(pid)?;
    let mut proxy = Proxy::start(&socket)?;
    let loaded = proxy.request("thread/loaded/list", json!({}))?;
    if !loaded.get("data").and_then(Value::as_array).is_some_and(|ids| ids.iter().any(|id| id.as_str() == Some(session))) {
        return Err("이 Codex 서버에서 해당 대화를 찾을 수 없습니다".into());
    }
    let read = proxy.request("thread/read", json!({"threadId":session,"includeTurns":true}))?;
    let thread = &read["thread"];
    let matched_cwd = thread.get("cwd").and_then(Value::as_str).and_then(|path| fs::canonicalize(path).ok()).is_some_and(|path| path == cwd);
    if thread.get("id").and_then(Value::as_str) != Some(session) || !matched_cwd { return Err("대화와 작업 폴더가 일치하지 않습니다".into()); }
    let turns = thread.get("turns").and_then(Value::as_array).ok_or("대기 중인 질문을 확인할 수 없습니다")?;
    let items: Vec<&Value> = turns.iter().flat_map(|turn| turn.get("items").and_then(Value::as_array).into_iter().flatten()).collect();
    let request = items.iter().find(|item| item.get("type").and_then(Value::as_str) == Some("agentMessage")
        && item.get("id").and_then(Value::as_str) == Some(call)).ok_or("대기 중인 질문을 찾을 수 없습니다")?;
    let question = request.get("questions").and_then(Value::as_array).and_then(|questions| questions.get(index as usize))
        .ok_or("대기 중인 질문을 찾을 수 없습니다")?;
    if question.get("isSecret").and_then(Value::as_bool) == Some(true) || question.get("is_secret").and_then(Value::as_bool) == Some(true)
        || question.get("multiSelect").and_then(Value::as_bool) == Some(true)
        || question.get("multi_select").and_then(Value::as_bool) == Some(true) {
        return Err("이 질문은 Codex에서 직접 답변해 주세요".into());
    }
    let actual = question.get("title").and_then(Value::as_str).filter(|text| !text.trim().is_empty())
        .or_else(|| question.get("question").and_then(Value::as_str)).ok_or("질문 내용을 확인할 수 없습니다")?;
    if actual.trim() != shown_question { return Err("질문이 변경되었습니다. Codex에서 확인해 주세요".into()); }
    let shown = shown_options.as_array().filter(|options| options.len() <= 20).ok_or("선택지를 확인할 수 없습니다")?;
    let shown: Vec<&str> = shown.iter().map(Value::as_str).collect::<Option<Vec<_>>>().ok_or("선택지를 확인할 수 없습니다")?;
    let options = question.get("options").and_then(Value::as_array);
    let actual: Vec<&str> = match options {
        Some(options) if options.len() <= 20 => options.iter()
            .map(|option| option.as_str().or_else(|| option.get("label").and_then(Value::as_str)))
            .collect::<Option<Vec<_>>>().ok_or("선택지를 확인할 수 없습니다")?,
        Some(_) => return Err("이 질문은 Codex에서 직접 답변해 주세요".into()),
        None => Vec::new(),
    };
    if shown != actual {
        return Err("선택지가 변경되었습니다. Codex에서 확인해 주세요".into());
    }
    for item in &items {
        let parts = match item.get("type").and_then(Value::as_str) {
            Some("userMessage") => item.get("content").and_then(Value::as_array),
            Some("steeringUserMessage") if item.get("status").and_then(Value::as_str) == Some("accepted") => item.get("input").and_then(Value::as_array),
            _ => None,
        };
        for part in parts.into_iter().flatten() {
            let Some(text) = part.get("text").and_then(Value::as_str) else { continue; };
            let Some(text) = text.trim().strip_prefix("<send_user_message_question_reply>") else { continue; };
            let Some((body, _)) = text.split_once("</send_user_message_question_reply>") else { continue; };
            let Ok(value) = serde_json::from_str::<Value>(body.trim()) else { continue; };
            if value.as_array().is_some_and(|replies| replies.iter().any(|reply| reply.get("questionItemId").and_then(Value::as_str) == Some(question_id))) {
                return Err("이미 답변한 질문입니다".into());
            }
        }
    }
    let active = turns.iter().rev().find(|turn| turn.get("status").and_then(Value::as_str) == Some("inProgress"));
    let turn_id = active.and_then(|turn| turn.get("id")).and_then(Value::as_str);
    if thread.pointer("/status/type").and_then(Value::as_str) != Some("idle") && turn_id.is_none() {
        return Err("현재 Codex 작업 상태를 확인할 수 없습니다".into());
    }
    let prompt = encode_question_reply(question_id, shown_question, answer);
    proxy.request("thread/resume", json!({"threadId":session}))?;
    let response = if let Some(turn) = turn_id {
        proxy.request("turn/steer", json!({"threadId":session,"expectedTurnId":turn,"input":[{"type":"text","text":prompt}]}))
    } else {
        proxy.request("turn/start", json!({"threadId":session,"input":[{"type":"text","text":prompt}]}))
    };
    let accepted = response.as_ref().ok().and_then(|response| response.get("turnId").or_else(|| response.pointer("/turn/id")))
        .and_then(Value::as_str).is_some_and(|id| !id.is_empty());
    let _ = proxy.request("thread/unsubscribe", json!({"threadId":session}));
    Ok(json!({"status":if accepted {"accepted"} else {"unknown"}}))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn newest_record_wins_and_equal_timestamp_conflicts_fail_closed() {
        let first = PathBuf::from("/workspace/first");
        let second = PathBuf::from("/workspace/second");
        assert_eq!(newest_identity(vec![(10, 4, first.clone()), (20, 9, second.clone())]), Some((9, second.clone())));
        assert_eq!(newest_identity(vec![(20, 9, second.clone()), (20, 9, second.clone())]), Some((9, second.clone())));
        assert_eq!(newest_identity(vec![(20, 9, second.clone()), (20, 4, first)]), None);
        assert_eq!(newest_identity(Vec::new()), None);
    }

    #[test]
    fn freeform_question_reply_preserves_unicode_and_escapes() {
        let encoded = encode_question_reply("question-id", "선택하세요", "  직접 \"입력\"\n두 번째 줄  ");
        let body = encoded.strip_prefix("<send_user_message_question_reply>\n").unwrap()
            .strip_suffix("\n</send_user_message_question_reply>").unwrap();
        let value: Value = serde_json::from_str(body).unwrap();
        assert_eq!(value[0]["questionItemId"], "question-id");
        assert_eq!(value[0]["answer"], "직접 \"입력\"\n두 번째 줄");
    }
}
