//! Folder scan timing and lifetime of screenshot candidates.

#[no_mangle]
pub extern "C" fn rium_screenshot_scan_delay(burst_age: f64) -> f64 {
    if !burst_age.is_finite() || burst_age < 0.0 { return 0.35; }
    (1.0 - burst_age).clamp(0.0, 0.35)
}

#[no_mangle]
pub extern "C" fn rium_screenshot_shortcut_poll_interval(age: f64) -> f64 {
    if (0.0..60.0).contains(&age) { 0.2 } else { 0.0 }
}

fn candidate_active(first_seen: f64, now: f64, exists: bool) -> bool {
    exists && first_seen.is_finite() && now.is_finite() && now >= first_seen && now - first_seen <= 60.0
}

#[no_mangle]
pub extern "C" fn rium_screenshot_candidate_active(first_seen: f64, now: f64, exists: i32) -> i32 {
    if !(0..=1).contains(&exists) { return -1; }
    i32::from(candidate_active(first_seen, now, exists == 1))
}

// Reference layout: 104pt card height, 132pt slot spacing, 34pt first slot.
#[no_mangle]
pub extern "C" fn rium_screenshot_line_capacity(height: f64) -> i32 {
    if !height.is_finite() || height < 0.0 { return -1; }
    ((((height - 34.0 - 104.0 - 10.0) / 132.0).trunc() as i32).saturating_add(1)).clamp(1, 5)
}

const LINE_POINTS: usize = 34;
const LINE_CARDS: usize = 5;
const LINE_FRAME_VALUES: usize = LINE_POINTS * 2 + LINE_CARDS * 3;

struct LineMotion {
    height: f64,
    tray_x: f64,
    tray_velocity: f64,
    points: [[f64; 2]; LINE_POINTS],
    previous: [[f64; 2]; LINE_POINTS],
    angle: [f64; LINE_CARDS],
    angular_velocity: [f64; LINE_CARDS],
    pivot_velocity: [f64; LINE_CARDS],
    last_pivot_x: [f64; LINE_CARDS],
    last_count: usize,
    returning: [bool; LINE_CARDS],
    return_pivot: [[f64; 2]; LINE_CARDS],
    return_velocity: [[f64; 2]; LINE_CARDS],
    grabbed: Option<usize>,
    detached: bool,
    pointer: [f64; 2],
    grab_offset: [f64; 2],
}

impl LineMotion {
    fn new(height: f64) -> Self {
        let mut points = [[0.0; 2]; LINE_POINTS];
        for (index, point) in points.iter_mut().enumerate() {
            *point = [382.0, 18.0 + (height + 12.0) * index as f64 / (LINE_POINTS - 1) as f64];
        }
        Self { height, tray_x: 382.0, tray_velocity: 0.0, points, previous: points,
            angle: [0.0; LINE_CARDS], angular_velocity: [0.0; LINE_CARDS],
            pivot_velocity: [0.0; LINE_CARDS], last_pivot_x: [382.0; LINE_CARDS], last_count: 0,
            returning: [false; LINE_CARDS], return_pivot: [[0.0; 2]; LINE_CARDS],
            return_velocity: [[0.0; 2]; LINE_CARDS], grabbed: None, detached: false, pointer: [0.0; 2], grab_offset: [0.0; 2] }
    }

    fn sample(&self, index: usize) -> [f64; 2] {
        let segment = (self.height + 12.0) * 1.012 / (LINE_POINTS - 1) as f64;
        let s = ((34.0 + index as f64 * 132.0) / segment).clamp(0.0, (LINE_POINTS - 1) as f64 - 0.0001);
        let a = s as usize;
        let fraction = s - a as f64;
        [self.points[a][0] + (self.points[a + 1][0] - self.points[a][0]) * fraction,
         self.points[a][1] + (self.points[a + 1][1] - self.points[a][1]) * fraction]
    }

