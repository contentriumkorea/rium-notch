//! Opt-in stdio transport for a future Desktop App Server wrapper. No setup or
//! process is started until the caller explicitly invokes `desktop-bridge`.
use crate::agent_approval::Decision;
use crate::desktop_bridge::DesktopBridge;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::fs::{self, DirBuilder, File, OpenOptions};
use std::io::{self, BufRead, BufReader, Read, Write};
use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt};
use std::os::unix::io::AsRawFd;
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{mpsc, Arc};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

extern "C" { fn geteuid() -> u32; fn getpeereid(fd: i32, uid: *mut u32, gid: *mut u32) -> i32; }
const FRAME_LIMIT: u64 = 16 * 1024 * 1024;
const CONTROL_LIMIT: u64 = 65_536;
const CONTROL_RESPONSE_LIMIT: usize = 2_000_000;

enum Event { Desktop(Vec<u8>), Server(Vec<u8>), DesktopEnd, ServerEnd, Failure, Control(UnixStream, Value) }

struct FollowupPending {
    stream: UnixStream,
    session: String,
    workspace: PathBuf,
    text: String,
    question_id: Option<String>,
    expected_turn: Option<String>,
    sent: bool,
    metadata: Option<Value>,
    deadline: Instant,
}

fn read_frames<R: Read>(source: R, tx: mpsc::SyncSender<Event>, desktop: bool) {
    let mut reader = BufReader::new(source);
    loop {
        let mut frame = Vec::new();
        match (&mut reader).take(FRAME_LIMIT + 2).read_until(b'\n', &mut frame) {
            Ok(0) => { let _ = tx.send(if desktop { Event::DesktopEnd } else { Event::ServerEnd }); return; }
            Ok(_) => {
                if frame.len() as u64 > FRAME_LIMIT + 1 || (frame.len() as u64 == FRAME_LIMIT + 1 && frame.last() != Some(&b'\n')) {
                    let _ = tx.send(Event::Failure); return;
                }
                if frame.last() == Some(&b'\n') { frame.pop(); }
                if tx.send(if desktop { Event::Desktop(frame) } else { Event::Server(frame) }).is_err() { return; }
            }
            Err(_) => { let _ = tx.send(Event::Failure); return; }
        }
    }
}

fn random_token() -> Option<String> {
    let mut bytes = [0u8; 16];
    File::open("/dev/urandom").ok()?.read_exact(&mut bytes).ok()?;
    Some(bytes.iter().map(|byte| format!("{byte:02x}")).collect())
}
fn peer_is_owner(stream: &UnixStream) -> bool {
    let (mut uid, mut gid) = (0, 0);
    unsafe { getpeereid(stream.as_raw_fd(), &mut uid, &mut gid) == 0 && uid == geteuid() }
}

fn configure_control_stream(stream: &UnixStream) -> io::Result<()> {
    // Accepted sockets can inherit the listener's nonblocking mode on macOS.
    stream.set_nonblocking(false)?;
    stream.set_read_timeout(Some(Duration::from_millis(250)))?;
    stream.set_write_timeout(Some(Duration::from_millis(250)))
}

struct Endpoint { directory: PathBuf, socket: PathBuf, record: PathBuf, token: String, created: u64, running: Arc<AtomicBool> }
impl Drop for Endpoint {
    fn drop(&mut self) {
        self.running.store(false, Ordering::Relaxed);
        let _ = fs::remove_file(&self.record);
        let _ = fs::remove_file(&self.socket);
        let _ = fs::remove_dir(&self.directory);
    }
}
impl Endpoint {
    fn start(tx: mpsc::SyncSender<Event>) -> Option<Self> {
        let token = random_token()?;
        let root = crate::agent_hook::registry()?;
        let directory = PathBuf::from(format!("/tmp/rium-desktop-{token}"));
        let created = SystemTime::now().duration_since(UNIX_EPOCH).ok()?.as_millis().min(u64::MAX as u128) as u64;
        DirBuilder::new().mode(0o700).create(&directory).ok()?;
        let running = Arc::new(AtomicBool::new(true));
        let endpoint = Self { socket: directory.join("socket"), record: root.join(format!("desktop-{token}.json")),
            directory, token: token.clone(), created, running: running.clone() };
        let listener = UnixListener::bind(&endpoint.socket).ok()?;
        listener.set_nonblocking(true).ok()?;
        let mut record = OpenOptions::new().write(true).create_new(true).mode(0o600).open(&endpoint.record).ok()?;
        writeln!(record, "{}", json!({"token":token,"pid":std::process::id(),"createdAt":created,"revision":0})).ok()?;
        drop(record);
        thread::spawn(move || {
            while running.load(Ordering::Relaxed) {
                let (stream, _) = match listener.accept() {
                    Ok(connection) => connection,
                    Err(error) if error.kind() == io::ErrorKind::WouldBlock => { thread::sleep(Duration::from_millis(50)); continue; }
                    Err(_) => break,
                };
                if !peer_is_owner(&stream) { continue; }
                if configure_control_stream(&stream).is_err() { continue; }
                let mut bytes = Vec::new();
                let read = BufReader::new(&stream).take(CONTROL_LIMIT + 1).read_until(b'\n', &mut bytes);
                if read.is_err() || bytes.len() as u64 > CONTROL_LIMIT || bytes.last() != Some(&b'\n') { continue; }
                let Ok(value) = serde_json::from_slice::<Value>(&bytes) else { continue; };
                if value.get("token").and_then(Value::as_str) != Some(token.as_str()) { continue; }
                if tx.send(Event::Control(stream, value)).is_err() { break; }
            }
        });
        Some(endpoint)
    }

