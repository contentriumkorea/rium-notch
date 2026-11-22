use std::ffi::{c_char, c_int, c_uint, c_void};
use std::mem::{size_of, zeroed};
mod timer;
mod clipboard;
pub mod weather;
pub mod media;
pub mod lyrics;
pub mod agents;
pub mod agent_control;
pub mod assistant_stream;
pub mod assistant_transport;
pub mod assistant_history;
pub mod agent_approval;
pub mod desktop_bridge;
pub mod desktop_client;
pub mod desktop_launcher;
pub mod desktop_schema;
pub mod desktop_qualification;
pub mod desktop_setup;
pub mod desktop_setup_files;
pub mod desktop_activation;
pub mod desktop_transport;
pub mod claude_permission;
pub mod agent_hook;
mod process_identity;
pub mod claude_control;
pub mod notch_animation;
pub mod home_texture;
pub mod home_calendar;
pub mod audio_spectrum;
pub mod system_notifications;
mod power;
pub mod interview;
pub mod interview_deepgram;
pub mod interview_llm;
pub mod voice_command;
mod dictation;
pub mod voice_approval;
mod shelf;
mod airdrop;
mod screenshot;
mod volume;
mod brightness;
mod teleprompter;
mod notes;
pub use teleprompter::{rium_teleprompter_save, rium_teleprompter_load, rium_teleprompter_free, rium_teleprompter_chapters, rium_teleprompter_free_string};
pub use volume::{rium_output_volume, rium_output_volume_with_device};
pub use brightness::{rium_display_brightness, rium_observe_display_brightness};
pub use lyrics::{rium_lyrics_parse, rium_lyrics_free};
pub use shelf::{rium_shelf_add, rium_shelf_add_ordered, rium_shelf_remove, rium_shelf_json, rium_shelf_free};
pub use airdrop::{rium_is_airdrop_file, rium_airdrop_receiving_fraction, rium_airdrop_pending_decision, rium_airdrop_preview_progress, rium_airdrop_receive_glyph, rium_airdrop_send_glyph, rium_airdrop_send_result};
pub use timer::{rium_timer_start, rium_timer_pause, rium_timer_resume, rium_timer_reset, rium_timer_restore, rium_timer_status, rium_timer_running_seconds, rium_timer_remaining_seconds, rium_timer_fraction};
pub use clipboard::{rium_clipboard_add_record, rium_clipboard_json, rium_clipboard_copy_data, rium_clipboard_free_data, rium_clipboard_free, rium_clipboard_clear, rium_clipboard_remove, rium_clipboard_set_pinned, rium_clipboard_save, rium_clipboard_save_after_clear, rium_clipboard_load};

#[repr(C)]
struct VmInfo {
    free: u32, active: u32, inactive: u32, wired: u32,
    zero_fill: u64, reactivations: u64, pageins: u64, pageouts: u64,
    faults: u64, cow_faults: u64, lookups: u64, hits: u64, purges: u64,
    purgeable: u32, speculative: u32,
    decompressions: u64, compressions: u64, swapins: u64, swapouts: u64,
    compressor: u32, throttled: u32, external: u32, internal: u32,
    total_uncompressed: u64,
}
#[repr(C)]
struct Swap { total: u64, available: u64, used: u64, page_size: u32, encrypted: u32 }
extern "C" {
    fn mach_host_self() -> c_uint;
    static mach_task_self_: c_uint;
    fn mach_port_deallocate(task: c_uint, name: c_uint) -> c_int;
    fn host_statistics(host: c_uint, flavor: c_int, info: *mut c_int, count: *mut c_uint) -> c_int;
    fn host_statistics64(host: c_uint, flavor: c_int, info: *mut c_int, count: *mut c_uint) -> c_int;
    fn sysctlbyname(name: *const c_char, old: *mut c_void, oldlen: *mut usize, new: *mut c_void, newlen: usize) -> c_int;
    fn getpagesize() -> c_int;
}
// The UI may sample from more than one queue. Keep the CPU baseline synchronized.
static PREVIOUS: std::sync::Mutex<Option<[u32; 4]>> = std::sync::Mutex::new(None);

const CPU_AVAILABLE: c_int = 1;
const MEMORY_AVAILABLE: c_int = 2;
const SWAP_AVAILABLE: c_int = 4;

struct Samples {
    ticks: Option<[u32; 4]>,
    memory: Option<(u64, u64)>,
    swap: Option<u64>,
}

