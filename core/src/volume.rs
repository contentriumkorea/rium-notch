//! Read-only output sampling through Core Audio.
use std::ffi::c_void;
use std::mem::size_of;
#[repr(C)]
struct Address { selector: u32, scope: u32, element: u32 }
#[link(name = "CoreAudio", kind = "framework")]
extern "C" {
    fn AudioObjectGetPropertyDataSize(object: u32, address: *const Address, qualifier_size: u32, qualifier: *const c_void, size: *mut u32) -> i32;
    fn AudioObjectGetPropertyData(object: u32, address: *const Address, qualifier_size: u32, qualifier: *const c_void, size: *mut u32, data: *mut c_void) -> i32;
}
fn fourcc(value: &[u8; 4]) -> u32 { u32::from_be_bytes(*value) }
unsafe fn get<T: Copy + Default>(object: u32, selector: &[u8; 4], scope: &[u8; 4], element: u32) -> Option<T> {
    let address = Address { selector: fourcc(selector), scope: fourcc(scope), element };
    let mut value = T::default(); let mut length = size_of::<T>() as u32;
    if AudioObjectGetPropertyData(object, &address, 0, std::ptr::null(), &mut length, (&mut value as *mut T).cast()) == 0 && length == size_of::<T>() as u32 { Some(value) } else { None }
}
pub(crate) fn possibly_emitting_processes() -> Option<Vec<(u32, Option<bool>)>> {
    let address = Address { selector: fourcc(b"prs#"), scope: fourcc(b"glob"), element: 0 };
    let mut size = 0;
    let null = std::ptr::null();
    if unsafe { AudioObjectGetPropertyDataSize(1, &address, 0, null, &mut size) } != 0 {
        return None;
    }
    let stride = size_of::<u32>() as u32;
    if size % stride != 0 || size / stride > 4096 { return None; }
    if size == 0 { return Some(Vec::new()); }
    let mut objects = vec![0u32; (size / stride) as usize];
    let capacity = size;
    if unsafe { AudioObjectGetPropertyData(1, &address, 0, null, &mut size, objects.as_mut_ptr().cast()) } != 0
        || size > capacity || size % stride != 0 {
        return None;
    }
    let mut processes = Vec::new();
    for object in objects.into_iter().take((size / stride) as usize) {
        let running = unsafe { get::<u32>(object, b"piro", b"glob", 0) }.map(|value| value != 0);
        if running == Some(false) { continue; }
        let pid = unsafe { get::<i32>(object, b"ppid", b"glob", 0) }?;
        if pid > 1 { processes.push((pid as u32, running)); }
    }
    Some(processes)
}

/// Availability flags: volume=1, mute=2. Outputs -1 on invalid pointers.
#[no_mangle]
pub unsafe extern "C" fn rium_output_volume(volume: *mut f64, muted: *mut i32) -> i32 {
    let mut device = 0;
    rium_output_volume_with_device(volume, muted, &mut device)
}

#[no_mangle]
pub unsafe extern "C" fn rium_output_volume_with_device(volume: *mut f64, muted: *mut i32, output_device: *mut u32) -> i32 {
    if volume.is_null() || muted.is_null() || output_device.is_null() { return -1; }
    *volume = -1.0; *muted = 0; *output_device = 0;
    let Some(device) = get::<u32>(1, b"dOut", b"glob", 0).filter(|id| *id != 0) else { return 0; };
    *output_device = device;
    let mut flags = 0;
    let scalar = get::<f32>(device, b"volm", b"outp", 0).or_else(|| {
        let left = get::<f32>(device, b"volm", b"outp", 1);
        let right = get::<f32>(device, b"volm", b"outp", 2);
        match (left,right) { (Some(l),Some(r)) => Some((l+r)/2.0), (Some(l),None) => Some(l), (None,Some(r)) => Some(r), _ => None }
    });
    if let Some(value) = scalar.filter(|n| n.is_finite() && (0.0..=1.0).contains(n)) { *volume = f64::from(value) * 100.0; flags |= 1; }
    if let Some(value) = get::<u32>(device, b"mute", b"outp", 0) { *muted = i32::from(value != 0); flags |= 2; }
    flags
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn volume_rejects_missing_output_pointers() {
        let mut volume = 0.0; let mut muted = 0; let mut device = 0;
        unsafe {
            assert_eq!(rium_output_volume_with_device(std::ptr::null_mut(), &mut muted, &mut device), -1);
            assert_eq!(rium_output_volume_with_device(&mut volume, std::ptr::null_mut(), &mut device), -1);
            assert_eq!(rium_output_volume_with_device(&mut volume, &mut muted, std::ptr::null_mut()), -1);
        }
    }
}
