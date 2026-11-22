//! Time range for the home calendar's day timeline.

/// Expand the reference's 08:00–20:00 default window to include event bounds.
/// The caller computes the defaults in the local calendar and time zone.
pub fn timeline_bounds(default_start: f64, default_end: f64, events: &[[f64; 2]]) -> Option<[f64; 2]> {
    if !default_start.is_finite() || !default_end.is_finite() || default_start >= default_end { return None; }
    let mut start = default_start;
    let mut end = default_end;
    for [event_start, event_end] in events {
        if event_start.is_finite() { start = start.min(*event_start); }
        if event_end.is_finite() { end = end.max(*event_end); }
    }
    Some([start, end])
}

/// Writes the timeline bounds as Unix timestamps to `output`.
///
/// # Safety
/// `output` must point to two writable f64 values. When `count` is nonzero,
/// `events` must point to `count` consecutive pairs of readable f64 values.
#[no_mangle]
pub unsafe extern "C" fn rium_home_calendar_bounds(default_start: f64, default_end: f64,
    events: *const [f64; 2], count: usize, output: *mut f64) -> i32 {
    if output.is_null() || (count > 0 && events.is_null()) || count > isize::MAX as usize / std::mem::size_of::<[f64; 2]>() { return -1; }
    let events = if count == 0 { &[] } else { std::slice::from_raw_parts(events, count) };
    let Some(bounds) = timeline_bounds(default_start, default_end, events) else { return -1; };
    std::ptr::copy_nonoverlapping(bounds.as_ptr(), output, 2);
    0
}

#[cfg(test)]
mod tests {
    use super::timeline_bounds;

    #[test]
    fn expands_default_window_for_early_late_and_multiday_events() {
        assert_eq!(timeline_bounds(8.0, 20.0, &[]), Some([8.0, 20.0]));
        assert_eq!(timeline_bounds(8.0, 20.0, &[[10.0, 12.0]]), Some([8.0, 20.0]));
        assert_eq!(timeline_bounds(8.0, 20.0, &[[6.0, 9.0], [19.0, 23.0]]), Some([6.0, 23.0]));
        assert_eq!(timeline_bounds(8.0, 20.0, &[[-2.0, 30.0]]), Some([-2.0, 30.0]));
        assert_eq!(timeline_bounds(8.0, 20.0, &[[f64::NAN, f64::INFINITY]]), Some([8.0, 20.0]));
        assert_eq!(timeline_bounds(20.0, 8.0, &[]), None);
    }
}
