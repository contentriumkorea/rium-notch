//! Reconstructed home background texture generation.
//!
//! The reference paints an opaque 960 × 260 RGBA image. These functions
//! reconstruct several of its procedural texture colour calculations.

pub const TEXTURE_WIDTH: usize = 960;
pub const TEXTURE_HEIGHT: usize = 260;
pub const TEXTURE_BYTES: usize = TEXTURE_WIDTH * TEXTURE_HEIGHT * 4;

fn halftone_rgb(x: usize, y: usize) -> [f64; 3] {
    let u = x as f64 / TEXTURE_WIDTH as f64;
    let v = y as f64 / TEXTURE_HEIGHT as f64;
    let dx = (x % 10) as f64 - 5.0;
    let dy = (y % 10) as f64 - 5.0;
    let radius = (0.75 * u + 0.2) * 5.0;
    if dx * dx + dy * dy >= radius * radius {
        [1.0, 0.86, 0.82]
    } else {
        let inverse = 1.0 - v;
        [0.98 * inverse + 0.93 * v,
         0.47 * inverse + 0.36 * v,
         0.42 * inverse + 0.52 * v]
    }
}

// The same integer hash is used for interpolated value noise and pixel grain.
fn hash(x: i64, y: i64, seed: i64) -> f64 {
    let key = x.wrapping_mul(0x1656_67b1)
        .wrapping_add(y.wrapping_mul(0x27d4_eb2f))
        .wrapping_add(seed.wrapping_mul(0x7fff_ffff)) as u64;
    let mixed = (key ^ (key >> 13)).wrapping_mul(0x4bf1_9f61) as u32;
    f64::from((mixed ^ (mixed >> 16)) & 0xffff) / 65535.0
}

fn value_noise(x: f64, y: f64, seed: i64) -> f64 {
    let ix = x.floor() as i64;
    let iy = y.floor() as i64;
    let dx = x - x.floor();
    let dy = y - y.floor();
    let sx = dx * dx * (3.0 - 2.0 * dx);
    let sy = dy * dy * (3.0 - 2.0 * dy);
    let lower = hash(ix, iy, seed) * (1.0 - sx) + hash(ix + 1, iy, seed) * sx;
    let upper = hash(ix, iy + 1, seed) * (1.0 - sx) + hash(ix + 1, iy + 1, seed) * sx;
    lower * (1.0 - sy) + upper * sy
}

fn fbm(x: f64, y: f64, seed: i64) -> f64 {
    value_noise(x, y, seed) * 0.5
        + value_noise(x * 2.0, y * 2.0, seed + 17) * 0.25
        + value_noise(x * 4.0, y * 4.0, seed + 34) * 0.125
        + value_noise(x * 8.0, y * 8.0, seed + 51) * 0.0625
}

fn linen_rgb(x: usize, y: usize) -> [f64; 3] {
    let u = x as f64 / TEXTURE_WIDTH as f64;
    let v = y as f64 / TEXTURE_HEIGHT as f64;
    let vertical = ((x as f64 * 1.4).sin() + 1.0) * 0.5;
    let horizontal = ((y as f64 * 1.4).sin() + 1.0) * 0.5;
    let shade = 0.92 + vertical * horizontal * 0.08 + (fbm(u * 2.0, v * 30.0, 71) - 0.5) * 0.1;
    [shade * 0.86, shade * 0.82, shade * 0.74]
}

fn fluted_rgb(x: usize, y: usize) -> [f64; 3] {
    let u = x as f64 / TEXTURE_WIDTH as f64;
    let v = y as f64 / TEXTURE_HEIGHT as f64;
    let rib = (x as f64 / 9.0 * std::f64::consts::PI).sin();
    let cloud = fbm(u * 2.0, v, 2) * 0.4;
    let attenuation = 0.9 + rib * 0.08;
    let highlight = rib.max(0.0).powf(12.0) * 0.12;
    let base = [0.98 * (1.0 - u) + 0.7 * u,
                0.7 * (1.0 - u) + u,
                0.84 * (1.0 - u) + 0.8 * u];
    let cloud_tint = [1.0, 0.95, 0.9];
    std::array::from_fn(|i| (base[i] * (1.0 - cloud) + cloud_tint[i] * cloud) * attenuation + highlight)
}

