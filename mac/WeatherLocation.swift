import AppKit
import CoreLocation

func weatherLocationCallbackIsCurrent(_ callback: AnyObject, active: AnyObject?) -> Bool {
    callback === active
}

// The user enables current-location weather; later stale refreshes may request it again.
final class WeatherLocation: NSObject, CLLocationManagerDelegate {
    static let permissionRequiredMessage = "위치 권한이 필요합니다"
    private var manager: CLLocationManager?
    private var completion: ((Result<CLLocation, StringError>) -> Void)?
    private var timeout: DispatchWorkItem?
    private var requestedLocation = false
    private var requestedAuthorization = false
    private var allowAuthorizationPrompt = false

    func request(allowAuthorizationPrompt: Bool, _ completion: @escaping (Result<CLLocation, StringError>) -> Void) {
        cancel(); self.completion = completion
        self.allowAuthorizationPrompt = allowAuthorizationPrompt
        let manager = CLLocationManager()
        self.manager = manager
        scheduleTimeout(for: manager, after: 25)
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.delegate = self
    }

    private func scheduleTimeout(for manager: CLLocationManager, after delay: TimeInterval) {
        timeout?.cancel()
        let timeout = DispatchWorkItem { [weak self, weak manager] in
            guard let self = self, let manager = manager,
                  weatherLocationCallbackIsCurrent(manager, active: self.manager) else { return }
            self.finish(.failure(StringError("현재 위치를 확인하지 못했습니다")))
        }
        self.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: timeout)
    }
    func cancel() {
        timeout?.cancel(); timeout = nil; completion = nil; requestedLocation = false
        requestedAuthorization = false
        manager?.delegate = nil; manager?.stopUpdatingLocation(); manager = nil
    }
    private func finish(_ result: Result<CLLocation, StringError>) {
        guard let completion = completion else { return }
        cancel(); completion(result)
    }
    private func checkAuthorization(_ manager: CLLocationManager) {
        guard completion != nil, weatherLocationCallbackIsCurrent(manager, active: self.manager) else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            guard allowAuthorizationPrompt else {
                finish(.failure(StringError(Self.permissionRequiredMessage))); return
            }
            guard !requestedAuthorization else { return }
            requestedAuthorization = true
            NSApp.activate(ignoringOtherApps: true)
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            guard !requestedLocation else { return }
            requestedLocation = true
            scheduleTimeout(for: manager, after: 12)
            manager.requestLocation()
        case .restricted, .denied:
            finish(.failure(StringError(Self.permissionRequiredMessage)))
        @unknown default:
            finish(.failure(StringError("위치 권한 상태를 확인할 수 없습니다")))
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { checkAuthorization(manager) }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard weatherLocationCallbackIsCurrent(manager, active: self.manager) else { return }
        guard let location = locations.last(where: { $0.horizontalAccuracy >= 0 && abs($0.timestamp.timeIntervalSinceNow) < 300 }) else {
            finish(.failure(StringError("현재 위치를 확인하지 못했습니다"))); return
        }
        finish(.success(location))
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard weatherLocationCallbackIsCurrent(manager, active: self.manager) else { return }
        let message = (error as? CLError)?.code == .denied ? Self.permissionRequiredMessage : "현재 위치를 확인하지 못했습니다"
        finish(.failure(StringError(message)))
    }
}

struct StringError: Error { let message: String; init(_ message: String) { self.message = message } }
