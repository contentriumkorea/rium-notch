//! Sleep-inclusive monotonic focus countdown. UI draws the timer.
use std::sync::Mutex;
use std::time::Duration;

// Darwin CLOCK_MONOTONIC_RAW advances during sleep, unlike CLOCK_UPTIME_RAW.
extern "C" { fn clock_gettime_nsec_np(clock_id: i32) -> u64; }
fn now() -> Duration { Duration::from_nanos(unsafe { clock_gettime_nsec_np(4) }) }

#[derive(Default)]
struct Countdown {
    remaining: Duration,
    deadline: Option<Duration>,
    started: bool,
}

impl Countdown {
    fn remaining_at(&self, now: Duration) -> Duration {
        self.deadline.map(|deadline| deadline.saturating_sub(now)).unwrap_or(self.remaining)
    }
    fn start(&mut self, seconds: u32, now: Duration) {
        self.remaining = Duration::from_secs(seconds.into());
        self.started = seconds > 0;
        self.deadline = if self.started { now.checked_add(self.remaining) } else { None };
    }
    fn pause(&mut self, now: Duration) {
        self.remaining = self.remaining_at(now);
        self.deadline = None;
    }
    fn resume(&mut self, now: Duration) {
        if self.started && self.deadline.is_none() && !self.remaining.is_zero() {
            self.deadline = now.checked_add(self.remaining);
        }
    }
    fn status(&self, now: Duration) -> (i32, u64) {
        let remaining = self.remaining_at(now);
        let rounded = remaining.as_secs() + u64::from(remaining.subsec_nanos() != 0);
        let state = if !self.started { 0 } else if remaining.is_zero() { 3 } else if self.deadline.is_some() { 1 } else { 2 };
        (state, rounded)
    }
}

static TIMER: Mutex<Countdown> = Mutex::new(Countdown { remaining: Duration::ZERO, deadline: None, started: false });

#[no_mangle]
pub extern "C" fn rium_timer_start(seconds: u32) { TIMER.lock().unwrap_or_else(|e| e.into_inner()).start(seconds, now()); }
#[no_mangle]
pub extern "C" fn rium_timer_pause() { TIMER.lock().unwrap_or_else(|e| e.into_inner()).pause(now()); }
#[no_mangle]
pub extern "C" fn rium_timer_resume() { TIMER.lock().unwrap_or_else(|e| e.into_inner()).resume(now()); }
#[no_mangle]
pub extern "C" fn rium_timer_reset() { *TIMER.lock().unwrap_or_else(|e| e.into_inner()) = Countdown::default(); }
/// Restore a validated checkpoint. 1 running, 2 paused, 3 complete.
#[no_mangle]
pub extern "C" fn rium_timer_restore(state: i32, seconds: u32) -> i32 {
    if !(1..=3).contains(&state) || seconds > 86_400 || (state != 3 && seconds == 0) { return -1; }
    let mut timer = TIMER.lock().unwrap_or_else(|e| e.into_inner());
    if state == 3 { *timer = Countdown { remaining: Duration::ZERO, deadline: None, started: true }; }
    else { let current = now(); timer.start(seconds, current); if state == 2 { timer.pause(current); } }
    0
}
/// 0 idle, 1 running, 2 paused, 3 complete. Null output returns -1.
#[no_mangle]
pub unsafe extern "C" fn rium_timer_status(seconds: *mut u64) -> i32 {
    if seconds.is_null() { return -1; }
    let (status, remaining) = TIMER.lock().unwrap_or_else(|e| e.into_inner()).status(now());
    *seconds = remaining;
    status
}

