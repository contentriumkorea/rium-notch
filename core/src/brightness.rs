//! Read-only display brightness through the same optional system service used
//! by the reference app. The interface is private and may be unavailable.
use std::ffi::{c_char, c_int, c_void};
use std::sync::OnceLock;

type GetBrightness = unsafe extern "C" fn(u32, *mut f32) -> i32;
pub type BrightnessChanged = unsafe extern "C" fn(*const c_void, *mut c_void, *const c_void, *const c_void, *const c_void);
type RegisterBrightness = unsafe extern "C" fn(u32, u32, BrightnessChanged) -> i32;
type UnregisterBrightness = unsafe extern "C" fn(u32, u32) -> i32;
struct DisplayServices {
    get: GetBrightness,
    observers: Option<(RegisterBrightness, UnregisterBrightness)>,
}
extern "C" {
    fn dlopen(path: *const c_char, mode: c_int) -> *mut c_void;
    fn dlsym(handle: *mut c_void, symbol: *const c_char) -> *mut c_void;
}
static SERVICES: OnceLock<Option<DisplayServices>> = OnceLock::new();
fn display_services() -> Option<&'static DisplayServices> {
    SERVICES.get_or_init(|| unsafe {
        let library = dlopen(b"/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices\0".as_ptr().cast(), 1);
        if library.is_null() { return None; }
        let get = dlsym(library, b"DisplayServicesGetBrightness\0".as_ptr().cast());
        if get.is_null() { return None; }
        let register = dlsym(library, b"DisplayServicesRegisterForBrightnessChangeNotifications\0".as_ptr().cast());
        let unregister = dlsym(library, b"DisplayServicesUnregisterForBrightnessChangeNotifications\0".as_ptr().cast());
        let observers = if register.is_null() || unregister.is_null() {
            None
        } else {
            Some((std::mem::transmute::<*mut c_void, RegisterBrightness>(register),
                  std::mem::transmute::<*mut c_void, UnregisterBrightness>(unregister)))
        };
        Some(DisplayServices { get: std::mem::transmute::<*mut c_void, GetBrightness>(get), observers })
    }).as_ref()
}
/// Returns 1 when read, 0 when unavailable, -1 for invalid input.
#[no_mangle]
pub unsafe extern "C" fn rium_display_brightness(display: u32, result: *mut f64) -> i32 {
    if display == 0 || result.is_null() { return -1; }
    *result = -1.0;
    let Some(services) = display_services() else { return 0; };
    let mut value = -1.0f32;
    if (services.get)(display, &mut value) != 0 || !value.is_finite() || !(0.0..=1.0).contains(&value) { return 0; }
    *result = f64::from(value) * 100.0;
    1
}

/// Uses the display ID as the observer token. A null callback removes that observer.
#[no_mangle]
pub unsafe extern "C" fn rium_observe_display_brightness(display: u32, callback: Option<BrightnessChanged>) -> i32 {
    if display == 0 { return -1; }
    let Some((register, unregister)) = display_services().and_then(|services| services.observers) else { return 0; };
    let status = match callback {
        Some(callback) => register(display, display, callback),
        None => unregister(display, display),
    };
    i32::from(status == 0)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn invalid_inputs_fail_without_calling_system_service() {
        let mut result = 0.0;
        assert_eq!(unsafe { rium_display_brightness(0, &mut result) }, -1);
        assert_eq!(unsafe { rium_display_brightness(1, std::ptr::null_mut()) }, -1);
        assert_eq!(unsafe { rium_observe_display_brightness(0, None) }, -1);
    }
}
