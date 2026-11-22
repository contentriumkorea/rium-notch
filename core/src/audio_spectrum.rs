//! Transient six-band analysis for the optional music lighting visualizer.
//! No samples or results are persisted by this module.

use std::f64::consts::PI;

const EDGES: [f64; 7] = [40.0, 160.0, 400.0, 1000.0, 2500.0, 6000.0, 16000.0];
const FFT_SIZE: usize = 1024;

fn transition_height(from: f64, to: f64, elapsed: f64) -> Option<f64> {
    if !from.is_finite() || !to.is_finite() || !elapsed.is_finite() { return None; }
    let t = (elapsed / 0.1).clamp(0.0, 1.0);
    let blend = t * t * (3.0 - 2.0 * t);
    Some(from + (to - from) * blend)
}

#[no_mangle]
pub extern "C" fn rium_audio_wave_transition(from: f64, to: f64, elapsed: f64) -> f64 {
    transition_height(from, to, elapsed).unwrap_or(f64::NAN)
}

// shortcut: the three-second grace period needs calibration against real audio streams.
fn sample_expired(last: f64, now: f64) -> bool {
    last.is_finite() && now.is_finite() && now >= last && now - last >= 3.0
}

#[no_mangle]
pub extern "C" fn rium_audio_spectrum_expired(last: f64, now: f64) -> i32 {
    i32::from(sample_expired(last, now))
}

/// Computes bounded display levels from the most recent PCM samples.
///
/// shortcut: real-FFT scaling may differ from vDSP; calibrate with audio comparison.
fn spectrum(samples: &[f32], sample_rate: f64, previous: &[f64; 6]) -> Option<[f64; 6]> {
    if !(FFT_SIZE..=8192).contains(&samples.len()) || !sample_rate.is_finite()
        || !(8000.0..=192000.0).contains(&sample_rate)
        || previous.iter().any(|level| !level.is_finite() || !(0.0..=1.0).contains(level))
    {
        return None;
    }
    let samples = &samples[samples.len() - FFT_SIZE..];
    if samples.iter().any(|sample| !sample.is_finite()) {
        return None;
    }
    let size = FFT_SIZE;
    let mut bins = vec![(0.0f64, 0.0f64); size];
    for (index, &sample) in samples.iter().enumerate() {
        let window = 0.816_496_580_927_726 * (1.0 - (2.0 * PI * index as f64 / size as f64).cos());
        bins[index].0 = f64::from(sample.clamp(-1.0, 1.0)) * window;
    }
    // In-place radix-2 FFT.
    let mut reversed = 0usize;
    for index in 1..size {
        let mut bit = size >> 1;
        while reversed & bit != 0 { reversed ^= bit; bit >>= 1; }
        reversed ^= bit;
        if index < reversed { bins.swap(index, reversed); }
    }
    let mut span = 2;
    while span <= size {
        let angle = -2.0 * PI / span as f64;
        let (step_i, step_r) = angle.sin_cos();
        for base in (0..size).step_by(span) {
            let (mut wr, mut wi) = (1.0, 0.0);
            for offset in 0..span / 2 {
                let (right_r, right_i) = bins[base + offset + span / 2];
                let (tr, ti) = (right_r * wr - right_i * wi, right_r * wi + right_i * wr);
                let (left_r, left_i) = bins[base + offset];
                bins[base + offset] = (left_r + tr, left_i + ti);
                bins[base + offset + span / 2] = (left_r - tr, left_i - ti);
                (wr, wi) = (wr * step_r - wi * step_i, wr * step_i + wi * step_r);
            }
        }
        span *= 2;
    }
    let mut levels = [0.0; 6];
    let bin_width = sample_rate / size as f64;
    for band in 0..levels.len() {
        let first = ((EDGES[band] / bin_width).ceil() as usize).max(1);
        let last = (((EDGES[band + 1] / bin_width).ceil() as usize) - 1).min(size / 2 - 1);
        let target = if first > last { 0.0 } else {
            let mean = bins[first..=last].iter().map(|&(real, imaginary)| 2.0 * real.hypot(imaginary)).sum::<f64>() / (last - first + 1) as f64;
            let db = 20.0 * (mean / 512.0 + 1e-7).log10();
            ((db + 54.0) / 34.0).clamp(0.0, 1.0).powf(0.62)
        };
        let factor = if target > previous[band] { 0.85 } else { 0.42 };
        levels[band] = previous[band] + (target - previous[band]) * factor;
    }
    Some(levels)
}

fn stereo_spectrum(left: &[f32], right: Option<&[f32]>, sample_rate: f64, previous: &[f64; 6]) -> Option<[f64; 6]> {
    let mut levels = spectrum(left, sample_rate, previous)?;
    if let Some(right) = right {
        if right.len() != left.len() { return None; }
        let other = spectrum(right, sample_rate, previous)?;
        for (level, other) in levels.iter_mut().zip(other) { *level = (*level).max(other); }
    }
    Some(levels)
}

/// The optional right channel and the required left channel each contain `len` samples.
#[no_mangle]
pub unsafe extern "C" fn rium_audio_stereo_spectrum(
    left: *const f32, right: *const f32, len: usize, sample_rate: f64, previous: *const f64, output: *mut f64,
) -> i32 {
    if left.is_null() || previous.is_null() || output.is_null() || !(FFT_SIZE..=8192).contains(&len) { return -1; }
    let left = std::slice::from_raw_parts(left, len);
    let right = (!right.is_null()).then(|| std::slice::from_raw_parts(right, len));
    let mut last = [0.0; 6];
    last.copy_from_slice(std::slice::from_raw_parts(previous, 6));
    match stereo_spectrum(left, right, sample_rate, &last) {
        Some(levels) => { std::ptr::copy_nonoverlapping(levels.as_ptr(), output, levels.len()); 0 }
        None => -1,
    }
}

