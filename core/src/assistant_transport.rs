//! Bidirectional stdio connection to a separate Codex app-server process.
use serde_json::Value;
use std::io::{self, BufRead, BufReader, Read, Write};
use std::path::Path;
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, SyncSender};
use std::thread;
use std::time::{Duration, Instant};

const MAX_FRAME: u64 = 2 * 1024 * 1024;
#[derive(Clone, Copy)]
enum Side { Client, Server }
enum Event { Frame(Side, Vec<u8>), End(Side), Invalid }

fn read_frames(source: impl Read, tx: SyncSender<Event>, side: Side) {
    let mut reader = BufReader::new(source);
    loop {
        let mut line = Vec::new();
        match (&mut reader).take(MAX_FRAME + 2).read_until(b'\n', &mut line) {
            Ok(0) => { let _ = tx.send(Event::End(side)); return; }
            Ok(_) => {
                if line.last() == Some(&b'\n') { line.pop(); }
                if line.len() as u64 > MAX_FRAME || !serde_json::from_slice::<Value>(&line).is_ok_and(|value| value.is_object()) {
                    let _ = tx.send(Event::Invalid); return;
                }
                if tx.send(Event::Frame(side, line)).is_err() { return; }
            }
            Err(_) => { let _ = tx.send(Event::Invalid); return; }
        }
    }
}

fn write_frame(output: &mut impl Write, frame: &[u8]) -> io::Result<()> {
    output.write_all(frame)?; output.write_all(b"\n")?; output.flush()
}

/// No request is fabricated or approved by the transport; the client owns the protocol.
pub fn run(binary: &Path, shutdown: &AtomicBool) -> Result<i32, &'static str> {
    let mut child = Command::new(binary).args(["app-server", "--listen", "stdio://"])
        .stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::null())
        .spawn().map_err(|_| "assistant_server_start_failed")?;
    let Some(mut child_in) = child.stdin.take() else { let _ = child.kill(); let _ = child.wait(); return Err("assistant_server_input_unavailable"); };
    let Some(child_out) = child.stdout.take() else { let _ = child.kill(); let _ = child.wait(); return Err("assistant_server_output_unavailable"); };
    let (tx, rx) = mpsc::sync_channel(8);
    let client_tx = tx.clone();
    thread::spawn(move || read_frames(io::stdin(), client_tx, Side::Client));
    thread::spawn(move || read_frames(child_out, tx, Side::Server));
    let mut output = io::stdout().lock();
    let mut error = None;
    while !shutdown.load(Ordering::Relaxed) {
        match rx.recv_timeout(Duration::from_millis(100)) {
            Ok(Event::Frame(Side::Client, frame)) => if write_frame(&mut child_in, &frame).is_err() { error = Some("assistant_server_write_failed"); break; },
            Ok(Event::Frame(Side::Server, frame)) => if write_frame(&mut output, &frame).is_err() { error = Some("assistant_client_write_failed"); break; },
            Ok(Event::End(_)) => break,
            Ok(Event::Invalid) | Err(mpsc::RecvTimeoutError::Disconnected) => { error = Some("assistant_invalid_frame"); break; }
            Err(mpsc::RecvTimeoutError::Timeout) => {}
        }
    }
    drop(child_in);
    if shutdown.load(Ordering::Relaxed) || error.is_some() { let _ = child.kill(); }
    let deadline = Instant::now() + Duration::from_secs(1);
    let status = loop {
        match child.try_wait() {
            Ok(Some(status)) => break status,
            Ok(None) if Instant::now() < deadline => thread::sleep(Duration::from_millis(20)),
            _ => { let _ = child.kill(); break child.wait().map_err(|_| "assistant_server_wait_failed")?; }
        }
    };
    if let Some(error) = error { return Err(error); }
    use std::os::unix::process::ExitStatusExt;
    Ok(status.code().unwrap_or_else(|| 128 + status.signal().unwrap_or(1)))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn frames_preserve_json_and_reject_invalid_or_oversized_input() {
        let (tx, rx) = mpsc::sync_channel(8);
        read_frames(io::Cursor::new(b"{\"method\":\"initialized\"}\n{\"id\":1}"), tx, Side::Client);
        assert!(matches!(rx.recv().unwrap(), Event::Frame(Side::Client, frame) if frame.as_slice() == br#"{"method":"initialized"}"#));
        assert!(matches!(rx.recv().unwrap(), Event::Frame(Side::Client, frame) if frame.as_slice() == br#"{"id":1}"#));
        assert!(matches!(rx.recv().unwrap(), Event::End(Side::Client)));
        let (tx, rx) = mpsc::sync_channel(1);
        read_frames(io::Cursor::new(b"[]\n"), tx, Side::Server);
        assert!(matches!(rx.recv().unwrap(), Event::Invalid));
        let (tx, rx) = mpsc::sync_channel(1);
        read_frames(io::Cursor::new(vec![b'x'; MAX_FRAME as usize + 1]), tx, Side::Client);
        assert!(matches!(rx.recv().unwrap(), Event::Invalid));
    }
}
