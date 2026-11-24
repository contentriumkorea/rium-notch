//! Time-based notch motion and event-light geometry.
//!
//! The reference has multiple animation layers: its root open/close and
//! state-specific shell springs do not always use the same parameters. Their
//! exact internal integration is not established by static evidence. The analytic damped oscillator
//! below is therefore a reconstruction, not a claim of pixel equivalence.
//! Timestamps belong to the caller: a monotonic clock makes interruption and
//! retargeting independent of frame rate or wall-clock adjustments.

use std::f64::consts::PI;

/// Offset for the reference notification marquee's pause and repeating lane.
pub fn notification_marquee_offset(elapsed: f64, text_width: f64) -> Option<f64> {
    if !elapsed.is_finite() || elapsed < 0.0 || !text_width.is_finite() || text_width <= 0.0 { return None; }
    let period = (text_width + 40.0) / 34.0 + 0.9;
    if !period.is_finite() { return None; }
    Some(-34.0 * (elapsed.rem_euclid(period) - 0.9).max(0.0))
}

#[no_mangle]
pub extern "C" fn rium_notification_marquee_offset(elapsed: f64, text_width: f64) -> f64 {
    notification_marquee_offset(elapsed, text_width).unwrap_or(0.0)
}

/// Three pulses recovered from NotificationArrivalGlow.envelope.
pub fn notification_arrival_envelope(elapsed: f64, duration: f64, reduce_motion: bool) -> Option<f64> {
    if !elapsed.is_finite() || !duration.is_finite() || elapsed < 0.0 || duration <= 0.0 { return None; }
    if reduce_motion {
        return Some(if elapsed <= duration { (PI * elapsed / duration).sin().max(0.0) } else { 0.0 });
    }
    let pulse = |start: f64, width: f64, strength: f64| {
        if elapsed >= start && elapsed <= start + width { strength * (PI * (elapsed - start) / width).sin().max(0.0) } else { 0.0 }
    };
    Some(pulse(0.06, 0.15, 1.0).max(pulse(0.30, 0.16, 1.0)).max(pulse(0.54, 0.22, 0.42)))
}

#[no_mangle]
pub extern "C" fn rium_notification_arrival_envelope(elapsed: f64, duration: f64, reduce_motion: i32) -> f64 {
    if !(0..=1).contains(&reduce_motion) { return -1.0; }
    notification_arrival_envelope(elapsed, duration, reduce_motion == 1).unwrap_or(-1.0)
}

/// The reference keeps a faint gauge between the notification pulses.
pub fn notification_arrival_gauge(elapsed: f64, duration: f64) -> Option<f64> {
    if !elapsed.is_finite() || !duration.is_finite() || elapsed < 0.0 || duration <= 0.0 { return None; }
    let entrance = (elapsed / 0.07).min(1.0);
    let exit = ((duration - elapsed) / 0.5).clamp(0.0, 1.0);
    Some((elapsed / 0.2).min(1.0) * entrance.min(exit) * 0.22)
}

#[no_mangle]
pub extern "C" fn rium_notification_arrival_gauge(elapsed: f64, duration: f64) -> f64 {
    notification_arrival_gauge(elapsed, duration).unwrap_or(-1.0)
}

/// Reference OrganicAudioCloud field: a 47 by 19 grid filtered by elliptical density.
pub fn assistant_cloud_speck(column: i32, row: i32) -> Option<[f64; 4]> {
    if !(0..47).contains(&column) || !(0..19).contains(&row) { return None; }
    let x = f64::from(column) / 46.0;
    let y = f64::from(row) / 18.0;
    let density = (-2.8 * (((x - 0.5) / 0.48).powi(2) + ((y - 0.5) / 0.39).powi(2))).exp();
    if density <= 0.045 { return None; }
    let seed = (row as u64).wrapping_mul(0x220e_5eac_c7db)
        .wrapping_add((column as u64).wrapping_mul(0x00b9_7f4a_7c15));
    Some([x, y, density, ((seed >> 32) & 0xff) as f64 / 255.0])
}

#[no_mangle]
pub unsafe extern "C" fn rium_assistant_cloud_speck(column: i32, row: i32, output: *mut f64) -> i32 {
    if output.is_null() || !(0..47).contains(&column) || !(0..19).contains(&row) { return -1; }
    let Some(speck) = assistant_cloud_speck(column, row) else { return 0; };
    std::ptr::copy_nonoverlapping(speck.as_ptr(), output, speck.len());
    1
}

/// OrganicAudioCloud batches rectangles by five-bit RGB and 16-step opacity.
pub fn assistant_cloud_color_bucket(red: f64, green: f64, blue: f64, opacity: f64) -> Option<u32> {
    if ![red, green, blue, opacity].iter().all(|value| value.is_finite()) || opacity <= 0.004 { return None; }
    let channel = |value: f64| (value.clamp(0.0, 1.0) * 31.0).round() as u32;
    let alpha = (opacity.clamp(0.0, 1.0) * 16.0).round() as u32;
    Some((channel(red) << 15) | (channel(green) << 10) | (channel(blue) << 5) | alpha)
}

#[no_mangle]
pub extern "C" fn rium_assistant_cloud_color_bucket(red: f64, green: f64, blue: f64, opacity: f64) -> i64 {
    assistant_cloud_color_bucket(red, green, blue, opacity).map(i64::from).unwrap_or(-1)
}

/// Entry, exit and exit pulse from MurmurOrganicMotion; zero base level is
/// used when the assistant has no live voice input.
pub fn assistant_cloud_envelope(age: f64, exit_age: Option<f64>, animated: bool) -> Option<[f64; 4]> {
    if !age.is_finite() || age < 0.0 || exit_age.is_some_and(|value| !value.is_finite() || value < 0.0) { return None; }
    let phase = if animated { age.rem_euclid(40.0 * PI) } else { 0.6 };
    let entry = if animated { smoothstep(age / 0.38) } else { 1.0 };
    let exit = match exit_age { Some(value) if animated => smoothstep(value / 0.36), Some(_) => 1.0, None => 0.0 };
    let flash = match exit_age {
        Some(value) if animated && value < 100.0 => (value / 0.28).powi(2) * (-value / 0.19).exp() * 1.8,
        _ => 0.0,
    };
    let energy = (0.23 + 0.09 * (phase * 2.05).sin()) * entry * (1.0 - exit);
    Some([entry, exit, flash, energy])
}

#[no_mangle]
pub unsafe extern "C" fn rium_assistant_cloud_envelope(age: f64, exit_age: f64, animated: i32, output: *mut f64) -> i32 {
    if output.is_null() || !(0..=1).contains(&animated) || !exit_age.is_finite() || exit_age < -1.0 { return -1; }
    let exit = if exit_age == -1.0 { None } else { Some(exit_age) };
    let Some(frame) = assistant_cloud_envelope(age, exit, animated == 1) else { return -1; };
    std::ptr::copy_nonoverlapping(frame.as_ptr(), output, frame.len());
    0
}

/// Continue the live meter into MurmurOrganicMotion's writing phase.
pub fn dictation_writing_cloud_sample(age: f64, writing_age: f64, initial_level: f64, animated: bool) -> Option<[f64; 4]> {
    if !age.is_finite() || age < 0.0 || !writing_age.is_finite() || writing_age < 0.0 || !initial_level.is_finite() { return None; }
    let phase = if animated { age.rem_euclid(40.0 * PI) } else { 0.6 };
    let entry = if animated { smoothstep(writing_age / 0.38) } else { 1.0 };
    let initial = initial_level.clamp(0.0, 1.0);
    let energy = initial + entry * ((0.23 + 0.09 * (phase * 2.05).sin()) - initial);
    Some([entry, 0.0, energy, 0.0])
}

#[no_mangle]
pub unsafe extern "C" fn rium_dictation_writing_cloud_sample(age: f64, writing_age: f64, initial_level: f64, animated: i32, output: *mut f64) -> i32 {
    if output.is_null() || !(0..=1).contains(&animated) { return -1; }
    let Some(frame) = dictation_writing_cloud_sample(age, writing_age, initial_level, animated == 1) else { return -1; };
    std::ptr::copy_nonoverlapping(frame.as_ptr(), output, frame.len());
    0
}

/// Reference OrganicAudioCloud column waves: two currents, density wave and ripple.
pub fn assistant_cloud_column(index: i32, time: f64, reduce_motion: bool) -> Option<[f64; 4]> {
    if !(0..47).contains(&index) || !time.is_finite() { return None; }
    let x = f64::from(index) / 46.0;
    let phase = if reduce_motion { 0.6 } else { time.rem_euclid(40.0 * PI) };
    Some([(3.6 * phase + 5.2 * x).sin(), (2.5 * phase + 7.3 * x + 0.8).sin(),
          0.5 + 0.25 * (8.5 * x - 2.05 * phase).sin() + 0.2 * (11.0 * x + 1.4 * phase + 0.8).sin(),
          (9.0 * x - 2.05 * phase).sin()])
}

#[no_mangle]
pub unsafe extern "C" fn rium_assistant_cloud_column(index: i32, time: f64, reduce_motion: i32, output: *mut f64) -> i32 {
    if output.is_null() || !(0..=1).contains(&reduce_motion) { return -1; }
    let Some(frame) = assistant_cloud_column(index, time, reduce_motion == 1) else { return -1; };
    std::ptr::copy_nonoverlapping(frame.as_ptr(), output, frame.len());
    0
}

/// Reference organic-mode particle position, size, opacity and colour whitening.
pub fn assistant_cloud_particle(x: f64, y: f64, density: f64, grain: f64, time: f64,
    width: f64, height: f64, column: [f64; 4], sample: [f64; 4]) -> Option<[f64; 5]> {
    if ![x, y, density, grain, time, width, height].iter().chain(column.iter()).chain(sample.iter()).all(|v| v.is_finite())
        || !(0.0..=1.0).contains(&x) || !(0.0..=1.0).contains(&y)
        || !(0.0..=1.0).contains(&density) || !(0.0..=1.0).contains(&grain) || width <= 0.0 || height <= 0.0 { return None; }
    let [writing, done, energy, exhale] = sample;
    if !(0.0..=1.0).contains(&writing) || !(0.0..=1.0).contains(&done) || energy < 0.0 || exhale < 0.0 { return None; }
    let [wave, ripple, current, drift] = column;
    let opacity_base = (energy * 0.7 + 0.65) * (writing * (1.0 - done) * (current * 0.65 - 0.3) + 1.0);
    let opacity = density * (grain * 0.14 + 0.86) * (opacity_base + done * (1.1 - opacity_base));
    let size = density * 0.55 + 0.95 + energy * 0.4 + exhale * 0.15;
    let phase = time.rem_euclid(40.0 * PI);
    // shortcut: this phase-to-particle mapping needs reference-frame comparison.
    let horizontal = (x - 0.5) * (energy * 0.13 + 0.87) + 0.5
        + (1.0 - done) * (4.2 * y + 2.3 * phase).sin() * 0.028 * energy;
    let vertical_scale = energy * 0.82 + 0.38 + energy * 0.2 * ripple;
    // shortcut: completion breathing uses a fixed midpoint until its caller mapping is recovered.
    let vertical = (y - 0.5) * (vertical_scale + done * (0.76 - vertical_scale)) + 0.5
        + (energy * 0.11 + done * (0.012 - energy * 0.11)) * wave
        + writing * (1.0 - done) * 0.035 * drift;
    let result = [horizontal * width - size / 2.0, vertical * height - size / 2.0,
                  size, opacity, density * 0.1 + done * 0.26];
    if result.iter().all(|v| v.is_finite()) { Some(result) } else { None }
}

#[no_mangle]
pub unsafe extern "C" fn rium_assistant_cloud_particle(x: f64, y: f64, density: f64, grain: f64, time: f64,
    width: f64, height: f64, column: *const f64, sample: *const f64, output: *mut f64) -> i32 {
    if column.is_null() || sample.is_null() || output.is_null() { return -1; }
    let c = std::slice::from_raw_parts(column, 4);
    let m = std::slice::from_raw_parts(sample, 4);
    let Some(result) = assistant_cloud_particle(x, y, density, grain, time, width, height,
        [c[0], c[1], c[2], c[3]], [m[0], m[1], m[2], m[3]]) else { return -1; };
    std::ptr::copy_nonoverlapping(result.as_ptr(), output, result.len());
    0
}

// shortcut: word timing approximates output energy until audio samples are available.
#[no_mangle]
pub extern "C" fn rium_assistant_speech_pulse(elapsed: f64) -> f64 {
    if !elapsed.is_finite() || elapsed < 0.0 { return 0.0; }
    0.12 + 0.6 * (-3.0 * elapsed).exp()
}

/// AssistantCloud levels: listening, thinking, acting, approval, done.
pub fn assistant_live_level(mode: i32, time: f64, input_level: f64) -> Option<f64> {
    if !(0..=4).contains(&mode) || !time.is_finite() || !input_level.is_finite() { return None; }
    let phase = time.rem_euclid(20.0 * PI);
    let value = match mode {
        0 => input_level,
        1 => 0.3 + 0.22 * (phase * 2.2).sin() + 0.12 * (phase * 5.3 + 1.0).sin(),
        2 => 0.25,
        3 => 0.25 + ((time.rem_euclid(2.0 / 1.8) * 1.8 * PI).sin() * 0.5 + 0.5) * 0.25,
        _ => 0.0,
    };
    Some(value.clamp(0.0, 1.0))
}

#[no_mangle]
pub extern "C" fn rium_assistant_live_level(mode: i32, time: f64, input_level: f64) -> f64 {
    assistant_live_level(mode, time, input_level).unwrap_or(f64::NAN)
}

/// OrganicAudioCloud's non-organic branch, used by the reference AssistantCloud.
pub fn assistant_live_particle(x: f64, y: f64, density: f64, grain: f64, time: f64,
    width: f64, height: f64, column: [f64; 4], level: f64, completion: f64,
    listening: bool, moving: bool) -> Option<[f64; 5]> {
    if ![x, y, density, grain, time, width, height, level, completion].iter().chain(column.iter()).all(|v| v.is_finite())
        || ![x, y, density, grain, level, completion].iter().all(|v| (0.0..=1.0).contains(v))
        || width <= 0.0 || height <= 0.0 { return None; }
    let phase = time.rem_euclid(40.0 * PI);
    let [wave, ripple, _, _] = column;
    let oscillation = if moving { (4.2 * y + 2.3 * phase).sin() * 0.028 } else { 0.0 };
    let vertical_wave = if moving { wave * 0.11 * level + (1.2 * phase).sin() * 0.002 } else { wave * 0.045 };
    let listening_pulse = if listening {
        let sweep = phase.rem_euclid(1.4) / 1.4 * 1.3 - 0.15;
        (1.0 - completion) * (-((x - sweep) / 0.09).powi(2)).exp()
    } else { 0.0 };
    let grain_strength = 0.86 + 0.14 * grain;
    let base = (0.65 + level * 0.7) * density * grain_strength * (0.95 + 0.05 * ripple);
    let alpha = if listening { base * (0.8 + 0.7 * listening_pulse) } else { base };
    let completion_alpha = (density * 1.1 * grain_strength * (0.18 * (x * 3.0 + phase * 2.4 + grain * 6.28).sin() + 0.82)).min(1.0);
    let opacity = alpha.min(1.0) + (completion_alpha - alpha.min(1.0)) * completion;
    let base_size = density * 0.55 + 0.95 + level * 0.48 + listening_pulse * 0.5;
    let size = base_size + (density * 0.55 + 1.05 - base_size) * completion;
    let base_x = (x - 0.5) * (level * 0.13 + 0.87) + 0.5 + oscillation * level;
    let full_x = (x - 0.5) * 0.9 + 0.5;
    let horizontal = base_x + (full_x - base_x) * completion;
    let base_y = vertical_wave + 0.5 + (y - 0.5) * (level * 0.82 + 0.38 + level * 0.2 * ripple);
    // shortcut: completion breathing and secondary drift phases need frame comparison.
    let done_y = (y - 0.5) * 0.76 + 0.5 + wave * 0.012;
    let vertical = base_y + (done_y - base_y) * completion;
    let result = [horizontal * width - size / 2.0, vertical * height - size / 2.0,
                  size, opacity, completion * 0.35 + density * 0.18];
    if result.iter().all(|v| v.is_finite()) { Some(result) } else { None }
}

#[no_mangle]
pub unsafe extern "C" fn rium_assistant_live_particle(x: f64, y: f64, density: f64, grain: f64, time: f64,
    width: f64, height: f64, column: *const f64, level: f64, completion: f64,
    listening: i32, moving: i32, output: *mut f64) -> i32 {
    if column.is_null() || output.is_null() || !(0..=1).contains(&listening) || !(0..=1).contains(&moving) { return -1; }
    let c = std::slice::from_raw_parts(column, 4);
    let Some(result) = assistant_live_particle(x, y, density, grain, time, width, height,
        [c[0], c[1], c[2], c[3]], level, completion, listening == 1, moving == 1) else { return -1; };
    std::ptr::copy_nonoverlapping(result.as_ptr(), output, result.len());
    0
}

/// Remaining hover reopen cooldown from the observed root-view timing.
/// The caller supplies elapsed monotonic time since the last collapse.
pub fn hover_reopen_wait(elapsed: f64) -> Option<f64> {
    if !elapsed.is_finite() || elapsed < 0.0 { return None; }
    let remaining = 0.34 - elapsed;
    Some(if remaining > 0.02 { remaining } else { 0.0 })
}

#[no_mangle]
pub extern "C" fn rium_notch_hover_reopen_wait(elapsed: f64) -> f64 {
    hover_reopen_wait(elapsed).unwrap_or(0.0)
}

#[no_mangle]
pub extern "C" fn rium_notch_hover_close_delay(delay: f64, home_editing: i32) -> f64 {
    delay.max(if home_editing == 1 { 3.0 } else { 0.1 })
}

#[no_mangle]
pub extern "C" fn rium_notch_agent_action_hold_duration() -> f64 {
    1.5
}

#[no_mangle]
pub extern "C" fn rium_reminder_list_spring_response() -> f64 { 0.30 }

#[no_mangle]
pub extern "C" fn rium_reminder_row_entry_scale() -> f64 { 0.96 }

#[no_mangle]
pub extern "C" fn rium_notch_agent_switcher_index(count: i64, current: i64, direction: i32) -> i64 {
    if count <= 0 || !matches!(direction, -1 | 1) {
        return -1;
    }
    let current = if (0..count).contains(&current) { current } else { 0 };
    (current + i64::from(direction)).rem_euclid(count)
}

/// Reference BandFold: top-anchored x/y scale, blur radius, and opacity.
/// Progress 0 is fully visible; progress 1 is folded out.
pub fn band_fold_frame(progress: f64) -> Option<[f64; 4]> {
    if !progress.is_finite() { return None; }
    let frame = [1.0 - 0.3 * progress, 1.0 - 0.12 * progress, 7.0 * progress, 1.0 - progress];
    if frame.iter().all(|v| v.is_finite()) { Some(frame) } else { None }
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_band_fold_frame(progress: f64, output: *mut f64) -> i32 {
    if output.is_null() { return -1; }
    let Some(frame) = band_fold_frame(progress) else { return -1; };
    std::ptr::copy_nonoverlapping(frame.as_ptr(), output, frame.len());
    0
}

/// The four arrival light widths divide the available range into equal steps.
pub fn agent_arrival_arm_run(preset: i32, screen_width: f64, notch_width: f64) -> Option<f64> {
    if !(0..=3).contains(&preset)
        || !screen_width.is_finite()
        || !notch_width.is_finite()
        || screen_width <= 0.0
        || notch_width < 0.0
    {
        return None;
    }
    let room = ((screen_width - notch_width) / 2.0).max(0.0);
    let narrow = room.min(76.0 * 2.2);
    let widest = room.min(768.0);
    Some(narrow + (widest - narrow) * f64::from(preset) / 3.0)
}

#[no_mangle]
pub extern "C" fn rium_agent_arrival_arm_run(preset: i32, screen_width: f64, notch_width: f64) -> f64 {
    agent_arrival_arm_run(preset, screen_width, notch_width).unwrap_or(f64::NAN)
}

/// BandHours selects the lower two-hour anchor for the local clock time.
#[no_mangle]
pub extern "C" fn rium_home_hour_photo(hour: i32) -> i32 {
    if !(0..24).contains(&hour) { return -1; }
    (hour / 2) * 2
}

/// Writes the regular collapsed notch size in points.
#[no_mangle]
pub unsafe extern "C" fn rium_notch_regular_compact_size(
    camera_width: f64, camera_height: f64, screen_width: f64, shelf_minimum_width: f64,
    agent: i32, timer: i32, music: i32, notification: i32, focus_alarm: i32, shelf: i32,
    output: *mut f64,
) -> i32 {
    if output.is_null() || !screen_width.is_finite() || screen_width <= 0.0 {
        return -1;
    }
    let physical_width = if camera_width.is_finite() { camera_width.clamp(0.0, screen_width) } else { 0.0 };
    let base = if physical_width > 0.0 { physical_width } else { 185.0 };
    let measured_height = camera_height.is_finite() && camera_height > 0.0;
    let has_physical_notch = physical_width > 0.0 && measured_height;
    let base_height = if measured_height { camera_height } else { 32.0 };
    let extra_height = match (shelf != 0, focus_alarm != 0, has_physical_notch, notification != 0, agent != 0) {
        (true, _, _, _, _) => 180.0,
        (_, true, _, _, _) => 96.0,
        (_, _, false, true, _) => 2.0,
        (_, _, false, _, true) => 3.0,
        _ => 0.0,
    };
    let requested = match (shelf != 0, focus_alarm != 0, notification != 0, agent != 0, timer != 0, music != 0) {
        (true, _, _, _, _, _) => base.max(320.0).max(shelf_minimum_width),
        (_, true, _, _, _, _) => 540.0,
        (_, _, true, _, _, _) => base + 344.0,
        (_, _, _, true, _, _) => (base + 240.0).max(420.0),
        (_, _, _, _, true, true) => (base + if has_physical_notch { 160.0 } else { 146.0 }).max(330.0),
        (_, _, _, _, true, false) => (base + 114.0).max(250.0),
        (_, _, _, _, false, true) => (base + if has_physical_notch { 116.0 } else { 88.0 }).max(296.0),
        _ => base.max(60.0),
    };
    let available = screen_width.min(physical_width.max((screen_width - 24.0).max(60.0)));
    *output = requested.min(available);
    *output.add(1) = base_height + extra_height;
    0
}

#[no_mangle]
pub extern "C" fn rium_notch_shell_state(expanded: i32, detail: i32, status: i32, media: i32, shelf: i32) -> i32 {
    match (shelf != 0, expanded != 0, detail != 0, status != 0, media != 0) {
        (true, _, _, _, _) => 4,
        (_, true, _, _, _) => 5,
        (_, _, true, _, _) => 2,
        (_, _, _, true, _) => 1,
        (_, _, _, _, true) => 0,
        _ => 3,
    }
}

/// Only a bare shell can keep the outgoing panel after a collapse starts.
#[no_mangle]
pub extern "C" fn rium_notch_panel_retention(expanded: i32, shell: i32, was_retained: i32) -> i32 {
    i32::from(expanded != 0 || (shell == 3 && was_retained != 0))
}

/// Corner radius and top shoulder outset for the reference shell states.
///
/// State tags are the order of the recovered ShellMorphState enum: media,
/// status band, detail peek, bare notch, shelf, and expanded. These are
/// target values; the renderer must interpolate them with the same progress
/// as its visible silhouette and exterior-light masks.
pub fn shell_corner_geometry(state: i32) -> Option<[f64; 2]> {
    match state {
        0..=2 | 4 => Some([16.0, 20.0]),
        3 => Some([8.0, 12.0]),
        5 => Some([28.0, 36.0]),
        _ => None,
    }
}

/// Writes bottom-corner radius and top-shoulder outset, in points.
#[no_mangle]
pub unsafe extern "C" fn rium_notch_shell_corner_geometry(state: i32, output: *mut f64) -> i32 {
    if output.is_null() { return -1; }
    let Some(values) = shell_corner_geometry(state) else { return -1; };
    *output = values[0];
    *output.add(1) = values[1];
    0
}

/// Converts an outer silhouette size to shoulder, bottom radius and the two
/// Bézier control distances. The reference's shape receives an inner rect
/// and lets its shoulders extend outwards; Rium stores the outer width.
pub fn shell_contour_metrics(width: f64, height: f64, bottom: f64, shoulder: f64) -> Option<[f64; 4]> {
    if !width.is_finite() || !height.is_finite() || !bottom.is_finite() || !shoulder.is_finite()
        || width < 0.0 || height < 0.0 { return None; }
    // A shoulder cannot be represented outside a finite Rium outer frame
    // when that frame is narrower than twice the desired shoulder.
    let shoulder = shoulder.max(0.0).min(width / 2.0);
    let inner_width = (width - 2.0 * shoulder).max(0.0);
    let radius = bottom.max(0.0).min(inner_width.min(height) / 2.0);
    // Keep the physical shoulder shape with either bottom corner radius.
    // Blend smoothly as the shoulder and the bottom corners change size.
    let equal_radii_weight = 1.0 - (shoulder - radius).abs() / 4.0;
    let physical_shoulder_weight = 1.0 - (shoulder - 10.0).abs() / 2.0;
    let weight = equal_radii_weight.max(physical_shoulder_weight).clamp(0.0, 1.0);
    let smooth_weight = weight * weight * (3.0 - 2.0 * weight);
    let upper = shoulder * (0.22 + 0.12 * smooth_weight);
    Some([shoulder, radius, upper, radius * 0.78])
}

/// Writes shoulder, bottom radius, upper control and lower control distances.
#[no_mangle]
pub unsafe extern "C" fn rium_notch_shell_contour_metrics(width: f64, height: f64, bottom: f64,
    shoulder: f64, output: *mut f64) -> i32 {
    if output.is_null() { return -1; }
    let Some(values) = shell_contour_metrics(width, height, bottom, shoulder) else { return -1; };
    for (index, value) in values.iter().enumerate() { *output.add(index) = *value; }
    0
}

/// Lower visible edge of the same silhouette used by the SwiftUI shell, at an
/// x coordinate relative to its outer frame. Outside the frame the edge is the
/// screen top. At a vertical edge, choose its lower end for exterior effects.
pub fn shell_contour_y(x: f64, width: f64, height: f64, bottom: f64, shoulder: f64) -> Option<f64> {
    if !x.is_finite() { return None; }
    let [shoulder, radius, upper, lower] = shell_contour_metrics(width, height, bottom, shoulder)?;
    if x < 0.0 || x > width || width == 0.0 { return Some(0.0); }
    let local = x.min(width - x);
    // Solve x(t) for the relevant cubic. Both curves are monotonic in x.
    let cubic = |a: f64, b: f64, c: f64, d: f64, t: f64| {
        let u = 1.0 - t;
        u * u * u * a + 3.0 * u * u * t * b + 3.0 * u * t * t * c + t * t * t * d
    };
    let solve = |points: [f64; 4]| {
        let (mut lo, mut hi) = (0.0, 1.0);
        for _ in 0..20 {
            let mid = (lo + hi) * 0.5;
            if cubic(points[0], points[1], points[2], points[3], mid) < local { lo = mid; } else { hi = mid; }
        }
        (lo + hi) * 0.5
    };
    if shoulder > 0.0 && local < shoulder {
        let t = solve([0.0, shoulder - upper, shoulder, shoulder]);
        return Some(cubic(0.0, 0.0, upper, shoulder, t));
    }
    if radius > 0.0 && local < shoulder + radius {
        let t = solve([shoulder, shoulder, shoulder + radius - lower, shoulder + radius]);
        return Some(cubic(height - radius, height - radius + lower, height, height, t));
    }
    Some(height)
}

#[no_mangle]
pub extern "C" fn rium_notch_shell_contour_y(x: f64, width: f64, height: f64, bottom: f64, shoulder: f64) -> f64 {
    shell_contour_y(x, width, height, bottom, shoulder).unwrap_or(f64::NAN)
}

/// The reference FloatingIslandShape's three cubic corner segments. The ten
/// points run from the top edge towards the left edge in a local corner.
pub fn floating_island_corner(radius: f64, width: f64, height: f64) -> Option<[[f64; 2]; 10]> {
    if ![radius, width, height].iter().all(|v| v.is_finite()) || radius < 0.0 || width <= 0.0 || height <= 0.0 { return None; }
    let r = radius.min(width / 2.0).min(height / 2.0);
    if r == 0.0 { return Some([[0.0; 2]; 10]); }
    let normal = [[1.0,0.0], [0.8739,0.0], [0.7488,0.0241], [0.6315,0.0705], [0.3748,0.1721],
                  [0.1721,0.3748], [0.0705,0.6315], [0.0241,0.7488], [0.0,0.8739], [0.0,1.0]];
    let continuous = [[1.52866483,0.0], [1.08849296,0.0], [0.86840694,0.0], [0.63149399,0.074911], [0.37282392,0.16905899],
                      [0.16905899,0.37282392], [0.074911,0.63149399], [0.0,0.86840694], [0.0,1.08849296], [0.0,1.52866483]];
    let blend = ((width.min(height) / 2.0 / r - 1.0) / 0.52866483).clamp(0.0, 1.0);
    let points = std::array::from_fn(|i| std::array::from_fn(|axis| {
        (normal[i][axis] + (continuous[i][axis] - normal[i][axis]) * blend) * r
    }));
    if points.iter().flatten().all(|v| v.is_finite()) { Some(points) } else { None }
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_floating_corner(radius: f64, width: f64, height: f64, output: *mut f64) -> i32 {
    if output.is_null() { return -1; }
    let Some(points) = floating_island_corner(radius, width, height) else { return -1; };
    std::ptr::copy_nonoverlapping(points.as_ptr().cast::<f64>(), output, 20);
    0
}

/// A synthetic notch is used when neither a physical cutout nor a usable
/// top safe area has been resolved. This tests the safe-area fallback.
#[no_mangle]
pub extern "C" fn rium_notch_uses_virtual_geometry(screen_height: f64, safe_area_top: f64) -> i32 {
    if screen_height.is_finite() && safe_area_top > 0.0 && safe_area_top < screen_height * 0.25 {
        0
    } else {
        1
    }
}

/// Top inset recovered from NotchController.islandPositionBounds. The caller
/// supplies the actual menu-bar height, including its system fallback.
pub fn floating_island_top_inset(menu_height: f64) -> Option<f64> {
    if !menu_height.is_finite() || menu_height < 0.0 { return None; }
    let island_height = (menu_height - 6.0).clamp(12.0, 24.0);
    Some(((menu_height - 1.0 - island_height) / 2.0).max(0.0))
}

#[no_mangle]
pub extern "C" fn rium_notch_floating_top_inset(menu_height: f64) -> f64 {
    floating_island_top_inset(menu_height).unwrap_or(f64::NAN)
}

/// Compact widths recovered from the reference's interactive card sizing.
// shortcut: mapping app states to these branches and detail height needs visual comparison.
pub fn floating_island_compact_size(screen_width: f64, menu_height: f64, mode: i32) -> Option<[f64; 2]> {
    if !screen_width.is_finite() || screen_width <= 16.0 || !menu_height.is_finite() || menu_height < 0.0 { return None; }
    let base = (menu_height - 6.0).clamp(12.0, 24.0);
    let (width, height): (f64, f64) = match mode {
        0 => (96.0, base),
        1 => (400.0, base + 3.0),
        // Rium's single-row previews need up to 34 pt plus vertical padding.
        2 => (400.0, (base + 2.0).max(38.0)),
        3 => (250.0, base),
        4 => (296.0, base),
        5 => (330.0, base),
        6 => (540.0, base + 96.0),
        _ => return None,
    };
    Some([width.min(screen_width - 16.0), height])
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_floating_compact_size(screen_width: f64, menu_height: f64,
                                                          mode: i32, output: *mut f64) -> i32 {
    if output.is_null() { return -1; }
    let Some(size) = floating_island_compact_size(screen_width, menu_height, mode) else { return -1; };
    std::ptr::copy_nonoverlapping(size.as_ptr(), output, 2);
    0
}

/// Horizontal center and top offset for a screen-relative island anchor.
/// The reference uses a 96pt compact width and reserves 470pt plus 8pt below.
pub fn floating_island_anchor(screen_x: f64, width: f64, height: f64, top_inset: f64,
                              virtual_screen: bool, normalized_x: f64, normalized_y: f64) -> Option<[f64; 2]> {
    if ![screen_x, width, height, top_inset, normalized_x, normalized_y].iter().all(|x| x.is_finite())
        || width <= 0.0 || height <= 0.0 || top_inset < 0.0
        || !(0.0..=1.0).contains(&normalized_x) || !(0.0..=1.0).contains(&normalized_y) { return None; }
    let margin = 56.0_f64.min(width / 2.0);
    let span_x = (width - 2.0 * margin).max(0.0);
    let span_y = if virtual_screen { 0.0 } else { (height - top_inset - 478.0).max(0.0) };
    let result = [screen_x + margin + normalized_x * span_x, top_inset + normalized_y * span_y];
    if result.iter().all(|x| x.is_finite()) { Some(result) } else { None }
}

/// Normalize a dragged position for storage, clamping it to the reference's
/// movable range. Degenerate screens use the centered/top anchor.
pub fn floating_island_normalized(screen_x: f64, width: f64, height: f64, top_inset: f64,
                                  virtual_screen: bool, center_x: f64, top_offset: f64) -> Option<[f64; 2]> {
    if ![screen_x, width, height, top_inset, center_x, top_offset].iter().all(|x| x.is_finite())
        || width <= 0.0 || height <= 0.0 || top_inset < 0.0 { return None; }
    let margin = 56.0_f64.min(width / 2.0);
    let span_x = (width - 2.0 * margin).max(0.0);
    let span_y = if virtual_screen { 0.0 } else { (height - top_inset - 478.0).max(0.0) };
    let x = if span_x > 0.0 { ((center_x - screen_x - margin) / span_x).clamp(0.0, 1.0) } else { 0.5 };
    let y = if span_y > 0.0 { ((top_offset - top_inset) / span_y).clamp(0.0, 1.0) } else { 0.0 };
    if x.is_finite() && y.is_finite() { Some([x, y]) } else { None }
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_floating_position(screen_x: f64, width: f64, height: f64, top_inset: f64,
                                                       virtual_screen: i32, x: f64, y: f64, normalize: i32,
                                                       output: *mut f64) -> i32 {
    if output.is_null() || !(0..=1).contains(&virtual_screen) || !(0..=1).contains(&normalize) { return -1; }
    let position = if normalize == 1 { floating_island_normalized(screen_x, width, height, top_inset, virtual_screen == 1, x, y) }
        else { floating_island_anchor(screen_x, width, height, top_inset, virtual_screen == 1, x, y) };
    let Some(position) = position else { return -1; };
    std::ptr::copy_nonoverlapping(position.as_ptr(), output, position.len());
    0
}

/// Card translation from NotchScreenGeometry.islandCardOffset. Camera bounds
/// are [min_x, max_x, min_y] in AppKit screen coordinates.
pub fn floating_island_card_offset(screen_min_x: f64, screen_width: f64, screen_max_y: f64,
                                   notch_center_x: f64, card_width: f64, top_offset: f64,
                                   floating: bool, camera: Option<[f64; 3]>) -> Option<[f64; 2]> {
    if ![screen_min_x, screen_width, screen_max_y, notch_center_x, card_width, top_offset].iter().all(|v| v.is_finite())
        || screen_width <= 0.0 || card_width < 0.0 || top_offset < 0.0
        || camera.is_some_and(|c| !c.iter().all(|v| v.is_finite()) || c[0] > c[1]) { return None; }
    if !floating { return Some([0.0, 0.0]); }
    let half_card = card_width / 2.0;
    let margin = (half_card + 8.0).min(screen_width / 2.0);
    let lower = screen_min_x + margin;
    let upper = screen_min_x + screen_width - margin;
    if !lower.is_finite() || !upper.is_finite() || lower > upper { return None; }
    let center = notch_center_x.clamp(lower, upper);
    let down = camera.map_or(0.0, |c| {
        let overlap = (c[1] + 4.0).min(center + half_card) - (c[0] - 4.0).max(center - half_card);
        (screen_max_y - c[2] + 4.0 - top_offset).max(0.0) * (overlap / 4.0).clamp(0.0, 1.0)
    });
    let result = [center - notch_center_x, down];
    if result.iter().all(|v| v.is_finite()) { Some(result) } else { None }
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_floating_card_offset(screen_min_x: f64, screen_width: f64, screen_max_y: f64,
    notch_center_x: f64, card_width: f64, top_offset: f64, floating: i32, has_camera: i32,
    camera_min_x: f64, camera_max_x: f64, camera_min_y: f64, output: *mut f64) -> i32 {
    if output.is_null() || !(0..=1).contains(&floating) || !(0..=1).contains(&has_camera) { return -1; }
    let camera = (has_camera == 1).then_some([camera_min_x, camera_max_x, camera_min_y]);
    let Some(offset) = floating_island_card_offset(screen_min_x, screen_width, screen_max_y,
        notch_center_x, card_width, top_offset, floating == 1, camera) else { return -1; };
    std::ptr::copy_nonoverlapping(offset.as_ptr(), output, offset.len());
    0
}

/// The reference divides the drawing width by the grid spacing and rounds up.
// shortcut: cap unusually wide surfaces until their rendering cost is measured.
pub fn pixel_grid_columns(width: f64, spacing: f64) -> Option<u32> {
    if !width.is_finite() || !spacing.is_finite() || width <= 0.0 || spacing <= 0.0 { return None; }
    Some((width / spacing).ceil().clamp(1.0, 4096.0) as u32)
}

#[no_mangle]
pub extern "C" fn rium_notch_pixel_grid_columns(width: f64, spacing: f64) -> u32 {
    pixel_grid_columns(width, spacing).unwrap_or(0)
}

/// Bounds the recovered contour and its largest scaled highlight on the canvas.
// The margin also covers the reference's maximum 1.28 intensity multiplier.
pub fn pixel_field_bounds(width: f64, height: f64, notch_width: f64, notch_height: f64,
                          arm: f64, thickness: f64) -> Option<[f64; 4]> {
    if ![width, height, notch_width, notch_height, arm, thickness].iter().all(|v| v.is_finite())
        || width <= 0.0 || height <= 0.0 || notch_width <= 0.0 || notch_height <= 0.0 || arm < 0.0 || thickness <= 0.0 {
        return None;
    }
    let reach = ((width - notch_width) / 2.0).max(0.0);
    let shoulder = reach.max(22.0).min(width * 0.42);
    let edge = (shoulder - 5.0 - arm).max(0.0);
    let phase = 0.34 + 1.0 / 3.0;
    let scale_x = 1.0 + 0.32 * phase;
    let scale_y = 1.0 + 1.6 * (scale_x - 1.0);
    let margin = 32.0 * thickness.max(1.0) + 3.0;
    let half = (width / 2.0 - edge) * scale_x + margin;
    let bottom = (height - 2.0).min(notch_height - 2.0).max(17.0).max(notch_height - 2.0);
    Some([(width / 2.0 - half).max(0.0), (width / 2.0 + half).min(width), 0.0,
          (2.0 + (bottom - 2.0).max(0.0) * scale_y + margin).min(height)])
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_pixel_field_bounds(width: f64, height: f64, notch_width: f64,
                                                         notch_height: f64, arm: f64, thickness: f64,
                                                         output: *mut f64) -> i32 {
    if output.is_null() { return -1; }
    let Some(bounds) = pixel_field_bounds(width, height, notch_width, notch_height, arm, thickness) else { return -1; };
    std::ptr::copy_nonoverlapping(bounds.as_ptr(), output, bounds.len());
    0
}

/// The reference pixel halo varies each square's size by its grid position.
/// This reproduces that one factor; density, motion and opacity are separate.
pub fn pixel_cell_size(column: u32, row: u32, grid_spacing: f64) -> Option<f64> {
    if !grid_spacing.is_finite() || grid_spacing <= 0.0 { return None; }
    let phase = f64::from(row) * 0.63 + f64::from(column) * 1.71;
    Some(grid_spacing * (0.72 + 0.1 * (1.0 + phase.sin())))
}

#[no_mangle]
pub extern "C" fn rium_notch_pixel_cell_size(column: u32, row: u32, grid_spacing: f64) -> f64 {
    pixel_cell_size(column, row, grid_spacing).unwrap_or(f64::NAN)
}

/// Reference pixel halo evaluates its distance field at a distorted sample
/// position, while drawing each square at its undistorted grid position.
pub fn pixel_sample_position(x: f64, y: f64) -> Option<[f64; 2]> {
    if !x.is_finite() || !y.is_finite() { return None; }
    Some([
        x + 1.35 * (y * 0.23 + 1.054).sin() + 0.72 * (x * 0.071 - 0.578).sin(),
        y + 0.55 * (y * 0.17 - 0.374).sin() + 1.8 * (x * 0.052 + 0.782).sin(),
    ])
}

#[no_mangle]
pub extern "C" fn rium_notch_pixel_sample_x(x: f64, y: f64) -> f64 {
    pixel_sample_position(x, y).map(|point| point[0]).unwrap_or(f64::NAN)
}

#[no_mangle]
pub extern "C" fn rium_notch_pixel_sample_y(x: f64, y: f64) -> f64 {
    pixel_sample_position(x, y).map(|point| point[1]).unwrap_or(f64::NAN)
}

/// Five contour segments, center wash and three scaled Gaussian highlights.
// shortcut: the caller's exact arm and thickness mapping need visual comparison.
pub fn pixel_contour_field(x: f64, y: f64, width: f64, height: f64,
                           notch_width: f64, notch_height: f64, arm: f64, thickness: f64) -> Option<f64> {
    if ![x, y, width, height, notch_width, notch_height, arm, thickness].iter().all(|v| v.is_finite())
        || width <= 0.0 || height <= 0.0 || notch_width <= 0.0 || notch_height <= 0.0 || arm < 0.0 || thickness <= 0.0 {
        return None;
    }
    let reach = ((width - notch_width) / 2.0).max(0.0);
    let left = reach.max(22.0).min(width * 0.42);
    let right = width - left;
    let bottom = (height - 2.0).min(notch_height - 2.0).max(17.0);
    let segments = [
        ((left - 5.0 - arm).max(0.0), 2.0, left - 5.0, 2.0),
        (left, 7.0, left, bottom - 9.0),
        (left + 9.0, bottom, right - 9.0, bottom),
        (right, 7.0, right, bottom - 9.0),
        (right + 5.0, 2.0, (right + 5.0 + arm).min(width), 2.0),
    ];
    let distance_squared = |px: f64, py: f64| segments.iter().map(|&(ax, ay, bx, by)| {
        let (dx, dy) = (bx - ax, by - ay);
        let squared = dx * dx + dy * dy;
        let t = if squared > 0.0 { (((px - ax) * dx + (py - ay) * dy) / squared).clamp(0.0, 1.0) } else { 0.0 };
        (px - ax - dx * t).powi(2) + (py - ay - dy * t).powi(2)
    }).fold(f64::INFINITY, f64::min);
    let outline = 0.86 * (-distance_squared(x, y).sqrt() / (7.8 * thickness)).exp();
    let center = if x > reach + 7.0 && x < width - reach - 7.0 {
        0.98 * (-(y - (notch_height - 2.0)).powi(2) / (30.0 * thickness * thickness)).exp()
    } else { 0.0 };
    let mut field = outline.max(center);
    for index in 0..3 {
        let phase = (0.34 + f64::from(index) / 3.0).fract();
        let amplitude = 0.78 * (1.0 - phase).powi(2);
        if amplitude <= field { continue; }
        let scale_x = 1.0 + 0.32 * phase;
        let scale_y = 1.0 + 1.6 * (scale_x - 1.0);
        let sample_x = width / 2.0 + (x - width / 2.0) / scale_x;
        let sample_y = 2.0 + (y - 2.0) / scale_y;
        let highlight = amplitude * (-distance_squared(sample_x, sample_y) / (8.5 * thickness * thickness)).exp();
        field = field.max(highlight);
    }
    Some(field)
}

#[no_mangle]
pub extern "C" fn rium_notch_pixel_contour_field(x: f64, y: f64, width: f64, height: f64,
                                                   notch_width: f64, notch_height: f64, arm: f64, thickness: f64) -> f64 {
    pixel_contour_field(x, y, width, height, notch_width, notch_height, arm, thickness).unwrap_or(f64::NAN)
}

/// LegacyPixelatedNotchHalo scales its field before applying Bayer thresholds.
pub fn pixel_intensity_scale(intensity: f64) -> Option<f64> {
    if !intensity.is_finite() || !(0.0..=1.0).contains(&intensity) { return None; }
    Some(0.94 + 0.34 * intensity)
}

#[no_mangle]
pub extern "C" fn rium_notch_pixel_intensity_scale(intensity: f64) -> f64 {
    pixel_intensity_scale(intensity).unwrap_or(f64::NAN)
}

/// Bayer matrix and threshold/opacity transfer recovered from the pixel halo.
/// The caller supplies the halo's spatial field before the arm fade.
pub fn pixel_cell_opacity(column: u32, row: u32, field: f64, fade: f64) -> Option<f64> {
    if !field.is_finite() || !fade.is_finite() || field < 0.0 || !(0.0..=1.0).contains(&fade) { return None; }
    const BAYER: [u8; 64] = [
        0,48,12,60,3,51,15,63, 32,16,44,28,35,19,47,31,
        8,56,4,52,11,59,7,55, 40,24,36,20,43,27,39,23,
        2,50,14,62,1,49,13,61, 34,18,46,30,33,17,45,29,
        10,58,6,54,9,57,5,53, 42,26,38,22,41,25,37,21,
    ];
    let index = (((row.wrapping_add(1) & 7) * 8) + (column.wrapping_add(3) & 7)) as usize;
    let intensity = field * fade;
    if intensity <= 0.04 || intensity <= f64::from(BAYER[index]) * (0.54 / 64.0) { return Some(0.0); }
    Some((0.24 + 0.84 * intensity).min(1.0) * fade.powf(0.72))
}

#[no_mangle]
pub extern "C" fn rium_notch_pixel_cell_opacity(column: u32, row: u32, field: f64, fade: f64) -> f64 {
    pixel_cell_opacity(column, row, field, fade).unwrap_or(f64::NAN)
}

/// LegacyPixelatedNotchHalo.armFade: blend symmetric horizontal edge fades
/// into a vertical fade. `arm_run == None` is the reference's optional branch.
pub fn pixel_arm_fade(x: f64, y: f64, width: f64, contour_height: f64,
                      arm_reach: f64, arm_run: Option<f64>) -> Option<f64> {
    if !x.is_finite() || !y.is_finite() || !width.is_finite() || !contour_height.is_finite()
        || !arm_reach.is_finite() || width < 0.0 || contour_height < 0.0
        || arm_run.is_some_and(|run| !run.is_finite() || run < 0.0) { return None; }
    let (start, ramp) = match arm_run {
        Some(run) => {
            let shoulder = arm_reach.max(22.0).min(width * 0.42) - 5.0;
            ((shoulder - run).max(0.0), (run * 0.18).clamp(12.0, 28.0))
        }
        None => (0.0, (arm_reach * 0.34).max(28.0).min(width * 0.22)),
    };
    let ramp = ramp.max(0.001);
    let smooth = |value: f64| {
        let t = value.clamp(0.0, 1.0);
        t * t * (3.0 - 2.0 * t)
    };
    let across = smooth((x - start) / ramp) * smooth((width - x - start) / ramp);
    let above = contour_height * 0.26;
    let below = contour_height * 0.72;
    let down = smooth((y - above) / (below - above).max(0.001));
    Some(1.0 - (1.0 - across) * (1.0 - down))
}

#[no_mangle]
pub extern "C" fn rium_notch_pixel_arm_fade(x: f64, y: f64, width: f64, contour_height: f64,
                                            arm_reach: f64, arm_run: f64) -> f64 {
    pixel_arm_fade(x, y, width, contour_height, arm_reach,
                   if arm_run == -1.0 { None } else { Some(arm_run) }).unwrap_or(f64::NAN)
}

/// Independent impact overlay used by both copy and paste sweeps.
pub fn copy_impact_frame(elapsed: f64, reduce_motion: bool) -> Option<[f64; 7]> {
    if !elapsed.is_finite() || elapsed < 0.0 || elapsed >= 0.55 || reduce_motion { return None; }
    let progress = (elapsed / 0.42).min(1.0);
    let flash = 0.72 * (-elapsed / 0.075).exp();
    let moving = 0.42 * (1.0 - (-elapsed / 0.13).exp());
    Some([3.0 + 34.0 * progress, 2.0 + 20.0 * progress,
          0.72 * 0.62 * (1.0 - progress).powf(1.6),
          flash * 0.95, flash * 0.8, moving,
          0.72 * 0.9 * (1.0 - elapsed / 0.42).max(0.0)])
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_copy_impact_frame(elapsed: f64, reduced: i32, output: *mut f64) -> i32 {
    if output.is_null() || !(0..=1).contains(&reduced) { return -1; }
    let Some(values) = copy_impact_frame(elapsed, reduced == 1) else { return -1; };
    for (index, value) in values.iter().enumerate() { *output.add(index) = *value; }
    0
}

/// CopySweepGlow's center and fade, parameterized by the two travel times.
/// The reference keeps the reduced-motion light still at the center.
pub fn copy_sweep_frame(elapsed: f64, outward: f64, backward: f64, reduce_motion: bool) -> Option<[f64; 2]> {
    if !elapsed.is_finite() || !outward.is_finite() || !backward.is_finite()
        || elapsed < 0.0 || outward <= 0.0 || backward <= 0.0 { return None; }
    if reduce_motion {
        let fade = if elapsed < 0.3 { (elapsed / 0.08).min(1.0) }
            else { (1.0 - (elapsed - 0.3) / 0.22).max(0.0) };
        return Some([0.5, fade]);
    }
    let center = if elapsed <= outward { smoothstep((elapsed / outward).clamp(0.0, 1.0)) }
        else { 1.0 - smoothstep(((elapsed - outward) / backward).clamp(0.0, 1.0)) };
    let fade_in = (elapsed / 0.08).min(1.0);
    let fade_out = ((outward + backward - elapsed) / 0.14).clamp(0.0, 1.0);
    Some([center, fade_in.min(fade_out)])
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_copy_sweep_frame(elapsed: f64, outward: f64, backward: f64,
    reduce_motion: i32, output: *mut f64) -> i32 {
    if output.is_null() || !(0..=1).contains(&reduce_motion) { return -1; }
    let Some(values) = copy_sweep_frame(elapsed, outward, backward, reduce_motion == 1) else { return -1; };
    *output = values[0]; *output.add(1) = values[1];
    0
}

/// Outbound CopySweepGlow sends two crests from the center to the edges.
/// The bright crest uses the main clock; its wider band is delayed separately.
pub fn paste_sweep_frame(elapsed: f64, travel: f64, reduce_motion: bool) -> Option<[f64; 3]> {
    if !elapsed.is_finite() || !travel.is_finite() || elapsed < 0.0 || travel <= 0.045 { return None; }
    if reduce_motion {
        let fade = if elapsed < 0.3 { (elapsed / 0.08).min(1.0) }
            else { (1.0 - (elapsed - 0.3) / 0.22).max(0.0) };
        return Some([0.5, 0.5, fade]);
    }
    let progress = ((elapsed - 0.045) / (travel - 0.045)).clamp(0.0, 1.0);
    let eased = 1.0 - (1.0 - progress).powi(2);
    let fade = (elapsed / 0.08).min(1.0).min(((travel - elapsed) / 0.14).clamp(0.0, 1.0));
    Some([0.5 - 0.5 * eased, 0.5 + 0.5 * eased, fade])
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_paste_sweep_frame(elapsed: f64, travel: f64,
    reduce_motion: i32, output: *mut f64) -> i32 {
    if output.is_null() || !(0..=1).contains(&reduce_motion) { return -1; }
    let Some(values) = paste_sweep_frame(elapsed, travel, reduce_motion == 1) else { return -1; };
    for (index, value) in values.iter().enumerate() { *output.add(index) = *value; }
    0
}

/// Half-width, line width, blur and opacity of the outbound center band.
/// The two crests have a separate delayed clock; this band uses the main one.
pub fn paste_sweep_center_band(elapsed: f64, travel: f64, reduce_motion: bool) -> Option<[f64; 4]> {
    if !elapsed.is_finite() || !travel.is_finite() || elapsed < 0.0 || travel <= 0.045 { return None; }
    let progress = if reduce_motion { 0.0 } else { ((elapsed - 0.045) / (travel - 0.045)).clamp(0.0, 1.0) };
    let intensity = (1.0 - progress).powi(12);
    Some([0.06 + 0.1 * intensity, 9.0 + 11.0 * intensity, 3.0 + 5.0 * intensity,
          if intensity > 0.01 { intensity } else { 0.0 }])
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_paste_center_band(elapsed: f64, travel: f64,
    reduce_motion: i32, output: *mut f64) -> i32 {
    if output.is_null() || !(0..=1).contains(&reduce_motion) { return -1; }
    let Some(values) = paste_sweep_center_band(elapsed, travel, reduce_motion == 1) else { return -1; };
    for (index, value) in values.iter().enumerate() { *output.add(index) = *value; }
    0
}

/// Reference StatusTextSweep traverses from -1 to 1 every 0.82 seconds.
pub fn agent_status_sweep(time: f64, reduce_motion: bool) -> Option<f64> {
    if !time.is_finite() || time < 0.0 { return None; }
    Some(if reduce_motion { 0.46 } else { (time % 0.82) / 0.82 * 2.0 - 1.0 })
}

#[no_mangle]
pub extern "C" fn rium_agent_status_sweep(time: f64, reduce_motion: i32) -> f64 {
    if !(0..=1).contains(&reduce_motion) { return f64::NAN; }
    agent_status_sweep(time, reduce_motion == 1).unwrap_or(f64::NAN)
}

/// Murmur's discrete reveal timeline: elapsed seconds, reference character
/// count and mosaic shape. A negative shape means that no mosaic is drawn.
pub fn murmur_pixel_duration(character_count: i32) -> Option<f64> {
    if !(0..=4096).contains(&character_count) { return None; }
    if character_count == 0 { return Some(0.0); }
    if character_count <= 2 { return Some(2.0 / 15.0); }
    Some(2.0 / 15.0 + (1.566667 - 2.0 / 15.0) * f64::from(character_count - 1) / 22.0)
}

#[no_mangle]
pub extern "C" fn rium_murmur_pixel_duration(character_count: i32) -> f64 {
    murmur_pixel_duration(character_count).unwrap_or(f64::NAN)
}

fn murmur_normalized_time(elapsed: f64, character_count: i32) -> Option<f64> {
    if !elapsed.is_finite() || elapsed < 0.0 || murmur_pixel_duration(character_count).is_none() { return None; }
    Some(if elapsed <= 2.0 / 15.0 { elapsed }
        else if character_count <= 2 { 1.6 }
        else { 2.0 / 15.0 + (elapsed - 2.0 / 15.0) * 22.0 / f64::from(character_count - 1) })
}

pub fn murmur_pixel_scale(elapsed: f64, character_count: i32, reduce_motion: bool) -> Option<f64> {
    let time = murmur_normalized_time(elapsed, character_count)?;
    if reduce_motion || character_count == 0 { return Some(1.0); }
    Some(1.0 + 0.2 * (1.0 - smoothstep(time / 1.376)))
}

#[no_mangle]
pub extern "C" fn rium_murmur_pixel_scale(elapsed: f64, character_count: i32, reduce_motion: i32) -> f64 {
    if !(0..=1).contains(&reduce_motion) { return f64::NAN; }
    murmur_pixel_scale(elapsed, character_count, reduce_motion == 1).unwrap_or(f64::NAN)
}

pub fn murmur_pixel_frame(elapsed: f64, character_count: i32, reduce_motion: bool) -> Option<[i32; 3]> {
    let normalized = murmur_normalized_time(elapsed, character_count)?;
    if reduce_motion || character_count == 0 { return Some([23, -1, 0]); }
    const FRAMES: [(f64, i32, i32, i32); 23] = [
        (0.0, 0, 0, 248), (0.066667, 0, 11, 326), (0.133333, 1, 1, 410), (0.216667, 2, 2, 482),
        (0.283333, 3, 3, 572), (0.35, 4, 4, 608), (0.416667, 5, 5, 752), (0.5, 7, 3, 914),
        (0.566667, 8, 10, 968), (0.633333, 10, 6, 1056), (0.716667, 12, 3, 1128),
        (0.783333, 13, 7, 1218), (0.866667, 15, 10, 1308), (0.916667, 16, -1, 0),
        (1.0, 18, 7, 1416), (1.066667, 19, 7, 1542), (1.133333, 20, 3, 1614),
        (1.216667, 20, -1, 0), (1.283333, 21, 8, 1686), (1.35, 22, 8, 1686),
        (1.416667, 22, 9, 1758), (1.5, 22, -1, 0), (1.566667, 23, -1, 0),
    ];
    let frame = FRAMES.iter().rev().find(|(start, _, _, _)| *start <= normalized + 0.00001)?;
    Some([frame.1, frame.2, frame.3])
}

#[no_mangle]
pub unsafe extern "C" fn rium_murmur_pixel_frame(elapsed: f64, character_count: i32, reduce_motion: i32, output: *mut i32) -> i32 {
    if output.is_null() || !(0..=1).contains(&reduce_motion) { return -1; }
    let Some(frame) = murmur_pixel_frame(elapsed, character_count, reduce_motion == 1) else { return -1; };
    std::ptr::copy_nonoverlapping(frame.as_ptr(), output, frame.len());
    0
}

/// shortcut: cosine approximates the reference's repeating ease-in-out until frame comparison.
pub fn agent_cursor_opacity(elapsed: f64, reduce_motion: bool) -> Option<f64> {
    if !elapsed.is_finite() || elapsed < 0.0 { return None; }
    Some(if reduce_motion { 1.0 } else {
        0.55 - 0.45 * (std::f64::consts::TAU * (elapsed % 1.0)).cos()
    })
}

#[no_mangle]
pub extern "C" fn rium_agent_cursor_opacity(elapsed: f64, reduce_motion: i32) -> f64 {
    if !(0..=1).contains(&reduce_motion) { return f64::NAN; }
    agent_cursor_opacity(elapsed, reduce_motion == 1).unwrap_or(f64::NAN)
}

/// Pseudorandom choices within the reference's idle and action token ranges.
pub fn agent_token_sample(seed: u64, index: u64) -> [f64; 4] {
    let mut value = seed ^ index.wrapping_mul(0x9e37_79b9_7f4a_7c15);
    value ^= value >> 30;
    value = value.wrapping_mul(0xbf58_476d_1ce4_e5b9);
    value ^= value >> 27;
    value = value.wrapping_mul(0x94d0_49bb_1331_11eb);
    value ^= value >> 31;
    let a = (value & 0xffff) as f64 / 65535.0;
    let b = ((value >> 16) & 0xffff) as f64 / 65535.0;
    let c = ((value >> 32) & 0xffff) as f64 / 65535.0;
    [1.1 + 0.7 * a, 2.0 + 4.0 * b, 2.0 + 6.5 * c, (3 + (value >> 48) % 4) as f64]
}

#[no_mangle]
pub unsafe extern "C" fn rium_agent_token_sample(seed: u64, index: u64, output: *mut f64) -> i32 {
    if output.is_null() { return -1; }
    for (i, value) in agent_token_sample(seed, index).iter().enumerate() { *output.add(i) = *value; }
    0
}

#[cfg(test)]
mod shell_corner_tests {
    use super::{agent_status_sweep, agent_token_sample, copy_sweep_frame, floating_island_anchor, floating_island_card_offset, floating_island_compact_size, floating_island_corner, floating_island_normalized, floating_island_top_inset, paste_sweep_center_band, paste_sweep_frame, pixel_arm_fade, pixel_cell_opacity, pixel_cell_size, pixel_sample_position, rium_home_hour_photo, shell_contour_metrics, shell_contour_y, shell_corner_geometry};

    #[test]
    fn agent_cursor_breathes_and_rejects_invalid_time() {
        use super::{agent_cursor_opacity, rium_agent_cursor_opacity};
        assert!((agent_cursor_opacity(0.0, false).unwrap() - 0.1).abs() < 1e-12);
        assert_eq!(agent_cursor_opacity(0.5, false), Some(1.0));
        assert!((agent_cursor_opacity(1.0, false).unwrap() - 0.1).abs() < 1e-12);
        assert_eq!(agent_cursor_opacity(0.25, true), Some(1.0));
        assert_eq!(agent_cursor_opacity(-1.0, false), None);
        assert_eq!(agent_cursor_opacity(f64::NAN, false), None);
        assert!(rium_agent_cursor_opacity(0.0, 2).is_nan());
    }

    #[test]
    fn band_fold_uses_reference_transform_and_rejects_invalid_input() {
        use super::band_fold_frame;
        assert_eq!(band_fold_frame(0.0), Some([1.0, 1.0, 0.0, 1.0]));
        assert_eq!(band_fold_frame(0.5), Some([0.85, 0.94, 3.5, 0.5]));
        assert_eq!(band_fold_frame(1.0), Some([0.7, 0.88, 7.0, 0.0]));
        assert!(band_fold_frame(f64::NAN).is_none());
        assert!(band_fold_frame(f64::MAX).is_none());
    }

    #[test]
    fn agent_peek_entrance_respects_reduced_motion() {
        use super::{agent_peek_entrance_scale, rium_agent_peek_entrance_scale};
        assert_eq!(agent_peek_entrance_scale(false, false), 0.82);
        assert_eq!(agent_peek_entrance_scale(true, false), 1.0);
        assert_eq!(agent_peek_entrance_scale(false, true), 1.0);
        assert!(rium_agent_peek_entrance_scale(2, 0).is_nan());
    }

    #[test]
    fn agent_status_wait_uses_the_remaining_lead_time() {
        use super::rium_agent_peek_status_wait_ns;
        assert_eq!(rium_agent_peek_status_wait_ns(0.0, 1, 0), 80_000_000);
        assert_eq!(rium_agent_peek_status_wait_ns(0.0, 0, 0), 100_000_000);
        assert_eq!(rium_agent_peek_status_wait_ns(0.04, 1, 0), 40_000_000);
        assert_eq!(rium_agent_peek_status_wait_ns(0.11, 1, 0), 0);
        assert_eq!(rium_agent_peek_status_wait_ns(0.0, 0, 1), 0);
        assert_eq!(rium_agent_peek_status_wait_ns(f64::NAN, 1, 0), 0);
    }

    #[test]
    fn paste_glyph_uses_reference_endpoints_and_validates_ffi() {
        use super::{paste_glyph_frame, rium_paste_glyph_frame};
        assert_eq!(paste_glyph_frame(false, false), [-5.2, 0.4]);
        assert_eq!(paste_glyph_frame(true, false), [0.5, 1.0]);
        assert_eq!(paste_glyph_frame(true, true), [-5.2, 1.0]);
        let mut frame = [0.0; 2];
        unsafe {
            assert_eq!(rium_paste_glyph_frame(1, 0, frame.as_mut_ptr()), 0);
            assert_eq!(frame, [0.5, 1.0]);
            assert_eq!(rium_paste_glyph_frame(2, 0, frame.as_mut_ptr()), -1);
            assert_eq!(rium_paste_glyph_frame(1, 1, std::ptr::null_mut()), -1);
        }
    }

    #[test]
    fn thinking_orb_projects_animated_bounded_particles() {
        use super::thinking_orb_particles;
        let first = thinking_orb_particles(24.0, 24.0, 0.0).unwrap();
        let later = thinking_orb_particles(24.0, 24.0, 0.15).unwrap();
        assert_eq!(first.len(), 180);
        assert!(first.iter().all(|p| p[0].is_finite() && p[1].is_finite() && (0.26..=1.02).contains(&p[2]) && (0.2..=0.98).contains(&p[3]) && (0.0..=1.0).contains(&p[4])));
        assert!(first.iter().zip(later.iter()).any(|(a, b)| (a[0] - b[0]).abs() > 0.01 || (a[1] - b[1]).abs() > 0.01));
        for (index, particle) in first.iter().enumerate() {
            let expected = particle[4] > 0.82 && (index / 18 + index % 18) % 5 == 0;
            assert_eq!(particle[5] > 0.0, expected);
        }
        assert!(first.iter().enumerate().any(|(index, p)| index % 18 != 0 && p[5] > 0.0));
        assert!(thinking_orb_particles(0.0, 24.0, 0.0).is_none());
        assert!(thinking_orb_particles(24.0, 24.0, f64::NAN).is_none());
    }

    #[test]
    fn success_orb_uses_distinct_particle_count_and_motion() {
        use super::success_orb_particles;
        let first = success_orb_particles(24.0, 24.0, 0.0).unwrap();
        let later = success_orb_particles(24.0, 24.0, 0.25).unwrap();
        assert_eq!(first.len(), 153);
        assert!(first.iter().all(|p| p[0].is_finite() && p[1].is_finite() && (0.25..=0.97).contains(&p[2]) && (0.22..=1.0).contains(&p[3])));
        assert!(first.iter().zip(later.iter()).any(|(a, b)| (a[0] - b[0]).abs() > 0.01 || (a[1] - b[1]).abs() > 0.01));
        assert!(success_orb_particles(24.0, -1.0, 0.0).is_none());
        assert!(success_orb_particles(24.0, 24.0, f64::INFINITY).is_none());
    }

    #[test]
    fn success_checkmark_has_reference_path_and_rejects_invalid_bounds() {
        use super::success_checkmark_points;
        let points = success_checkmark_points(100.0, 100.0).unwrap();
        for (point, expected) in points.iter().zip([[4.0, 55.0], [38.0, 90.0], [98.0, 12.0]]) {
            assert!((point[0] - expected[0]).abs() < 1e-9 && (point[1] - expected[1]).abs() < 1e-9);
        }
        assert!(success_checkmark_points(0.0, 10.0).is_none());
        assert!(success_checkmark_points(10.0, f64::NAN).is_none());
    }

    #[test]
    fn hover_cooldown_uses_only_valid_elapsed_time() {
        use super::hover_reopen_wait;
        assert_eq!(hover_reopen_wait(0.0), Some(0.34));
        assert!((hover_reopen_wait(0.1).unwrap() - 0.24).abs() < 1e-9);
        assert_eq!(hover_reopen_wait(0.33), Some(0.0));
        assert_eq!(hover_reopen_wait(-1.0), None);
        assert_eq!(hover_reopen_wait(f64::NAN), None);
    }

    #[test]
    fn home_editing_allows_a_longer_hover_exit() {
        assert_eq!(super::rium_notch_hover_close_delay(0.05, 0), 0.1);
        assert_eq!(super::rium_notch_hover_close_delay(0.4, 0), 0.4);
        assert_eq!(super::rium_notch_hover_close_delay(0.4, 1), 3.0);
        assert_eq!(super::rium_notch_hover_close_delay(3.5, 1), 3.5);
    }

    #[test]
    fn agent_switcher_wraps_in_both_directions() {
        use super::rium_notch_agent_switcher_index as step;
        assert_eq!(step(3, 0, -1), 2);
        assert_eq!(step(3, 2, 1), 0);
        assert_eq!(step(3, -1, 1), 1);
        assert_eq!(step(0, -1, 1), -1);
        assert_eq!(step(3, 0, 2), -1);
    }

    #[test]
    fn pixel_field_samples_move_without_moving_the_grid() {
        let [x, y] = pixel_sample_position(100.0, 20.0).unwrap();
        assert!((x - (100.0 + 1.35 * (20.0_f64 * 0.23 + 1.054).sin()
            + 0.72 * (100.0_f64 * 0.071 - 0.578).sin())).abs() < 1e-12);
        assert!((y - (20.0 + 0.55 * (20.0_f64 * 0.17 - 0.374).sin()
            + 1.8 * (100.0_f64 * 0.052 + 0.782).sin())).abs() < 1e-12);
        assert!(pixel_sample_position(f64::INFINITY, 0.0).is_none());
    }

    #[test]
    fn pixel_grid_keeps_its_spacing_on_wide_displays() {
        assert_eq!(super::pixel_grid_columns(780.0, 3.0), Some(260));
        assert_eq!(super::pixel_grid_columns(1512.0, 3.0), Some(504));
        assert_eq!(super::pixel_grid_columns(1513.0, 3.0), Some(505));
        assert_eq!(super::pixel_grid_columns(20_000.0, 3.0), Some(4096));
        assert_eq!(super::pixel_grid_columns(0.0, 3.0), None);
        assert_eq!(super::pixel_grid_columns(100.0, f64::NAN), None);
    }

    #[test]
    fn pixel_bounds_include_scaled_highlights_and_stay_on_screen() {
        let bounds = super::pixel_field_bounds(1000.0, 100.0, 200.0, 32.0, 130.0, 1.0).unwrap();
        assert!(bounds[0] < 265.0 && bounds[1] > 735.0 && bounds[2] == 0.0 && bounds[3] > 60.0);
        assert!((bounds[0] + bounds[1] - 1000.0).abs() < 1e-12);
        let clipped = super::pixel_field_bounds(500.0, 40.0, 180.0, 32.0, 440.0, 2.0).unwrap();
        assert_eq!(clipped, [0.0, 500.0, 0.0, 40.0]);
        assert!(super::pixel_field_bounds(f64::NAN, 100.0, 200.0, 32.0, 130.0, 1.0).is_none());
    }

    #[test]
    fn pixel_field_uses_both_arms_and_the_center_wash() {
        let field = |x, y| super::pixel_contour_field(x, y, 1000.0, 100.0, 200.0, 32.0, 130.0, 1.0).unwrap();
        assert!((field(350.0, 2.0) - 0.86).abs() < 1e-12);
        assert!((field(650.0, 2.0) - field(350.0, 2.0)).abs() < 1e-12);
        assert!((field(500.0, 30.0) - 0.98).abs() < 1e-12);
        assert!(field(500.0, 70.0) < 0.01);
        assert!(field(389.12, 20.0) > 0.30);
        assert!((field(389.12, 20.0) - field(610.88, 20.0)).abs() < 1e-12);
        let capped = super::pixel_contour_field(430.0, 30.0, 1000.0, 100.0, 100.0, 32.0, 130.0, 1.0).unwrap();
        assert!((capped - 0.86).abs() < 1e-12);
        assert!(super::pixel_contour_field(0.0, 0.0, 1000.0, 100.0, 200.0, 32.0, 130.0, 0.0).is_none());
    }

    #[test]
    fn pixel_dither_uses_reference_offsets_threshold_and_transfer() {
        assert!((super::pixel_intensity_scale(0.0).unwrap() - 0.94).abs() < 1e-12);
        assert!((super::pixel_intensity_scale(1.0).unwrap() - 1.28).abs() < 1e-12);
        assert!(super::pixel_intensity_scale(-0.01).is_none());
        assert!(super::pixel_intensity_scale(f64::NAN).is_none());
        assert_eq!(pixel_cell_opacity(0, 0, 0.20, 1.0), Some(0.0));
        assert!((pixel_cell_opacity(0, 0, 0.30, 1.0).unwrap() - 0.492).abs() < 1e-12);
        assert_eq!(pixel_cell_opacity(8, 8, 0.20, 1.0), Some(0.0));
        assert_eq!(pixel_cell_opacity(0, 0, 0.30, 0.0), Some(0.0));
        assert!(pixel_cell_opacity(0, 0, f64::NAN, 1.0).is_none());
    }

    #[test]
    fn pixel_fade_is_symmetric_and_extends_downward() {
        let fade = |x, y| pixel_arm_fade(x, y, 1000.0, 32.0, 380.0, Some(120.0)).unwrap();
        assert_eq!(fade(0.0, 0.0), 0.0);
        assert_eq!(fade(500.0, 0.0), 1.0);
        assert_eq!(fade(0.0, 32.0), 1.0);
        assert!((fade(270.0, 0.0) - fade(730.0, 0.0)).abs() < 1e-12);
        assert!(pixel_arm_fade(0.0, 0.0, 1000.0, 32.0, 380.0, Some(f64::NAN)).is_none());
        assert!(pixel_arm_fade(0.0, 0.0, 1000.0, 32.0, 380.0, None).is_some());
    }

    #[test]
    fn pixel_size_uses_reference_grid_phase_and_stays_bounded() {
        assert!((pixel_cell_size(0, 0, 3.0).unwrap() - 2.46).abs() < 1e-12);
        assert!((pixel_cell_size(1, 0, 3.0).unwrap() - 3.0 * (0.82 + 0.1 * 1.71_f64.sin())).abs() < 1e-12);
        assert!((pixel_cell_size(0, 1, 3.0).unwrap() - 3.0 * (0.82 + 0.1 * 0.63_f64.sin())).abs() < 1e-12);
        for column in 0..100 {
            for row in 0..10 {
                let size = pixel_cell_size(column, row, 3.0).unwrap();
                assert!(size >= 2.16 && size <= 2.76);
            }
        }
        assert!(pixel_cell_size(0, 0, f64::NAN).is_none());
        assert!(pixel_cell_size(0, 0, 0.0).is_none());
    }

    #[test]
    fn exterior_style_follows_symmetric_shell_contour() {
        let sample = |x| shell_contour_y(x, 240.0, 32.0, 16.0, 20.0).unwrap();
        assert_eq!(sample(-1.0), 0.0);
        assert!(sample(0.0).abs() < 0.001);
        assert!(sample(10.0) > 0.0 && sample(10.0) < 20.0);
        assert!(sample(25.0) > 16.0 && sample(25.0) < 32.0);
        assert_eq!(sample(120.0), 32.0);
        for x in [0.0, 10.0, 20.0, 25.0, 50.0] {
            assert!((sample(x) - sample(240.0 - x)).abs() < 1e-9);
        }
        assert!(shell_contour_y(f64::NAN, 240.0, 32.0, 16.0, 20.0).is_none());
    }

    #[test]
    fn home_hour_photo_uses_lower_anchor_and_rejects_invalid_hours() {
        assert_eq!(rium_home_hour_photo(0), 0);
        assert_eq!(rium_home_hour_photo(1), 0);
        assert_eq!(rium_home_hour_photo(2), 2);
        assert_eq!(rium_home_hour_photo(23), 22);
        assert_eq!(rium_home_hour_photo(24), -1);
        assert_eq!(rium_home_hour_photo(-1), -1);
    }

    #[test]
    fn token_sample_is_deterministic_and_stays_in_recovered_ranges() {
        for index in 0..1000 {
            let a = agent_token_sample(42, index);
            assert_eq!(a, agent_token_sample(42, index));
            assert!((1.1..=1.8).contains(&a[0]));
            assert!((2.0..=6.0).contains(&a[1]));
            assert!((2.0..=8.5).contains(&a[2]));
            assert!((3.0..=6.0).contains(&a[3]) && a[3].fract() == 0.0);
        }
    }

    #[test]
    fn status_sweep_repeats_and_reduced_motion_is_stationary() {
        assert_eq!(agent_status_sweep(0.0, false), Some(-1.0));
        assert!(agent_status_sweep(0.41, false).unwrap().abs() < 1e-9);
        assert_eq!(agent_status_sweep(0.82, false), Some(-1.0));
        assert_eq!(agent_status_sweep(10.0, true), Some(0.46));
        assert!(agent_status_sweep(f64::NAN, false).is_none());
    }

    #[test]
    fn murmur_reveal_uses_discrete_frames_and_settles() {
        use super::{murmur_pixel_duration, murmur_pixel_frame, murmur_pixel_scale, rium_murmur_pixel_frame};
        assert_eq!(murmur_pixel_frame(0.0, 23, false), Some([0, 0, 248]));
        assert_eq!(murmur_pixel_frame(0.5, 23, false), Some([7, 3, 914]));
        assert_eq!(murmur_pixel_frame(0.916667, 23, false), Some([16, -1, 0]));
        assert_eq!(murmur_pixel_frame(1.566667, 23, false), Some([23, -1, 0]));
        assert_eq!(murmur_pixel_frame(10.0, 23, false), Some([23, -1, 0]));
        assert_eq!(murmur_pixel_frame(0.0, 23, true), Some([23, -1, 0]));
        assert_eq!(murmur_pixel_frame(0.0, 0, false), Some([23, -1, 0]));
        assert_eq!(murmur_pixel_frame(0.14, 1, false), Some([23, -1, 0]));
        assert_eq!(murmur_pixel_frame(0.4, 5, false), Some([23, -1, 0]));
        assert_eq!(murmur_pixel_scale(0.0, 23, false), Some(1.2));
        assert_eq!(murmur_pixel_scale(2.0, 23, false), Some(1.0));
        assert_eq!(murmur_pixel_scale(0.0, 23, true), Some(1.0));
        assert!((murmur_pixel_duration(23).unwrap() - 1.566667).abs() < 1e-9);
        assert!(murmur_pixel_duration(5).unwrap() < 0.4);
        assert!(murmur_pixel_frame(-0.1, 5, false).is_none());
        assert!(murmur_pixel_frame(f64::NAN, 5, false).is_none());
        assert!(murmur_pixel_duration(-1).is_none());
        let mut output = [-9, -9, -9];
        unsafe {
            assert_eq!(rium_murmur_pixel_frame(0.5, 23, 0, output.as_mut_ptr()), 0);
            assert_eq!(output, [7, 3, 914]);
            assert_eq!(rium_murmur_pixel_frame(0.5, 23, 2, output.as_mut_ptr()), -1);
            assert_eq!(output, [7, 3, 914]);
            assert_eq!(rium_murmur_pixel_frame(0.5, 23, 0, std::ptr::null_mut()), -1);
        }
    }

    #[test]
    fn recovered_shell_states_select_distinct_geometry() {
        for state in [0, 1, 2, 4] {
            assert_eq!(shell_corner_geometry(state), Some([16.0, 20.0]));
        }
        assert_eq!(shell_corner_geometry(3), Some([8.0, 12.0]));
        assert_eq!(shell_corner_geometry(5), Some([28.0, 36.0]));
        assert_eq!(shell_corner_geometry(-1), None);
        assert_eq!(shell_corner_geometry(6), None);
    }

    #[test]
    fn floating_corner_clamps_radius_and_blends_reference_control_points() {
        let capsule = floating_island_corner(28.0, 64.0, 17.0).unwrap();
        assert_eq!(capsule[0], [8.5, 0.0]);
        assert_eq!(capsule[9], [0.0, 8.5]);
        let wide = floating_island_corner(28.0, 200.0, 120.0).unwrap();
        assert!((wide[0][0] - 28.0 * 1.52866483).abs() < 1e-9);
        assert!((wide[9][1] - wide[0][0]).abs() < 1e-9);
        assert_eq!(floating_island_corner(0.0, 30.0, 20.0), Some([[0.0; 2]; 10]));
        assert!(floating_island_corner(2.0, 0.0, 20.0).is_none());
        assert!(floating_island_corner(f64::NAN, 30.0, 20.0).is_none());
    }

    #[test]
    fn floating_compact_sizes_fit_content_and_screen() {
        assert_eq!(floating_island_compact_size(1440.0, 36.0, 0), Some([96.0, 24.0]));
        assert_eq!(floating_island_compact_size(1440.0, 36.0, 2), Some([400.0, 38.0]));
        assert_eq!(floating_island_compact_size(1440.0, 36.0, 3), Some([250.0, 24.0]));
        assert_eq!(floating_island_compact_size(1440.0, 36.0, 4), Some([296.0, 24.0]));
        assert_eq!(floating_island_compact_size(1440.0, 36.0, 5), Some([330.0, 24.0]));
        assert_eq!(floating_island_compact_size(300.0, 36.0, 2), Some([284.0, 38.0]));
        assert!(floating_island_compact_size(1440.0, f64::NAN, 0).is_none());
        assert!(floating_island_compact_size(16.0, 36.0, 0).is_none());
        assert_eq!(floating_island_compact_size(1440.0, 36.0, 6), Some([540.0, 120.0]));
        assert_eq!(floating_island_compact_size(300.0, 36.0, 6), Some([284.0, 120.0]));
        assert!(floating_island_compact_size(1440.0, 36.0, 7).is_none());
    }

    #[test]
    fn floating_island_position_is_bounded_and_round_trips() {
        let inset = floating_island_top_inset(36.0).unwrap();
        assert_eq!(inset, 5.5);
        let anchor = floating_island_anchor(-1440.0, 1440.0, 900.0, inset, false, 0.25, 0.75).unwrap();
        let normalized = floating_island_normalized(-1440.0, 1440.0, 900.0, inset, false, anchor[0], anchor[1]).unwrap();
        assert!((normalized[0] - 0.25).abs() < 1e-12 && (normalized[1] - 0.75).abs() < 1e-12);
        assert_eq!(floating_island_normalized(0.0, 80.0, 400.0, 0.0, false, -100.0, 900.0), Some([0.5, 0.0]));
        assert_eq!(floating_island_anchor(0.0, 1440.0, 900.0, inset, true, 0.5, 1.0), Some([720.0, inset]));
        assert!(floating_island_anchor(0.0, 1440.0, 900.0, inset, false, 1.1, 0.0).is_none());
        assert!(floating_island_top_inset(f64::NAN).is_none());
    }

    #[test]
    fn floating_geometry_uses_virtual_fallback_without_a_usable_top_inset() {
        let virtual_geometry = super::rium_notch_uses_virtual_geometry;
        assert_eq!(virtual_geometry(900.0, 36.0), 0);
        assert_eq!(virtual_geometry(900.0, 224.99), 0);
        for top in [0.0, -1.0, 225.0, f64::INFINITY, f64::NAN] {
            assert_eq!(virtual_geometry(900.0, top), 1);
        }
        assert_eq!(virtual_geometry(0.0, 36.0), 1);
        assert_eq!(virtual_geometry(f64::INFINITY, 36.0), 1);
    }

    #[test]
    fn island_card_stays_on_screen_and_moves_clear_of_camera() {
        let camera = Some([650.0, 790.0, 868.0]);
        assert_eq!(floating_island_card_offset(0.0, 1440.0, 900.0, 40.0, 400.0, 6.0, true, camera), Some([168.0, 0.0]));
        assert_eq!(floating_island_card_offset(0.0, 1440.0, 900.0, 720.0, 400.0, 6.0, true, camera), Some([0.0, 30.0]));
        assert_eq!(floating_island_card_offset(0.0, 1440.0, 900.0, 446.0, 400.0, 6.0, true, camera), Some([0.0, 0.0]));
        assert_eq!(floating_island_card_offset(0.0, 1440.0, 900.0, 448.0, 400.0, 6.0, true, camera), Some([0.0, 15.0]));
        assert_eq!(floating_island_card_offset(0.0, 1440.0, 900.0, 720.0, 400.0, 6.0, false, camera), Some([0.0, 0.0]));
        assert!(floating_island_card_offset(0.0, 0.0, 900.0, 720.0, 400.0, 6.0, true, camera).is_none());
    }

    #[test]
    fn island_card_offset_ffi_validates_flags_and_output() {
        use super::rium_notch_floating_card_offset;
        let mut offset = [0.0; 2];
        unsafe {
            assert_eq!(rium_notch_floating_card_offset(0.0, 1440.0, 900.0, 720.0, 400.0, 6.0,
                1, 1, 650.0, 790.0, 868.0, offset.as_mut_ptr()), 0);
            assert_eq!(offset, [0.0, 30.0]);
            assert_eq!(rium_notch_floating_card_offset(0.0, 1440.0, 900.0, 720.0, 400.0, 6.0,
                2, 0, 0.0, 0.0, 0.0, offset.as_mut_ptr()), -1);
            assert_eq!(rium_notch_floating_card_offset(0.0, 1440.0, 900.0, 720.0, 400.0, 6.0,
                1, 0, 0.0, 0.0, 0.0, std::ptr::null_mut()), -1);
        }
    }

    #[test]
    fn shoulder_and_bottom_radius_follow_reference_rect_rules() {
        for (input, expected) in [
            ([205.0, 32.0, 10.0, 10.0], [10.0, 10.0, 3.4, 7.8]),
            ([890.0, 210.0, 28.0, 10.0], [10.0, 28.0, 3.4, 21.84]),
            ([240.0, 32.0, 16.0, 20.0], [20.0, 16.0, 4.4, 12.48]),
            ([200.0, 90.0, 28.0, 36.0], [36.0, 28.0, 7.92, 21.84]),
            ([10.0, 50.0, 16.0, 20.0], [5.0, 0.0, 1.1, 0.0]),
        ] {
            let actual = shell_contour_metrics(input[0], input[1], input[2], input[3]).unwrap();
            for i in 0..4 { assert!((actual[i] - expected[i]).abs() < 1e-9); }
        }
        let left = shell_contour_y(5.0, 205.0, 32.0, 10.0, 10.0).unwrap();
        let right = shell_contour_y(200.0, 205.0, 32.0, 10.0, 10.0).unwrap();
        assert!(left > 0.8 && left < 1.0);
        assert!((left - right).abs() < 1e-9);
        assert!(shell_contour_metrics(f64::NAN, 32.0, 8.0, 0.0).is_none());
    }

    #[test]
    fn copy_impact_decays_and_reduced_motion_disables_it() {
        let start = super::copy_impact_frame(0.0, false).unwrap();
        assert_eq!(start[0..2], [3.0, 2.0]);
        assert!((start[3] - 0.684).abs() < 1e-12 && start[5] == 0.0);
        let later = super::copy_impact_frame(0.2, false).unwrap();
        assert!(later[0] > start[0] && later[3] < start[3] && later[5] > 0.0);
        assert_eq!(super::copy_impact_frame(0.42, false).unwrap()[2], 0.0);
        assert!(super::copy_impact_frame(0.55, false).is_none());
        assert!(super::copy_impact_frame(0.0, true).is_none());
        assert!(super::copy_impact_frame(f64::NAN, false).is_none());
    }

    #[test]
    fn copy_sweep_turns_around_and_reduced_motion_stays_centered() {
        assert_eq!(copy_sweep_frame(0.0, 0.34, 0.34, false), Some([0.0, 0.0]));
        assert_eq!(copy_sweep_frame(0.17, 0.34, 0.34, false), Some([0.5, 1.0]));
        assert_eq!(copy_sweep_frame(0.34, 0.34, 0.34, false), Some([1.0, 1.0]));
        let returning = copy_sweep_frame(0.51, 0.34, 0.34, false).unwrap();
        assert!((returning[0] - 0.5).abs() < 1e-9 && returning[1] == 1.0);
        assert_eq!(copy_sweep_frame(0.3, 0.34, 0.34, true), Some([0.5, 1.0]));
        let reduced_end = copy_sweep_frame(0.52, 0.34, 0.34, true).unwrap();
        assert_eq!(reduced_end[0], 0.5);
        assert!(reduced_end[1] < 1e-9);
        assert!(copy_sweep_frame(0.0, 0.0, 1.0, false).is_none());
    }

    #[test]
    fn paste_sweep_moves_symmetrically_outward() {
        assert_eq!(paste_sweep_frame(0.0, 0.42, false), Some([0.5, 0.5, 0.0]));
        let waiting = paste_sweep_frame(0.045, 0.42, false).unwrap();
        assert!((waiting[0] - 0.5).abs() < 1e-9 && (waiting[1] - 0.5).abs() < 1e-9);
        let middle = paste_sweep_frame(0.2325, 0.42, false).unwrap();
        assert!((middle[0] - 0.125).abs() < 1e-9);
        assert!((middle[1] - 0.875).abs() < 1e-9);
        let delayed_band = paste_sweep_frame(0.2325 - 0.07, 0.42, false).unwrap();
        assert!(delayed_band[0] > middle[0] && delayed_band[1] < middle[1]);
        let end = paste_sweep_frame(0.42, 0.42, false).unwrap();
        assert!(end[0].abs() < 1e-9 && (end[1] - 1.0).abs() < 1e-9 && end[2] == 0.0);
        let finished = paste_sweep_frame(0.49, 0.42, false).unwrap();
        assert!(finished[0].abs() < 1e-9 && (finished[1] - 1.0).abs() < 1e-9 && finished[2] == 0.0);
        assert_eq!(paste_sweep_frame(0.3, 0.42, true), Some([0.5, 0.5, 1.0]));
        assert!(paste_sweep_frame(0.1, 0.045, false).is_none());
    }

    #[test]
    fn paste_center_band_recedes_on_its_own_clock() {
        let start = paste_sweep_center_band(0.0, 0.42, false).unwrap();
        assert!((start[0] - 0.16).abs() < 1e-9 && start[1..] == [20.0, 8.0, 1.0]);
        let band = paste_sweep_center_band(0.1, 0.42, false).unwrap();
        assert!(band[0] > 0.06 && band[0] < 0.16 && band[3] > 0.01 && band[3] < 1.0);
        assert_eq!(paste_sweep_center_band(0.42, 0.42, false).unwrap()[3], 0.0);
        assert_eq!(paste_sweep_center_band(0.3, 0.42, true), Some(start));
        assert!(paste_sweep_center_band(f64::NAN, 0.42, false).is_none());
    }
}

/// Outward, non-contour wave radius and fade from the embedded edge shader.
/// Spatial noise and blending are computed separately by the renderer.
pub fn agent_screen_wave(elapsed: f64) -> Option<[f64; 2]> {
    if !elapsed.is_finite() || elapsed < 0.0 { return None; }
    let phase = ((elapsed - 0.1) / 2.25).clamp(0.0, 1.0);
    let radius = 1.05 * (1.0 - (1.0 - phase).powf(1.8))
        + 0.015 * (phase * PI).sin() * (1.0 - phase);
    Some([radius, 1.0 - smoothstep((elapsed - 1.5) / 1.1)])
}

/// Writes the normalized radius and opacity as two consecutive doubles.
#[no_mangle]
pub unsafe extern "C" fn rium_agent_screen_wave(elapsed: f64, output: *mut f64) -> i32 {
    if output.is_null() { return -1; }
    let Some(frame) = agent_screen_wave(elapsed) else { return -1; };
    *output = frame[0];
    *output.add(1) = frame[1];
    0
}

/// Reference EdgeWavePacer's four pulse categories and 60-second history.
/// Categories: running=0, asking=1, done=2, failed=3. Battery doubles the
/// per-category interval and halves the shared quota; low-power suppression
/// is checked by the caller. Returns None for malformed input.
pub fn agent_wave_admit(now: f64, kind: i32, active_agents: i32, battery: bool,
                        free: bool, history: &[(f64, i32)]) -> Option<bool> {
    if !now.is_finite() || !(0..=3).contains(&kind) || active_agents < 0
        || history.iter().any(|(at, k)| !at.is_finite() || *at > now || !(0..=3).contains(k)) {
        return None;
    }
    let recent: Vec<_> = history.iter().copied().filter(|(at, _)| now - *at <= 60.0).collect();
    if let Some(&(at, previous)) = recent.last() {
        if now - at < 1.2 && (kind != 1 || previous == 1) { return Some(false); }
    }
    if free { return Some(true); }
    let multiplier = if battery { 2.0 } else { 1.0 };
    let interval = match kind {
        0 if active_agents >= 3 => return Some(false),
        0 => 6.0,
        1 => 1.2,
        2 if active_agents >= 3 => 12.0,
        _ => 3.0,
    };
    if let Some(&(at, _)) = recent.iter().rev().find(|(_, previous)| *previous == kind) {
        if now - at < interval * multiplier { return Some(false); }
    }
    if kind == 0 && recent.iter().filter(|(_, previous)| *previous == 0).count() >= 3 { return Some(false); }
    let quota = (if active_agents < 3 { 6 } else { 3 }) / (if battery { 2 } else { 1 });
    if kind != 1 && recent.len() >= quota { return Some(false); }
    Some(true)
}

/// `times` and `kinds` contain `count` elements in chronological order.
#[no_mangle]
pub unsafe extern "C" fn rium_agent_wave_admit(now: f64, kind: i32, active_agents: i32,
    battery: i32, free: i32, times: *const f64, kinds: *const i32, count: usize) -> i32 {
    if !(0..=1).contains(&battery) || !(0..=1).contains(&free) || count > 1024
        || (count != 0 && (times.is_null() || kinds.is_null())) { return -1; }
    let history = if count == 0 { Vec::new() } else {
        std::slice::from_raw_parts(times, count).iter().copied()
            .zip(std::slice::from_raw_parts(kinds, count).iter().copied()).collect()
    };
    match agent_wave_admit(now, kind, active_agents, battery == 1, free == 1, &history) {
        Some(true) => 1, Some(false) => 0, None => -1,
    }
}

/// Reference NotchCue ordering and the observed close-cue coalescing window.
/// permission, success, running, response, dictation begin, dictation end.
pub fn sound_cue_admit(kind: i32, previous: Option<i32>, elapsed: f64, free: bool) -> Option<bool> {
    let priority = [100, 60, 40, 50, 50, 50];
    if !(0..=5).contains(&kind) || !elapsed.is_finite() || elapsed < 0.0 { return None; }
    let Some(previous) = previous else { return Some(true); };
    if !(0..=5).contains(&previous) { return None; }
    if free { return Some(kind != previous || elapsed >= 0.25); }
    if elapsed >= 1.2 { return Some(true); }
    if kind == previous { return Some(false); }
    if kind >= 3 { return Some(true); }
    Some(priority[kind as usize] > priority[previous as usize])
}

#[no_mangle]
pub extern "C" fn rium_sound_cue_admit(kind: i32, previous: i32, elapsed: f64, free: i32) -> i32 {
    if !(0..=1).contains(&free) || previous < -1 { return -1; }
    match sound_cue_admit(kind, (previous >= 0).then_some(previous), elapsed, free == 1) {
        Some(true) => 1, Some(false) => 0, None => -1,
    }
}

const AGENT_TRANSIENT_PEEK_DURATION: f64 = 2.5;

#[no_mangle]
pub extern "C" fn rium_agent_transient_peek_duration() -> f64 { AGENT_TRANSIENT_PEEK_DURATION }

/// Progress, opacity and scale for the compact running/completed orb.
// shortcut: the orb curves and completion duration require reference-frame comparison.
pub fn agent_peek_orb(elapsed: f64, completed: bool, reduce_motion: bool) -> Option<[f64; 3]> {
    if !elapsed.is_finite() || elapsed < 0.0 { return None; }
    if reduce_motion { return Some([0.72, 1.0, 1.0]); }
    let enter = smoothstep(elapsed / 0.3);
    let fade = 1.0 - smoothstep((elapsed - (AGENT_TRANSIENT_PEEK_DURATION - 0.35)) / 0.35);
    let phase = if completed { 0.72 } else { (elapsed / 1.35).rem_euclid(1.0) };
    let scale = 0.92 + 0.08 * enter + if completed { 0.08 * (PI * (elapsed / 0.7).clamp(0.0, 1.0)).sin() } else { 0.02 * (elapsed * PI).sin() };
    Some([phase, enter * fade, scale])
}

#[no_mangle]
pub unsafe extern "C" fn rium_agent_peek_orb(elapsed: f64, completed: i32, reduce_motion: i32, output: *mut f64) -> i32 {
    if output.is_null() || !(0..=1).contains(&completed) || !(0..=1).contains(&reduce_motion) { return -1; }
    let Some(values) = agent_peek_orb(elapsed, completed == 1, reduce_motion == 1) else { return -1; };
    for (index, value) in values.iter().enumerate() { *output.add(index) = *value; }
    0
}

#[no_mangle]
pub extern "C" fn rium_agent_peek_status_wait_ns(elapsed: f64, running: i32, reduce_motion: i32) -> u64 {
    if !elapsed.is_finite() || reduce_motion == 1 { return 0; }
    let lead: f64 = if running == 1 { 0.08 } else { 0.10 };
    ((lead - elapsed.max(0.0)).max(0.0) * 1_000_000_000.0).ceil() as u64
}

/// Endpoints for the reference FogEntranceModifier's ordinary scale branch.
pub fn agent_peek_entrance_scale(visible: bool, reduce_motion: bool) -> f64 {
    if visible || reduce_motion { 1.0 } else { 0.82 }
}

#[no_mangle]
pub extern "C" fn rium_agent_peek_entrance_scale(visible: i32, reduce_motion: i32) -> f64 {
    if !(0..=1).contains(&visible) || !(0..=1).contains(&reduce_motion) { return f64::NAN; }
    agent_peek_entrance_scale(visible == 1, reduce_motion == 1)
}

/// PastePreviewGlyph's paper position and opacity at the two animation endpoints.
pub fn paste_glyph_frame(active: bool, reduce_motion: bool) -> [f64; 2] {
    [if active && !reduce_motion { 0.5 } else { -5.2 }, if active { 1.0 } else { 0.4 }]
}

#[no_mangle]
pub unsafe extern "C" fn rium_paste_glyph_frame(active: i32, reduce_motion: i32, output: *mut f64) -> i32 {
    if output.is_null() || !(0..=1).contains(&active) || !(0..=1).contains(&reduce_motion) { return -1; }
    std::ptr::copy_nonoverlapping(paste_glyph_frame(active == 1, reduce_motion == 1).as_ptr(), output, 2);
    0
}

/// ThinkingOrbLoader's 10 by 18 projected particles: x, y, radius, opacity,
/// depth, and a sparse highlight flag. Coordinates are local to the canvas.
// shortcut: the static reduced-motion time and glow compositing need comparison.
pub fn thinking_orb_particles(width: f64, height: f64, time: f64) -> Option<[[f64; 6]; 180]> {
    if ![width, height, time].iter().all(|v| v.is_finite()) || width <= 0.0 || height <= 0.0 || time < 0.0 || time > 1.0e12 { return None; }
    let tick = (time / 0.24).floor() as i64;
    let progress = ((time % 0.24) / 0.147).min(1.0);
    let base = ((tick / 2) % 4) as f64 * PI / 2.0;
    let turning = base + (1.0 - (1.0 - progress).powi(3)) * PI / 2.0;
    let (latitude_turn, longitude_turn) = if tick % 2 == 0 { (base, turning) } else { (turning, base + PI / 2.0) };
    let radius = width.min(height) * 0.45 * (1.0 + 0.045 * (time * 1.45).sin());
    let (yaw_sin, yaw_cos) = (time * 0.28).sin_cos();
    let (pitch_sin, pitch_cos) = (0.48 + 0.1 * (time * 0.24).sin()).sin_cos();
    let mut points = [[0.0; 6]; 180];
    for row in 0..10 {
        let latitude_base = (row as f64 + 0.5) / 10.0 * PI - PI / 2.0;
        let longitude_wave = if (2..7).contains(&row) { (((row - 2) as f64) * PI / 4.0).sin() * longitude_turn } else { 0.0 };
        for col in 0..18 {
            let latitude_wave = if (3..13).contains(&col) { (((col - 3) as f64) * PI / 9.0).sin() * latitude_turn } else { 0.0 };
            let latitude = latitude_base + latitude_wave;
            let longitude = col as f64 / 18.0 * 2.0 * PI + ((row * 17 + col * 11) as f64).sin() * 0.035 + longitude_wave;
            let (lat_sin, lat_cos) = latitude.sin_cos();
            let (lon_sin, lon_cos) = longitude.sin_cos();
            let x = yaw_cos * lat_cos * lon_cos - yaw_sin * lat_cos * lon_sin;
            let z_rotated = yaw_sin * lat_cos * lon_cos + yaw_cos * lat_cos * lon_sin;
            let y = pitch_cos * lat_sin - pitch_sin * z_rotated;
            let z = pitch_sin * lat_sin + pitch_cos * z_rotated;
            let depth = ((z + 1.0) * 0.5).clamp(0.0, 1.0);
            let perspective = radius * 1.42 / (2.55 - z);
            let highlight = if depth > 0.82 && (row + col) % 5 == 0 { 1.0 } else { 0.0 };
            points[row * 18 + col] = [width * 0.5 + x * perspective, height * 0.5 + y * perspective,
                                      0.26 + depth * 0.76, 0.2 + depth * 0.78, depth, highlight];
        }
    }
    if points.iter().flatten().all(|v| v.is_finite()) { Some(points) } else { None }
}

#[no_mangle]
pub unsafe extern "C" fn rium_thinking_orb_particles(width: f64, height: f64, time: f64, output: *mut f64) -> i32 {
    if output.is_null() { return -1; }
    let Some(points) = thinking_orb_particles(width, height, time) else { return -1; };
    std::ptr::copy_nonoverlapping(points.as_ptr().cast::<f64>(), output, 180 * 6);
    0
}

/// SuccessOrbLoader's 9 by 17 particles in its default green palette.
// shortcut: the checkmark's independent entry and alternate palettes still need comparison.
pub fn success_orb_particles(width: f64, height: f64, time: f64) -> Option<[[f64; 6]; 153]> {
    if ![width, height, time].iter().all(|v| v.is_finite()) || width <= 0.0 || height <= 0.0 || time < 0.0 || time > 1.0e12 { return None; }
    let radius = width.min(height) * 0.45 * (1.0 + 0.042 * (time * 1.5).sin());
    let (yaw_sin, yaw_cos) = (time * 0.34).sin_cos();
    let (pitch_sin, pitch_cos) = (0.46 + 0.09 * (time * 0.31).sin()).sin_cos();
    let mut points = [[0.0; 6]; 153];
    for row in 0..9 {
        let latitude = (row as f64 + 0.5) / 9.0 * PI - PI / 2.0;
        let (lat_sin, lat_cos) = latitude.sin_cos();
        for col in 0..17 {
            let longitude = col as f64 / 17.0 * 2.0 * PI + time * 0.22 + ((row * 13 + col * 7) as f64).sin() * 0.045;
            let (lon_sin, lon_cos) = longitude.sin_cos();
            let x = yaw_cos * lat_cos * lon_cos - yaw_sin * lat_cos * lon_sin;
            let z_rotated = yaw_sin * lat_cos * lon_cos + yaw_cos * lat_cos * lon_sin;
            let y = pitch_cos * lat_sin - pitch_sin * z_rotated;
            let z = pitch_sin * lat_sin + pitch_cos * z_rotated;
            let depth = ((z + 1.0) * 0.5).clamp(0.0, 1.0);
            let perspective = radius * 1.42 / (2.55 - z);
            points[row * 17 + col] = [width * 0.5 + x * perspective, height * 0.5 + y * perspective,
                                      0.25 + depth * 0.72, 0.22 + depth * 0.78, depth, 0.0];
        }
    }
    if points.iter().flatten().all(|v| v.is_finite()) { Some(points) } else { None }
}

#[no_mangle]
pub unsafe extern "C" fn rium_success_orb_particles(width: f64, height: f64, time: f64, output: *mut f64) -> i32 {
    if output.is_null() { return -1; }
    let Some(points) = success_orb_particles(width, height, time) else { return -1; };
    std::ptr::copy_nonoverlapping(points.as_ptr().cast::<f64>(), output, 153 * 6);
    0
}

/// Points of the reference CheckmarkShape in local coordinates.
pub fn success_checkmark_points(width: f64, height: f64) -> Option<[[f64; 2]; 3]> {
    if ![width, height].iter().all(|v| v.is_finite()) || width <= 0.0 || height <= 0.0 { return None; }
    Some([[width * 0.04, height * 0.55], [width * 0.38, height * 0.9], [width * 0.98, height * 0.12]])
}

#[no_mangle]
pub unsafe extern "C" fn rium_success_checkmark_points(width: f64, height: f64, output: *mut f64) -> i32 {
    if output.is_null() { return -1; }
    let Some(points) = success_checkmark_points(width, height) else { return -1; };
    std::ptr::copy_nonoverlapping(points.as_ptr().cast::<f64>(), output, 6);
    0
}

#[derive(Clone, Copy, Debug)]
pub struct SpringSample {
    pub position: f64,
    pub velocity: f64,
}

/// Sample a unit-mass damped oscillator. `response` is its undamped period;
/// `damping` is the damping ratio. Inputs and result must be finite.
pub fn spring_sample(start: f64, initial_velocity: f64, target: f64, elapsed: f64,
                     response: f64, damping: f64) -> Option<SpringSample> {
    if ![start, initial_velocity, target, elapsed, response, damping].iter().all(|x| x.is_finite())
        || elapsed < 0.0 || !(0.01..=10.0).contains(&response) || !(0.0..=4.0).contains(&damping) {
        return None;
    }
    let omega = 2.0 * PI / response;
    let displacement = start - target;
    let (offset, velocity) = if damping < 1.0 - 1.0e-6 {
        let gamma = damping * omega;
        let frequency = omega * (1.0 - damping * damping).sqrt();
        let b = (initial_velocity + gamma * displacement) / frequency;
        let phase = frequency * elapsed;
        let (s, c) = phase.sin_cos();
        let decay = (-gamma * elapsed).exp();
        let y = decay * (displacement * c + b * s);
        let v = decay * ((b * frequency - gamma * displacement) * c
            + (-displacement * frequency - gamma * b) * s);
        (y, v)
    } else if damping <= 1.0 + 1.0e-6 {
        let b = initial_velocity + omega * displacement;
        let decay = (-omega * elapsed).exp();
        let y = decay * (displacement + b * elapsed);
        let v = decay * (b - omega * (displacement + b * elapsed));
        (y, v)
    } else {
        let root = (damping * damping - 1.0).sqrt();
        let r1 = -omega * (damping - root);
        let r2 = -omega * (damping + root);
        let c1 = (initial_velocity - r2 * displacement) / (r1 - r2);
        let c2 = displacement - c1;
        let e1 = (r1 * elapsed).exp();
        let e2 = (r2 * elapsed).exp();
        (c1 * e1 + c2 * e2, c1 * r1 * e1 + c2 * r2 * e2)
    };
    let position = target + offset;
    if position.is_finite() && velocity.is_finite() { Some(SpringSample { position, velocity }) } else { None }
}

/// Keeps a continuous position and velocity when the target changes before
/// the previous movement finishes. Times are caller-supplied monotonic seconds.
#[derive(Clone, Copy, Debug)]
pub struct SpringTransition {
    pub start: SpringSample,
    pub target: f64,
    pub began_at: f64,
    pub response: f64,
    pub damping: f64,
}

impl SpringTransition {
    pub fn sample(&self, now: f64) -> Option<SpringSample> {
        if !now.is_finite() || !self.began_at.is_finite() { return None; }
        spring_sample(self.start.position, self.start.velocity, self.target,
                      (now - self.began_at).max(0.0), self.response, self.damping)
    }

    pub fn retarget(&mut self, now: f64, target: f64, response: f64, damping: f64) -> bool {
        if !target.is_finite() || !now.is_finite() || now < self.began_at { return false; }
        let Some(current) = self.sample(now) else { return false; };
        if spring_sample(current.position, current.velocity, target, 0.0, response, damping).is_none() { return false; }
        self.start = current;
        self.target = target;
        self.began_at = now;
        self.response = response;
        self.damping = damping;
        true
    }
}

#[derive(Clone, Copy, Debug)]
pub struct LightSegment {
    pub start: f64,
    pub end: f64,
    pub opacity: f64,
    pub highlight: bool,
}

fn segment(start: f64, end: f64, opacity: f64, highlight: bool) -> LightSegment {
    LightSegment { start, end, opacity, highlight }
}

fn smoothstep(value: f64) -> f64 {
    let t = value.clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}

/// Three staggered indicators from TrackSkipPeekPreview.wave.
pub fn track_skip_peek_wave(phase: f64, index: i32, forward: bool) -> Option<f64> {
    if !phase.is_finite() || !(0..3).contains(&index) { return None; }
    if phase < 0.0 { return Some(1.0); }
    let index = if forward { index } else { 2 - index };
    let local = (phase.rem_euclid(1.0) - f64::from(index) / 3.0).rem_euclid(1.0);
    Some((1.0 - 3.0 * local).max(0.0).powi(2))
}

#[no_mangle]
pub extern "C" fn rium_track_skip_peek_wave(phase: f64, index: i32, forward: i32) -> f64 {
    if !(0..=1).contains(&forward) { return f64::NAN; }
    track_skip_peek_wave(phase, index, forward == 1).unwrap_or(f64::NAN)
}

/// AirDrop inbound radius and held contour charge from the modified app's
/// embedded edge-wave shader. The switch to held mode is chosen by the caller.
/// Returns normalized radius and contour charge, before spatial noise/blending.
pub fn receiving_tide_frame(elapsed: f64, clock: f64, progress: f64, held: bool, reduce_motion: bool) -> Option<[f64; 2]> {
    if ![elapsed, clock, progress].iter().all(|value| value.is_finite()) || elapsed < 0.0 { return None; }
    let progress = progress.clamp(0.0, 1.0);
    let oscillation = if reduce_motion { 0.0 } else { (clock.rem_euclid(2.0 * PI / 2.2) * 2.2).sin() };
    if held { return Some([0.082 + 0.04 * progress + 0.004 * oscillation,
                           0.85 + 0.15 * progress + 0.08 * oscillation]); }
    let t = (2.0 - elapsed).max(0.0);
    let phase = ((t - 0.1) / 2.25).clamp(0.0, 1.0);
    let radius = 1.05 * (1.0 - (1.0 - phase).powf(1.8)) + 0.015 * (phase * PI).sin() * (1.0 - phase);
    let charge = smoothstep((elapsed - 1.45) / 0.45)
        + 0.35 * (PI * ((elapsed - 1.9) / 0.6).clamp(0.0, 1.0)).sin();
    Some([radius, charge])
}

/// Edge-wave front radius and fade from the reference shader. Spatial noise,
/// screen blending and the rounded-notch distance field are separate concerns.
/// Straight-alpha equivalent of the bright-surface shader for Canvas strokes.
pub fn edge_wave_fallback_color(color: [f64; 3], opacity: f64, style: i32) -> Option<[f64; 4]> {
    if !(0..=2).contains(&style) || !opacity.is_finite() || !(0.0..=1.0).contains(&opacity)
        || color.iter().any(|v| !v.is_finite() || !(0.0..=1.0).contains(v)) { return None; }
    if style == 0 { return Some([color[0], color[1], color[2], opacity]); }
    let peak = color[0].max(color[1]).max(color[2]) * opacity;
    if peak == 0.0 { return Some([0.0; 4]); }
    let mut rgb = color.map(|v| v * opacity / peak.max(0.001));
    let grey = rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722;
    if style == 1 {
        rgb = rgb.map(|v| (grey + (v - grey) * 1.04).clamp(0.0, 1.0));
        let white = rgb[0].min(rgb[1]).min(rgb[2]) * 0.12;
        rgb = rgb.map(|v| (v - white) / (1.0 - white).max(0.001));
    }
    Some([rgb[0], rgb[1], rgb[2], (peak * if style == 1 { 1.10 } else { 1.0 }).min(1.0)])
}

#[no_mangle]
pub unsafe extern "C" fn rium_edge_wave_fallback_color(r: f64, g: f64, b: f64, opacity: f64, style: i32, output: *mut f64) -> i32 {
    if output.is_null() { return -1; }
    let Some(values) = edge_wave_fallback_color([r, g, b], opacity, style) else { return -1; };
    std::ptr::copy_nonoverlapping(values.as_ptr(), output, values.len());
    0
}

pub fn edge_wave_frame(elapsed: f64, inward: bool) -> Option<[f64; 2]> {
    if !elapsed.is_finite() || elapsed < 0.0 { return None; }
    let duration = if inward { 2.6 } else { 3.0 };
    if elapsed >= duration { return Some([0.0, 0.0]); }
    let t = if inward { (2.0 - elapsed).max(0.0) } else { (elapsed - 0.4).max(0.0) };
    let phase = ((t - 0.1) / 2.25).clamp(0.0, 1.0);
    let radius = 1.05 * (1.0 - (1.0 - phase).powf(1.8)) + 0.015 * (phase * PI).sin() * (1.0 - phase);
    let fade = 1.0 - smoothstep((t - 1.5) / 1.1);
    Some([radius, fade])
}

fn wave_noise(x: f64, y: f64) -> f64 {
    fn hash(x: f64, y: f64) -> f64 {
        let value = ((x * 127.1 + y * 311.7).sin()) * 43758.5453;
        value - value.floor()
    }
    let ix = x.floor(); let iy = y.floor();
    let fx = smoothstep(x - ix); let fy = smoothstep(y - iy);
    let lower = hash(ix, iy) * (1.0 - fx) + hash(ix + 1.0, iy) * fx;
    let upper = hash(ix, iy + 1.0) * (1.0 - fx) + hash(ix + 1.0, iy + 1.0) * fx;
    lower * (1.0 - fy) + upper * fy
}

fn wave_texture(mut x: f64, mut y: f64) -> f64 {
    let mut value = 0.0; let mut amplitude = 0.5;
    for _ in 0..4 {
        value += amplitude * wave_noise(x, y);
        x = x * 2.03 + 1.7; y = y * 2.03 + 9.2; amplitude *= 0.5;
    }
    value
}

/// Front displacement, breakup, and traveling rim brightness.
pub fn edge_wave_detail(angle: f64, time: f64, radius: f64) -> Option<[f64; 3]> {
    if ![angle, time, radius].iter().all(|v| v.is_finite()) || !(-PI..=PI).contains(&angle) || !(0.0..=3.0).contains(&time)
        || !(0.0..=1.1).contains(&radius) { return None; }
    let wobble = (0.035 * (3.0 * angle + 2.1 * time).sin()
        + 0.02 * (5.0 * angle - 3.3 * time).sin()
        + 0.012 * (9.0 * angle + 4.7 * time).sin()) * (0.6 + 0.8 * radius);
    let broken = wave_texture(angle * 3.0, time * 0.6) - 0.55 + (1.7 - time) * 0.5;
    let breakup = smoothstep((broken + 0.12) / 0.34);
    let spark = wave_texture(angle * 10.0 + time * 1.5, time * 2.0).powi(3) * 3.0;
    Some([wobble, breakup, spark])
}

/// Interpolate a bounded phase through ordered keyframes without a velocity
/// discontinuity at each keyframe. Callers supply phase in the 0...1 range.
fn smooth_keyframes(phase: f64, points: &[(f64, f64)]) -> f64 {
    let Some(first) = points.first() else { return 0.0; };
    if phase <= first.0 { return first.1; }
    let last = points.last().unwrap();
    if phase >= last.0 { return last.1; }
    for pair in points.windows(2) {
        let (t0, y0) = pair[0];
        let (t1, y1) = pair[1];
        if phase <= t1 {
            let amount = if t1 > t0 { smoothstep((phase - t0) / (t1 - t0)) } else { 1.0 };
            return y0 + (y1 - y0) * amount;
        }
    }
    last.1
}

/// Width, height, and opacity of AssistantResponseLight's cyan ellipse.
pub fn response_halo_frame(elapsed: f64, notch_width: f64) -> Option<[f64; 3]> {
    if !elapsed.is_finite() || !notch_width.is_finite() || notch_width < 0.0 { return None; }
    if !(0.0..0.85).contains(&elapsed) { return Some([0.0; 3]); }
    let phase = elapsed / 0.85;
    let pulse = (PI * phase).sin();
    Some([notch_width * (0.35 + 0.45 * phase), 28.0 + 34.0 * pulse, 0.46 * pulse])
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_response_halo(elapsed: f64, notch_width: f64, output: *mut f64) -> i32 {
    if output.is_null() { return -1; }
    let Some(frame) = response_halo_frame(elapsed, notch_width) else { return -1; };
    std::ptr::copy_nonoverlapping(frame.as_ptr(), output, frame.len());
    0
}

pub fn playback_transition_envelope(elapsed: f64) -> Option<f64> {
    if !elapsed.is_finite() || elapsed < 0.0 { return None; }
    Some((elapsed / 0.045).min(1.0) * (1.0 - (elapsed - 0.4).max(0.0) / 0.42).max(0.0))
}

#[no_mangle]
pub extern "C" fn rium_notch_playback_transition_envelope(elapsed: f64) -> f64 {
    playback_transition_envelope(elapsed).unwrap_or(f64::NAN)
}

pub fn track_skip_reduced_opacity(kind: i32, elapsed: f64) -> Option<f64> {
    if !elapsed.is_finite() || elapsed < 0.0 { return None; }
    match kind {
        9 | 10 => Some(0.44 * (1.0 - elapsed / 0.46).max(0.0)),
        12 | 13 => Some(0.24),
        _ => None,
    }
}

#[no_mangle]
pub extern "C" fn rium_notch_track_skip_reduced_opacity(kind: i32, elapsed: f64) -> f64 {
    track_skip_reduced_opacity(kind, elapsed).unwrap_or(f64::NAN)
}

/// Segment fractions may extend outside 0...1; the drawing layer clips them.
/// `shoulder_arc_length` is the measured upper corner of the rendered path;
/// -1 retains the older estimate for callers without contour measurements.
pub fn arrival_segments(kind: i32, elapsed: f64, path_length: f64, arm: f64,
                        notch_width: f64, height: f64, shoulder_arc_length: f64) -> Option<Vec<LightSegment>> {
    if ![elapsed, path_length, arm, notch_width, height, shoulder_arc_length].iter().all(|x| x.is_finite())
        || !(0..=13).contains(&kind) || arm < 0.0 || notch_width < 0.0 || height < 0.0
        || (shoulder_arc_length < 0.0 && shoulder_arc_length != -1.0) {
        return None;
    }
    // The hunt frame repeats a linear pass every 0.62 s at 0.58 opacity.
    if kind == 12 || kind == 13 {
        if elapsed < 0.0 || path_length <= 0.0 { return Some(Vec::new()); }
        let position = -0.13 + 1.26 * (elapsed / 0.62).fract();
        let center = if kind == 12 { position } else { 1.0 - position };
        let trailing = if kind == 12 { center - 0.13 } else { center + 0.13 };
        let spread = (26.0_f64.max(arm * 0.16) / path_length).min(1.0);
        return Some(vec![segment(center.min(trailing), center.max(trailing), 0.58 * 0.42, false),
                         segment(center - spread, center + spread, 0.58 * 0.98, true),
                         segment(trailing - spread, trailing + spread, 0.58 * 0.58, true)]);
    }
    // TrackSkipPrismFrame's arrival gauge fades as 0.88 × (1 - t / 0.58)².
    if kind == 11 {
        if elapsed < 0.0 || elapsed >= 0.58 || path_length <= 0.0 { return Some(Vec::new()); }
        return Some(vec![segment(0.0, 1.0, 0.88 * (1.0 - elapsed / 0.58).powi(2), false)]);
    }
    // TrackSkipPrismFrame's pass uses 0.46 s, a 0.055 s entry and
    // smoothstep travel from -0.13 to 1.13, reversed for the previous track.
    if kind == 9 || kind == 10 {
        if elapsed < 0.0 || elapsed >= 0.46 || path_length <= 0.0 { return Some(Vec::new()); }
        let position = -0.13 + 1.26 * smoothstep(elapsed / 0.46);
        let center = if kind == 9 { position } else { 1.0 - position };
        let trailing = if kind == 9 { center - 0.13 } else { center + 0.13 };
        let opacity = (elapsed / 0.055).min(1.0) * ((0.46 - elapsed) / 0.16).clamp(0.0, 1.0);
        let spread = (26.0_f64.max(arm * 0.16) / path_length).min(1.0);
        return Some(vec![segment(center.min(trailing), center.max(trailing), opacity * 0.42, false),
                         segment(center - spread, center + spread, opacity * 0.98, true),
                         segment(trailing - spread, trailing + spread, opacity * 0.58, true)]);
    }
    // AssistantResponseLight: 0.85 s, paired crests at 0.5 ± 0.47 × smoothstep,
    // with a 76-point spread and 0.78 × sin(π × phase) opacity.
    if kind == 8 {
        if elapsed < 0.0 || elapsed >= 0.85 || path_length <= 0.0 { return Some(Vec::new()); }
        let phase = elapsed / 0.85;
        let distance = 0.47 * smoothstep(phase);
        let spread = 76.0 / path_length;
        let opacity = (phase * PI).sin() * 0.78;
        return Some(vec![segment(0.5 - distance - spread, 0.5 - distance + spread, opacity, true),
                         segment(0.5 + distance - spread, 0.5 + distance + spread, opacity, true)]);
    }
    // PlaybackPrismFrame expands for play and contracts for pause.
    if kind == 5 || kind == 6 {
        if elapsed < 0.0 || elapsed >= 0.85 || path_length <= 0.0 { return Some(Vec::new()); }
        let progress = smoothstep(elapsed / 0.62);
        let envelope = playback_transition_envelope(elapsed)?;
        let half = if kind == 5 { 0.5 * progress } else { 0.44 - 0.32 * (1.0 - (1.0 - progress).powi(3)) };
        let (left, right) = (0.5 - half, 0.5 + half);
        let spread = (if kind == 5 { 48.0 } else { 22.0 }) / path_length;
        let (gauge, crest) = if kind == 5 { (0.3, 0.95) } else { (0.24, 0.82) };
        return Some(vec![segment(left, right, envelope * gauge, false),
                         segment(left - spread, left + spread, envelope * crest, true),
                         segment(right - spread, right + spread, envelope * crest, true)]);
    }
    // shortcut: track-change crest timing and width need reference-frame comparison.
    if kind == 7 {
        if elapsed < 0.0 || elapsed >= 2.0 { return Some(Vec::new()); }
        let phase = elapsed / 2.0;
        let envelope = smoothstep(phase / 0.08) * smoothstep((1.0 - phase) / 0.22);
        let center = -0.08 + 1.16 * smoothstep(phase / 0.8);
        return Some(vec![segment(center - 0.09, center + 0.03, envelope * 0.7, false),
                         segment(center - 0.012, center + 0.012, envelope, true)]);
    }
    if kind >= 3 {
        let shoulder = (height / 3.0).min(notch_width / 3.0).min(20.0).max(0.0);
        let bottom_half_span = (notch_width / 2.0 - shoulder).max(0.0);
        let shoulder_arc = if shoulder_arc_length >= 0.0 { shoulder_arc_length } else { shoulder * PI / 2.0 };
        return agenda_arrival_segments(kind, elapsed, path_length, bottom_half_span, arm + shoulder_arc / 2.0);
    }
    let duration = if kind == 2 { 0.72 } else { 0.82 };
    if elapsed < 0.0 || elapsed >= duration || (kind != 0 && path_length <= 0.0) {
        return Some(Vec::new());
    }
    let phase = elapsed / duration;
    let fade_in = (phase / 0.09).min(1.0);
    let envelope = fade_in * ((1.0 - phase) / 0.24).min(1.0);
    if kind == 0 {
        let spread = smoothstep((phase - 0.06) / 0.78) * 0.5;
        let left = 0.5 - spread;
        let right = 0.5 + spread;
        return Some(vec![
            segment(left, (left + 0.11).min(0.5), envelope * 0.62, false),
            segment((right - 0.11).max(0.5), right, envelope * 0.62, false),
            segment(left - 0.009, left + 0.009, envelope, true),
            segment(right - 0.009, right + 0.009, envelope, true),
        ]);
    }
    let shoulder = (height / 3.0).min(notch_width / 3.0).min(20.0).max(0.0);
    // shortcut: the fallback reconstructs a circular arc; the supplied length
    // instead follows Rium's currently drawn cubic and still needs visual comparison.
    let shoulder_arc = if shoulder_arc_length >= 0.0 { shoulder_arc_length } else { shoulder * PI / 2.0 };
    if kind == 1 {
        let position = smoothstep(phase / 0.68) * (arm + shoulder_arc / 2.0) / path_length;
        let mirror = 1.0 - position;
        let radius = 20.0 / path_length;
        return Some(vec![
            segment((position - 0.1).max(0.0), position + radius, envelope * 0.5, false),
            segment(mirror - radius, (mirror + 0.1).min(1.0), envelope * 0.5, false),
            segment(position - radius, position + radius, envelope, true),
            segment(mirror - radius, mirror + radius, envelope, true),
        ]);
    }
    let position = (1.0 - smoothstep(phase / 0.7)) * arm / path_length;
    let mirror = 1.0 - position;
    let radius = 16.0 / path_length;
    let arm_end = (arm + shoulder_arc) / path_length;
    let arm_opacity = fade_in * (1.0 - phase / 0.74).max(0.0).powf(0.65) * 0.86;
    let mut result = vec![
        segment(0.0, arm_end, arm_opacity, false),
        segment(1.0 - arm_end, 1.0, arm_opacity, false),
        segment(position, (position + 0.14).min(arm_end), envelope * 0.72, false),
        segment((mirror - 0.14).max(1.0 - arm_end), mirror, envelope * 0.72, false),
        segment(position - radius, position + radius, envelope, true),
        segment(mirror - radius, mirror + radius, envelope, true),
    ];
    if phase > 0.58 {
        let flash = ((phase - 0.58) / 0.42 * PI).sin() * 0.95;
        result.push(segment(0.0, 0.035, flash, true));
        result.push(segment(0.965, 1.0, flash, true));
    }
    Some(result)
}

// shortcut: agenda crest timing and width need reference-frame comparison.
fn agenda_arrival_segments(kind: i32, elapsed: f64, path_length: f64,
                           bottom_half_span: f64, shoulder_distance: f64) -> Option<Vec<LightSegment>> {
    if !matches!(kind, 3 | 4)
        || ![elapsed, path_length, bottom_half_span, shoulder_distance].iter().all(|x| x.is_finite())
        || bottom_half_span < 0.0 || shoulder_distance < 0.0 {
        return None;
    }
    if elapsed < 0.0 || elapsed >= 2.0 || path_length <= 0.0 { return Some(Vec::new()); }
    let phase = elapsed / 2.0;
    let envelope = smoothstep(phase / 0.08) * smoothstep((1.0 - phase) / 0.22);
    let radius = (9.0 / path_length).min(0.08);
    if kind == 3 {
        let bottom_half = (bottom_half_span / path_length).min(0.5);
        let center = 0.5 - bottom_half + 2.0 * bottom_half * smoothstep(phase / 0.68);
        let mut parts = vec![segment(center - radius * 3.0, center + radius, envelope * 0.75, false),
                             segment(center - radius, center + radius, envelope, true)];
        if phase > 0.58 {
            parts.push(segment(0.5 - radius, 0.5 + radius, envelope * smoothstep((phase - 0.58) / 0.14), true));
        }
        return Some(parts);
    }

    let shoulder_position = (shoulder_distance / path_length).clamp(0.0, 0.5);
    let distance = (0.5 - shoulder_position) * smoothstep(phase / 0.68);
    Some(vec![segment(0.5 - distance - radius, 0.5 - distance + radius, envelope, true),
              segment(0.5 + distance - radius, 0.5 + distance + radius, envelope, true)])
}

/// ShortcutGlow.life values recovered from the reference, mapped to our
/// shortcut order. Paste uses CopySweepGlow's separate lifecycle.
pub fn shortcut_light_duration(kind: i32) -> Option<f64> {
    Some(match kind {
        0 => 0.54, 1 => 0.62, 2 => 0.60, 3 => 0.66, 4 => 0.78,
        5 => 0.52, 6 => 0.58,
        7 => 0.60,
        8 => 0.85, 9 => 1.10,
        _ => return None,
    })
}

#[no_mangle]
pub extern "C" fn rium_notch_shortcut_light_duration(kind: i32) -> f64 {
    shortcut_light_duration(kind).unwrap_or(-1.0)
}

/// Base and highlight RGB values from ShortcutPrism's reference initializers.
pub fn shortcut_prism(kind: i32) -> Option<[[f64; 3]; 2]> {
    Some(match kind {
        0 => [[1.0, 0.35, 0.24], [1.0, 0.12, 0.58]],
        1 => [[1.0, 0.83, 0.18], [1.0, 0.36, 0.06]],
        2 => [[0.36, 1.0, 0.74], [0.02, 0.65, 0.42]],
        3 => [[0.12, 1.0, 0.85], [0.36, 0.25, 1.0]],
        4 => [[0.43, 0.85, 1.0], [0.66, 0.42, 1.0]],
        5 => [[0.20, 0.55, 1.0], [0.05, 1.0, 0.94]],
        6 => [[1.0, 0.39, 0.37], [0.49, 0.19, 0.95]],
        7 => [[0.72, 0.35, 1.0], [1.0, 0.18, 0.65]],
        8 | 9 => [[1.0, 1.0, 1.0], [0.64, 0.32, 1.0]],
        _ => return None,
    })
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_shortcut_prism(kind: i32, output: *mut f64) -> i32 {
    if output.is_null() { return -1; }
    let Some(colors) = shortcut_prism(kind) else { return -1; };
    std::ptr::copy_nonoverlapping(colors.as_ptr().cast::<f64>(), output, 6);
    0
}

/// Base and highlight RGB values from the reference system-control prisms.
pub fn system_hud_prism(kind: i32) -> Option<[[f64; 3]; 2]> {
    Some(match kind {
        0 => [[0.10, 0.91, 1.0], [0.22, 0.25, 1.0]],
        1 => [[1.0, 0.88, 0.48], [1.0, 0.37, 0.09]],
        2 => [[0.37, 0.48, 0.94], [0.40, 0.13, 0.64]],
        _ => return None,
    })
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_system_hud_prism(kind: i32, output: *mut f64) -> i32 {
    if output.is_null() { return -1; }
    let Some(colors) = system_hud_prism(kind) else { return -1; };
    std::ptr::copy_nonoverlapping(colors.as_ptr().cast::<f64>(), output, 6);
    0
}

/// ShortcutGlow.fade(at:) uses a 60 ms entrance and a 240 ms exit.
fn shortcut_light_fade(elapsed: f64, duration: f64) -> f64 {
    (elapsed / 0.06).clamp(0.0, 1.0)
        .min(((duration - elapsed) / 0.24).clamp(0.0, 1.0))
}

/// Select-all's second, blurred contour: width, blur and opacity.
pub fn select_all_trace(elapsed: f64) -> Option<[f64; 3]> {
    if !elapsed.is_finite() || elapsed < 0.0 { return None; }
    let progress = ((elapsed - 0.1) / 0.38).clamp(0.0, 1.0);
    Some([5.0 + 24.0 * progress, 3.0 + 14.0 * progress,
          0.32 * (PI * progress).sin().max(0.0) * shortcut_light_fade(elapsed, 0.52)])
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_select_all_trace(elapsed: f64, output: *mut f64) -> i32 {
    if output.is_null() { return -1; }
    let Some(trace) = select_all_trace(elapsed) else { return -1; };
    std::ptr::copy_nonoverlapping(trace.as_ptr(), output, trace.len());
    0
}

/// Full-screen capture's prism opacity and expanding trace width, blur, opacity.
pub fn screenshot_flash_frame(elapsed: f64) -> Option<[f64; 4]> {
    if !elapsed.is_finite() || elapsed < 0.0 { return None; }
    if elapsed >= 0.85 { return Some([0.0; 4]); }
    let progress = ((elapsed - 0.26) / 0.59).clamp(0.0, 1.0);
    let flash = (elapsed / 0.1).min(1.0) * (-3.4 * progress).exp();
    Some([0.85 * flash, 4.0 + 30.0 * progress, 3.0 + 30.0 * progress, 0.45 * flash])
}

/// ScreenshotFileGlow closes two crests from the arms, then brightens the centre.
pub fn screenshot_file_glow(elapsed: f64, arm: f64, length: f64, reduce_motion: bool) -> Option<[f64; 6]> {
    if ![elapsed, arm, length].iter().all(|value| value.is_finite()) || elapsed < 0.0 || arm < 0.0 || length <= 0.0 { return None; }
    let life = 1.35;
    let fade = (elapsed / 0.08).min(1.0) * ((life - elapsed) / 0.26).clamp(0.0, 1.0);
    if reduce_motion { return Some([0.0, 1.0, 0.58 * fade, 0.0, 0.0, 0.0]); }
    let progress = smoothstep((elapsed / life).clamp(0.0, 1.0));
    let start = (0.1 * arm / length).clamp(0.0, 0.5);
    let left = start + (0.5 - start) * progress;
    let spread = (arm * 0.2).clamp(2.0, 28.0) / length;
    let frame = [left, 1.0 - left, 0.4 * fade * (1.0 - 0.45 * progress),
                 0.92 * fade, spread, 0.72 * fade * ((progress - 0.78) / 0.22).clamp(0.0, 1.0)];
    frame.iter().all(|value| value.is_finite()).then_some(frame)
}

#[no_mangle]
pub unsafe extern "C" fn rium_screenshot_file_glow(elapsed: f64, arm: f64, length: f64, reduce_motion: i32, output: *mut f64) -> i32 {
    if output.is_null() || !(0..=1).contains(&reduce_motion) { return -1; }
    let Some(frame) = screenshot_file_glow(elapsed, arm, length, reduce_motion == 1) else { return -1; };
    std::ptr::copy_nonoverlapping(frame.as_ptr(), output, frame.len());
    0
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_screenshot_flash(elapsed: f64, output: *mut f64) -> i32 {
    if output.is_null() { return -1; }
    let Some(frame) = screenshot_flash_frame(elapsed) else { return -1; };
    std::ptr::copy_nonoverlapping(frame.as_ptr(), output, frame.len());
    0
}

/// Area capture's four crest centers, spread and opacity along a symmetric contour.
pub fn area_capture_reticle(elapsed: f64, path_length: f64, arm: f64, shoulder_arc: f64,
                            side: f64, lower_arc: f64) -> Option<[f64; 6]> {
    if ![elapsed, path_length, arm, shoulder_arc, side, lower_arc].iter().all(|v| v.is_finite())
        || elapsed < 0.0 || path_length <= 0.0 || [arm, shoulder_arc, side, lower_arc].iter().any(|v| *v < 0.0) { return None; }
    let shoulder = ((arm + shoulder_arc * 0.5) / path_length).clamp(0.0, 0.5);
    let lower = ((arm + shoulder_arc + side + lower_arc * 0.5) / path_length).clamp(shoulder, 0.5);
    let opacity = if elapsed >= 1.1 { 0.0 } else {
        let pulse = 0.55 + 0.45 * (2.0 * PI * elapsed / 0.62).sin();
        (0.42 + 0.34 * pulse) * shortcut_light_fade(elapsed, 1.1)
    };
    Some([shoulder, 1.0 - shoulder, lower, 1.0 - lower, (24.0 / path_length).min(1.0), opacity])
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_area_capture_reticle(elapsed: f64, path_length: f64, arm: f64,
    shoulder_arc: f64, side: f64, lower_arc: f64, output: *mut f64) -> i32 {
    if output.is_null() { return -1; }
    let Some(frame) = area_capture_reticle(elapsed, path_length, arm, shoulder_arc, side, lower_arc) else { return -1; };
    std::ptr::copy_nonoverlapping(frame.as_ptr(), output, frame.len());
    0
}

/// Quit's central prism crest: normalized start, end and opacity.
pub fn shortcut_quit_crest(elapsed: f64, path_length: f64) -> Option<[f64; 3]> {
    if !elapsed.is_finite() || elapsed < 0.0 || !path_length.is_finite() || path_length <= 0.0 { return None; }
    let progress = smoothstep(elapsed / 0.58);
    let spread = ((12.0 + 30.0 * (1.0 - progress)) / path_length).min(0.5);
    let opacity = (PI * progress).sin().max(0.0) * shortcut_light_fade(elapsed, 0.58);
    Some([0.5 - spread, 0.5 + spread, opacity])
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_shortcut_quit_crest(elapsed: f64, path_length: f64, output: *mut f64) -> i32 {
    if output.is_null() { return -1; }
    let Some(frame) = shortcut_quit_crest(elapsed, path_length) else { return -1; };
    std::ptr::copy_nonoverlapping(frame.as_ptr(), output, frame.len());
    0
}

/// Refresh's moving prism crest: center, spread and opacity.
pub fn shortcut_refresh_crest(elapsed: f64, path_length: f64, arm: f64) -> Option<[f64; 3]> {
    if ![elapsed, path_length, arm].iter().all(|v| v.is_finite()) || elapsed < 0.0 || path_length <= 0.0 || arm < 0.0 { return None; }
    let center = (elapsed / 0.66).clamp(0.0, 1.0);
    let spread = (30.0_f64.max(arm * 0.18) / path_length).min(1.0);
    Some([center, spread, 0.9 * shortcut_light_fade(elapsed, 0.66)])
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_shortcut_refresh_crest(elapsed: f64, path_length: f64, arm: f64, output: *mut f64) -> i32 {
    if output.is_null() { return -1; }
    let Some(frame) = shortcut_refresh_crest(elapsed, path_length, arm) else { return -1; };
    std::ptr::copy_nonoverlapping(frame.as_ptr(), output, frame.len());
    0
}

/// Cut's symmetric crest centers, spread and opacity.
pub fn shortcut_cut_crests(elapsed: f64, path_length: f64) -> Option<[f64; 4]> {
    if !elapsed.is_finite() || elapsed < 0.0 || !path_length.is_finite() || path_length <= 0.0 { return None; }
    let gap = 0.25 * smoothstep(elapsed / 0.54);
    Some([0.5 - gap, 0.5 + gap, (26.0 / path_length).min(1.0), 0.85 * shortcut_light_fade(elapsed, 0.54)])
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_shortcut_cut_crests(elapsed: f64, path_length: f64, output: *mut f64) -> i32 {
    if output.is_null() { return -1; }
    let Some(frame) = shortcut_cut_crests(elapsed, path_length) else { return -1; };
    std::ptr::copy_nonoverlapping(frame.as_ptr(), output, frame.len());
    0
}

/// Undo's leading crest moves from the right edge to the left.
pub fn shortcut_undo_crest(elapsed: f64, path_length: f64, arm: f64) -> Option<[f64; 3]> {
    if ![elapsed, path_length, arm].iter().all(|v| v.is_finite()) || elapsed < 0.0 || path_length <= 0.0 || arm < 0.0 { return None; }
    let center = 1.0 - smoothstep(elapsed / 0.62);
    let spread = (34.0_f64.max(arm * 0.20) / path_length).min(1.0);
    Some([center, spread, 0.88 * shortcut_light_fade(elapsed, 0.62)])
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_shortcut_undo_crest(elapsed: f64, path_length: f64, arm: f64, output: *mut f64) -> i32 {
    if output.is_null() { return -1; }
    let Some(frame) = shortcut_undo_crest(elapsed, path_length, arm) else { return -1; };
    std::ptr::copy_nonoverlapping(frame.as_ptr(), output, frame.len());
    0
}

/// Approximate shortcut-specific contour effects described by the
/// reference UI. Physical geometry and easing are not fully recovered.
/// Kinds: cut, undo, save, refresh, print, select all, quit, paste, full and area capture.
pub fn shortcut_segments(kind: i32, elapsed: f64) -> Option<Vec<LightSegment>> {
    if !elapsed.is_finite() { return None; }
    let duration = shortcut_light_duration(kind)?;
    if !(0.0..duration).contains(&elapsed) { return Some(Vec::new()); }
    let phase = elapsed / duration;
    // shortcut: the paste entry reuses this recovered fade without a matching reference action.
    let envelope = shortcut_light_fade(elapsed, duration);
    let mut parts = Vec::new();
    match kind {
        0 => {
            let gap = 0.25 * smoothstep(elapsed / 0.54);
            parts.push(segment(0.0, 0.5 - gap, envelope * 0.62, false));
            parts.push(segment(0.5 + gap, 1.0, envelope * 0.62, false));
        }
        1 => {
            let head = 1.0 - smoothstep(elapsed / 0.62);
            let tail = 1.0 - smoothstep((elapsed - 0.075).max(0.0) / 0.62);
            parts.push(segment(head, tail, envelope * 0.6, true));
            parts.push(segment(head, (head + 0.18).min(1.0), envelope * 0.3, false));
        }
        2 => {
            let spread = 0.5 * smoothstep(elapsed / 0.6);
            parts.push(segment(0.5 - spread, 0.5 + spread, envelope * 0.6, false));
            if phase > 0.82 {
                let completion = (PI * (phase - 0.82) / 0.18).sin().max(0.0);
                parts.push(segment(0.0, 1.0, completion * 0.65, true));
            }
        }
        3 => {
            let trailing = ((elapsed - 0.095) / 0.66).max(0.0);
            parts.push(segment(trailing, phase, envelope * 0.68, true));
            parts.push(segment((phase - 0.22).max(0.0), phase, envelope * 0.26, false));
        }
        4 => {
            // shortcut: the reference uses a multi-layer prism gauge; this
            // segment preserves its recovered span and three-pulse envelope.
            let beat = [0.06, 0.28, 0.50].into_iter().map(|start| {
                let local = (elapsed - start) / 0.20;
                if (0.0..=1.0).contains(&local) { (PI * local).sin().max(0.0) } else { 0.0 }
            }).fold(0.0_f64, f64::max);
            if beat > 0.0 { parts.push(segment(0.3, 0.7, envelope * 0.72 * beat, false)); }
        }
        5 => parts.push(segment(0.0, 1.0, envelope * 0.78 * (elapsed / 0.07).min(1.0), false)),
        6 => {
            let progress = smoothstep(elapsed / 0.58);
            parts.push(segment(0.5 * progress, 1.0 - 0.5 * progress, envelope * 0.8 * (1.0 - progress), false));
        }
        7 => {
            // shortcut: paste direction and timing need reference-frame comparison.
            let center = 0.5 * smoothstep(phase / 0.75);
            let half_width = 0.04;
            parts.push(segment(center - half_width, center + half_width, envelope * 0.8, false));
            parts.push(segment(1.0 - center - half_width, 1.0 - center + half_width, envelope * 0.8, false));
        }
        8 => parts.push(segment(0.0, 1.0, screenshot_flash_frame(elapsed)?[0], false)),
        9 => {
            let pulse = 0.55 + 0.45 * (2.0 * PI * elapsed / 0.62).sin();
            parts.push(segment(0.0, 1.0, envelope * (0.42 + 0.34 * pulse), false));
        }
        _ => unreachable!(),
    }
    Some(parts)
}

/// Base and highlight colors from the reference modifier-key prisms.
pub fn case_key_prism(kind: i32) -> Option<[[f64; 3]; 2]> {
    Some(match kind {
        0 => [[1.0, 0.82, 0.18], [1.0, 0.38, 0.05]],
        1 => [[0.38, 0.73, 1.0], [0.55, 0.35, 1.0]],
        2 => [[0.48, 0.85, 1.0], [0.51, 0.43, 1.0]],
        _ => return None,
    })
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_case_key_prism(kind: i32, output: *mut f64) -> i32 {
    if output.is_null() { return -1; }
    let Some(colors) = case_key_prism(kind) else { return -1; };
    std::ptr::copy_nonoverlapping(colors.as_ptr().cast::<f64>(), output, 6);
    0
}

/// Caps uses the reference's expanding or contracting gauge; Shift uses moving crests.
// shortcut: Shift's layered prism and crest geometry need reference-frame comparison.
pub fn case_key_segments(kind: i32, elapsed: f64, path_length: f64, arm: f64) -> Option<Vec<LightSegment>> {
    if !(0..=2).contains(&kind) || !elapsed.is_finite() || !path_length.is_finite() || path_length <= 0.0 || !arm.is_finite() || arm < 0.0 { return None; }
    let duration = match kind { 0 => 0.78, 1 => 0.34, _ => f64::INFINITY };
    if !(0.0..duration).contains(&elapsed) { return Some(Vec::new()); }
    let pulse = |start: f64, duration: f64| {
        let phase = (elapsed - start) / duration;
        if (0.0..=1.0).contains(&phase) { (phase * PI).sin().max(0.0) } else { 0.0 }
    };
    match kind {
        0 | 1 => {
            let enabled = kind == 0;
            let travel = if enabled { 0.42 } else { 0.30 };
            let progress = smoothstep(elapsed / travel);
            let extent = if enabled { progress } else { 1.0 - progress };
            let fade = if enabled { (1.0 - (elapsed - 0.42).max(0.0) / 0.36).max(0.0) }
                       else { (1.0 - elapsed / 0.34).max(0.0) };
            let left = 0.5 - extent * 0.5;
            let right = 0.5 + extent * 0.5;
            let spread = 42.0 / path_length;
            let mut parts = vec![
                segment(left, right, (elapsed / 0.045).min(1.0) * 0.48 * fade, false),
                segment(left - spread, left + spread, 0.92 * fade, true),
                segment(right - spread, right + spread, 0.92 * fade, true),
            ];
            if enabled && elapsed > 0.38 {
                parts.push(segment(0.0, 1.0, 0.42 * pulse(0.38, 0.38), false));
            }
            Some(parts)
        },
        2 => {
            let progress = smoothstep(elapsed / 0.58);
            let position = 0.5 * progress;
            let fade = (elapsed / 0.07).min(1.0);
            let breathing = 0.8 + 0.1 * (1.0 - (2.0 * PI * elapsed / 1.9).cos());
            let alpha = fade * breathing;
            let left = 0.5 - position;
            let right = 0.5 + position;
            let spread = (arm * 0.22).max(30.0) / path_length;
            Some(vec![segment(0.0, 1.0, alpha * progress * 0.22, false),
                      segment(left - spread, left + spread, alpha * 0.85, true),
                      segment(right - spread, right + spread, alpha * 0.85, true)])
        },
        _ => unreachable!(),
    }
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_case_key_segments(kind: i32, elapsed: f64, path_length: f64, arm: f64, output: *mut f64, capacity: i32) -> i32 {
    if capacity < 0 || (output.is_null() && capacity != 0) { return -1; }
    let Some(segments) = case_key_segments(kind, elapsed, path_length, arm) else { return -1; };
    let count = segments.len() as i32;
    if output.is_null() && capacity == 0 { return count; }
    if capacity < count { return -2; }
    for (index, item) in segments.iter().enumerate() {
        let base = output.add(index * 4);
        *base = item.start; *base.add(1) = item.end; *base.add(2) = item.opacity;
        *base.add(3) = if item.highlight { 1.0 } else { 0.0 };
    }
    count
}

// shortcut: the pulse envelope and mute transitions need reference-frame comparison.
pub fn system_hud_interpolated_level(previous: f64, current: f64, elapsed: f64) -> Option<f64> {
    if !previous.is_finite() || !current.is_finite() || !elapsed.is_finite() { return None; }
    let from = previous.clamp(0.0, 1.0);
    let to = current.clamp(0.0, 1.0);
    Some(from + (to - from) * smoothstep(elapsed / 0.23))
}

#[no_mangle]
pub extern "C" fn rium_notch_system_hud_level(previous: f64, current: f64, elapsed: f64) -> f64 {
    system_hud_interpolated_level(previous, current, elapsed).unwrap_or(f64::NAN)
}

pub fn system_hud_pulse_energy(previous: f64, elapsed: f64) -> Option<f64> {
    if !previous.is_finite() || !elapsed.is_finite() || elapsed < 0.0 { return None; }
    Some((0.48 + 0.65 * previous.clamp(0.0, 1.0) * (1.0 - elapsed / 0.6).max(0.0)).min(1.0))
}

#[no_mangle]
pub extern "C" fn rium_notch_system_hud_pulse_energy(previous: f64, elapsed: f64) -> f64 {
    system_hud_pulse_energy(previous, elapsed).unwrap_or(f64::NAN)
}

/// LevelPrismFrame's end crest: position, normalized spread, line and opacity.
pub fn system_hud_pulse_crest(level: f64, energy: f64, elapsed: f64, path_length: f64) -> Option<[f64; 4]> {
    if ![level, energy, elapsed, path_length].iter().all(|value| value.is_finite()) || elapsed < 0.0 || path_length <= 0.0 { return None; }
    let pulse = energy.clamp(0.0, 1.0) * (1.0 - elapsed / 0.78).max(0.0);
    let spread = (24.0 + 46.0 * pulse) / path_length;
    if !spread.is_finite() { return None; }
    Some([level.clamp(0.0, 1.0), spread, 6.0 + 3.0 * pulse,
          if pulse > 0.005 { pulse } else { 0.0 }])
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_system_hud_pulse_crest(level: f64, energy: f64, elapsed: f64, path_length: f64, output: *mut f64) -> i32 {
    if output.is_null() { return -1; }
    let Some(frame) = system_hud_pulse_crest(level, energy, elapsed, path_length) else { return -1; };
    std::ptr::copy_nonoverlapping(frame.as_ptr(), output, frame.len());
    0
}

pub fn system_hud_restore_crests(level: f64, energy: f64, elapsed: f64, path_length: f64) -> Option<[f64; 4]> {
    let frame = system_hud_pulse_crest(level, energy, elapsed, path_length)?;
    let spread = 40.0 / path_length;
    if !spread.is_finite() { return None; }
    let movement = 0.5 * smoothstep(elapsed / 0.42);
    Some([(0.5 - movement) * frame[0], (0.5 + movement) * frame[0], spread, frame[3]])
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_system_hud_restore_crests(level: f64, energy: f64, elapsed: f64, path_length: f64, output: *mut f64) -> i32 {
    if output.is_null() { return -1; }
    let Some(frame) = system_hud_restore_crests(level, energy, elapsed, path_length) else { return -1; };
    std::ptr::copy_nonoverlapping(frame.as_ptr(), output, frame.len());
    0
}

pub fn system_hud_limit_flash(level: f64, energy: f64, elapsed: f64) -> Option<f64> {
    if ![level, energy, elapsed].iter().all(|value| value.is_finite()) || elapsed < 0.0 { return None; }
    let level = level.clamp(0.0, 1.0);
    let pulse = energy.clamp(0.0, 1.0) * (1.0 - elapsed / 0.78).max(0.0);
    if (0.001..=0.999).contains(&level) || pulse <= 0.005 || elapsed >= 0.5 { return Some(0.0); }
    Some((PI * (2.0 * elapsed).min(1.0)).sin() * pulse)
}

#[no_mangle]
pub extern "C" fn rium_notch_system_hud_limit_flash(level: f64, energy: f64, elapsed: f64) -> f64 {
    system_hud_limit_flash(level, energy, elapsed).unwrap_or(f64::NAN)
}

pub fn system_hud_brightness_flare(direction: f64, energy: f64, elapsed: f64) -> Option<[f64; 3]> {
    if ![direction, energy, elapsed].iter().all(|value| value.is_finite()) || elapsed < 0.0 { return None; }
    let pulse = energy.clamp(0.0, 1.0) * (1.0 - elapsed / 0.78).max(0.0);
    let growth = 1.0 - (-elapsed / 0.14).exp();
    let opacity = if pulse > 0.005 { pulse * if direction > 0.0 { 0.42 } else { 0.24 } } else { 0.0 };
    Some([12.0 + 24.0 * growth, 9.0 + 11.0 * growth, opacity])
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_system_hud_brightness_flare(direction: f64, energy: f64, elapsed: f64, output: *mut f64) -> i32 {
    if output.is_null() { return -1; }
    let Some(frame) = system_hud_brightness_flare(direction, energy, elapsed) else { return -1; };
    std::ptr::copy_nonoverlapping(frame.as_ptr(), output, frame.len());
    0
}

pub fn system_hud_volume_flare(level: f64, energy: f64, elapsed: f64) -> Option<[f64; 3]> {
    if ![level, energy, elapsed].iter().all(|value| value.is_finite()) || elapsed < 0.0 { return None; }
    let level = level.clamp(0.0, 1.0);
    let pulse = energy.clamp(0.0, 1.0) * (1.0 - elapsed / 0.78).max(0.0);
    Some([(level - 0.22 * pulse).max(0.0), level, if pulse > 0.005 { 0.7 * pulse } else { 0.0 }])
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_system_hud_volume_flare(level: f64, energy: f64, elapsed: f64, output: *mut f64) -> i32 {
    if output.is_null() { return -1; }
    let Some(frame) = system_hud_volume_flare(level, energy, elapsed) else { return -1; };
    std::ptr::copy_nonoverlapping(frame.as_ptr(), output, frame.len());
    0
}

pub fn system_mute_frame(elapsed: f64, arm: f64, path_length: f64, reduce_motion: bool) -> Option<[f64; 3]> {
    if !elapsed.is_finite() || elapsed < 0.0 || !arm.is_finite() || arm < 0.0 || !path_length.is_finite() || path_length <= 0.0 { return None; }
    let start = (arm / path_length).min(0.5);
    let half = if reduce_motion { 0.5 } else { 0.5 * smoothstep((elapsed - 0.06) / 0.42) };
    let width = 1.0 - 2.0 * start;
    Some([start + width * half, 1.0 - start - width * half, (1.0 - elapsed / 0.58).max(0.0)])
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_system_mute_frame(elapsed: f64, arm: f64, path_length: f64, reduce_motion: i32, output: *mut f64) -> i32 {
    if output.is_null() || !(0..=1).contains(&reduce_motion) { return -1; }
    let Some(frame) = system_mute_frame(elapsed, arm, path_length, reduce_motion == 1) else { return -1; };
    std::ptr::copy_nonoverlapping(frame.as_ptr(), output, frame.len());
    0
}

const SYSTEM_HUD_SECONDS: f64 = 1.35;

#[no_mangle]
pub extern "C" fn rium_notch_system_hud_seconds() -> f64 {
    SYSTEM_HUD_SECONDS
}

#[no_mangle]
pub extern "C" fn rium_notch_system_control_at_limit(percent: f64, direction: i32) -> i32 {
    i32::from(match direction {
        -1 => percent == 0.0,
        1 => percent == 100.0,
        _ => false,
    })
}

pub fn system_hud_segments(kind: i32, level: f64, elapsed: f64) -> Option<Vec<LightSegment>> {
    if !(0..=2).contains(&kind) || !level.is_finite() || !elapsed.is_finite() { return None; }
    if !(0.0..SYSTEM_HUD_SECONDS).contains(&elapsed) { return Some(Vec::new()); }
    let envelope = (elapsed / 0.18).min(1.0) * ((SYSTEM_HUD_SECONDS - elapsed) / 0.45).min(1.0);
    match kind {
        0 => {
            let value = level.clamp(0.0, 1.0);
            Some(vec![segment(0.0, value, 0.4 + value * 0.25, true)])
        },
        1 | 2 => {
            let progress = smoothstep(elapsed / 0.9);
            let width = 0.5 * if kind == 1 { 1.0 - progress } else { progress };
            Some(vec![segment(0.5 - width, 0.5 + width, envelope * if kind == 1 { 0.58 } else { 0.85 }, true)])
        },
        _ => unreachable!(),
    }
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_system_hud_segments(kind: i32, level: f64, elapsed: f64, output: *mut f64, capacity: i32) -> i32 {
    if capacity < 0 || (output.is_null() && capacity != 0) { return -1; }
    let Some(segments) = system_hud_segments(kind, level, elapsed) else { return -1; };
    let count = segments.len() as i32;
    if output.is_null() && capacity == 0 { return count; }
    if capacity < count { return -2; }
    for (index, item) in segments.iter().enumerate() {
        let base = output.add(index * 4);
        *base = item.start; *base.add(1) = item.end; *base.add(2) = item.opacity;
        *base.add(3) = if item.highlight { 1.0 } else { 0.0 };
    }
    count
}

/// Writes shortcut segments as start, end, opacity, highlight records.
#[no_mangle]
pub unsafe extern "C" fn rium_notch_shortcut_segments(kind: i32, elapsed: f64, output: *mut f64, capacity: i32) -> i32 {
    if capacity < 0 || (output.is_null() && capacity != 0) { return -1; }
    let Some(segments) = shortcut_segments(kind, elapsed) else { return -1; };
    let count = segments.len() as i32;
    if output.is_null() && capacity == 0 { return count; }
    if capacity < count { return -2; }
    for (index, item) in segments.iter().enumerate() {
        let base = output.add(index * 4);
        *base = item.start;
        *base.add(1) = item.end;
        *base.add(2) = item.opacity;
        *base.add(3) = if item.highlight { 1.0 } else { 0.0 };
    }
    count
}

/// Approximate icon movement paired with shortcut_segments. Values are
/// rotation in degrees, scale, x/y offsets, opacity and normalized phase.
pub fn shortcut_icon_frame(kind: i32, elapsed: f64, reduce_motion: bool) -> Option<[f64; 6]> {
    if !(0..=9).contains(&kind) || !elapsed.is_finite() { return None; }
    if reduce_motion { return Some([0.0, 1.0, 0.0, 0.0, 1.0, 1.0]); }
    let phase = (elapsed / 1.15).clamp(0.0, 1.0);
    let mut result = [0.0, 1.0, 0.0, 0.0, 1.0, phase];
    match kind {
        0 => { result[0] = 15.0 * (phase * 3.0 * PI).sin() * (1.0 - phase); }
        1 => { result[0] = -28.0 * (phase * PI).sin(); result[2] = -2.0 * (phase * PI).sin(); }
        2 => { result[1] = 0.72 + 0.28 * smoothstep(phase / 0.55); }
        3 => { result[0] = phase * 360.0; }
        4 => { result[3] = -1.0; }
        5 => { result[1] = 1.0 + 0.14 * (phase * PI).sin(); }
        6 => { result[4] = (1.0 - phase * 0.8).max(0.2); }
        7 => { result[3] = -2.0 * (phase * PI).sin(); }
        8 => { result[1] = 1.0 + 0.12 * (phase * PI).sin(); }
        9 => { result[1] = 0.85 + 0.15 * smoothstep(phase / 0.5); }
        _ => unreachable!(),
    }
    Some(result)
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_shortcut_icon_frame(kind: i32, elapsed: f64, reduce_motion: i32, output: *mut f64) -> i32 {
    if output.is_null() || !(0..=1).contains(&reduce_motion) { return -1; }
    let Some(frame) = shortcut_icon_frame(kind, elapsed, reduce_motion == 1) else { return -1; };
    for (index, value) in frame.iter().enumerate() { *output.add(index) = *value; }
    0
}

/// Music ripple period follows the current reconstruction; its exact source
/// timing is not yet established. A negative time wraps consistently.
pub fn music_ripple_phase(time: f64, offset: f64) -> Option<f64> {
    if !time.is_finite() || !offset.is_finite() { return None; }
    let value = time / 2.7 + offset;
    if !value.is_finite() { return None; }
    Some(value - value.floor())
}

/// HomeMusicWaveWidget's 26 fixed bars use a deterministic baseline and an
/// additional time-varying oscillation only while media is playing.
pub fn home_music_wave_height(index: i32, time: f64, playing: bool, reduce_motion: bool) -> Option<f64> {
    if !(0..26).contains(&index) || !time.is_finite() { return None; }
    let i = f64::from(index);
    let baseline = (18.0 * (i * 0.9).sin() + 7.0 * (i * 0.37).cos()).abs();
    let motion = if playing && !reduce_motion { 6.0 * (time * 2.4 + i * 0.7).sin().abs() } else { 0.0 };
    Some(5.0 + baseline + motion)
}

#[no_mangle]
pub extern "C" fn rium_home_music_wave_height(index: i32, time: f64, playing: i32, reduce_motion: i32) -> f64 {
    if !(0..=1).contains(&playing) || !(0..=1).contains(&reduce_motion) { return -1.0; }
    home_music_wave_height(index, time, playing == 1, reduce_motion == 1).unwrap_or(-1.0)
}

/// Source card's 14-bar signal uses a paired sine/cosine oscillator.
pub fn home_source_wave_height(index: i32, time: f64, playing: bool, reduce_motion: bool) -> Option<f64> {
    if !(0..14).contains(&index) || !time.is_finite() || time.abs() > f64::MAX / 3.0 { return None; }
    if !playing || reduce_motion { return Some(4.95); }
    let i = f64::from(index);
    Some(3.0 + 13.0 * (0.25 + 0.75 * ((time * 3.0 + i * 0.9).sin() * (time * 1.7 + i).cos()).abs()))
}

#[no_mangle]
pub extern "C" fn rium_home_source_wave_height(index: i32, time: f64, playing: i32, reduce_motion: i32) -> f64 {
    if !(0..=1).contains(&playing) || !(0..=1).contains(&reduce_motion) { return -1.0; }
    home_source_wave_height(index, time, playing == 1, reduce_motion == 1).unwrap_or(-1.0)
}

fn music_wave_random(mut value: u64) -> f64 {
    value = (value ^ (value >> 30)).wrapping_mul(0xbf58_476d_1ce4_e5b9);
    value = (value ^ (value >> 27)).wrapping_mul(0x94d0_49bb_1331_11eb);
    ((value ^ (value >> 31)) & 0xffff) as f64 / 65535.0
}

fn synthetic_music_wave(index: i32, time: f64, seed: u64) -> f64 {
    let offset = 0x9e37_79b9_7f4a_7c15u64.wrapping_mul(index as u64 + 1);
    let random = |salt: u64| music_wave_random((seed ^ salt).wrapping_add(offset));
    // Keep the noise step inside the integer range even for malformed clock values.
    let time = time.rem_euclid(1e12);
    let tempo = 92.0 + 34.0 * music_wave_random(seed ^ 0xa24b_aed4_963e_e407);
    let beat = (time / (60.0 / tempo)).fract();
    let kick = (-6.4 * beat).exp();
    let offbeat = (-8.4 * (beat + 0.5).fract()).exp();
    let phase = random(!30) + time / (0.24 + 0.12 * random(!18));
    let step = phase.floor() as u64;
    let progress = phase - phase.floor();
    let blend = progress * progress * (3.0 - 2.0 * progress);
    let noise = random(step) + (random(step + 1) - random(step)) * blend;
    let opposite = if index % 2 == 1 { 1.0 - noise } else { noise };
    ((0.68 + 0.32 * random(!42)) * (0.22 * kick + 0.24 * offbeat)
        + (0.25 * noise + 0.75 * opposite) * 0.38 + 0.12).clamp(0.0, 1.0)
}

/// Compact music bars, using captured levels only when the user enabled them.
pub fn collapsed_music_wave_height(index: i32, time: f64, levels: Option<&[f64]>, reduce_motion: bool) -> Option<f64> {
    collapsed_music_wave_frame(index, time, levels, reduce_motion, 0xcbf2_9ce4_8422_2325, time).map(|frame| frame[0])
}

fn collapsed_music_wave_frame(index: i32, time: f64, levels: Option<&[f64]>, reduce_motion: bool, seed: u64, playback_time: f64) -> Option<[f64; 2]> {
    if !(0..6).contains(&index) || !time.is_finite() || !playback_time.is_finite() || time.abs() > (f64::MAX - 13.0) / 6.0 { return None; }
    let envelope = 0.78 + 0.22 * ((f64::from(index) + 1.0) * std::f64::consts::PI / 7.0).sin();
    let (signal, base, weight) = if reduce_motion {
        let offset = 0x9e37_79b9_7f4a_7c15u64.wrapping_mul(index as u64 + 1);
        (0.24 + 0.06 * music_wave_random((seed ^ !6).wrapping_add(offset)), 0.34, 0.42)
    } else if let Some(levels) = levels {
        if levels.len() != 6 || levels.iter().any(|v| !v.is_finite() || !(0.0..=1.0).contains(v)) { return None; }
        let pulse = 0.75 + 0.25 * (time * 6.0 + f64::from(index) * 2.6).sin();
        (levels[index as usize] * pulse, 0.2, 0.8)
    } else {
        (synthetic_music_wave(index, playback_time, seed), 0.34, 0.42)
    };
    Some([(21.6 * (base + weight * signal * envelope)).clamp(5.76, 24.0), 0.55 + 0.42 * signal])
}

#[no_mangle]
pub unsafe extern "C" fn rium_collapsed_music_wave_height(index: i32, time: f64, levels: *const f64, count: usize, reduce_motion: i32) -> f64 {
    if !(0..=1).contains(&reduce_motion) || (levels.is_null() && count != 0) || (!levels.is_null() && count != 6) { return -1.0; }
    let levels = if levels.is_null() { None } else { Some(std::slice::from_raw_parts(levels, count)) };
    collapsed_music_wave_height(index, time, levels, reduce_motion == 1).unwrap_or(-1.0)
}

#[no_mangle]
pub unsafe extern "C" fn rium_collapsed_music_wave_frame(index: i32, time: f64, levels: *const f64, count: usize, reduce_motion: i32, seed: u64, playback_time: f64, output: *mut f64) -> i32 {
    if output.is_null() || !(0..=1).contains(&reduce_motion) || (levels.is_null() && count != 0) || (!levels.is_null() && count != 6) { return -1; }
    let levels = if levels.is_null() { None } else { Some(std::slice::from_raw_parts(levels, count)) };
    let Some(frame) = collapsed_music_wave_frame(index, time, levels, reduce_motion == 1, seed, playback_time) else { return -1; };
    std::ptr::copy_nonoverlapping(frame.as_ptr(), output, frame.len());
    0
}

/// SpinningDisc advances 150 degrees per second, retaining its angle on pause.
pub fn home_disc_angle(base: f64, elapsed: f64) -> Option<f64> {
    if !base.is_finite() || !elapsed.is_finite() || elapsed < 0.0 { return None; }
    // Reduce before multiplying so a long sleep cannot overflow the angle.
    Some((base.rem_euclid(360.0) + (elapsed % 2.4) * 150.0).rem_euclid(360.0))
}

#[no_mangle]
pub extern "C" fn rium_home_disc_angle(base: f64, elapsed: f64) -> f64 {
    home_disc_angle(base, elapsed).unwrap_or(0.0)
}

/// Remaining fraction follows MusicProgressGlow's clamp(1 - elapsed / duration).
pub fn music_remaining_fraction(elapsed: f64, duration: f64) -> Option<f64> {
    if !elapsed.is_finite() || !duration.is_finite() || duration <= 0.0 { return None; }
    Some((1.0 - elapsed / duration).clamp(0.0, 1.0))
}

#[no_mangle]
pub extern "C" fn rium_music_remaining_fraction(elapsed: f64, duration: f64) -> f64 {
    music_remaining_fraction(elapsed, duration).unwrap_or(-1.0)
}

/// The notch's elapsed-progress light fills as playback advances.
pub fn music_progress_fraction(elapsed: f64, duration: f64) -> Option<f64> {
    music_remaining_fraction(elapsed, duration).map(|remaining| 1.0 - remaining)
}

#[no_mangle]
pub extern "C" fn rium_music_progress_fraction(elapsed: f64, duration: f64) -> f64 {
    music_progress_fraction(elapsed, duration).unwrap_or(-1.0)
}

/// The crest's 0.13 fade width and 0.01...0.99 peak clamp were observed in
/// the original's static instructions. Output is ordered at both screen edges.
pub fn music_crest_positions(center: f64) -> Option<[f64; 3]> {
    if !center.is_finite() { return None; }
    let peak = center.clamp(0.01, 0.99);
    Some([(peak - 0.13).max(0.0), peak, (peak + 0.13).min(1.0)])
}

/// AmbientContour's edge fade: the system HUD and notification glow supply 20 points.
pub fn system_tip_fade_fraction(glow_width: f64) -> Option<f64> {
    if !glow_width.is_finite() || glow_width < 1.0 { return None; }
    Some((20.0 / glow_width).min(0.25))
}

// shortcut: pulse period and intensity are estimates until frame comparison.
#[no_mangle]
pub extern "C" fn rium_notch_timer_pulse(time: f64, reduce_motion: i32) -> f64 {
    if !time.is_finite() || !(0..=1).contains(&reduce_motion) { return 0.0; }
    if reduce_motion == 1 { return 0.35; }
    0.28 + 0.25 * (0.5 + 0.5 * (2.0 * PI * time.rem_euclid(1.6) / 1.6).sin())
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_system_tip_fade(glow_width: f64, output: *mut f64) -> i32 {
    if output.is_null() { return -1; }
    let Some(fraction) = system_tip_fade_fraction(glow_width) else { return -1; };
    *output = fraction;
    0
}

/// Parameters of the organic light's per-arm fog. The geometry and gradient
/// are from static Glance 0.4.1 observations (REA ev_5cbbb3e3d52845a95319d0348de664589c8cd53db1b5f7bf49b271adb11f8618).
/// The caller still determines the original's scale, position, tint, and
/// clipping, which are not established by this calculation.
/// Returns width, height, three vertical opacities and the two inner fade stops.
pub fn organic_ray_fog(arm_width: f64, scale: f64) -> Option<[f64; 7]> {
    if !arm_width.is_finite() || !scale.is_finite() || arm_width < 0.0 || scale < 0.0 { return None; }
    let width = (arm_width - 14.0).max(40.0) + 34.0;
    let height = (scale * 20.0 + 40.0) * 0.9;
    let first_opacity = scale * 0.05 + 0.11;
    let fade = (30.0 / width.max(1.0)).clamp(0.08, 0.3);
    let result = [width, height, first_opacity, 0.04, 0.0, fade, 1.0 - fade];
    if result.iter().all(|x| x.is_finite()) { Some(result) } else { None }
}

/// OrganicRaysNotchLight's per-ray geometry: distance, length, width,
/// rotation in degrees and base opacity. Placement and layer blending remain
/// the responsibility of the platform renderer.
pub fn organic_ray(index: i32, count: i32, side: i32, arm_width: f64, scale: f64, thickness: f64) -> Option<[f64; 5]> {
    if !(1..=34).contains(&count) || !(0..count).contains(&index) || ![-1, 1].contains(&side)
        || ![arm_width, scale, thickness].iter().all(|value| value.is_finite() && *value >= 0.0) { return None; }
    let seed = index as f64 * 34.17;
    let random = |offset: f64| { let value = (seed + offset).sin() * 6151.71; value - value.floor() };
    let position = (if count > 1 { index as f64 / (count - 1) as f64 } else { 0.0 }
        + (random(if side < 0 { 21.703 } else { 53.271 }) - 0.5) * 0.06).clamp(0.0, 1.0);
    let edge = 1.0 - 0.45 * position * position;
    let result = [
        position * (arm_width - 14.0).max(40.0),
        (random(100.623) * 0.4 + 0.6) * (edge * 0.28 + 0.72) * (scale * 20.0 + 40.0),
        (random(171.651) * 3.0 + 1.3) * thickness,
        (5.0 + position * 12.0) * side as f64 + (random(65.109) - 0.5) * 4.0,
        (random(76.947) * 0.09 + 0.06) * edge,
    ];
    result.iter().all(|value| value.is_finite()).then_some(result)
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_organic_ray(index: i32, count: i32, side: i32, arm_width: f64, scale: f64, thickness: f64, output: *mut f64) -> i32 {
    if output.is_null() { return -1; }
    let Some(values) = organic_ray(index, count, side, arm_width, scale, thickness) else { return -1; };
    std::ptr::copy_nonoverlapping(values.as_ptr(), output, values.len());
    0
}

/// Reference humidity specks use a static field, denser near the top.
/// Returns normalized x/y, radius and base opacity; a separate mask fades
/// the field's edges in the platform renderer.
pub fn humidity_speck(index: usize, width: f64, height: f64, scale: f64) -> Option<[f64; 4]> {
    if index >= 1400 || ![width, height, scale].iter().all(|value| value.is_finite())
        || width <= 1.0 || height <= 1.0 || scale < 0.0 { return None; }
    static FIELD: std::sync::OnceLock<[[f64; 4]; 1400]> = std::sync::OnceLock::new();
    let [x, y, radius, density] = FIELD.get_or_init(|| std::array::from_fn(|index| {
        let seed = index as f64 * 12.9898;
        let random = |offset: f64| { let value = (seed + offset).sin() * 43758.5453; value - value.floor() };
        let y = random(336.4019).powi(2);
        let x = 0.5 + (random(132.9961) - 0.5) * 2.0 * (0.42 + 0.08 * y);
        let radius = random(172.1126) * 0.45 + 0.35;
        let density = (random(711.9203) * 0.7 + 0.3) * (1.0 - 0.85 * y);
        [x, y, radius, density]
    }))[index];
    let opacity = density * (scale * 0.7 * 0.2 + 0.04);
    if !opacity.is_finite() || opacity <= 0.003 { return None; }
    Some([x, y, radius, opacity])
}

/// Writes x/y/radius/opacity for up to 1400 specks into the supplied buffer.
#[no_mangle]
pub unsafe extern "C" fn rium_notch_humidity_specks(width: f64, height: f64, scale: f64, output: *mut f64, capacity: usize) -> i32 {
    if output.is_null() || capacity < 1400 * 4 || ![width, height, scale].iter().all(|value| value.is_finite())
        || width <= 1.0 || height <= 1.0 || scale < 0.0 { return -1; }
    let count = ((width.min(1400.0 / 2.6) * 2.6) as usize).clamp(120, 1400);
    let mut written = 0;
    for index in 0..count {
        if let Some(values) = humidity_speck(index, width, height, scale) {
            std::ptr::copy_nonoverlapping(values.as_ptr(), output.add(written * 4), 4);
            written += 1;
        }
    }
    written as i32
}

/// Subtle breathing for a steady light: line opacity multiplier, glow opacity
/// multiplier, and contour-width multiplier. This is a visual approximation,
/// not a claim about original timing. Modulo the common period keeps these
/// periodic waves continuous even when the supplied monotonic clock is large.
pub fn idle_light_frame(time: f64, reduce_motion: bool) -> Option<[f64; 3]> {
    if !time.is_finite() { return None; }
    if reduce_motion { return Some([1.0, 1.0, 1.0]); }
    let t = time.rem_euclid(180.0);
    let breath = (2.0 * PI * t / 6.0).sin();
    let drift = (2.0 * PI * t / 15.0).sin();
    Some([1.0 + 0.045 * breath + 0.015 * drift,
          1.0 + 0.09 * breath + 0.025 * drift,
          1.0 + 0.018 * breath])
}

/// A slow spatial shimmer for the always-on idle light. Position and strength
/// are deliberately small; the reference's idle layer is not yet identified.
// shortcut: timing and intensity need comparison with the reference frames.
pub fn idle_shimmer_frame(time: f64, reduce_motion: bool) -> Option<[f64; 2]> {
    if !time.is_finite() { return None; }
    if reduce_motion { return Some([0.5, 0.0]); }
    let t = time.rem_euclid(70.0);
    // Separate the traveling highlight from the six-second brightness breath.
    let position = 0.5 + 0.20 * (2.0 * PI * t / 14.0).sin() + 0.07 * (2.0 * PI * t / 35.0).sin();
    let strength = 0.055 + 0.014 * (2.0 * PI * t / 10.0).sin();
    Some([position, strength])
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_idle_shimmer(time: f64, reduce_motion: i32, output: *mut f64) -> i32 {
    if output.is_null() || !(0..=1).contains(&reduce_motion) { return -1; }
    let Some(values) = idle_shimmer_frame(time, reduce_motion == 1) else { return -1; };
    *output = values[0]; *output.add(1) = values[1];
    0
}

/// The shelf hover sends two staggered crests toward the notch every 1.5 seconds.
pub fn shelf_hover_progress(time: f64, reduce_motion: bool) -> Option<[f64; 2]> {
    if !time.is_finite() { return None; }
    if reduce_motion { return Some([0.0, 0.0]); }
    let phase = (time / 1.5).rem_euclid(1.0);
    let smooth = |v: f64| { let x = v.clamp(0.0, 1.0); x * x * (3.0 - 2.0 * x) };
    Some([smooth(phase), smooth(phase - 0.34)])
}

#[no_mangle]
pub unsafe extern "C" fn rium_shelf_hover_progress(time: f64, reduce_motion: i32, output: *mut f64) -> i32 {
    if output.is_null() || !(0..=1).contains(&reduce_motion) { return -1; }
    let Some(values) = shelf_hover_progress(time, reduce_motion == 1) else { return -1; };
    *output = values[0]; *output.add(1) = values[1];
    0
}

/// The shelf catch enters in 0.08 seconds, travels in 0.3 and fades over the final 0.22.
pub fn shelf_catch_frame(elapsed: f64, reduce_motion: bool) -> Option<[f64; 2]> {
    if !elapsed.is_finite() || elapsed < 0.0 { return None; }
    let rise = (elapsed / 0.08).min(1.0);
    let fade = ((0.62 - elapsed) / 0.22).clamp(0.0, 1.0);
    let x = if reduce_motion { 1.0 } else { (elapsed / 0.3).min(1.0) };
    Some([x * x * (3.0 - 2.0 * x), rise.min(fade)])
}

#[no_mangle]
pub unsafe extern "C" fn rium_shelf_catch_frame(elapsed: f64, reduce_motion: i32, output: *mut f64) -> i32 {
    if output.is_null() || !(0..=1).contains(&reduce_motion) { return -1; }
    let Some(values) = shelf_catch_frame(elapsed, reduce_motion == 1) else { return -1; };
    *output = values[0]; *output.add(1) = values[1];
    0
}

/// AssistantOrganicLight.travel: paired crests are half a cycle apart.
/// The reference uses a 1.45 s cycle for acting and 2.1 s otherwise.
pub fn agent_organic_travel(time: f64, acting: bool, reduce_motion: bool) -> Option<[f64; 2]> {
    if !time.is_finite() || time < 0.0 { return None; }
    let period = if acting { 1.45 } else { 2.1 };
    let time = if reduce_motion { 0.6 } else { time };
    let first = time.rem_euclid(period) / period;
    Some([first, (first + 0.5).rem_euclid(1.0)])
}

/// Reconstructed contour fraction and opacity for the two organic crests.
/// Thinking mirrors the second crest; other states keep both moving forward.
pub fn agent_organic_crests(time: f64, acting: bool, thinking: bool, reduce_motion: bool) -> Option<[[f64; 2]; 2]> {
    let phases = agent_organic_travel(time, acting, reduce_motion)?;
    Some(std::array::from_fn(|index| {
        let phase = phases[index];
        let position_phase = if thinking && index == 1 { 1.0 - phase } else { phase };
        [0.04 + 0.92 * position_phase, (2.0 * (PI * phase).sin()).clamp(0.0, 1.0)]
    }))
}

#[no_mangle]
pub unsafe extern "C" fn rium_agent_organic_crests(time: f64, acting: i32, thinking: i32, reduce_motion: i32, output: *mut f64) -> i32 {
    if output.is_null() || !(0..=1).contains(&acting) || !(0..=1).contains(&thinking)
        || !(0..=1).contains(&reduce_motion) { return -1; }
    let Some(crests) = agent_organic_crests(time, acting == 1, thinking == 1, reduce_motion == 1) else { return -1; };
    for (index, crest) in crests.iter().enumerate() {
        *output.add(index * 2) = crest[0];
        *output.add(index * 2 + 1) = crest[1];
    }
    0
}

// Reference DictationAuroraPalette: six colours sampled at 41 positions.
pub fn dictation_aurora_palette(time: f64, cycles: f64, whiten: f64, reduce_motion: bool) -> Option<[[f64; 3]; 41]> {
    if ![time, cycles, whiten].iter().all(|value| value.is_finite())
        || !(0.0..=4.0).contains(&cycles) || !(0.0..=1.0).contains(&whiten) { return None; }
    let colors = [[0.82, 0.27, 0.60], [0.61, 0.25, 0.72], [0.43, 0.49, 0.91],
                  [0.18, 0.72, 0.76], [0.94, 0.60, 0.35], [0.88, 0.31, 0.48]];
    let t = if reduce_motion { 0.6 } else { time.rem_euclid(5.0) };
    Some(std::array::from_fn(|index| {
        let position = (index as f64 / 40.0 * cycles - t * 0.2).rem_euclid(1.0) * 6.0;
        let start = position.floor() as usize % colors.len();
        let blend = smoothstep(position.fract());
        std::array::from_fn(|channel| {
            let base = colors[start][channel] + (colors[(start + 1) % 6][channel] - colors[start][channel]) * blend;
            base + ([0.96, 0.97, 1.0][channel] - base) * whiten
        })
    }))
}

#[no_mangle]
pub unsafe extern "C" fn rium_dictation_aurora_palette(time: f64, cycles: f64, whiten: f64, reduce_motion: i32, output: *mut f64) -> i32 {
    if output.is_null() || !(0..=1).contains(&reduce_motion) { return -1; }
    let Some(colors) = dictation_aurora_palette(time, cycles, whiten, reduce_motion == 1) else { return -1; };
    std::ptr::copy_nonoverlapping(colors.as_ptr().cast::<f64>(), output, 41 * 3);
    0
}

const ORGANIC_GLACIER: [[f64; 3]; 5] = [[0.72, 0.90, 1.0], [0.20, 0.80, 0.98],
    [0.28, 0.46, 0.98], [0.62, 0.46, 1.0], [0.86, 0.92, 1.0]];
const ORGANIC_AMBER: [[f64; 3]; 4] = [[1.0, 0.80, 0.34], [1.0, 0.60, 0.22],
    [1.0, 0.88, 0.58], [0.99, 0.68, 0.36]];

fn organic_palette_color(approval: bool, position: f64, whiten: f64) -> [f64; 3] {
    let palette: &[[f64; 3]] = if approval { &ORGANIC_AMBER } else { &ORGANIC_GLACIER };
    let position = position.rem_euclid(1.0) * palette.len() as f64;
    let start = position.floor() as usize % palette.len();
    let blend = smoothstep(position.fract());
    std::array::from_fn(|channel| {
        let color = palette[start][channel] + (palette[(start + 1) % palette.len()][channel] - palette[start][channel]) * blend;
        color + ([0.96, 0.97, 1.0][channel] - color) * whiten
    })
}

/// AssistantOrganicLight samples its state's palette at 0 and 0.45, then
/// blends each sample 40% toward its cool-white highlight colour.
pub fn agent_organic_crest_colors(approval: bool) -> [[f64; 3]; 2] {
    std::array::from_fn(|index| organic_palette_color(approval, index as f64 * 0.45, 0.4))
}

#[no_mangle]
pub unsafe extern "C" fn rium_agent_organic_crest_colors(approval: i32, output: *mut f64) -> i32 {
    if output.is_null() || !(0..=1).contains(&approval) { return -1; }
    let colors = agent_organic_crest_colors(approval == 1);
    std::ptr::copy_nonoverlapping(colors.as_ptr().cast::<f64>(), output, 6);
    0
}

/// Non-completion organic gradient: 41 samples, 1.1 cycles across the
/// surface, advancing by a quarter of a palette cycle per second.
pub fn agent_organic_palette(time: f64, approval: bool, reduce_motion: bool, whiten: f64) -> Option<[[f64; 3]; 41]> {
    if !time.is_finite() || !whiten.is_finite() || !(0.0..=1.0).contains(&whiten) { return None; }
    let t = if reduce_motion { 0.6 } else { time.rem_euclid(4.0) };
    Some(std::array::from_fn(|index| organic_palette_color(approval, index as f64 / 40.0 * 1.1 - t * 0.25, whiten)))
}

#[no_mangle]
pub unsafe extern "C" fn rium_agent_organic_palette(time: f64, approval: i32, reduce_motion: i32, whiten: f64, output: *mut f64) -> i32 {
    if output.is_null() || !(0..=1).contains(&approval) || !(0..=1).contains(&reduce_motion) { return -1; }
    let Some(colors) = agent_organic_palette(time, approval == 1, reduce_motion == 1, whiten) else { return -1; };
    std::ptr::copy_nonoverlapping(colors.as_ptr().cast::<f64>(), output, 41 * 3);
    0
}

#[no_mangle]
pub unsafe extern "C" fn rium_agent_organic_travel(time: f64, acting: i32, reduce_motion: i32, output: *mut f64) -> i32 {
    if output.is_null() || !(0..=1).contains(&acting) || !(0..=1).contains(&reduce_motion) { return -1; }
    let Some(positions) = agent_organic_travel(time, acting == 1, reduce_motion == 1) else { return -1; };
    *output = positions[0];
    *output.add(1) = positions[1];
    0
}

/// Gentle activity light modulation. AssistantOrganicLight's time-based
/// breath has a 1.9-second period; its application to this persistent layer
/// and the moving crest's intensity still need reference comparison.
/// Values are contour opacity, halo opacity, crest position and crest opacity.
pub fn agent_light_frame(time: f64, reduce_motion: bool) -> Option<[f64; 4]> {
    if !time.is_finite() { return None; }
    if reduce_motion { return Some([1.0, 1.0, 0.5, 0.0]); }
    // shortcut: The original branch and light-layer mapping are unverified.
    // 190 seconds is a common period for 1.9- and 10-second oscillations.
    let t = time.rem_euclid(190.0);
    let breath = (2.0 * PI * t / 1.9).sin();
    let drift = (2.0 * PI * t / 10.0).sin();
    Some([1.0 + 0.025 * breath,
          1.0 + 0.065 * breath + 0.015 * drift,
          0.5 + 0.3 * drift,
          0.055 + 0.015 * breath])
}

/// AssistantQuestionLight's 2.5-second pulse and regular-notch halo size.
pub fn question_light_frame(time: f64, notch_width: f64, reduce_motion: bool) -> Option<[f64; 3]> {
    if !time.is_finite() || !notch_width.is_finite() || notch_width < 0.0 { return None; }
    let time = if reduce_motion { 0.6 } else { time.rem_euclid(2.5) };
    let pulse = 0.5 - 0.5 * (2.0 * PI * time / 2.5).cos();
    Some([pulse, notch_width * (0.48 + 0.12 * pulse), 42.0 + 28.0 * pulse])
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_question_light(time: f64, notch_width: f64, reduce_motion: i32, output: *mut f64) -> i32 {
    if output.is_null() || !(0..=1).contains(&reduce_motion) { return -1; }
    let Some(frame) = question_light_frame(time, notch_width, reduce_motion == 1) else { return -1; };
    std::ptr::copy_nonoverlapping(frame.as_ptr(), output, frame.len());
    0
}

fn question_palette_color(position: f64, whiten: f64) -> [f64; 3] {
    let colors = [[1.0, 0.80, 0.34], [1.0, 0.60, 0.22], [1.0, 0.88, 0.58], [0.99, 0.68, 0.36]];
    let position = position.rem_euclid(1.0) * 4.0;
    let start = position.floor() as usize % colors.len();
    let blend = smoothstep(position.fract());
    std::array::from_fn(|channel| {
        let color = colors[start][channel] + (colors[(start + 1) % 4][channel] - colors[start][channel]) * blend;
        color + ([0.96, 0.97, 1.0][channel] - color) * whiten
    })
}

/// Forty-one leading-to-trailing samples of the reference question aurora.
pub fn question_light_palette(time: f64, reduce_motion: bool, whiten: f64) -> Option<[[f64; 3]; 41]> {
    if !time.is_finite() || !whiten.is_finite() || !(0.0..=1.0).contains(&whiten) { return None; }
    let t = if reduce_motion { 0.6 } else { time.rem_euclid(12.5) };
    Some(std::array::from_fn(|index| {
        question_palette_color(index as f64 / 40.0 * 1.2 - t * 0.08, whiten)
    }))
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_question_palette(time: f64, reduce_motion: i32, whiten: f64, output: *mut f64) -> i32 {
    if output.is_null() || !(0..=1).contains(&reduce_motion) { return -1; }
    let Some(colors) = question_light_palette(time, reduce_motion == 1, whiten) else { return -1; };
    std::ptr::copy_nonoverlapping(colors.as_ptr().cast::<f64>(), output, 41 * 3);
    0
}

/// Question highlight extends 30 points beyond each lower-corner midpoint.
pub fn question_highlight_range(arm: f64, upper_arc: f64, side: f64, lower_arc: f64, length: f64) -> Option<[f64; 2]> {
    if ![arm, upper_arc, side, lower_arc, length].iter().all(|v| v.is_finite())
        || [arm, upper_arc, side, lower_arc].iter().any(|v| *v < 0.0) || length <= 0.0 { return None; }
    let start = ((arm + upper_arc + side + lower_arc / 2.0 - 30.0) / length).clamp(0.0, 0.5);
    Some([start, 1.0 - start])
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_question_highlight(arm: f64, upper_arc: f64, side: f64, lower_arc: f64, length: f64, output: *mut f64) -> i32 {
    if output.is_null() { return -1; }
    let Some(values) = question_highlight_range(arm, upper_arc, side, lower_arc, length) else { return -1; };
    std::ptr::copy_nonoverlapping(values.as_ptr(), output, values.len());
    0
}

/// Two inward-moving question crests: positions, half-spread, opacity, RGB.
pub fn question_crests(time: f64, path_length: f64) -> Option<[f64; 7]> {
    if !time.is_finite() || !path_length.is_finite() || path_length <= 0.0 { return None; }
    let phase = time.rem_euclid(2.5) / 2.5;
    let distance = 0.46 - 0.40 * phase;
    let color = question_palette_color(phase * 0.30, 0.20);
    Some([0.5 - distance, 0.5 + distance, 82.0 / path_length,
          0.72 * (PI * phase).sin(), color[0], color[1], color[2]])
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_question_crests(time: f64, path_length: f64, output: *mut f64) -> i32 {
    if output.is_null() { return -1; }
    let Some(values) = question_crests(time, path_length) else { return -1; };
    std::ptr::copy_nonoverlapping(values.as_ptr(), output, values.len());
    0
}

/// The timer's two gauge endpoints contract symmetrically along the card span.
/// Positions are relative to a contour without the optional outer arms.
pub fn timer_contour_crests(fraction: f64, path_length: f64) -> Option<[f64; 3]> {
    if !fraction.is_finite() || !path_length.is_finite() || path_length <= 0.0 { return None; }
    let half = fraction.clamp(0.0, 1.0) / 2.0;
    Some([0.5 - half, 0.5 + half, 16.0 / path_length])
}

#[no_mangle]
pub unsafe extern "C" fn rium_timer_contour_crests(fraction: f64, path_length: f64, output: *mut f64) -> i32 {
    if output.is_null() { return -1; }
    let Some(values) = timer_contour_crests(fraction, path_length) else { return -1; };
    std::ptr::copy_nonoverlapping(values.as_ptr(), output, values.len());
    0
}

/// Normalize pointer coordinates as observed in the modified reference.
pub fn lumi_pointer_gaze(x: f64, y: f64, width: f64, height: f64) -> Option<[f64; 2]> {
    if ![x, y, width, height].iter().all(|v| v.is_finite()) || width <= 0.0 || height <= 0.0 { return None; }
    Some([(2.0 * (x / width - 0.5)).clamp(-1.0, 1.0),
          (2.0 * (y / height - 0.5)).clamp(-1.0, 1.0)])
}

/// Reference selection table: one or two recent clicks depend on mood; clicks
/// three through five choose dizzy and six or more choose turn.
pub fn lumi_reaction_kind(mood: i32, clicks: u32) -> Option<i32> {
    let first = [0, 1, 2, 3, 4, 5, 1, 6, 7];
    if !(0..=8).contains(&mood) || clicks == 0 { return None; }
    Some(if clicks > 5 { 9 } else if clicks > 2 { 8 } else { first[mood as usize] })
}

pub fn lumi_reaction_duration(kind: i32) -> Option<f64> {
    [1.0, 1.0, 1.2, 1.0, 1.1, 1.4, 1.2, 1.0, 1.1, 2.2].get(usize::try_from(kind).ok()?).copied()
}

#[no_mangle]
pub extern "C" fn rium_notch_lumi_reaction_duration(kind: i32) -> f64 {
    lumi_reaction_duration(kind).unwrap_or(-1.0)
}

/// Face overrides observed in LumiReaction.apply.
pub fn lumi_reaction_face(kind: i32, elapsed: f64, reduce_motion: bool) -> Option<i32> {
    let duration = lumi_reaction_duration(kind)?;
    if !elapsed.is_finite() || elapsed < 0.0 { return None; }
    if reduce_motion || elapsed >= duration { return Some(-1); }
    let t = elapsed / duration;
    Some(match kind {
        0 | 4 => 6,
        1 => 7,
        2 | 7 => 8,
        3 => 9,
        5 => 10,
        6 if t < 0.6 => 8,
        8 => 11,
        9 if t > 0.12 && t < 0.88 => 12,
        _ => -1,
    })
}

/// Select Rium's expression; an active interaction takes precedence over mood.
pub fn rium_character_expression(mood: i32, reaction: i32) -> Option<i32> {
    if !(0..=8).contains(&mood) || !(-1..=12).contains(&reaction) { return None; }
    Some(if reaction >= 0 { reaction } else {
        match mood { 4 => 2, 5 => 3, 7 => 4, 8 => 5, _ => 0 }
    })
}

#[no_mangle]
pub extern "C" fn rium_character_face(mood: i32, reaction: i32) -> i32 {
    rium_character_expression(mood, reaction).unwrap_or(-1)
}

/// Rium's idle glance: pause at the center and on each side between turns.
pub fn rium_idle_gaze(time: f64, reduce_motion: bool) -> Option<f64> {
    if !time.is_finite() { return None; }
    if reduce_motion { return Some(0.0); }
    let phase = time.rem_euclid(9.0) / 9.0;
    Some(smooth_keyframes(phase, &[
        (0.0, 0.0), (0.12, 0.0), (0.22, -0.65), (0.36, -0.65),
        (0.46, 0.0), (0.56, 0.0), (0.66, 0.65), (0.80, 0.65),
        (0.90, 0.0), (1.0, 0.0),
    ]))
}

#[no_mangle]
pub extern "C" fn rium_character_idle_gaze(time: f64, reduce_motion: i32) -> f64 {
    if !(0..=1).contains(&reduce_motion) { return f64::NAN; }
    rium_idle_gaze(time, reduce_motion == 1).unwrap_or(f64::NAN)
}

/// Pixel-eye glyph recovered from the modified reference's eyePattern.
/// The output is width, height and three left-to-right row bitmasks. Face 12
/// has no glyph. The reference uses the pose’s lid and eyeScale fields at offsets 0x60
/// and 0x68 for the 0.45 and 1.1 comparisons respectively.
pub fn lumi_pixel_eye_pattern(face: i32, eye_open: f64, eye_scale: f64, right: bool) -> Option<[u8; 5]> {
    if !(0..=12).contains(&face) || !eye_open.is_finite() || !eye_scale.is_finite() { return None; }
    Some(match face {
        0 | 1 if eye_open < 0.45 => [2, 1, 0b11, 0, 0],
        0 | 1 if face == 1 || eye_scale > 1.1 => [2, 2, 0b11, 0b11, 0],
        0 | 1 => [1, 2, 0b1, 0b1, 0],
        2 | 6 => [3, 2, 0b010, 0b101, 0],
        3 => [3, 3, 0b101, 0b010, 0b101],
        4 | 5 | 10 => [2, 1, 0b11, 0, 0],
        7 => [1, 2, 0b1, 0b1, 0],
        8 => [2, 2, 0b11, 0b11, 0],
        9 if right => [2, 1, 0b11, 0, 0],
        9 => [1, 2, 0b1, 0b1, 0],
        11 => [3, 3, 0b110, 0b101, 0b011],
        12 => [0, 0, 0, 0, 0],
        _ => return None,
    })
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_lumi_pixel_eye_pattern(face: i32, eye_open: f64, eye_scale: f64, right: i32, output: *mut u8) -> i32 {
    if output.is_null() || !(0..=1).contains(&right) { return -1; }
    let Some(pattern) = lumi_pixel_eye_pattern(face, eye_open, eye_scale, right == 1) else { return -1; };
    std::ptr::copy_nonoverlapping(pattern.as_ptr(), output, pattern.len());
    0
}

/// Scale about the feet, then rotate about the body center, as in the pixel renderer.
fn lumi_pixel_body_point(x: f64, y: f64, pose: [f64; 3]) -> [f64; 2] {
    let x = (x - 100.0) * pose[1];
    let y = (y - 165.0) * pose[2] + 35.0;
    let (sin, cos) = pose[0].to_radians().sin_cos();
    [100.0 + x * cos - y * sin, 130.0 + x * sin + y * cos]
}

/// Align an eye glyph after the reference head and body transforms.
// shortcut: gaze normalization is Rium's mapping and needs reference comparison.
pub fn lumi_pixel_eye_origin(face: i32, lid: f64, eye_scale: f64, right: bool, gaze_x: f64, gaze_y: f64, head_tilt: f64, body: [f64; 3]) -> Option<[i32; 2]> {
    if ![gaze_x, gaze_y, head_tilt, body[0], body[1], body[2]].iter().all(|n| n.is_finite()) { return None; }
    let glyph = lumi_pixel_eye_pattern(face, lid, eye_scale, right)?;
    let x = if right { 114.0 } else { 86.0 };
    let x = x + 3.0 * gaze_x.clamp(-1.0, 1.0);
    let y = 68.0 + 2.4 * gaze_y.clamp(-1.0, 1.0);
    let (sin, cos) = head_tilt.rem_euclid(360.0).to_radians().sin_cos();
    let dx = x - 100.0; let dy = y - 70.0;
    let [tx, ty] = lumi_pixel_body_point(100.0 + dx * cos - dy * sin, 70.0 + dx * sin + dy * cos, body);
    let col = (tx - 5.0) / 9.5 - f64::from(glyph[0]) / 2.0;
    let row = (ty - 1.0) / 9.5 + if matches!(face, 5 | 10) { 1.0 } else { 0.0 }
        - f64::from(glyph[1]) / 2.0;
    Some([if right { col.ceil() as i32 } else { col.floor() as i32 }, row.round() as i32])
}

/// Pixel-aligned sprite origin and cell size from the reference spriteRect.
pub fn lumi_pixel_sprite_rect(width: f64, height: f64, badge: bool, display_scale: f64) -> Option<[f64; 3]> {
    if ![width, height, display_scale].iter().all(|value| value.is_finite())
        || width <= 0.0 || height <= 0.0 || display_scale <= 0.0 { return None; }
    let minimum = width.min(height);
    let (left, top, viewport) = if minimum >= 44.0 { (0.0, 0.0, 200.0) }
        else if badge { (30.0, 20.0, 150.0) } else { (40.0, 30.0, 140.0) };
    let scale = minimum / viewport;
    let device_scale = display_scale.max(1.0);
    let cell = (((171.0 / 18.0) * scale * device_scale).round() / device_scale).max(1.0 / device_scale);
    let center_x = width / 2.0 + (90.5 - (left + viewport / 2.0)) * scale;
    let center_y = height / 2.0 + (86.5 - (top + viewport / 2.0)) * scale;
    let x = ((center_x - cell * 9.0) * device_scale).round() / device_scale;
    let y = ((center_y - cell * 9.0) * device_scale).round() / device_scale;
    if ![x, y, cell].iter().all(|value| value.is_finite()) { return None; }
    Some([x, y, cell])
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_lumi_pixel_sprite_rect(width: f64, height: f64, badge: i32, display_scale: f64, output: *mut f64) -> i32 {
    if output.is_null() || !(0..=1).contains(&badge) { return -1; }
    let Some(rect) = lumi_pixel_sprite_rect(width, height, badge == 1, display_scale) else { return -1; };
    std::ptr::copy_nonoverlapping(rect.as_ptr(), output, rect.len());
    0
}

/// Badge width, height and up to five row bitmasks from badgeGlyph.
pub fn lumi_pixel_badge(mood: i32, clock: f64, small: bool) -> Option<[u8; 7]> {
    if !(0..=8).contains(&mood) || !clock.is_finite() { return None; }
    if mood == 0 || mood == 8 { return Some([0; 7]); }
    if mood == 1 {
        let n = if small { 3usize } else { 5usize };
        let mut glyph = [0u8; 7]; glyph[0] = n as u8; glyph[1] = n as u8;
        for bar in 0..3 {
            let height = (((clock.rem_euclid(2.0 * PI) * 6.0 + bar as f64 * 1.3).sin() + 1.0) * 0.5 * (n - 1) as f64).round() as usize + 1;
            let col = if small { bar } else { bar * 2 };
            for row in n - height..n { glyph[2 + row] |= 1 << (n - col - 1); }
        }
        return Some(glyph);
    }
    Some(match (mood, small) {
        (2, false) => [5, 5, 4, 4, 4, 0, 4], (2, true) => [3, 3, 2, 2, 0, 0, 0],
        (3, false) => [5, 5, 14, 1, 6, 0, 4], (3, true) => [3, 3, 6, 1, 2, 0, 0],
        (4, false) => [5, 5, 0, 1, 2, 20, 8], (4, true) => [3, 3, 1, 5, 2, 0, 0],
        (5, false) => [5, 5, 17, 10, 4, 10, 17], (5, true) => [3, 3, 5, 2, 5, 0, 0],
        (6, false) => [5, 5, 22, 25, 29, 1, 14], (6, true) => [3, 3, 6, 5, 3, 0, 0],
        (7, false) => [5, 5, 10, 10, 10, 10, 10], (7, true) => [3, 3, 5, 5, 5, 0, 0],
        _ => return None,
    })
}

/// Reference source aliases, plus Rium's normalized `claude` source.
pub fn lumi_costume_for_source(source: &str) -> i32 {
    match source {
        "claude" | "claude-code" | "claude-chat" => 1,
        "codex" | "chatgpt" => 2,
        "cursor" => 3,
        _ => 0,
    }
}

/// Reference LumiTokenScreen.Kind colors, expressed as RGB rather than HSV.
pub fn agent_token_kind_color(kind: i32) -> Option<[f64; 3]> {
    match kind {
        0 => Some([0.50, 0.78, 1.0]), 1 => Some([0.30, 0.68, 1.0]),
        2 => Some([1.0, 0.70, 0.36]), 3 => Some([0.72, 0.61, 1.0]),
        4 => Some([1.0, 1.0, 1.0]), _ => None,
    }
}

#[no_mangle]
pub unsafe extern "C" fn rium_agent_token_kind_color(kind: i32, output: *mut f64) -> i32 {
    if output.is_null() { return -1; }
    let Some(color) = agent_token_kind_color(kind) else { return -1; };
    std::ptr::copy_nonoverlapping(color.as_ptr(), output, color.len());
    0
}

// shortcut: Mapping Rium's localized activity labels to reference kinds is
// approximate until every source preserves its original tool kind.
pub fn agent_token_color(activity: &str) -> [f64; 3] {
    let text = activity.to_lowercase();
    let kind = if text.contains("수정") || text.contains("edit") { 1 }
    else if text.contains("검색") || text.contains("search") { 3 }
    else if text.contains("확인") || text.contains("read") { 0 }
    else if text.contains("실행") || text.contains("command") { 2 }
    else { 4 };
    agent_token_kind_color(kind).unwrap_or([1.0, 1.0, 1.0])
}

#[no_mangle]
pub unsafe extern "C" fn rium_agent_token_color(activity: *const u8, len: usize, output: *mut f64) -> i32 {
    if output.is_null() || len > 1024 || (activity.is_null() && len > 0) { return -1; }
    let input = if len == 0 { "" } else {
        let Ok(text) = std::str::from_utf8(std::slice::from_raw_parts(activity, len)) else { return -1; };
        text
    };
    let color = agent_token_color(input);
    std::ptr::copy_nonoverlapping(color.as_ptr(), output, color.len());
    0
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_lumi_costume(source: *const u8, len: usize) -> i32 {
    if len > 256 || (source.is_null() && len > 0) { return -1; }
    if len == 0 { return 0; }
    let Ok(value) = std::str::from_utf8(std::slice::from_raw_parts(source, len)) else { return -1; };
    lumi_costume_for_source(value)
}

/// Base wing, body, head and eye colors from LumiPalette.init(mood).
// shortcut: Byte rounding and exact color-space conversion require comparison.
pub fn lumi_pixel_palette(mood: i32, costume: i32) -> Option<[[u8; 4]; 8]> {
    if !(0..=8).contains(&mood) || !(0..=3).contains(&costume) { return None; }
    let mut rgb: [[f64; 3]; 8] = match mood {
        7 => [[0.36,0.37,0.42], [0.60,0.62,0.66], [0.29,0.31,0.35], [0.49,0.51,0.55],
              [0.31,0.33,0.29], [0.16,0.18,0.21], [0.06,0.07,0.09], [0.79,0.80,0.83]],
        8 => [[0.11,0.23,0.66], [0.31,0.56,0.82], [0.08,0.19,0.60], [0.23,0.45,0.77],
              [0.11,0.24,0.62], [0.09,0.14,0.37], [0.02,0.03,0.12], [0.87,0.91,1.00]],
        _ => [[0.09,0.27,0.94], [0.13,0.78,1.00], [0.04,0.19,0.85], [0.18,0.55,1.00],
              [0.09,0.33,0.95], [0.11,0.17,0.49], [0.02,0.03,0.15], [0.95,0.98,1.00]],
    };
    let head = match costume {
        1 => Some([[0.91,0.54,0.42], [0.66,0.28,0.17], [1.00,0.97,0.95]]),
        2 => Some([[0.96,0.96,0.97], [0.73,0.74,0.77], [0.07,0.07,0.09]]),
        3 => Some([[0.20,0.20,0.23], [0.05,0.05,0.06], [0.95,0.97,1.00]]),
        _ => None,
    };
    if let Some([top, bottom, eye]) = head { rgb[5] = top; rgb[6] = bottom; rgb[7] = eye; }
    Some(rgb.map(|c| [(c[0] * 255.0).round() as u8, (c[1] * 255.0).round() as u8,
                      (c[2] * 255.0).round() as u8, 255]))
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_lumi_palette(mood: i32, costume: i32, output: *mut u8) -> i32 {
    if output.is_null() { return -1; }
    let Some(palette) = lumi_pixel_palette(mood, costume) else { return -1; };
    std::ptr::copy_nonoverlapping(palette.as_ptr().cast::<u8>(), output, 8 * 4);
    0
}

// shortcut: Colors are converted to bytes before mixing; compare the original's
// SwiftUI color-space conversion when visual testing is permitted.
fn lumi_pixel_body_color(base: [u8; 4], tint: [u8; 3], core: [u8; 3], radius: f64, lamp: f64) -> [u8; 4] {
    let (source, strength) = if radius < 0.34 {
        (if radius < 0.17 { core } else { tint }, 0.25 + 0.75 * lamp.clamp(0.0, 1.0))
    } else {
        (if radius < 0.56 { tint } else { [base[0], base[1], base[2]] }, 0.4 + 0.6 * lamp.clamp(0.0, 1.0))
    };
    let mut result = base;
    for channel in 0..3 {
        result[channel] = (f64::from(base[channel]) + strength * (f64::from(source[channel]) - f64::from(base[channel]))).round() as u8;
    }
    result
}

/// 18×18 RGBA character frame. Eye glyphs and grid size are from the modified
/// reference; the body is a temporary rasterization of Rium's vector shapes.
// shortcut: Palette, lamp and remaining shape layers require recovery from
// LumiPixelRenderer.cells and visual comparison.
pub fn lumi_pixel_sprite(mood: i32, costume: i32, face: i32, lid: f64, eye_scale: f64, gaze_x: f64, gaze_y: f64, head_tilt: f64, left_wing: f64, centre_wing: f64, antenna: f64, lamp: f64, clock: f64, mood_time: f64, badge: bool, small: bool, show_effect: bool, body: [f64; 3]) -> Option<[u8; 18 * 18 * 4]> {
    if !(0..=8).contains(&mood) || !(0..=12).contains(&face)
        || ![lid, eye_scale, gaze_x, gaze_y, head_tilt, left_wing, centre_wing, antenna, lamp, clock, mood_time, body[0], body[1], body[2]].iter().all(|n| n.is_finite()) || eye_scale < 0.0 || mood_time < 0.0 { return None; }
    let mut pixels = [0u8; 18 * 18 * 4];
    let palette = lumi_pixel_palette(mood, costume)?;
    let ellipse = |x: f64, y: f64, cx: f64, cy: f64, rx: f64, ry: f64, sin: f64, cos: f64| {
        let dx = x - cx; let dy = y - cy;
        let u = (dx * cos + dy * sin) / rx;
        let v = (-dx * sin + dy * cos) / ry;
        u * u + v * v <= 1.0
    };
    let tint = match mood {
        1 => [76, 173, 255], 2 | 3 => [255, 140, 13], 4 => [71, 224, 140],
        5 => [255, 92, 92], 6 => [255, 184, 51], 7 => [158, 158, 163],
        8 => [184, 168, 115], _ => [158, 199, 255],
    };
    let core = match mood {
        1 => [217, 242, 255], 2 | 3 => [255, 242, 201], 4 => [235, 255, 242],
        5 => [255, 217, 212], 6 => [255, 245, 209], 7 => [230, 230, 235],
        8 => [242, 235, 209], _ => [237, 245, 255],
    };
    let (left_sin, left_cos) = left_wing.to_radians().sin_cos();
    let (centre_sin, centre_cos) = centre_wing.to_radians().sin_cos();
    let (head_sin, head_cos) = head_tilt.to_radians().sin_cos();
    let (antenna_sin, antenna_cos) = antenna.to_radians().sin_cos();
    let distance_to_segment = |x: f64, y: f64, ax: f64, ay: f64, bx: f64, by: f64| {
        let dx = bx - ax; let dy = by - ay;
        let t = (((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy)).clamp(0.0, 1.0);
        (x - ax - t * dx).hypot(y - ay - t * dy)
    };
    let eyes = [lumi_pixel_eye_pattern(face, lid, eye_scale, false)?, lumi_pixel_eye_pattern(face, lid, eye_scale, true)?];
    let eye_origins = [lumi_pixel_eye_origin(face, lid, eye_scale, false, gaze_x, gaze_y, head_tilt, body)?,
                       lumi_pixel_eye_origin(face, lid, eye_scale, true, gaze_x, gaze_y, head_tilt, body)?];
    let (body_sin, body_cos) = body[0].to_radians().sin_cos();
    // shortcut: zero scale uses a thin body until the original degenerate frame is compared.
    let nonzero = |scale: f64| if scale.abs() < 1e-9 { 1e-9_f64.copysign(scale) } else { scale };
    let (scale_x, scale_y) = (nonzero(body[1]), nonzero(body[2]));
    for row in 0..18 {
        for col in 0..18 {
            let dx = 5.0 + (col as f64 + 0.5) * 9.5 - 100.0;
            let dy = 1.0 + (row as f64 + 0.5) * 9.5 - 130.0;
            let x = 100.0 + (dx * body_cos + dy * body_sin) / scale_x;
            let y = 165.0 + (-dx * body_sin + dy * body_cos - 35.0) / scale_y;
            let mut color = [0, 0, 0, 0];
            if ellipse(x, y, 114.0, 130.0, 33.0, 33.0, 0.0, 1.0) {
                color = lumi_pixel_body_color(palette[4], tint, core,
                    (x - 124.6).hypot(y - 145.8) / 51.5, lamp);
            }
            // The reference tests the body first, then centre and left wings.
            // Undo each animated rotation around (102, 100), then test the
            // intrinsic 12° and 48° ellipse orientations respectively.
            let dx = x - 102.0; let dy = y - 100.0;
            let centre_x = 102.0 + dx * centre_cos + dy * centre_sin;
            let centre_y = 100.0 - dx * centre_sin + dy * centre_cos;
            if ellipse(centre_x, centre_y, 96.0, 135.0, 15.0, 33.0,
                       0.20791169081775931, 0.9781476007338057) {
                color = if centre_y < 135.0 { palette[2] } else { palette[3] };
            }
            let left_x = 102.0 + dx * left_cos + dy * left_sin;
            let left_y = 100.0 - dx * left_sin + dy * left_cos;
            if ellipse(left_x, left_y, 80.0, 122.0, 13.0, 30.0,
                       0.7431448254773942, 0.6691306063588582) {
                color = if left_y < 122.0 { palette[0] } else { palette[1] };
            }
            let hx = 100.0 + (x - 100.0) * head_cos + (y - 70.0) * head_sin;
            let hy = 70.0 - (x - 100.0) * head_sin + (y - 70.0) * head_cos;
            // Inverse-rotate the sampled point into the antenna's local space.
            let ax = 148.0 + (hx - 148.0) * antenna_cos + (hy - 58.0) * antenna_sin;
            let ay = 58.0 - (hx - 148.0) * antenna_sin + (hy - 58.0) * antenna_cos;
            if distance_to_segment(ax, ay, 150.0, 55.0, 163.0, 47.0) < 4.75
                || distance_to_segment(ax, ay, 151.0, 66.0, 165.0, 70.0) < 4.75 {
                color = palette[5];
            }
            if hy >= 46.0 && hy <= 90.0 {
                let nearest_x = hx.clamp(78.0, 122.0);
                if (hx - nearest_x).powi(2) + (hy - 68.0).powi(2) <= 22.0_f64.powi(2) {
                    color = if hy < 68.0 { palette[5] } else { palette[6] };
                }
            }
            let offset = (row * 18 + col) * 4;
            pixels[offset..offset + 4].copy_from_slice(&color);
        }
    }
    for (pattern, origin) in eyes.into_iter().zip(eye_origins) {
        for row in 0..pattern[1] {
            for col in 0..pattern[0] {
                if pattern[2 + usize::from(row)] & (1 << (pattern[0] - col - 1)) == 0 { continue; }
                let x = origin[0] + i32::from(col); let y = origin[1] + i32::from(row);
                if !(0..18).contains(&x) || !(0..18).contains(&y) { continue; }
                let offset = ((y * 18 + x) * 4) as usize;
                pixels[offset..offset + 4].copy_from_slice(&palette[7]);
            }
        }
    }
    if !small && mood == 1 {
        for index in 0..3 {
            if index == 2 && (clock * 10.0).trunc().rem_euclid(2.0) != 1.0 { continue; }
            let x = ((66.0 - 16.0 * f64::from(index) - 5.0) / 9.5).floor() as i32;
            let y = ((152.0 + 6.0 * (clock * 6.0 + f64::from(index) * 1.3).sin() - 1.0) / 9.5).floor() as i32;
            if !(0..18).contains(&x) || !(0..18).contains(&y) { continue; }
            let offset = ((y * 18 + x) * 4) as usize;
            // shortcut: the original tint's color-space conversion needs visual comparison.
            let color = [tint[0], tint[1], tint[2], ((1.0 - 0.3 * f64::from(index)) * 255.0).round() as u8];
            pixels[offset..offset + 4].copy_from_slice(&color);
        }
    }
    if !small && show_effect && mood == 4 {
        for (x, y, delay) in [(42.0, 58.0, 0.0), (168.0, 96.0, 0.8), (152.0, 26.0, 1.6), (36.0, 118.0, 2.2)] {
            if (mood_time + delay).rem_euclid(1.2) >= 0.7 { continue; }
            let col = ((x - 5.0) / 9.5_f64).floor() as i32;
            let row = ((y - 1.0) / 9.5_f64).floor() as i32;
            let color = if delay > 1.5 { [255, 232, 120, 255] } else { [255, 255, 255, 255] };
            for (dx, dy) in [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)] {
                let (x, y) = (col + dx, row + dy);
                if !(0..18).contains(&x) || !(0..18).contains(&y) { continue; }
                let offset = ((y * 18 + x) * 4) as usize;
                pixels[offset..offset + 4].copy_from_slice(&color);
            }
        }
    }
    if !small && show_effect && mood == 5 {
        for index in 0..2 {
            let phase = (mood_time * 0.9 + f64::from(index) * 0.5).fract();
            let x = ((140.0 + 8.0 * f64::from(index) - 5.0) / 9.5).floor() as i32;
            let y = ((150.0 - 70.0 * phase - 1.0) / 9.5).floor() as i32;
            if !(0..18).contains(&x) || !(0..18).contains(&y) { continue; }
            let offset = ((y * 18 + x) * 4) as usize;
            // shortcut: RGB bytes approximate the reference color-space conversion.
            pixels[offset..offset + 4].copy_from_slice(&[150, 153, 161, ((1.0 - phase) * 255.0).round() as u8]);
        }
    }
    if !small && show_effect && mood == 8 {
        for index in 0..2 {
            let phase = (clock * 0.35 + f64::from(index) * 0.5).rem_euclid(1.0);
            if phase >= 0.85 { continue; }
            let col = ((150.0 + 24.0 * phase - 5.0) / 9.5).floor() as i32;
            let row = ((58.0 - 50.0 * phase - 1.0) / 9.5).floor() as i32;
            let color = [237, 227, 191, ((1.0 - phase) * 255.0).round() as u8];
            for (dx, dy) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
                let (x, y) = (col + dx, row + dy);
                if !(0..18).contains(&x) || !(0..18).contains(&y) { continue; }
                let offset = ((y * 18 + x) * 4) as usize;
                pixels[offset..offset + 4].copy_from_slice(&color);
            }
        }
    }
    if badge {
        let glyph = lumi_pixel_badge(mood, clock, small)?;
        let n = usize::from(glyph[0]);
        if n > 0 {
            // shortcut: placement and the border tint follow the recovered
            // integer grid; the precise layer overlap still needs comparison.
            let (x0, y0) = if small { (3, 2) } else { (0, 0) };
            let outer = n + 2;
            for y in 0..outer {
                for x in 0..outer {
                    if (x == 0 || x == outer - 1) && (y == 0 || y == outer - 1) { continue; }
                    let offset = ((y0 + y) * 18 + x0 + x) * 4;
                    let lit = x > 0 && x <= n && y > 0 && y <= n
                        && glyph[1 + y] & (1 << (n - x)) != 0;
                    let color = if lit { [242, 250, 255, 255] } else { [6, 7, 10, 255] };
                    pixels[offset..offset + 4].copy_from_slice(&color);
                }
            }
        }
    }
    Some(pixels)
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_lumi_pixel_sprite(mood: i32, costume: i32, face: i32, lid: f64, eye_scale: f64, gaze_x: f64, gaze_y: f64, head_tilt: f64, left_wing: f64, centre_wing: f64, antenna: f64, lamp: f64, clock: f64, mood_time: f64, badge: i32, small: i32, show_effect: i32, body_angle: f64, body_scale_x: f64, body_scale_y: f64, output: *mut u8) -> i32 {
    if output.is_null() || !(0..=1).contains(&badge) || !(0..=1).contains(&small) || !(0..=1).contains(&show_effect) { return -1; }
    let Some(frame) = lumi_pixel_sprite(mood, costume, face, lid, eye_scale, gaze_x, gaze_y, head_tilt, left_wing, centre_wing, antenna, lamp, clock, mood_time, badge == 1, small == 1, show_effect == 1, [body_angle, body_scale_x, body_scale_y]) else { return -1; };
    std::ptr::copy_nonoverlapping(frame.as_ptr(), output, frame.len());
    0
}

/// Local spiral point for a dizzy eye, including the reference's rotating phase.
pub fn lumi_dizzy_eye_point(clock: f64, index: i32) -> Option<[f64; 2]> {
    if !clock.is_finite() || !(0..=28).contains(&index) { return None; }
    let t = f64::from(index) / 28.0;
    let angle = clock.rem_euclid(2.0 * PI / 10.0) * 10.0 + t * 3.4 * PI;
    let radius = 1.0 + 5.2 * t;
    Some([radius * angle.cos(), radius * angle.sin()])
}

#[no_mangle]
pub extern "C" fn rium_notch_lumi_reaction_face(kind: i32, elapsed: f64, reduce_motion: i32) -> i32 {
    if !(0..=1).contains(&reduce_motion) { return -1; }
    lumi_reaction_face(kind, elapsed, reduce_motion == 1).unwrap_or(-1)
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_lumi_dizzy_eye_point(clock: f64, index: i32, output: *mut f64) -> i32 {
    if output.is_null() { return -1; }
    let Some(point) = lumi_dizzy_eye_point(clock, index) else { return -1; };
    std::ptr::copy_nonoverlapping(point.as_ptr(), output, point.len());
    0
}

/// Eye multiplier, gaze x/y offsets, tilt, x/y displacement, scale multiplier,
/// head tilt, horizontal reflection and optional lamp override (-1 = none).
/// Displacements use the original 200-point canvas coordinates.
pub fn lumi_reaction_frame(kind: i32, elapsed: f64, reduce_motion: bool) -> Option<[f64; 10]> {
    let duration = lumi_reaction_duration(kind)?;
    if !elapsed.is_finite() || elapsed < 0.0 { return None; }
    let mut frame = [1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 1.0, -1.0];
    if reduce_motion { return Some(frame); }
    if elapsed >= duration {
        // shortcut: The recovered sigh ends away from neutral; the reference's
        // return transition is unknown. Ease it back instead of snapping.
        if kind == 5 && elapsed < duration + 0.2 {
            let remaining = 1.0 - smoothstep((elapsed - duration) / 0.2);
            frame[3] = 3.0 * remaining;
            frame[5] = 2.0 * remaining;
        }
        return Some(frame);
    }
    let t = elapsed / duration;
    match kind {
        0 => {
            let wave = (8.0 * PI * t).sin() * (1.0 - t);
            frame[3] = 3.0 * wave; frame[5] = -2.5 * wave.abs();
        }
        1 => {
            let sway = smooth_keyframes(t, &[(0.0,0.0),(0.15,-7.0),(0.3,7.0),(0.45,-5.0),(0.6,4.0),(0.8,0.0),(1.0,0.0)]);
            frame[4] = sway; frame[3] = sway * 0.7;
        }
        2 => {
            frame[5] = smooth_keyframes(t, &[(0.0,0.0),(0.15,-16.0),(0.3,2.0),(0.48,-14.0),(0.64,1.0),(0.8,0.0),(1.0,0.0)]);
            frame[3] = smooth_keyframes(t, &[(0.0,0.0),(0.64,0.0),(0.8,8.0),(1.0,0.0)]);
        }
        3 => { frame[7] = smooth_keyframes(t, &[(0.0,0.0),(0.3,-22.0),(0.6,14.0),(1.0,0.0)]); }
        4 => {
            frame[3] = 360.0 * smoothstep(((t - 0.2) / 0.4).clamp(0.0, 1.0));
            frame[5] = smooth_keyframes(t, &[(0.0,0.0),(0.2,6.0),(0.6,-26.0),(0.85,0.0),(1.0,0.0)]);
        }
        5 => {
            frame[5] = smooth_keyframes(t, &[(0.0,0.0),(0.3,-10.0),(0.7,8.0),(1.0,2.0)]);
            frame[3] = smooth_keyframes(t, &[(0.0,0.0),(0.7,5.0),(1.0,3.0)]);
        }
        6 => { frame[9] = if t < 0.15 { 0.06 } else if t < 0.3 { 0.9 } else if t < 0.45 { 0.2 } else if t < 0.7 { 0.85 } else { -1.0 }; }
        7 => {
            frame[5] = smooth_keyframes(t, &[(0.0,0.0),(0.12,-30.0),(0.3,-24.0),(0.55,2.0),(1.0,0.0)]);
            frame[3] = smooth_keyframes(t, &[(0.0,0.0),(0.3,-6.0),(0.55,0.0),(1.0,0.0)]);
        }
        8 => {
            frame[3] = smooth_keyframes(t, &[(0.0,0.0),(0.2,-14.0),(0.4,12.0),(0.6,-9.0),(0.8,6.0),(1.0,0.0)]);
            frame[4] = 3.0 * (4.0 * PI * t).sin() * (1.0 - t);
        }
        9 => { frame[8] = smooth_keyframes(t, &[(0.0,1.0),(0.18,-1.0),(0.82,-1.0),(1.0,1.0)]); }
        _ => return None,
    }
    Some(frame)
}

/// Phase and opacity for the large-character status effect.
pub fn lumi_effect_frame(mood: i32, age: f64, clock: f64, reduce_motion: bool) -> Option<[f64; 2]> {
    if !(0..=8).contains(&mood) || !age.is_finite() || age < 0.0 || !clock.is_finite() { return None; }
    if !matches!(mood, 4 | 5 | 8) { return Some([0.0, 0.0]); }
    // LumiPose disables completion effects at 7.8s and failure effects at 2.4s.
    if mood == 4 && age >= 7.8 || mood == 5 && age >= 2.4 { return Some([0.0, 0.0]); }
    if reduce_motion { return Some(match mood { 4 => [0.3, 1.0], 5 => [1.5, 1.0], _ => [0.3, 1.0] }); }
    if mood == 5 { return Some([age, 1.0]); }
    let period = if mood == 4 { 2.6 } else { 3.6 };
    let phase = (if mood == 8 { clock } else { age }).rem_euclid(period) / period;
    Some([phase, 1.0])
}

/// Working-state trailing dots: center, radius, and opacity in the 200-point canvas.
pub fn lumi_trail_frame(clock: f64, index: i32) -> Option<[f64; 4]> {
    if !clock.is_finite() || !(0..=2).contains(&index) { return None; }
    let (x, y, radius) = [(76.0, 150.0, 3.0), (70.0, 158.0, 2.2), (80.0, 160.0, 1.8)][index as usize];
    let t = (clock / 1.1 + f64::from(index) / 3.0).rem_euclid(1.0);
    let opacity = if t < 0.15 { 0.9 * t / 0.15 } else { 0.9 * (1.0 - t) / 0.85 };
    Some([x - 34.0 * t, y + 10.0 * t, radius, opacity])
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_lumi_trail_frame(clock: f64, index: i32, output: *mut f64) -> i32 {
    if output.is_null() { return -1; }
    let Some(frame) = lumi_trail_frame(clock, index) else { return -1; };
    std::ptr::copy_nonoverlapping(frame.as_ptr(), output, frame.len());
    0
}

/// Stalled-state glyph center, font size and opacity from the reference.
pub fn lumi_zzz_frame(phase: f64, index: i32) -> Option<[f64; 4]> {
    if !phase.is_finite() || !(0.0..=1.0).contains(&phase) || !(0..=2).contains(&index) { return None; }
    let t = (phase - f64::from(index) / 3.0).rem_euclid(1.0);
    let opacity = if t < 0.2 { t / 0.2 } else { 1.0 - (t - 0.2) / 0.8 };
    let base = [13.0, 16.0, 19.0][index as usize];
    Some([170.0 + 14.0 * t, 36.0 - 30.0 * t, base * (0.6 + 0.55 * t), opacity])
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_lumi_zzz_frame(phase: f64, index: i32, output: *mut f64) -> i32 {
    if output.is_null() { return -1; }
    let Some(frame) = lumi_zzz_frame(phase, index) else { return -1; };
    std::ptr::copy_nonoverlapping(frame.as_ptr(), output, frame.len());
    0
}

/// Failure puff center, radius and opacity from the reference renderer.
pub fn lumi_puff_frame(age: f64, index: i32) -> Option<[f64; 4]> {
    if !age.is_finite() || age < 0.0 || !(0..=1).contains(&index) { return None; }
    let t = (age - 0.8 - f64::from(index) * 0.25) / 1.4;
    if !(0.0..1.0).contains(&t) || t == 0.0 { return Some([0.0; 4]); }
    let (x, y, radius) = if index == 0 { (138.0, 150.0, 5.0) } else { (130.0, 148.0, 4.0) };
    Some([x + 8.0 * t, y - 26.0 * t, radius * (t + 0.4), 0.5 * (1.0 - t)])
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_lumi_puff_frame(age: f64, index: i32, output: *mut f64) -> i32 {
    if output.is_null() { return -1; }
    let Some(frame) = lumi_puff_frame(age, index) else { return -1; };
    std::ptr::copy_nonoverlapping(frame.as_ptr(), output, frame.len());
    0
}

/// Completion sparkle amplitude and rotation from the reference keyframes.
pub fn lumi_sparkle_frame(phase: f64, index: i32) -> Option<[f64; 2]> {
    if !phase.is_finite() || !(0.0..=1.0).contains(&phase) || !(0..=3).contains(&index) { return None; }
    let local = phase - f64::from(index) * 0.046;
    if !(0.0..=1.0).contains(&local) { return Some([0.0, 0.0]); }
    let amplitude = smooth_keyframes(local, &[(0.0, 0.0), (0.18, 0.0), (0.3, 1.15), (0.6, 0.8), (0.8, 0.0), (1.0, 0.0)]);
    Some([amplitude, local * 80.0])
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_lumi_sparkle_frame(phase: f64, index: i32, output: *mut f64) -> i32 {
    if output.is_null() { return -1; }
    let Some(frame) = lumi_sparkle_frame(phase, index) else { return -1; };
    *output = frame[0];
    *output.add(1) = frame[1];
    0
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_lumi_effect_frame(mood: i32, age: f64, clock: f64, reduce_motion: i32,
    output: *mut f64) -> i32 {
    if output.is_null() || !(0..=1).contains(&reduce_motion) { return -1; }
    let Some(frame) = lumi_effect_frame(mood, age, clock, reduce_motion == 1) else { return -1; };
    *output = frame[0];
    *output.add(1) = frame[1];
    0
}

/// Idle LumiMotion lamp: 0.62 + 0.18 sin(2πt / 3.2). The caller applies
/// the reference's per-character phase offset before passing `time`.
pub fn lumi_idle_lamp(time: f64, reduce_motion: bool) -> Option<f64> {
    if !time.is_finite() { return None; }
    // shortcut: the static level for Reduce Motion is inferred.
    if reduce_motion { return Some(0.62); }
    Some(0.62 + 0.18 * (2.0 * PI * time.rem_euclid(3.2) / 3.2).sin())
}

#[no_mangle]
pub extern "C" fn rium_notch_lumi_idle_lamp(time: f64, reduce_motion: i32) -> f64 {
    if !(0..=1).contains(&reduce_motion) { return f64::NAN; }
    lumi_idle_lamp(time, reduce_motion == 1).unwrap_or(f64::NAN)
}

/// Additional LumiMotion lamp curves decoded from the same binary. Unknown
/// moods return None so the renderer can retain its provisional fallback.
pub fn lumi_state_lamp(mood: i32, time: f64, state_age: f64, reduce_motion: bool) -> Option<f64> {
    if !time.is_finite() || !state_age.is_finite() || state_age < 0.0 { return None; }
    if mood == 0 { return lumi_idle_lamp(time, reduce_motion); }
    if mood == 4 {
        // shortcut: Reduce Motion's settled midpoint is inferred.
        if reduce_motion { return Some(0.55); }
        if state_age < 7.8 {
            let phase = state_age.rem_euclid(2.6) / 2.6;
            return Some(smooth_keyframes(phase, &[(0.0, 0.5), (0.14, 0.5), (0.24, 1.0),
                                                 (0.7, 0.55), (1.0, 0.5)]));
        }
        return Some(0.55 + 0.10 * (2.0 * PI * time.rem_euclid(4.0) / 4.0).sin());
    }
    if mood == 5 {
        // shortcut: Reduce Motion's final brightness is inferred.
        if reduce_motion { return Some(0.32); }
        return Some(smooth_keyframes(state_age, &[(0.0, 0.9), (0.5, 0.9), (0.6, 0.2),
                                                  (0.7, 0.8), (0.85, 0.15), (1.0, 0.55),
                                                  (1.2, 0.32), (1.6, 0.32)]));
    }
    if mood == 7 {
        // shortcut: the final resting level for Reduce Motion is inferred.
        if reduce_motion { return Some(0.06); }
        return Some(0.70 - 0.64 * (state_age / 1.6).min(1.0));
    }
    if mood == 2 {
        // Two Gaussian flashes per 1.2-second cycle: centers 0.06 and 0.32
        // in normalized phase, with a 0.06 phase-width denominator.
        // shortcut: Reduce Motion's fixed midpoint is inferred.
        if reduce_motion { return Some(0.65); }
        let phase = time.rem_euclid(1.2) / 1.2;
        let pulse = |center: f64| (-((phase - center) / 0.06).powi(2)).exp();
        return Some(0.30 + 0.70 * pulse(0.06).max(pulse(0.32)));
    }
    let (base, amplitude, period) = match mood {
        1 => (0.62, 0.20, 1.1),
        3 => (0.60, 0.20, 1.8),
        6 => (0.60, 0.20, 2.2),
        8 => (0.40, 0.12, 3.8),
        _ => return None,
    };
    // shortcut: Reduce Motion's static brightness is inferred from the midpoint.
    if reduce_motion { return Some(base); }
    Some(base + amplitude * (2.0 * PI * time.rem_euclid(period) / period).sin())
}

#[no_mangle]
pub extern "C" fn rium_notch_lumi_state_lamp(mood: i32, time: f64, state_age: f64, reduce_motion: i32) -> f64 {
    if !(0..=1).contains(&reduce_motion) { return f64::NAN; }
    lumi_state_lamp(mood, time, state_age, reduce_motion == 1).unwrap_or(f64::NAN)
}

/// Pose values are eye opening, gaze x/y, head tilt in degrees, body x/y in
/// points, body scale and state intensity. The basic blink follows static
/// Glance evidence ev_78ecfc6b: 0.14 seconds long, with 0.92 sinusoidal
/// closure. Idle, running, permission, question and retry periods are 5.0,
/// 4.2, 3.0, 4.5 and 4.8 seconds. Other states fall back to idle timing.
/// Displacements use the original 200-point canvas; gaze x is normalized
/// from original -3...3 units. Some movement and transitions are approximate.
/// `state_age` is seconds since the caller last changed status. For smooth
/// transitions from one *moving* pose to another, the caller should blend the
/// prior and current poses; a state-age ramp alone cannot preserve velocity.
pub fn character_pose(state: i32, time: f64, state_age: f64, reduce_motion: bool) -> Option<[f64; 8]> {
    if !(0..=8).contains(&state) || !time.is_finite() || !state_age.is_finite() || state_age < 0.0 { return None; }
    if reduce_motion {
        let intensity = match state { 1 => 0.35, 2 => 0.85, 3 => 0.65, 4 => 0.7, 5 => 0.9, 6 => 0.6, 7 => 0.35, 8 => 0.6, _ => 0.0 };
        return Some([1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, intensity]);
    }
    let t = time.rem_euclid(300.0);
    let wave = |period: f64| (2.0 * PI * t / period).sin();
    let blink_period = match state { 1 => 4.2, 2 => 3.0, 3 => 4.5, 6 => 4.8, _ => 5.0 };
    let blink_time = time.rem_euclid(blink_period);
    let eye_open = if blink_time < 0.14 { 1.0 - 0.92 * (PI * blink_time / 0.14).sin().powi(2) } else { 1.0 };
    let idle_lift = (2.0 * PI * time.rem_euclid(4.0) / 4.0).sin();
    if state == 0 { return Some([eye_open, 0.0, 0.0, 0.0, 0.0, -3.5 - 3.5 * idle_lift, 1.0, 0.0]); }
    let ramp = smoothstep(state_age / 0.35);
    if state == 1 {
        let running = (2.0 * PI * time.rem_euclid(1.3) / 1.3).sin();
        let phase = time.rem_euclid(3.4) / 3.4;
        let gaze = smooth_keyframes(phase, &[(0.0,0.0),(0.2,0.0),(0.35,3.0),(0.55,3.0),(0.7,-3.0),(0.9,-3.0),(1.0,0.0)]) / 3.0;
        return Some([eye_open, gaze, 0.0, running - 4.0, running,
                     -2.5 - 2.5 * running, 1.0, ramp * (0.4 + 0.1 * wave(6.0))]);
    }
    if state == 2 {
        let phase = time.rem_euclid(0.9) / 0.9;
        let lift = -smooth_keyframes(phase, &[(0.0,0.0),(0.4,12.0),(0.6,10.0),(1.0,0.0)]);
        return Some([eye_open, 0.0, 0.0, 0.0, 0.0, lift, 1.0, ramp * (0.75 + 0.15 * wave(5.0))]);
    }
    if state == 3 {
        let lift = -3.0 - 3.0 * (2.0 * PI * time.rem_euclid(2.4) / 2.4).sin();
        // shortcut: eye positions are normalized for Rium's renderer and need visual comparison.
        return Some([eye_open, -0.5, -2.0 / 2.4, 0.0, 0.0, lift, 1.0, ramp * (0.58 + 0.1 * wave(6.0))]);
    }
    if state == 5 {
        let progress = smoothstep(state_age / 0.9);
        let shake = if state_age < 0.8 { 4.0 * (40.0 * state_age).sin() * (1.0 - state_age / 0.8) } else { 0.0 };
        return Some([1.0, 0.0, 0.0, 4.0 * progress, shake, 7.0 * progress, 1.0, ramp * 0.9]);
    }
    if state == 6 {
        let lift = -3.5 - 3.5 * (2.0 * PI * time.rem_euclid(2.2) / 2.2).sin();
        // shortcut: Rium normalizes the reference's (-2, -2) gaze to its eye renderer.
        return Some([eye_open, -2.0 / 3.0, -2.0 / 2.4, 0.0, 0.0, lift, 1.0, ramp * (0.55 + 0.1 * wave(6.0))]);
    }
    if state == 7 {
        let progress = smoothstep(state_age / 1.2);
        return Some([1.0, 0.0, 0.0, 0.0, 0.0, 10.0 * progress, 1.0, ramp * 0.35]);
    }
    if state == 8 {
        return Some([1.0, 0.0, 0.0, 0.0, 0.0, 4.0, 1.0, ramp * 0.6]);
    }
    let lift = if state_age < 7.8 {
        let phase = state_age.rem_euclid(2.6) / 2.6;
        smooth_keyframes(phase, &[(0.0,0.0),(0.08,3.0),(0.22,-20.0),(0.38,0.0),(0.46,-4.0),(0.6,0.0),(1.0,0.0)])
    } else {
        -2.0 - 2.0 * (2.0 * PI * time.rem_euclid(4.5) / 4.5).sin()
    };
    Some([1.0, 0.0, 0.0, 0.0, 0.0, lift, 1.0, ramp * 0.7])
}

pub fn lumi_dance_lift(time: f64, index: i32, reduce_motion: bool) -> Option<f64> {
    if !time.is_finite() || time < 0.0 || index < 0 { return None; }
    if reduce_motion { return Some(0.0); }
    Some(-10.0 * (PI * time / 0.62 + f64::from(index) * 0.95).sin().abs())
}

#[no_mangle]
pub extern "C" fn rium_notch_lumi_dance_lift(time: f64, index: i32, reduce_motion: i32) -> f64 {
    if !(0..=1).contains(&reduce_motion) { return f64::NAN; }
    lumi_dance_lift(time, index, reduce_motion == 1).unwrap_or(f64::NAN)
}

// shortcut: the reference's exact gaze-release easing has not been recovered.
pub fn gaze_return_weight(elapsed: f64, reduce_motion: bool) -> Option<f64> {
    if !elapsed.is_finite() || elapsed < 0.0 { return None; }
    if reduce_motion { return Some(0.0); }
    Some(1.0 - smoothstep(elapsed / 0.35))
}

#[no_mangle]
pub extern "C" fn rium_notch_gaze_return_weight(elapsed: f64, reduce_motion: i32) -> f64 {
    if !(0..=1).contains(&reduce_motion) { return -1.0; }
    gaze_return_weight(elapsed, reduce_motion == 1).unwrap_or(-1.0)
}

/// Independent antenna rotation from the reference's LumiPose field at 0x40.
pub fn lumi_antenna_angle(mood: i32, time: f64, age: f64, reduce_motion: bool) -> Option<f64> {
    if !(0..=8).contains(&mood) || !time.is_finite() || !age.is_finite() || age < 0.0 { return None; }
    if reduce_motion { return Some(0.0); }
    let wave = |period: f64| (2.0 * PI * time.rem_euclid(period) / period).sin();
    Some(match mood {
        0 => 4.0 * wave(3.0),
        1 => 3.0 * wave(1.3),
        2 => 9.0 * wave(0.45),
        5 => 16.0 * smoothstep(age / 0.9),
        7 => 10.0 * smoothstep(age / 1.2),
        _ => 0.0,
    })
}

#[no_mangle]
pub extern "C" fn rium_notch_lumi_antenna_angle(mood: i32, time: f64, age: f64, reduce_motion: i32) -> f64 {
    if !(0..=1).contains(&reduce_motion) { return f64::NAN; }
    lumi_antenna_angle(mood, time, age, reduce_motion == 1).unwrap_or(f64::NAN)
}

/// Waiting-too-long breathing distortion from the reference's squash fields.
pub fn lumi_stalled_squash(time: f64, reduce_motion: bool) -> Option<[f64; 2]> {
    if !time.is_finite() { return None; }
    if reduce_motion { return Some([1.0, 1.0]); }
    let breath = 0.5 + 0.5 * (2.0 * PI * time.rem_euclid(3.8) / 3.8).sin();
    Some([1.0 + 0.025 * breath, 1.0 + 0.04 * breath])
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_lumi_stalled_squash(time: f64, reduce_motion: i32, output: *mut f64) -> i32 {
    if output.is_null() || !(0..=1).contains(&reduce_motion) { return -1; }
    let Some(squash) = lumi_stalled_squash(time, reduce_motion == 1) else { return -1; };
    std::ptr::copy_nonoverlapping(squash.as_ptr(), output, squash.len());
    0
}

/// Additional independent Lumi part rotations in degrees: head, left wing,
/// centre wing. Idle wing angles follow the modified 0.4.1 binary's 1.4 s
/// sine, -2...20 and 0...9 ranges. In the running branch those two values
/// use a 0.18 s period, with the centre value offset by 0.04 s. Permission,
/// question, retry and done use the synchronized periods and ranges recovered
/// from the modified binary's pose function and field metadata. The pivots,
/// field-to-part mapping and other curves remain provisional pending visual
/// comparison.
pub fn lumi_parts_pose(state: i32, time: f64, state_age: f64, reduce_motion: bool) -> Option<[f64; 3]> {
    let pose = character_pose(state, time, state_age, reduce_motion)?;
    if reduce_motion { return Some([0.0, 0.0, 0.0]); }
    let periodic = |period: f64| (2.0 * PI * time.rem_euclid(period) / period).sin();
    let mut head = pose[3] * 0.65 + pose[1] * 0.9;
    let mut left = 1.0 * periodic(5.0);
    let mut centre = 0.7 * periodic(5.0);
    match state {
        1 => {
            head = 0.0;
            let wing = (periodic(0.18) + 1.0) * 0.5;
            let offset_wing = ((2.0 * PI * (time + 0.04).rem_euclid(0.18) / 0.18).sin() + 1.0) * 0.5;
            left = wing * 22.0 - 2.0;
            centre = offset_wing * 9.0;
        },
        2 => {
            head = 0.0;
            let wing = (periodic(0.32) + 1.0) * 0.5;
            left = wing * 22.0 - 2.0;
            centre = wing * 9.0;
        },
        3 => {
            head = 7.5 * periodic(2.8);
            let wing = (periodic(0.9) + 1.0) * 0.5;
            left = wing * 20.0 - 2.0;
            centre = wing * 8.0;
        },
        4 => {
            let (period, left_range, centre_range) = if state_age < 7.8 { (0.14, 22.0, 9.0) } else { (1.8, 14.0, 6.0) };
            let wing = (periodic(period) + 1.0) * 0.5;
            head = 0.0;
            left = wing * left_range - 2.0;
            centre = wing * centre_range;
        },
        5 => {
            let progress = smoothstep(state_age / 0.9);
            head = 0.0;
            left = -12.0 * progress;
            centre = -5.0 * progress;
        },
        6 => {
            head = 0.0;
            let wing = (periodic(0.8) + 1.0) * 0.5;
            left = wing * 20.0 - 2.0;
            centre = wing * 8.0;
        },
        7 => {
            let progress = smoothstep(state_age / 1.2);
            head = 0.0;
            left = -14.0 * progress;
            centre = -6.0 * progress;
        },
        8 => { head = 0.0; left = 0.0; centre = 0.0; },
        0 => {
            let wing = (periodic(1.4) + 1.0) * 0.5;
            head = 0.0;
            left = wing * 22.0 - 2.0;
            centre = wing * 9.0;
        },
        _ => {}
    }
    Some([head, left, centre])
}

#[cfg(test)]
mod shortcut_tests {
    use super::{agent_light_frame, agent_peek_orb, agent_screen_wave, agent_token_color, agent_token_kind_color, agent_wave_admit, arrival_segments, case_key_segments, collapsed_music_wave_height, edge_wave_detail, edge_wave_frame, home_disc_angle, home_music_wave_height, home_source_wave_height, idle_shimmer_frame, music_remaining_fraction, receiving_tide_frame, shortcut_icon_frame, shortcut_light_duration, shortcut_light_fade, shortcut_segments, sound_cue_admit, system_hud_segments};

    #[test]
    fn agenda_arrivals_follow_measured_bottom_and_shoulders() {
        use super::agenda_arrival_segments;
        let calendar = agenda_arrival_segments(3, 1.5, 500.0, 120.0, 30.0).unwrap();
        let right = calendar[1];
        let settled = calendar[2];
        assert!(((right.start + right.end) / 2.0 - 0.74).abs() < 1e-9);
        assert!(((settled.start + settled.end) / 2.0 - 0.5).abs() < 1e-9);
        let reminder = agenda_arrival_segments(4, 1.5, 500.0, 120.0, 30.0).unwrap();
        assert!(((reminder[0].start + reminder[0].end) / 2.0 - 0.06).abs() < 1e-9);
        assert!(((reminder[1].start + reminder[1].end) / 2.0 - 0.94).abs() < 1e-9);
        assert!(agenda_arrival_segments(3, 2.0, 500.0, 120.0, 30.0).unwrap().is_empty());
        assert!(agenda_arrival_segments(4, 1.0, 500.0, 120.0, -1.0).is_none());
    }

    #[test]
    fn notification_marquee_pauses_then_loops_at_reference_speed() {
        use super::notification_marquee_offset as offset;
        let period = 0.9 + (100.0 + 40.0) / 34.0;
        assert_eq!(offset(0.5, 100.0), Some(0.0));
        assert!((offset(1.9, 100.0).unwrap() + 34.0).abs() < 1e-9);
        assert!((offset(period - 0.01, 100.0).unwrap() + 139.66).abs() < 1e-9);
        assert_eq!(offset(period, 100.0), Some(0.0));
        assert!(offset(f64::NAN, 100.0).is_none());
        assert!(offset(1.0, 0.0).is_none());
    }

    #[test]
    fn notification_arrival_has_three_reference_pulses() {
        use super::notification_arrival_envelope as envelope;
        assert_eq!(envelope(0.0, 0.8, false), Some(0.0));
        assert!((envelope(0.135, 0.8, false).unwrap() - 1.0).abs() < 1e-9);
        assert_eq!(envelope(0.25, 0.8, false), Some(0.0));
        assert!((envelope(0.38, 0.8, false).unwrap() - 1.0).abs() < 1e-9);
        assert_eq!(envelope(0.50, 0.8, false), Some(0.0));
        assert!((envelope(0.65, 0.8, false).unwrap() - 0.42).abs() < 1e-9);
        assert_eq!(envelope(0.8, 0.8, false), Some(0.0));
        assert!((envelope(0.4, 0.8, true).unwrap() - 1.0).abs() < 1e-9);
        assert_eq!(envelope(0.9, 0.8, true), Some(0.0));
        assert!(envelope(f64::NAN, 0.8, false).is_none());
        assert!(envelope(0.1, 0.0, false).is_none());
    }

    #[test]
    fn notification_gauge_fades_in_and_out_between_pulses() {
        use super::notification_arrival_gauge as gauge;
        assert_eq!(gauge(0.0, 0.8), Some(0.0));
        assert!((gauge(0.035, 0.8).unwrap() - 0.01925).abs() < 1e-9);
        assert!((gauge(0.3, 0.8).unwrap() - 0.22).abs() < 1e-9);
        assert!((gauge(0.55, 0.8).unwrap() - 0.11).abs() < 1e-9);
        assert_eq!(gauge(0.9, 0.8), Some(0.0));
        assert!(gauge(f64::NAN, 0.8).is_none());
        assert!(gauge(0.0, 0.0).is_none());
        let reference_total = 0.78 + 1.4;
        assert!((gauge(1.0, reference_total).unwrap() - 0.22).abs() < 1e-9);
        assert!((gauge(reference_total - 0.1, reference_total).unwrap() - 0.044).abs() < 1e-9);
        assert_eq!(gauge(reference_total + 0.1, reference_total), Some(0.0));
    }

    #[test]
    fn assistant_cloud_specks_follow_the_reference_ellipse() {
        let center = super::assistant_cloud_speck(23, 9).unwrap();
        assert_eq!(&center[..3], &[0.5, 0.5, 1.0]);
        let seed = 9u64 * 0x220e_5eac_c7db + 23u64 * 0x00b9_7f4a_7c15;
        assert_eq!(center[3], ((seed >> 32) & 0xff) as f64 / 255.0);
        assert!(super::assistant_cloud_speck(0, 0).is_none());
        assert!(super::assistant_cloud_speck(47, 9).is_none());
        assert!(super::assistant_cloud_speck(23, 19).is_none());
    }

    #[test]
    fn assistant_cloud_color_buckets_quantize_and_reject_invalid_values() {
        assert_eq!(super::assistant_cloud_color_bucket(1.0, 0.5, 0.0, 0.5), Some((31 << 15) | (16 << 10) | 8));
        assert_eq!(super::assistant_cloud_color_bucket(-1.0, 2.0, 0.0, 2.0), Some((31 << 10) | 16));
        assert_eq!(super::assistant_cloud_color_bucket(0.0, 0.0, 0.0, 0.004), None);
        assert_eq!(super::assistant_cloud_color_bucket(f64::NAN, 0.0, 0.0, 1.0), None);
    }

    #[test]
    fn assistant_cloud_envelope_enters_exits_and_respects_reduce_motion() {
        assert_eq!(super::assistant_cloud_envelope(0.0, None, true).unwrap(), [0.0; 4]);
        let active = super::assistant_cloud_envelope(0.38, None, true).unwrap();
        assert_eq!((active[0], active[1], active[2]), (1.0, 0.0, 0.0));
        let closing = super::assistant_cloud_envelope(1.0, Some(0.18), true).unwrap();
        assert!((closing[1] - 0.5).abs() < 1e-12 && closing[2] > 0.0);
        assert_eq!(super::assistant_cloud_envelope(1.0, Some(0.36), true).unwrap()[1], 1.0);
        assert_eq!(super::assistant_cloud_envelope(1.0, Some(0.0), false).unwrap()[1], 1.0);
        assert!(super::assistant_cloud_envelope(1.0, Some(f64::MAX), true).unwrap().iter().all(|value| value.is_finite()));
        assert_eq!(super::assistant_cloud_envelope(-1.0, None, true), None);
    }

    #[test]
    fn dictation_cloud_carries_the_last_level_into_writing() {
        let sample = super::dictation_writing_cloud_sample;
        assert_eq!(sample(2.0, 0.0, 0.7, true), Some([0.0, 0.0, 0.7, 0.0]));
        let finished = sample(2.0, 0.38, 0.7, true).unwrap();
        assert_eq!(finished[0], 1.0);
        assert!((finished[2] - (0.23 + 0.09 * (2.0_f64 * 2.05).sin())).abs() < 1e-12);
        assert_eq!(sample(20.0, 1.0, 0.7, false), sample(0.0, 0.0, 0.1, false));
        assert_eq!(sample(2.0, 0.0, 2.0, true).unwrap()[2], 1.0);
        assert!(sample(2.0, 0.0, f64::NAN, true).is_none());
        assert!(sample(2.0, -0.1, 0.0, true).is_none());
    }

    #[test]
    fn assistant_cloud_columns_are_bounded_and_reduce_motion_is_static() {
        for index in 0..47 {
            let [wave, ripple, current, drift] = super::assistant_cloud_column(index, 17.0, false).unwrap();
            assert!((-1.0..=1.0).contains(&wave) && (-1.0..=1.0).contains(&ripple));
            assert!((0.05..=0.95).contains(&current) && (-1.0..=1.0).contains(&drift));
            assert_eq!(super::assistant_cloud_column(index, 0.0, true), super::assistant_cloud_column(index, 17.0, true));
        }
        assert_eq!(super::assistant_cloud_column(-1, 0.0, false), None);
        assert_eq!(super::assistant_cloud_column(47, 0.0, false), None);
        assert_eq!(super::assistant_cloud_column(0, f64::NAN, false), None);
        assert!(super::assistant_cloud_column(6, f64::MAX, false).unwrap().iter().all(|value| value.is_finite()));
        let center = super::assistant_cloud_column(23, 0.0, false).unwrap();
        assert!((center[2] - (0.5 + 0.25 * 4.25_f64.sin() + 0.2 * 6.3_f64.sin())).abs() < 1e-12);
        assert!((center[0] - 2.6_f64.sin()).abs() < 1e-12);
        assert!((center[1] - 4.45_f64.sin()).abs() < 1e-12);
    }

    #[test]
    fn assistant_cloud_particle_uses_reference_density_and_geometry() {
        let column = super::assistant_cloud_column(23, 0.0, false).unwrap();
        let particle = super::assistant_cloud_particle(0.5, 0.5, 1.0, 0.5, 0.0, 38.0, 24.0,
            column, [1.0, 0.0, 0.23, 0.0]).unwrap();
        assert!(particle.iter().all(|value| value.is_finite()));
        assert!((particle[2] - (0.55 + 0.95 + 0.23 * 0.4)).abs() < 1e-12);
        assert!((particle[4] - 0.1).abs() < 1e-12);
        assert!(super::assistant_cloud_particle(0.5, 0.5, 1.0, 0.5, 0.0, 0.0, 24.0,
            column, [1.0, 0.0, 0.23, 0.0]).is_none());
    }

    #[test]
    fn assistant_speech_pulse_follows_word_boundaries() {
        let first = super::rium_assistant_speech_pulse(0.0);
        let later = super::rium_assistant_speech_pulse(1.0);
        assert!((first - 0.72).abs() < 1e-12);
        assert!(later > 0.12 && later < first);
        assert_eq!(super::rium_assistant_speech_pulse(-1.0), 0.0);
        assert_eq!(super::rium_assistant_speech_pulse(f64::NAN), 0.0);
    }

    #[test]
    fn assistant_live_levels_follow_real_moment_and_listening_input() {
        assert_eq!(super::assistant_live_level(0, 0.0, 0.8), Some(0.8));
        assert_eq!(super::assistant_live_level(0, 0.0, 2.0), Some(1.0));
        assert_eq!(super::assistant_live_level(2, 0.0, 0.0), Some(0.25));
        assert_eq!(super::assistant_live_level(3, 0.0, 0.0), Some(0.375));
        assert_eq!(super::assistant_live_level(4, 0.0, 0.0), Some(0.0));
        assert!(super::assistant_live_level(1, 0.0, 0.0).unwrap() > 0.3);
        assert_eq!(super::assistant_live_level(5, 0.0, 0.0), None);
        assert_eq!(super::assistant_live_level(0, f64::NAN, 0.0), None);
    }

    #[test]
    fn assistant_live_particle_scales_with_input_and_validates_geometry() {
        let column = super::assistant_cloud_column(23, 0.0, false).unwrap();
        let quiet = super::assistant_live_particle(0.5, 0.5, 1.0, 0.5, 0.0, 38.0, 24.0,
            column, 0.0, 0.0, false, true).unwrap();
        let loud = super::assistant_live_particle(0.5, 0.5, 1.0, 0.5, 0.0, 38.0, 24.0,
            column, 1.0, 0.0, false, true).unwrap();
        assert!(loud[2] > quiet[2] && loud[3] > quiet[3]);
        assert!(super::assistant_live_particle(0.5, 0.5, 1.0, 0.5, 0.0, 0.0, 24.0,
            column, 0.0, 0.0, false, true).is_none());
    }

    #[test]
    fn agent_arrival_arms_use_reference_scale_and_surface_bounds() {
        use super::agent_arrival_arm_run;
        assert!((agent_arrival_arm_run(0, 3000.0, 185.0).unwrap() - 167.2).abs() < 1e-9);
        assert_eq!(agent_arrival_arm_run(3, 3000.0, 185.0), Some(768.0));
        assert_eq!(agent_arrival_arm_run(3, 640.0, 185.0), Some(227.5));
        assert_eq!(agent_arrival_arm_run(1, 100.0, 185.0), Some(0.0));
        assert!(agent_arrival_arm_run(4, 1512.0, 185.0).is_none());
        assert!(agent_arrival_arm_run(0, f64::NAN, 185.0).is_none());
    }

    #[test]
    fn agent_arrival_segments_follow_the_supplied_shoulder_arc() {
        use super::arrival_segments;
        let flat = arrival_segments(1, 0.82 * 0.68, 1000.0, 200.0, 185.0, 32.0, 0.0).unwrap();
        let curved = arrival_segments(1, 0.82 * 0.68, 1000.0, 200.0, 185.0, 32.0, 40.0).unwrap();
        assert!((curved[2].start - flat[2].start - 0.02).abs() < 1e-9);
        let done = arrival_segments(2, 0.3, 1000.0, 200.0, 185.0, 32.0, 40.0).unwrap();
        assert!((done[0].end - 0.24).abs() < 1e-9);
        let reminder_flat = arrival_segments(4, 2.0 * 0.68, 1000.0, 200.0, 185.0, 32.0, 0.0).unwrap();
        let reminder_curved = arrival_segments(4, 2.0 * 0.68, 1000.0, 200.0, 185.0, 32.0, 40.0).unwrap();
        assert!((reminder_curved[0].start - reminder_flat[0].start - 0.02).abs() < 1e-9);
        assert!(arrival_segments(1, 0.3, 1000.0, 200.0, 185.0, 32.0, -2.0).is_none());
    }

    #[test]
    fn response_crests_split_symmetrically_and_finish() {
        use super::arrival_segments;
        let mid = arrival_segments(8, 0.425, 1000.0, 200.0, 185.0, 32.0, 40.0).unwrap();
        assert_eq!(mid.len(), 2);
        assert!((mid[0].start - 0.189).abs() < 1e-9 && (mid[0].end - 0.341).abs() < 1e-9);
        assert!((mid[1].start - 0.659).abs() < 1e-9 && (mid[1].end - 0.811).abs() < 1e-9);
        assert!((mid[0].opacity - 0.78).abs() < 1e-9);
        assert!(arrival_segments(8, 0.85, 1000.0, 200.0, 185.0, 32.0, 40.0).unwrap().is_empty());
        assert!(arrival_segments(8, 0.1, 0.0, 200.0, 185.0, 32.0, 40.0).unwrap().is_empty());
    }

    #[test]
    fn playback_start_expands_and_pause_contracts_with_distinct_crests() {
        use super::playback_transition_envelope;
        assert_eq!(playback_transition_envelope(0.0), Some(0.0));
        assert!((playback_transition_envelope(0.0225).unwrap() - 0.5).abs() < 1e-9);
        assert!((playback_transition_envelope(0.61).unwrap() - 0.5).abs() < 1e-9);
        assert!(playback_transition_envelope(-0.1).is_none());
        assert!(playback_transition_envelope(f64::NAN).is_none());
        let play = arrival_segments(5, 0.31, 1000.0, 200.0, 185.0, 32.0, 40.0).unwrap();
        let pause = arrival_segments(6, 0.31, 1000.0, 200.0, 185.0, 32.0, 40.0).unwrap();
        assert!((play[0].start - 0.25).abs() < 1e-9 && (play[0].end - 0.75).abs() < 1e-9);
        assert!((pause[0].start - 0.34).abs() < 1e-9 && (pause[0].end - 0.66).abs() < 1e-9);
        assert!((play[0].opacity - 0.3).abs() < 1e-9 && (play[1].opacity - 0.95).abs() < 1e-9);
        assert!((pause[0].opacity - 0.24).abs() < 1e-9 && (pause[1].opacity - 0.82).abs() < 1e-9);
        assert!((play[1].end - play[1].start - 0.096).abs() < 1e-9);
        assert!((pause[1].end - pause[1].start - 0.044).abs() < 1e-9);
        assert!(arrival_segments(5, 0.85, 1000.0, 0.0, 0.0, 0.0, 0.0).unwrap().is_empty());
        assert!(arrival_segments(6, 0.1, 0.0, 0.0, 0.0, 0.0, 0.0).unwrap().is_empty());
    }

    #[test]
    fn track_skip_pass_reverses_direction_and_finishes() {
        let forward = arrival_segments(9, 0.23, 1000.0, 200.0, 185.0, 32.0, 40.0).unwrap();
        let backward = arrival_segments(10, 0.23, 1000.0, 200.0, 185.0, 32.0, 40.0).unwrap();
        assert_eq!(forward.len(), 3);
        assert!((forward[1].start + backward[1].end - 1.0).abs() < 1e-9);
        assert!((forward[2].start + backward[2].end - 1.0).abs() < 1e-9);
        assert!((forward[0].opacity - 0.42).abs() < 1e-9);
        assert!((forward[1].opacity - 0.98).abs() < 1e-9 && (forward[2].opacity - 0.58).abs() < 1e-9);
        assert!((forward[1].end - forward[1].start - 0.064).abs() < 1e-9);
        let fading = arrival_segments(9, 0.38, 1000.0, 200.0, 185.0, 32.0, 40.0).unwrap();
        assert!((fading[1].opacity - 0.49).abs() < 1e-9);
        assert!(arrival_segments(9, 0.46, 1000.0, 200.0, 185.0, 32.0, 40.0).unwrap().is_empty());
        assert!(arrival_segments(9, 0.1, 0.0, 200.0, 185.0, 32.0, 40.0).unwrap().is_empty());
    }

    #[test]
    fn track_skip_arrival_fades_the_entire_contour() {
        let start = arrival_segments(11, 0.0, 1000.0, 200.0, 185.0, 32.0, 40.0).unwrap();
        let middle = arrival_segments(11, 0.29, 1000.0, 200.0, 185.0, 32.0, 40.0).unwrap();
        assert_eq!((start[0].start, start[0].end), (0.0, 1.0));
        assert!((start[0].opacity - 0.88).abs() < 1e-9);
        assert!((middle[0].opacity - 0.22).abs() < 1e-9);
        assert!(arrival_segments(11, 0.58, 1000.0, 200.0, 185.0, 32.0, 40.0).unwrap().is_empty());
    }

    #[test]
    fn track_skip_hunt_repeats_and_mirrors_direction() {
        let first = arrival_segments(12, 0.31, 1000.0, 200.0, 185.0, 32.0, 40.0).unwrap();
        let repeated = arrival_segments(12, 0.93, 1000.0, 200.0, 185.0, 32.0, 40.0).unwrap();
        let backward = arrival_segments(13, 0.31, 1000.0, 200.0, 185.0, 32.0, 40.0).unwrap();
        assert!((first[1].start - repeated[1].start).abs() < 1e-9);
        assert!((first[2].start + backward[2].end - 1.0).abs() < 1e-9);
        assert!((first[0].opacity - 0.58 * 0.42).abs() < 1e-9);
        assert!((first[1].opacity - 0.58 * 0.98).abs() < 1e-9);
        assert!((first[2].opacity - 0.58 * 0.58).abs() < 1e-9);
        assert!((first[1].end - first[1].start - 0.064).abs() < 1e-9);
        assert!(arrival_segments(12, -1.0, 1000.0, 200.0, 185.0, 32.0, 40.0).unwrap().is_empty());
    }

    #[test]
    fn reduced_motion_track_skip_distinguishes_pass_from_hunt() {
        use super::track_skip_reduced_opacity;
        assert_eq!(track_skip_reduced_opacity(9, 0.0), Some(0.44));
        assert!((track_skip_reduced_opacity(10, 0.23).unwrap() - 0.22).abs() < 1e-9);
        assert_eq!(track_skip_reduced_opacity(9, 0.46), Some(0.0));
        assert_eq!(track_skip_reduced_opacity(12, 2.0), Some(0.24));
        assert_eq!(track_skip_reduced_opacity(13, 0.0), Some(0.24));
        assert!(track_skip_reduced_opacity(11, 0.0).is_none());
        assert!(track_skip_reduced_opacity(9, f64::NAN).is_none());
    }

    #[test]
    fn track_skip_peek_indicator_chases_and_reverses() {
        use super::track_skip_peek_wave;
        assert_eq!(track_skip_peek_wave(0.0, 0, true), Some(1.0));
        assert_eq!(track_skip_peek_wave(0.0, 2, false), Some(1.0));
        assert!((track_skip_peek_wave(1.0 / 6.0, 0, true).unwrap() - 0.25).abs() < 1e-9);
        assert_eq!(track_skip_peek_wave(-1.0, 1, true), Some(1.0));
        assert!(track_skip_peek_wave(0.0, 3, true).is_none());
        assert!(track_skip_peek_wave(f64::NAN, 0, true).is_none());
    }

    #[test]
    fn response_halo_expands_and_fades_with_the_reference_pulse() {
        use super::response_halo_frame;
        let mid = response_halo_frame(0.425, 200.0).unwrap();
        assert!((mid[0] - 115.0).abs() < 1e-9);
        assert!((mid[1] - 62.0).abs() < 1e-9);
        assert!((mid[2] - 0.46).abs() < 1e-9);
        assert_eq!(response_halo_frame(0.85, 200.0), Some([0.0; 3]));
        assert_eq!(response_halo_frame(-0.1, 200.0), Some([0.0; 3]));
        assert!(response_halo_frame(0.4, f64::NAN).is_none());
    }

    #[test]
    fn collapsed_music_uses_audio_when_available_and_respects_motion_preference() {
        let levels = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0];
        let silent = super::collapsed_music_wave_frame(0, 0.0, Some(&levels), false, 42, 0.0).unwrap();
        assert_eq!(silent, [5.76, 0.55]);
        let envelope = 0.78 + 0.22 * (6.0 * std::f64::consts::PI / 7.0).sin();
        let pulse = 0.75 + 0.25 * (13.0f64).sin();
        let loud = super::collapsed_music_wave_frame(5, 0.0, Some(&levels), false, 42, 0.0).unwrap();
        assert!((loud[0] - 21.6 * (0.2 + 0.8 * pulse * envelope)).abs() < 1e-9);
        assert!((loud[1] - (0.55 + 0.42 * pulse)).abs() < 1e-9);
        let still = super::collapsed_music_wave_frame(0, 0.0, Some(&levels), true, 42, 0.0).unwrap();
        assert_eq!(still, super::collapsed_music_wave_frame(0, 50.0, None, true, 42, 50.0).unwrap());
        assert!((0.65..=0.68).contains(&still[1]));
        let first = super::collapsed_music_wave_frame(0, 0.0, None, false, 42, 0.0).unwrap();
        let later = super::collapsed_music_wave_frame(0, 0.1, None, false, 42, 0.1).unwrap();
        assert_ne!(first, later);
        assert_ne!(first, super::collapsed_music_wave_frame(0, 0.0, None, false, 99, 0.0).unwrap());
        assert_eq!(super::collapsed_music_wave_frame(0, 1.0, Some(&levels), false, 42, 1.0),
                   super::collapsed_music_wave_frame(0, 1.0, Some(&levels), false, 99, 20.0));
        assert!(super::collapsed_music_wave_frame(0, 0.0, None, false, 42, f64::NAN).is_none());
        assert!(collapsed_music_wave_height(0, 0.0, Some(&[f64::NAN; 6]), false).is_none());
        assert!(collapsed_music_wave_height(6, 0.0, None, false).is_none());
    }

    #[test]
    fn idle_shimmer_is_subtle_periodic_and_respects_reduce_motion() {
        let start = idle_shimmer_frame(0.0, false).unwrap();
        let later = idle_shimmer_frame(3.75, false).unwrap();
        assert!(later[0] > start[0] && later[1] > start[1]);
        assert_ne!(idle_shimmer_frame(14.0, false).unwrap()[0], start[0]);
        assert_eq!(idle_shimmer_frame(70.0, false), Some(start));
        let before = idle_shimmer_frame(70.0 - 1e-6, false).unwrap();
        let after = idle_shimmer_frame(70.0 + 1e-6, false).unwrap();
        for (left, right) in before.iter().zip(after) { assert!((left - right).abs() < 1e-6); }
        for step in 0..700 {
            let [position, strength] = idle_shimmer_frame(step as f64 / 10.0, false).unwrap();
            assert!((0.22..=0.78).contains(&position) && (0.040..=0.070).contains(&strength));
        }
        assert_eq!(idle_shimmer_frame(10.0, true), Some([0.5, 0.0]));
        assert!(idle_shimmer_frame(f64::NAN, false).is_none());
    }

    #[test]
    fn shelf_hover_crests_repeat_and_respect_reduced_motion() {
        use super::shelf_hover_progress;
        assert_eq!(shelf_hover_progress(0.0, false), Some([0.0, 0.0]));
        assert_eq!(shelf_hover_progress(1.5, false), Some([0.0, 0.0]));
        let mid = shelf_hover_progress(0.75, false).unwrap();
        assert!((mid[0] - 0.5).abs() < 1e-9 && mid[1] > 0.0 && mid[1] < mid[0]);
        assert_eq!(shelf_hover_progress(0.75, true), Some([0.0, 0.0]));
        assert!(shelf_hover_progress(f64::NAN, false).is_none());
    }

    #[test]
    fn shelf_catch_reaches_the_shoulder_then_fades() {
        use super::shelf_catch_frame;
        assert_eq!(shelf_catch_frame(0.0, false), Some([0.0, 0.0]));
        assert_eq!(shelf_catch_frame(0.3, false), Some([1.0, 1.0]));
        assert_eq!(shelf_catch_frame(0.62, false), Some([1.0, 0.0]));
        assert_eq!(shelf_catch_frame(0.08, true), Some([1.0, 1.0]));
        assert!(shelf_catch_frame(-1.0, false).is_none());
    }

    #[test]
    fn organic_rays_span_each_arm_and_reject_bad_parameters() {
        use super::{organic_ray, rium_notch_organic_ray};
        let left = organic_ray(0, 12, -1, 220.0, 1.0, 1.0).unwrap();
        let right = organic_ray(0, 12, 1, 220.0, 1.0, 1.0).unwrap();
        assert_eq!(left[0], 0.0);
        assert!((right[0] - 0.169_048_935_965).abs() < 1e-7);
        assert!(left[3] < 0.0 && right[3] > 0.0);
        for side in [-1, 1] {
            for index in 0..12 {
                let ray = organic_ray(index, 12, side, 220.0, 1.0, 1.0).unwrap();
                assert!((0.0..=206.0).contains(&ray[0]));
                assert!(ray[1] > 0.0 && ray[2] >= 1.3 && ray[2] < 4.3 && ray[4] > 0.0 && ray[4] < 0.15);
            }
        }
        assert!(organic_ray(12, 12, -1, 220.0, 1.0, 1.0).is_none());
        assert!(organic_ray(0, 12, 0, 220.0, 1.0, 1.0).is_none());
        assert!(organic_ray(0, 12, -1, f64::NAN, 1.0, 1.0).is_none());
        assert_eq!(unsafe { rium_notch_organic_ray(0, 12, -1, 220.0, 1.0, 1.0, std::ptr::null_mut()) }, -1);
    }

    #[test]
    fn humidity_field_uses_reference_seed_and_bounded_output() {
        use super::{humidity_speck, organic_ray_fog, rium_notch_humidity_specks};
        let point = humidity_speck(7, 200.0, 66.0, 1.0).unwrap();
        for (actual, expected) in point.iter().zip([0.374147008365, 0.600888454334, 0.610170977590, 0.085890230463]) {
            assert!((actual - expected).abs() < 1e-7);
        }
        let dim = humidity_speck(7, 400.0, 100.0, 0.5).unwrap();
        assert_eq!(&point[..3], &dim[..3]);
        assert!((dim[3] / point[3] - 0.11 / 0.18).abs() < 1e-12);
        assert_eq!(organic_ray_fog(1000.0, 1.0).unwrap()[5], 0.08);
        assert!(humidity_speck(1400, 200.0, 66.0, 1.0).is_none());
        assert!(humidity_speck(0, f64::NAN, 66.0, 1.0).is_none());
        let mut output = [0.0; 1400 * 4];
        let count = unsafe { rium_notch_humidity_specks(40.0, 66.0, 1.0, output.as_mut_ptr(), output.len()) };
        assert!(count > 0 && count <= 120);
        assert!(output[..count as usize * 4].chunks_exact(4).all(|point|
            (0.0..=1.0).contains(&point[0]) && (0.0..=1.0).contains(&point[1])
                && (0.35..0.8).contains(&point[2]) && point[3] > 0.003));
        assert_eq!(unsafe { rium_notch_humidity_specks(40.0, 66.0, 1.0, output.as_mut_ptr(), output.len() - 1) }, -1);
    }

    #[test]
    fn idle_breath_stays_visible_and_continuous_across_its_cycle() {
        use super::idle_light_frame;
        let before = idle_light_frame(180.0 - 1e-6, false).unwrap();
        let after = idle_light_frame(180.0 + 1e-6, false).unwrap();
        for (a, b) in before.iter().zip(after) { assert!((a - b).abs() < 1e-5); }
        let samples: Vec<_> = (0..360).map(|step| idle_light_frame(step as f64 / 2.0, false).unwrap()).collect();
        assert!(samples.iter().all(|frame| frame.iter().all(|value| *value > 0.85 && *value < 1.15)));
        assert!(samples.iter().any(|frame| (frame[0] - 1.0).abs() > 0.01));
        assert_eq!(idle_light_frame(27.0, true), Some([1.0, 1.0, 1.0]));
        assert!(idle_light_frame(f64::INFINITY, false).is_none());
    }

    #[test]
    fn organic_crests_have_reference_cycles_and_half_cycle_offset() {
        use super::agent_organic_travel;
        assert_eq!(agent_organic_travel(0.0, false, false), Some([0.0, 0.5]));
        let general = agent_organic_travel(1.05, false, false).unwrap();
        assert!((general[0] - 0.5).abs() < 1e-12 && general[1].abs() < 1e-12);
        let acting = agent_organic_travel(0.725, true, false).unwrap();
        assert!((acting[0] - 0.5).abs() < 1e-12 && acting[1].abs() < 1e-12);
        assert_eq!(agent_organic_travel(1.0, true, true), agent_organic_travel(0.6, true, false));
        assert_eq!(agent_organic_travel(1.0, false, true), agent_organic_travel(0.6, false, false));
        assert!(agent_organic_travel(f64::NAN, false, false).is_none());
        assert!(agent_organic_travel(-1.0, false, false).is_none());
    }

    #[test]
    fn organic_crest_positions_are_mirrored_only_for_thinking() {
        use super::agent_organic_crests;
        let thinking = agent_organic_crests(0.525, false, true, false).unwrap();
        let acting = agent_organic_crests(0.3625, true, false, false).unwrap();
        assert!((thinking[0][0] - 0.27).abs() < 1e-12);
        assert!((thinking[1][0] - 0.27).abs() < 1e-12);
        assert!((acting[1][0] - 0.73).abs() < 1e-12);
        assert!(thinking.iter().all(|crest| (0.0..=1.0).contains(&crest[1])));
        let start = agent_organic_crests(0.0, false, false, false).unwrap();
        assert_eq!(start[0][1], 0.0);
        assert_eq!(start[1][1], 1.0);
        let middle = agent_organic_crests(0.525, false, false, false).unwrap();
        assert_eq!(middle[0][1], 1.0);
        assert!(agent_organic_crests(f64::NAN, false, false, false).is_none());
    }

    #[test]
    fn organic_crests_use_brightened_glacier_and_amber_samples() {
        use super::agent_organic_crest_colors;
        let glacier = agent_organic_crest_colors(false);
        let amber = agent_organic_crest_colors(true);
        for (actual, expected) in glacier[0].iter().zip([0.816, 0.928, 1.0]) {
            assert!((actual - expected).abs() < 1e-12);
        }
        for (actual, expected) in glacier[1].iter().zip([0.583875, 0.664, 0.989875]) {
            assert!((actual - expected).abs() < 1e-12);
        }
        for (actual, expected) in amber[0].iter().zip([0.984, 0.868, 0.604]) {
            assert!((actual - expected).abs() < 1e-12);
        }
        assert_ne!(amber[0], amber[1]);
        assert!(amber.iter().flatten().all(|component| (0.0..=1.0).contains(component)));
    }

    #[test]
    fn dictation_gradient_uses_reference_palette_and_period() {
        use super::dictation_aurora_palette;
        let colors = dictation_aurora_palette(0.0, 0.9, 0.0, false).unwrap();
        assert_eq!(colors[0], [0.82, 0.27, 0.60]);
        assert_eq!(colors, dictation_aurora_palette(5.0, 0.9, 0.0, false).unwrap());
        assert_ne!(colors, dictation_aurora_palette(1.0, 0.9, 0.0, false).unwrap());
        assert_eq!(dictation_aurora_palette(10.0, 1.6, 0.45, true), dictation_aurora_palette(0.6, 1.6, 0.45, false));
        assert!(dictation_aurora_palette(f64::NAN, 0.9, 0.0, false).is_none());
        assert!(dictation_aurora_palette(0.0, 0.9, 1.1, false).is_none());
    }

    #[test]
    fn aurora_palettes_handle_rounding_at_the_cycle_boundary() {
        use super::{dictation_aurora_palette, organic_palette_color, question_palette_color};
        let tiny = f64::EPSILON / 8.0;
        assert_eq!((-tiny).rem_euclid(1.0), 1.0);
        assert_eq!(dictation_aurora_palette(tiny, 0.9, 0.0, false).unwrap()[0], [0.82, 0.27, 0.60]);
        assert_eq!(organic_palette_color(false, -tiny, 0.0), [0.72, 0.90, 1.0]);
        assert_eq!(organic_palette_color(true, -tiny, 0.0), [1.0, 0.80, 0.34]);
        assert_eq!(question_palette_color(-tiny, 0.0), [1.0, 0.80, 0.34]);
    }

    #[test]
    fn organic_gradient_moves_cycles_and_respects_reduce_motion() {
        use super::agent_organic_palette;
        let glacier = agent_organic_palette(0.0, false, false, 0.0).unwrap();
        assert_eq!(glacier[0], [0.72, 0.90, 1.0]);
        assert_eq!(glacier, agent_organic_palette(4.0, false, false, 0.0).unwrap());
        assert_ne!(glacier, agent_organic_palette(1.0, false, false, 0.0).unwrap());
        assert_eq!(agent_organic_palette(10.0, true, true, 0.0), agent_organic_palette(0.6, true, false, 0.0));
        assert!(agent_organic_palette(f64::NAN, false, false, 0.0).is_none());
        assert!(agent_organic_palette(0.0, false, false, 1.1).is_none());
    }

    #[test]
    fn agent_breath_repeats_without_a_wrap_jump() {
        let peak = agent_light_frame(1.9 / 4.0, false).unwrap();
        assert!((peak[0] - 1.025).abs() < 1e-9);
        let first = agent_light_frame(0.0, false).unwrap();
        let repeated = agent_light_frame(190.0, false).unwrap();
        assert!(first.iter().zip(repeated).all(|(a, b)| (a - b).abs() < 1e-9));
        assert_eq!(agent_light_frame(0.5, true), Some([1.0, 1.0, 0.5, 0.0]));
    }

    #[test]
    fn question_halo_uses_reference_pulse_and_static_phase() {
        use super::question_light_frame;
        assert_eq!(question_light_frame(0.0, 200.0, false), Some([0.0, 96.0, 42.0]));
        let peak = question_light_frame(1.25, 200.0, false).unwrap();
        assert!((peak[0] - 1.0).abs() < 1e-9);
        assert!((peak[1] - 120.0).abs() < 1e-9);
        assert!((peak[2] - 70.0).abs() < 1e-9);
        assert_eq!(question_light_frame(4.0, 200.0, true), question_light_frame(0.6, 200.0, false));
        assert!(question_light_frame(f64::NAN, 200.0, false).is_none());
    }

    #[test]
    fn question_aurora_wraps_reference_colors_smoothly() {
        use super::question_light_palette;
        let colors = question_light_palette(0.0, false, 0.0).unwrap();
        assert_eq!(colors[0], [1.0, 0.8, 0.34]);
        assert!((colors[10][1] - 0.62912).abs() < 1e-9);
        assert!((colors[10][2] - 0.25744).abs() < 1e-9);
        assert_eq!(colors, question_light_palette(12.5, false, 0.0).unwrap());
        assert_eq!(question_light_palette(0.0, true, 0.0), question_light_palette(0.6, false, 0.0));
        let highlight = question_light_palette(0.0, false, 0.25).unwrap();
        assert!((highlight[0][0] - 0.99).abs() < 1e-9);
        assert!((highlight[0][1] - 0.8425).abs() < 1e-9);
        assert!((highlight[0][2] - 0.505).abs() < 1e-9);
        assert!(question_light_palette(f64::NAN, false, 0.0).is_none());
        assert!(question_light_palette(0.0, false, 2.0).is_none());
    }

    #[test]
    fn question_highlight_spans_both_lower_corners() {
        use super::question_highlight_range;
        let range = question_highlight_range(400.0, 20.0, 10.0, 10.0, 1000.0).unwrap();
        assert!((range[0] - 0.405).abs() < 1e-9 && (range[1] - 0.595).abs() < 1e-9);
        assert_eq!(question_highlight_range(0.0, 0.0, 0.0, 0.0, 100.0), Some([0.0, 1.0]));
        assert!(question_highlight_range(1.0, 1.0, 1.0, 1.0, 0.0).is_none());
    }

    #[test]
    fn question_crests_move_inward_and_fade_each_cycle() {
        use super::question_crests;
        let start = question_crests(0.0, 1000.0).unwrap();
        assert!((start[0] - 0.04).abs() < 1e-9 && (start[1] - 0.96).abs() < 1e-9);
        assert_eq!(start[3], 0.0);
        let middle = question_crests(1.25, 1000.0).unwrap();
        assert!((middle[0] - 0.24).abs() < 1e-9 && (middle[1] - 0.76).abs() < 1e-9);
        assert!((middle[2] - 0.082).abs() < 1e-9 && (middle[3] - 0.72).abs() < 1e-9);
        assert_eq!(start, question_crests(2.5, 1000.0).unwrap());
        assert!(question_crests(0.0, 0.0).is_none());
    }

    #[test]
    fn timer_contour_endpoints_contract_and_reject_invalid_geometry() {
        use super::timer_contour_crests;
        assert_eq!(timer_contour_crests(1.0, 400.0), Some([0.0, 1.0, 0.04]));
        assert_eq!(timer_contour_crests(0.5, 400.0), Some([0.25, 0.75, 0.04]));
        assert_eq!(timer_contour_crests(-1.0, 400.0), Some([0.5, 0.5, 0.04]));
        assert!(timer_contour_crests(f64::NAN, 400.0).is_none());
        assert!(timer_contour_crests(0.5, 0.0).is_none());
    }

    #[test]
    fn agent_token_colors_are_reference_rgb() {
        assert_eq!(agent_token_color("파일 확인"), [0.50, 0.78, 1.0]);
        assert_eq!(agent_token_color("파일 수정"), [0.30, 0.68, 1.0]);
        assert_eq!(agent_token_color("웹 검색"), [0.72, 0.61, 1.0]);
        assert_eq!(agent_token_color("작업 실행"), [1.0, 0.70, 0.36]);
        assert_eq!(agent_token_color("EDIT"), [0.30, 0.68, 1.0]);
        assert_eq!(agent_token_color("도구 사용"), [1.0, 1.0, 1.0]);
        assert_eq!(agent_token_kind_color(2), Some([1.0, 0.70, 0.36]));
        assert_eq!(agent_token_kind_color(4), Some([1.0, 1.0, 1.0]));
        assert_eq!(agent_token_kind_color(5), None);
    }

    #[test]
    fn source_wave_matches_reference_baseline_and_oscillator() {
        assert_eq!(home_source_wave_height(0, 0.0, false, false), Some(4.95));
        assert_eq!(home_source_wave_height(0, 0.0, true, true), Some(4.95));
        assert_eq!(home_source_wave_height(0, 0.0, true, false), Some(6.25));
        let t: f64 = 0.4;
        let expected = 3.0 + 13.0 * (0.25 + 0.75 * ((3.0 * t + 0.9).sin() * (1.7 * t + 1.0).cos()).abs());
        assert!((home_source_wave_height(1, t, true, false).unwrap() - expected).abs() < 1e-9);
        assert!(home_source_wave_height(14, 0.0, true, false).is_none());
        assert!(home_source_wave_height(0, f64::NAN, true, false).is_none());
    }

    #[test]
    fn home_disc_angle_wraps_and_preserves_the_paused_angle() {
        assert_eq!(home_disc_angle(25.0, 0.0), Some(25.0));
        assert_eq!(home_disc_angle(25.0, 1.0), Some(175.0));
        assert!((home_disc_angle(25.0, 2.4).unwrap() - 25.0).abs() < 1e-9);
        assert!(home_disc_angle(0.0, -1.0).is_none());
        assert!(home_disc_angle(f64::NAN, 0.0).is_none());
    }

    #[test]
    fn home_music_wave_matches_reference_shape_and_playback() {
        let peak_time = std::f64::consts::PI / 4.8;
        assert_eq!(home_music_wave_height(0, 0.0, false, false), Some(12.0));
        assert!((home_music_wave_height(0, peak_time, true, false).unwrap() - 18.0).abs() < 1e-9);
        assert_eq!(home_music_wave_height(0, peak_time, true, true), Some(12.0));
        assert!(home_music_wave_height(26, 0.0, true, false).is_none());
        assert!(home_music_wave_height(0, f64::NAN, true, false).is_none());
    }

    #[test]
    fn compact_orb_fades_at_both_ends_and_stops_moving_for_reduced_motion() {
        assert_eq!(agent_peek_orb(0.0, false, false).unwrap()[1], 0.0);
        assert!(agent_peek_orb(1.0, false, false).unwrap()[1] > 0.9);
        assert_eq!(agent_peek_orb(2.5, false, false).unwrap()[1], 0.0);
        assert_eq!(agent_peek_orb(1.0, true, true), agent_peek_orb(2.0, true, true));
        assert!(agent_peek_orb(f64::NAN, false, false).is_none());
    }

    #[test]
    fn sound_cues_prioritize_attention_and_coalesce_duplicates() {
        assert_eq!(sound_cue_admit(0, Some(2), 0.1, false), Some(true));
        assert_eq!(sound_cue_admit(2, Some(0), 0.1, false), Some(false));
        assert_eq!(sound_cue_admit(0, Some(0), 0.24, true), Some(false));
        assert_eq!(sound_cue_admit(0, Some(0), 0.25, true), Some(true));
        assert_eq!(sound_cue_admit(4, Some(0), 0.1, false), Some(true));
        assert_eq!(sound_cue_admit(2, Some(0), 1.2, false), Some(true));
    }

    #[test]
    fn agent_pacer_respects_attention_battery_and_recent_history() {
        assert_eq!(agent_wave_admit(20.0, 1, 1, false, false, &[(19.5, 0)]), Some(true));
        assert_eq!(agent_wave_admit(20.0, 1, 1, false, true, &[(19.5, 1)]), Some(false));
        assert_eq!(agent_wave_admit(20.0, 0, 3, false, false, &[]), Some(false));
        assert_eq!(agent_wave_admit(20.0, 2, 1, true, false, &[(15.0, 2)]), Some(false));
        assert_eq!(agent_wave_admit(20.0, 2, 1, false, false, &[(15.0, 2)]), Some(true));
        assert_eq!(agent_wave_admit(80.0, 0, 1, false, false, &[(1.0, 0), (2.0, 0), (3.0, 0)]), Some(true));
        assert_eq!(agent_wave_admit(20.0, 0, 1, false, false, &[(21.0, 0)]), None);
    }

    #[test]
    fn agent_wave_uses_the_unoffset_outward_shader_timeline() {
        let start = agent_screen_wave(0.0).unwrap();
        let middle = agent_screen_wave(1.0).unwrap();
        let end = agent_screen_wave(2.6).unwrap();
        assert_eq!(start[0], 0.0);
        assert!(middle[0] > start[0] && middle[1] > 0.0);
        assert!(end[0] > middle[0] && end[1].abs() < 1.0e-10);
        assert!(agent_screen_wave(-0.1).is_none());
        assert!(agent_screen_wave(f64::NAN).is_none());
    }

    #[test]
    fn edge_wave_fallback_respects_surface_and_transparency() {
        use super::edge_wave_fallback_color;
        let color = [0.2, 0.8, 0.4];
        assert_eq!(edge_wave_fallback_color(color, 0.5, 0), Some([0.2, 0.8, 0.4, 0.5]));
        let velvet = edge_wave_fallback_color(color, 0.5, 2).unwrap();
        assert!((velvet[0] - 0.25).abs() < 1e-12 && (velvet[3] - 0.4).abs() < 1e-12);
        let neon = edge_wave_fallback_color(color, 0.5, 1).unwrap();
        assert!(neon[0] < velvet[0] && (neon[3] - 0.44).abs() < 1e-12);
        let faint = edge_wave_fallback_color(color, 0.0001, 2).unwrap();
        assert!((faint[1] - 0.08).abs() < 1e-12 && (faint[3] - 0.00008).abs() < 1e-12);
        assert_eq!(edge_wave_fallback_color(color, 0.0, 1), Some([0.0; 4]));
        assert!(edge_wave_fallback_color(color, f64::NAN, 1).is_none());
        assert!(edge_wave_fallback_color(color, 0.5, 3).is_none());
    }

    #[test]
    fn edge_wave_detail_varies_over_time_and_stays_bounded() {
        let a = edge_wave_detail(0.5, 0.5, 0.4).unwrap();
        let b = edge_wave_detail(0.5, 1.5, 0.4).unwrap();
        assert_ne!(a, b);
        assert!(a[0].abs() < 0.1 && (0.0..=1.0).contains(&a[1]) && a[2] >= 0.0);
        assert!(edge_wave_detail(f64::NAN, 1.0, 0.2).is_none());
    }

    #[test]
    fn edge_wave_changes_direction_and_stops() {
        assert!(edge_wave_frame(0.2, true).unwrap()[0] > edge_wave_frame(1.8, true).unwrap()[0]);
        assert!(edge_wave_frame(2.0, false).unwrap()[0] > edge_wave_frame(0.4, false).unwrap()[0]);
        assert_eq!(edge_wave_frame(3.0, false), Some([0.0, 0.0]));
        assert!(edge_wave_frame(-1.0, true).is_none());
    }

    #[test]
    fn receiving_tide_draws_inward_and_held_charge_tracks_progress() {
        let start = receiving_tide_frame(0.0, 0.0, 0.0, false, false).unwrap();
        let end = receiving_tide_frame(2.0, 0.0, 0.0, false, false).unwrap();
        assert!(start[0] > end[0] && end[1] > start[1]);
        let low = receiving_tide_frame(3.0, 0.0, 0.0, true, true).unwrap();
        let high = receiving_tide_frame(3.0, 0.0, 1.0, true, true).unwrap();
        assert!(high[0] > low[0] && high[1] > low[1]);
        assert!(receiving_tide_frame(f64::NAN, 0.0, 0.0, false, false).is_none());
    }

    #[test]
    fn paste_effect_stays_symmetric_and_expires() {
        let parts = shortcut_segments(7, 0.3).unwrap();
        assert_eq!(parts.len(), 2);
        assert!((parts[0].start + parts[1].end - 1.0).abs() < 1e-9);
        assert!((parts[0].end + parts[1].start - 1.0).abs() < 1e-9);
        assert!(shortcut_segments(7, 1.15).unwrap().is_empty());
        assert_eq!(shortcut_icon_frame(7, 0.3, true).unwrap()[3], 0.0);
        assert!(shortcut_icon_frame(10, 0.3, false).is_none());
        assert!(!shortcut_segments(8, 0.2).unwrap().is_empty());
        assert!(shortcut_segments(9, 1.15).unwrap().is_empty());
    }

    #[test]
    fn shortcut_light_uses_action_specific_reference_lifetimes() {
        let durations = [0.54, 0.62, 0.60, 0.66, 0.78, 0.52, 0.58, 0.60, 0.85, 1.10];
        for (kind, expected) in durations.into_iter().enumerate() {
            assert_eq!(shortcut_light_duration(kind as i32), Some(expected));
            assert!(shortcut_segments(kind as i32, expected).unwrap().is_empty());
        }
        assert_eq!(shortcut_light_duration(-1), None);
        assert_eq!(shortcut_light_duration(10), None);
    }

    #[test]
    fn shortcut_prism_retains_each_actions_reference_colors() {
        use super::shortcut_prism;
        assert_eq!(shortcut_prism(0), Some([[1.0, 0.35, 0.24], [1.0, 0.12, 0.58]]));
        assert_eq!(shortcut_prism(4), Some([[0.43, 0.85, 1.0], [0.66, 0.42, 1.0]]));
        assert_eq!(shortcut_prism(5), Some([[0.20, 0.55, 1.0], [0.05, 1.0, 0.94]]));
        assert_eq!(shortcut_prism(8), shortcut_prism(9));
        assert_eq!(shortcut_prism(-1), None);
        assert_eq!(shortcut_prism(10), None);
    }

    #[test]
    fn print_light_uses_three_stationary_reference_pulses() {
        for time in [0.16, 0.38, 0.60] {
            let pulse = shortcut_segments(4, time).unwrap();
            assert_eq!(pulse.len(), 1);
            assert_eq!((pulse[0].start, pulse[0].end), (0.3, 0.7));
            assert!(pulse[0].opacity > 0.0);
        }
        for time in [0.0, 0.27, 0.49, 0.71] {
            assert!(shortcut_segments(4, time).unwrap().is_empty());
        }
    }

    #[test]
    fn select_all_gauge_and_trace_follow_reference_ramps() {
        use super::select_all_trace;
        let early = shortcut_segments(5, 0.035).unwrap();
        assert!((early[0].opacity - 0.78 * 0.5 * (0.035 / 0.06)).abs() < 1e-12);
        assert_eq!(select_all_trace(0.1).unwrap(), [5.0, 3.0, 0.0]);
        let middle = select_all_trace(0.29).unwrap();
        assert!((middle[0] - 17.0).abs() < 1e-12);
        assert!((middle[1] - 10.0).abs() < 1e-12);
        assert!((middle[2] - 0.32 * (0.23 / 0.24)).abs() < 1e-12);
        assert!(select_all_trace(f64::NAN).is_none());
    }

    #[test]
    fn screenshot_flash_has_a_held_peak_and_expanding_fade() {
        use super::screenshot_flash_frame;
        assert_eq!(screenshot_flash_frame(0.0), Some([0.0, 4.0, 3.0, 0.0]));
        assert_eq!(screenshot_flash_frame(0.1), Some([0.85, 4.0, 3.0, 0.45]));
        assert_eq!(screenshot_flash_frame(0.26), Some([0.85, 4.0, 3.0, 0.45]));
        let later = screenshot_flash_frame(0.55).unwrap();
        assert!(later[0] < 0.85 && later[0] > 0.0 && later[1] > 4.0 && later[2] > 3.0);
        assert_eq!(screenshot_flash_frame(0.85), Some([0.0; 4]));
        assert!(screenshot_flash_frame(f64::NAN).is_none());
    }

    #[test]
    fn screenshot_file_light_closes_symmetrically_and_fades() {
        let early = super::screenshot_file_glow(0.08, 100.0, 500.0, false).unwrap();
        let middle = super::screenshot_file_glow(0.675, 100.0, 500.0, false).unwrap();
        let late = super::screenshot_file_glow(1.2, 100.0, 500.0, false).unwrap();
        assert!(early[0] < middle[0] && middle[0] < late[0] && (middle[0] + middle[1] - 1.0).abs() < 1e-12);
        assert!(early[2] > 0.0 && early[3] > 0.0 && early[5] == 0.0 && late[5] > 0.0);
        assert_eq!(super::screenshot_file_glow(1.35, 100.0, 500.0, false).unwrap()[2], 0.0);
        let reduced = super::screenshot_file_glow(0.4, 100.0, 500.0, true).unwrap();
        assert_eq!(reduced, [0.0, 1.0, 0.58, 0.0, 0.0, 0.0]);
        assert!(super::screenshot_file_glow(0.1, 1.0, 0.0, false).is_none());
        assert!(super::screenshot_file_glow(f64::NAN, 1.0, 100.0, false).is_none());
    }

    #[test]
    fn area_capture_gauge_breathes_at_the_reference_period() {
        let bright = shortcut_segments(9, 0.155).unwrap();
        let dim = shortcut_segments(9, 0.465).unwrap();
        assert_eq!((bright[0].start, bright[0].end), (0.0, 1.0));
        assert!((bright[0].opacity - 0.76).abs() < 1e-12);
        assert!((dim[0].opacity - 0.454).abs() < 1e-12);
    }

    #[test]
    fn area_capture_reticles_follow_symmetric_curves() {
        use super::area_capture_reticle;
        let frame = area_capture_reticle(0.155, 200.0, 30.0, 20.0, 10.0, 10.0).unwrap();
        for (actual, expected) in frame.into_iter().zip([0.2, 0.8, 0.325, 0.675, 0.12, 0.76]) {
            assert!((actual - expected).abs() < 1e-12);
        }
        assert_eq!(area_capture_reticle(1.1, 200.0, 30.0, 20.0, 10.0, 10.0).unwrap()[5], 0.0);
        assert!(area_capture_reticle(0.2, 0.0, 30.0, 20.0, 10.0, 10.0).is_none());
    }

    #[test]
    fn quit_light_contracts_and_adds_a_center_crest() {
        use super::shortcut_quit_crest;
        let gauge = shortcut_segments(6, 0.29).unwrap();
        assert!((gauge[0].start - 0.25).abs() < 1e-12);
        assert!((gauge[0].end - 0.75).abs() < 1e-12);
        assert!((gauge[0].opacity - 0.4).abs() < 1e-12);
        let crest = shortcut_quit_crest(0.29, 270.0).unwrap();
        assert!((crest[0] - 0.4).abs() < 1e-12 && (crest[1] - 0.6).abs() < 1e-12);
        assert!((crest[2] - 1.0).abs() < 1e-12);
        assert_eq!(shortcut_quit_crest(0.58, 270.0).unwrap()[2], 0.0);
        assert!(shortcut_quit_crest(0.2, 0.0).is_none());
    }

    #[test]
    fn save_light_expands_and_flashes_near_completion() {
        let midpoint = shortcut_segments(2, 0.3).unwrap();
        assert_eq!(midpoint.len(), 1);
        assert!((midpoint[0].start - 0.25).abs() < 1e-12);
        assert!((midpoint[0].end - 0.75).abs() < 1e-12);
        assert!((midpoint[0].opacity - 0.6).abs() < 1e-12);
        let completion = shortcut_segments(2, 0.546).unwrap();
        assert_eq!(completion.len(), 2);
        assert!(completion[1].highlight && (completion[1].opacity - 0.65).abs() < 1e-12);
        assert!(shortcut_segments(2, 0.6).unwrap().is_empty());
    }

    #[test]
    fn refresh_light_uses_two_trails_and_a_moving_crest() {
        use super::shortcut_refresh_crest;
        let parts = shortcut_segments(3, 0.33).unwrap();
        assert_eq!(parts.len(), 2);
        assert!((parts[0].start - 0.235 / 0.66).abs() < 1e-12 && (parts[0].end - 0.5).abs() < 1e-12);
        assert!((parts[0].opacity - 0.68).abs() < 1e-12);
        assert!((parts[1].start - 0.28).abs() < 1e-12 && (parts[1].opacity - 0.26).abs() < 1e-12);
        let crest = shortcut_refresh_crest(0.33, 300.0, 100.0).unwrap();
        assert!((crest[0] - 0.5).abs() < 1e-12 && (crest[1] - 0.1).abs() < 1e-12 && (crest[2] - 0.9).abs() < 1e-12);
        let edge = shortcut_refresh_crest(0.03, 300.0, 100.0).unwrap();
        assert!(edge[0] < edge[1]);
        assert!(shortcut_refresh_crest(0.1, 0.0, 100.0).is_none());
    }

    #[test]
    fn cut_light_separates_into_symmetric_edges() {
        use super::shortcut_cut_crests;
        let parts = shortcut_segments(0, 0.27).unwrap();
        assert_eq!(parts.len(), 2);
        assert!((parts[0].end - 0.375).abs() < 1e-12 && (parts[1].start - 0.625).abs() < 1e-12);
        assert!((parts[0].opacity - 0.62).abs() < 1e-12);
        let crests = shortcut_cut_crests(0.27, 260.0).unwrap();
        for (actual, expected) in crests.into_iter().zip([0.375, 0.625, 0.1, 0.85]) { assert!((actual - expected).abs() < 1e-12); }
        assert!(shortcut_cut_crests(0.1, 0.0).is_none());
    }

    #[test]
    fn undo_light_moves_left_with_a_delayed_trail() {
        use super::shortcut_undo_crest;
        let parts = shortcut_segments(1, 0.31).unwrap();
        assert_eq!(parts.len(), 2);
        assert!((parts[0].start - 0.5).abs() < 1e-12 && parts[0].end > 0.5);
        assert!((parts[0].opacity - 0.6).abs() < 1e-12 && (parts[1].opacity - 0.3).abs() < 1e-12);
        let ending = shortcut_segments(1, 0.60).unwrap();
        assert!((ending[1].end - ending[1].start - 0.18).abs() < 1e-12);
        let crest = shortcut_undo_crest(0.31, 340.0, 100.0).unwrap();
        assert!((crest[0] - 0.5).abs() < 1e-12 && (crest[1] - 0.1).abs() < 1e-12 && (crest[2] - 0.88).abs() < 1e-12);
        let edge = shortcut_undo_crest(0.03, 340.0, 100.0).unwrap();
        assert!(edge[0] + edge[1] > 1.0);
        assert!(shortcut_undo_crest(0.1, 0.0, 100.0).is_none());
    }

    #[test]
    fn shortcut_light_uses_reference_fade_envelope() {
        let duration = 0.62;
        assert_eq!(shortcut_light_fade(0.0, duration), 0.0);
        assert!((shortcut_light_fade(0.03, duration) - 0.5).abs() < 1e-9);
        assert_eq!(shortcut_light_fade(0.10, duration), 1.0);
        assert!((shortcut_light_fade(duration - 0.12, duration) - 0.5).abs() < 1e-9);
        assert_eq!(shortcut_light_fade(duration, duration), 0.0);
    }

    #[test]
    fn case_key_flashes_and_shift_crests_are_bounded() {
        let first = case_key_segments(0, 0.10, 840.0, 220.0).unwrap();
        let expanded = case_key_segments(0, 0.42, 840.0, 220.0).unwrap();
        let second = case_key_segments(0, 0.57, 840.0, 220.0).unwrap();
        let off = case_key_segments(1, 0.15, 840.0, 220.0).unwrap();
        assert!(first[0].end - first[0].start < expanded[0].end - expanded[0].start);
        assert_eq!((expanded[0].start, expanded[0].end), (0.0, 1.0));
        assert!(second[3].opacity > 0.0);
        assert!(off[0].end - off[0].start < 1.0 && off[0].opacity > 0.0);
        assert!((first[1].end - first[1].start - 0.1).abs() < 1e-9);
        assert!(case_key_segments(0, 0.78, 840.0, 220.0).unwrap().is_empty());
        assert!(case_key_segments(1, 0.34, 840.0, 220.0).unwrap().is_empty());
        let shift = case_key_segments(2, 0.35, 840.0, 220.0).unwrap();
        assert_eq!(shift.len(), 3);
        assert!((shift[1].start + shift[2].end - 1.0).abs() < 1e-9);
        assert!((shift[1].end - shift[1].start - 2.0 * 48.4 / 840.0).abs() < 1e-9);
        assert!(case_key_segments(2, 10.0, 840.0, 220.0).unwrap()[0].opacity > 0.0);
        assert!(case_key_segments(3, 0.1, 840.0, 220.0).is_none());
        assert!(case_key_segments(0, 0.1, 0.0, 220.0).is_none());
        assert!(case_key_segments(2, 0.1, 840.0, -1.0).is_none());
    }

    #[test]
    fn case_key_prisms_match_reference_colors_and_reject_unknown_kinds() {
        use super::case_key_prism;
        assert_eq!(case_key_prism(0), Some([[1.0, 0.82, 0.18], [1.0, 0.38, 0.05]]));
        assert_eq!(case_key_prism(1), Some([[0.38, 0.73, 1.0], [0.55, 0.35, 1.0]]));
        assert_eq!(case_key_prism(2), Some([[0.48, 0.85, 1.0], [0.51, 0.43, 1.0]]));
        assert_eq!(case_key_prism(-1), None);
        assert_eq!(case_key_prism(3), None);
    }

    #[test]
    fn music_remaining_clamps_and_rejects_invalid_duration() {
        assert_eq!(music_remaining_fraction(0.0, 100.0), Some(1.0));
        assert_eq!(music_remaining_fraction(25.0, 100.0), Some(0.75));
        assert_eq!(music_remaining_fraction(110.0, 100.0), Some(0.0));
        assert_eq!(music_remaining_fraction(-1.0, 100.0), Some(1.0));
        assert!(music_remaining_fraction(0.0, 0.0).is_none());
        assert!(music_remaining_fraction(f64::NAN, 100.0).is_none());
        assert_eq!(super::music_progress_fraction(0.0, 100.0), Some(0.0));
        assert_eq!(super::music_progress_fraction(25.0, 100.0), Some(0.25));
        assert_eq!(super::music_progress_fraction(110.0, 100.0), Some(1.0));
        assert!(super::music_progress_fraction(0.0, 0.0).is_none());
    }

    #[test]
    fn system_hud_level_and_mute_are_distinct_and_bounded() {
        use super::system_hud_interpolated_level;
        assert_eq!(system_hud_interpolated_level(0.2, 0.8, 0.0), Some(0.2));
        assert!((system_hud_interpolated_level(0.2, 0.8, 0.115).unwrap() - 0.5).abs() < 1e-12);
        assert!((system_hud_interpolated_level(0.8, 0.2, 0.23).unwrap() - 0.2).abs() < 1e-12);
        assert_eq!(system_hud_interpolated_level(-1.0, 2.0, 1.0), Some(1.0));
        assert!(system_hud_interpolated_level(f64::NAN, 1.0, 0.0).is_none());
        let quarter = system_hud_segments(0, 0.25, 0.5).unwrap();
        let full = system_hud_segments(0, 1.0, 0.5).unwrap();
        assert_eq!(quarter.len(), 1);
        assert_eq!((quarter[0].start, quarter[0].end), (0.0, 0.25));
        assert_eq!((full[0].start, full[0].end), (0.0, 1.0));
        assert!((quarter[0].opacity - 0.4625).abs() < 1e-12);
        assert!((full[0].opacity - 0.65).abs() < 1e-12);
        assert_eq!(system_hud_segments(0, 0.25, 0.0).unwrap()[0].opacity, quarter[0].opacity);
        assert_eq!(system_hud_segments(0, 0.25, 1.3).unwrap()[0].opacity, quarter[0].opacity);
        assert_eq!(system_hud_segments(0, -1.0, 0.5).unwrap()[0].end, 0.0);
        assert_eq!(system_hud_segments(0, 2.0, 0.5).unwrap()[0].end, 1.0);
        let muted_early = system_hud_segments(1, 0.0, 0.2).unwrap();
        let muted_late = system_hud_segments(1, 0.0, 0.7).unwrap();
        assert!(muted_early[0].end - muted_early[0].start > muted_late[0].end - muted_late[0].start);
        assert!(system_hud_segments(0, f64::NAN, 0.5).is_none());
        assert_eq!(super::rium_notch_system_hud_seconds(), 1.35);
        assert!(system_hud_segments(0, 0.5, 1.35).unwrap().is_empty());
        let at_limit = super::rium_notch_system_control_at_limit;
        assert_eq!(at_limit(100.0, 1), 1);
        assert_eq!(at_limit(0.0, -1), 1);
        for (percent, direction) in [(100.0, -1), (0.0, 1), (99.9, 1), (0.01, -1), (100.0, 0), (f64::NAN, -1)] {
            assert_eq!(at_limit(percent, direction), 0);
        }
    }

    #[test]
    fn system_hud_pulse_carries_recent_energy_and_fades_the_end_crest() {
        use super::{system_hud_limit_flash, system_hud_pulse_crest, system_hud_pulse_energy};
        assert_eq!(system_hud_pulse_energy(0.0, 0.0), Some(0.48));
        assert!((system_hud_pulse_energy(0.48, 0.3).unwrap() - 0.636).abs() < 1e-12);
        assert_eq!(system_hud_pulse_energy(0.9, 0.6), Some(0.48));
        assert_eq!(system_hud_pulse_energy(1.0, 0.0), Some(1.0));
        let crest = system_hud_pulse_crest(0.5, 0.5, 0.39, 400.0).unwrap();
        assert!((crest[0] - 0.5).abs() < 1e-12 && (crest[1] - 0.08875).abs() < 1e-12);
        assert!((crest[2] - 6.75).abs() < 1e-12 && (crest[3] - 0.25).abs() < 1e-12);
        assert_eq!(system_hud_pulse_crest(0.5, 0.5, 0.78, 400.0).unwrap()[3], 0.0);
        assert!(system_hud_pulse_crest(0.5, 0.5, 0.0, 0.0).is_none());
        assert!(system_hud_pulse_crest(0.5, 0.5, 0.0, f64::MIN_POSITIVE).is_none());
        let limit = 0.48 * (1.0 - 0.25 / 0.78);
        assert!((system_hud_limit_flash(0.0, 0.48, 0.25).unwrap() - limit).abs() < 1e-12);
        assert!((system_hud_limit_flash(1.0, 0.48, 0.25).unwrap() - limit).abs() < 1e-12);
        assert_eq!(system_hud_limit_flash(0.001, 0.48, 0.25), Some(0.0));
        assert_eq!(system_hud_limit_flash(0.999, 0.48, 0.25), Some(0.0));
        assert_eq!(system_hud_limit_flash(1.0, 0.48, 0.5), Some(0.0));
        assert!(system_hud_limit_flash(f64::NAN, 0.48, 0.25).is_none());
    }

    #[test]
    fn unmute_crests_spread_from_the_middle_of_the_restored_level() {
        use super::system_hud_restore_crests;
        let start = system_hud_restore_crests(0.8, 0.48, 0.0, 400.0).unwrap();
        assert_eq!(start, [0.4, 0.4, 0.1, 0.48]);
        let middle = system_hud_restore_crests(0.8, 0.48, 0.21, 400.0).unwrap();
        assert!((middle[0] - 0.2).abs() < 1e-12 && (middle[1] - 0.6).abs() < 1e-12);
        let end = system_hud_restore_crests(0.8, 0.48, 0.42, 400.0).unwrap();
        assert_eq!(end[0], 0.0);
        assert_eq!(end[1], 0.8);
        assert_eq!(system_hud_restore_crests(0.8, 0.48, 0.78, 400.0).unwrap()[3], 0.0);
        assert!(system_hud_restore_crests(0.8, 0.48, 0.0, 0.0).is_none());
        assert!(system_hud_restore_crests(f64::NAN, 0.48, 0.0, 400.0).is_none());
    }

    #[test]
    fn brightness_flare_grows_and_tracks_adjustment_direction() {
        use super::system_hud_brightness_flare;
        let up = system_hud_brightness_flare(1.0, 0.5, 0.0).unwrap();
        let down = system_hud_brightness_flare(-1.0, 0.5, 0.0).unwrap();
        assert_eq!(up, [12.0, 9.0, 0.21]);
        assert_eq!(down, [12.0, 9.0, 0.12]);
        let later = system_hud_brightness_flare(1.0, 0.5, 0.14).unwrap();
        assert!((later[0] - (12.0 + 24.0 * (1.0 - (-1.0_f64).exp()))).abs() < 1e-12);
        assert!(later[1] > 9.0 && later[2] < up[2]);
        assert_eq!(system_hud_brightness_flare(1.0, 0.5, 0.78).unwrap()[2], 0.0);
        assert!(system_hud_brightness_flare(1.0, 0.5, -0.1).is_none());
        assert!(system_hud_brightness_flare(f64::NAN, 0.5, 0.0).is_none());
    }

    #[test]
    fn volume_flare_trails_the_level_and_fades() {
        use super::system_hud_volume_flare;
        let start = system_hud_volume_flare(0.5, 0.5, 0.0).unwrap();
        assert!((start[0] - 0.39).abs() < 1e-12);
        assert_eq!(start[1], 0.5);
        assert!((start[2] - 0.35).abs() < 1e-12);
        let later = system_hud_volume_flare(0.5, 0.5, 0.39).unwrap();
        assert!((later[0] - 0.445).abs() < 1e-12 && (later[2] - 0.175).abs() < 1e-12);
        assert_eq!(system_hud_volume_flare(0.0, 0.5, 0.0).unwrap()[0..2], [0.0, 0.0]);
        assert_eq!(system_hud_volume_flare(0.5, 0.5, 0.78).unwrap()[2], 0.0);
        assert!(system_hud_volume_flare(f64::NAN, 0.5, 0.0).is_none());
        assert!(system_hud_volume_flare(0.5, 0.5, -0.1).is_none());
    }

    #[test]
    fn mute_collapses_the_card_span_and_fades() {
        use super::system_mute_frame;
        assert_eq!(system_mute_frame(0.0, 100.0, 400.0, false), Some([0.25, 0.75, 1.0]));
        let middle = system_mute_frame(0.27, 100.0, 400.0, false).unwrap();
        assert!((middle[0] - 0.375).abs() < 1e-12 && (middle[1] - 0.625).abs() < 1e-12);
        let end = system_mute_frame(0.58, 100.0, 400.0, false).unwrap();
        assert_eq!((end[0], end[1], end[2]), (0.5, 0.5, 0.0));
        let reduced = system_mute_frame(0.1, 100.0, 400.0, true).unwrap();
        assert_eq!((reduced[0], reduced[1]), (0.5, 0.5));
        assert!(system_mute_frame(0.1, 100.0, 0.0, false).is_none());
    }

    #[test]
    fn system_hud_prisms_match_reference_control_colors() {
        use super::system_hud_prism;
        assert_eq!(system_hud_prism(0), Some([[0.10, 0.91, 1.0], [0.22, 0.25, 1.0]]));
        assert_eq!(system_hud_prism(1), Some([[1.0, 0.88, 0.48], [1.0, 0.37, 0.09]]));
        assert_eq!(system_hud_prism(2), Some([[0.37, 0.48, 0.94], [0.40, 0.13, 0.64]]));
        assert_eq!(system_hud_prism(-1), None);
        assert_eq!(system_hud_prism(3), None);
    }
}

#[cfg(test)]
mod lumi_tests {
    use super::{gaze_return_weight, lumi_costume_for_source, lumi_dizzy_eye_point, lumi_effect_frame, lumi_parts_pose, lumi_pixel_badge, lumi_pixel_body_color, lumi_pixel_body_point, lumi_pixel_eye_origin, lumi_pixel_eye_pattern, lumi_pixel_palette, lumi_pixel_sprite, lumi_pixel_sprite_rect, lumi_pointer_gaze, lumi_puff_frame, lumi_reaction_face, lumi_reaction_frame, lumi_reaction_kind, lumi_sparkle_frame, lumi_trail_frame, lumi_zzz_frame};

    #[test]
    fn keyframes_follow_reference_endpoints_and_smooth_interpolation() {
        use super::smooth_keyframes;
        let points = [(0.0, 2.0), (1.0, 6.0), (2.0, -2.0)];
        assert_eq!(smooth_keyframes(0.0, &[]), 0.0);
        assert_eq!(smooth_keyframes(-1.0, &[(0.0, 4.0)]), 4.0);
        assert_eq!(smooth_keyframes(-1.0, &points), 2.0);
        assert_eq!(smooth_keyframes(0.5, &points), 4.0);
        assert_eq!(smooth_keyframes(1.0, &points), 6.0);
        assert_eq!(smooth_keyframes(3.0, &points), -2.0);
        assert!(smooth_keyframes(0.0, &[(0.0, 1.0), (0.0, 2.0)]).is_finite());
    }

    #[test]
    fn troupe_dance_uses_indexed_reference_lift() {
        use super::lumi_dance_lift;
        assert_eq!(lumi_dance_lift(0.0, 0, false), Some(0.0));
        assert!((lumi_dance_lift(0.31, 0, false).unwrap() + 10.0).abs() < 1e-9);
        assert!(lumi_dance_lift(0.62, 0, false).unwrap().abs() < 1e-9);
        assert!((lumi_dance_lift(0.0, 1, false).unwrap() + 10.0 * 0.95_f64.sin()).abs() < 1e-9);
        assert_eq!(lumi_dance_lift(0.31, 0, true), Some(0.0));
        assert!(lumi_dance_lift(f64::NAN, 0, false).is_none());
        assert!(lumi_dance_lift(0.0, -1, false).is_none());
    }

    #[test]
    fn idle_pose_keeps_neutral_gaze_and_tilt_while_lifting() {
        use super::character_pose;
        let rising = character_pose(0, 1.0, 3.0, false).unwrap();
        let resting = character_pose(0, 3.0, 3.0, false).unwrap();
        assert_eq!(&rising[1..5], &[0.0, 0.0, 0.0, 0.0]);
        assert!((rising[5] + 7.0).abs() < 1e-9);
        assert!(resting[5].abs() < 1e-9);
        assert_eq!(lumi_parts_pose(0, 1.0, 3.0, false).unwrap()[0], 0.0);
        assert!((character_pose(0, 0.07, 3.0, false).unwrap()[0] - 0.08).abs() < 1e-9);
    }

    #[test]
    fn working_pose_uses_reference_sway_and_body_tilt() {
        use super::character_pose;
        let pose = character_pose(1, 0.325, 2.0, false).unwrap();
        assert!((pose[3] + 3.0).abs() < 1e-9);
        assert!((pose[4] - 1.0).abs() < 1e-9);
        assert!((pose[5] + 5.0).abs() < 1e-9);
        assert_eq!(pose[2], 0.0);
        assert_eq!(lumi_parts_pose(1, 0.325, 2.0, false).unwrap()[0], 0.0);
    }

    #[test]
    fn waiting_poses_follow_reference_lift_and_gaze() {
        use super::character_pose;
        let approval = character_pose(2, 0.36, 2.0, false).unwrap();
        assert_eq!(&approval[1..5], &[0.0, 0.0, 0.0, 0.0]);
        assert!((approval[5] + 12.0).abs() < 1e-9);
        assert_eq!(lumi_parts_pose(2, 0.36, 2.0, false).unwrap()[0], 0.0);
        let question = character_pose(3, 0.6, 2.0, false).unwrap();
        assert_eq!(question[1], -0.5);
        assert!((question[2] + 2.0 / 2.4).abs() < 1e-9);
        assert_eq!((question[3], question[4]), (0.0, 0.0));
        assert!((question[5] + 6.0).abs() < 1e-9);
    }

    #[test]
    fn failed_pose_moves_wings_and_antenna_in_distinct_directions() {
        use super::{character_pose, lumi_antenna_angle};
        let pose = character_pose(5, 0.0, 0.45, false).unwrap();
        assert!((pose[3] - 2.0).abs() < 1e-9);
        assert!((pose[5] - 3.5).abs() < 1e-9);
        let parts = lumi_parts_pose(5, 0.0, 0.45, false).unwrap();
        assert_eq!(parts, [0.0, -6.0, -2.5]);
        assert_eq!(lumi_antenna_angle(5, 0.0, 0.45, false), Some(8.0));
        assert_eq!(character_pose(5, 0.0, 0.8, false).unwrap()[4], 0.0);
        assert_eq!(character_pose(5, 0.07, 0.45, false).unwrap()[0], 1.0);
        assert_eq!(character_pose(5, 5.07, 3.0, false).unwrap()[0], 1.0);
    }

    #[test]
    fn interrupted_and_stalled_poses_match_reference_state() {
        use super::{character_pose, lumi_stalled_squash};
        let interrupted = character_pose(7, 0.0, 0.6, false).unwrap();
        assert_eq!(&interrupted[1..5], &[0.0, 0.0, 0.0, 0.0]);
        assert!((interrupted[5] - 5.0).abs() < 1e-9);
        assert_eq!(lumi_parts_pose(7, 0.0, 0.6, false), Some([0.0, -7.0, -3.0]));
        assert_eq!(lumi_parts_pose(8, 0.0, 2.0, false), Some([0.0; 3]));
        assert!((character_pose(8, 0.0, 2.0, false).unwrap()[5] - 4.0).abs() < 1e-9);
        let high = lumi_stalled_squash(0.95, false).unwrap();
        assert!((high[0] - 1.025).abs() < 1e-9 && (high[1] - 1.04).abs() < 1e-9);
        assert_eq!(lumi_stalled_squash(1.0, true), Some([1.0; 2]));
        assert!(lumi_stalled_squash(f64::NAN, false).is_none());
    }

    #[test]
    fn retry_pose_uses_reference_lift_and_fixed_gaze() {
        use super::character_pose;
        let pose = character_pose(6, 0.55, 2.0, false).unwrap();
        assert!((pose[1] + 2.0 / 3.0).abs() < 1e-9);
        assert!((pose[2] + 2.0 / 2.4).abs() < 1e-9);
        assert_eq!((pose[3], pose[4]), (0.0, 0.0));
        assert!((pose[5] + 7.0).abs() < 1e-9);
        assert_eq!(lumi_parts_pose(6, 0.55, 2.0, false).unwrap()[0], 0.0);
    }

    #[test]
    fn completed_pose_uses_jump_then_settled_lift() {
        use super::character_pose;
        let jumping = character_pose(4, 0.0, 2.6 * 0.22, false).unwrap();
        assert!((jumping[5] + 20.0).abs() < 1e-9);
        assert_eq!(&jumping[1..5], &[0.0, 0.0, 0.0, 0.0]);
        let settled = character_pose(4, 1.125, 8.0, false).unwrap();
        assert!((settled[5] + 4.0).abs() < 1e-9);
        assert_eq!(settled[6], 1.0);
    }

    #[test]
    fn idle_lamp_uses_observed_cycle_and_static_reduced_motion_level() {
        use super::lumi_idle_lamp;
        assert!((lumi_idle_lamp(0.0, false).unwrap() - 0.62).abs() < 1e-9);
        assert!((lumi_idle_lamp(0.8, false).unwrap() - 0.80).abs() < 1e-9);
        assert!((lumi_idle_lamp(2.4, false).unwrap() - 0.44).abs() < 1e-9);
        assert!((lumi_idle_lamp(3.2, false).unwrap() - 0.62).abs() < 1e-9);
        assert_eq!(lumi_idle_lamp(0.8, true), Some(0.62));
        assert_eq!(lumi_idle_lamp(f64::NAN, false), None);
    }

    #[test]
    fn antenna_angle_follows_mood_and_respects_reduced_motion() {
        use super::lumi_antenna_angle;
        assert!((lumi_antenna_angle(0, 0.75, 0.0, false).unwrap() - 4.0).abs() < 1e-9);
        assert!((lumi_antenna_angle(1, 0.325, 0.0, false).unwrap() - 3.0).abs() < 1e-9);
        assert!((lumi_antenna_angle(2, 0.1125, 0.0, false).unwrap() - 9.0).abs() < 1e-9);
        assert_eq!(lumi_antenna_angle(3, 0.5, 0.0, false), Some(0.0));
        assert_eq!(lumi_antenna_angle(5, 0.0, 0.45, false), Some(8.0));
        assert_eq!(lumi_antenna_angle(7, 0.0, 0.6, false), Some(5.0));
        assert_eq!(lumi_antenna_angle(2, 0.1125, 0.0, true), Some(0.0));
        assert!(lumi_antenna_angle(1, f64::NAN, 0.0, false).is_none());
    }

    #[test]
    fn state_lamps_preserve_their_independent_reference_periods() {
        use super::lumi_state_lamp;
        for (mood, base, amplitude, period) in [(1, 0.62, 0.20, 1.1), (3, 0.60, 0.20, 1.8),
                                                 (6, 0.60, 0.20, 2.2), (8, 0.40, 0.12, 3.8)] {
            assert!((lumi_state_lamp(mood, period / 4.0, 0.0, false).unwrap() - base - amplitude).abs() < 1e-9);
            assert!((lumi_state_lamp(mood, period, 0.0, false).unwrap() - base).abs() < 1e-9);
            assert_eq!(lumi_state_lamp(mood, period / 4.0, 0.0, true), Some(base));
        }
        assert!((lumi_state_lamp(2, 0.072, 0.0, false).unwrap() - 1.0).abs() < 1e-9);
        assert!((lumi_state_lamp(2, 0.384, 0.0, false).unwrap() - 1.0).abs() < 1e-9);
        assert!(lumi_state_lamp(2, 0.72, 0.0, false).unwrap() < 0.301);
        assert_eq!(lumi_state_lamp(2, 0.2, 0.0, true), Some(0.65));
        assert!((lumi_state_lamp(7, 0.0, 0.8, false).unwrap() - 0.38).abs() < 1e-9);
        assert!((lumi_state_lamp(7, 0.0, 3.0, false).unwrap() - 0.06).abs() < 1e-9);
        assert!((lumi_state_lamp(4, 0.0, 0.24 * 2.6, false).unwrap() - 1.0).abs() < 1e-9);
        assert!((lumi_state_lamp(4, 1.0, 7.8, false).unwrap() - 0.65).abs() < 1e-9);
        assert!((lumi_state_lamp(5, 0.0, 0.6, false).unwrap() - 0.2).abs() < 1e-9);
        assert!((lumi_state_lamp(5, 0.0, 3.0, false).unwrap() - 0.32).abs() < 1e-9);
        assert_eq!(lumi_state_lamp(9, 0.0, 0.0, false), None);
        assert_eq!(lumi_state_lamp(1, f64::NAN, 0.0, false), None);
    }

    #[test]
    fn pointer_gaze_returns_smoothly_and_respects_reduced_motion() {
        assert_eq!(gaze_return_weight(0.0, false), Some(1.0));
        assert!((gaze_return_weight(0.175, false).unwrap() - 0.5).abs() < 1e-9);
        assert_eq!(gaze_return_weight(0.35, false), Some(0.0));
        assert_eq!(gaze_return_weight(0.0, true), Some(0.0));
        assert_eq!(gaze_return_weight(f64::NAN, false), None);
    }

    #[test]
    fn reaction_faces_expire_and_dizzy_spiral_is_bounded() {
        assert_eq!(super::lumi_reaction_duration(5), Some(1.4));
        assert_eq!(super::lumi_reaction_duration(9), Some(2.2));
        assert_eq!(super::lumi_reaction_duration(-1), None);
        assert_eq!(lumi_reaction_face(0, 0.3, false), Some(6));
        assert_eq!(lumi_reaction_face(1, 0.3, false), Some(7));
        assert_eq!(lumi_reaction_face(3, 0.3, false), Some(9));
        assert_eq!(lumi_reaction_face(5, 0.3, false), Some(10));
        assert_eq!(lumi_reaction_face(8, 0.3, false), Some(11));
        assert_eq!(lumi_reaction_face(8, 1.1, false), Some(-1));
        assert_eq!(lumi_reaction_face(9, 1.1, false), Some(12));
        assert_eq!(lumi_reaction_face(9, 1.1, true), Some(-1));
        let start = lumi_dizzy_eye_point(0.0, 0).unwrap();
        assert!((start[0] - 1.0).abs() < 1e-9 && start[1].abs() < 1e-9);
        let end = lumi_dizzy_eye_point(0.0, 28).unwrap();
        assert!((end[0].hypot(end[1]) - 6.2).abs() < 1e-9);
        assert!(lumi_dizzy_eye_point(f64::NAN, 0).is_none());
    }

    #[test]
    fn rium_expression_tracks_mood_and_active_reaction() {
        use super::rium_character_expression;
        assert_eq!(rium_character_expression(1, -1), Some(0));
        assert_eq!(rium_character_expression(4, -1), Some(2));
        assert_eq!(rium_character_expression(5, -1), Some(3));
        assert_eq!(rium_character_expression(8, -1), Some(5));
        assert_eq!(rium_character_expression(4, 11), Some(11));
        assert_eq!(rium_character_expression(5, 12), Some(12));
        assert_eq!(rium_character_expression(9, -1), None);
        assert_eq!(rium_character_expression(1, 13), None);
    }

    #[test]
    fn rium_idle_glance_pauses_and_returns_to_center() {
        use super::rium_idle_gaze;
        assert_eq!(rium_idle_gaze(0.0, false), Some(0.0));
        assert_eq!(rium_idle_gaze(2.7, false), Some(-0.65));
        assert_eq!(rium_idle_gaze(6.3, false), Some(0.65));
        assert_eq!(rium_idle_gaze(9.0, false), Some(0.0));
        assert_eq!(rium_idle_gaze(2.7, true), Some(0.0));
        assert_eq!(rium_idle_gaze(f64::NAN, false), None);
    }

    #[test]
    fn working_trail_fades_and_repeats_with_staggered_dots() {
        let first = lumi_trail_frame(0.165, 0).unwrap();
        for (actual, expected) in first.iter().zip([70.9, 151.5, 3.0, 0.9]) {
            assert!((actual - expected).abs() < 1e-9);
        }
        let repeated = lumi_trail_frame(1.265, 0).unwrap();
        for (actual, expected) in repeated.iter().zip(first) { assert!((actual - expected).abs() < 1e-9); }
        assert_eq!(lumi_trail_frame(0.0, 0).unwrap()[3], 0.0);
        assert!(lumi_trail_frame(0.0, 1).unwrap()[3] > 0.0);
        assert!(lumi_trail_frame(f64::NAN, 0).is_none());
        assert!(lumi_trail_frame(0.0, 3).is_none());
    }

    #[test]
    fn large_status_effects_follow_mood_and_reduce_motion() {
        assert_eq!(lumi_effect_frame(1, 0.7, 1.0, false), Some([0.0, 0.0]));
        assert_eq!(lumi_effect_frame(4, 1.3, 1.0, false), Some([0.5, 1.0]));
        assert_eq!(lumi_effect_frame(4, 7.79, 1.0, false).unwrap()[1], 1.0);
        assert_eq!(lumi_effect_frame(4, 7.8, 1.0, false), Some([0.0, 0.0]));
        assert_eq!(lumi_effect_frame(5, 2.39, 1.0, false).unwrap()[1], 1.0);
        assert_eq!(lumi_effect_frame(5, 2.4, 1.0, false), Some([0.0, 0.0]));
        assert_eq!(lumi_effect_frame(4, 7.8, 1.0, true), Some([0.0, 0.0]));
        assert_eq!(lumi_effect_frame(8, 1.0, 1.0, true), Some([0.3, 1.0]));
        assert!(lumi_effect_frame(5, f64::NAN, 1.0, false).is_none());
    }

    #[test]
    fn stalled_glyphs_repeat_at_staggered_phases() {
        let first = lumi_zzz_frame(0.2, 0).unwrap();
        for (actual, expected) in first.iter().zip([172.8, 30.0, 9.23, 1.0]) {
            assert!((actual - expected).abs() < 1e-9);
        }
        assert_eq!(lumi_zzz_frame(0.0, 0).unwrap()[3], 0.0);
        assert!(lumi_zzz_frame(0.2, 1).unwrap()[1] < first[1]);
        assert!(lumi_zzz_frame(f64::INFINITY, 0).is_none());
    }

    #[test]
    fn completion_sparkles_stagger_and_follow_observed_keyframes() {
        assert_eq!(lumi_sparkle_frame(0.3, 0), Some([1.15, 24.0]));
        assert_eq!(lumi_sparkle_frame(0.1, 3), Some([0.0, 0.0]));
        assert_eq!(lumi_sparkle_frame(0.9, 0), Some([0.0, 72.0]));
        assert!(lumi_sparkle_frame(f64::NAN, 0).is_none());
    }

    #[test]
    fn failure_puffs_are_delayed_staggered_and_fade() {
        assert_eq!(lumi_puff_frame(0.8, 0), Some([0.0; 4]));
        let first = lumi_puff_frame(1.5, 0).unwrap();
        for (actual, expected) in first.iter().zip([142.0, 137.0, 4.5, 0.25]) {
            assert!((actual - expected).abs() < 1e-9);
        }
        assert_eq!(lumi_puff_frame(2.2, 0), Some([0.0; 4]));
        assert!(lumi_puff_frame(f64::NAN, 0).is_none());
    }

    #[test]
    fn reaction_selection_and_duration_are_bounded() {
        assert_eq!(lumi_reaction_kind(0, 1), Some(0));
        assert_eq!(lumi_reaction_kind(2, 2), Some(2));
        assert_eq!(lumi_reaction_kind(2, 3), Some(8));
        assert_eq!(lumi_reaction_kind(2, 6), Some(9));
        assert_eq!(lumi_reaction_kind(9, 1), None);
        assert_eq!(lumi_reaction_frame(9, 2.2, false), Some([1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 1.0, -1.0]));
        assert_eq!(lumi_reaction_frame(4, 0.5, true), Some([1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 1.0, -1.0]));
        assert!((lumi_reaction_frame(1, 0.15, false).unwrap()[3] + 4.9).abs() < 1e-9);
        assert!((lumi_reaction_frame(2, 0.18, false).unwrap()[5] + 16.0).abs() < 1e-9);
        assert!((lumi_reaction_frame(9, 1.1, false).unwrap()[8] + 1.0).abs() < 1e-9);
        assert!((lumi_reaction_frame(6, 0.24, false).unwrap()[9] - 0.9).abs() < 1e-9);
    }

    #[test]
    fn pixel_eye_patterns_follow_face_and_blink_thresholds() {
        assert_eq!(lumi_pixel_eye_pattern(0, 0.449, 1.0, false), Some([2, 1, 3, 0, 0]));
        assert_eq!(lumi_pixel_eye_pattern(0, 0.45, 1.1, false), Some([1, 2, 1, 1, 0]));
        assert_eq!(lumi_pixel_eye_pattern(0, 1.0, 1.101, false), Some([2, 2, 3, 3, 0]));
        assert_eq!(lumi_pixel_eye_pattern(2, 1.0, 1.0, false), Some([3, 2, 2, 5, 0]));
        assert_eq!(lumi_pixel_eye_pattern(9, 1.0, 1.0, true), Some([2, 1, 3, 0, 0]));
        assert_eq!(lumi_pixel_eye_pattern(9, 1.0, 1.0, false), Some([1, 2, 1, 1, 0]));
        assert_eq!(lumi_pixel_eye_pattern(11, 1.0, 1.0, false), Some([3, 3, 6, 5, 3]));
        assert_eq!(lumi_pixel_eye_pattern(12, 1.0, 1.0, false), Some([0; 5]));
        assert!(lumi_pixel_eye_pattern(13, 1.0, 1.0, false).is_none());
        assert!(lumi_pixel_eye_pattern(0, f64::NAN, 1.0, false).is_none());
    }

    #[test]
    fn pixel_eye_centers_align_after_head_rotation() {
        assert_eq!(lumi_pixel_eye_origin(0, 1.0, 1.0, false, 0.0, 0.0, 0.0, [0.0, 1.0, 1.0]), Some([8, 6]));
        assert_eq!(lumi_pixel_eye_origin(0, 1.0, 1.0, true, 0.0, 0.0, 0.0, [0.0, 1.0, 1.0]), Some([11, 6]));
        assert_eq!(lumi_pixel_eye_origin(5, 1.0, 1.0, false, 0.0, 0.0, 0.0, [0.0, 1.0, 1.0]), Some([7, 8]));
        assert_ne!(lumi_pixel_eye_origin(0, 1.0, 1.0, false, 0.0, 0.0, 0.0, [0.0, 1.0, 1.0]),
                   lumi_pixel_eye_origin(0, 1.0, 1.0, false, 0.0, 0.0, 45.0, [0.0, 1.0, 1.0]));
        assert!(lumi_pixel_eye_origin(0, 1.0, 1.0, false, 0.0, 0.0, f64::NAN, [0.0, 1.0, 1.0]).is_none());
        assert_eq!(lumi_pixel_body_point(110.0, 155.0, [0.0, 2.0, 0.5]), [120.0, 160.0]);
        let rotated = lumi_pixel_body_point(110.0, 130.0, [90.0, 1.0, 1.0]);
        assert!((rotated[0] - 100.0).abs() < 1e-9 && (rotated[1] - 140.0).abs() < 1e-9);
        assert_ne!(lumi_pixel_eye_origin(0, 1.0, 1.0, false, 0.0, 0.0, 0.0, [0.0, 1.0, 1.0]),
                   lumi_pixel_eye_origin(0, 1.0, 1.0, false, 0.0, 0.0, 0.0, [20.0, 1.1, 0.9]));
        assert!(lumi_pixel_eye_origin(0, 1.0, 1.0, false, 0.0, 0.0, 0.0, [0.0, f64::NAN, 1.0]).is_none());
    }

    #[test]
    fn pixel_sprite_has_bounded_cells_and_stateful_eyes() {
        let open = lumi_pixel_sprite(1, 0, 0, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 0.0, 0.0, false, false, false, [0.0, 1.0, 1.0]).unwrap();
        let closed = lumi_pixel_sprite(1, 0, 0, 0.1, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 0.0, 0.0, false, false, false, [0.0, 1.0, 1.0]).unwrap();
        let wide = lumi_pixel_sprite(1, 0, 0, 1.0, 1.18, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 0.0, 0.0, false, false, false, [0.0, 1.0, 1.0]).unwrap();
        assert_eq!(open.len(), 18 * 18 * 4);
        assert_eq!(&open[(6 * 18 + 8) * 4..(6 * 18 + 8) * 4 + 4], &[242, 250, 255, 255]);
        assert_eq!(&open[(16 * 18 + 14) * 4..(16 * 18 + 14) * 4 + 4], &[0, 0, 0, 0]);
        assert_ne!(open, closed);
        assert_ne!(open, wide);
        assert!(open.chunks_exact(4).any(|pixel| pixel[3] == 0));
        let tilted = lumi_pixel_sprite(1, 0, 0, 1.0, 1.0, 0.0, 0.0, 20.0, 0.0, 0.0, 0.0, 0.5, 0.0, 0.0, false, false, false, [0.0, 1.0, 1.0]).unwrap();
        assert_ne!(open, tilted);
        let body_tilted = lumi_pixel_sprite(1, 0, 0, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 0.0, 0.0, false, false, false, [20.0, 1.1, 0.9]).unwrap();
        assert_ne!(open, body_tilted);
        let body_flipped = lumi_pixel_sprite(1, 0, 0, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 0.0, 0.0, false, false, false, [0.0, -1.0, 1.0]).unwrap();
        assert_ne!(open, body_flipped);
        assert!(lumi_pixel_sprite(1, 0, 0, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 0.0, 0.0, false, false, false, [0.0, 0.0, 1.0]).is_some());
        let wing_raised = lumi_pixel_sprite(1, 0, 0, 1.0, 1.0, 0.0, 0.0, 0.0, 45.0, 0.0, 0.0, 0.5, 0.0, 0.0, false, false, false, [0.0, 1.0, 1.0]).unwrap();
        assert_ne!(open, wing_raised);
        let antenna_turned = lumi_pixel_sprite(1, 0, 0, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 45.0, 0.5, 0.0, 0.0, false, false, false, [0.0, 1.0, 1.0]).unwrap();
        assert_ne!(open, antenna_turned);
        let clockwise = lumi_pixel_sprite(1, 0, 0, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 90.0, 0.5, 0.0, 0.0, false, false, false, [0.0, 1.0, 1.0]).unwrap();
        let counterclockwise = lumi_pixel_sprite(1, 0, 0, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, -90.0, 0.5, 0.0, 0.0, false, false, false, [0.0, 1.0, 1.0]).unwrap();
        let antenna_tip_alpha = (7 * 18 + 16) * 4 + 3;
        assert_eq!(clockwise[antenna_tip_alpha], 255);
        assert_eq!(counterclockwise[antenna_tip_alpha], 0);
        assert!(lumi_pixel_sprite(9, 0, 0, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 0.0, 0.0, false, false, false, [0.0, 1.0, 1.0]).is_none());
        assert!(lumi_pixel_sprite(1, 0, 0, f64::NAN, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 0.0, 0.0, false, false, false, [0.0, 1.0, 1.0]).is_none());
        assert!(lumi_pixel_sprite(1, 0, 0, 1.0, -1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 0.0, 0.0, false, false, false, [0.0, 1.0, 1.0]).is_none());
    }

    #[test]
    fn pixel_completion_sparkles_follow_reference_grid_and_visibility() {
        let frame = |clock, small, effect| lumi_pixel_sprite(4, 0, 2, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 123.0, clock, false, small, effect, [0.0, 1.0, 1.0]).unwrap();
        let star = (6 * 18 + 3) * 4;
        assert_eq!(&frame(0.0, false, true)[star..star + 4], &[255, 255, 255, 255]);
        assert_eq!(&frame(0.8, false, true)[star..star + 4], &[0, 0, 0, 0]);
        assert_eq!(frame(0.0, true, true), frame(0.0, true, false));
        assert_ne!(frame(0.0, false, true), frame(0.0, false, false));
        let different_clock = lumi_pixel_sprite(4, 0, 2, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 456.0, 0.0, false, false, true, [0.0, 1.0, 1.0]).unwrap();
        assert_eq!(frame(0.0, false, true), different_clock);
    }

    #[test]
    fn pixel_running_trail_follows_clock_and_is_hidden_when_small() {
        let frame = |clock, small| lumi_pixel_sprite(1, 0, 0, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, clock, 0.0, false, small, false, [0.0, 1.0, 1.0]).unwrap();
        let first = (15 * 18 + 6) * 4;
        let third = (15 * 18 + 3) * 4;
        assert_eq!(&frame(0.0, false)[first..first + 4], &[76, 173, 255, 255]);
        assert_eq!(&frame(0.0, true)[first..first + 4], &[0, 0, 0, 0]);
        assert_eq!(&frame(0.1, false)[third..third + 4], &[76, 173, 255, 102]);
        assert_ne!(frame(0.0, false), frame(0.1, false));
    }

    #[test]
    fn pixel_failure_and_stalled_effects_follow_their_own_clocks() {
        let frame = |mood, clock, age, small, effect| lumi_pixel_sprite(mood, 0, 0, 1.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, clock, age, false, small, effect, [0.0, 1.0, 1.0]).unwrap();
        let failure = (15 * 18 + 14) * 4;
        let stalled = (6 * 18 + 15) * 4;
        assert_eq!(&frame(5, 12.0, 0.0, false, true)[failure..failure + 4], &[150, 153, 161, 255]);
        assert_eq!(&frame(8, 0.0, 7.0, false, true)[stalled..stalled + 4], &[237, 227, 191, 255]);
        assert_ne!(frame(5, 12.0, 0.0, false, true), frame(5, 12.0, 1.0, false, true));
        assert_ne!(frame(8, 0.0, 7.0, false, true), frame(8, 1.0, 7.0, false, true));
        assert_eq!(frame(5, 12.0, 0.0, true, true), frame(5, 12.0, 0.0, true, false));
        assert_eq!(frame(8, 0.0, 7.0, false, false), frame(8, 1.0, 7.0, false, false));
    }

    #[test]
    fn pixel_badge_uses_reference_glyphs_and_animated_bars() {
        assert_eq!(lumi_pixel_badge(2, 0.0, true), Some([3, 3, 2, 2, 0, 0, 0]));
        assert_eq!(lumi_pixel_badge(4, 0.0, false), Some([5, 5, 0, 1, 2, 20, 8]));
        assert_eq!(lumi_pixel_badge(6, 0.0, false), Some([5, 5, 22, 25, 29, 1, 14]));
        assert_eq!(lumi_pixel_badge(0, 0.0, false), Some([0; 7]));
        assert_ne!(lumi_pixel_badge(1, 0.0, true), lumi_pixel_badge(1, 0.25, true));
        assert!(lumi_pixel_badge(1, f64::NAN, true).is_none());
    }

    #[test]
    fn pixel_palette_follows_reference_mood_groups() {
        assert_eq!(lumi_pixel_palette(1, 0).unwrap()[0], [23, 69, 240, 255]);
        assert_eq!(lumi_pixel_palette(7, 0).unwrap()[4], [79, 84, 74, 255]);
        assert_eq!(lumi_pixel_palette(8, 0).unwrap()[0], [28, 59, 168, 255]);
        assert_eq!(lumi_pixel_palette(0, 0), lumi_pixel_palette(6, 0));
        assert_eq!(lumi_pixel_palette(1, 1).unwrap()[5], [232, 138, 107, 255]);
        assert_eq!(lumi_pixel_palette(1, 2).unwrap()[7], [18, 18, 23, 255]);
        assert_eq!(lumi_pixel_palette(8, 2).unwrap()[5], [245, 245, 247, 255]);
        assert!(lumi_pixel_palette(1, 4).is_none());
        assert!(lumi_pixel_palette(9, 0).is_none());
    }

    #[test]
    fn lumi_costume_uses_provider_aliases_and_unknown_fallback() {
        for source in ["claude", "claude-code", "claude-chat"] { assert_eq!(lumi_costume_for_source(source), 1); }
        for source in ["codex", "chatgpt"] { assert_eq!(lumi_costume_for_source(source), 2); }
        assert_eq!(lumi_costume_for_source("cursor"), 3);
        assert_eq!(lumi_costume_for_source(""), 0);
        assert_eq!(lumi_costume_for_source("other"), 0);
    }

    #[test]
    fn pixel_sprite_rect_respects_reference_viewports_and_device_pixels() {
        assert_eq!(lumi_pixel_sprite_rect(200.0, 200.0, false, 2.0), Some([5.0, 1.0, 9.5]));
        let small = lumi_pixel_sprite_rect(19.0, 18.0, false, 2.0).unwrap();
        assert_eq!(small, [-2.0, -1.5, 1.0]);
        let badge = lumi_pixel_sprite_rect(19.0, 18.0, true, 2.0).unwrap();
        assert_ne!(small, badge);
        for value in badge { assert_eq!((value * 2.0).fract(), 0.0); }
        assert!(lumi_pixel_sprite_rect(0.0, 18.0, false, 2.0).is_none());
        assert!(lumi_pixel_sprite_rect(19.0, 18.0, false, f64::NAN).is_none());
    }

    #[test]
    fn pixel_body_uses_reference_color_bands_and_lamp_strength() {
        let base = [20, 40, 60, 255];
        let tint = [100, 120, 140];
        let core = [220, 200, 180];
        assert_eq!(lumi_pixel_body_color(base, tint, core, 0.16, 1.0), [220, 200, 180, 255]);
        assert_eq!(lumi_pixel_body_color(base, tint, core, 0.18, 1.0), [100, 120, 140, 255]);
        assert_eq!(lumi_pixel_body_color(base, tint, core, 0.35, 0.0), [52, 72, 92, 255]);
        assert_eq!(lumi_pixel_body_color(base, tint, core, 0.57, 1.0), base);
        assert_eq!(lumi_pixel_body_color(base, tint, core, 0.16, -1.0), [70, 80, 90, 255]);
    }

    #[test]
    fn sigh_returns_continuously_to_its_resting_pose() {
        let before = lumi_reaction_frame(5, 1.4 - 1e-6, false).unwrap();
        let boundary = lumi_reaction_frame(5, 1.4, false).unwrap();
        assert!((before[3] - boundary[3]).abs() < 1e-6);
        assert!((before[5] - boundary[5]).abs() < 1e-6);
        let middle = lumi_reaction_frame(5, 1.5, false).unwrap();
        assert!((middle[3] - 1.5).abs() < 1e-9);
        assert!((middle[5] - 1.0).abs() < 1e-9);
        let end = lumi_reaction_frame(5, 1.6, false).unwrap();
        assert_eq!(end[3], 0.0);
        assert_eq!(end[5], 0.0);
        assert_eq!(lumi_reaction_frame(5, 1.4, true).unwrap()[3], 0.0);
    }

    #[test]
    fn pointer_gaze_is_centered_and_clamped() {
        assert_eq!(lumi_pointer_gaze(9.5, 9.0, 19.0, 18.0), Some([0.0, 0.0]));
        assert_eq!(lumi_pointer_gaze(0.0, 18.0, 19.0, 18.0), Some([-1.0, 1.0]));
        assert_eq!(lumi_pointer_gaze(50.0, -5.0, 19.0, 18.0), Some([1.0, -1.0]));
        assert_eq!(lumi_pointer_gaze(0.0, 0.0, 0.0, 18.0), None);
        assert_eq!(lumi_pointer_gaze(f64::NAN, 0.0, 19.0, 18.0), None);
    }

    #[test]
    fn permission_wings_follow_the_same_observed_cycle() {
        let high = lumi_parts_pose(2, 0.08, 1.0, false).unwrap();
        let low = lumi_parts_pose(2, 0.24, 1.0, false).unwrap();
        assert!((high[1] - 20.0).abs() < 1e-9 && (high[2] - 9.0).abs() < 1e-9);
        assert!((low[1] + 2.0).abs() < 1e-9 && low[2].abs() < 1e-9);
        assert_eq!(lumi_parts_pose(2, 0.08, 1.0, true), Some([0.0; 3]));
    }

    #[test]
    fn question_retry_and_done_keep_their_distinct_wing_cycles() {
        let question = lumi_parts_pose(3, 0.225, 1.0, false).unwrap();
        assert!((question[1] - 18.0).abs() < 1e-9 && (question[2] - 8.0).abs() < 1e-9);
        let retry = lumi_parts_pose(6, 0.6, 1.0, false).unwrap();
        assert!((retry[1] + 2.0).abs() < 1e-9 && retry[2].abs() < 1e-9);
        let done = lumi_parts_pose(4, 0.035, 1.0, false).unwrap();
        assert!((done[1] - 20.0).abs() < 1e-9 && (done[2] - 9.0).abs() < 1e-9);
        let settled = lumi_parts_pose(4, 0.45, 8.0, false).unwrap();
        assert!((settled[1] - 12.0).abs() < 1e-9 && (settled[2] - 6.0).abs() < 1e-9);
    }
}

/// Returns 0 on success, -1 for invalid values or output pointers.
#[no_mangle]
pub unsafe extern "C" fn rium_notch_spring_sample(start: f64, initial_velocity: f64, target: f64,
    elapsed: f64, response: f64, damping: f64, position: *mut f64, velocity: *mut f64) -> i32 {
    if position.is_null() || velocity.is_null() || position == velocity { return -1; }
    let Some(sample) = spring_sample(start, initial_velocity, target, elapsed, response, damping) else { return -1; };
    *position = sample.position;
    *velocity = sample.velocity;
    0
}

/// Each output record consists of four doubles: start, end, opacity, highlight
/// (0 or 1). `capacity` counts records. A null output with capacity 0 queries
/// the required number; -1 means invalid input and -2 insufficient capacity.
#[no_mangle]
pub unsafe extern "C" fn rium_notch_arrival_segments(kind: i32, elapsed: f64, path_length: f64,
    arm: f64, notch_width: f64, height: f64, shoulder_arc_length: f64, output: *mut f64, capacity: i32) -> i32 {
    write_arrival_segments(arrival_segments(kind, elapsed, path_length, arm, notch_width, height, shoulder_arc_length), output, capacity)
}

/// Uses the measured lower straight span and shoulder distance of a floating contour.
#[no_mangle]
pub unsafe extern "C" fn rium_notch_agenda_arrival_segments(kind: i32, elapsed: f64, path_length: f64,
    bottom_half_span: f64, shoulder_distance: f64, output: *mut f64, capacity: i32) -> i32 {
    write_arrival_segments(agenda_arrival_segments(kind, elapsed, path_length, bottom_half_span, shoulder_distance), output, capacity)
}

unsafe fn write_arrival_segments(segments: Option<Vec<LightSegment>>, output: *mut f64, capacity: i32) -> i32 {
    if capacity < 0 || (output.is_null() && capacity != 0) { return -1; }
    let Some(segments) = segments else { return -1; };
    if segments.iter().any(|item| !item.start.is_finite() || !item.end.is_finite() || !item.opacity.is_finite()) { return -1; }
    let count = segments.len() as i32;
    if output.is_null() && capacity == 0 { return count; }
    if capacity < count { return -2; }
    for (index, item) in segments.iter().enumerate() {
        let base = output.add(index * 4);
        *base = item.start;
        *base.add(1) = item.end;
        *base.add(2) = item.opacity;
        *base.add(3) = if item.highlight { 1.0 } else { 0.0 };
    }
    count
}

/// Writes a repeating 0...1 music ripple phase to the caller's pointer.
#[no_mangle]
pub unsafe extern "C" fn rium_notch_music_ripple_phase(time: f64, offset: f64, output: *mut f64) -> i32 {
    if output.is_null() { return -1; }
    let Some(phase) = music_ripple_phase(time, offset) else { return -1; };
    *output = phase;
    0
}

/// Writes three consecutive doubles: left, peak and right gradient stops.
#[no_mangle]
pub unsafe extern "C" fn rium_notch_music_crest_positions(center: f64, output: *mut f64) -> i32 {
    if output.is_null() { return -1; }
    let Some(stops) = music_crest_positions(center) else { return -1; };
    for (index, value) in stops.iter().enumerate() { *output.add(index) = *value; }
    0
}

/// Writes seven consecutive doubles: width, height, three vertical gradient
/// opacities, left fade stop and right fade stop. Returns 0 or -1 on error.
#[no_mangle]
pub unsafe extern "C" fn rium_notch_organic_ray_fog(arm_width: f64, scale: f64, output: *mut f64) -> i32 {
    if output.is_null() { return -1; }
    let Some(values) = organic_ray_fog(arm_width, scale) else { return -1; };
    for (index, value) in values.iter().enumerate() { *output.add(index) = *value; }
    0
}

/// Writes three doubles: line brightness, glow brightness, contour width.
/// `reduce_motion` must be 0 or 1. Returns 0 on success, -1 on error.
#[no_mangle]
pub unsafe extern "C" fn rium_notch_idle_light(time: f64, reduce_motion: i32, output: *mut f64) -> i32 {
    if output.is_null() || !(0..=1).contains(&reduce_motion) { return -1; }
    let Some(values) = idle_light_frame(time, reduce_motion == 1) else { return -1; };
    for (index, value) in values.iter().enumerate() { *output.add(index) = *value; }
    0
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_receiving_tide(elapsed: f64, clock: f64, progress: f64,
    held: i32, reduce_motion: i32, output: *mut f64) -> i32 {
    if output.is_null() || !(0..=1).contains(&held) || !(0..=1).contains(&reduce_motion) { return -1; }
    let Some(values) = receiving_tide_frame(elapsed, clock, progress, held == 1, reduce_motion == 1) else { return -1; };
    *output = values[0]; *output.add(1) = values[1];
    0
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_edge_wave(elapsed: f64, inward: i32, output: *mut f64) -> i32 {
    if output.is_null() || !(0..=1).contains(&inward) { return -1; }
    let Some(values) = edge_wave_frame(elapsed, inward == 1) else { return -1; };
    *output = values[0]; *output.add(1) = values[1];
    0
}

#[no_mangle]
pub unsafe extern "C" fn rium_notch_edge_wave_detail(angle: f64, time: f64, radius: f64, output: *mut f64) -> i32 {
    if output.is_null() { return -1; }
    let Some(values) = edge_wave_detail(angle, time, radius) else { return -1; };
    for (index, value) in values.iter().enumerate() { *output.add(index) = *value; }
    0
}

/// Writes four doubles in the order documented by `agent_light_frame`.
#[no_mangle]
pub unsafe extern "C" fn rium_notch_agent_light(time: f64, reduce_motion: i32, output: *mut f64) -> i32 {
    if output.is_null() || !(0..=1).contains(&reduce_motion) { return -1; }
    let Some(values) = agent_light_frame(time, reduce_motion == 1) else { return -1; };
    for (index, value) in values.iter().enumerate() { *output.add(index) = *value; }
    0
}

/// Writes eight doubles in the order documented by `character_pose`.
/// State 0=idle, 1=working, 2=approval, 3=question, 4=done, 5=failed,
/// 6=retry, 7=interrupted, 8=stalled.
#[no_mangle]
pub unsafe extern "C" fn rium_notch_character_pose(state: i32, time: f64, state_age: f64,
    reduce_motion: i32, output: *mut f64) -> i32 {
    if output.is_null() || !(0..=1).contains(&reduce_motion) { return -1; }
    let Some(values) = character_pose(state, time, state_age, reduce_motion == 1) else { return -1; };
    for (index, value) in values.iter().enumerate() { *output.add(index) = *value; }
    0
}

/// Writes three doubles in the order documented by `lumi_parts_pose`.
#[no_mangle]
pub unsafe extern "C" fn rium_notch_lumi_parts_pose(state: i32, time: f64, state_age: f64,
    reduce_motion: i32, output: *mut f64) -> i32 {
    if output.is_null() || !(0..=1).contains(&reduce_motion) { return -1; }
    let Some(values) = lumi_parts_pose(state, time, state_age, reduce_motion == 1) else { return -1; };
    for (index, value) in values.iter().enumerate() { *output.add(index) = *value; }
    0
}

/// Writes the two normalized gaze components.
#[no_mangle]
pub unsafe extern "C" fn rium_notch_lumi_pointer_gaze(x: f64, y: f64, width: f64, height: f64, output: *mut f64) -> i32 {
    if output.is_null() { return -1; }
    let Some(values) = lumi_pointer_gaze(x, y, width, height) else { return -1; };
    *output = values[0]; *output.add(1) = values[1];
    0
}

#[no_mangle]
pub extern "C" fn rium_notch_lumi_reaction_kind(mood: i32, clicks: u32) -> i32 {
    lumi_reaction_kind(mood, clicks).unwrap_or(-1)
}

/// Writes ten doubles describing the reaction overlay.
#[no_mangle]
pub unsafe extern "C" fn rium_notch_lumi_reaction_frame(kind: i32, elapsed: f64, reduce_motion: i32, output: *mut f64) -> i32 {
    if output.is_null() || !(0..=1).contains(&reduce_motion) { return -1; }
    let Some(values) = lumi_reaction_frame(kind, elapsed, reduce_motion == 1) else { return -1; };
    for (index, value) in values.iter().enumerate() { *output.add(index) = *value; }
    0
}