fn paper_rgb(x: usize, y: usize) -> [f64; 3] {
    let u = x as f64 / TEXTURE_WIDTH as f64;
    let v = y as f64 / TEXTURE_HEIGHT as f64;
    let variation = (fbm(u * 60.0, v * 6.0, 31) - 0.5) * 0.08;
    [0.92 + variation, 0.91 + variation, 0.88 + variation]
}

fn sand_rgb(x: usize, y: usize) -> [f64; 3] {
    let u = x as f64 / TEXTURE_WIDTH as f64;
    let v = y as f64 / TEXTURE_HEIGHT as f64;
    let ridge = ((14.0 * v + 6.0 * fbm(5.0 * u, 3.0 * v, 5) + 0.8 * (9.0 * u).sin())
        * std::f64::consts::PI).sin().abs().powf(18.0) * 0.55;
    let base = [0.95 * (1.0 - v) + 0.9 * v,
                0.87 * (1.0 - v) + 0.76 * v,
                0.76 * (1.0 - v) + 0.63 * v];
    let ridge_colour = [0.78, 0.62, 0.48];
    std::array::from_fn(|i| base[i] * (1.0 - ridge) + ridge_colour[i] * ridge)
}

fn opart_rgb(x: usize, y: usize) -> [f64; 3] {
    let u = x as f64 / TEXTURE_WIDTH as f64;
    let v = y as f64 / TEXTURE_HEIGHT as f64;
    let warp = (2.0 * u + 3.0 * v).sin() * 0.08 + fbm(1.5 * u, v, 151) * 0.1;
    let band = (((u + warp) * 260.0).sin() * 0.5 + 0.5).powi(3) * 0.75;
    let dark = [0.16, 0.16, 0.19];
    let light = [0.86, 0.84, 0.80];
    std::array::from_fn(|channel| dark[channel] * (1.0 - band) + light[channel] * band)
}

fn mist_rgb(x: usize, y: usize) -> [f64; 3] {
    let u = x as f64 / TEXTURE_WIDTH as f64;
    let v = y as f64 / TEXTURE_HEIGHT as f64;
    let n = fbm(4.0 * u, 3.0 * v, 11);
    let edge = (u - 0.6).max(0.0);
    let dark = [0.80, 0.93, 0.91];
    let light = [0.97, 0.99, 1.0];
    let edge_colour = [0.70, 0.84, 0.95];
    std::array::from_fn(|i| (dark[i] * (1.0 - n) + light[i] * n) * (1.0 - edge) + edge_colour[i] * edge)
}

fn silk_rgb(x: usize, y: usize) -> [f64; 3] {
    let u = x as f64 / TEXTURE_WIDTH as f64;
    let v = y as f64 / TEXTURE_HEIGHT as f64;
    let n = fbm(1.2 * u, 40.0 * v, 21);
    let wave = ((1.6 * u + 0.4 * v) * std::f64::consts::PI).sin().powi(2) * 0.7;
    let base = [0.88, 0.82, 0.72];
    let light = [1.0, 0.97, 0.9];
    std::array::from_fn(|i| base[i] * (1.0 - wave) + light[i] * wave + (n - 0.5) * 0.12)
}

fn ripple_rgb(x: usize, y: usize) -> [f64; 3] {
    let u = x as f64 / TEXTURE_WIDTH as f64;
    let v = y as f64 / TEXTURE_HEIGHT as f64;
    let r1 = ((3.7 * (u - 0.25)).powi(2) + (v - 0.9).powi(2)).sqrt();
    let r2 = ((3.7 * (u - 0.78)).powi(2) + (v - 1.1).powi(2)).sqrt();
    let wave = 0.5 + 0.35 * ((38.0 * r1).sin() * (-1.2 * r1).exp() + (38.0 * r2).sin() * (-1.2 * r2).exp());
    let dark = [0.10, 0.38, 0.66];
    let light = [0.50, 0.80, 0.98];
    std::array::from_fn(|i| dark[i] * (1.0 - wave) + light[i] * wave)
}