fn values(samples: Samples, previous: &mut Option<[u32; 4]>) -> (c_int, f64, u64, u64, u64) {
    let mut flags = 0;
    let mut cpu = -1.0;
    let (mut used, mut total, mut swap) = (0, 0, 0);
    if let Some(ticks) = samples.ticks {
        flags |= CPU_AVAILABLE;
        if let Some(prev) = *previous {
            let delta = [ticks[0].wrapping_sub(prev[0]), ticks[1].wrapping_sub(prev[1]), ticks[2].wrapping_sub(prev[2]), ticks[3].wrapping_sub(prev[3])];
            let sum: u64 = delta.iter().map(|&n| n as u64).sum();
            if sum != 0 { cpu = 100.0 * (sum - delta[2] as u64) as f64 / sum as f64; }
        }
        *previous = Some(ticks);
    }
    if let Some((current, capacity)) = samples.memory { flags |= MEMORY_AVAILABLE; used = current; total = capacity; }
    if let Some(current) = samples.swap { flags |= SWAP_AVAILABLE; swap = current; }
    (flags, cpu, used, total, swap)
}

/// Returns independent availability bits: CPU=1, RAM=2 and swap=4.
/// A CPU value of -1 means that another tick sample is needed.
#[no_mangle]
pub unsafe extern "C" fn read_metrics_v2(cpu: *mut f64, used: *mut u64, total: *mut u64, swap_used: *mut u64) -> c_int {
    if cpu.is_null() || used.is_null() || total.is_null() || swap_used.is_null() { return -1; }
    let host = mach_host_self();
    let mut ticks = [0u32; 4];
    let mut count = 4;
    let cpu_ok = host_statistics(host, 3, ticks.as_mut_ptr() as *mut c_int, &mut count) == 0 && count >= 4;
    let mut vm: VmInfo = zeroed();
    let mut vm_count = (size_of::<VmInfo>() / 4) as u32;
    let vm_ok = host_statistics64(host, 4, &mut vm as *mut VmInfo as *mut c_int, &mut vm_count) == 0
        && vm_count as usize * 4 >= std::mem::offset_of!(VmInfo, internal) + size_of::<u32>();
    mach_port_deallocate(mach_task_self_, host);
    let mut memory = 0u64;
    let mut len = size_of::<u64>();
    let mem_ok = sysctlbyname(b"hw.memsize\0".as_ptr() as *const c_char, &mut memory as *mut _ as *mut c_void, &mut len, std::ptr::null_mut(), 0) == 0 && len == size_of::<u64>() && memory > 0;
    let mut swap: Swap = zeroed();
    len = size_of::<Swap>();
    let swap_ok = sysctlbyname(b"vm.swapusage\0".as_ptr() as *const c_char, &mut swap as *mut _ as *mut c_void, &mut len, std::ptr::null_mut(), 0) == 0 && len == size_of::<Swap>();
    let pages = (vm.internal as u64).saturating_sub(vm.purgeable as u64) + vm.wired as u64 + vm.compressor as u64;
    let page_size = getpagesize();
    let used_memory = if vm_ok && mem_ok && page_size > 0 { pages.checked_mul(page_size as u64).filter(|&n| n <= memory) } else { None };
    let samples = Samples { ticks: if cpu_ok { Some(ticks) } else { None }, memory: used_memory.map(|n| (n, memory)), swap: if swap_ok { Some(swap.used) } else { None } };
    let mut previous = PREVIOUS.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
    let (flags, new_cpu, new_used, new_total, new_swap) = values(samples, &mut previous);
    *cpu = new_cpu; *used = new_used; *total = new_total; *swap_used = new_swap;
    flags
}

/// Preserve the original prototype's all-or-nothing ABI.
#[no_mangle]
pub unsafe extern "C" fn read_metrics(cpu: *mut f64, used: *mut u64, total: *mut u64, swap_used: *mut u64) -> c_int {
    match read_metrics_v2(cpu, used, total, swap_used) { -1 => -1, 7 => 0, _ => -2 }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn independent_sources_and_cpu_warmup() {
        let mut previous = None;
        let first=values(Samples { ticks:Some([10,20,50,0]),memory:Some((8,16)),swap:None },&mut previous);
        assert_eq!(first,(CPU_AVAILABLE | MEMORY_AVAILABLE,-1.0,8,16,0));
        let second=values(Samples { ticks:Some([20,25,75,0]),memory:None,swap:Some(3) },&mut previous);
        assert_eq!(second,(CPU_AVAILABLE | SWAP_AVAILABLE,37.5,0,0,3));
        let failed=values(Samples { ticks:None,memory:None,swap:Some(0) },&mut previous);
        assert_eq!(failed,(SWAP_AVAILABLE,-1.0,0,0,0));
        assert_eq!(previous,Some([20,25,75,0]));
    }
}
