//! Bounded macOS process identity for validating a recorded agent PID.
use std::ffi::c_void;
use std::mem::{size_of, MaybeUninit};

#[repr(C)]
struct ProcBsdInfo {
    flags: u32, status: u32, xstatus: u32, pid: u32, ppid: u32,
    uid: u32, gid: u32, ruid: u32, rgid: u32, svuid: u32, svgid: u32, reserved: u32,
    comm: [u8; 16], name: [u8; 32], nfiles: u32, pgid: u32, jobc: u32,
    tty_device: u32, tty_pgid: u32, nice: i32, start_sec: u64, start_usec: u64,
}

extern "C" {
    fn proc_pidinfo(pid: i32, flavor: i32, arg: u64, buffer: *mut c_void, size: i32) -> i32;
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct ProcessIdentity {
    pub uid: u32,
    pub name: String,
    pub start_sec: u64,
    pub start_usec: u64,
}

fn identity_from_info(pid: u32, info: &ProcBsdInfo) -> Option<ProcessIdentity> {
    if pid <= 1 || info.pid != pid || info.start_sec == 0 || info.start_usec >= 1_000_000 { return None; }
    let end = info.comm.iter().position(|byte| *byte == 0).unwrap_or(info.comm.len());
    let name = std::str::from_utf8(&info.comm[..end]).ok()?;
    if name.is_empty() { return None; }
    Some(ProcessIdentity { uid: info.uid, name: name.to_owned(), start_sec: info.start_sec, start_usec: info.start_usec })
}

fn bsd_info(pid: u32) -> Option<ProcBsdInfo> {
    let pid_arg = i32::try_from(pid).ok().filter(|value| *value > 1)?;
    let mut info = MaybeUninit::<ProcBsdInfo>::uninit();
    let length = size_of::<ProcBsdInfo>();
    let received = unsafe { proc_pidinfo(pid_arg, 3, 0, info.as_mut_ptr().cast(), length as i32) };
    if received != length as i32 { return None; }
    let info = unsafe { info.assume_init() };
    (info.pid == pid).then_some(info)
}

pub(crate) fn process_identity(pid: u32) -> Option<ProcessIdentity> {
    identity_from_info(pid, &bsd_info(pid)?)
}

pub(crate) fn process_parent(pid: u32) -> Option<u32> {
    Some(bsd_info(pid)?.ppid)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn identity_rejects_wrong_process_or_invalid_start_time() {
        assert_eq!(size_of::<ProcBsdInfo>(), 136);
        let mut info: ProcBsdInfo = unsafe { std::mem::zeroed() };
        info.pid = 42; info.uid = 501; info.start_sec = 100; info.start_usec = 3;
        info.comm[..6].copy_from_slice(b"claude");
        assert_eq!(identity_from_info(42, &info).unwrap().name, "claude");
        assert!(identity_from_info(43, &info).is_none());
        info.start_usec = 1_000_000;
        assert!(identity_from_info(42, &info).is_none());
        info.start_usec = 0; info.start_sec = 0;
        assert!(identity_from_info(42, &info).is_none());
    }
}