fn prism_rgb(x: usize, y: usize) -> [f64; 3] {
    let u = x as f64 / TEXTURE_WIDTH as f64;
    let v = y as f64 / TEXTURE_HEIGHT as f64;
    let phase = 6.0 * (1.4 * u + 0.6 * v + 0.3 * fbm(2.0 * u, 2.0 * v, 9));
    [0.8 + 0.18 * phase.sin(), 0.82 + 0.16 * (phase + 2.1).sin(), 0.88 + 0.12 * (phase + 4.2).sin()]
}

fn topo_rgb(x: usize, y: usize) -> [f64; 3] {
    let u = x as f64 / TEXTURE_WIDTH as f64;
    let v = y as f64 / TEXTURE_HEIGHT as f64;
    let n = 12.0 * fbm(3.2 * u, 1.6 * v, 41);
    let line = (1.0 - 2.0 * (n.fract() - 0.5).abs()).max(0.0).powi(22) * 0.8;
    let top = [0.04, 0.20, 0.24];
    let bottom = [0.07, 0.34, 0.38];
    let contour = [0.55, 0.92, 0.86];
    std::array::from_fn(|i| (top[i] * (1.0 - v) + bottom[i] * v) * (1.0 - line) + contour[i] * line)
}

fn sunset_rgb(x: usize, y: usize) -> [f64; 3] {
    let u = x as f64 / TEXTURE_WIDTH as f64;
    let v = y as f64 / TEXTURE_HEIGHT as f64;
    let t = v + (fbm(2.0 * u, v, 91) - 0.5) * 0.2;
    let (a, b, position) = if t < 0.5 {
        ([0.42, 0.26, 0.62], [0.98, 0.42, 0.52], 2.0 * t)
    } else {
        ([0.98, 0.42, 0.52], [1.0, 0.62, 0.36], 2.0 * (t - 0.5))
    };
    let radius = ((3.7 * (u - 0.62)).powi(2) + (v - 1.0).powi(2)).sqrt();
    let sun = (1.0 - 2.0 * radius).max(0.0).powi(2);
    let sun_colour = [1.0, 0.90, 0.62];
    std::array::from_fn(|i| (a[i] * (1.0 - position) + b[i] * position) * (1.0 - sun) + sun_colour[i] * sun)
}

fn marble_rgb(x: usize, y: usize) -> [f64; 3] {
    let u = x as f64 / TEXTURE_WIDTH as f64;
    let v = y as f64 / TEXTURE_HEIGHT as f64;
    let vein = ((7.0 * u + 3.0 * v + 6.0 * fbm(4.0 * u, 2.0 * v, 51)) * std::f64::consts::PI * 0.5).sin().abs().powf(0.12);
    let n = fbm(8.0 * u, 4.0 * v, 52);
    let dark = (1.0 - vein) * 0.9;
    let base = [0.96, 0.95, 0.93];
    let mottled = [0.90, 0.89, 0.88];
    let vein_colour = [0.62, 0.58, 0.52];
    std::array::from_fn(|i| (base[i] * (1.0 - n) + mottled[i] * n) * (1.0 - dark) + vein_colour[i] * dark)
}

fn holo_rgb(x: usize, y: usize) -> [f64; 3] {
    let u = x as f64 / TEXTURE_WIDTH as f64;
    let v = y as f64 / TEXTURE_HEIGHT as f64;
    let phase = 5.0 * (2.0 * u + 1.6 * fbm(3.0 * u, 3.0 * v, 131));
    let n = fbm(6.0 * u, 4.0 * v, 132);
    let white = 0.5 * n * n;
    let colour = [0.78 + 0.2 * phase.sin(), 0.80 + 0.18 * (phase + 2.3).sin(), 0.86 + 0.14 * (phase + 4.4).sin()];
    std::array::from_fn(|i| colour[i] * (1.0 - white) + white)
}

