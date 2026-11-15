//! Read-only output-volume sampling through Core Audio.
use std::ffi::c_void;
use std::mem::size_of;
#[repr(C)]
struct Address { selector: u32, scope: u32, element: u32 }
#[link(name = "CoreAudio", kind = "framework")]
extern "C" {
    fn AudioObjectGetPropertyData(object: u32, address: *const Address, qualifier_size: u32, qualifier: *const c_void, size: *mut u32, data: *mut c_void) -> i32;
}
fn fourcc(value: &[u8; 4]) -> u32 { u32::from_be_bytes(*value) }
unsafe fn get<T: Copy + Default>(object: u32, selector: &[u8; 4], scope: &[u8; 4], element: u32) -> Option<T> {
    let address = Address { selector: fourcc(selector), scope: fourcc(scope), element };
    let mut value = T::default(); let mut length = size_of::<T>() as u32;
    if AudioObjectGetPropertyData(object, &address, 0, std::ptr::null(), &mut length, (&mut value as *mut T).cast()) == 0 && length == size_of::<T>() as u32 { Some(value) } else { None }
}
/// Availability flags: volume=1, mute=2. Outputs -1 on invalid pointers.
#[no_mangle]
pub unsafe extern "C" fn rium_output_volume(volume: *mut f64, muted: *mut i32) -> i32 {
    if volume.is_null() || muted.is_null() { return -1; }
    *volume = -1.0; *muted = 0;
    let Some(device) = get::<u32>(1, b"dOut", b"glob", 0).filter(|id| *id != 0) else { return 0; };
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