    fn publish_revision(&self, revision: u64) -> Option<()> {
        let temporary = self.record.with_file_name(format!(".desktop-{}-{revision}.tmp", self.token));
        let mut file = OpenOptions::new().write(true).create_new(true).mode(0o600).open(&temporary).ok()?;
        if writeln!(file, "{}", json!({"token":self.token,"pid":std::process::id(),"createdAt":self.created,"revision":revision})).is_err() {
            let _ = fs::remove_file(&temporary); return None;
        }
        drop(file);
        if fs::rename(&temporary, &self.record).is_err() { let _ = fs::remove_file(&temporary); return None; }
        Some(())
    }
}

fn write_line(output: &mut impl Write, bytes: &[u8]) -> io::Result<()> {
    output.write_all(bytes)?;
    output.write_all(b"\n")?;
    output.flush()
}

fn send_control(stream: &mut UnixStream, value: &Value) {
    if let Ok(bytes) = serde_json::to_vec(value) { if bytes.len() <= CONTROL_RESPONSE_LIMIT { let _ = write_line(stream, &bytes); } }
}

fn followup_request(session: &str, workspace: &Path, thread: &Value, text: &str) -> Result<Value, &'static str> {
    let cwd = thread.get("cwd").and_then(Value::as_str).and_then(|path| fs::canonicalize(path).ok());
    if thread.get("id").and_then(Value::as_str) != Some(session)
        || fs::canonicalize(workspace).ok() != cwd || cwd.is_none() {
        return Err("대화와 작업 폴더가 일치하지 않습니다");
    }
    let text = text.trim();
    if text.is_empty() || text.len() > 20_000 { return Err("메시지를 확인할 수 없습니다"); }
    let input = json!([{"type":"text","text":text,"text_elements":[]}]);
    match crate::agent_control::followup_turn(thread)? {
        Some(turn) => Ok(json!({"method":"turn/steer","params":{"threadId":session,"expectedTurnId":turn,"input":input}})),
        None => Ok(json!({"method":"turn/start","params":{"threadId":session,"input":input}})),
    }
}

#[cfg(test)]
fn question_already_answered(thread: &Value, question_id: &str) -> bool {
    thread.get("turns").and_then(Value::as_array).into_iter().flatten()
        .flat_map(|turn| turn.get("items").and_then(Value::as_array).into_iter().flatten())
        .flat_map(|item| match item.get("type").and_then(Value::as_str) {
            Some("userMessage") => item.get("content").and_then(Value::as_array),
            Some("steeringUserMessage") if item.get("status").and_then(Value::as_str) == Some("accepted") => item.get("input").and_then(Value::as_array),
            _ => None,
        }.into_iter().flatten())
        .filter_map(|part| part.get("text").and_then(Value::as_str))
        .filter_map(|text| text.trim().strip_prefix("<send_user_message_question_reply>"))
        .filter_map(|text| text.split_once("</send_user_message_question_reply>").map(|(body, _)| body))
        .filter_map(|body| serde_json::from_str::<Value>(body.trim()).ok())
        .any(|replies| replies.as_array().is_some_and(|items| items.iter().any(|item| item.get("questionItemId").and_then(Value::as_str) == Some(question_id))))
}