fn watercolor_rgb(x: usize, y: usize) -> [f64; 3] {
    let u = x as f64 / TEXTURE_WIDTH as f64;
    let v = y as f64 / TEXTURE_HEIGHT as f64;
    let n = 3.0 * fbm(3.5 * u, 2.5 * v, 61);
    let edge = (1.0 - 2.0 * (n - n.round()).abs()).max(0.0).powi(10) * 0.6;
    let palette = [[0.98, 0.80, 0.78], [0.78, 0.86, 0.98], [0.86, 0.94, 0.82], [0.99, 0.92, 0.76]];
    let colour = palette[(n as usize) % palette.len()];
    let tint = [0.2475, 0.245, 0.24];
    std::array::from_fn(|i| (colour[i] * 0.75 + tint[i]) * (1.0 - edge) + colour[i] * 0.82 * edge)
}

fn matcha_rgb(x: usize, y: usize) -> [f64; 3] {
    let u = x as f64 / TEXTURE_WIDTH as f64;
    let v = y as f64 / TEXTURE_HEIGHT as f64;
    let noise = (fbm(40.0 * u, 5.0 * v, 161) - 0.5) * 0.08;
    let top = [0.78, 0.86, 0.66];
    let bottom = [0.60, 0.74, 0.50];
    std::array::from_fn(|i| top[i] * (1.0 - v) + bottom[i] * v + noise)
}

fn ember_rgb(x: usize, y: usize) -> [f64; 3] {
    let u = x as f64 / TEXTURE_WIDTH as f64;
    let v = y as f64 / TEXTURE_HEIGHT as f64;
    let heat = fbm(5.0 * u, 3.0 * v - 0.2, 121).powf(2.5) * (0.9 * v + 0.4);
    let glow = (heat * 1.8).min(1.0);
    let hot = (heat * 2.2 - 1.0).max(0.0);
    let dark = [0.08, 0.02, 0.02];
    let orange = [0.85, 0.22, 0.05];
    let highlight = [1.0, 0.72, 0.30];
    std::array::from_fn(|i| (dark[i] * (1.0 - glow) + orange[i] * glow) * (1.0 - hot) + highlight[i] * hot)
}

fn neon_rgb(x: usize, y: usize) -> [f64; 3] {
    let u = x as f64 / TEXTURE_WIDTH as f64;
    let v = y as f64 / TEXTURE_HEIGHT as f64;
    let horizon = (1.0 - 3.0 * (v - 0.45).abs()).max(0.0);
    let sky = [0.07, 0.03, 0.15];
    let horizon_colour = [0.55, 0.10, 0.45];
    let base: [f64; 3] = std::array::from_fn(|i| sky[i] * (1.0 - horizon) + horizon_colour[i] * horizon);
    if v <= 0.45 { return base; }
    let perspective = (v - 0.45) / 0.55;
    let depth = perspective.max(0.05);
    let gx = 3.0 * (u - 0.5) / depth;
    let gy = 2.0 / depth;
    let vertical = (1.0 - 10.0 * (gx - gx.round()).abs()).max(0.0).powi(2);
    let horizontal = (1.0 - 6.0 * (gy - gy.round()).abs()).max(0.0).powi(2);
    let grid = perspective * vertical.max(horizontal);
    let grid_colour = [0.25, 0.95, 1.0];
    std::array::from_fn(|i| base[i] * (1.0 - grid) + grid_colour[i] * grid)
}

fn caustics_rgb(x: usize, y: usize) -> [f64; 3] {
    let u = x as f64 / TEXTURE_WIDTH as f64;
    let v = y as f64 / TEXTURE_HEIGHT as f64;
    let a = fbm(7.0 * u, 3.0 * v, 101);
    let b = fbm(7.0 * u + 3.1, 3.0 * v + 1.7, 102);
    let light = (1.0 - 9.0 * (a - b).abs()).max(0.0).powi(3) * 0.85;
    let top = [0.12, 0.62, 0.70];
    let bottom = [0.20, 0.78, 0.80];
    let reflection = [0.88, 1.0, 0.96];
    std::array::from_fn(|i| (top[i] * (1.0 - v) + bottom[i] * v) * (1.0 - light) + reflection[i] * light)
}

