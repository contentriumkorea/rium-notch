//! City weather lookup using MET Norway Locationforecast. No automatic location lookup.
use serde_json::{json, Value};
use std::process::Command;

/// Refresh stale forecasts after a bounded retry interval, never during a selection.
pub fn may_auto_refresh(in_progress: bool, since_attempt: f64, cache_age: f64) -> bool {
    !in_progress && since_attempt.is_finite() && cache_age.is_finite()
        && since_attempt >= 900.0 && cache_age >= 10_800.0
}

#[no_mangle]
pub extern "C" fn rium_weather_may_auto_refresh(in_progress: i32, since_attempt: f64, cache_age: f64) -> i32 {
    if !(0..=1).contains(&in_progress) { return -1; }
    i32::from(may_auto_refresh(in_progress == 1, since_attempt, cache_age))
}

#[no_mangle]
pub extern "C" fn rium_weather_dashboard_gauge(temperature: f64) -> f64 {
    if !temperature.is_finite() {
        return f64::NAN;
    }
    ((temperature.round() + 10.0) / 50.0).clamp(0.0, 1.0)
}

// The source uses the condition symbol's category; MET codes have different names.
// shortcut: polar-twilight artwork is inferred until original mapping is compared.
fn illustration(symbol: &str) -> Option<i32> {
    let value = symbol.to_ascii_lowercase();
    if value.contains("thunder") { Some(5) }
    else if value.contains("snow") || value.contains("sleet") { Some(4) }
    else if value.contains("rain") || value.contains("drizzle") { Some(3) }
    else if value.contains("fog") || value.contains("haze") { Some(6) }
    else if value.contains("wind") { Some(7) }
    else if value.contains("cloud") || value.contains("fair") { Some(2) }
    else if value.contains("clear") { Some(if value.contains("night") { 1 } else { 0 }) }
    else { None }
}

#[no_mangle]
pub unsafe extern "C" fn rium_weather_illustration(bytes: *const u8, len: usize) -> i32 {
    if bytes.is_null() || len == 0 || len > 128 { return -1; }
    let Ok(symbol) = std::str::from_utf8(std::slice::from_raw_parts(bytes, len)) else { return -1; };
    illustration(symbol).unwrap_or(-1)
}

// shortcut: maps MET symbols to the reference's sky categories; its WeatherKit
// symbol-to-sky mapping and polar twilight still need visual comparison.
fn sky_photograph(symbol: &str) -> Option<i32> {
    let value = symbol.to_ascii_lowercase();
    if value.contains("thunder") { Some(7) }
    else if value.contains("snow") || value.contains("sleet") { Some(6) }
    else if value.contains("rain") || value.contains("drizzle") { Some(5) }
    else if value.contains("fog") || value.contains("haze") { Some(4) }
    else if value.contains("partlycloudy") || value.contains("fair") { Some(3) }
    else if value.contains("cloud") { Some(2) }
    else if value.contains("clear") { Some(if value.contains("night") { 1 } else { 0 }) }
    else { None }
}

#[no_mangle]
pub unsafe extern "C" fn rium_weather_sky_photograph(bytes: *const u8, len: usize) -> i32 {
    if bytes.is_null() || len == 0 || len > 128 { return -1; }
    let Ok(symbol) = std::str::from_utf8(std::slice::from_raw_parts(bytes, len)) else { return -1; };
    sky_photograph(symbol).unwrap_or(-1)
}

/// Estimated wind chill or heat index in °C, where the NWS formula applies.
/// This is not a provider-supplied apparent temperature and does not account for sun.
/// https://www.weather.gov/safety/cold-faqs
/// https://www.weather.gov/ctp/heat
// shortcut: The original app's weather provider and apparent-temperature method are not recovered.
pub fn feels_like_estimate(temp_c: f64, wind_mps: f64, humidity: f64) -> Option<f64> {
    if !temp_c.is_finite() || !(-90.0..=60.0).contains(&temp_c) { return None; }
    let t = temp_c * 1.8 + 32.0;
    let result_f = if t <= 50.0 {
        if !wind_mps.is_finite() || wind_mps < 0.0 || wind_mps > 100.0 { return None; }
        let speed = wind_mps * 2.236_936_292_054_4;
        if speed <= 3.0 { return None; }
        let v = speed.powf(0.16);
        35.74 + 0.6215 * t - 35.75 * v + 0.4275 * t * v
    } else if (80.0..=112.0).contains(&t) {
        if !humidity.is_finite() || !(0.0..=100.0).contains(&humidity) { return None; }
        let r = humidity;
        let simple = 0.5 * (t + 61.0 + (t - 68.0) * 1.2 + r * 0.094);
        let mean = (simple + t) / 2.0;
        if mean < 80.0 { mean } else {
            let mut hi = -42.379 + 2.04901523 * t + 10.14333127 * r - 0.22475541 * t * r
                - 0.00683783 * t * t - 0.05481717 * r * r + 0.00122874 * t * t * r
                + 0.00085282 * t * r * r - 0.00000199 * t * t * r * r;
            if r < 13.0 { hi -= (13.0 - r) / 4.0 * ((17.0 - (t - 95.0).abs()) / 17.0).sqrt(); }
            else if r > 85.0 && t <= 87.0 { hi += (r - 85.0) / 10.0 * (87.0 - t) / 5.0; }
            hi
        }
    } else { return None; };
    let result = (result_f - 32.0) / 1.8;
    result.is_finite().then_some(result)
}

