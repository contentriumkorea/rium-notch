//! City weather lookup using MET Norway Locationforecast. No automatic location lookup.
use serde_json::{json, Value};
use std::process::Command;

fn parse(data: &[u8]) -> Result<Value, String> {
    let root: Value = serde_json::from_slice(data).map_err(|_| "날씨 응답을 읽을 수 없습니다")?;
    let slot = root.pointer("/properties/timeseries/0").ok_or("날씨 예보가 비어 있습니다")?;
    let details = slot.pointer("/data/instant/details").ok_or("날씨 수치를 찾을 수 없습니다")?;
    let temperature = details.get("air_temperature").and_then(Value::as_f64).filter(|n| n.is_finite()).ok_or("기온을 찾을 수 없습니다")?;
    let symbol = slot.pointer("/data/next_1_hours/summary/symbol_code").and_then(Value::as_str).unwrap_or("unknown");
    // Keep enough hourly slots to remain useful during the required cache
    // interval. Period precipitation is an amount over the following hour,
    // not a probability or a minute-by-minute nowcast.
    let hourly: Vec<Value> = root.pointer("/properties/timeseries").and_then(Value::as_array)
        .into_iter().flatten().take(16).filter_map(|hour| {
            let time = hour.get("time")?.as_str()?;
            let temperature = hour.pointer("/data/instant/details/air_temperature")?.as_f64().filter(|n| n.is_finite())?;
            let symbol = hour.pointer("/data/next_1_hours/summary/symbol_code").and_then(Value::as_str);
            let precipitation = hour.pointer("/data/next_1_hours/details/precipitation_amount")
                .and_then(Value::as_f64).filter(|n| n.is_finite() && *n >= 0.0);
            Some(json!({"time":time,"temperature":temperature,"symbol":symbol,"precipitation":precipitation}))
        }).collect();
    Ok(json!({"temperature": temperature, "symbol": symbol, "wind": details.get("wind_speed"), "time": slot.get("time"), "source": "MET Norway", "hourly":hourly}))
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
}