fn lowpoly_rgb(x: usize, y: usize) -> [f64; 3] {
    let u = x as f64 / TEXTURE_WIDTH as f64;
    let gx = x as f64 / 48.0;
    let gy = y as f64 / 33.6;
    let cell_x = gx.floor() as i64;
    let cell_y = gy.floor() as i64;
    let triangle = if gx.fract() + gy.fract() < 1.0 { 1 } else { 0 };
    let shade = 0.75 + 0.4 * hash(cell_x * 2 + triangle, cell_y, 141);
    let left = [0.28, 0.36, 0.66];
    let right = [0.62, 0.42, 0.78];
    std::array::from_fn(|i| (left[i] * (1.0 - u) + right[i] * u) * shade)
}

fn terrazzo_rgb(x: usize, y: usize) -> [f64; 3] {
    let cell_x = (x / 26) as i64;
    let cell_y = (y / 26) as i64;
    let center_x = (cell_x as f64 + 0.1 + 0.8 * hash(cell_x, cell_y, 81)) * 26.0;
    let center_y = (cell_y as f64 + 0.1 + 0.8 * hash(cell_x, cell_y, 82)) * 26.0;
    let radius = 3.0 + 8.0 * hash(cell_x, cell_y, 83);
    let distortion = (value_noise(x as f64 * 0.3, y as f64 * 0.3, 84) - 0.5) * 4.0;
    let distance = (x as f64 - center_x).abs() + 1.3 * (y as f64 - center_y).abs() + distortion;
    let palette = [[0.93, 0.55, 0.44], [0.36, 0.55, 0.52], [0.96, 0.78, 0.46], [0.55, 0.60, 0.82]];
    let index = ((hash(cell_x, cell_y, 85) * 3.99) as usize).min(3);
    if distance < radius { palette[index] } else { [0.96, 0.93, 0.88] }
}

fn cosmos_rgb(x: usize, y: usize) -> [f64; 3] {
    let u = x as f64 / TEXTURE_WIDTH as f64;
    let v = y as f64 / TEXTURE_HEIGHT as f64;
    let nebula = 1.4 * fbm(3.0 * u, 2.0 * v, 111).powf(2.2);
    let cloud = 1.2 * fbm(2.0 * u + 5.0, 3.0 * v, 112).powi(3);
    let dark = [0.03, 0.03, 0.10];
    let purple = [0.40, 0.16, 0.55];
    let blue = [0.10, 0.45, 0.70];
    let mut colour: [f64; 3] = std::array::from_fn(|i| (dark[i] * (1.0 - nebula) + purple[i] * nebula) * (1.0 - cloud) + blue[i] * cloud);
    if hash(x as i64, y as i64, 113) > 0.9975 {
        colour = colour.map(|channel| 0.9 + channel * 0.1);
    }
    colour
}

#[derive(Clone, Copy)]
struct BokehLight { x: f64, y: f64, radius: f64, opacity: f64 }

fn bokeh_lights() -> [BokehLight; 26] {
    // shortcut: the reference initializes this generator from Swift's
    // per-process randomized hash; use a stable seed for a stable background.
    let mut state = 0x42_4f_4b_45_49u64;
    let mut next = || {
        state = state.wrapping_mul(0x5851_f42d_4c95_7f2d).wrapping_add(0x1405_7b7e_f767_814f);
        ((state >> 33) & 0x00ff_ffff) as f64 / 16_777_215.0
    };
    std::array::from_fn(|_| BokehLight { x: next(), y: next(), radius: 0.04 + 0.12 * next(), opacity: 0.25 + 0.6 * next() })
}