#[no_mangle]
pub extern "C" fn rium_weather_feels_like(temp_c: f64, wind_mps: f64, humidity: f64) -> f64 {
    feels_like_estimate(temp_c, wind_mps, humidity).unwrap_or(f64::NAN)
}

// shortcut: Hourly model amounts and the provisional threshold cannot reproduce
// the reference's minute-level rain alerts; upgrade when that data is available.
fn precipitation_window(now: f64, updated: f64, times: &[f64], amounts: &[f64]) -> Option<f64> {
    if !now.is_finite() || !updated.is_finite() || !(0.0..10_800.0).contains(&(now - updated)) || times.len() != amounts.len() { return None; }
    let current = times.iter().position(|&time| time.is_finite() && time <= now && now < time + 3600.0)?;
    let current_amount = amounts[current];
    if !current_amount.is_finite() || !(0.0..0.1).contains(&current_amount) { return None; }
    for index in current + 1..times.len() {
        let (time, previous, amount) = (times[index], times[index - 1], amounts[index]);
        if !time.is_finite() || (time - previous - 3600.0).abs() > 1.0 || !amount.is_finite() || amount < 0.0 || time - now > 7200.0 { return None; }
        if amount >= 0.1 { return Some(time); }
    }
    None
}

#[no_mangle]
pub unsafe extern "C" fn rium_weather_precipitation_window(now: f64, updated: f64, times: *const f64, amounts: *const f64, count: usize, output: *mut f64) -> i32 {
    if times.is_null() || amounts.is_null() || output.is_null() || count == 0 || count > 96 { return -1; }
    let times = std::slice::from_raw_parts(times, count);
    let amounts = std::slice::from_raw_parts(amounts, count);
    match precipitation_window(now, updated, times, amounts) {
        Some(time) => { *output = time; 1 }
        None => 0,
    }
}

fn weather_symbol(slot: &Value) -> Option<&str> {
    slot.pointer("/data/next_1_hours/summary/symbol_code")
        .and_then(Value::as_str)
        .or_else(|| slot.pointer("/data/next_6_hours/summary/symbol_code").and_then(Value::as_str))
}

fn wind_and_humidity(details: &Value) -> (Option<f64>, Option<f64>) {
    let wind = details.get("wind_speed").and_then(Value::as_f64).filter(|n| n.is_finite() && *n >= 0.0);
    let humidity = details.get("relative_humidity").and_then(Value::as_f64).filter(|n| n.is_finite() && (0.0..=100.0).contains(n));
    (wind, humidity)
}

fn parse(data: &[u8]) -> Result<Value, String> {
    let root: Value = serde_json::from_slice(data).map_err(|_| "날씨 응답을 읽을 수 없습니다")?;
    let slot = root.pointer("/properties/timeseries/0").ok_or("날씨 예보가 비어 있습니다")?;
    let details = slot.pointer("/data/instant/details").ok_or("날씨 수치를 찾을 수 없습니다")?;
    let temperature = details.get("air_temperature").and_then(Value::as_f64).filter(|n| n.is_finite()).ok_or("기온을 찾을 수 없습니다")?;
    let symbol = weather_symbol(slot).unwrap_or("unknown");
    // Keep the provider's hourly and later, less frequent forecast samples.
    // One-hour precipitation remains an amount, not a probability or nowcast.
    let hourly: Vec<Value> = root.pointer("/properties/timeseries").and_then(Value::as_array)
        .into_iter().flatten().take(96).filter_map(|hour| {
            let time = hour.get("time")?.as_str()?;
            let details = hour.pointer("/data/instant/details")?;
            let temperature = details.get("air_temperature")?.as_f64().filter(|n| n.is_finite())?;
            let (wind, humidity) = wind_and_humidity(details);
            let precipitation = hour.pointer("/data/next_1_hours/details/precipitation_amount")
                .and_then(Value::as_f64).filter(|n| n.is_finite() && *n >= 0.0);
            Some(json!({"time":time,"temperature":temperature,"symbol":weather_symbol(hour),
                        "precipitation":precipitation,"wind":wind,"humidity":humidity}))
        }).collect();
    let (wind, humidity) = wind_and_humidity(details);
    Ok(json!({"temperature": temperature, "symbol": symbol, "wind": wind, "humidity": humidity, "time": slot.get("time"), "source": "MET Norway", "hourly":hourly}))
}

