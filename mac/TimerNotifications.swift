import Foundation
import UserNotifications

protocol TimerNotificationBackend: AnyObject {
    func pending(_ completion: @escaping ([String]) -> Void)
    func remove(_ identifiers: [String])
    func add(identifier: String, after seconds: TimeInterval, title: String, completion: @escaping (Error?) -> Void)
}

enum AgentNotificationKind: Equatable {
    case attention, failure
}

func agentNotificationKind(_ state: String) -> AgentNotificationKind? {
    if agentNeedsAttention(state) { return .attention }
    if state == "실패" || state.hasPrefix("응답 지연") { return .failure }
    return nil
}

private func agentAttentionType(_ state: String) -> Int? {
    if state.hasPrefix("승인 대기") { return 0 }
    if state.hasPrefix("질문 대기") || state.hasPrefix("입력 대기") { return 1 }
    return nil
}

func agentNotificationTransitions(previous: [AgentActivity], current: [AgentActivity], initialized: Bool, newQuestionSessions: Set<AgentSessionKey>? = nil) -> [(AgentActivity, AgentNotificationKind)] {
    guard initialized else { return [] }
    let old = Dictionary(previous.map { (AgentSessionKey($0), $0) }, uniquingKeysWith: { _, last in last })
    var seen = Set<AgentSessionKey>()
    return current.compactMap { item in
        let session = AgentSessionKey(item)
        guard seen.insert(session).inserted else { return nil }
        guard let kind = agentNotificationKind(item.state),
              old[session].flatMap({ agentNotificationKind($0.state) }) != kind ||
                (kind == .attention && old[session].flatMap({ agentAttentionType($0.state) }) != agentAttentionType(item.state)) ||
                (kind == .attention && (newQuestionSessions?.contains(session) ?? agentHasNewQuestions(previous: old[session], current: item))) else { return nil }
        return (item, kind)
    }
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
        content.sound = FeedbackSound.timerEnabled ? .default : nil
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
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
    func replace(remaining: (() -> TimeInterval)?, title: String = "타이머 완료") {
        precondition(Thread.isMainThread)
        revision += 1
        let current = revision
        backend.pending { [weak self] identifiers in
            DispatchQueue.main.async {
                guard let self = self, self.revision == current else { return }
                self.backend.remove(identifiers.filter { $0.hasPrefix(Self.prefix) })
                // The pending-request lookup can take longer than the timer itself.
                guard let seconds = remaining?(), seconds.isFinite, seconds > 0 else { return }
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
    private static let agentPrefix = "app.rium.notch.agent."
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
    func notifyAgent(_ item: AgentActivity, kind: AgentNotificationKind, showProject: Bool, completion: @escaping (Error?) -> Void) {
        let content = UNMutableNotificationContent()
        content.title = showProject ? "\(item.providerName) · \(item.project)" : "Rium Notch"
        switch kind {
        case .attention: content.body = "에이전트에 확인이 필요한 작업이 감지됐습니다."
        case .failure: content.body = "에이전트 작업의 오류 또는 지연이 감지됐습니다."
        }
        // The existing in-app feedback player owns the optional sound.
        content.sound = nil
        let request = UNNotificationRequest(identifier: Self.agentPrefix + UUID().uuidString, content: content, trigger: nil)
        center.add(request, withCompletionHandler: completion)
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        DispatchQueue.main.async {
            if notification.request.identifier.hasPrefix(Self.agentPrefix) { completionHandler([.banner]); return }
            let playSound = FeedbackSound.timerEnabled && !FeedbackSound.quietForPrivacy && !FeedbackSound.timerAlarmIsPlaying
            completionHandler(playSound ? [.banner, .sound] : [.banner])
        }
    }
}