fn bokeh_rgb(x: usize, y: usize, lights: &[BokehLight]) -> [f64; 3] {
    let u = x as f64 / TEXTURE_WIDTH as f64;
    let v = y as f64 / TEXTURE_HEIGHT as f64;
    let top = [0.16, 0.12, 0.30];
    let bottom = [0.85, 0.45, 0.40];
    let mut colour: [f64; 3] = std::array::from_fn(|i| top[i] * (1.0 - v) + bottom[i] * v);
    for light in lights {
        let distance = ((3.7 * (u - light.x)).powi(2) + (v - light.y).powi(2)).sqrt();
        let opacity = ((light.radius - distance) / (0.18 * light.radius)).clamp(0.0, 1.0) * light.opacity * 0.5;
        let tint = [1.0, 0.86, 0.62];
        for i in 0..3 { colour[i] = colour[i] * (1.0 - opacity) + tint[i] * opacity; }
    }
    colour
}

fn aurora_rgb(x: usize, y: usize) -> [f64; 3] {
    let u = x as f64 / TEXTURE_WIDTH as f64;
    let v = y as f64 / TEXTURE_HEIGHT as f64;
    let shift = 0.25 * fbm(3.0 * u, 2.0 * v, 3);
    let weight = |cx: f64, cy: f64, radius: f64| {
        let distance = ((3.7 * (u - cx)).powi(2) + (v - cy).powi(2)).sqrt();
        let t = (1.0 - distance / radius).clamp(0.0, 1.0);
        t * t * (3.0 - 2.0 * t)
    };
    let layers = [
        (0.10 + shift, 0.70, 0.75, [1.0, 0.74, 0.62]),
        (0.38, 0.95, 0.70, [0.78, 0.70, 1.0]),
        (0.66 - shift, 0.60, 0.80, [0.58, 0.84, 1.0]),
        (0.92, 0.95, 0.65, [0.68, 0.96, 0.84]),
    ];
    let mut colour = [0.97, 0.91, 0.94];
    for (cx, cy, radius, tint) in layers {
        let amount = weight(cx, cy, radius);
        for i in 0..3 { colour[i] = colour[i] * (1.0 - amount) + tint[i] * amount; }
    }
    colour
}

fn grain(x: usize, y: usize) -> f64 {
    let seed = 0x3_7fff_fff9u64
        .wrapping_add((y as u64).wrapping_mul(0x27d4_eb2f))
        .wrapping_add((x as u64).wrapping_mul(0x1656_67b1));
    let mixed = (seed ^ (seed >> 13)).wrapping_mul(0x4bf1_9f61) as u32;
    let bits = (mixed ^ (mixed >> 16)) & 0xffff;
    (f64::from(bits) / 65535.0 - 0.5) * 0.045
}