// Glance's observed defaults: 25-minute focus, 5-minute short break,
// 15-minute long break after four focus sessions. `elapsed` is whole seconds
// since the just-finished phase ended (for example, while the Mac slept).
#[derive(Clone, Copy)]
struct PomodoroConfig { focus: u32, short_break: u32, long_break: u32, sessions: u32 }
impl PomodoroConfig {
    fn valid(self) -> bool { (1..=180).contains(&self.focus) && (1..=60).contains(&self.short_break) && (1..=60).contains(&self.long_break) && (1..=12).contains(&self.sessions) }
}
const DEFAULT_POMODORO: PomodoroConfig = PomodoroConfig { focus: 25, short_break: 5, long_break: 15, sessions: 4 };
fn pomodoro_advance_with(config: PomodoroConfig, mut phase: i32, mut completed: u64, mut elapsed: u64) -> Option<(i32, u64, u64)> {
    if !config.valid() { return None; }
    fn next(phase: i32, completed: &mut u64, sessions: u64) -> Option<i32> {
        match phase {
            0 => { *completed = completed.checked_add(1)?; Some(if *completed % sessions == 0 { 2 } else { 1 }) }
            1 | 2 => Some(0),
            _ => None,
        }
    }
    let sessions = u64::from(config.sessions);
    phase = next(phase, &mut completed, sessions)?;
    loop {
        // At a complete cycle boundary skip whole cycles, even after a long
        // sleep, without looping once per missed phase.
        let cycle = (sessions * u64::from(config.focus) + (sessions - 1) * u64::from(config.short_break) + u64::from(config.long_break)) * 60;
        if phase == 0 && completed % sessions == 0 && elapsed >= cycle {
            let cycles = elapsed / cycle;
            completed = completed.checked_add(cycles.checked_mul(sessions)?)?;
            elapsed %= cycle;
        }
        let duration = u64::from(match phase { 0 => config.focus, 1 => config.short_break, 2 => config.long_break, _ => return None }) * 60;
        if elapsed < duration { return Some((phase, completed, duration - elapsed)); }
        elapsed -= duration;
        phase = next(phase, &mut completed, sessions)?;
    }
}

#[no_mangle]
pub unsafe extern "C" fn rium_pomodoro_advance(phase: i32, completed: u64, elapsed: u64, next_phase: *mut i32, next_completed: *mut u64, remaining: *mut u64) -> i32 {
    let c = DEFAULT_POMODORO;
    rium_pomodoro_advance_config(phase, completed, elapsed, c.focus, c.short_break, c.long_break, c.sessions, next_phase, next_completed, remaining)
}

#[no_mangle]
pub unsafe extern "C" fn rium_pomodoro_advance_config(phase: i32, completed: u64, elapsed: u64, focus: u32, short_break: u32, long_break: u32, sessions: u32, next_phase: *mut i32, next_completed: *mut u64, remaining: *mut u64) -> i32 {
    if next_phase.is_null() || next_completed.is_null() || remaining.is_null() { return -1; }
    match pomodoro_advance_with(PomodoroConfig { focus, short_break, long_break, sessions }, phase, completed, elapsed) {
        Some((p, c, r)) => { *next_phase = p; *next_completed = c; *remaining = r; 0 }
        None => -1,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn countdown_survives_pause_and_finishes_without_underflow() {
        let now = Duration::from_secs(100); let mut timer = Countdown::default();
        timer.start(60, now);
        assert_eq!(timer.status(now + Duration::from_secs(20)), (1, 40));
        timer.pause(now + Duration::from_secs(20));
        assert_eq!(timer.status(now + Duration::from_secs(100)), (2, 40));
        timer.resume(now + Duration::from_secs(100));
        assert_eq!(timer.status(now + Duration::from_secs(141)), (3, 0));
        timer.pause(now + Duration::from_secs(150));
        timer.resume(now + Duration::from_secs(151));
        assert_eq!(timer.status(now + Duration::from_secs(152)), (3, 0));
    }
    #[test]
    fn pomodoro_progresses_through_short_and_long_breaks() {
        let pomodoro_advance = |phase, count, elapsed| pomodoro_advance_with(DEFAULT_POMODORO, phase, count, elapsed);
        assert_eq!(pomodoro_advance(0, 0, 0), Some((1, 1, 300)));
        assert_eq!(pomodoro_advance(1, 1, 0), Some((0, 1, 1500)));
        assert_eq!(pomodoro_advance(0, 3, 0), Some((2, 4, 900)));
        assert_eq!(pomodoro_advance(2, 4, 7800), Some((0, 8, 1500)));
        assert_eq!(pomodoro_advance(0, 0, 300 + 45), Some((0, 1, 1455)));
        assert!(pomodoro_advance(3, 0, 0).is_none());
        assert!(pomodoro_advance(0, u64::MAX, 0).is_none());
        let custom = PomodoroConfig { focus: 12, short_break: 3, long_break: 8, sessions: 2 };
        assert_eq!(pomodoro_advance_with(custom, 0, 0, 0), Some((1, 1, 180)));
        assert_eq!(pomodoro_advance_with(custom, 0, 1, 0), Some((2, 2, 480)));
        assert_eq!(pomodoro_advance_with(custom, 2, 2, 35 * 60), Some((0, 4, 720)));
        assert!(pomodoro_advance_with(PomodoroConfig { sessions: 0, ..custom }, 0, 0, 0).is_none());
    }
}