fn control(bridge: &mut DesktopBridge, message: &Value, now: u64, output: Option<&mut std::process::ChildStdin>) -> Value {
    let action = message.get("action").and_then(Value::as_str).unwrap_or("");
    if action == "sessions" { return json!({"status":"ok","sessions":bridge.sessions()}); }
    if action == "activity" { return json!({"status":"ok","sessions":bridge.activity(now)}); }
    let session = message.get("sessionId").and_then(Value::as_str).unwrap_or("");
    let workspace = Path::new(message.get("workspace").and_then(Value::as_str).unwrap_or(""));
    if action == "previews" {
        let previews: Vec<Value> = bridge.previews(session, workspace, now).into_iter().take(32).collect();
        return json!({"status":"ok","previews":previews});
    }
    let Some(output) = output else { return json!({"status":"unavailable"}); };
    let token = message.get("requestToken").and_then(Value::as_str).unwrap_or("");
    let turn = message.get("turnId").and_then(Value::as_str).unwrap_or("");
    let shown = &message["shown"];
    let response = match action {
        "approval" => match message.get("decision").and_then(Value::as_str) {
            Some("allow") => bridge.claim_approval(session, workspace, token, turn, now, shown, Decision::Allow),
            Some("deny") => bridge.claim_approval(session, workspace, token, turn, now, shown, Decision::Deny),
            _ => None,
        },
        "question" => bridge.claim_question(session, workspace, token, turn, now, shown, &message["answers"]),
        _ => None,
    };
    let Some(response) = response else { return json!({"status":"not_pending"}); };
    let Ok(bytes) = serde_json::to_vec(&response) else { return json!({"status":"unknown"}); };
    if write_line(output, &bytes).is_ok() { json!({"status":"submitted"}) } else { json!({"status":"unknown"}) }
}

/// Starts only the executable and arguments supplied by the outer client. An
/// unavailable private endpoint leaves the normal Desktop path operational.
pub fn run(command: &[String], shutdown: &AtomicBool) -> Result<i32, &'static str> {
    run_with_official_cli(command, shutdown, None)
}