    fn nearest_rope(&self, point: [f64; 2]) -> (f64, f64) {
        let mut nearest = (0.0, f64::INFINITY);
        for i in 0..LINE_POINTS - 1 {
            let start = self.points[i];
            let dx = self.points[i + 1][0] - start[0];
            let dy = self.points[i + 1][1] - start[1];
            let length2 = (dx * dx + dy * dy).max(f64::EPSILON);
            let t = (((point[0] - start[0]) * dx + (point[1] - start[1]) * dy) / length2).clamp(0.0, 1.0);
            let distance = (point[0] - start[0] - dx * t).hypot(point[1] - start[1] - dy * t);
            if distance < nearest.1 { nearest = (i as f64 + t, distance); }
        }
        nearest
    }

    fn remap(&mut self, indices: &[i32]) -> bool {
        if indices.len() > LINE_CARDS { return false; }
        let mut seen = [false; LINE_CARDS];
        for &index in indices {
            if index < -1 || index >= self.last_count as i32 { return false; }
            if index >= 0 {
                if seen[index as usize] { return false; }
                seen[index as usize] = true;
            }
        }
        let old_angle = self.angle;
        let old_angular = self.angular_velocity;
        let old_velocity = self.pivot_velocity;
        let old_last_x = self.last_pivot_x;
        let old_returning = self.returning;
        let old_return_pivot = self.return_pivot;
        let old_return_velocity = self.return_velocity;
        let old_grabbed = self.grabbed;
        self.grabbed = None;
        for (new, &mapped) in indices.iter().enumerate() {
            if mapped < 0 {
                self.angle[new] = 0.0; self.angular_velocity[new] = 0.0;
                let pivot = self.sample(new);
                self.pivot_velocity[new] = 0.0; self.last_pivot_x[new] = pivot[0];
                self.returning[new] = false;
                continue;
            }
            let old = mapped as usize;
            self.angle[new] = old_angle[old]; self.angular_velocity[new] = old_angular[old];
            self.pivot_velocity[new] = old_velocity[old]; self.last_pivot_x[new] = old_last_x[old];
            self.returning[new] = old_returning[old];
            self.return_pivot[new] = old_return_pivot[old]; self.return_velocity[new] = old_return_velocity[old];
            if old_grabbed == Some(old) { self.grabbed = Some(new); }
            else if old != new && !self.returning[new] {
                self.returning[new] = true;
                let prior_pivot = self.sample(old);
                self.return_pivot[new] = prior_pivot;
                self.return_velocity[new] = [0.0; 2];
            }
        }
        if old_grabbed.is_some() && self.grabbed.is_none() { self.detached = false; }
        self.last_count = indices.len();
        true
    }

