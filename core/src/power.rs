const BASELINE: u8 = 1;
const LOW: u8 = 2;
const CRITICAL: u8 = 4;

/// Warnings are remembered separately until the battery connects to external power.
fn update_feedback(seen: &mut u8, previous_source: i32, source: i32, warning: i32) -> i32 {
    if !(0..=1).contains(&source) || !(0..=2).contains(&warning) {
        return 0;
    }
    let level = match warning {
        1 => LOW,
        2 => CRITICAL,
        _ => 0,
    };
    let previously_seen = *seen;
    if source == 1 {
        *seen = BASELINE;
    } else {
        *seen |= BASELINE | level;
        if level != 0 && previously_seen & BASELINE != 0 && previously_seen & level == 0 {
            return warning + 1;
        }
    }
    i32::from((0..=1).contains(&previous_source) && previous_source != source)
}

/// A zeroed state belongs to one observer. Returns 0 none, 1 source, 2 low, 3 critical.
#[no_mangle]
pub unsafe extern "C" fn rium_power_feedback_update(
    seen: *mut u8, previous_source: i32, source: i32, warning: i32,
) -> i32 {
    let Some(seen) = seen.as_mut() else { return 0; };
    update_feedback(seen, previous_source, source, warning)
}

/// -1 is a source change, 0 is a low warning, and 1 is a critical warning.
#[no_mangle]
pub extern "C" fn rium_battery_feedback_seconds(critical: i32) -> f64 {
    match critical {
        -1 => crate::notch_animation::rium_notch_system_hud_seconds(),
        0 => 4.0,
        1 => 5.0,
        _ => 0.0,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn power_warnings_are_debounced_per_level_until_charging() {
        let mut seen = 0;
        assert_eq!(update_feedback(&mut seen, -1, 0, 1), 0);
        assert_eq!(update_feedback(&mut seen, 0, 0, 0), 0);
        assert_eq!(update_feedback(&mut seen, 0, 0, 1), 0);
        assert_eq!(update_feedback(&mut seen, 0, 0, 2), 3);
        assert_eq!(update_feedback(&mut seen, 0, 0, 1), 0);
        assert_eq!(update_feedback(&mut seen, 0, -1, 1), 0);
        assert_eq!(update_feedback(&mut seen, -1, 0, 2), 0);
        assert_eq!(update_feedback(&mut seen, 0, 1, 2), 1);
        assert_eq!(update_feedback(&mut seen, 1, 1, 1), 0);
        assert_eq!(update_feedback(&mut seen, 1, 0, 1), 2);
        assert_eq!(update_feedback(&mut seen, 0, 0, 2), 3);
        let mut critical_first = 0;
        assert_eq!(update_feedback(&mut critical_first, -1, 0, 2), 0);
        assert_eq!(update_feedback(&mut critical_first, 0, 0, 1), 2);
        assert_eq!(update_feedback(&mut critical_first, 0, 0, 2), 0);
    }
}