pub fn forecast(lat: f64, lon: f64) -> Result<Value, String> {
    if !lat.is_finite() || !lon.is_finite() || !(-90.0..=90.0).contains(&lat) || !(-180.0..=180.0).contains(&lon) {
        return Err("날씨 위치가 올바르지 않습니다".into());
    }
    let url = format!("https://api.met.no/weatherapi/locationforecast/2.0/compact?lat={lat:.4}&lon={lon:.4}");
    let output = Command::new("/usr/bin/curl")
        .args(["--fail", "--silent", "--show-error", "--max-time", "12", "--user-agent", "RiumNotch/0.1 (https://github.com/contentriumkorea)", "--url", &url])
        .output().map_err(|_| "날씨 연결을 시작할 수 없습니다")?;
    if !output.status.success() { return Err("날씨 서비스에 연결할 수 없습니다".into()); }
    if output.stdout.len() > 2_000_000 { return Err("날씨 응답이 너무 큽니다".into()); }
    parse(&output.stdout)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn dashboard_gauge_tracks_displayed_degrees_and_marks_missing_values() {
        assert_eq!(rium_weather_dashboard_gauge(-20.0), 0.0);
        assert_eq!(rium_weather_dashboard_gauge(-10.0), 0.0);
        assert_eq!(rium_weather_dashboard_gauge(0.0), 0.2);
        assert_eq!(rium_weather_dashboard_gauge(-0.5), 0.18);
        assert_eq!(rium_weather_dashboard_gauge(14.5), 0.5);
        assert_eq!(rium_weather_dashboard_gauge(15.0), 0.5);
        assert_eq!(rium_weather_dashboard_gauge(40.0), 1.0);
        assert_eq!(rium_weather_dashboard_gauge(45.0), 1.0);
        assert!(rium_weather_dashboard_gauge(f64::NAN).is_nan());
        assert!(rium_weather_dashboard_gauge(f64::INFINITY).is_nan());
    }

    #[test]
    fn stale_weather_retries_without_bypassing_cache_or_selection() {
        assert!(!may_auto_refresh(true, 900.0, 10_800.0));
        assert!(!may_auto_refresh(false, 899.0, 10_800.0));
        assert!(!may_auto_refresh(false, 900.0, 10_799.0));
        assert!(may_auto_refresh(false, 900.0, 10_800.0));
        assert!(!may_auto_refresh(false, f64::NAN, 10_800.0));
        assert_eq!(rium_weather_may_auto_refresh(2, 900.0, 10_800.0), -1);
    }
    #[test]
    fn precipitation_hint_requires_fresh_contiguous_known_hourly_data() {
        let times = [0.0, 3600.0, 7200.0];
        assert_eq!(precipitation_window(1800.0, 1700.0, &times, &[0.0, 0.0, 0.3]), Some(7200.0));
        assert_eq!(precipitation_window(1800.0, 1700.0, &times, &[0.0, f64::NAN, 0.3]), None);
        assert_eq!(precipitation_window(1800.0, 1700.0, &times, &[0.2, 0.0, 0.3]), None);
        assert_eq!(precipitation_window(1800.0, -9000.0, &times, &[0.0, 0.0, 0.3]), None);
        assert_eq!(precipitation_window(1800.0, 1700.0, &[0.0, 7200.0], &[0.0, 0.3]), None);
    }
    #[test]
    fn estimated_feels_like_respects_domain_and_missing_inputs() {
        let cold = feels_like_estimate(-6.666_666_666_7, 8.940_8, f64::NAN).unwrap();
        assert!((cold + 15.56).abs() < 0.2);
        let hot = feels_like_estimate(32.222_222_222_2, f64::NAN, 65.0).unwrap();
        assert!(hot > 39.0 && hot < 43.0);
        assert!(feels_like_estimate(15.0, 3.0, 50.0).is_none());
        assert!(feels_like_estimate(0.0, 0.0, 50.0).is_none());
        assert!(feels_like_estimate(30.0, 2.0, f64::NAN).is_none());
    }
    #[test]
    fn parses_forecast_and_rejects_missing_temperature() {
        let input = br#"{"properties":{"timeseries":[{"time":"2026-11-15T00:00:00Z","data":{"instant":{"details":{"air_temperature":12.5,"wind_speed":2.0}},"next_1_hours":{"summary":{"symbol_code":"clearsky_day"}}}}]}}"#;
        let v = parse(input).unwrap();
        assert_eq!(v["temperature"], 12.5);
        assert_eq!(v["symbol"], "clearsky_day");
        assert!(parse(br#"{"properties":{"timeseries":[]}}"#).is_err());
        assert!(forecast(f64::NAN, 0.0).is_err());
    }
    #[test]
    fn hourly_precipitation_keeps_missing_distinct_from_zero() {
        let input = br#"{"properties":{"timeseries":[
            {"time":"2026-11-15T00:00:00Z","data":{"instant":{"details":{"air_temperature":12.5}},"next_1_hours":{"summary":{"symbol_code":"rain"},"details":{"precipitation_amount":0.0}}}},
            {"time":"2026-11-15T01:00:00Z","data":{"instant":{"details":{"air_temperature":11.0}},"next_1_hours":{"summary":{"symbol_code":"cloudy"}}}},
            {"time":"2026-11-15T02:00:00Z","data":{"instant":{"details":{"air_temperature":10.0}},"next_1_hours":{"details":{"precipitation_amount":-1.0}}}},
            {"time":"2026-11-15T03:00:00Z","data":{"instant":{"details":{}}}}
        ]}}"#;
        let v = parse(input).unwrap();
        let hours = v["hourly"].as_array().unwrap();
        assert_eq!(hours.len(), 3);
        assert_eq!(hours[0]["precipitation"], 0.0);
        assert!(hours[1]["precipitation"].is_null());
        assert!(hours[2]["precipitation"].is_null());
    }
    #[test]
    fn current_humidity_and_wind_preserve_missing_and_reject_invalid() {
        let input = br#"{"properties":{"timeseries":[{"time":"2026-11-18T00:00:00Z","data":{"instant":{"details":{"air_temperature":12.0,"relative_humidity":72.0,"wind_speed":3.5}}}}]}}"#;
        let v = parse(input).unwrap();
        assert_eq!(v["humidity"], 72.0);
        assert_eq!(v["wind"], 3.5);
        assert_eq!(v["hourly"][0]["humidity"], 72.0);
        assert_eq!(v["hourly"][0]["wind"], 3.5);
        let invalid = br#"{"properties":{"timeseries":[{"time":"2026-11-18T00:00:00Z","data":{"instant":{"details":{"air_temperature":12.0,"relative_humidity":101.0,"wind_speed":-1.0}}}}]}}"#;
        let v = parse(invalid).unwrap();
        assert!(v["humidity"].is_null());
        assert!(v["wind"].is_null());
        assert!(v["hourly"][0]["humidity"].is_null());
        assert!(v["hourly"][0]["wind"].is_null());
    }
    #[test]
    fn six_hour_symbol_does_not_become_one_hour_rain() {
        let input = br#"{"properties":{"timeseries":[{"time":"2026-11-18T00:00:00Z","data":{"instant":{"details":{"air_temperature":12.0}},"next_6_hours":{"summary":{"symbol_code":"rain"},"details":{"precipitation_amount":5.0}}}}]}}"#;
        let v = parse(input).unwrap();
        assert_eq!(v["hourly"][0]["symbol"], "rain");
        assert!(v["hourly"][0]["precipitation"].is_null());
    }
    #[test]
    fn illustrated_weather_category_preserves_precipitation_priority_and_daylight() {
        assert_eq!(illustration("clearsky_day"), Some(0));
        assert_eq!(illustration("clearsky_night"), Some(1));
        assert_eq!(illustration("partlycloudy_night"), Some(2));
        assert_eq!(illustration("rainshowers_day"), Some(3));
        assert_eq!(illustration("sleet"), Some(4));
        assert_eq!(illustration("snowandthunder"), Some(5));
        assert_eq!(illustration("fog"), Some(6));
        assert_eq!(illustration("unknown"), None);
    }
    #[test]
    fn sky_photo_distinguishes_cloud_cover_daylight_and_storm() {
        assert_eq!(sky_photograph("clearsky_day"), Some(0));
        assert_eq!(sky_photograph("clearsky_night"), Some(1));
        assert_eq!(sky_photograph("cloudy"), Some(2));
        assert_eq!(sky_photograph("partlycloudy_day"), Some(3));
        assert_eq!(sky_photograph("fog"), Some(4));
        assert_eq!(sky_photograph("rainshowers_night"), Some(5));
        assert_eq!(sky_photograph("sleet"), Some(6));
        assert_eq!(sky_photograph("snowandthunder"), Some(7));
        assert_eq!(sky_photograph("unknown"), None);
    }
}