    fn step(&mut self, dt: f64, expanded: bool, count: usize, reduced: bool) {
        let target = if expanded { 212.0 } else { 382.0 };
        if reduced {
            self.tray_x = target;
            self.tray_velocity = 0.0;
            for (index, point) in self.points.iter_mut().enumerate() {
                *point = [target, 18.0 + (self.height + 12.0) * index as f64 / (LINE_POINTS - 1) as f64];
            }
            self.angle = [0.0; LINE_CARDS];
            self.angular_velocity = [0.0; LINE_CARDS];
            self.returning = [false; LINE_CARDS];
            for index in 0..LINE_POINTS { self.points[index][0] = target; }
            self.previous = self.points;
            self.last_pivot_x = [target; LINE_CARDS];
            self.last_count = count;
            return;
        }
        if dt == 0.0 { return; }
        if count != self.last_count { self.returning = [false; LINE_CARDS]; }
        for card in self.last_count..count {
            self.last_pivot_x[card] = self.sample(card)[0];
            self.pivot_velocity[card] = 0.0;
            self.angle[card] = 0.0;
            self.angular_velocity[card] = 0.0;
        }
        let h = dt / (dt * 120.0).ceil().max(1.0);
        let steps = (dt / h).round() as usize;
        for _ in 0..steps {
            self.tray_velocity += ((target - self.tray_x) * 8.5 * 8.5 - self.tray_velocity * 13.26) * h;
            self.tray_x += self.tray_velocity * h;
            let segment = (self.height + 12.0) * 1.012 / (LINE_POINTS - 1) as f64;
            let mut force = [1900.0; LINE_POINTS];
            for card in 0..count {
                if self.returning[card] || (self.grabbed == Some(card) && self.detached) { continue; }
                let s = ((34.0 + card as f64 * 132.0) / segment).clamp(0.0, (LINE_POINTS - 1) as f64 - 0.0001);
                let a = s as usize;
                let t = s - a as f64;
                force[a] += 1900.0 * 5.0 * (1.0 - t);
                force[a + 1] += 1900.0 * 5.0 * t;
            }
            let damping = 0.99_f64.powf(h * 240.0);
            for (i, &gravity) in force.iter().enumerate().take(LINE_POINTS - 1).skip(1) {
                let current = self.points[i];
                self.points[i][0] += (current[0] - self.previous[i][0]) * damping;
                self.points[i][1] += (current[1] - self.previous[i][1]) * damping + gravity * h * h;
                self.previous[i] = current;
            }
            self.points[0] = [self.tray_x, 18.0];
            self.points[LINE_POINTS - 1] = [self.tray_x, self.height + 30.0];
            if let Some(card) = self.grabbed.filter(|&card| card < count && !self.detached) {
                let s = ((34.0 + card as f64 * 132.0) / segment).clamp(0.0, (LINE_POINTS - 1) as f64 - 0.0001);
                let index = s as usize;
                let t = s - index as f64;
                let pivot = self.sample(card);
                for axis in 0..2 {
                    let change = (self.pointer[axis] - self.grab_offset[axis] - pivot[axis]) * 0.6;
                    if index > 0 { self.points[index][axis] += change * (1.0 - t); }
                    if index + 1 < LINE_POINTS - 1 { self.points[index + 1][axis] += change * t; }
                }
            }
            let length2 = segment * segment;
            for iteration in 0..12 {
                for j in 0..LINE_POINTS - 1 {
                    let i = if iteration % 2 == 0 { j } else { LINE_POINTS - 2 - j };
                    let dx = self.points[i + 1][0] - self.points[i][0];
                    let dy = self.points[i + 1][1] - self.points[i][1];
                    let distance2 = dx * dx + dy * dy;
                    if distance2 <= f64::EPSILON { continue; }
                    let correction = length2 / (length2 + distance2) - 0.5;
                    let weight = if i == 0 || i + 1 == LINE_POINTS - 1 { 2.0 } else { 1.0 };
                    if i != 0 { self.points[i][0] -= dx * correction * weight; self.points[i][1] -= dy * correction * weight; }
                    if i + 1 != LINE_POINTS - 1 { self.points[i + 1][0] += dx * correction * weight; self.points[i + 1][1] += dy * correction * weight; }
                }
            }
            for card in 0..count {
                if self.returning[card] {
                    let target = self.sample(card);
                    for (axis, target_value) in target.iter().enumerate() {
                        let acceleration = (target_value - self.return_pivot[card][axis]) * 11.0 * 11.0
                            - self.return_velocity[card][axis] * (2.0 * 0.74 * 11.0);
                        self.return_velocity[card][axis] += acceleration * h;
                        self.return_pivot[card][axis] += self.return_velocity[card][axis] * h;
                    }
                    let dx = self.return_pivot[card][0] - target[0];
                    let dy = self.return_pivot[card][1] - target[1];
                    let speed = self.return_velocity[card][0].hypot(self.return_velocity[card][1]);
                    if dx.hypot(dy) < 4.0 && speed < 160.0 { self.returning[card] = false; }
                }
                let pivot_x = if self.grabbed == Some(card) && self.detached {
                    self.pointer[0] - self.grab_offset[0]
                } else if self.returning[card] { self.return_pivot[card][0] }
                else { self.sample(card)[0] };
                let velocity = (pivot_x - self.last_pivot_x[card]) / h;
                let acceleration = (velocity - self.pivot_velocity[card]) / h;
                // shortcut: card pendulum damping is inferred until the reference rotation is fully decoded.
                self.angular_velocity[card] += (-24.0 * self.angle[card] - 8.0 * self.angular_velocity[card] - acceleration * 0.002) * h;
                self.angular_velocity[card] = self.angular_velocity[card].clamp(-4.0, 4.0);
                self.angle[card] = (self.angle[card] + self.angular_velocity[card] * h).clamp(-0.35, 0.35);
                self.last_pivot_x[card] = pivot_x;
                self.pivot_velocity[card] = velocity;
            }
        }
        self.last_count = count;
    }

