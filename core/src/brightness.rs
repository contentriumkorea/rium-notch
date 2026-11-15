//! Read-only display brightness through the same optional system service used
//! by the reference app. The interface is private and may be unavailable.
use std::ffi::{c_char, c_int, c_void};
use std::sync::OnceLock;

type GetBrightness = unsafe extern "C" fn(u32, *mut f32) -> i32;
extern "C" {
    fn dlopen(path: *const c_char, mode: c_int) -> *mut c_void;
    fn dlsym(handle: *mut c_void, symbol: *const c_char) -> *mut c_void;
}
static GETTER: OnceLock<Option<GetBrightness>> = OnceLock::new();
fn getter() -> Option<GetBrightness> {
    *GETTER.get_or_init(|| unsafe {
        let library = dlopen(b"/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices\0".as_ptr().cast(), 1);
        if library.is_null() { return None; }
        let symbol = dlsym(library, b"DisplayServicesGetBrightness\0".as_ptr().cast());
        if symbol.is_null() { None } else { Some(std::mem::transmute::<*mut c_void, GetBrightness>(symbol)) }
    })
}
/// Returns 1 when read, 0 when unavailable, -1 for invalid input.
#[no_mangle]
pub unsafe extern "C" fn rium_display_brightness(display: u32, result: *mut f64) -> i32 {
    if display == 0 || result.is_null() { return -1; }
    *result = -1.0;
    let Some(get) = getter() else { return 0; };
    let mut value = -1.0f32;
    if get(display, &mut value) != 0 || !value.is_finite() || !(0.0..=1.0).contains(&value) { return 0; }
    *result = f64::from(value) * 100.0;
    1
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn invalid_inputs_fail_without_calling_system_service() {
        let mut result = 0.0;
        assert_eq!(unsafe { rium_display_brightness(0, &mut result) }, -1);
        assert_eq!(unsafe { rium_display_brightness(1, std::ptr::null_mut()) }, -1);
    }
}