/// Fill the caller-owned buffer with RGBA pixels. Returns 0 for an invalid
/// buffer or texture kind. Kinds 1–24 denote halftone, linen, fluted, paper,
/// sand, op art, mist, silk, ripple, prism, topography, sunset, marble, holo,
/// watercolor, matcha, ember, neon, caustics, low poly, terrazzo, cosmos, bokeh and aurora.
///
/// # Safety
/// `out` must point to at least `len` writable bytes, and not alias any other
/// memory accessed during this call.
#[no_mangle]
pub unsafe extern "C" fn rium_home_texture_rgba(kind: i32, out: *mut u8, len: usize) -> i32 {
    if !(1..=24).contains(&kind) || out.is_null() || len < TEXTURE_BYTES {
        return 0;
    }
    let bytes = std::slice::from_raw_parts_mut(out, TEXTURE_BYTES);
    let bokeh = (kind == 23).then(bokeh_lights);
    for y in 0..TEXTURE_HEIGHT {
        for x in 0..TEXTURE_WIDTH {
            let rgb = match kind {
                1 => halftone_rgb(x, y),
                2 => linen_rgb(x, y),
                3 => fluted_rgb(x, y),
                4 => paper_rgb(x, y),
                5 => sand_rgb(x, y),
                6 => opart_rgb(x, y),
                7 => mist_rgb(x, y),
                8 => silk_rgb(x, y),
                9 => ripple_rgb(x, y),
                10 => prism_rgb(x, y),
                11 => topo_rgb(x, y),
                12 => sunset_rgb(x, y),
                13 => marble_rgb(x, y),
                14 => holo_rgb(x, y),
                15 => watercolor_rgb(x, y),
                16 => matcha_rgb(x, y),
                17 => ember_rgb(x, y),
                18 => neon_rgb(x, y),
                19 => caustics_rgb(x, y),
                20 => lowpoly_rgb(x, y),
                21 => terrazzo_rgb(x, y),
                22 => cosmos_rgb(x, y),
                23 => bokeh_rgb(x, y, bokeh.as_ref().unwrap()),
                24 => aurora_rgb(x, y),
                _ => unreachable!(),
            };
            // The reference uses a stronger grain for paper than for the other textures.
            let noise = grain(x, y) * if kind == 4 { 0.1 / 0.045 } else { 1.0 };
            let offset = (y * TEXTURE_WIDTH + x) * 4;
            for channel in 0..3 {
                bytes[offset + channel] = ((rgb[channel] + noise).clamp(0.0, 1.0) * 255.0) as u8;
            }
            bytes[offset + 3] = 255;
        }
    }
    1
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn halftone_uses_reference_cells_and_colour_gradient() {
        assert_eq!(halftone_rgb(0, 0), [1.0, 0.86, 0.82]);
        assert_eq!(halftone_rgb(5, 5), [0.98 * (1.0 - 5.0 / 260.0) + 0.93 * (5.0 / 260.0), 0.47 * (1.0 - 5.0 / 260.0) + 0.36 * (5.0 / 260.0), 0.42 * (1.0 - 5.0 / 260.0) + 0.52 * (5.0 / 260.0)]);
        assert_eq!(halftone_rgb(959, 0), [1.0, 0.86, 0.82]);
        assert!(grain(1, 2).abs() <= 0.0225);
    }

    #[test]
    fn texture_noise_is_continuous_and_colours_are_finite() {
        let at_edge = value_noise(1.0, 3.25, 71);
        assert!((at_edge - value_noise(1.0 - 1e-8, 3.25, 71)).abs() < 1e-8);
        assert!((at_edge - value_noise(1.0 + 1e-8, 3.25, 71)).abs() < 1e-8);
        for (x, y) in [(0, 0), (50, 12), (959, 259)] {
            for value in linen_rgb(x, y).into_iter().chain(fluted_rgb(x, y)).chain(paper_rgb(x, y)).chain(sand_rgb(x, y)).chain(opart_rgb(x, y)).chain(mist_rgb(x, y)).chain(silk_rgb(x, y)).chain(ripple_rgb(x, y)).chain(prism_rgb(x, y)).chain(topo_rgb(x, y)).chain(sunset_rgb(x, y)).chain(marble_rgb(x, y)).chain(holo_rgb(x, y)).chain(watercolor_rgb(x, y)).chain(matcha_rgb(x, y)).chain(ember_rgb(x, y)).chain(neon_rgb(x, y)).chain(caustics_rgb(x, y)).chain(lowpoly_rgb(x, y)).chain(terrazzo_rgb(x, y)).chain(cosmos_rgb(x, y)).chain(bokeh_rgb(x, y, &bokeh_lights())).chain(aurora_rgb(x, y)) {
                assert!(value.is_finite() && (0.0..=1.2).contains(&value));
            }
        }
    }

    #[test]
    fn ffi_rejects_invalid_output_without_writing() {
        let mut byte = 99;
        unsafe {
            assert_eq!(rium_home_texture_rgba(1, std::ptr::null_mut(), TEXTURE_BYTES), 0);
            assert_eq!(rium_home_texture_rgba(1, &mut byte, 1), 0);
            assert_eq!(rium_home_texture_rgba(0, &mut byte, 1), 0);
        }
        assert_eq!(byte, 99);
    }
}