    fn write_frame(&self, output: &mut [f64]) {
        for (i, point) in self.points.iter().enumerate() {
            output[i * 2] = point[0]; output[i * 2 + 1] = point[1];
        }
        for i in 0..LINE_CARDS {
            let pivot = if self.grabbed == Some(i) && self.detached {
                [self.pointer[0] - self.grab_offset[0], self.pointer[1] - self.grab_offset[1]]
            } else if self.returning[i] { self.return_pivot[i] }
            else { self.sample(i) };
            let angle = self.angle[i];
            let at = LINE_POINTS * 2 + i * 3;
            output[at] = pivot[0] - angle.sin() * 48.0;
            output[at + 1] = pivot[1] + angle.cos() * 48.0;
            output[at + 2] = angle;
        }
    }
}

#[no_mangle]
pub extern "C" fn rium_screenshot_line_create(height: f64) -> *mut std::ffi::c_void {
    if !height.is_finite() || !(1.0..=100_000.0).contains(&height) { return std::ptr::null_mut(); }
    Box::into_raw(Box::new(LineMotion::new(height))).cast()
}

#[no_mangle]
pub unsafe extern "C" fn rium_screenshot_line_free(state: *mut std::ffi::c_void) {
    if !state.is_null() { drop(Box::from_raw(state.cast::<LineMotion>())); }
}

#[no_mangle]
pub unsafe extern "C" fn rium_screenshot_line_step(state: *mut std::ffi::c_void, dt: f64, expanded: i32,
    count: i32, reduced: i32, output: *mut f64, output_len: usize) -> i32 {
    if state.is_null() || output.is_null() || output_len < LINE_FRAME_VALUES || !dt.is_finite()
        || !(0.0..=0.05).contains(&dt) || !(0..=1).contains(&expanded)
        || !(0..=LINE_CARDS as i32).contains(&count) || !(0..=1).contains(&reduced) { return -1; }
    let motion = &mut *state.cast::<LineMotion>();
    motion.step(dt, expanded == 1, count as usize, reduced == 1);
    motion.write_frame(std::slice::from_raw_parts_mut(output, LINE_FRAME_VALUES));
    0
}

#[no_mangle]
pub unsafe extern "C" fn rium_screenshot_line_remap(state: *mut std::ffi::c_void, indices: *const i32, count: usize) -> i32 {
    if state.is_null() || count > LINE_CARDS || (indices.is_null() && count != 0) { return -1; }
    let mapping = if count == 0 { &[] } else { std::slice::from_raw_parts(indices, count) };
    if (&mut *state.cast::<LineMotion>()).remap(mapping) { 0 } else { -1 }
}

#[no_mangle]
pub unsafe extern "C" fn rium_screenshot_line_grab(state: *mut std::ffi::c_void, index: i32, x: f64, y: f64) -> i32 {
    if state.is_null() || !(0..LINE_CARDS as i32).contains(&index) || !x.is_finite() || !y.is_finite() { return -1; }
    let motion = &mut *state.cast::<LineMotion>();
    if index as usize >= motion.last_count || motion.grabbed.is_some() { return -1; }
    let card = index as usize;
    let pivot = if motion.returning[card] { motion.return_pivot[card] } else { motion.sample(card) };
    motion.grabbed = Some(card);
    motion.detached = motion.returning[card];
    motion.returning[card] = false;
    motion.pointer = [x, y];
    motion.grab_offset = [x - pivot[0], y - pivot[1]];
    0
}