/// Writes six display levels and returns 0; returns -1 for invalid arguments.
///
/// # Safety
/// `samples` must point to `len` readable f32 values; `previous` and `output`
/// must point to six readable and writable f64 values respectively, without overlap.
#[no_mangle]
pub unsafe extern "C" fn rium_audio_spectrum(
    samples: *const f32, len: usize, sample_rate: f64, previous: *const f64, output: *mut f64,
) -> i32 {
    if samples.is_null() || previous.is_null() || output.is_null() || !(FFT_SIZE..=8192).contains(&len) {
        return -1;
    }
    let input = std::slice::from_raw_parts(samples, len);
    let mut last = [0.0; 6];
    last.copy_from_slice(std::slice::from_raw_parts(previous, 6));
    match spectrum(input, sample_rate, &last) {
        Some(levels) => {
            std::ptr::copy_nonoverlapping(levels.as_ptr(), output, levels.len());
            0
        }
        None => -1,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn waveform_transition_is_continuous_and_bounded() {
        assert_eq!(transition_height(4.0, 12.0, -0.1), Some(4.0));
        assert_eq!(transition_height(4.0, 12.0, 0.05), Some(8.0));
        assert_eq!(transition_height(4.0, 12.0, 0.1), Some(12.0));
        assert_eq!(transition_height(4.0, 12.0, 1.0), Some(12.0));
        assert!(transition_height(f64::NAN, 12.0, 0.05).is_none());
    }
    #[test]
    fn old_levels_expire_without_treating_clock_reversal_as_silence() {
        assert!(!sample_expired(10.0, 12.9));
        assert!(sample_expired(10.0, 13.0));
        assert!(!sample_expired(10.0, 9.0));
        assert!(!sample_expired(f64::NAN, 13.0));
    }

    fn tone(frequency: f64) -> Vec<f32> {
        (0..2048).map(|i| (0.2 * (2.0 * PI * frequency * i as f64 / 48000.0).sin()) as f32).collect()
    }

    #[test]
    fn silence_and_distinct_frequencies() {
        assert_eq!(spectrum(&vec![0.0; 1024], 48000.0, &[0.0; 6]), Some([0.0; 6]));
        for (frequency, band) in [(90.0, 0), (250.0, 1), (650.0, 2), (1600.0, 3), (4000.0, 4), (9000.0, 5)] {
            let levels = spectrum(&tone(frequency), 48000.0, &[0.0; 6]).unwrap();
            assert!(levels[band] > 0.0);
            assert!(levels.iter().all(|v| (0.0..=1.0).contains(v)));
            assert_eq!(levels.iter().enumerate().max_by(|a, b| a.1.total_cmp(b.1)).unwrap().0, band);
        }
        let decay = spectrum(&[0.0; 1024], 48000.0, &[1.0; 6]).unwrap();
        assert!(decay.iter().all(|value| (*value - 0.58).abs() < 1e-9));
    }

    #[test]
    fn stereo_bands_do_not_cancel_out_of_phase_audio() {
        let left = tone(650.0);
        let inverted: Vec<f32> = left.iter().map(|sample| -*sample).collect();
        let mono = spectrum(&left, 48000.0, &[0.0; 6]).unwrap();
        let stereo = stereo_spectrum(&left, Some(&inverted), 48000.0, &[0.0; 6]).unwrap();
        for (a, b) in mono.iter().zip(stereo) { assert!((a - b).abs() < 1e-9); }
        let right = tone(4000.0);
        let mixed = stereo_spectrum(&left, Some(&right), 48000.0, &[0.0; 6]).unwrap();
        assert!(mixed[2] > 0.0 && mixed[4] > 0.0);
        assert!(stereo_spectrum(&left, Some(&right[..1024]), 48000.0, &[0.0; 6]).is_none());
        assert!(stereo_spectrum(&left, None, 48000.0, &[0.0; 6]).is_some());
    }

    #[test]
    fn empty_band_does_not_borrow_the_next_frequency_at_high_sample_rates() {
        let samples: Vec<f32> = (0..1024)
            .map(|i| (0.2 * (2.0 * PI * i as f64 / 1024.0).sin()) as f32)
            .collect();
        let levels = spectrum(&samples, 192000.0, &[0.0; 6]).unwrap();
        assert_eq!(levels[0], 0.0);
        assert!(levels[1] > 0.0);
    }

    #[test]
    fn rejects_invalid_input_and_skips_frequencies_above_nyquist() {
        assert!(spectrum(&[0.0; 1023], 48000.0, &[0.0; 6]).is_none());
        assert!(spectrum(&[0.0; 1024], f64::NAN, &[0.0; 6]).is_none());
        let mut invalid = vec![0.0; 1024];
        invalid[12] = f32::NAN;
        assert!(spectrum(&invalid, 48000.0, &[0.0; 6]).is_none());
        assert_eq!(spectrum(&[0.0; 1024], 8000.0, &[0.0; 6]).unwrap()[5], 0.0);
        assert!(spectrum(&[0.0; 1024], 48000.0, &[f64::NAN; 6]).is_none());
        assert_eq!(unsafe { rium_audio_spectrum(std::ptr::null(), 1024, 48000.0, std::ptr::null(), std::ptr::null_mut()) }, -1);
    }
}