pub fn run_with_official_cli(command: &[String], shutdown: &AtomicBool, official: Option<&Path>) -> Result<i32, &'static str> {
    if command.is_empty() || command[0].is_empty() { return Err("missing_command"); }
    let mut bridge = DesktopBridge::new().ok_or("random_unavailable")?;
    let mut process = Command::new(&command[0]);
    process.args(&command[1..]).stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::inherit());
    if let Some(official) = official { process.env("CODEX_CLI_PATH", official); }
    let mut child = process.spawn().map_err(|_| "engine_start_failed")?;
    let mut engine_in = child.stdin.take();
    let Some(engine_out) = child.stdout.take() else { let _ = child.kill(); let _ = child.wait(); return Err("engine_output_unavailable"); };
    let (tx, rx) = mpsc::sync_channel(8);
    let endpoint = Endpoint::start(tx.clone());
    let client_tx = tx.clone();
    thread::spawn(move || read_frames(io::stdin(), client_tx, true));
    thread::spawn(move || read_frames(engine_out, tx, false));
    let started = Instant::now();
    let mut desktop_out = io::stdout().lock();
    let mut failed = false;
    let mut published_revision = 0;
    let control_prefix = format!("rium-control-{}-", random_token().ok_or("random_unavailable")?);
    let mut control_sequence = 0u64;
    let mut pending: HashMap<String, FollowupPending> = HashMap::new();
    while !shutdown.load(Ordering::Relaxed) {
        let expired: Vec<String> = pending.iter().filter(|(_, request)| Instant::now() >= request.deadline).map(|(id, _)| id.clone()).collect();
        for id in expired {
            if let Some(mut request) = pending.remove(&id) {
                send_control(&mut request.stream, &json!({"status":if request.sent {"unknown"} else {"unavailable"}}));
            }
        }
        let event = match rx.recv_timeout(Duration::from_millis(100)) {
            Ok(event) => event,
            Err(mpsc::RecvTimeoutError::Timeout) => continue,
            Err(mpsc::RecvTimeoutError::Disconnected) => { failed = true; break; }
        };
        let now = started.elapsed().as_millis().min(u64::MAX as u128) as u64;
        match event {
            Event::Desktop(line) => match bridge.from_desktop(&line) {
                Ok(Some(output)) => if engine_in.as_mut().map_or(true, |writer| write_line(writer, &output).is_err()) { failed = true; break; },
                Ok(None) => {},
                Err(_) => {
                    let id = serde_json::from_slice::<Value>(&line).ok().and_then(|value| value.get("id").cloned());
                    if let Some(id) = id {
                        let error = json!({"id":id,"error":{"code":-32001,"message":"Rium bridge unavailable"}});
                        if write_line(&mut desktop_out, error.to_string().as_bytes()).is_err() { failed = true; break; }
                    } else { failed = true; break; }
                }
            },
            Event::Server(line) if serde_json::from_slice::<Value>(&line).ok().and_then(|v| v.get("id").and_then(Value::as_str).map(|id| id.starts_with(&control_prefix))).unwrap_or(false) => {
                let Ok(message) = serde_json::from_slice::<Value>(&line) else { continue; };
                if message.get("method").is_some() { continue; }
                let Some(id) = message.get("id").and_then(Value::as_str) else { continue; };
                let Some(mut request) = pending.remove(id) else { continue; };
                if request.sent {
                    let turn = message.pointer("/result/turnId").or_else(|| message.pointer("/result/turn/id")).and_then(Value::as_str);
                    let accepted = message.get("error").is_none() && turn.is_some_and(|id| !id.is_empty() && request.expected_turn.as_deref().is_none_or(|expected| expected == id));
                    send_control(&mut request.stream, &json!({"status":if accepted {"accepted"} else {"unknown"}}));
                } else if request.metadata.is_none() {
                    let Some(thread) = message.pointer("/result/thread").cloned() else {
                        send_control(&mut request.stream, &json!({"status":"unavailable"})); continue;
                    };
                    if request.question_id.is_some() {
                        // A metadata-only read cannot establish whether a question was already answered.
                        send_control(&mut request.stream, &json!({"status":"unavailable"})); continue;
                    }
                    request.metadata = Some(thread);
                    control_sequence = control_sequence.wrapping_add(1);
                    let next_id = format!("{control_prefix}{control_sequence}");
                    let list = json!({"id":next_id,"method":"thread/turns/list","params":{
                        "threadId":request.session,"limit":2,"sortDirection":"desc","itemsView":"notLoaded"}});
                    let written = serde_json::to_vec(&list).ok().and_then(|bytes| engine_in.as_mut().and_then(|output| write_line(output, &bytes).ok())).is_some();
                    if written { pending.insert(next_id, request); }
                    else { send_control(&mut request.stream, &json!({"status":"unavailable"})); }
                } else {
                    let turns = message.pointer("/result/data").and_then(Value::as_array);
                    let next = turns.and_then(|turns| {
                        let mut thread = request.metadata.take()?;
                        thread["turns"] = json!(turns);
                        followup_request(&request.session, &request.workspace, &thread, &request.text).ok()
                    });
                    let Some(mut next) = next.filter(|_| bridge.matches_thread(&request.session, &request.workspace)) else {
                        send_control(&mut request.stream, &json!({"status":"unavailable"})); continue;
                    };
                    request.expected_turn = next.pointer("/params/expectedTurnId").and_then(Value::as_str).map(str::to_owned);
                    control_sequence = control_sequence.wrapping_add(1);
                    let next_id = format!("{control_prefix}{control_sequence}");
                    next["id"] = json!(next_id);
                    request.sent = true;
                    let written = serde_json::to_vec(&next).ok().and_then(|bytes| engine_in.as_mut().and_then(|output| write_line(output, &bytes).ok())).is_some();
                    if written { pending.insert(next_id, request); }
                    else { send_control(&mut request.stream, &json!({"status":"unknown"})); }
                }
            }
            Event::Server(line) => match bridge.from_server(&line, now) {
                Ok(Some(output)) => if write_line(&mut desktop_out, &output).is_err() { failed = true; break; },
                Ok(None) => {},
                Err(_) => { failed = true; break; }
            },
            Event::Control(mut stream, request) => {
                if request.get("action").and_then(Value::as_str) == Some("followup") {
                    let session = request.get("sessionId").and_then(Value::as_str).unwrap_or("");
                    let workspace = Path::new(request.get("workspace").and_then(Value::as_str).unwrap_or(""));
                    let text = request.get("text").and_then(Value::as_str).unwrap_or("").trim();
                    let question_id = request.get("questionId").and_then(Value::as_str).filter(|id| !id.is_empty() && id.len() <= 230).map(str::to_owned);
                    if pending.len() >= 16 || !bridge.matches_thread(session, workspace) || text.is_empty() || text.len() > 20_000 {
                        send_control(&mut stream, &json!({"status":"unavailable"})); continue;
                    }
                    control_sequence = control_sequence.wrapping_add(1);
                    let id = format!("{control_prefix}{control_sequence}");
                    let read = json!({"id":id,"method":"thread/read","params":{"threadId":session,"includeTurns":false}});
                    let written = serde_json::to_vec(&read).ok().and_then(|bytes| engine_in.as_mut().and_then(|output| write_line(output, &bytes).ok())).is_some();
                    if written {
                        pending.insert(id, FollowupPending { stream, session:session.to_owned(), workspace:workspace.to_path_buf(), text:text.to_owned(), question_id,
                            expected_turn:None, sent:false, metadata:None, deadline:Instant::now()+Duration::from_secs(6) });
                    } else { send_control(&mut stream, &json!({"status":"unavailable"})); }
                } else {
                    let response = control(&mut bridge, &request, now, engine_in.as_mut());
                    send_control(&mut stream, &response);
                }
            }
            Event::DesktopEnd => { engine_in.take(); }
            Event::ServerEnd => break,
            Event::Failure => { failed = true; break; }
        }
        if bridge.revision() != published_revision {
            if endpoint.as_ref().is_some_and(|endpoint| endpoint.publish_revision(bridge.revision()).is_some()) {
                published_revision = bridge.revision();
            }
        }
    }
    drop(engine_in);
    if shutdown.load(Ordering::Relaxed) || failed { let _ = child.kill(); }
    let grace = Instant::now() + Duration::from_secs(1);
    let status = loop {
        match child.try_wait() {
            Ok(Some(status)) => break status,
            Ok(None) if Instant::now() < grace => thread::sleep(Duration::from_millis(20)),
            _ => { let _ = child.kill(); break child.wait().map_err(|_| "engine_wait_failed")?; }
        }
    };
    use std::os::unix::process::ExitStatusExt;
    Ok(status.code().unwrap_or_else(|| 128 + status.signal().unwrap_or(1)))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn control_response_exceeding_socket_buffer_is_complete() {
        let (mut sender, receiver) = UnixStream::pair().unwrap();
        sender.set_nonblocking(true).unwrap();
        configure_control_stream(&sender).unwrap();
        let payload = "x".repeat(128 * 1024);
        let expected = payload.clone();
        let writer = thread::spawn(move || send_control(&mut sender, &json!({"sessions":payload})));
        // Let the sender fill the socket before the reader starts: a
        // nonblocking sender would fail and silently leave a partial frame.
        thread::sleep(Duration::from_millis(50));
        let mut received = String::new();
        BufReader::new(receiver).read_line(&mut received).unwrap();
        writer.join().unwrap();
        let response: Value = serde_json::from_str(&received).unwrap();
        assert_eq!(response["sessions"], expected);
    }

    #[test]
    fn followup_uses_the_owner_thread_and_never_an_ambiguous_turn() {
        let cwd = fs::canonicalize(std::env::temp_dir()).unwrap();
        let active = json!({"id":"s","cwd":cwd,"status":{"type":"active"},
            "turns":[{"id":"turn-1","status":"inProgress"}]});
        let request = followup_request("s", &cwd, &active, "hello").unwrap();
        assert_eq!(request["method"], "turn/steer");
        assert_eq!(request["params"]["expectedTurnId"], "turn-1");
        assert_eq!(request["params"]["input"][0]["text"], "hello");
        assert!(followup_request("other", &cwd, &active, "hello").is_err());
        let ambiguous = json!({"id":"s","cwd":cwd,"status":{"type":"active"},
            "turns":[{"id":"a","status":"inProgress"},{"id":"b","status":"inProgress"}]});
        assert!(followup_request("s", &cwd, &ambiguous, "hello").is_err());
        let idle = json!({"id":"s","cwd":cwd,"status":{"type":"idle"},"turns":[]});
        assert_eq!(followup_request("s", &cwd, &idle, "hello").unwrap()["method"], "turn/start");
    }

    #[test]
    fn question_reply_is_not_sent_twice() {
        let text = crate::agent_control::encode_question_reply("q", "질문", "네");
        let thread = json!({"turns":[{"items":[{"type":"userMessage","content":[{"type":"text","text":text}]}]}]});
        assert!(question_already_answered(&thread, "q"));
        assert!(!question_already_answered(&thread, "other"));
    }

    #[test]
    fn framing_preserves_order_and_a_final_unterminated_frame() {
        let (tx, rx) = mpsc::sync_channel(8);
        read_frames(io::Cursor::new(b"first\nsecond"), tx, true);
        match rx.recv().unwrap() { Event::Desktop(frame) => assert_eq!(frame, b"first"), _ => panic!("expected first frame") }
        match rx.recv().unwrap() { Event::Desktop(frame) => assert_eq!(frame, b"second"), _ => panic!("expected final frame") }
        assert!(matches!(rx.recv().unwrap(), Event::DesktopEnd));
    }
}