#[no_mangle]
pub unsafe extern "C" fn rium_screenshot_line_move(state: *mut std::ffi::c_void, x: f64, y: f64) -> i32 {
    if state.is_null() || !x.is_finite() || !y.is_finite() { return -1; }
    let motion = &mut *state.cast::<LineMotion>();
    let Some(card) = motion.grabbed else { return -1; };
    motion.pointer = [x, y];
    if !motion.detached {
        let pivot = motion.sample(card);
        let dx = x - motion.grab_offset[0] - pivot[0];
        let dy = y - motion.grab_offset[1] - pivot[1];
        if dx.hypot(dy) > 62.0 { motion.detached = true; }
    }
    i32::from(motion.detached)
}

#[no_mangle]
pub unsafe extern "C" fn rium_screenshot_line_release(state: *mut std::ffi::c_void, velocity_x: f64, velocity_y: f64) -> i32 {
    if state.is_null() || !velocity_x.is_finite() || !velocity_y.is_finite() { return -1; }
    let motion = &mut *state.cast::<LineMotion>();
    let Some(card) = motion.grabbed.take() else { return -1; };
    let drop = motion.detached && (velocity_x > 1100.0 || motion.pointer[0] - motion.grab_offset[0] > 326.0);
    let mut result = i32::from(drop);
    if motion.detached && !drop {
        motion.returning[card] = true;
        motion.return_pivot[card] = [motion.pointer[0] - motion.grab_offset[0], motion.pointer[1] - motion.grab_offset[1]];
        motion.return_velocity[card] = [velocity_x * 0.6, velocity_y * 0.6];
        let (nearest, distance) = motion.nearest_rope(motion.return_pivot[card]);
        let mut slot = card;
        if distance < 220.0 {
            let segment = (motion.height + 12.0) * 1.012 / (LINE_POINTS - 1) as f64;
            slot = (0..motion.last_count).filter(|&i| i != card && (34.0 + i as f64 * 132.0) / segment <= nearest).count();
        }
        result = slot as i32 + 2;
    }
    motion.detached = false;
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn screenshot_shortcut_wait_expires_after_a_minute() {
        assert_eq!(rium_screenshot_shortcut_poll_interval(0.0), 0.2);
        assert_eq!(rium_screenshot_shortcut_poll_interval(59.99), 0.2);
        assert_eq!(rium_screenshot_shortcut_poll_interval(60.0), 0.0);
        assert_eq!(rium_screenshot_shortcut_poll_interval(-1.0), 0.0);
        assert_eq!(rium_screenshot_shortcut_poll_interval(f64::NAN), 0.0);
    }

    #[test]
    fn screenshot_scan_waits_for_quiet_with_a_one_second_cap() {
        assert_eq!(rium_screenshot_scan_delay(0.0), 0.35);
        assert_eq!(rium_screenshot_scan_delay(0.5), 0.35);
        assert_eq!(rium_screenshot_scan_delay(0.75), 0.25);
        assert_eq!(rium_screenshot_scan_delay(1.2), 0.0);
        assert_eq!(rium_screenshot_scan_delay(f64::NAN), 0.35);
    }

    #[test]
    fn line_motion_keeps_endpoints_and_moves_toward_expanded_position() {
        let mut motion = LineMotion::new(800.0);
        for _ in 0..120 { motion.step(1.0 / 120.0, true, 3, false); }
        assert!((motion.tray_x - 212.0).abs() < 5.0);
        assert_eq!(motion.points[0], [motion.tray_x, 18.0]);
        assert_eq!(motion.points[LINE_POINTS - 1], [motion.tray_x, 830.0]);
        assert!(motion.points.iter().flatten().all(|value| value.is_finite()));
        motion.step(1.0 / 60.0, false, 3, true);
        assert_eq!(motion.tray_x, 382.0);
        assert_eq!(motion.angle, [0.0; LINE_CARDS]);
    }

    #[test]
    fn line_grab_detaches_and_release_can_drop_only_detached_cards() {
        let mut motion = LineMotion::new(800.0);
        motion.step(1.0 / 60.0, true, 1, false);
        let pivot = motion.sample(0);
        let state = (&mut motion as *mut LineMotion).cast();
        unsafe {
            assert_eq!(rium_screenshot_line_grab(state, 0, pivot[0], pivot[1]), 0);
            assert_eq!(rium_screenshot_line_move(state, pivot[0] - 30.0, pivot[1]), 0);
            assert_eq!(rium_screenshot_line_release(state, 1200.0, 0.0), 0);
            assert_eq!(rium_screenshot_line_grab(state, 0, pivot[0], pivot[1]), 0);
            assert_eq!(rium_screenshot_line_move(state, pivot[0] - 70.0, pivot[1]), 1);
            assert_eq!(rium_screenshot_line_release(state, 1200.0, 0.0), 1);
        }
    }

    #[test]
    fn detached_card_returns_without_a_position_jump() {
        let mut motion = LineMotion::new(800.0);
        motion.step(1.0 / 60.0, true, 1, false);
        let pivot = motion.sample(0);
        let state = (&mut motion as *mut LineMotion).cast();
        unsafe {
            assert_eq!(rium_screenshot_line_grab(state, 0, pivot[0], pivot[1]), 0);
            assert_eq!(rium_screenshot_line_move(state, pivot[0] - 90.0, pivot[1] + 20.0), 1);
            assert_eq!(rium_screenshot_line_release(state, 0.0, 0.0), 2);
        }
        assert_eq!(motion.return_pivot[0], [pivot[0] - 90.0, pivot[1] + 20.0]);
        assert!(motion.returning[0]);
        for _ in 0..240 { motion.step(1.0 / 120.0, true, 1, false); }
        assert!(!motion.returning[0]);
    }

    #[test]
    fn remap_keeps_return_and_grab_with_the_same_card() {
        let mut motion = LineMotion::new(800.0);
        motion.step(1.0 / 60.0, true, 2, false);
        motion.returning[0] = true;
        motion.return_pivot[0] = [123.0, 234.0];
        motion.grabbed = Some(1);
        assert!(motion.remap(&[-1, 1, 0]));
        assert_eq!(motion.grabbed, Some(1));
        assert!(motion.returning[2]);
        assert_eq!(motion.return_pivot[2], [123.0, 234.0]);
        assert!(!motion.remap(&[0, 0]));
    }

    #[test]
    fn detached_card_selects_slot_nearest_to_its_release_point() {
        let mut motion = LineMotion::new(800.0);
        motion.step(1.0 / 60.0, true, 3, true);
        let first = motion.sample(0);
        let third = motion.sample(2);
        let state = (&mut motion as *mut LineMotion).cast();
        unsafe {
            assert_eq!(rium_screenshot_line_grab(state, 0, first[0], first[1]), 0);
            assert_eq!(rium_screenshot_line_move(state, third[0], third[1] + 10.0), 1);
            assert_eq!(rium_screenshot_line_release(state, 0.0, 0.0), 4);
        }
    }

    #[test]
    fn line_capacity_tracks_screen_height_and_remains_bounded() {
        assert_eq!(rium_screenshot_line_capacity(0.0), 1);
        assert_eq!(rium_screenshot_line_capacity(279.99), 1);
        assert_eq!(rium_screenshot_line_capacity(280.0), 2);
        assert_eq!(rium_screenshot_line_capacity(676.0), 5);
        assert_eq!(rium_screenshot_line_capacity(10000.0), 5);
        assert_eq!(rium_screenshot_line_capacity(f64::NAN), -1);
        assert_eq!(rium_screenshot_line_capacity(-1.0), -1);
    }

    #[test]
    fn metadata_wait_is_bounded_and_requires_the_original_file() {
        assert!(candidate_active(10.0, 70.0, true));
        assert!(!candidate_active(10.0, 70.01, true));
        assert!(!candidate_active(10.0, 11.0, false));
        assert!(!candidate_active(10.0, 9.0, true));
        assert!(!candidate_active(f64::NAN, 10.0, true));
        assert_eq!(rium_screenshot_candidate_active(10.0, 11.0, 2), -1);
    }
}
