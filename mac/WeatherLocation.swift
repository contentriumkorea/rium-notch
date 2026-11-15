import AppKit
import CoreLocation

// A location request is started only by the user's weather button.
final class WeatherLocation: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var completion: ((Result<CLLocation, StringError>) -> Void)?
    private var timeout: DispatchWorkItem?
    private var requestedLocation = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }
    func request(_ completion: @escaping (Result<CLLocation, StringError>) -> Void) {
        cancel(); self.completion = completion
        let timeout = DispatchWorkItem { [weak self] in self?.finish(.failure(StringError("현재 위치를 확인하지 못했습니다"))) }
        self.timeout = timeout; DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: timeout)
        checkAuthorization()
    }
    func cancel() { timeout?.cancel(); timeout = nil; completion = nil; requestedLocation = false; manager.stopUpdatingLocation() }
    private func finish(_ result: Result<CLLocation, StringError>) {
        guard let completion = completion else { return }
        cancel(); completion(result)
    }
    private func checkAuthorization() {
        guard completion != nil else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            NSApp.activate(ignoringOtherApps: true)
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            if !requestedLocation { requestedLocation = true; manager.requestLocation() }
        case .restricted, .denied:
            finish(.failure(StringError("위치 권한이 필요합니다")))
        @unknown default:
            finish(.failure(StringError("위치 권한 상태를 확인할 수 없습니다")))
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { checkAuthorization() }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last(where: { $0.horizontalAccuracy >= 0 && abs($0.timestamp.timeIntervalSinceNow) < 300 }) else {
            finish(.failure(StringError("현재 위치를 확인하지 못했습니다"))); return
        }
        finish(.success(location))
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(.failure(StringError("현재 위치를 확인하지 못했습니다")))
    }
}

struct StringError: Error { let message: String; init(_ message: String) { self.message = message } }
