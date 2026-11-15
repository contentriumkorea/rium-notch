import Foundation
import UserNotifications

protocol TimerNotificationBackend: AnyObject {
    func pending(_ completion: @escaping ([String]) -> Void)
    func remove(_ identifiers: [String])
    func add(identifier: String, after seconds: TimeInterval, title: String, completion: @escaping (Error?) -> Void)
}

final class SystemTimerNotificationBackend: TimerNotificationBackend {
    let center: UNUserNotificationCenter
    init(center: UNUserNotificationCenter) { self.center = center }
    func pending(_ completion: @escaping ([String]) -> Void) {
        center.getPendingNotificationRequests { completion($0.map(\.identifier)) }
    }
    func remove(_ identifiers: [String]) { center.removePendingNotificationRequests(withIdentifiers: identifiers) }
    func add(identifier: String, after seconds: TimeInterval, title: String, completion: @escaping (Error?) -> Void) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "설정한 시간이 끝났습니다."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger), withCompletionHandler: completion)
    }
}

// Calls are serialized on the main queue. Each request has a unique ID so an
// old asynchronous completion cannot remove a newer timer's notification.
final class TimerNotificationCoordinator {
    static let prefix = "app.rium.notch.focus-timer."
    private let backend: TimerNotificationBackend
    private var revision = 0
    var onError: ((String) -> Void)?
    init(backend: TimerNotificationBackend) { self.backend = backend }
    func replace(after seconds: TimeInterval?, title: String = "타이머 완료") {
        precondition(Thread.isMainThread)
        revision += 1
        let current = revision
        backend.pending { [weak self] identifiers in
            DispatchQueue.main.async {
                guard let self = self, self.revision == current else { return }
                self.backend.remove(identifiers.filter { $0.hasPrefix(Self.prefix) })
                guard let seconds = seconds, seconds.isFinite, seconds > 0 else { return }
                let id = Self.prefix + UUID().uuidString
                self.backend.add(identifier: id, after: seconds, title: title) { [weak self] error in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        if self.revision != current { self.backend.remove([id]); return }
                        if error != nil { self.onError?("타이머 알림을 예약하지 못했습니다") }
                    }
                }
            }
        }
    }
}

final class TimerNotificationService: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    lazy var coordinator = TimerNotificationCoordinator(backend: SystemTimerNotificationBackend(center: center))
    override init() { super.init(); center.delegate = self }
    func authorization(_ completion: @escaping (Bool) -> Void) {
        center.getNotificationSettings { settings in
            let status = settings.authorizationStatus
            DispatchQueue.main.async { completion(status == .authorized || status == .provisional) }
        }
    }
    func requestAuthorization(_ completion: @escaping (Bool) -> Void) {
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
