import AppKit
import SwiftUI
import CoreLocation
import EventKit
import UniformTypeIdentifiers
import ServiceManagement
import CoreImage

typealias MediaRequester = (String, String?, @escaping ([String: Any]) -> Void) -> Void
@_silgen_name("read_metrics_v2")
func readMetrics(_ cpu: UnsafeMutablePointer<Double>, _ used: UnsafeMutablePointer<UInt64>, _ total: UnsafeMutablePointer<UInt64>, _ swap: UnsafeMutablePointer<UInt64>) -> Int32
@_silgen_name("rium_timer_start") func timerStart(_ seconds: UInt32)
@_silgen_name("rium_timer_pause") func timerPause()
@_silgen_name("rium_timer_resume") func timerResume()
@_silgen_name("rium_timer_reset") func timerReset()
@_silgen_name("rium_timer_restore") func timerRestore(_ state: Int32, _ seconds: UInt32) -> Int32
@_silgen_name("rium_timer_status") func timerStatus(_ seconds: UnsafeMutablePointer<UInt64>) -> Int32
@_silgen_name("rium_pomodoro_advance_config") func pomodoroAdvance(_ phase: Int32, _ completed: UInt64, _ elapsed: UInt64, _ focus: UInt32, _ shortBreak: UInt32, _ longBreak: UInt32, _ sessions: UInt32, _ next: UnsafeMutablePointer<Int32>, _ nextCompleted: UnsafeMutablePointer<UInt64>, _ remaining: UnsafeMutablePointer<UInt64>) -> Int32
@_silgen_name("rium_clipboard_add_record") func clipboardAddRecord(_ kind: UnsafePointer<CChar>, _ bytes: UnsafeRawPointer?, _ length: Int) -> Bool
@_silgen_name("rium_clipboard_json") func clipboardJSON() -> UnsafeMutablePointer<CChar>?
@_silgen_name("rium_clipboard_free") func clipboardFree(_ value: UnsafeMutablePointer<CChar>?)
@_silgen_name("rium_clipboard_copy_data") func clipboardCopyData(_ id: UInt64, _ length: UnsafeMutablePointer<Int>) -> UnsafeMutablePointer<UInt8>?
@_silgen_name("rium_clipboard_free_data") func clipboardFreeData(_ data: UnsafeMutablePointer<UInt8>?, _ length: Int)
@_silgen_name("rium_clipboard_clear") func clipboardClear()
@_silgen_name("rium_clipboard_save") func clipboardSave(_ path: UnsafePointer<CChar>) -> Int32
@_silgen_name("rium_clipboard_load") func clipboardLoad(_ path: UnsafePointer<CChar>) -> Int32
@_silgen_name("rium_shelf_add") func shelfAdd(_ path: UnsafePointer<CChar>) -> Int32
@_silgen_name("rium_shelf_remove") func shelfRemove(_ path: UnsafePointer<CChar>) -> Int32
@_silgen_name("rium_shelf_json") func shelfJSON() -> UnsafeMutablePointer<CChar>?
@_silgen_name("rium_shelf_free") func shelfFree(_ value: UnsafeMutablePointer<CChar>?)
@_silgen_name("rium_output_volume") func outputVolume(_ value: UnsafeMutablePointer<Double>, _ muted: UnsafeMutablePointer<Int32>) -> Int32
@_silgen_name("rium_display_brightness") func displayBrightness(_ display: UInt32, _ value: UnsafeMutablePointer<Double>) -> Int32

struct Account: Identifiable {
    let id: String
    var name: String
    var usage = "확인 전"
    var detail = ""
    var additionalUsage: [String] = []
    var connected = false
}
struct ClipboardMetadata: Decodable { let id: UInt64; let kind: String; let size: Int }
func clipboardImageSize(_ count: Int) -> String {
    if count < 1024 { return "\(max(0, count))바이트" }
    if count < 1024 * 1024 { return String(format: "%.1f KB", Double(count) / 1024) }
    return String(format: "%.1f MB", Double(count) / (1024 * 1024))
}
struct ClipboardRecord: Identifiable {
    enum Content { case text(String), files([URL]), image(Data, NSPasteboard.PasteboardType) }
    let id: UInt64
    let content: Content
}
func codexWindow(_ value: Any?) -> String? {
    guard let object = value as? [String: Any], let used = object["usedPercent"] as? Double, used.isFinite else { return nil }
    let minutes = object["windowDurationMins"] as? Int
    let period: String
    if let minutes = minutes, minutes > 0 {
        let days = minutes / 1440, hours = (minutes % 1440) / 60, remainder = minutes % 60
        period = [(days, "일"), (hours, "시간"), (remainder, "분")].compactMap { $0.0 > 0 ? "\($0.0)\($0.1)" : nil }.joined(separator: " ")
    } else { period = "기간" }
    let reset: String
    if let seconds = object["resetsAt"] as? Double, seconds.isFinite {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "ko_KR"); formatter.dateFormat = "M/d HH:mm"
        reset = " · 초기화 \(formatter.string(from: Date(timeIntervalSince1970: seconds)))"
    } else { reset = "" }
    return String(format: "%@ 사용 %.0f%%%@", period, used, reset)
}
func codexRestrictions(_ data: [String: Any]) -> [String] {
    var result: [String] = []
    if let reason = data["rateLimitReachedType"] as? String, !reason.isEmpty {
        switch reason {
        case "rate_limit_reached": result.append("사용 한도 도달")
        case "workspace_owner_credits_depleted": result.append("워크스페이스 크레딧 소진")
        case "workspace_member_credits_depleted": result.append("구성원 크레딧 소진")
        case "workspace_owner_usage_limit_reached": result.append("워크스페이스 사용 한도 도달")
        case "workspace_member_usage_limit_reached": result.append("구성원 사용 한도 도달")
        default: result.append("사용 제한 상태 확인 필요")
        }
    }
    if let limit = data["individualLimit"] as? [String: Any], let remaining = limit["remainingPercent"] as? Int, (0...100).contains(remaining) {
        var label = "개인 지출 한도 \(remaining)% 남음"
        if let seconds = limit["resetsAt"] as? Double, seconds.isFinite, seconds > 0, seconds < 4_102_444_800 {
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "ko_KR"); formatter.dateFormat = "M/d HH:mm"
            label += " · 초기화 \(formatter.string(from: Date(timeIntervalSince1970: seconds)))"
        }
        result.append(label)
    }
    return result
}
func codexAdditionalUsage(_ data: [String: Any]) -> [String] {
    guard let buckets = data["buckets"] as? [[String: Any]] else { return [] }
    return buckets.map { bucket in
        let raw = (bucket["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (bucket["model"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (bucket["id"] as? String ?? "추가 사용량")
        let name = String(raw.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.prefix(50))
        var parts = [codexWindow(bucket["primary"]), codexWindow(bucket["secondary"])].compactMap { $0 }
        if bucket["spendControlReached"] as? Bool == true { parts.append("지출 한도 도달") }
        parts.append(contentsOf: codexRestrictions(bucket))
        return "\(name): \(parts.isEmpty ? "사용량 조회 불가" : parts.joined(separator: " · "))"
    }
}
struct AgentActivity: Identifiable {
    let id: String
    let project: String
    let state: String
    let activity: String
    var source: String = "codex"
    var recentActivities: [String] = []
    var ageSeconds: UInt64? = nil
    var providerName: String { source == "claude" ? "Claude" : "Codex" }
}
// Prefer a task needing attention or currently active over a completed one.
func collapsedAgent(_ items: [AgentActivity]) -> AgentActivity? {
    let priority = ["승인 대기 감지", "승인 대기", "도구 실행 감지", "작업 중", "활동 감지", "완료", "중단됨", "최근 활동"]
    return items.enumerated().min { lhs, rhs in
        let left = priority.firstIndex(of: lhs.element.state) ?? priority.count
        let right = priority.firstIndex(of: rhs.element.state) ?? priority.count
        return left == right ? lhs.offset < rhs.offset : left < right
    }?.element
}
func agentArrival(previous: [AgentActivity], current: [AgentActivity], initialized: Bool) -> NotchLightCue.Kind? {
    guard initialized else { return nil }
    func category(_ state: String) -> NotchLightCue.Kind? {
        if state.hasPrefix("승인 대기") { return .agentApproval }
        if ["작업 중", "활동 감지", "도구 실행 감지"].contains(state) { return .agentRunning }
        if state == "완료" { return .agentDone }
        return nil
    }
    let old = Dictionary(previous.map { ($0.id, $0.state) }, uniquingKeysWith: { _, last in last })
    let changes = current.compactMap { item -> NotchLightCue.Kind? in
        let next = category(item.state)
        guard let next = next, old[item.id].flatMap(category) != next else { return nil }
        return next
    }
    if changes.contains(.agentApproval) { return .agentApproval }
    if changes.contains(.agentDone) { return .agentDone }
    return changes.first
}
func codexThreadURL(_ id: String) -> URL? {
    guard let uuid = UUID(uuidString: id), id.count == 36 else { return nil }
    var parts = URLComponents()
    parts.scheme = "codex"; parts.host = "threads"; parts.path = "/" + uuid.uuidString.lowercased()
    return parts.url
}
struct LyricLine: Identifiable {
    let id: Int
    let time: Double?
    let text: String
}
func parseLyrics(synced: String?, plain: String?) -> [LyricLine] {
    let pattern = try? NSRegularExpression(pattern: #"^\[(\d{1,3}):(\d{2}(?:\.\d{1,3})?)\]"#)
    var timed: [(Double, String)] = []
    for line in (synced ?? "").components(separatedBy: .newlines) {
        var remaining = line
        var timestamps: [Double] = []
        while true {
            let ns = remaining as NSString
            guard let match = pattern?.firstMatch(in: remaining, range: NSRange(location: 0, length: ns.length)),
                  let minutes = Double(ns.substring(with: match.range(at: 1))), let seconds = Double(ns.substring(with: match.range(at: 2))), seconds < 60 else { break }
            timestamps.append(minutes * 60 + seconds)
            remaining = ns.substring(from: NSMaxRange(match.range))
        }
        let text = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
        for time in timestamps { timed.append((time, text)) }
    }
    if timed.contains(where: { !$0.1.isEmpty }) {
        return timed.enumerated().sorted { $0.element.0 == $1.element.0 ? $0.offset < $1.offset : $0.element.0 < $1.element.0 }.enumerated().map { LyricLine(id: $0.offset, time: $0.element.element.0, text: $0.element.element.1) }
    }
    return (plain ?? "").components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.enumerated().map { LyricLine(id: $0.offset, time: nil, text: $0.element) }
}
enum PanelSection { case home, monitor, weather, agenda, shelf, music, agents, dictation, clipboard }
// Monitoring is held back while the Glance interface is being rebuilt.
// The implementation remains available for the later integration stage.
let usageTrackingEnabled = false
enum Brand {
    static let icon: NSImage? = Bundle.main.url(forResource: "AppIcon", withExtension: "icns").flatMap { NSImage(contentsOf: $0) }
}
private let artworkBlurContext = CIContext(options: [.cacheIntermediates: false])
func blurredArtwork(_ image: NSImage) -> NSImage? {
    guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil), source.width > 0, source.height > 0 else { return nil }
    let scale = 128.0 / Double(max(source.width, source.height))
    let resized = CIImage(cgImage: source).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let bounds = resized.extent.integral
    let blurred = resized.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 18]).cropped(to: bounds)
    guard let result = artworkBlurContext.createCGImage(blurred, from: bounds) else { return nil }
    return NSImage(cgImage: result, size: NSSize(width: bounds.width, height: bounds.height))
}
func droppedFileURL(_ item: NSSecureCoding?) -> URL? {
    let url: URL?
    if let value = item as? URL { url = value }
    else if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
    else if let string = item as? String { url = URL(string: string) }
    else { url = nil }
    guard let url = url, url.isFileURL else { return nil }
    return url.standardizedFileURL
}
func reportDropDiagnostic(_ message: String) {
    if CommandLine.arguments.contains("--report-windows") { print("RIUM_DROP \(message)"); fflush(stdout) }
}
func notchWidth(expanded: Bool, displayWidth: CGFloat? = nil) -> CGFloat {
    // Reserve space for the shoulders outside the content on narrow displays.
    let available = max(240, (displayWidth ?? NSScreen.main?.frame.width ?? 850) - (expanded ? 40 : 24))
    return min(expanded ? 870 : 405, available)
}
func notchOutlineSize(content: CGSize, expanded: Bool, screenWidth: CGFloat) -> CGSize {
    CGSize(width: min(screenWidth, content.width + (expanded ? 40 : 0)), height: content.height)
}
func resolvedDisplayID(preferred: UInt32?, available: [UInt32], primary: UInt32?) -> UInt32? {
    if let preferred = preferred, available.contains(preferred) { return preferred }
    if let primary = primary, available.contains(primary) { return primary }
    return available.first
}
func displayIdentifier(_ screen: NSScreen) -> UInt32? {
    (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
}
struct NotchDisplayChoice: Identifiable {
    let id: UInt32
    let name: String
}
// NSScreen's auxiliary areas use global screen coordinates. Reserve a
// centered span covering their gap, including a possible off-center camera.
func cameraExclusionWidth(screen: NSRect, topInset: CGFloat, left: NSRect?, right: NSRect?) -> CGFloat {
    guard topInset.isFinite, topInset > 0, screen.width > 0,
          let left = left, let right = right,
          left.maxX.isFinite, right.minX.isFinite,
          left.maxX >= screen.minX, right.minX <= screen.maxX,
          left.maxX < right.minX else { return 0 }
    return min(screen.width, 2 * max(screen.midX - left.maxX, right.minX - screen.midX))
}
func notchHeight(expanded: Bool, section: PanelSection) -> CGFloat {
    if !expanded { return 36 }
    if section == .home { return 210 }
    if section == .music { return 374 }
    return 410
}
// Glance RootView.interactiveCardWidth uses the physical notch width as the
// idle base, then adds room only for active peeks, music or a timer.
func calculateCollapsedNotchSize(cameraWidth: CGFloat, cameraHeight: CGFloat, screenWidth: CGFloat, agent: Bool, timer: Bool, music: Bool) -> CGSize {
    let base = cameraWidth > 0 ? cameraWidth : 185
    // The active-agent silhouette has shoulders inside its frame; a live
    // comparison on this Mac showed that the original extends about 20 pt
    // farther overall and 3 pt lower in that state.
    let height = (cameraHeight > 0 ? cameraHeight : 32) + (agent ? 3 : 0)
    let requested: CGFloat
    if agent { requested = max(base + 240, 420) }
    else if timer && music { requested = max(base + 66 + 60 + 20, 330) }
    else if timer { requested = max(base + 34 + 60 + 20, 250) }
    else if music { requested = max(base + 72 + 16, 296) }
    else { requested = max(base, 60) }
    return CGSize(width: min(requested, max(60, screenWidth - 24)), height: height)
}
// The physical camera remains opaque even when a compact preview is narrow.
// Never make the camera gap smaller merely to give both sides more room.
func collapsedHeaderMetrics(width: CGFloat, cameraWidth: CGFloat) -> (side: CGFloat, gap: CGFloat) {
    let available = max(0, width - 52)
    let gap = min(available, max(0, cameraWidth) + 8)
    return (max(0, (available - gap) / 2), gap)
}
// RootView.expandFromHover uses the remaining part of a 0.34 s cooldown;
// when no close has just happened, expansion is immediate.
func hoverReopenWait(lastCollapse: Date?, now: Date) -> TimeInterval {
    guard let lastCollapse = lastCollapse else { return 0 }
    let remaining = 0.34 - now.timeIntervalSince(lastCollapse)
    return remaining > 0.02 ? remaining : 0
}
func notchContainsScreenPoint(_ point: NSPoint, screen: NSRect, expanded: Bool, section: PanelSection, size: CGSize? = nil) -> Bool {
    let width = size?.width ?? notchWidth(expanded: expanded, displayWidth: screen.width)
    let height = size?.height ?? notchHeight(expanded: expanded, section: section)
    let local = CGPoint(x: point.x - (screen.midX - width / 2), y: screen.maxY - point.y)
    return NotchSilhouette().path(in: CGRect(x: 0, y: 0, width: width, height: height)).contains(local)
}
struct NotchPointerDecision {
    let ignoresMouse: Bool
    let inside: Bool
    let hoverChange: Bool?
}
func notchPointerDecision(inside: Bool, wasInside: Bool, ignoring: Bool, buttonDown: Bool, notifyHover: Bool) -> NotchPointerDecision {
    let preservingDrag = buttonDown && !ignoring
    let deferExit = preservingDrag && !inside && notifyHover
    return NotchPointerDecision(
        ignoresMouse: preservingDrag ? ignoring : !inside,
        inside: deferExit ? wasInside : inside,
        hoverChange: notifyHover && !deferExit && inside != wasInside ? inside : nil
    )
}
enum FocusPhase: Int32 {
    case focus = 0, shortBreak = 1, longBreak = 2
    var title: String { switch self { case .focus: return "집중"; case .shortBreak: return "짧은 휴식"; case .longBreak: return "긴 휴식" } }
    var completionTitle: String { self == .focus ? "집중 시간 완료" : "휴식 시간 완료" }
}
enum PomodoroSetting: String, CaseIterable {
    case focus, shortBreak, longBreak, sessions
    var key: String { "rium.pomodoro.\(rawValue)" }
    var defaultValue: Int { switch self { case .focus: return 25; case .shortBreak: return 5; case .longBreak: return 15; case .sessions: return 4 } }
    var range: ClosedRange<Int> { switch self { case .focus: return 1...180; case .shortBreak, .longBreak: return 1...60; case .sessions: return 1...12 } }
    var label: String { switch self { case .focus: return "집중"; case .shortBreak: return "짧은 휴식"; case .longBreak: return "긴 휴식"; case .sessions: return "긴 휴식까지 집중 횟수" } }
    var unit: String { self == .sessions ? "회" : "분" }
}
func timerSummary(state: Int32, remaining: UInt64, phase: FocusPhase? = nil) -> String? {
    guard state == 1 || state == 2 || state == 3 else { return nil }
    let name = phase?.title ?? "타이머"
    if state == 3 { return "\(name) 완료" }
    let time = remaining >= 3600
        ? String(format: "%llu:%02llu:%02llu", remaining / 3600, remaining / 60 % 60, remaining % 60)
        : String(format: "%02llu:%02llu", remaining / 60, remaining % 60)
    return state == 2 ? "\(name) 일시 정지 \(time)" : "\(name) \(time)"
}
func memoryUsagePercent(used: UInt64, total: UInt64, available: Bool) -> Double? {
    guard available, total > 0, used <= total else { return nil }
    return Double(used) * 100 / Double(total)
}
func appendMonitorSample(_ value: Double?, to history: inout [Double?]) {
    history.append(value.flatMap { $0.isFinite && (0...100).contains($0) ? $0 : nil })
    if history.count > 30 { history.removeFirst(history.count - 30) }
}

struct WeatherHour: Identifiable {
    let id: String
    let date: Date
    let temperature: Double
    let symbol: String
    let precipitation: Double?
}
func weatherDescription(_ symbol: String) -> String {
    if symbol.contains("sleet") { return "비와 눈" }
    if symbol.contains("snow") { return "눈" }
    if symbol.contains("rain") { return symbol.contains("thunder") ? "비와 천둥" : "비" }
    if symbol.contains("fair") || symbol.contains("partlycloudy") { return "구름 조금" }
    if symbol.contains("cloudy") { return "흐림" }
    if symbol.contains("clear") { return "맑음" }
    if symbol.contains("fog") { return "안개" }
    return "날씨 정보 없음"
}
func weatherIcon(_ symbol: String) -> String {
    if symbol.contains("thunder") { return "cloud.bolt.rain.fill" }
    if symbol.contains("sleet") { return "cloud.sleet.fill" }
    if symbol.contains("snow") { return "cloud.snow.fill" }
    if symbol.contains("rain") { return "cloud.rain.fill" }
    if symbol.contains("fog") { return "cloud.fog.fill" }
    if symbol.contains("partlycloudy") || symbol.contains("fair") { return symbol.contains("night") ? "cloud.moon.fill" : "cloud.sun.fill" }
    if symbol.contains("cloudy") { return "cloud.fill" }
    if symbol.contains("clear") { return symbol.contains("night") ? "moon.stars.fill" : "sun.max.fill" }
    return "cloud.fill"
}
func weatherHours(_ rows: [[String: Any]]) -> [WeatherHour] {
    let parser = ISO8601DateFormatter()
    var seen = Set<String>()
    return rows.prefix(16).compactMap { row in
        guard let time = row["time"] as? String, let date = parser.date(from: time),
              let temperature = row["temperature"] as? Double, temperature.isFinite,
              seen.insert(time).inserted else { return nil }
        let precipitation = (row["precipitation"] as? Double).flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        return WeatherHour(id: time, date: date, temperature: temperature, symbol: row["symbol"] as? String ?? "", precipitation: precipitation)
    }.sorted { $0.date < $1.date }
}
func weatherHourLabel(_ date: Date, timeZoneID: String?) -> String {
    let formatter = DateFormatter(); formatter.locale = Locale(identifier: "ko_KR")
    formatter.timeZone = timeZoneID.flatMap(TimeZone.init(identifier:)) ?? .current
    formatter.dateFormat = "M/d HH시"
    return formatter.string(from: date)
}

final class Model: ObservableObject {
    @Published var cpu = "측정 중"
    @Published var memory = "측정 중"
    @Published var memoryPercent = "측정 중"
    @Published var pressure = "확인 중"
    @Published var swap = "확인 중"
    @Published var cpuHistory: [Double?] = []
    @Published var memoryHistory: [Double?] = []
    @Published var accounts: [Account] = []
    @Published var message = ""
    @Published var expanded = false {
        didSet { if oldValue && !expanded { lastCollapse = Date() } }
    }
    @Published var displayWidth = NSScreen.main?.frame.width ?? 850
    @Published var cameraExclusion: CGFloat = 0
    @Published var cameraHeight: CGFloat = 0
    @Published private(set) var preferredDisplayID: UInt32?
    @Published private(set) var availableDisplays: [NotchDisplayChoice] = []
    @Published var hoverEnabled = true
    @Published var autoHideEnabled = true
    @Published var autoHideDelay = 0.4
    private var lastCollapse: Date?
    @Published private(set) var fileDragActive = false
    @Published var lightCue: NotchLightCue?
    private var lightClearWork: DispatchWorkItem?
    private var hoverWork: DispatchWorkItem?
    @Published var volume = "음량 조회 불가"
    @Published var volumeOverlay = ""
    @Published var overlaySymbol = "speaker.wave.2.fill"
    @Published var brightness = "밝기 확인 중"
    private var selectedDisplayID: UInt32?
    private var brightnessBaseline: Int?
    private var brightnessDisplayID: UInt32?
    @Published var sampleInterval = 2
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var settingsMessage = ""
    private var volumeSeen = false
    private var volumeHideAt = Date.distantPast
    @Published var timerState: Int32 = 0
    @Published var timerRemaining: UInt64 = 0
    @Published var timerPomodoro = false
    @Published var timerPhase: FocusPhase = .focus
    @Published var timerSessions: UInt64 = 0
    @Published private(set) var pomodoroFocus = 25
    @Published private(set) var pomodoroShortBreak = 5
    @Published private(set) var pomodoroLongBreak = 15
    @Published private(set) var pomodoroSessions = 4
    @Published var timerNotificationsEnabled = false
    @Published var timerNotificationStatus = ""
    private var timerNotificationsAuthorized = false
    private var timerPermissionRevision = 0
    private var timerScheduleRevision = 0
    private var timerNotificationService: TimerNotificationService?
    @Published var clipboardEnabled = false
    @Published var clipboardItems: [ClipboardRecord] = []
    @Published var clipboardReady = true
    @Published var clipboardStorageStatus = ""
    @Published var section: PanelSection = .home
    let updater = UpdateController()
    let dictation = DictationController()
    let teleprompter = TeleprompterController()
    let power = PowerModel()
    let audioOutputs = AudioOutputModel()
    @Published var agentItems: [AgentActivity] = []
    @Published var agentStatus = "최근 Codex 활동 없음"
    private var agentBusy = false
    private var agentObservationReady = false
    var showsCollapsedAgent: Bool {
        agentItems.contains { ["작업 중", "활동 감지", "도구 실행 감지"].contains($0.state) || $0.state.hasPrefix("승인 대기") }
            || lightCue.map { [.agentRunning, .agentApproval, .agentDone].contains($0.kind) } == true
    }
    var collapsedIsIdle: Bool { !showsCollapsedAgent && timerState == 0 && !mediaPlaying && volumeOverlay.isEmpty }
    var collapsedNotchSize: CGSize {
        calculateCollapsedNotchSize(cameraWidth: cameraExclusion, cameraHeight: cameraHeight, screenWidth: displayWidth,
                           agent: showsCollapsedAgent || !volumeOverlay.isEmpty, timer: timerState != 0, music: mediaPlaying)
    }
    var currentNotchSize: CGSize {
        expanded ? CGSize(width: notchWidth(expanded: true, displayWidth: displayWidth), height: notchHeight(expanded: true, section: section)) : collapsedNotchSize
    }
    var currentNotchOutlineSize: CGSize {
        notchOutlineSize(content: currentNotchSize, expanded: expanded, screenWidth: displayWidth)
    }
    @Published var mediaTitle = "재생 정보를 불러오세요"
    @Published var mediaArtist = ""
    @Published var mediaAvailable = false
    @Published var mediaPlaying = false
    @Published var mediaDuration = 0.0
    @Published var mediaElapsed = 0.0
    @Published var mediaSeekPending = false
    @Published private(set) var mediaControlPending = false
    @Published var mediaError = ""
    @Published var lyricsEnabled = false
    @Published var showLyricsPanel = true
    @Published var lyricLines: [LyricLine] = []
    @Published var lyricsStatus = "가사를 켜면 현재 곡을 조회합니다."
    private var lyricsKey = ""
    private var lyricsBusy = false
    private var lyricsGeneration = 0
    @Published var mediaEditingPosition = false
    @Published var mediaEditedPosition = 0.0
    private var mediaRevision = 0
    private var mediaBaseElapsed = 0.0
    private var mediaObservedUptime = 0.0
    @Published var mediaArtwork: NSImage?
    @Published var mediaAtmosphere: NSImage?
    @Published var mediaLightColor = NSColor(calibratedRed: 0.55, green: 0.73, blue: 1, alpha: 1)
    private var mediaArtworkFingerprint: Int?
    private var mediaBusy = false
    private var mediaRefreshPending = false
    private var mediaCommands: [String] = []
    private var mediaCommandBusy = false
    private let mediaRequester: MediaRequester?
    private var mediaTick = 0
    @Published var shelfItems: [String] = []
    @Published var shelfStatus = "파일을 끌어 놓거나 추가하세요"
    @Published var airDropStatus = "AirDrop 수신 감시 꺼짐"
    @Published var airDropEnabled = false
    @Published var screenshotEnabled = false
    @Published var screenshotStatus = "스크린샷 감시 꺼짐"
    lazy var airDropMonitor = AirDropMonitor(onStatus: { [weak self] status in
        self?.airDropStatus = status
        if status.contains("확인해 주세요") || status.contains("수 없습니다") {
            self?.airDropEnabled = false
            UserDefaults.standard.set(false, forKey: "rium.airdrop.enabled")
        }
    }, onFile: { [weak self] url in
        self?.addShelf(url)
        self?.airDropStatus = "AirDrop 수신: \(url.lastPathComponent)"
        self?.showLight(.airDrop)
    })
    lazy var screenshotMonitor = ScreenshotMonitor(onStatus: { [weak self] status in
        self?.screenshotStatus = status
        if status.contains("확인해 주세요") || status.contains("수 없습니다") {
            self?.screenshotEnabled = false
            UserDefaults.standard.set(false, forKey: "rium.screenshot.enabled")
        }
    }, onFile: { [weak self] url in
        self?.addShelf(url); self?.screenshotStatus = "스크린샷: \(url.lastPathComponent)"
    })
    @Published var weatherText = "도시를 선택해 주세요"
    @Published var weatherDetail = "날씨 제공: MET Norway"
    @Published var weatherCity = ""
    @Published var weatherCondition = ""
    @Published var weatherTemperature: Double?
    @Published var weatherForecast: [WeatherHour] = []
    @Published var weatherTimeZoneID: String?
    let agenda: AgendaModel
    @Published var now = Date()
    private let geocoder = CLGeocoder()
    private let weatherLocator = WeatherLocation()
    private var weatherGeneration = 0
    private var lastWeatherAttempt = Date.distantPast
    private var timer: Timer?
    private var accountTimer: Timer?
    private var clockTimer: Timer?
    private var hudTimer: Timer?
    private var pressureSource: DispatchSourceMemoryPressure?
    private var pressureEvent: String?
    private var clipboardChangeCount = 0
    private let clipboardQueue = DispatchQueue(label: "app.rium.notch.clipboard.store", qos: .utility)
    private var clipboardRoot: URL?
    private var clipboardCanSave = false
    private let pasteboard: NSPasteboard
    private let timerPreferences: UserDefaults?
    private var busy = Set<String>()

    init(pasteboard: NSPasteboard = .general, startServices: Bool = true, timerPreferences: UserDefaults? = nil, mediaRequester: MediaRequester? = nil) {
        self.pasteboard = pasteboard
        self.timerPreferences = timerPreferences ?? (startServices ? .standard : nil)
        self.mediaRequester = mediaRequester
        self.agenda = AgendaModel(autoRefresh: startServices)
        restorePomodoroSettings()
        guard startServices else { return }
        updater.start()
        restoreClipboard()
        if let value = UserDefaults.standard.object(forKey: "rium.notch.display") as? NSNumber, value.uint64Value > 0, value.uint64Value <= UInt64(UInt32.max) {
            preferredDisplayID = value.uint32Value
        }
        restoreTimer()
        timerNotificationsEnabled = UserDefaults.standard.bool(forKey: "rium.timer.notifications")
        if timerNotificationsEnabled { refreshTimerNotificationPermission() }
        lyricsEnabled = UserDefaults.standard.bool(forKey: "rium.lyrics.enabled")
        if usageTrackingEnabled { sample(); monitorMemoryPressure() }
        let savedInterval = UserDefaults.standard.integer(forKey: "rium.monitor.interval")
        hoverEnabled = UserDefaults.standard.object(forKey: "rium.notch.hover") as? Bool ?? true
        autoHideEnabled = UserDefaults.standard.object(forKey: "rium.notch.autoHide") as? Bool ?? true
        if let delay = UserDefaults.standard.object(forKey: "rium.notch.autoHideDelay") as? Double, delay.isFinite {
            autoHideDelay = min(3, max(0.1, delay))
        }
        sampleInterval = [2, 5, 10].contains(savedInterval) ? savedInterval : 2
        if usageTrackingEnabled { scheduleSampling() }
        dictation.restoreIfAuthorized()
        if UserDefaults.standard.bool(forKey: "rium.airdrop.enabled") { airDropEnabled = true; airDropMonitor.start() }
        if UserDefaults.standard.bool(forKey: "rium.screenshot.enabled") { screenshotEnabled = true; screenshotMonitor.start() }
        if usageTrackingEnabled { listAccounts() }
        refreshAgents()
        refreshMedia()
        if let cache = UserDefaults.standard.dictionary(forKey: "rium.weather.cache"),
           let data = cache["data"] as? [String: Any], let updated = cache["updated"] as? Double {
            showWeather(city: cache["city"] as? String ?? "선택 도시", data: data, updated: Date(timeIntervalSince1970: updated), timeZoneID: cache["timezone"] as? String)
            refreshStaleWeather()
        }
        if usageTrackingEnabled {
            accountTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                for account in self.accounts { self.refresh(account.id) }
            }
        }
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.updateTimer(); self.sampleClipboard(); self.advanceMedia(); self.mediaTick += 1
            if self.mediaTick % 5 == 0 && (self.section == .music || self.section == .home || self.mediaTick % 10 == 0) { self.refreshMedia() }
            if self.mediaTick % 10 == 0 { self.refreshAgents(); self.agenda.refreshIfAuthorizationChanged(); self.dictation.restoreIfAuthorized() }
            if self.mediaTick % 60 == 0 { self.now = Date() }
            if self.mediaTick % 300 == 0 { self.refreshStaleWeather(); self.agenda.refreshAuthorized() }
        }
        hudTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.sampleVolume(); self?.sampleBrightness() }
    }

    func setHoverEnabled(_ enabled: Bool) {
        hoverEnabled = enabled; UserDefaults.standard.set(enabled, forKey: "rium.notch.hover")
        hoverWork?.cancel(); hoverWork = nil
    }
    func setAutoHideEnabled(_ enabled: Bool) {
        autoHideEnabled = enabled; UserDefaults.standard.set(enabled, forKey: "rium.notch.autoHide")
        if !enabled { hoverWork?.cancel(); hoverWork = nil }
    }
    func setAutoHideDelay(_ delay: Double) {
        guard delay.isFinite else { return }
        autoHideDelay = min(3, max(0.1, delay))
        UserDefaults.standard.set(autoHideDelay, forKey: "rium.notch.autoHideDelay")
    }
    func showLight(_ kind: NotchLightCue.Kind) {
        let cue = NotchLightCue(kind: kind, started: Date())
        lightClearWork?.cancel()
        lightCue = cue
        let task = DispatchWorkItem { [weak self] in
            if self?.lightCue?.id == cue.id { self?.lightCue = nil }
        }
        lightClearWork = task
        DispatchQueue.main.asyncAfter(deadline: .now() + cue.duration, execute: task)
    }
    func handleHover(_ inside: Bool) {
        guard hoverEnabled, !fileDragActive else { return }
        hoverWork?.cancel()
        guard inside != expanded else { return }
        if !inside && !autoHideEnabled { return }
        let delay = inside ? hoverReopenWait(lastCollapse: lastCollapse, now: Date()) : autoHideDelay
        if delay <= 0 { expanded = inside; return }
        let task = DispatchWorkItem { [weak self] in self?.expanded = inside }
        hoverWork = task; DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }

    func setFileDragActive(_ active: Bool) {
        guard fileDragActive != active else { return }
        reportDropDiagnostic("targeted=\(active)")
        fileDragActive = active; hoverWork?.cancel(); hoverWork = nil
        if active { select(.shelf); expanded = true }
        else {
            let inside = (NSApp.delegate as? AppDelegate)?.pointIsInsideNotch(NSEvent.mouseLocation) ?? false
            handleHover(inside)
        }
    }

    func monitorMemoryPressure() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        source.setEventHandler { [weak self, weak source] in
            guard let self = self, let data = source?.data else { return }
            if data.contains(.critical) { self.pressureEvent = "위험" }
            else if data.contains(.warning) { self.pressureEvent = "주의" }
            else if data.contains(.normal) { self.pressureEvent = "정상" }
            self.pressure = currentMemoryPressure() ?? self.pressureEvent ?? "조회 불가"
        }
        pressureSource = source; source.resume()
    }

    func advanceMedia() {
        guard mediaPlaying, mediaDuration > 0, mediaObservedUptime > 0 else { return }
        mediaElapsed = min(mediaDuration, max(0, mediaBaseElapsed + ProcessInfo.processInfo.systemUptime - mediaObservedUptime))
    }

    func scheduleSampling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(sampleInterval), repeats: true) { [weak self] _ in self?.sample() }
    }
    func setSampleInterval(_ seconds: Int) {
        guard [2, 5, 10].contains(seconds) else { return }
        sampleInterval = seconds; UserDefaults.standard.set(seconds, forKey: "rium.monitor.interval"); scheduleSampling()
    }
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            settingsMessage = SMAppService.mainApp.status == .requiresApproval ? "시스템 설정에서 로그인 항목을 허용해 주세요" : ""
        } catch { launchAtLogin = SMAppService.mainApp.status == .enabled; settingsMessage = "로그인 항목을 변경할 수 없습니다" }
    }

    func select(_ next: PanelSection) {
        section = next
        if next == .agenda || next == .home { agenda.refreshAuthorized() }
        if next == .shelf { reloadShelf() }
        if next == .music || next == .home { refreshMedia() }
        if next == .agents { refreshAgents() }
    }

    func sampleVolume() {
        var value = -1.0; var muted: Int32 = 0
        let flags = outputVolume(&value, &muted)
        let label: String
        if flags & 2 != 0 && muted != 0 { label = "음소거" }
        else if flags & 1 != 0 { label = String(format: "음량 %.0f%%", value) }
        else { label = "음량 조회 불가" }
        if volumeSeen && label != volume && label != "음량 조회 불가" { showControlOverlay(label, symbol: muted != 0 ? "speaker.slash.fill" : "speaker.wave.2.fill") }
        volume = label; volumeSeen = label != "음량 조회 불가"
        if Date() >= volumeHideAt { volumeOverlay = "" }
    }
    private func showControlOverlay(_ label: String, symbol: String) {
        volumeOverlay = label; overlaySymbol = symbol; volumeHideAt = Date().addingTimeInterval(2)
        if lightCue == nil || lightCue?.kind == .systemControl { showLight(.systemControl) }
    }
    func selectDisplay(_ id: UInt32?) {
        guard id != selectedDisplayID else { return }
        selectedDisplayID = id; brightnessBaseline = nil; brightnessDisplayID = nil
        sampleBrightness()
    }
    func refreshDisplayChoices() {
        let screens = NSScreen.screens
        availableDisplays = screens.enumerated().compactMap { index, screen in
            guard let id = displayIdentifier(screen), id != 0 else { return nil }
            let name = screen.localizedName
            let title = screens.filter { $0.localizedName == name }.count > 1 ? "\(name) (\(index + 1))" : name
            return NotchDisplayChoice(id: id, name: title)
        }
    }
    func setPreferredDisplay(_ id: UInt32) {
        let preferred: UInt32? = id == 0 ? nil : id
        guard preferred != preferredDisplayID else { return }
        preferredDisplayID = preferred
        if let preferred = preferred { UserDefaults.standard.set(NSNumber(value: preferred), forKey: "rium.notch.display") }
        else { UserDefaults.standard.removeObject(forKey: "rium.notch.display") }
        NotificationCenter.default.post(name: .notchDisplayChanged, object: nil)
    }
    func recordBrightness(display: UInt32, percent: Double?) {
        guard let percent = percent, percent.isFinite, (0...100).contains(percent) else {
            brightness = "밝기 조회 불가"; brightnessBaseline = nil; brightnessDisplayID = display; return
        }
        let value = Int(percent.rounded())
        if brightnessDisplayID == display, let previous = brightnessBaseline, previous != value {
            showControlOverlay("밝기 \(value)%", symbol: "sun.max.fill")
        }
        brightness = "밝기 \(value)%"; brightnessBaseline = value; brightnessDisplayID = display
    }
    func sampleBrightness() {
        guard let display = selectedDisplayID else { brightness = "밝기 조회 불가"; return }
        var value = -1.0
        let available = displayBrightness(display, &value) == 1
        recordBrightness(display: display, percent: available ? value : nil)
    }

    func toggleClipboard() {
        guard clipboardReady else { return }
        clipboardChangeCount = pasteboard.changeCount
        clipboardEnabled.toggle()
        if clipboardRoot != nil { UserDefaults.standard.set(clipboardEnabled, forKey: "rium.clipboard.enabled") }
    }

    private func restoreClipboard() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let root = support.appendingPathComponent("Rium Notch", isDirectory: true)
        clipboardRoot = root; clipboardReady = false
        clipboardQueue.async { [weak self] in
            let result = root.path.withCString { clipboardLoad($0) }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.clipboardCanSave = result == 0
                self.clipboardStorageStatus = result == 0 ? "" : "저장된 기록을 읽지 못해 이번 실행의 기록은 저장하지 않습니다."
                if result == 0 { self.reloadClipboard() }
                self.clipboardChangeCount = self.pasteboard.changeCount
                self.clipboardEnabled = UserDefaults.standard.bool(forKey: "rium.clipboard.enabled")
                self.clipboardReady = true
            }
        }
    }
    private func scheduleClipboardSave() {
        guard clipboardCanSave, let root = clipboardRoot else { return }
        clipboardQueue.async { [weak self] in
            let result = root.path.withCString { clipboardSave($0) }
            DispatchQueue.main.async { [weak self] in self?.clipboardStorageStatus = result == 0 ? "" : "클립보드 기록을 저장하지 못했습니다." }
        }
    }
    func flushClipboard() { if clipboardRoot != nil { clipboardQueue.sync {} } }

    func sampleClipboard() {
        guard clipboardReady, clipboardEnabled else { return }
        let board = pasteboard
        guard board.changeCount != clipboardChangeCount else { return }
        clipboardChangeCount = board.changeCount
        // Password managers can mark pasteboard entries as confidential or transient.
        let excluded = Set(["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType"])
        let types = Set(board.types?.map(\.rawValue) ?? [])
        guard types.isDisjoint(with: excluded) else { return }
        let kind: String, data: Data
        if types.contains(NSPasteboard.PasteboardType.fileURL.rawValue) {
            guard let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
                  !urls.isEmpty, urls.count <= 100,
                  let encoded = try? JSONEncoder().encode(urls.map(\.absoluteString)) else { return }
            kind = "files"; data = encoded
        } else if types.contains(NSPasteboard.PasteboardType.png.rawValue), let png = board.data(forType: .png) {
            kind = "image/png"; data = png
        } else if types.contains(NSPasteboard.PasteboardType.tiff.rawValue), let tiff = board.data(forType: .tiff) {
            kind = "image/tiff"; data = tiff
        } else if let text = board.string(forType: .string), let encoded = text.data(using: .utf8) {
            kind = "text"; data = encoded
        } else { return }
        let added = kind.withCString { name in data.withUnsafeBytes { bytes in clipboardAddRecord(name, bytes.baseAddress, bytes.count) } }
        if added { reloadClipboard(); scheduleClipboardSave(); showLight(.clipboard) }
    }

    func reloadClipboard() {
        guard let raw = clipboardJSON() else { return }
        defer { clipboardFree(raw) }
        let data = Data(bytes: raw, count: strlen(raw))
        let metadata = (try? JSONDecoder().decode([ClipboardMetadata].self, from: data)) ?? []
        clipboardItems = metadata.compactMap { item in
            guard item.size > 0, item.size <= 8 * 1024 * 1024 else { return nil }
            var length = 0
            guard let bytes = clipboardCopyData(item.id, &length) else { return nil }
            defer { clipboardFreeData(bytes, length) }
            guard length == item.size else { return nil }
            let data = Data(bytes: bytes, count: length)
            switch item.kind {
            case "text":
                guard let text = String(data: data, encoding: .utf8) else { return nil }
                return ClipboardRecord(id: item.id, content: .text(text))
            case "files":
                guard let values = try? JSONDecoder().decode([String].self, from: data) else { return nil }
                let urls = values.compactMap(URL.init(string:)).filter(\.isFileURL)
                guard !urls.isEmpty, urls.count == values.count else { return nil }
                return ClipboardRecord(id: item.id, content: .files(urls))
            case "image/png", "image/tiff":
                guard NSImage(data: data) != nil else { return nil }
                return ClipboardRecord(id: item.id, content: .image(data, item.kind == "image/png" ? .png : .tiff))
            default: return nil
            }
        }
    }

    func copyClipboard(_ record: ClipboardRecord) {
        let board = pasteboard; board.clearContents()
        switch record.content {
        case .text(let value): board.setString(value, forType: .string)
        case .files(let urls): board.writeObjects(urls as [NSURL])
        case .image(let data, let type): board.setData(data, forType: type)
        }
        clipboardChangeCount = board.changeCount
    }
    func clearClipboardHistory() { guard clipboardReady else { return }; clipboardClear(); reloadClipboard(); scheduleClipboardSave() }

    func pomodoroValue(_ setting: PomodoroSetting) -> Int {
        switch setting { case .focus: return pomodoroFocus; case .shortBreak: return pomodoroShortBreak; case .longBreak: return pomodoroLongBreak; case .sessions: return pomodoroSessions }
    }
    private func assignPomodoroValue(_ setting: PomodoroSetting, _ value: Int) {
        switch setting { case .focus: pomodoroFocus = value; case .shortBreak: pomodoroShortBreak = value; case .longBreak: pomodoroLongBreak = value; case .sessions: pomodoroSessions = value }
    }
    private func restorePomodoroSettings() {
        for setting in PomodoroSetting.allCases {
            let value = timerPreferences?.object(forKey: setting.key) as? Int ?? setting.defaultValue
            assignPomodoroValue(setting, setting.range.contains(value) ? value : setting.defaultValue)
        }
    }
    func setPomodoroValue(_ setting: PomodoroSetting, _ value: Int) {
        guard setting.range.contains(value) else { return }
        assignPomodoroValue(setting, value)
        timerPreferences?.set(value, forKey: setting.key)
    }
    func updateTimer() {
        var seconds: UInt64 = 0
        let previous = timerState
        timerState = timerStatus(&seconds); timerRemaining = seconds
        if previous == 1 && timerState == 3 {
            if timerPomodoro && advancePomodoro() {
                saveTimer()
                if !timerNotificationsEnabled || !timerNotificationsAuthorized { NSSound.beep() }
                // Let the just-completed phase's scheduled alert arrive before
                // replacing it with the next phase's pending alert.
                syncTimerNotification(afterTransition: true)
                return
            }
            saveTimer()
            if !timerNotificationsEnabled || !timerNotificationsAuthorized { NSSound.beep() }
        }
    }

    private func advancePomodoro() -> Bool {
        var next: Int32 = 0, completed: UInt64 = 0, remaining: UInt64 = 0
        guard pomodoroAdvance(timerPhase.rawValue, timerSessions, 0, UInt32(pomodoroFocus), UInt32(pomodoroShortBreak), UInt32(pomodoroLongBreak), UInt32(pomodoroSessions), &next, &completed, &remaining) == 0,
              let phase = FocusPhase(rawValue: next), remaining > 0, remaining <= 86_400 else { return false }
        timerPhase = phase; timerSessions = completed; timerStart(UInt32(remaining))
        timerState = timerStatus(&remaining); timerRemaining = remaining
        return timerState == 1
    }

    func saveTimer(at now: Date = Date()) {
        guard let defaults = timerPreferences else { return }
        var checkpoint: [String: Any] = ["state": timerState, "mode": timerPomodoro ? "pomodoro" : "timer", "phase": timerPhase.rawValue, "sessions": timerSessions]
        switch timerState {
        case 1: checkpoint["deadline"] = now.timeIntervalSince1970 + Double(timerRemaining)
        case 2: checkpoint["remaining"] = timerRemaining
        case 3: break
        default: defaults.removeObject(forKey: "rium.timer.checkpoint"); return
        }
        defaults.set(checkpoint, forKey: "rium.timer.checkpoint")
    }
    func restoreTimer(at now: Date = Date()) {
        guard let defaults = timerPreferences, let checkpoint = defaults.dictionary(forKey: "rium.timer.checkpoint"), let state = checkpoint["state"] as? Int else { return }
        timerPomodoro = (checkpoint["mode"] as? String) == "pomodoro"
        if timerPomodoro {
            guard let rawPhase = checkpoint["phase"] as? Int, let phaseValue = Int32(exactly: rawPhase), let phase = FocusPhase(rawValue: phaseValue),
                  let count = checkpoint["sessions"] as? NSNumber, count.int64Value >= 0, count.uint64Value <= 1_000_000 else {
                timerPomodoro = false; defaults.removeObject(forKey: "rium.timer.checkpoint"); return
            }
            timerPhase = phase; timerSessions = count.uint64Value
        } else { timerPhase = .focus; timerSessions = 0 }
        var restoredState = state
        var remaining = 0.0
        if state == 1, let deadline = checkpoint["deadline"] as? Double, deadline.isFinite {
            remaining = ceil(deadline - now.timeIntervalSince1970)
            if remaining <= 0 {
                if timerPomodoro && advancePomodoro() { saveTimer(at: now); return }
                restoredState = 3; remaining = 0
            }
        } else if state == 2, let value = checkpoint["remaining"] as? NSNumber { remaining = value.doubleValue }
        else if state != 3 { defaults.removeObject(forKey: "rium.timer.checkpoint"); return }
        guard remaining.isFinite, remaining >= 0, remaining <= 86_400, [1, 2, 3].contains(restoredState),
              timerRestore(Int32(restoredState), UInt32(remaining)) == 0 else { defaults.removeObject(forKey: "rium.timer.checkpoint"); return }
        updateTimer(); if restoredState == 3 { saveTimer(at: now) }
    }
    private func notificationService() -> TimerNotificationService {
        if let service = timerNotificationService { return service }
        let service = TimerNotificationService()
        service.coordinator.onError = { [weak self] message in
            self?.timerNotificationsAuthorized = false
            self?.timerNotificationStatus = message
        }
        timerNotificationService = service
        return service
    }
    private func syncTimerNotification(afterTransition: Bool = false) {
        timerScheduleRevision += 1; let revision = timerScheduleRevision
        guard timerNotificationsEnabled, timerNotificationsAuthorized else { return }
        if timerState == 1 {
            let schedule = { [weak self] in
                guard let self = self, self.timerScheduleRevision == revision, self.timerNotificationsEnabled,
                      self.timerNotificationsAuthorized, self.timerState == 1 else { return }
                let title = self.timerPomodoro ? self.timerPhase.completionTitle : "타이머 완료"
                self.notificationService().coordinator.replace(after: TimeInterval(self.timerRemaining), title: title)
            }
            if afterTransition { DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: schedule) } else { schedule() }
        }
        else if timerState == 0 || timerState == 2 { notificationService().coordinator.replace(after: nil) }
    }
    func refreshTimerNotificationPermission() {
        guard timerNotificationsEnabled else { return }
        timerPermissionRevision += 1; let revision = timerPermissionRevision
        timerScheduleRevision += 1
        notificationService().authorization { [weak self] granted in
            guard let self = self, self.timerNotificationsEnabled, self.timerPermissionRevision == revision else { return }
            self.timerNotificationsAuthorized = granted
            self.timerNotificationStatus = granted ? "" : "시스템 설정에서 Rium Notch 알림을 허용해 주세요."
            if granted { self.syncTimerNotification() } else { self.timerNotificationService?.coordinator.replace(after: nil) }
        }
    }
    func setTimerNotificationsEnabled(_ enabled: Bool) {
        timerPermissionRevision += 1; let revision = timerPermissionRevision
        timerScheduleRevision += 1
        timerNotificationsEnabled = enabled; UserDefaults.standard.set(enabled, forKey: "rium.timer.notifications")
        if !enabled {
            timerNotificationsAuthorized = false; timerNotificationStatus = ""
            timerNotificationService?.coordinator.replace(after: nil)
            return
        }
        timerNotificationStatus = "알림 권한 확인 중…"
        notificationService().requestAuthorization { [weak self] granted in
            guard let self = self, self.timerNotificationsEnabled, self.timerPermissionRevision == revision else { return }
            self.timerNotificationsAuthorized = granted
            self.timerNotificationStatus = granted ? "" : "시스템 설정에서 Rium Notch 알림을 허용해 주세요."
            if granted { self.syncTimerNotification() } else { self.timerNotificationService?.coordinator.replace(after: nil) }
        }
    }
    func startTimer(_ seconds: UInt32) { timerPomodoro = false; timerPhase = .focus; timerSessions = 0; timerStart(seconds); updateTimer(); saveTimer(); syncTimerNotification() }
    func startPomodoro() { timerPomodoro = true; timerPhase = .focus; timerSessions = 0; timerStart(UInt32(pomodoroFocus * 60)); updateTimer(); saveTimer(); syncTimerNotification() }
    func pauseTimer() { updateTimer(); timerPause(); updateTimer(); saveTimer(); syncTimerNotification() }
    func resumeTimer() { timerResume(); updateTimer(); saveTimer(); syncTimerNotification() }
    func resetTimer() { timerReset(); timerPomodoro = false; timerPhase = .focus; timerSessions = 0; updateTimer(); saveTimer(); syncTimerNotification() }

    func customTimer() {
        let alert = NSAlert(); alert.messageText = "타이머 시간"
        alert.informativeText = "1분부터 1,440분까지 입력할 수 있습니다."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24)); field.stringValue = "25"; alert.accessoryView = field
        alert.addButton(withTitle: "시작"); alert.addButton(withTitle: "취소"); NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn, let minutes = UInt32(field.stringValue), (1...1440).contains(minutes) else { return }
        startTimer(minutes * 60)
    }

    func reloadShelf() {
        guard let raw = shelfJSON() else { shelfStatus = "보관함을 읽을 수 없습니다"; return }
        defer { shelfFree(raw) }
        let data = Data(bytes: raw, count: strlen(raw))
        if let result = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            if let items = result["items"] as? [String] { shelfItems = items; shelfStatus = items.isEmpty ? "파일을 끌어 놓거나 추가하세요" : "파일 \(items.count)개" }
            else { shelfStatus = result["error"] as? String ?? "보관함을 읽을 수 없습니다" }
        }
    }

    @discardableResult func addShelf(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let result = url.path.withCString { shelfAdd($0) }
        if result < 0 { shelfStatus = "보관함에 추가할 수 없습니다"; return false }
        reloadShelf(); return true
    }

    func receiveFileDrop(_ providers: [NSItemProvider]) -> Bool {
        let identifier = UTType.fileURL.identifier
        let files = providers.filter { $0.hasItemConformingToTypeIdentifier(identifier) }
        reportDropDiagnostic("providers=\(providers.count) files=\(files.count)")
        guard !files.isEmpty else { return false }
        for provider in files {
            provider.loadItem(forTypeIdentifier: identifier, options: nil) { [weak self] item, _ in
                let url = droppedFileURL(item)
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    guard let url = url else { self.shelfStatus = "끌어온 파일을 읽을 수 없습니다"; return }
                    if self.addShelf(url) { self.showLight(.shelf); reportDropDiagnostic("added=true") }
                }
            }
        }
        return true
    }

    func removeShelf(_ path: String) {
        if path.withCString({ shelfRemove($0) }) < 0 { shelfStatus = "보관함에서 제거할 수 없습니다" } else { reloadShelf() }
    }

    func chooseShelfFiles() {
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        panel.prompt = "보관함에 추가"; NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK { for url in panel.urls { addShelf(url) } }
    }

    func toggleAirDropMonitor() {
        airDropEnabled.toggle()
        UserDefaults.standard.set(airDropEnabled, forKey: "rium.airdrop.enabled")
        if airDropEnabled { airDropMonitor.start() } else { airDropMonitor.stop() }
    }
    func toggleScreenshotMonitor() {
        screenshotEnabled.toggle()
        UserDefaults.standard.set(screenshotEnabled, forKey: "rium.screenshot.enabled")
        if screenshotEnabled { screenshotMonitor.start() } else { screenshotMonitor.stop() }
    }

    func sendAirDrop(_ path: String) {
        guard let service = NSSharingService(named: .sendViaAirDrop) else { shelfStatus = "AirDrop을 사용할 수 없습니다"; return }
        service.perform(withItems: [URL(fileURLWithPath: path)])
    }

    private func requestMedia(_ action: String, position: String? = nil, completion: @escaping ([String: Any]) -> Void) {
        if let requester = mediaRequester { requester(action, position, completion); return }
        var args = ["media", action]
        if let position = position { args.append(position) }
        run(args, event: completion)
    }
    func refreshMedia() {
        guard !mediaBusy, !mediaSeekPending, !mediaControlPending else { mediaRefreshPending = true; return }
        mediaRefreshPending = false; mediaBusy = true
        let revision = mediaRevision
        requestMedia("get") { [weak self] event in
            guard let self = self else { return }
            guard let kind = event["event"] as? String, kind == "result" || kind == "error" else { return }
            self.mediaBusy = false
            guard revision == self.mediaRevision, !self.mediaSeekPending, !self.mediaControlPending else {
                self.mediaRefreshPending = true
                if !self.mediaSeekPending && !self.mediaControlPending { self.refreshMedia() }
                return
            }
            if let data = event["data"] as? [String: Any] {
                let title = (data["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                self.mediaTitle = title ?? "재생 중인 미디어 없음"
                self.mediaArtist = data["artist"] as? String ?? ""
                self.mediaPlaying = data["playing"] as? Bool ?? false
                let duration = data["duration"] as? Double ?? 0, elapsed = data["elapsedTime"] as? Double ?? 0
                self.mediaDuration = duration.isFinite ? max(0, duration) : 0
                self.mediaElapsed = elapsed.isFinite ? max(0, elapsed) : 0
                self.mediaAvailable = title != nil || !self.mediaArtist.isEmpty || self.mediaPlaying || self.mediaDuration > 0 || ((data["artworkData"] as? String).map { !$0.isEmpty } ?? false)
                self.mediaBaseElapsed = self.mediaElapsed; self.mediaObservedUptime = ProcessInfo.processInfo.systemUptime
                if let encoded = data["artworkData"] as? String, !encoded.isEmpty {
                    let fingerprint = encoded.hashValue
                    if fingerprint != self.mediaArtworkFingerprint {
                        let artworkData = Data(base64Encoded: encoded)
                        self.mediaArtwork = artworkData.flatMap { NSImage(data: $0) }
                        self.mediaAtmosphere = self.mediaArtwork.flatMap { blurredArtwork($0) }
                        self.mediaLightColor = artworkData.flatMap { artworkLightColor($0) } ?? defaultMusicLightColor
                        self.mediaArtworkFingerprint = fingerprint
                    }
                } else { self.mediaArtwork = nil; self.mediaAtmosphere = nil; self.mediaArtworkFingerprint = nil; self.mediaLightColor = defaultMusicLightColor }
                self.refreshLyrics()
            } else if let message = event["message"] as? String {
                self.mediaTitle = message; self.mediaArtist = ""; self.mediaAvailable = false; self.mediaPlaying = false
                self.mediaDuration = 0; self.mediaElapsed = 0; self.mediaArtwork = nil; self.mediaAtmosphere = nil
                self.mediaArtworkFingerprint = nil; self.mediaLightColor = defaultMusicLightColor
            }
            if self.mediaRefreshPending { self.refreshMedia() }
        }
    }

    func refreshAgents() {
        guard !agentBusy else { return }; agentBusy = true
        run(["agents"]) { [weak self] event in
            guard let self = self else { return }
            if let rows = event["data"] as? [[String: Any]] {
                let updated: [AgentActivity] = rows.compactMap { row in
                    guard let id = row["id"] as? String, let project = row["project"] as? String, let state = row["state"] as? String else { return nil }
                    let knownActions: Set<String> = ["작업 실행", "웹 확인", "파일 수정", "도구 사용"]
                    let actions = (row["activities"] as? [String] ?? []).filter { knownActions.contains($0) }
                    return AgentActivity(id: id, project: project, state: state, activity: row["activity"] as? String ?? "", source: row["source"] as? String == "claude" ? "claude" : "codex", recentActivities: Array(actions.suffix(3)), ageSeconds: row["ageSeconds"] as? UInt64)
                }
                let arrival = agentArrival(previous: self.agentItems, current: updated, initialized: self.agentObservationReady)
                self.agentItems = updated; self.agentObservationReady = true
                if let cue = arrival { self.showLight(cue) }
                self.agentStatus = self.agentItems.isEmpty ? "최근 에이전트 활동 없음" : "최근 에이전트 활동"
                self.agentBusy = false
            } else if let message = event["message"] as? String { self.agentStatus = message; self.agentBusy = false }
        }
    }

    func openCodexThread(_ item: AgentActivity) {
        guard let url = codexThreadURL(item.id),
              let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") else {
            agentStatus = "Codex 앱이나 대화를 찾을 수 없습니다"
            return
        }
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            guard error != nil else { return }
            DispatchQueue.main.async { self?.agentStatus = "Codex에서 대화를 열지 못했습니다" }
        }
    }

    func controlMedia(_ action: String) {
        guard ["previous", "toggle", "next"].contains(action) else { return }
        mediaRevision += 1; mediaError = ""; mediaCommands.append(action); mediaControlPending = true
        sendNextMediaCommand()
    }
    private func sendNextMediaCommand() {
        guard !mediaCommandBusy, !mediaSeekPending, !mediaCommands.isEmpty else { return }
        mediaCommandBusy = true
        let action = mediaCommands.removeFirst()
        requestMedia(action) { [weak self] event in
            guard let self = self, let kind = event["event"] as? String, kind == "result" || kind == "error" else { return }
            self.mediaCommandBusy = false
            if kind == "error" { self.mediaError = event["message"] as? String ?? "재생 명령을 전달하지 못했습니다" }
            if !self.mediaCommands.isEmpty { self.sendNextMediaCommand(); return }
            self.mediaControlPending = false
            // The command can be accepted before the player updates metadata.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.refreshMedia() }
        }
    }

    func setLyricsEnabled(_ enabled: Bool) {
        lyricsEnabled = enabled; UserDefaults.standard.set(enabled, forKey: "rium.lyrics.enabled")
        lyricsGeneration += 1; lyricsKey = ""; lyricLines = []
        lyricsStatus = enabled ? "가사를 확인하는 중…" : "가사를 켜면 현재 곡을 조회합니다."
        if enabled { refreshLyrics() }
    }
    func refreshLyrics() {
        guard lyricsEnabled else { return }
        let title = mediaTitle.trimmingCharacters(in: .whitespacesAndNewlines), artist = mediaArtist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !artist.isEmpty, !title.isEmpty, title != "재생 중인 미디어 없음" else { lyricsGeneration += 1; lyricsKey = ""; lyricLines = []; lyricsStatus = "곡 제목과 아티스트를 기다리는 중"; return }
        let key = "\(title)\u{0}\(artist)\u{0}\(Int(min(mediaDuration, 604_800)))"
        if lyricsBusy { if key != lyricsKey { lyricsGeneration += 1; lyricsKey = ""; lyricLines = []; lyricsStatus = "새 곡의 가사를 기다리는 중" }; return }
        guard key != lyricsKey else { return }
        lyricsKey = key; lyricsGeneration += 1; let generation = lyricsGeneration
        lyricLines = []; lyricsStatus = "가사를 확인하는 중…"; lyricsBusy = true
        guard let input = try? JSONSerialization.data(withJSONObject: ["title":title, "artist":artist, "duration":mediaDuration]) else { lyricsBusy = false; lyricsStatus = "가사 요청을 만들 수 없습니다"; return }
        run(["lyrics"], input: input) { [weak self] event in
            guard let self = self else { return }
            self.lyricsBusy = false
            guard self.lyricsEnabled, generation == self.lyricsGeneration else { self.refreshLyrics(); return }
            if let data = event["data"] as? [String: Any] {
                self.lyricLines = parseLyrics(synced: data["synced"] as? String, plain: data["plain"] as? String)
                self.lyricsStatus = data["instrumental"] as? Bool == true ? "연주곡" : (self.lyricLines.isEmpty ? "이 곡의 가사를 찾지 못했습니다" : "가사 제공: LRCLIB")
            } else { self.lyricsStatus = event["message"] as? String ?? "가사를 불러올 수 없습니다" }
            self.refreshLyrics()
        }
    }

    func seekMedia(_ requested: Double) {
        guard requested.isFinite, mediaDuration.isFinite, mediaDuration > 0, !mediaSeekPending, !mediaControlPending else { return }
        let position = min(max(0, requested), min(mediaDuration, 604_800))
        mediaRevision += 1; mediaSeekPending = true; mediaError = ""
        mediaElapsed = position; mediaBaseElapsed = position; mediaObservedUptime = ProcessInfo.processInfo.systemUptime
        requestMedia("seek", position: String(position)) { [weak self] event in
            guard let self = self else { return }
            guard let kind = event["event"] as? String, kind == "result" || kind == "error" else { return }
            self.mediaSeekPending = false
            if let error = event["message"] as? String { self.mediaError = error }
            self.sendNextMediaCommand()
            // Acceptance means the command was sent, not that every player
            // supports it. Refresh from the player to show the actual position.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.refreshMedia() }
        }
    }

    func chooseWeatherCity() {
        let alert = NSAlert(); alert.messageText = "날씨 도시 선택"
        alert.informativeText = "도시 이름으로 날씨를 조회합니다. 선택한 도시의 좌표가 MET Norway에 전송됩니다."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24)); field.placeholderString = "예: 서울"
        alert.accessoryView = field; alert.addButton(withTitle: "조회"); alert.addButton(withTitle: "취소")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let city = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !city.isEmpty else { return }
        weatherLocator.cancel(); geocoder.cancelGeocode()
        weatherGeneration += 1; let geocodeGeneration = weatherGeneration
        weatherText = "도시 확인 중…"
        geocoder.geocodeAddressString(city) { [weak self] places, error in
            guard let self = self, self.weatherGeneration == geocodeGeneration else { return }
            guard error == nil, let place = places?.first, let coordinate = place.location?.coordinate else { self.weatherText = "도시를 찾을 수 없습니다"; return }
            UserDefaults.standard.set(false, forKey: "rium.weather.currentLocation")
            let roundedLat = (coordinate.latitude * 10000).rounded() / 10000
            let roundedLon = (coordinate.longitude * 10000).rounded() / 10000
            self.fetchWeather(city: city, lat: roundedLat, lon: roundedLon, timeZoneID: place.timeZone?.identifier)
        }
    }

    func useCurrentWeatherLocation() {
        weatherGeneration += 1; let generation = weatherGeneration
        geocoder.cancelGeocode(); lastWeatherAttempt = Date(); weatherText = "현재 위치 확인 중…"
        weatherLocator.request { [weak self] result in
            guard let self = self, self.weatherGeneration == generation else { return }
            switch result {
            case .failure(let error): self.weatherText = error.message
            case .success(let location):
                let coordinate = location.coordinate
                guard CLLocationCoordinate2DIsValid(coordinate) else { self.weatherText = "현재 위치를 확인하지 못했습니다"; return }
                let lat = (coordinate.latitude * 10_000).rounded() / 10_000
                let lon = (coordinate.longitude * 10_000).rounded() / 10_000
                UserDefaults.standard.set(true, forKey: "rium.weather.currentLocation")
                self.weatherText = "현재 위치의 날씨 확인 중…"
                self.geocoder.reverseGeocodeLocation(location) { [weak self] places, _ in
                    guard let self = self, self.weatherGeneration == generation else { return }
                    let place = places?.first
                    let city = place?.locality ?? place?.administrativeArea ?? "현재 위치"
                    self.fetchWeather(city: city, lat: lat, lon: lon, timeZoneID: place?.timeZone?.identifier)
                }
            }
        }
    }

    func refreshStaleWeather() {
        guard Date().timeIntervalSince(lastWeatherAttempt) >= 10_800,
              let cache = UserDefaults.standard.dictionary(forKey: "rium.weather.cache"),
              let updated = cache["updated"] as? Double, Date().timeIntervalSince1970 - updated >= 10_800,
              let lat = cache["lat"] as? Double, let lon = cache["lon"] as? Double,
              let city = cache["city"] as? String else { return }
        if UserDefaults.standard.bool(forKey: "rium.weather.currentLocation") { useCurrentWeatherLocation(); return }
        fetchWeather(city: city, lat: lat, lon: lon, timeZoneID: cache["timezone"] as? String)
    }

    func fetchWeather(city: String, lat: Double, lon: Double, timeZoneID: String? = nil) {
        weatherGeneration += 1; let generation = weatherGeneration
        let defaults = UserDefaults.standard
        if let cache = defaults.dictionary(forKey: "rium.weather.cache"), let oldLat = cache["lat"] as? Double,
           let oldLon = cache["lon"] as? Double, oldLat == lat, oldLon == lon,
           let updated = cache["updated"] as? Double, (0..<10_800).contains(Date().timeIntervalSince1970 - updated),
           let data = cache["data"] as? [String: Any] {
            var updatedCache = cache
            updatedCache["city"] = city
            if let id = timeZoneID, TimeZone(identifier: id) != nil { updatedCache["timezone"] = id }
            defaults.set(updatedCache, forKey: "rium.weather.cache")
            showWeather(city: city, data: data, updated: Date(timeIntervalSince1970: updated), timeZoneID: timeZoneID ?? (cache["timezone"] as? String)); return
        }
        lastWeatherAttempt = Date()
        weatherText = "날씨 조회 중…"
        run(["weather", String(lat), String(lon)]) { [weak self] event in
            guard let self = self, self.weatherGeneration == generation else { return }
            if let data = event["data"] as? [String: Any] {
                guard let temperature = data["temperature"] as? Double else { self.weatherText = "날씨를 읽을 수 없습니다"; return }
                let hours = weatherHours(data["hourly"] as? [[String: Any]] ?? [])
                let safeHours: [[String: Any]] = hours.map { hour in
                    var row: [String: Any] = ["time": hour.id, "temperature": hour.temperature, "symbol": hour.symbol]
                    if let precipitation = hour.precipitation { row["precipitation"] = precipitation }
                    return row
                }
                let safeData: [String: Any] = ["temperature": temperature, "symbol": data["symbol"] as? String ?? "", "hourly": safeHours]
                var entry: [String: Any] = ["lat": lat, "lon": lon, "city": city, "updated": Date().timeIntervalSince1970, "data": safeData]
                if let id = timeZoneID, TimeZone(identifier: id) != nil { entry["timezone"] = id }
                defaults.set(entry, forKey: "rium.weather.cache")
                self.showWeather(city: city, data: safeData, timeZoneID: timeZoneID)
            } else if let error = event["message"] as? String {
                if let cache = defaults.dictionary(forKey: "rium.weather.cache"), let oldLat = cache["lat"] as? Double,
                   let oldLon = cache["lon"] as? Double, oldLat == lat, oldLon == lon,
                   let updated = cache["updated"] as? Double, let data = cache["data"] as? [String: Any] {
                    self.showWeather(city: city, data: data, updated: Date(timeIntervalSince1970: updated), timeZoneID: cache["timezone"] as? String); self.weatherDetail += " · 연결 실패"
                } else { self.weatherText = error }
            }
        }
    }

    func showWeather(city: String, data: [String: Any], updated: Date = Date(), timeZoneID: String? = nil) {
        guard let temp = data["temperature"] as? Double else { weatherText = "날씨를 읽을 수 없습니다"; return }
        let symbol = data["symbol"] as? String ?? ""
        let description = weatherDescription(symbol)
        weatherText = String(format: "%@  %.0f°  %@", city, temp, description)
        weatherCity = city; weatherCondition = description; weatherTemperature = temp
        weatherForecast = weatherHours(data["hourly"] as? [[String: Any]] ?? [])
        weatherTimeZoneID = timeZoneID.flatMap { TimeZone(identifier: $0) != nil ? $0 : nil }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "ko_KR"); formatter.dateFormat = "M/d HH:mm"
        let stale = Date().timeIntervalSince(updated) >= 10_800 ? " · 업데이트 필요" : ""
        weatherDetail = "MET Norway · \(formatter.string(from: updated))\(stale)"
    }

    func sample() {
        var value = -1.0, used: UInt64 = 0, total: UInt64 = 0, swapped: UInt64 = 0
        let flags = readMetrics(&value, &used, &total, &swapped)
        let cpuValue: Double? = flags & 1 != 0 && value.isFinite && (0...100).contains(value) ? value : nil
        cpu = flags & 1 == 0 ? "조회 불가" : (value == -1 ? "측정 중" : (cpuValue.map { String(format: "%.0f%%", $0) } ?? "조회 불가"))
        let memoryValue = memoryUsagePercent(used: used, total: total, available: flags & 2 != 0)
        memory = memoryValue == nil ? "조회 불가" : String(format: "%.1f / %.1f GB", Double(used) / 1_000_000_000, Double(total) / 1_000_000_000)
        memoryPercent = memoryValue.map { String(format: "%.0f%%", $0) } ?? "조회 불가"
        swap = flags & 4 == 0 ? "조회 불가" : String(format: "%.1f GB", Double(swapped) / 1_000_000_000)
        pressure = currentMemoryPressure() ?? pressureEvent ?? "조회 불가"
        appendMonitorSample(cpuValue, to: &cpuHistory)
        appendMonitorSample(memoryValue, to: &memoryHistory)
    }

    // Each operation is isolated from the UI thread. The Rust helper keeps the
    // existing Rium Dock account profiles and asks the official Codex CLI.
    func run(_ args: [String], input: Data? = nil, event: @escaping ([String: Any]) -> Void) {
        guard let executable = Bundle.main.url(forAuxiliaryExecutable: "rium-notch-core") else { event(["event":"error", "message":"기능 도구를 찾을 수 없습니다"]); return }
        DispatchQueue.global(qos: .utility).async {
            let process = Process(); process.executableURL = executable; process.arguments = args
            let pipe = Pipe(); process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
            let inputPipe = input.map { _ in Pipe() }
            if let inputPipe = inputPipe { process.standardInput = inputPipe }
            do { try process.run() } catch { DispatchQueue.main.async { event(["event":"error", "message":"기능 도구를 실행할 수 없습니다"]) }; return }
            if let inputPipe = inputPipe, let input = input { try? inputPipe.fileHandleForWriting.write(contentsOf: input); try? inputPipe.fileHandleForWriting.close() }
            var buffer = Data()
            var terminalEvent = false
            while true {
                // availableData returns as soon as a line arrives. A fixed-size
                // read can wait for EOF and deadlock the interactive login flow.
                let data = pipe.fileHandleForReading.availableData
                if data.isEmpty { break }
                buffer.append(data)
                if buffer.count > 2_100_000 {
                    if process.isRunning { process.terminate() }
                    terminalEvent = true
                    DispatchQueue.main.async { event(["event":"error", "message":"기능 응답이 너무 큽니다"]) }
                    break
                }
                while let newline = buffer.firstIndex(of: 10) {
                    let line = buffer.prefix(upTo: newline); buffer.removeSubrange(...newline)
                    if let item = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                        if let kind = item["event"] as? String, kind == "result" || kind == "error" { terminalEvent = true }
                        DispatchQueue.main.async { event(item) }
                    }
                }
            }
            process.waitUntilExit()
            if !terminalEvent { DispatchQueue.main.async { event(["event":"error", "message":"기능 도구가 응답 없이 종료되었습니다"]) } }
        }
    }

    func listAccounts() {
        run(["list"]) { [weak self] e in
            guard let self = self else { return }
            if let rows = e["data"] as? [[String: Any]] {
                self.accounts = rows.compactMap { row in
                    guard let id = row["id"] as? String, let name = row["name"] as? String else { return nil }
                    return Account(id: id, name: name)
                }
                for account in self.accounts { self.refresh(account.id) }
            } else if let error = e["message"] as? String { self.message = error }
        }
    }

    func refresh(_ id: String) {
        guard !busy.contains(id) else { return }
        busy.insert(id)
        run(["refresh", id]) { [weak self] e in
            guard let self = self else { return }
            if e["event"] as? String == "result" {
                let data = e["data"] as? [String: Any] ?? [:]
                let status = data["status"] as? String ?? "unknown"
                let label: String
                switch status {
                case "connected": label = codexWindow(data["primary"]) ?? "사용량 조회 불가"
                case "disconnected": label = "로그인 필요"
                case "unsupported": label = "지원하지 않는 계정"
                default: label = "계정 상태 확인 불가"
                }
                var details: [String] = []
                if status == "connected", let secondary = codexWindow(data["secondary"]) { details.append(secondary) }
                if status == "connected", data["ordinaryUsageAllowed"] as? Bool == false { details.append("기본 사용 제한 중") }
                if status == "connected", data["spendControlReached"] as? Bool == true { details.append("지출 한도 도달") }
                if status == "connected" { details.append(contentsOf: codexRestrictions(data)) }
                if status == "connected", let available = data["resetCreditsAvailable"] as? Int, available > 0 { details.append("한도 초기화 크레딧 \(available)개") }
                if status == "connected", let credits = data["credits"] as? [String: Any] {
                    if credits["unlimited"] as? Bool == true { details.append("크레딧 무제한") }
                    else if let balance = credits["balance"] as? String, let number = Double(balance) { details.append(String(format: "크레딧 %.2f", number)) }
                    else if let balance = credits["balance"] as? NSNumber { details.append(String(format: "크레딧 %.2f", balance.doubleValue)) }
                }
                if let i = self.accounts.firstIndex(where: { $0.id == id }) {
                    self.accounts[i].usage = label
                    self.accounts[i].detail = details.joined(separator: " · ")
                    self.accounts[i].additionalUsage = status == "connected" ? codexAdditionalUsage(data) : []
                    self.accounts[i].connected = status == "connected"
                }
                self.busy.remove(id)
            } else if let error = e["message"] as? String {
                if let i = self.accounts.firstIndex(where: { $0.id == id }) { self.accounts[i].usage = error; self.accounts[i].detail = ""; self.accounts[i].additionalUsage = [] }
                self.busy.remove(id)
            }
        }
    }

    func login(_ id: String) {
        guard !busy.contains(id) else { return }; busy.insert(id); message = "로그인 창을 기다리는 중"
        run(["login", id]) { [weak self] e in
            guard let self = self else { return }
            if e["event"] as? String == "login_url", let str = e["url"] as? String, let url = URL(string: str), url.host == "auth.openai.com" { NSWorkspace.shared.open(url) }
            if e["event"] as? String == "result" { self.busy.remove(id); self.message = "로그인 완료"; self.refresh(id) }
            if let error = e["message"] as? String { self.busy.remove(id); self.message = error }
        }
    }

    func addAccount() {
        let alert = NSAlert(); alert.messageText = "Codex 계정 추가"; alert.informativeText = "이 Mac에서 구분할 이름을 입력하세요."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24)); alert.accessoryView = field
        alert.addButton(withTitle: "추가"); alert.addButton(withTitle: "취소")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        run(["create", name]) { [weak self] e in
            if let row = e["data"] as? [String: Any], let id = row["id"] as? String { self?.listAccounts(); self?.login(id) }
            else if let error = e["message"] as? String { self?.message = error }
        }
    }
    func renameAccount(_ account: Account) {
        guard !busy.contains(account.id) else { message = "계정 작업이 진행 중입니다"; return }
        let alert = NSAlert(); alert.messageText = "계정 이름 변경"
        alert.informativeText = "이 이름은 Rium Dock에도 함께 반영됩니다."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24)); field.stringValue = account.name
        alert.accessoryView = field; alert.addButton(withTitle: "변경"); alert.addButton(withTitle: "취소")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { message = "계정 이름을 입력해 주세요"; return }
        busy.insert(account.id); message = "계정 이름 변경 중"
        run(["rename", account.id, name]) { [weak self] event in
            guard let self = self else { return }
            if event["event"] as? String == "result" {
                if let i = self.accounts.firstIndex(where: { $0.id == account.id }) { self.accounts[i].name = name }
                self.busy.remove(account.id); self.message = "계정 이름을 변경했습니다"
            } else if let error = event["message"] as? String {
                self.busy.remove(account.id); self.message = error
            }
        }
    }
    func removeAccount(_ account: Account) {
        guard !busy.contains(account.id) else { message = "계정 작업이 진행 중입니다"; return }
        let alert = NSAlert(); alert.alertStyle = .warning; alert.messageText = "계정 연결 해제"
        alert.informativeText = "이 Mac의 공용 계정 정보가 삭제되고 Rium Dock에서도 로그아웃됩니다. OpenAI 계정 자체는 삭제되지 않습니다."
        alert.addButton(withTitle: "연결 해제"); alert.addButton(withTitle: "취소")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        busy.insert(account.id); message = "계정 연결 해제 중"
        run(["remove", account.id]) { [weak self] event in
            guard let self = self else { return }
            if event["event"] as? String == "result" {
                self.accounts.removeAll { $0.id == account.id }
                self.busy.remove(account.id); self.message = "계정 연결을 해제했습니다"
            } else if let error = event["message"] as? String {
                self.busy.remove(account.id); self.message = error
            }
        }
    }
}

struct ClipboardRecordButton: View {
    let record: ClipboardRecord
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: compact ? 6 : 10) {
                switch record.content {
                case .text(let value):
                    Image(systemName: "doc.text").frame(width: compact ? 22 : 34, height: compact ? 18 : 34)
                    Text(value).lineLimit(compact ? 1 : 2)
                case .files(let urls):
                    Image(systemName: "doc").frame(width: compact ? 22 : 34, height: compact ? 18 : 34)
                    Text(urls.count == 1 ? urls[0].lastPathComponent : "\(urls[0].lastPathComponent) 외 \(urls.count - 1)개").lineLimit(1)
                case .image(let data, _):
                    if let image = NSImage(data: data) {
                        Image(nsImage: image).resizable().scaledToFit().frame(width: compact ? 22 : 34, height: compact ? 18 : 34).clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    Text("이미지 · \(clipboardImageSize(data.count))").lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(compact ? 0 : 8)
            .background(.white.opacity(compact ? 0 : 0.06), in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain).help("다시 복사")
    }
}

struct ClipboardView: View {
    @ObservedObject var model: Model
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("클립보드").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button(model.clipboardEnabled ? "기록 끄기" : "기록 켜기") { model.toggleClipboard() }.disabled(!model.clipboardReady)
                if !model.clipboardItems.isEmpty { Button("기록 지우기") { model.clearClipboardHistory() } }
            }.buttonStyle(.plain)
            if model.clipboardItems.isEmpty {
                Spacer()
                Text(!model.clipboardReady ? "기록을 불러오는 중입니다." : (model.clipboardEnabled ? "복사한 텍스트, 이미지, 파일이 여기에 표시됩니다." : "기록을 켜면 복사한 항목을 이 Mac에 저장합니다."))
                    .font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(model.clipboardItems) { record in ClipboardRecordButton(record: record) { model.copyClipboard(record) } }
                    }
                }
            }
            Text(model.clipboardStorageStatus.isEmpty ? "항목을 선택하면 다시 복사합니다. 기록은 이 Mac에 저장되며 직접 지울 수 있습니다." : model.clipboardStorageStatus).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).font(.system(size: 12))
    }
}

// Compact activity shown beside the physical camera cutout. Its two eyes and
// activity capsules follow the observed Glance running state; no project or
// prompt text is exposed in the collapsed notch.
struct CollapsedAgentFace: View {
    let waiting: Bool
    let claude: Bool
    var body: some View {
        let tint: Color = waiting ? .orange : (claude ? Color(red: 0.85, green: 0.53, blue: 0.39) : Color(red: 0.28, green: 0.67, blue: 1))
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(tint.gradient)
            .frame(width: 19, height: 18)
            .overlay {
                HStack(spacing: 2.5) {
                    Capsule().frame(width: 1.6, height: 4.5)
                    Capsule().frame(width: 1.6, height: 4.5)
                }.foregroundStyle(Color.black.opacity(0.85)).offset(y: -1.5)
            }
            .accessibilityHidden(true)
    }
}

struct CollapsedAgentPulse: View {
    let waiting: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let heights: [CGFloat] = [3, 4, 3, 5, 3, 4, 3, 5, 3, 4, 3]
                let unit = (size.width - 8) / CGFloat(heights.count)
                for i in heights.indices {
                    let pulse = CGFloat(0.65 + 0.35 * (0.5 + 0.5 * sin(time * 4.2 + Double(i) * 0.9)))
                    let height = heights[i] * pulse
                    let width = max(2, unit - 1.2)
                    let rect = CGRect(x: 4 + CGFloat(i) * unit, y: (size.height - height) / 2, width: width, height: height)
                    context.fill(Path(roundedRect: rect, cornerRadius: min(height, width) / 2), with: .color(.white.opacity(0.8 + Double(pulse) * 0.2)))
                }
            }
        }
        .frame(width: 57, height: 18)
        .background(waiting ? Color.orange.opacity(0.25) : Color(red: 0.08, green: 0.10, blue: 0.32), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.06), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}

// A playing indicator until system-audio visualizer access is implemented.
// Its movement is decorative and does not claim to measure audio levels.
struct CollapsedMusicWave: View {
    let tint: NSColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 1.5) {
                ForEach(0..<4) { index in
                    let height = 3 + 8 * (0.5 + 0.5 * sin(time * 3.6 + Double(index) * 1.2))
                    Capsule().fill(Color(nsColor: tint)).frame(width: 2, height: height)
                }
            }.frame(width: 17, height: 18)
        }.accessibilityHidden(true)
    }
}

struct NotchView: View {
    @ObservedObject var model: Model

    @ViewBuilder private func collapsedAgentHeader() -> some View {
        if model.showsCollapsedAgent, let agent = collapsedAgent(model.agentItems) {
            Button(action: { model.select(.agents); model.expanded = true }) {
                CollapsedAgentFace(waiting: agent.state.hasPrefix("승인 대기"), claude: agent.source == "claude")
            }.buttonStyle(.plain)
            .accessibilityLabel("\(agent.providerName) \(agent.state)")
            .help("에이전트 활동 열기")
        } else if model.mediaPlaying {
            Button(action: { model.select(.music); model.expanded = true }) {
                HStack(spacing: 2) {
                    Group {
                        if let artwork = model.mediaArtwork { Image(nsImage: artwork).resizable().scaledToFill() }
                        else { Image(systemName: "music.note").font(.system(size: 10)).foregroundStyle(.white).frame(maxWidth: .infinity, maxHeight: .infinity).background(.white.opacity(0.15)) }
                    }.frame(width: 19, height: 19).clipShape(RoundedRectangle(cornerRadius: 4))
                    if model.timerState != 0 { CollapsedMusicWave(tint: model.mediaLightColor) }
                }
            }.buttonStyle(.plain).help("음악 열기").accessibilityLabel("음악 열기")
        } else if model.timerState != 0 {
            Button(action: { model.select(.monitor); model.expanded = true }) {
                Image(systemName: model.timerState == 3 ? "checkmark.circle.fill" : "timer").font(.system(size: 13, weight: .medium)).frame(width: 19, height: 19)
            }.buttonStyle(.plain).help("타이머 열기").accessibilityLabel("타이머 열기")
        }
    }
    @ViewBuilder private func headerControls(compact: Bool) -> some View {
        if model.showsCollapsedAgent, let agent = collapsedAgent(model.agentItems) {
            Button(action: { model.select(.agents); model.expanded = true }) {
                CollapsedAgentPulse(waiting: agent.state.hasPrefix("승인 대기"))
            }.buttonStyle(.plain).accessibilityLabel("\(agent.providerName) \(agent.state)").help("에이전트 활동 열기")
        } else if !model.volumeOverlay.isEmpty {
            Label(model.volumeOverlay, systemImage: model.overlaySymbol).font(.system(size: compact ? 9 : 11, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7)
        } else if timerSummary(state: model.timerState, remaining: model.timerRemaining, phase: model.timerPomodoro ? model.timerPhase : nil) != nil {
            Button(action: { model.select(.monitor); model.expanded = true }) {
                Text(String(format: "%02llu:%02llu", model.timerRemaining / 60, model.timerRemaining % 60))
                    .font(.system(size: compact ? 10 : 11, weight: .medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
            }.buttonStyle(.plain).help("타이머 열기").accessibilityLabel("타이머 \(model.timerRemaining / 60)분 \(model.timerRemaining % 60)초")
        } else if model.mediaPlaying {
            Button(action: { model.select(.music); model.expanded = true }) {
                CollapsedMusicWave(tint: model.mediaLightColor)
            }.buttonStyle(.plain).help("음악 열기").accessibilityLabel("음악 재생 중")
        } else if usageTrackingEnabled {
            Button(action: { model.select(.monitor); model.expanded = true }) {
                HStack(spacing: compact ? 3 : 8) {
                    Text("CPU \(model.cpu)"); Text("RAM \(model.memoryPercent)")
                    if !compact { Text(model.pressure) }
                }.font(.system(size: compact ? 9 : 11, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7)
            }.buttonStyle(.plain).help("시스템 모니터링")
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.expanded {
                // Reserve the physical camera area without inventing an app
                // title or monitoring controls inside the expanded notch.
                Color.clear.frame(height: max(0, (model.cameraHeight > 0 ? model.cameraHeight : 32) - 17))
                    .allowsHitTesting(false).accessibilityHidden(true)
            } else if model.collapsedIsIdle {
                EmptyView()
            } else if model.cameraExclusion > 0 {
                let metrics = collapsedHeaderMetrics(width: model.currentNotchSize.width, cameraWidth: model.cameraExclusion)
                let gap = metrics.gap, side = metrics.side
                HStack(spacing: 0) {
                    collapsedAgentHeader().frame(width: side, alignment: .leading)
                    Color.clear.frame(width: gap).allowsHitTesting(false).accessibilityHidden(true)
                    HStack(spacing: 4) { headerControls(compact: !model.expanded) }.frame(width: side, alignment: .trailing)
                }
            } else {
                HStack {
                    collapsedAgentHeader()
                    Spacer(); headerControls(compact: false)
                }
            }
            if model.expanded {
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        TabButton(model: model, section: .home, icon: "square.grid.2x2", title: "홈")
                        TabButton(model: model, section: .agents, icon: "bubble.left.and.bubble.right", title: "작업")
                        TabButton(model: model, section: .dictation, icon: "waveform", title: "받아쓰기")
                        TabButton(model: model, section: .clipboard, icon: "clipboard", title: "클립보드")
                        Button(action: { model.teleprompter.show() }) { Image(systemName: "text.alignleft").frame(width: 52, height: 28) }.help("프롬프터").accessibilityLabel("프롬프터")
                    }
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(.white.opacity(0.10), in: Capsule())
                    Spacer()
                    Menu {
                        Button("홈 편집 (준비 중)") {}.disabled(true)
                        Button("탭 편집 (준비 중)") {}.disabled(true)
                        Menu("다른 기능") {
                            Button("음악") { model.select(.music) }
                            Button("날씨") { model.select(.weather) }
                            Button("일정과 미리 알림") { model.select(.agenda) }
                            Button("보관함") { model.select(.shelf) }
                            Button("집중 타이머") { model.select(.monitor) }
                            if usageTrackingEnabled { Button("시스템 모니터링") { model.select(.monitor) } }
                        }
                        Divider()
                        Button("설정…") { (NSApp.delegate as? AppDelegate)?.showSettings() }
                        Divider()
                        Button("Rium Notch 종료") { NSApp.terminate(nil) }
                    } label: { Image(systemName: "ellipsis").frame(width: 30, height: 28).background(.white.opacity(0.09), in: Circle()) }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).help("더 보기").accessibilityLabel("더 보기")
                }.buttonStyle(.plain).font(.system(size: 12, weight: .medium)).padding(.trailing, -14)
                if model.section == .home {
                    HomeView(model: model, agenda: model.agenda)
                } else if model.section == .dictation {
                    DictationView(model: model.dictation)
                } else if model.section == .agents {
                    AgentView(model: model)
                } else if model.section == .music {
                    MusicView(model: model)
                } else if model.section == .shelf {
                    ShelfView(model: model)
                } else if model.section == .clipboard {
                    ClipboardView(model: model)
                } else if model.section == .weather {
                    WeatherView(model: model)
                } else if model.section == .agenda {
                    AgendaView(model: model.agenda)
                } else {
                if usageTrackingEnabled {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("시스템 모니터링").font(.system(size: 14, weight: .semibold))
                        HStack { VStack(alignment: .leading) { Text("CPU  \(model.cpu)"); Text("최근 사용률").font(.caption2).foregroundStyle(.secondary) }; Spacer(); Sparkline(samples: model.cpuHistory).stroke(Color.cyan.opacity(0.8), lineWidth: 1.5).frame(width: 100, height: 23).accessibilityHidden(true) }
                        HStack { VStack(alignment: .leading) { Text("RAM  \(model.memoryPercent)"); Text(model.memory).font(.caption2).foregroundStyle(.secondary) }; Spacer(); Sparkline(samples: model.memoryHistory).stroke(Color.purple.opacity(0.9), lineWidth: 1.5).frame(width: 100, height: 23).accessibilityHidden(true) }
                        HStack { Text("메모리 압력  \(model.pressure)"); Spacer(); Text("스왑  \(model.swap)") }.font(.caption)
                        HStack { Text(model.volume); Spacer(); Text(model.brightness) }.font(.caption)
                        PowerSummary(model: model.power).font(.caption)
                    }.frame(maxWidth: .infinity, alignment: .leading).riumTile()
                    VStack(alignment: .leading, spacing: 7) {
                        HStack { Text("Codex 계정").font(.system(size: 14, weight: .semibold)); Spacer(); Button("추가") { model.addAccount() }.buttonStyle(.plain) }
                        if model.accounts.isEmpty { Text("연결된 계정 없음").foregroundStyle(.secondary) }
                        if !model.accounts.isEmpty { ScrollView { VStack(alignment: .leading, spacing: 8) {
                            ForEach(model.accounts) { account in
                                HStack(alignment: .top) { VStack(alignment: .leading) { Text(account.name); Text(account.usage).font(.caption).foregroundStyle(.secondary); if !account.detail.isEmpty { Text(account.detail).font(.caption).foregroundStyle(.secondary) }; ForEach(Array(account.additionalUsage.enumerated()), id: \.offset) { _, line in Text(line).font(.caption).foregroundStyle(.secondary) } }; Spacer(); if !account.connected { Button("로그인") { model.login(account.id) }.buttonStyle(.plain) }; Button("새로고침") { model.refresh(account.id) }.buttonStyle(.plain)
                                    Menu("관리") {
                                        Button("이름 변경…") { model.renameAccount(account) }
                                        Button("연결 해제…", role: .destructive) { model.removeAccount(account) }
                                    }
                                    .menuStyle(.borderlessButton).fixedSize().help("계정 관리").accessibilityLabel("\(account.name) 계정 관리")
                                }
                            }
                        } }.frame(height: 112) }
                        if !model.message.isEmpty { Text(model.message).font(.caption).foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading).riumTile()
                }.font(.system(size: 12))
                Divider().overlay(.white.opacity(0.12))
                }
                HStack {
                    Text(model.timerPomodoro ? "포모도로 · \(model.timerPhase.title)" : "집중 타이머").font(.system(size: 13, weight: .semibold))
                    Text(String(format: "%02llu:%02llu", model.timerRemaining / 60, model.timerRemaining % 60)).monospacedDigit()
                    if model.timerPomodoro { Text("집중 완료 \(model.timerSessions)회").foregroundStyle(.secondary) }
                    if model.timerState == 3 { Text("완료").foregroundStyle(.secondary) }
                    Spacer()
                    if model.timerState == 1 {
                        Button("일시 정지") { model.pauseTimer() }
                    } else if model.timerState == 2 {
                        Button("계속") { model.resumeTimer() }
                    } else {
                        Menu("시작") {
                            ForEach([5, 10, 25, 50], id: \.self) { minutes in
                                Button("\(minutes)분") { model.startTimer(UInt32(minutes * 60)) }
                            }
                            Button("포모도로 시작 (\(model.pomodoroFocus)분 · \(model.pomodoroShortBreak)분)") { model.startPomodoro() }
                            Button("직접 입력…") { model.customTimer() }
                        }
                    }
                    if model.timerState != 0 { Button("초기화") { model.resetTimer() } }
                }.buttonStyle(.plain).font(.system(size: 12))
                Divider().overlay(.white.opacity(0.12))
                HStack {
                    Text("클립보드").font(.system(size: 13, weight: .semibold)); Spacer()
                    Button(model.clipboardEnabled ? "기록 끄기" : "기록 켜기") { model.toggleClipboard() }.disabled(!model.clipboardReady)
                    Button("모두 보기") { model.select(.clipboard) }
                    if !model.clipboardItems.isEmpty { Button("기록 지우기") { model.clearClipboardHistory() } }
                }.buttonStyle(.plain).font(.system(size: 12))
                if model.clipboardItems.isEmpty {
                    Text(!model.clipboardReady ? "기록을 불러오는 중입니다." : (model.clipboardEnabled ? "복사한 텍스트, 이미지, 파일이 여기에 표시됩니다." : "기록을 켜면 복사한 항목을 이 Mac에 저장합니다.")).font(.caption).foregroundStyle(.secondary)
                } else {
                    ScrollView { VStack(alignment: .leading, spacing: 4) {
                        ForEach(model.clipboardItems) { record in
                            ClipboardRecordButton(record: record, compact: true) { model.copyClipboard(record) }
                        }
                    }}.frame(maxHeight: 65)
                }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 26).padding(.vertical, model.expanded ? 12 : 8)
        .frame(width: model.currentNotchSize.width, height: model.currentNotchSize.height, alignment: .top)
        // The persistent opaque background is drawn by NotchContainer.
        .foregroundStyle(.white)
        .contentShape(NotchSilhouette())
        .overlay {
            if model.fileDragActive {
                NotchSilhouette().stroke(.orange.opacity(0.65), lineWidth: 2).blur(radius: 2).allowsHitTesting(false)
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: Binding(get: { model.fileDragActive }, set: { model.setFileDragActive($0) })) { model.receiveFileDrop($0) }
        .onTapGesture { if !model.expanded { model.expanded = true } }
        .onChange(of: model.expanded) { _, value in NotificationCenter.default.post(name: .notchSizeChanged, object: notchHeight(expanded: value, section: model.section)) }
        .onChange(of: model.section) { _, section in if model.expanded { NotificationCenter.default.post(name: .notchSizeChanged, object: notchHeight(expanded: true, section: section)) } }
    }
}

// Append the open left-to-right edge to a path already at rect.minX/minY.
// The silhouette and light stroke must share the same geometry.
func appendNotchContour(to path: inout Path, in rect: CGRect) {
    let shoulder = max(0, min(20, rect.height / 3, rect.width / 3))
    let left = rect.minX + shoulder, right = rect.maxX - shoulder
    let top = rect.minY, bottom = rect.maxY
    let corner = max(0, min(shoulder, (right - left) / 2, rect.height / 2))
    // Glance's NotchShoulderShape uses separate 0.22 shoulder and
    // 0.78 lower-corner Bézier control factors. Radii remain our choices.
    let upperControl = shoulder * 0.22, lowerControl = corner * 0.78
    path.addCurve(to: CGPoint(x: left, y: top + shoulder),
                  control1: CGPoint(x: left - upperControl, y: top),
                  control2: CGPoint(x: left, y: top + upperControl))
    path.addLine(to: CGPoint(x: left, y: bottom - corner))
    path.addCurve(to: CGPoint(x: left + corner, y: bottom),
                  control1: CGPoint(x: left, y: bottom - corner + lowerControl),
                  control2: CGPoint(x: left + corner - lowerControl, y: bottom))
    path.addLine(to: CGPoint(x: right - corner, y: bottom))
    path.addCurve(to: CGPoint(x: right, y: bottom - corner),
                  control1: CGPoint(x: right - corner + lowerControl, y: bottom),
                  control2: CGPoint(x: right, y: bottom - corner + lowerControl))
    path.addLine(to: CGPoint(x: right, y: top + shoulder))
    path.addCurve(to: CGPoint(x: right + shoulder, y: top),
                  control1: CGPoint(x: right, y: top + upperControl),
                  control2: CGPoint(x: right + upperControl, y: top))
}

struct NotchSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        appendNotchContour(to: &path, in: rect)
        path.closeSubpath(); return path
    }
}

struct PowerSummary: View {
    @ObservedObject var model: PowerModel
    var body: some View { Text(model.summary).foregroundStyle(model.percentage.map { $0 <= 10 ? Color.red : ($0 <= 20 ? Color.orange : Color.white) } ?? Color.secondary) }
}

struct TabButton: View {
    @ObservedObject var model: Model
    let section: PanelSection
    let icon: String
    let title: String
    var body: some View {
        Button(action: { model.select(section) }) {
            HStack(spacing: 6) {
                Image(systemName: icon).frame(width: 16)
                if section == .agents {
                    let count = model.agentItems.filter { ["작업 중", "활동 감지", "도구 실행 감지"].contains($0.state) || $0.state.hasPrefix("승인 대기") }.count
                    if count > 0 { Text("\(count)").font(.system(size: 10, weight: .semibold)).foregroundStyle(.black).padding(.horizontal, 6).padding(.vertical, 2).background(Color.blue, in: Capsule()) }
                }
                if section == .clipboard && !model.clipboardItems.isEmpty {
                    Text("\(model.clipboardItems.count)").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                }
                if model.section == section { Text(title).lineLimit(1) }
            }
            .padding(.horizontal, 9).frame(minWidth: 52, minHeight: 28)
            .background(model.section == section ? Color.white.opacity(0.18) : Color.clear, in: Capsule())
        }.buttonStyle(.plain).help(title).accessibilityLabel(title)
    }
}

func mainWeatherPreview(_ model: Model) -> [WeatherHour] {
    Array(model.weatherForecast.filter { $0.date > model.now }.prefix(3))
}

func homeWeatherHour(_ date: Date, timeZoneID: String?) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "H"
    if let timeZoneID = timeZoneID, let zone = TimeZone(identifier: timeZoneID) { formatter.timeZone = zone }
    return formatter.string(from: date)
}

struct HomeView: View {
    @ObservedObject var model: Model
    @ObservedObject var agenda: AgendaModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 7) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Group {
                            if let artwork = model.mediaArtwork { Image(nsImage: artwork).resizable().scaledToFill() }
                            else { Image(systemName: "music.note").resizable().scaledToFit().padding(10).foregroundStyle(.white.opacity(0.7)).background(Color.white.opacity(0.08)) }
                        }.frame(width: 42, height: 42).clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        Button(action: { model.select(.music) }) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.mediaTitle).fontWeight(.medium).lineLimit(1)
                                Text(model.mediaArtist.isEmpty ? "음악" : model.mediaArtist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain)
                    }
                    if model.mediaDuration > 0 {
                        ProgressView(value: min(max(model.mediaElapsed / model.mediaDuration, 0), 1)).tint(.white).controlSize(.mini)
                    } else { Capsule().fill(.white.opacity(0.15)).frame(height: 2) }
                    Spacer(minLength: 0)
                    HStack {
                        Button(action: { model.controlMedia("previous") }) { Image(systemName: "backward.fill").frame(width: 23, height: 23).overlay(Circle().stroke(.white.opacity(0.20), lineWidth: 1)) }.help("이전 곡")
                        Spacer()
                        Button(action: { model.controlMedia("toggle") }) { Image(systemName: model.mediaPlaying ? "pause.fill" : "play.fill").foregroundStyle(.black).frame(width: 27, height: 27).background(.white, in: Circle()) }.help(model.mediaPlaying ? "일시 정지" : "재생")
                        Spacer()
                        Button(action: { model.controlMedia("next") }) { Image(systemName: "forward.fill").frame(width: 23, height: 23).overlay(Circle().stroke(.white.opacity(0.20), lineWidth: 1)) }.help("다음 곡")
                    }.buttonStyle(.plain).disabled(!model.mediaAvailable || model.mediaControlPending)
                }.frame(maxWidth: .infinity, minHeight: 94, maxHeight: 94, alignment: .topLeading).riumGlassTile(artwork: model.mediaAtmosphere, tint: .pink, radius: 24)
                Button(action: { model.select(.agents) }) {
                    VStack(alignment: .leading, spacing: 2) {
                        if let agent = collapsedAgent(model.agentItems) {
                            HStack {
                                Text(agent.providerName).font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Circle().fill(Color.blue).frame(width: 6, height: 6)
                            }
                            Text(agent.state).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            Spacer(minLength: 0)
                            HStack {
                                Spacer()
                                CollapsedAgentFace(waiting: agent.state.hasPrefix("승인 대기"), claude: agent.source == "claude")
                                    .scaleEffect(2.3).frame(width: 46, height: 46)
                                Spacer()
                            }
                        } else {
                            Text("에이전트").font(.caption).foregroundStyle(.secondary)
                            Text("최근 활동 없음").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }.frame(maxWidth: .infinity, minHeight: 94, maxHeight: 94, alignment: .topLeading).riumGlassTile(tint: collapsedAgent(model.agentItems) == nil ? .clear : .blue, radius: 24)
                }.buttonStyle(.plain)
                Button(action: { model.select(.weather) }) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.weatherCity.isEmpty ? "날씨" : model.weatherCity).font(.caption).foregroundStyle(.secondary)
                        if let temperature = model.weatherTemperature {
                            Text(model.weatherCondition).font(.caption).foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            HStack(alignment: .bottom, spacing: 3) {
                                Text(String(format: "%.0f°", temperature)).font(.system(size: 38, weight: .light))
                                Spacer(minLength: 0)
                                ForEach(Array(mainWeatherPreview(model).prefix(3))) { hour in
                                    VStack(spacing: 2) {
                                        Text(String(format: "%.0f°", hour.temperature)).font(.caption)
                                        Text(homeWeatherHour(hour.date, timeZoneID: model.weatherTimeZoneID)).font(.system(size: 8)).lineLimit(1)
                                    }.foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            Text(model.weatherText).lineLimit(3)
                        }
                        Spacer(minLength: 0)
                    }.frame(maxWidth: .infinity, minHeight: 94, maxHeight: 94, alignment: .topLeading).riumGlassTile(tint: .cyan, radius: 24)
                }.buttonStyle(.plain)
                Button(action: { model.select(.agenda) }) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("다음 일정").font(.caption).foregroundStyle(.secondary)
                                if let event = agenda.events.first {
                                    Text(agendaRelativeLabel(event, now: model.now)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                                .frame(width: 25, height: 25).overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1)).accessibilityHidden(true)
                        }
                        if let event = agenda.events.first {
                            Text(agendaTimeLabel(event)).font(.system(size: 27, weight: .light))
                            HStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 1).fill(Color.blue).frame(width: 3, height: 12)
                                Text(event.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        else { Text(agenda.calendarStatus).lineLimit(3) }
                        Spacer(minLength: 0)
                    }.frame(maxWidth: .infinity, minHeight: 94, maxHeight: 94, alignment: .topLeading).riumGlassTile(radius: 24)
                }.buttonStyle(.plain)
            }.padding(.horizontal, -8)
            .background {
                if let artwork = model.mediaAtmosphere {
                    GeometryReader { geometry in
                        Image(nsImage: artwork).resizable().scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .opacity(0.20)
                            .mask(LinearGradient(stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .white, location: 0.08),
                                .init(color: .white.opacity(0.55), location: 0.48),
                                .init(color: .clear, location: 1)
                            ], startPoint: .leading, endPoint: .trailing))
                            .mask(LinearGradient(stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .white, location: 0.18),
                                .init(color: .white, location: 0.82),
                                .init(color: .clear, location: 1)
                            ], startPoint: .top, endPoint: .bottom))
                            .clipped()
                    }.allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .font(.system(size: 12))
            Spacer()
        }
    }
}

struct DictationView: View {
    @ObservedObject var model: DictationController
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("받아쓰기").font(.headline); Spacer(); Button(model.enabled ? "끄기" : "준비") { model.enabled ? model.disable() : model.prepare() }.buttonStyle(.plain) }
            Toggle("앱을 열 때 자동 준비", isOn: Binding(get: { model.autoStart }, set: { model.setAutoStart($0) }))
            Picker("받아쓰기 단축키", selection: Binding(get: { model.shortcut }, set: { model.setShortcut($0) })) {
                ForEach(DictationShortcut.allCases, id: \.rawValue) { shortcut in Text(shortcut.label).tag(shortcut) }
            }
            Picker("받아쓰기 언어", selection: Binding(get: { model.languageID }, set: { model.setLanguage($0) })) {
                ForEach(DictationController.languageIDs, id: \.self) { id in Text(DictationController.languageName(id)).tag(id) }
            }
            Text(model.status).foregroundStyle(.secondary)
            Text("\(model.shortcut.label)을 누른 채 말한 뒤 놓으면 입력합니다. 기기 내 인식을 지원하는 언어를 사용합니다.").font(.caption).foregroundStyle(.secondary)
            Button("손쉬운 사용 설정 열기") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
            }.buttonStyle(.plain)
            if !model.lastText.isEmpty {
                Text(model.lastText).textSelection(.enabled).riumTile()
                Button("텍스트 복사") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(model.lastText, forType: .string) }.buttonStyle(.plain)
            }
            Spacer()
        }.font(.system(size: 12))
    }
}

struct AgentView: View {
    @ObservedObject var model: Model
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if model.agentItems.isEmpty {
                    Text(model.agentStatus).font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 80)
                }
                ForEach(model.agentItems) { item in
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 7) {
                            CollapsedAgentFace(waiting: item.state.hasPrefix("승인 대기"), claude: item.source == "claude")
                            Text(item.providerName).fontWeight(.semibold)
                            Text("· \(item.project)").foregroundStyle(.secondary).lineLimit(1)
                            Spacer(minLength: 4)
                            if let age = item.ageSeconds { Text(age < 60 ? "\(age)초 전" : "\(age / 60)분 전").foregroundStyle(.secondary) }
                        }
                        HStack(spacing: 6) {
                            ForEach(Array(item.recentActivities.enumerated()), id: \.offset) { _, activity in
                                Label(activity, systemImage: activity == "웹 확인" ? "globe" : (activity == "파일 수정" ? "pencil" : "terminal"))
                                    .font(.caption).lineLimit(1).padding(.horizontal, 7).padding(.vertical, 4)
                                    .background(.white.opacity(0.06), in: Capsule())
                            }
                            Spacer(minLength: 0)
                        }
                        HStack(spacing: 8) {
                            Circle().fill(item.state.hasPrefix("승인 대기") ? Color.orange : (item.state == "완료" ? Color.green : Color.cyan)).frame(width: 5, height: 5)
                            Text(item.state).foregroundStyle(.secondary)
                            Spacer()
                            if item.source == "codex", codexThreadURL(item.id) != nil {
                                Button("대화 열기") { model.openCodexThread(item) }
                                    .buttonStyle(.plain).help("Codex에서 이 대화 열기")
                            }
                            Image(systemName: "infinity").foregroundStyle(.secondary.opacity(0.5)).help("승인 제어 연결 필요").accessibilityLabel("승인 제어 연결 필요")
                            Image(systemName: "stop.fill").foregroundStyle(.secondary.opacity(0.5)).help("작업 중단 제어 연결 필요").accessibilityLabel("작업 중단 제어 연결 필요")
                        }
                    }.font(.system(size: 12)).riumGlassTile()
                }
            }
        }
    }
}

struct MediaTransportGlyph: View {
    let playing: Bool
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 16
            if playing {
                for x in [3.5, 9.5] {
                    let rect = CGRect(x: x * scale, y: 2.5 * scale, width: 3 * scale, height: 11 * scale)
                    context.fill(Path(roundedRect: rect, cornerRadius: 0.7 * scale), with: .color(.black))
                }
            } else {
                var triangle = Path(); triangle.move(to: CGPoint(x: 4.5 * scale, y: 2 * scale))
                triangle.addLine(to: CGPoint(x: 13 * scale, y: 8 * scale)); triangle.addLine(to: CGPoint(x: 4.5 * scale, y: 14 * scale)); triangle.closeSubpath()
                context.fill(triangle, with: .color(.black))
            }
        }.frame(width: 16, height: 16).accessibilityHidden(true)
    }
}

struct MusicView: View {
    @ObservedObject var model: Model
    var body: some View {
        GeometryReader { geometry in
            let artSize = min(168, max(64, geometry.size.width * 0.21))
            HStack(spacing: 8) {
                HStack(spacing: 14) {
                    Group {
                        if let artwork = model.mediaArtwork { Image(nsImage: artwork).resizable().scaledToFill() }
                        else {
                            ZStack {
                                Color.white.opacity(0.07)
                                Image(systemName: "music.note").resizable().scaledToFit().padding(artSize * 0.27).foregroundStyle(.white.opacity(0.65))
                            }
                        }
                    }.frame(width: artSize, height: artSize).clipShape(RoundedRectangle(cornerRadius: min(24, artSize * 0.15)))
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(!model.mediaAvailable ? "재생 중인 미디어 없음" : (model.mediaPlaying ? "지금 재생 중" : "일시 정지"))
                                Text("음악")
                            }.font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            Spacer(minLength: 0)
                            if !model.showLyricsPanel {
                                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { model.showLyricsPanel = true } }) {
                                    Image(systemName: "text.quote").frame(width: 24, height: 24).background(.white.opacity(0.08), in: Circle())
                                }.buttonStyle(.plain).help("가사 패널 열기").accessibilityLabel("가사 패널 열기")
                            }
                        }
                        Spacer(minLength: 4)
                        Text(model.mediaTitle).font(.system(size: 18, weight: .medium)).lineLimit(2)
                        if !model.mediaArtist.isEmpty { Text(model.mediaArtist).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        if model.mediaDuration > 0 {
                            GeometryReader { bar in
                                let elapsed = model.mediaEditingPosition ? model.mediaEditedPosition : model.mediaElapsed
                                let fraction = min(1, max(0, elapsed / model.mediaDuration))
                                ZStack(alignment: .leading) {
                                    Capsule().fill(.white.opacity(0.20)).frame(height: 3)
                                    Capsule().fill(Color(red: 0.96, green: 0.48, blue: 0.65)).frame(width: bar.size.width * fraction, height: 3)
                                    Slider(value: Binding(get: { model.mediaEditingPosition ? model.mediaEditedPosition : min(max(model.mediaElapsed, 0), model.mediaDuration) }, set: { model.mediaEditedPosition = $0 }), in: 0...model.mediaDuration, onEditingChanged: { editing in
                                        if editing { model.mediaEditedPosition = min(max(model.mediaElapsed, 0), model.mediaDuration); model.mediaEditingPosition = true }
                                        else if model.mediaEditingPosition { model.mediaEditingPosition = false; model.seekMedia(model.mediaEditedPosition) }
                                    }).controlSize(.mini).opacity(0.02).disabled(model.mediaSeekPending || model.mediaControlPending).accessibilityLabel("재생 위치")
                                }
                            }.frame(height: 14)
                            HStack { Text(mediaTime(model.mediaEditingPosition ? model.mediaEditedPosition : model.mediaElapsed)); Spacer(); Text(mediaTime(model.mediaDuration)) }.font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                        }
                        if !model.mediaError.isEmpty { Text(model.mediaError).font(.caption2).foregroundStyle(.secondary).lineLimit(1).help(model.mediaError) }
                        HStack {
                            Button(action: { model.controlMedia("previous") }) { Image(systemName: "backward.fill").frame(width: 32, height: 32).overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1)) }.help("이전 곡")
                            Spacer(minLength: 4)
                            Button(action: { model.controlMedia("toggle") }) { MediaTransportGlyph(playing: model.mediaPlaying).frame(width: 40, height: 40).background(.white, in: Circle()) }
                                .help(model.mediaPlaying ? "일시 정지" : "재생").accessibilityLabel(model.mediaPlaying ? "일시 정지" : "재생")
                            Spacer(minLength: 4)
                            Button(action: { model.controlMedia("next") }) { Image(systemName: "forward.fill").frame(width: 32, height: 32).overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1)) }.help("다음 곡")
                        }.buttonStyle(.plain).disabled(!model.mediaAvailable || model.mediaControlPending).padding(.top, 4)
                    }
                }
                .frame(width: max(1, geometry.size.width * (model.showLyricsPanel ? 0.55 : 1) - 26), height: max(1, geometry.size.height - 22), alignment: .leading)
                .riumGlassTile(artwork: model.mediaAtmosphere, artworkOpacity: 0.09, radius: 24)
                if model.showLyricsPanel {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("가사").font(.caption).foregroundStyle(.secondary); Spacer()
                        AudioOutputMenu(model: model.audioOutputs)
                        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { model.showLyricsPanel = false } }) {
                            Image(systemName: "xmark").frame(width: 24, height: 24).background(.white.opacity(0.08), in: Circle())
                        }.buttonStyle(.plain).help("가사 패널 닫기").accessibilityLabel("가사 패널 닫기")
                    }
                    if !model.lyricsEnabled {
                        Spacer()
                        VStack(alignment: .leading, spacing: 8) {
                            Text("가사를 켜면 곡 제목과 아티스트, 재생 시간이 LRCLIB에 전송됩니다.").font(.caption).foregroundStyle(.secondary)
                            Button("가사 켜기") { model.setLyricsEnabled(true) }.buttonStyle(.plain)
                        }
                        Spacer()
                    } else if model.lyricLines.isEmpty {
                        Spacer(); Text(model.lyricsStatus).font(.caption).foregroundStyle(.secondary); Spacer()
                    } else {
                        let active = model.lyricLines.last(where: { ($0.time ?? .infinity) <= model.mediaElapsed })?.id
                        ScrollViewReader { proxy in
                            ScrollView { VStack(alignment: .leading, spacing: 10) {
                                ForEach(model.lyricLines) { line in
                                    Text(line.text.isEmpty ? " " : line.text).font(.system(size: 12, weight: active == line.id ? .semibold : .regular))
                                        .foregroundStyle(active == line.id ? Color.white : Color.white.opacity(0.52)).id(line.id)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading) }
                            .onChange(of: active) { _, value in if let value = value { withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(value, anchor: .center) } } }
                        }
                    }
                    if model.lyricsEnabled {
                        HStack {
                            Text("가사 제공: LRCLIB").font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Button("가사 끄기") { model.setLyricsEnabled(false) }.buttonStyle(.plain).font(.caption2)
                        }
                    }
                }.frame(width: max(1, geometry.size.width * 0.45 - 26), height: max(1, geometry.size.height - 22), alignment: .topLeading).riumGlassTile(radius: 24)
                }
            }
            .background {
                if let artwork = model.mediaAtmosphere {
                    GeometryReader { backdrop in
                        Image(nsImage: artwork).resizable().scaledToFill()
                            .frame(width: backdrop.size.width, height: backdrop.size.height)
                            .opacity(0.20)
                            .mask(LinearGradient(stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .white, location: 0.14),
                                .init(color: .white.opacity(0.80), location: 0.80),
                                .init(color: .clear, location: 1)
                            ], startPoint: .leading, endPoint: .trailing))
                            .mask(LinearGradient(stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .white, location: 0.22),
                                .init(color: .white, location: 0.80),
                                .init(color: .clear, location: 1)
                            ], startPoint: .top, endPoint: .bottom))
                            .clipped()
                    }.allowsHitTesting(false).accessibilityHidden(true)
                }
            }
        }
    }
    private func mediaTime(_ seconds: Double) -> String {
        let value = Int(min(max(seconds, 0), 86_400))
        return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) : String(format: "%d:%02d", value / 60, value % 60)
    }
}

struct ShelfView: View {
    @ObservedObject var model: Model
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("보관함").font(.headline); Spacer(); Button("파일 추가") { model.chooseShelfFiles() }.buttonStyle(.plain) }
            Text(model.shelfStatus).font(.caption).foregroundStyle(.secondary)
            HStack { Text(model.airDropStatus).font(.caption).foregroundStyle(.secondary); Spacer(); Button(model.airDropEnabled ? "수신 감시 끄기" : "수신 감시 켜기") { model.toggleAirDropMonitor() }.buttonStyle(.plain) }
            HStack { Text(model.screenshotStatus).font(.caption).foregroundStyle(.secondary); Spacer(); Button(model.screenshotEnabled ? "스크린샷 감시 끄기" : "스크린샷 감시 켜기") { model.toggleScreenshotMonitor() }.buttonStyle(.plain) }
            ScrollView { VStack(alignment: .leading, spacing: 6) {
                ForEach(model.shelfItems, id: \.self) { path in
                    HStack {
                        Image(systemName: "doc")
                        Text(URL(fileURLWithPath: path).lastPathComponent).lineLimit(1)
                        Spacer()
                        Button("AirDrop") { model.sendAirDrop(path) }.buttonStyle(.plain)
                        Button("열기") { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }.buttonStyle(.plain)
                        Button("제거") { model.removeShelf(path) }.buttonStyle(.plain)
                    }.riumTile().onDrag { NSItemProvider(contentsOf: URL(fileURLWithPath: path)) ?? NSItemProvider() }
                }
            }}
            Text("제거해도 원본 파일은 유지됩니다.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

extension View {
    func riumGlassTile(artwork: NSImage? = nil, tint: Color = .clear, artworkOpacity: Double = 0.38, radius: CGFloat = 15) -> some View {
        padding(11)
            .background {
                ZStack {
                    Color.white.opacity(0.075)
                    if let artwork = artwork {
                        GeometryReader { geometry in
                            Image(nsImage: artwork).resizable().scaledToFill()
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .opacity(artworkOpacity)
                        }.clipped()
                    } else {
                        LinearGradient(colors: [tint.opacity(0.20), .white.opacity(0.07), tint.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                    LinearGradient(colors: [.white.opacity(0.15), .clear, .black.opacity(0.12)], startPoint: .top, endPoint: .bottom)
                }.clipShape(RoundedRectangle(cornerRadius: radius))
            }
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(LinearGradient(colors: [.white.opacity(0.36), .white.opacity(0.10), .white.opacity(0.23)], startPoint: .top, endPoint: .bottom), lineWidth: 0.8))
    }
    func riumTile(_ tint: Color = .clear) -> some View {
        padding(11).background(RoundedRectangle(cornerRadius: 15).fill(LinearGradient(colors: [tint.opacity(0.20), Color.white.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.white.opacity(0.12), lineWidth: 0.7))
    }
}

struct Sparkline: Shape {
    let samples: [Double?]
    func path(in rect: CGRect) -> Path {
        var path = Path(); guard samples.count > 1 else { return path }
        var continuing = false
        for (index, value) in samples.enumerated() {
            guard let value = value, value.isFinite else { continuing = false; continue }
            let x = rect.width * CGFloat(index) / CGFloat(samples.count - 1)
            let y = rect.height * (1 - CGFloat(min(max(value, 0), 100)) / 100)
            if continuing { path.addLine(to: CGPoint(x: x, y: y)) } else { path.move(to: CGPoint(x: x, y: y)) }
            continuing = true
        }
        return path
    }
}

struct WeatherView: View {
    @ObservedObject var main: Model
    init(model: Model) { self.main = model }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "cloud.sun.fill").foregroundStyle(.yellow)
                VStack(alignment: .leading) { Text(main.weatherText).font(.headline); Text(main.weatherDetail).font(.caption).foregroundStyle(.secondary) }
                Spacer(); Button("현재 위치") { main.useCurrentWeatherLocation() }.buttonStyle(.plain).help("현재 위치 좌표를 날씨 제공처에 전송합니다")
                Button("도시 선택") { main.chooseWeatherCity() }.buttonStyle(.plain)
            }
            let forecast = Array(main.weatherForecast.filter { $0.date.addingTimeInterval(3600) > main.now }.prefix(8))
            if !forecast.isEmpty {
                Text("시간별 예보 · 1시간 예상 강수량 · \(main.weatherTimeZoneID == nil ? "기기 시간" : "선택 도시 시간")")
                    .font(.caption2).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(spacing: 14) {
                        ForEach(forecast) { hour in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(weatherHourLabel(hour.date, timeZoneID: main.weatherTimeZoneID)).font(.caption2).foregroundStyle(.secondary)
                                HStack(spacing: 4) { Image(systemName: weatherIcon(hour.symbol)); Text(String(format: "%.0f°", hour.temperature)) }.font(.caption)
                                Text(hour.precipitation.map { String(format: "%.1f mm", $0) } ?? "강수 정보 없음").font(.caption2).foregroundStyle(.secondary)
                            }.accessibilityElement(children: .combine)
                        }
                    }
                }
            } else if !main.weatherCity.isEmpty {
                Text(main.weatherForecast.isEmpty ? "시간별 예보는 다음 날씨 갱신 후 표시됩니다." : "현재 표시할 시간별 예보가 없습니다.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }.riumTile()
        Spacer(minLength: 0)
        }
    }
}

struct AgendaView: View {
    @ObservedObject var model: AgendaModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text("캘린더").font(.headline); Spacer(); Button("추가") { model.addEvent() }.buttonStyle(.plain); Button("불러오기") { model.loadCalendar() }.buttonStyle(.plain) }
                Text(model.calendarStatus).font(.caption).foregroundStyle(.secondary)
                ScrollView { VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.events) { item in VStack(alignment: .leading) { Text(item.title); Text(item.subtitle).font(.caption).foregroundStyle(.secondary) } }
                }.frame(maxWidth: .infinity, alignment: .leading) }
            }.frame(maxWidth: .infinity, alignment: .topLeading)
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text("미리 알림").font(.headline); Spacer(); Button("추가") { model.addReminder() }.buttonStyle(.plain); Button("불러오기") { model.loadReminders() }.buttonStyle(.plain) }
                Text(model.remindersStatus).font(.caption).foregroundStyle(.secondary)
                ScrollView { VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.reminders) { item in HStack { VStack(alignment: .leading) { Text(item.title); Text(item.subtitle).font(.caption).foregroundStyle(.secondary) }; Spacer(); Button("완료") { model.completeReminder(item.id) }.buttonStyle(.plain) } }
                }.frame(maxWidth: .infinity, alignment: .leading) }
            }.frame(maxWidth: .infinity, alignment: .topLeading)
        }.font(.system(size: 12))
        }
    }
}

extension Notification.Name {
    static let notchSizeChanged = Notification.Name("notchSizeChanged")
    static let notchDisplayChanged = Notification.Name("notchDisplayChanged")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = Model()
    var panel: NSPanel!
    var ambientPanel: NSPanel!
    var status: NSStatusItem!
    var settingsWindow: NSWindow?
    private var screenObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var pointerPollTimer: Timer?
    private var mouseInsideNotch = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(CommandLine.arguments.contains("--ui-test") ? .regular : .accessory)
        model.refreshDisplayChoices()
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 405, height: notchHeight(expanded: false, section: .home)), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.acceptsMouseMovedEvents = true
        // REA's native observer accepts layer-zero windows only. This opt-in
        // diagnostic keeps the same view and geometry while temporarily
        // lowering the window for observation; ordinary launches stay on top.
        panel.level = CommandLine.arguments.contains("--rea-inspect") ? .normal : .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let hosting = NSHostingView(rootView: NotchContainer(model: model)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top))
        hosting.sizingOptions = []
        panel.contentView = hosting
        position(height: notchHeight(expanded: false, section: .home)); panel.orderFrontRegardless()
        installMouseInterception()
        ambientPanel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        ambientPanel.isOpaque = false; ambientPanel.backgroundColor = .clear; ambientPanel.hasShadow = false
        ambientPanel.ignoresMouseEvents = true
        ambientPanel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        ambientPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ambientPanel.contentView = NSHostingView(rootView: NotchAmbientLight(model: model))
        positionAmbient(); ambientPanel.orderFrontRegardless()
        observeDisplayChanges()
        if CommandLine.arguments.contains("--verify-reflow") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self = self else { return }
                let notchFrame = self.panel.frame, lightFrame = self.ambientPanel.frame
                NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    guard let self = self else { return }
                    print("RIUM_REFLOW stable=\(self.panel.frame == notchFrame && self.ambientPanel.frame == lightFrame)")
                    fflush(stdout)
                }
            }
        }
        if CommandLine.arguments.contains("--report-windows") {
            print("RIUM_WINDOWS notch=\(panel.windowNumber) lighting=\(ambientPanel.windowNumber)")
            if let frame = NSScreen.main?.frame { print("RIUM_GEOMETRY screen=\(frame) panel=\(panel.frame)") }
            print("RIUM_AGENDA calendar_full=\(EKEventStore.authorizationStatus(for: .event) == .fullAccess) reminders_full=\(EKEventStore.authorizationStatus(for: .reminder) == .fullAccess)")
            let access = model.dictation.accessStatus
            print("RIUM_DICTATION accessibility=\(access.accessibility) speech=\(access.speech) microphone=\(access.microphone) enabled=\(model.dictation.enabled)")
            fflush(stdout)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                if let frame = NSScreen.main?.frame, let panel = self?.panel { print("RIUM_GEOMETRY_READY screen=\(frame) panel=\(panel.frame)"); fflush(stdout) }
            }
        }
        NotificationCenter.default.addObserver(forName: .notchSizeChanged, object: nil, queue: .main) { [weak self] _ in self?.updateMouseInterception(notifyHover: false) }
        NotificationCenter.default.addObserver(forName: .notchDisplayChanged, object: nil, queue: .main) { [weak self] _ in self?.reflowDisplays() }
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let icon = NSImage(contentsOf: url) {
            icon.size = NSSize(width: 18, height: 18); icon.isTemplate = false; status.button?.image = icon
        } else { status.button?.title = "R" }
        let menu = NSMenu(); let showItem = NSMenuItem(title: "노치 표시", action: #selector(show), keyEquivalent: ""); showItem.target = self; menu.addItem(showItem)
        let settingsItem = NSMenuItem(title: "설정…", action: #selector(showSettings), keyEquivalent: ""); settingsItem.target = self; menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator()); menu.addItem(NSMenuItem(title: "Rium Notch 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")); status.menu = menu
    }
    private func targetScreen() -> NSScreen? {
        let screens = NSScreen.screens
        let ids = screens.compactMap(displayIdentifier)
        let primary = CGMainDisplayID()
        if let selected = resolvedDisplayID(preferred: model.preferredDisplayID, available: ids, primary: primary),
           let screen = screens.first(where: { displayIdentifier($0) == selected }) {
            return screen
        }
        return screens.first
    }
    func position(height: CGFloat, animate: Bool = true) {
        guard let screen = targetScreen() else { return }
        let frame = screen.frame
        model.selectDisplay(displayIdentifier(screen))
        if model.displayWidth != frame.width { model.displayWidth = frame.width }
        let exclusion = cameraExclusionWidth(screen: frame, topInset: screen.safeAreaInsets.top, left: screen.auxiliaryTopLeftArea, right: screen.auxiliaryTopRightArea)
        if model.cameraExclusion != exclusion { model.cameraExclusion = exclusion }
        let cameraHeight = exclusion > 0 ? screen.safeAreaInsets.top : 0
        if model.cameraHeight != cameraHeight { model.cameraHeight = cameraHeight }
        // Like the original panel, keep a fixed surface above the desktop so
        // AppKit window resizing does not compete with SwiftUI's spring.
        let panelHeight = min(frame.height, 470)
        panel.setFrame(NSRect(x: frame.minX, y: frame.maxY - panelHeight, width: frame.width, height: panelHeight), display: true, animate: false)
    }
    func pointIsInsideNotch(_ point: NSPoint) -> Bool {
        guard let screen = targetScreen()?.frame else { return false }
        return notchContainsScreenPoint(point, screen: screen, expanded: model.expanded, section: model.section, size: model.currentNotchOutlineSize)
    }
    private func updateMouseInterception(notifyHover: Bool = true) {
        guard panel != nil else { return }
        let inside = pointIsInsideNotch(NSEvent.mouseLocation)
        let decision = notchPointerDecision(inside: inside, wasInside: mouseInsideNotch,
            ignoring: panel.ignoresMouseEvents, buttonDown: NSEvent.pressedMouseButtons != 0, notifyHover: notifyHover)
        if let hover = decision.hoverChange { model.handleHover(hover) }
        mouseInsideNotch = decision.inside
        if panel.ignoresMouseEvents != decision.ignoresMouse {
            panel.ignoresMouseEvents = decision.ignoresMouse
        }
    }
    private func handlePointerEvent(_ event: NSEvent) {
        updateMouseInterception()
        if event.type == .leftMouseUp || event.type == .rightMouseUp || event.type == .otherMouseUp {
            // A local monitor can run before AppKit updates pressedMouseButtons.
            // Recheck after delivery so releasing outside cannot leave the
            // large transparent panel intercepting subsequent clicks.
            DispatchQueue.main.async { [weak self] in self?.updateMouseInterception() }
        }
    }
    private func installMouseInterception() {
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .leftMouseUp, .rightMouseUp, .otherMouseUp]
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] event in self?.handlePointerEvent(event) }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in self?.handlePointerEvent(event); return event }
        // The original controller also polls every 0.08 s. This recovers when
        // an event is missed, including a mouse-up outside the panel.
        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in self?.updateMouseInterception() }
        RunLoop.main.add(timer, forMode: .common)
        pointerPollTimer = timer
        updateMouseInterception(notifyHover: false)
    }
    func positionAmbient() {
        guard let frame = targetScreen()?.frame else { return }
        ambientPanel.setFrame(NSRect(x: frame.minX, y: frame.maxY - 90, width: frame.width, height: 90), display: true)
    }
    private func observeDisplayChanges() {
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.reflowDisplays() }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didWakeNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.reflowDisplays() })
        }
    }
    private func reflowDisplays() {
        guard panel != nil, ambientPanel != nil else { return }
        model.refreshDisplayChoices()
        position(height: notchHeight(expanded: model.expanded, section: model.section), animate: false)
        updateMouseInterception(notifyHover: false)
        positionAmbient(); panel.orderFrontRegardless(); ambientPanel.orderFrontRegardless()
        if CommandLine.arguments.contains("--report-windows") { print("RIUM_REFLOW_EVENT notch=\(panel.frame) lighting=\(ambientPanel.frame)"); fflush(stdout) }
    }
    @objc func show() { panel.orderFrontRegardless() }
    @objc func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 780), styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "Rium Notch 설정"; window.center(); window.isReleasedWhenClosed = false
            window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
            window.contentView = NSHostingView(rootView: SettingsView(model: model)); settingsWindow = window
            if CommandLine.arguments.contains("--report-windows") { print("RIUM_SETTINGS window=\(window.windowNumber)"); fflush(stdout) }
        }
        settingsWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func applicationDidBecomeActive(_ notification: Notification) { model.agenda.refreshIfAuthorizationChanged(); model.dictation.restoreIfAuthorized(); model.refreshTimerNotificationPermission() }
    func applicationWillTerminate(_ notification: Notification) {
        model.teleprompter.flush()
        model.flushClipboard()
        model.dictation.disable(persist: false)
        if let screenObserver = screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        pointerPollTimer?.invalidate()
        if let monitor = globalMouseMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = localMouseMonitor { NSEvent.removeMonitor(monitor) }
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
}

if CommandLine.arguments.contains("--self-test-timer-notifications") {
    final class FakeTimerBackend: TimerNotificationBackend {
        var queries: [([String]) -> Void] = []
        var removed: [[String]] = []
        var additions: [(String, TimeInterval, (Error?) -> Void)] = []
        func pending(_ completion: @escaping ([String]) -> Void) { queries.append(completion) }
        func remove(_ identifiers: [String]) { removed.append(identifiers) }
        func add(identifier: String, after seconds: TimeInterval, title: String, completion: @escaping (Error?) -> Void) { additions.append((identifier, seconds, completion)) }
    }
    func settle() { RunLoop.current.run(until: Date().addingTimeInterval(0.03)) }
    let fake = FakeTimerBackend(), coordinator = TimerNotificationCoordinator(backend: fake)
    var errorMessage = ""; coordinator.onError = { errorMessage = $0 }
    coordinator.replace(after: 30); coordinator.replace(after: nil)
    fake.queries.removeFirst()([TimerNotificationCoordinator.prefix + "stale"]); settle()
    precondition(fake.removed.isEmpty && fake.additions.isEmpty)
    fake.queries.removeFirst()([TimerNotificationCoordinator.prefix + "old", "unrelated"]); settle()
    precondition(fake.removed == [[TimerNotificationCoordinator.prefix + "old"]])
    coordinator.replace(after: 20); fake.queries.removeFirst()([]); settle()
    precondition(fake.additions.count == 1 && fake.additions[0].1 == 20)
    let staleID = fake.additions[0].0
    coordinator.replace(after: nil); fake.queries.removeFirst()([]); settle()
    fake.additions[0].2(nil); settle()
    precondition(fake.removed.last == [staleID])
    coordinator.replace(after: 40); fake.queries.removeFirst()([]); settle()
    precondition(fake.additions.count == 2 && fake.additions[1].1 == 40)
    fake.additions[1].2(NSError(domain: "fixture", code: 1)); settle()
    precondition(errorMessage == "타이머 알림을 예약하지 못했습니다")
    print("timer notification coordination self-test passed")
} else if CommandLine.arguments.contains("--self-test-weather-forecast") {
    let rows: [[String: Any]] = [
        ["time": "2026-11-15T00:00:00Z", "temperature": 12.0, "symbol": "rain", "precipitation": 0.0],
        ["time": "2026-11-15T01:00:00Z", "temperature": 11.0, "symbol": "sleet"],
        ["time": "2026-11-15T01:00:00Z", "temperature": 99.0],
        ["time": "invalid", "temperature": 1.0]
    ]
    let hours = weatherHours(rows)
    precondition(hours.count == 2 && hours[0].precipitation == 0 && hours[1].precipitation == nil)
    precondition(weatherHourLabel(hours[0].date, timeZoneID: "Asia/Seoul") == "11/15 09시")
    precondition(weatherHourLabel(hours[0].date, timeZoneID: "Europe/London") == "11/15 00시")
    precondition(weatherDescription("sleet") == "비와 눈" && weatherIcon("clearsky_night") == "moon.stars.fill")
    print("weather forecast self-test passed")
} else if CommandLine.arguments.contains("--self-test-audio-output") {
    let output = AudioOutputModel(); output.refresh()
    let before = output.current
    guard output.devices.allSatisfy({ !$0.name.isEmpty }), !output.devices.contains(where: { $0.id == UInt32.max }) else { fatalError("invalid audio output list") }
    output.select(UInt32.max)
    guard output.current == before, !output.error.isEmpty else { fatalError("invalid output selection was not rejected") }
    output.refresh()
    guard output.current == before else { fatalError("read-only audio output check changed system output") }
    print("audio output read-only self-test passed")
} else if CommandLine.arguments.contains("--self-test-agent-link") {
    let id = "01234567-89ab-cdef-0123-456789abcdef"
    guard let link = codexThreadURL(id), link.absoluteString == "codex://threads/" + id,
          codexThreadURL("../other") == nil, codexThreadURL("") == nil,
          NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") != nil else {
        fatalError("Codex conversation link validation failed")
    }
    print("Codex conversation link self-test passed")
} else if CommandLine.arguments.contains("--self-test-notch-animation") {
    _ = NSApplication.shared
    let model = Model(startServices: false)
    model.displayWidth = 1000; model.cameraExclusion = 185; model.cameraHeight = 32
    let view = NSHostingView(rootView: NotchContainer(model: model))
    view.frame = NSRect(x: 0, y: 0, width: 1000, height: 470)
    let window = NSPanel(contentRect: NSRect(x: -2000, y: -2000, width: 1000, height: 470),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    window.isOpaque = false; window.backgroundColor = .clear; window.contentView = view
    window.orderFrontRegardless()
    RunLoop.current.run(until: Date().addingTimeInterval(0.15))
    notchAnimationProbe.removeAll()
    let start = model.currentNotchOutlineSize
    model.expanded = true
    let end = model.currentNotchOutlineSize
    RunLoop.current.run(until: Date().addingTimeInterval(0.6))
    let opening = notchAnimationProbe.filter { $0.width > start.width + 5 && $0.width < end.width - 5 && $0.height > start.height + 2 && $0.height < end.height - 2 }
    notchAnimationProbe.removeAll()
    model.expanded = false
    RunLoop.current.run(until: Date().addingTimeInterval(0.6))
    let closing = notchAnimationProbe.filter { $0.width > start.width + 5 && $0.width < end.width - 5 && $0.height > start.height + 2 && $0.height < end.height - 2 }
    window.orderOut(nil)
    guard !opening.isEmpty, !closing.isEmpty else { fatalError("notch shape did not interpolate: open=\(opening.count) close=\(closing.count) samples=\(notchAnimationProbe.prefix(12))") }
    print("notch animation intermediate shapes: open=\(opening.count) close=\(closing.count)")
} else if CommandLine.arguments.contains("--self-test-notch-outline") {
    let completed = AgentActivity(id: "one", project: "fixture", state: "완료", activity: "")
    let active = AgentActivity(id: "two", project: "fixture", state: "활동 감지", activity: "")
    let waiting = AgentActivity(id: "three", project: "fixture", state: "승인 대기", activity: "")
    precondition(collapsedAgent([]) == nil && collapsedAgent([completed, active])?.id == "two")
    precondition(collapsedAgent([active, waiting])?.id == "three")
    let path = NotchSilhouette().path(in: CGRect(x: 100, y: 50, width: 200, height: 90)).cgPath
    var curves: [[CGPoint]] = []
    path.applyWithBlock { element in
        if element.pointee.type == .addCurveToPoint {
            curves.append((0..<3).map { element.pointee.points[$0] })
        }
    }
    func close(_ a: CGPoint, _ b: CGPoint) -> Bool { abs(a.x - b.x) < 0.0001 && abs(a.y - b.y) < 0.0001 }
    precondition(curves.count == 4)
    precondition(close(curves[0][0], CGPoint(x: 115.6, y: 50)) && close(curves[0][1], CGPoint(x: 120, y: 54.4)) && close(curves[0][2], CGPoint(x: 120, y: 70)))
    precondition(close(curves[1][0], CGPoint(x: 120, y: 135.6)) && close(curves[1][1], CGPoint(x: 124.4, y: 140)) && close(curves[1][2], CGPoint(x: 140, y: 140)))
    var lightCurves: [[CGPoint]] = []
    lightContour(width: 200, height: 90, armWidth: 100).cgPath.applyWithBlock { element in
        if element.pointee.type == .addCurveToPoint { lightCurves.append((0..<3).map { element.pointee.points[$0] }) }
    }
    precondition(lightCurves.count == curves.count)
    for i in curves.indices { for j in 0..<3 {
        precondition(close(lightCurves[i][j], CGPoint(x: curves[i][j].x, y: curves[i][j].y - 50)))
    } }
    precondition(path.contains(CGPoint(x: 200, y: 90)) && !path.contains(CGPoint(x: 105, y: 100)))
    // Expanded home cards extend beyond the old inset shoulders. Both card
    // edges and the right-side menu must remain inside the animated mask.
    let homeContent = CGSize(width: 870, height: 210)
    let homeOutline = notchOutlineSize(content: homeContent, expanded: true, screenWidth: 1512)
    precondition(homeOutline == CGSize(width: 910, height: 210))
    let homeMask = AnimatedNotchBackdrop(width: homeOutline.width, height: homeOutline.height)
        .path(in: CGRect(origin: .zero, size: homeContent))
    precondition(homeMask.contains(CGPoint(x: 18, y: 100)) && homeMask.contains(CGPoint(x: 852, y: 100)))
    precondition(homeMask.contains(CGPoint(x: 858, y: 55)))
    let smallContent = CGSize(width: notchWidth(expanded: true, displayWidth: 640), height: 210)
    precondition(notchOutlineSize(content: smallContent, expanded: true, screenWidth: 640).width == 640)
    print("notch outline self-test passed")
} else if CommandLine.arguments.contains("--self-test-pointer-interception") {
    let screen = NSRect(x: 0, y: 0, width: 1512, height: 982)
    let leftArea = NSRect(x: 0, y: 950, width: 663.5, height: 32)
    let rightArea = NSRect(x: 848.5, y: 950, width: 663.5, height: 32)
    precondition(cameraExclusionWidth(screen: screen, topInset: 32, left: leftArea, right: rightArea) == 185)
    precondition(cameraExclusionWidth(screen: screen, topInset: 0, left: leftArea, right: rightArea) == 0)
    precondition(cameraExclusionWidth(screen: screen, topInset: 32, left: nil, right: rightArea) == 0)
    let musicSides = collapsedHeaderMetrics(width: 296, cameraWidth: 185)
    let bothSides = collapsedHeaderMetrics(width: 331, cameraWidth: 185)
    let constrainedSides = collapsedHeaderMetrics(width: 200, cameraWidth: 185)
    precondition(musicSides.gap == 193 && musicSides.side == 25.5)
    precondition(bothSides.gap == 193 && bothSides.side == 43)
    precondition(constrainedSides.gap == 148 && constrainedSides.side == 0)
    let offsetRight = NSRect(x: 868.5, y: 950, width: 643.5, height: 32)
    precondition(cameraExclusionWidth(screen: screen, topInset: 32, left: leftArea, right: offsetRight) == 225)
    precondition(notchContainsScreenPoint(NSPoint(x: 756, y: 962), screen: screen, expanded: false, section: .home))
    precondition(!notchContainsScreenPoint(NSPoint(x: 100, y: 832), screen: screen, expanded: false, section: .home))
    precondition(!notchContainsScreenPoint(NSPoint(x: 756, y: 900), screen: screen, expanded: false, section: .home))
    precondition(notchContainsScreenPoint(NSPoint(x: 756, y: 900), screen: screen, expanded: true, section: .home))
    let enter = notchPointerDecision(inside: true, wasInside: false, ignoring: true, buttonDown: false, notifyHover: true)
    precondition(!enter.ignoresMouse && enter.inside && enter.hoverChange == true)
    let dragOut = notchPointerDecision(inside: false, wasInside: true, ignoring: false, buttonDown: true, notifyHover: true)
    precondition(!dragOut.ignoresMouse && dragOut.inside && dragOut.hoverChange == nil)
    let releaseOut = notchPointerDecision(inside: false, wasInside: dragOut.inside, ignoring: dragOut.ignoresMouse, buttonDown: false, notifyHover: true)
    precondition(releaseOut.ignoresMouse && !releaseOut.inside && releaseOut.hoverChange == false)
    let outsideDragIn = notchPointerDecision(inside: true, wasInside: false, ignoring: true, buttonDown: true, notifyHover: true)
    precondition(!outsideDragIn.ignoresMouse && outsideDragIn.hoverChange == true)
    print("pointer interception self-test passed")
} else if CommandLine.arguments.contains("--self-test-dictation-timeout") {
    guard DictationController.testFinalizationTimeout() else { fatalError("dictation finalization timeout failed") }
    print("dictation finalization timeout self-test passed")
} else if CommandLine.arguments.contains("--self-test-brightness-watch") {
    _ = NSApplication.shared
    guard let screen = NSScreen.main, let id = displayIdentifier(screen) else { fatalError("main display unavailable") }
    let model = Model(startServices: false); model.selectDisplay(id)
    guard model.brightness != "밝기 조회 불가" else { fatalError("brightness unavailable") }
    print("RIUM_BRIGHTNESS_READY"); fflush(stdout)
    let deadline = Date().addingTimeInterval(8)
    while model.overlaySymbol != "sun.max.fill" && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.1)); model.sampleBrightness() }
    guard model.overlaySymbol == "sun.max.fill", model.volumeOverlay.hasPrefix("밝기 ") else { fatalError("brightness change was not surfaced") }
    print("brightness change observation passed"); fflush(stdout)
} else if CommandLine.arguments.contains("--self-test-brightness") {
    let model = Model(startServices: false)
    model.recordBrightness(display: 1, percent: 40)
    guard model.brightness == "밝기 40%", model.volumeOverlay.isEmpty else { fatalError("initial brightness incorrectly emitted an event") }
    model.recordBrightness(display: 1, percent: 42)
    guard model.volumeOverlay == "밝기 42%", model.overlaySymbol == "sun.max.fill", model.lightCue?.kind == .systemControl else { fatalError("brightness change not displayed") }
    model.showLight(.airDrop); model.recordBrightness(display: 1, percent: 43)
    guard model.lightCue?.kind == .airDrop else { fatalError("system light displaced AirDrop cue") }
    model.volumeOverlay = ""; model.recordBrightness(display: 2, percent: 80)
    guard model.volumeOverlay.isEmpty else { fatalError("display change emitted a brightness event") }
    model.recordBrightness(display: 2, percent: nil); model.recordBrightness(display: 2, percent: 75)
    guard model.volumeOverlay.isEmpty else { fatalError("brightness recovery emitted a false event") }
    _ = NSApplication.shared
    if let screen = NSScreen.main, let id = displayIdentifier(screen) {
        var value = -1.0; let result = displayBrightness(id, &value)
        guard result == 0 || (result == 1 && value.isFinite && (0...100).contains(value)) else { fatalError("invalid brightness result") }
        print(result == 1 ? "brightness read available" : "brightness read unavailable on this display")
    }
    print("brightness self-test passed")
} else if CommandLine.arguments.contains("--self-test-monitoring") {
    guard memoryUsagePercent(used: 8, total: 16, available: true) == 50,
          memoryUsagePercent(used: 1, total: 0, available: true) == nil,
          memoryUsagePercent(used: 17, total: 16, available: true) == nil,
          memoryUsagePercent(used: 8, total: 16, available: false) == nil else { fatalError("memory percentage calculation failed") }
    var history: [Double?] = []
    for _ in 0..<31 { appendMonitorSample(25, to: &history) }
    appendMonitorSample(nil, to: &history)
    guard history.count == 30, history.last! == nil else { fatalError("monitor history bounds or gaps failed") }
    let path = Sparkline(samples: [10, 20, nil, 50, 60]).path(in: CGRect(x: 0, y: 0, width: 100, height: 20)).cgPath
    var moves = 0, lines = 0
    path.applyWithBlock { element in
        if element.pointee.type == .moveToPoint { moves += 1 }
        if element.pointee.type == .addLineToPoint { lines += 1 }
    }
    guard moves == 2, lines == 2 else { fatalError("monitor graph bridged missing data") }
    let model = Model(startServices: false); model.sample()
    RunLoop.current.run(until: Date().addingTimeInterval(0.25)); model.sample()
    guard model.cpuHistory.count == 2, model.memoryHistory.count == 2 else { fatalError("live monitoring sample failed") }
    print("monitoring self-test passed; CPU=\(model.cpu), RAM=\(model.memoryPercent), pressure=\(model.pressure)")
} else if CommandLine.arguments.contains("--self-test-teleprompter") {
    _ = NSApplication.shared
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("rium-prompt-test-\(UUID().uuidString)", isDirectory: true)
    let suite = "app.rium.notch.prompt-test.\(UUID().uuidString)"
    guard let preferences = UserDefaults(suiteName: suite) else { fatalError("isolated preferences unavailable") }
    defer { try? FileManager.default.removeItem(at: root); preferences.removePersistentDomain(forName: suite) }
    let sample = "🙂 Test 두 TEST"
    guard let firstMatch = promptSearchRange(sample, query: "test", selected: NSRange(location: 0, length: 0), backwards: false),
          let secondMatch = promptSearchRange(sample, query: "test", selected: firstMatch, backwards: false),
          let wrappedMatch = promptSearchRange(sample, query: "test", selected: secondMatch, backwards: false),
          wrappedMatch == firstMatch,
          promptSearchRange(sample, query: "test", selected: firstMatch, backwards: true) == secondMatch,
          promptSearchRange(sample, query: "없음", selected: firstMatch, backwards: false) == nil else { fatalError("teleprompter search range failed") }
    func views(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap { views($0) } }
    let first = TeleprompterController(root: root, preferences: preferences); first.show()
    guard let firstWindow = NSApp.windows.first(where: { $0.title == "Rium Notch 프롬프터" && $0.isVisible }),
          let firstContent = firstWindow.contentView,
          let text = views(firstContent).compactMap({ $0 as? NSTextView }).first,
          let size = views(firstContent).compactMap({ $0 as? NSSlider }).first(where: { $0.accessibilityLabel() == "글자 크기" }) else { fatalError("teleprompter controls unavailable") }
    let fixture = "# 시작\n🙂 첫 번째 줄\n## 다음\n두 번째 줄"
    text.string = fixture; text.didChangeText(); first.flush()
    size.doubleValue = 42; guard let action = size.action else { fatalError("font control action missing") }; _ = NSApp.sendAction(action, to: size.target, from: size)
    RunLoop.current.run(until: Date().addingTimeInterval(0.8))
    guard let chapters = views(firstContent).compactMap({ $0 as? NSPopUpButton }).first(where: { $0.accessibilityLabel() == "원고 구간 이동" }), chapters.numberOfItems == 3,
          let search = views(firstContent).compactMap({ $0 as? NSSearchField }).first,
          let next = views(firstContent).compactMap({ $0 as? NSButton }).first(where: { $0.accessibilityLabel() == "다음 검색 결과" }), let findAction = next.action else { fatalError("teleprompter navigation controls unavailable") }
    search.stringValue = "두 번째"; _ = NSApp.sendAction(findAction, to: next.target, from: next)
    guard (text.string as NSString).substring(with: text.selectedRange()) == "두 번째" else { fatalError("teleprompter search action failed") }
    chapters.selectItem(at: 2); guard let chapterAction = chapters.action else { fatalError("chapter action missing") }
    _ = NSApp.sendAction(chapterAction, to: chapters.target, from: chapters)
    guard text.selectedRange().location == ("# 시작\n🙂 첫 번째 줄\n" as NSString).length else { fatalError("teleprompter chapter navigation failed") }
    firstWindow.close()
    let second = TeleprompterController(root: root, preferences: preferences); second.show()
    guard let nextWindow = NSApp.windows.first(where: { $0.title == "Rium Notch 프롬프터" && $0.isVisible }),
          let content = nextWindow.contentView,
          let restored = views(content).compactMap({ $0 as? NSTextView }).first,
          restored.string == fixture, abs((restored.font?.pointSize ?? 0) - 42) < 0.01 else { fatalError("teleprompter restore failed") }
    nextWindow.close(); print("teleprompter restore, search and chapter self-test passed")
} else if CommandLine.arguments.contains("--self-test-updater") {
    func release(_ tag: String, _ url: String, prerelease: Bool = false) -> Data {
        try! JSONSerialization.data(withJSONObject: ["tag_name": tag, "html_url": url, "draft": false, "prerelease": prerelease])
    }
    let good = release("v1.2.3", "https://github.com/contentriumkorea/rium-notch/releases/tag/v1.2.3")
    guard UpdateController.parse(good, current: "1.2.2").0.hasPrefix("새 릴리스"),
          UpdateController.parse(good, current: "1.2.3").0.hasPrefix("최신 릴리스"),
          UpdateController.parse(release("v1.2.3", "https://evil.example/contentriumkorea/rium-notch/releases/tag/v1.2.3"), current: "1.0.0").1 == nil,
          UpdateController.parse(release("v1.2.3", "https://github.com/contentriumkorea/rium-notch/releases/tag/v1.2.3", prerelease: true), current: "1.0.0").1 == nil,
          UpdateController.version("v1.2.3-beta") == nil else { fatalError("updater validation failed") }
    guard UpdateController.isDue(last: 0, now: 100),
          !UpdateController.isDue(last: 100, now: 100 + 86399),
          UpdateController.isDue(last: 100, now: 100 + 86400),
          UpdateController.isDue(last: 200, now: 100) else { fatalError("updater schedule failed") }
    let suite = "app.rium.notch.updater-test.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suite) else { fatalError("updater test preferences unavailable") }
    defer { defaults.removePersistentDomain(forName: suite) }
    let response = HTTPURLResponse(url: URL(string: "https://api.github.com/repos/contentriumkorea/rium-notch/releases/latest")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    var requests = 0
    let updater = UpdateController(defaults: defaults, currentVersion: "1.2.2", fetch: { _, done in requests += 1; done(good, response, nil) })
    updater.start()
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    guard requests == 1, updater.status.hasPrefix("새 릴리스"), updater.releaseURL != nil else { fatalError("automatic update check failed") }
    let restored = UpdateController(defaults: defaults, currentVersion: "1.2.2", fetch: { _, _ in requests += 1 })
    restored.start()
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    guard requests == 1, restored.status.hasPrefix("새 릴리스"), restored.releaseURL != nil else { fatalError("update cache or throttle failed") }
    defaults.removeObject(forKey: "rium.update.lastCheck")
    let malformed = UpdateController(defaults: defaults, currentVersion: "1.2.2", fetch: { _, done in done(Data("{}".utf8), response, nil) })
    malformed.check()
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    guard defaults.double(forKey: "rium.update.lastCheck") == 0, malformed.releaseURL != nil else { fatalError("invalid response suppressed retry or erased cached release") }
    print("updater release, automatic scheduling, cache and retry self-test passed")
} else if CommandLine.arguments.contains("--self-test-media-order") {
    struct MediaRequestFixture { let action: String; let done: ([String: Any]) -> Void }
    var requests: [MediaRequestFixture] = []
    let model = Model(startServices: false, mediaRequester: { action, _, done in requests.append(MediaRequestFixture(action: action, done: done)) })
    model.mediaTitle = "초기 곡"
    model.refreshMedia(); model.controlMedia("next"); model.controlMedia("previous")
    guard requests.map(\.action) == ["get", "next"], model.mediaControlPending else { fatalError("media commands not serialized") }
    requests[0].done(["event": "result", "data": ["title": "이전 응답", "playing": true]])
    guard model.mediaTitle == "초기 곡" else { fatalError("stale media response applied") }
    requests[1].done(["event": "result"])
    guard requests.map(\.action) == ["get", "next", "previous"] else { fatalError("second media command order failed") }
    requests[2].done(["event": "result"])
    RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    guard !model.mediaControlPending, requests.last?.action == "get" else { fatalError("media command refresh missing") }
    requests.last?.done(["event": "result", "data": ["title": "현재 곡", "duration": 100.0, "elapsedTime": 20.0]])
    guard model.mediaTitle == "현재 곡" else { fatalError("fresh media response missing") }
    model.seekMedia(25); model.controlMedia("next")
    guard requests.last?.action == "seek" else { fatalError("command overtook seek") }
    requests.last?.done(["event": "result"])
    guard requests.last?.action == "next" else { fatalError("queued command did not resume after seek") }
    requests.last?.done(["event": "error", "message": "명령 오류"])
    guard !model.mediaControlPending, model.mediaError == "명령 오류" else { fatalError("media error was not surfaced") }
    print("media ordering and stale response self-test passed")
} else if CommandLine.arguments.contains("--self-test-timer-process-write") || CommandLine.arguments.contains("--self-test-timer-process-read") {
    guard let suite = ProcessInfo.processInfo.environment["RIUM_TIMER_TEST_SUITE"], suite.hasPrefix("app.rium.notch.timer-test."), let defaults = UserDefaults(suiteName: suite) else { fatalError("isolated timer suite required") }
    let model = Model(startServices: false, timerPreferences: defaults)
    if CommandLine.arguments.contains("--self-test-timer-process-write") {
        model.startTimer(60); defaults.synchronize(); print("timer checkpoint written")
    } else {
        timerReset(); model.restoreTimer()
        guard model.timerState == 1, (50...60).contains(model.timerRemaining) else { fatalError("timer did not restore across processes") }
        model.resetTimer(); defaults.removePersistentDomain(forName: suite); defaults.synchronize()
        print("timer checkpoint restored across processes")
    }
} else if CommandLine.arguments.contains("--self-test-pomodoro") {
    let suite = "app.rium.notch.timer-test.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suite) else { fatalError("timer test preferences unavailable") }
    defer { defaults.removePersistentDomain(forName: suite); timerReset() }
    let first = Model(startServices: false, timerPreferences: defaults)
    first.startPomodoro()
    guard first.timerPomodoro, first.timerPhase == .focus, first.timerSessions == 0, first.timerState == 1,
          (1499...1500).contains(first.timerRemaining) else { fatalError("pomodoro start failed") }
    first.pauseTimer(); guard first.timerState == 2 else { fatalError("pomodoro pause failed") }
    first.resumeTimer(); guard first.timerState == 1 else { fatalError("pomodoro resume failed") }
    timerStart(1); RunLoop.current.run(until: Date().addingTimeInterval(1.2)); first.updateTimer()
    guard first.timerPhase == .shortBreak, first.timerSessions == 1, first.timerState == 1,
          (299...300).contains(first.timerRemaining),
          timerSummary(state: 1, remaining: 300, phase: .shortBreak) == "짧은 휴식 05:00" else { fatalError("pomodoro transition failed") }
    timerReset()
    let restored = Model(startServices: false, timerPreferences: defaults); restored.restoreTimer()
    guard restored.timerPomodoro, restored.timerPhase == .shortBreak, restored.timerSessions == 1, restored.timerState == 1 else { fatalError("pomodoro restore failed") }
    defaults.set(["state": 1, "mode": "pomodoro", "phase": 0, "sessions": 3,
                  "deadline": Date().timeIntervalSince1970 - 300], forKey: "rium.timer.checkpoint")
    timerReset()
    let afterExpiry = Model(startServices: false, timerPreferences: defaults); afterExpiry.restoreTimer()
    guard afterExpiry.timerPhase == .longBreak, afterExpiry.timerSessions == 4, afterExpiry.timerState == 1,
          (899...900).contains(afterExpiry.timerRemaining) else { fatalError("long break restore failed") }
    afterExpiry.pauseTimer(); timerReset()
    let paused = Model(startServices: false, timerPreferences: defaults); paused.restoreTimer()
    guard paused.timerState == 2, paused.timerPhase == .longBreak, paused.timerSessions == 4 else { fatalError("paused pomodoro restore failed") }
    defaults.set(["state": 2, "mode": "pomodoro", "phase": Int.max, "sessions": 0, "remaining": 10], forKey: "rium.timer.checkpoint")
    paused.restoreTimer()
    guard defaults.object(forKey: "rium.timer.checkpoint") == nil else { fatalError("invalid pomodoro checkpoint accepted") }
    paused.setPomodoroValue(.focus, 12); paused.setPomodoroValue(.shortBreak, 3)
    paused.setPomodoroValue(.longBreak, 8); paused.setPomodoroValue(.sessions, 2)
    paused.setPomodoroValue(.focus, 0)
    timerReset()
    let custom = Model(startServices: false, timerPreferences: defaults)
    guard custom.pomodoroFocus == 12, custom.pomodoroShortBreak == 3, custom.pomodoroLongBreak == 8, custom.pomodoroSessions == 2 else { fatalError("pomodoro settings did not persist") }
    custom.startPomodoro()
    guard (719...720).contains(custom.timerRemaining) else { fatalError("custom focus duration failed") }
    timerStart(1); RunLoop.current.run(until: Date().addingTimeInterval(1.2)); custom.updateTimer()
    guard custom.timerPhase == .shortBreak, (179...180).contains(custom.timerRemaining) else { fatalError("custom short break failed") }
    defaults.set(["state": 1, "mode": "pomodoro", "phase": 0, "sessions": 1,
                  "deadline": Date().timeIntervalSince1970 - 1], forKey: "rium.timer.checkpoint")
    timerReset()
    let customRestored = Model(startServices: false, timerPreferences: defaults); customRestored.restoreTimer()
    guard customRestored.timerPhase == .longBreak, customRestored.timerSessions == 2,
          (479...480).contains(customRestored.timerRemaining) else { fatalError("custom long break failed") }
    print("pomodoro transition and persistence self-test passed")
} else if CommandLine.arguments.contains("--self-test-timer-persistence") {
    let suite = "app.rium.notch.timer-test.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suite) else { fatalError("timer test preferences unavailable") }
    defer { defaults.removePersistentDomain(forName: suite); timerReset() }
    let first = Model(startServices: false, timerPreferences: defaults)
    first.startTimer(60); first.pauseTimer()
    timerReset()
    let second = Model(startServices: false, timerPreferences: defaults); second.restoreTimer()
    guard second.timerState == 2, (59...60).contains(second.timerRemaining) else { fatalError("paused timer restore failed") }
    second.resumeTimer(); timerReset()
    let third = Model(startServices: false, timerPreferences: defaults); third.restoreTimer(at: Date().addingTimeInterval(120))
    guard third.timerState == 3, third.timerRemaining == 0 else { fatalError("expired timer restore failed") }
    third.resetTimer()
    guard defaults.object(forKey: "rium.timer.checkpoint") == nil else { fatalError("timer checkpoint not removed") }
    defaults.set(["state": 2, "remaining": 86401], forKey: "rium.timer.checkpoint")
    third.restoreTimer()
    guard defaults.object(forKey: "rium.timer.checkpoint") == nil else { fatalError("invalid timer checkpoint accepted") }
    print("timer checkpoint self-test passed")
} else if CommandLine.arguments.contains("--self-test-timer-state") {
    let model = Model(startServices: false)
    timerStart(1); model.updateTimer()
    guard model.timerState == 1, timerSummary(state: model.timerState, remaining: model.timerRemaining) != nil else { fatalError("timer did not start") }
    RunLoop.current.run(until: Date().addingTimeInterval(1.2)); model.updateTimer()
    guard model.timerState == 3, timerSummary(state: model.timerState, remaining: model.timerRemaining) == "타이머 완료" else { fatalError("timer did not finish") }
    timerReset(); model.updateTimer()
    guard model.timerState == 0 else { fatalError("timer did not reset") }
    print("timer start, finish and reset self-test passed")
} else if CommandLine.arguments.contains("--self-test-timer-summary") {
    guard timerSummary(state: 0, remaining: 0) == nil,
          timerSummary(state: 1, remaining: 61) == "타이머 01:01",
          timerSummary(state: 2, remaining: 3601) == "타이머 일시 정지 1:00:01",
          timerSummary(state: 3, remaining: 0) == "타이머 완료" else { fatalError("timer summary failed") }
    print("timer summary self-test passed")
} else if CommandLine.arguments.contains("--self-test-live-lyrics") {
    _ = NSApplication.shared
    let model = Model(startServices: false)
    model.lyricsEnabled = true; model.mediaTitle = "I Want to Live"; model.mediaArtist = "Borislav Slavov"; model.mediaDuration = 233
    model.refreshLyrics()
    model.mediaTitle = "Rium Notch nonexistent fixture 473860"; model.mediaArtist = "Rium Notch nonexistent artist 473860"
    model.refreshLyrics()
    let firstDeadline = Date().addingTimeInterval(25)
    while model.lyricsStatus != "이 곡의 가사를 찾지 못했습니다" && Date() < firstDeadline { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
    guard model.lyricsStatus == "이 곡의 가사를 찾지 못했습니다", model.lyricLines.isEmpty else { fatalError("stale lyric response was not discarded") }
    model.mediaTitle = "I Want to Live"; model.mediaArtist = "Borislav Slavov"; model.refreshLyrics()
    let deadline = Date().addingTimeInterval(25)
    while model.lyricLines.isEmpty && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
    guard !model.lyricLines.isEmpty, model.lyricLines.contains(where: { $0.time != nil }), model.lyricsStatus == "가사 제공: LRCLIB" else { fatalError("live lyric model did not load") }
    print("live lyric model and stale-response self-test passed")
} else if CommandLine.arguments.contains("--self-test-lyrics") {
    let timed = parseLyrics(synced: "[00:12.20]두 번째\n[00:02.50]첫 번째\n[ar:metadata]", plain: nil)
    guard timed.count == 2, timed[0].text == "첫 번째", timed[0].time == 2.5, timed[1].time == 12.2 else { fatalError("timed lyric parsing failed") }
    let plain = parseLyrics(synced: nil, plain: "첫 줄\n\n둘째 줄")
    guard plain.count == 2, plain[0].time == nil else { fatalError("plain lyric parsing failed") }
    let repeated = parseLyrics(synced: "[00:03.00][00:09.00]반복\n[00:06.00]\n[ar:metadata]", plain: nil)
    guard repeated.count == 3, repeated[0].time == 3, repeated[1].time == 6, repeated[1].text.isEmpty, repeated[2].time == 9, repeated[2].text == "반복" else { fatalError("repeated or empty lyric timing failed") }
    print("lyrics self-test passed")
} else if CommandLine.arguments.contains("--self-test-codex-usage") {
    precondition(codexWindow(["usedPercent": 0.0 as Any, "windowDurationMins": 300 as Any]) == "5시간 사용 0%")
    precondition(codexWindow(["usedPercent": 42.0 as Any, "windowDurationMins": 1501 as Any]) == "1일 1시간 1분 사용 42%")
    precondition(codexWindow(["usedPercent": NSNull()]) == nil)
    let extra = codexAdditionalUsage(["buckets": [["id":"extra", "name":"추가\n구간", "primary":["usedPercent":42.0], "spendControlReached":true]]])
    precondition(extra.count == 1 && extra[0].contains("추가구간") && extra[0].contains("42%") && extra[0].contains("지출 한도 도달"))
    let restrictions = codexRestrictions(["rateLimitReachedType":"workspace_member_usage_limit_reached", "individualLimit":["remainingPercent":13]])
    precondition(restrictions == ["구성원 사용 한도 도달", "개인 지출 한도 13% 남음"])
    precondition(codexRestrictions(["individualLimit":["remainingPercent":-1]]).isEmpty)
    precondition(codexRestrictions(["rateLimitReachedType":"future_kind"]) == ["사용 제한 상태 확인 필요"])
    let bucket = codexAdditionalUsage(["buckets":[["id":"extra", "rateLimitReachedType":"rate_limit_reached"]]])
    precondition(bucket.count == 1 && bucket[0].contains("사용 한도 도달"))
    print("Codex usage self-test passed")
} else if CommandLine.arguments.contains("--self-test-clipboard") {
    // A private named pasteboard never reads or modifies the user's clipboard.
    let board = NSPasteboard(name: NSPasteboard.Name("app.rium.notch.self-test.\(UUID().uuidString)"))
    let model = Model(pasteboard: board, startServices: false)
    guard clipboardImageSize(159) == "159바이트", clipboardImageSize(1024) == "1.0 KB", clipboardImageSize(1048576) == "1.0 MB" else { fatalError("clipboard size display failed") }
    clipboardClear(); model.toggleClipboard()
    board.clearContents(); board.setString("Rium test value", forType: .string); model.sampleClipboard()
    guard model.clipboardItems.count == 1, case .text("Rium test value") = model.clipboardItems[0].content else { fatalError("text capture failed") }
    board.clearContents(); board.setString("hidden fixture", forType: .string)
    board.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")); model.sampleClipboard()
    guard model.clipboardItems.count == 1 else { fatalError("concealed content was recorded") }
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("clipboard image fixture unavailable") }
    board.clearContents(); board.setData(png, forType: .png); model.sampleClipboard()
    guard model.clipboardItems.count == 2, case .image(let stored, .png) = model.clipboardItems[0].content, stored == png else { fatalError("image capture failed") }
    model.copyClipboard(model.clipboardItems[0]); model.sampleClipboard()
    guard board.data(forType: .png) == png, model.clipboardItems.count == 2 else { fatalError("image restore or self-copy guard failed") }
    let urls = [URL(fileURLWithPath: "/tmp/rium-clipboard-fixture-a"), URL(fileURLWithPath: "/tmp/rium-clipboard-fixture-b")]
    board.clearContents(); board.writeObjects(urls as [NSURL]); model.sampleClipboard()
    guard model.clipboardItems.count == 3, case .files(let storedURLs) = model.clipboardItems[0].content, storedURLs == urls else { fatalError("file URL capture failed") }
    model.copyClipboard(model.clipboardItems[0])
    guard let copiedURLs = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], copiedURLs == urls else { fatalError("file URL restore failed") }
    clipboardClear(); model.reloadClipboard(); guard model.clipboardItems.isEmpty else { fatalError("clipboard clear failed") }
    board.releaseGlobally()
    print("clipboard self-test passed")
} else if CommandLine.arguments.contains("--self-test-displays") {
    guard resolvedDisplayID(preferred: 11, available: [11, 22], primary: 22) == 11,
          resolvedDisplayID(preferred: nil, available: [11, 22], primary: 22) == 22,
          resolvedDisplayID(preferred: 11, available: [22], primary: nil) == 22,
          resolvedDisplayID(preferred: 11, available: [], primary: nil) == nil,
          notchWidth(expanded: true, displayWidth: 640) == 600,
          notchWidth(expanded: false, displayWidth: 640) == 405 else { fatalError("display resolution test failed") }
    func size(_ agent: Bool, _ timer: Bool, _ music: Bool) -> CGSize {
        calculateCollapsedNotchSize(cameraWidth: 185, cameraHeight: 32, screenWidth: 1512, agent: agent, timer: timer, music: music)
    }
    guard size(false, false, false) == CGSize(width: 185, height: 32),
          size(true, false, false) == CGSize(width: 425, height: 35), size(false, true, false).width == 299,
          size(false, false, true).width == 296, size(false, true, true).width == 331 else { fatalError("collapsed notch state size failed") }
    print("display selection self-test passed")
} else if CommandLine.arguments.contains("--self-test-dictation-preferences") {
    let domain = "app.rium.notch.dictationtest.\(UUID().uuidString)"
    guard let preferences = UserDefaults(suiteName: domain) else { fatalError("isolated preferences unavailable") }
    defer {
        preferences.removePersistentDomain(forName: domain); preferences.synchronize()
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences/\(domain).plist")
        if let data = try? Data(contentsOf: url),
           let contents = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any], contents.isEmpty {
            try? FileManager.default.removeItem(at: url)
        }
    }
    let first = DictationController(preferences: preferences)
    guard first.autoStart else { fatalError("default dictation preference is not enabled") }
    first.disable(persist: false)
    guard first.autoStart else { fatalError("temporary shutdown changed preference") }
    first.disable()
    guard !DictationController(preferences: preferences).autoStart else { fatalError("disabled preference was not retained") }
    guard DictationShortcut.fn.matches(.function), !DictationShortcut.fn.matches([.function, .command]),
          DictationShortcut.controlOption.matches([.control, .option]), !DictationShortcut.controlOption.matches(.control) else { fatalError("shortcut flags are incorrect") }
    first.setShortcut(.controlOption)
    guard DictationController(preferences: preferences).shortcut == .controlOption else { fatalError("shortcut preference was not retained") }
    print("dictation preferences self-test passed")
} else if CommandLine.arguments.contains("--self-test-file-drop") {
    guard let root = ProcessInfo.processInfo.environment["RIUM_SHELF_TEST_ROOT"] else { fatalError("isolated test root required") }
    _ = NSApplication.shared
    let folder = URL(fileURLWithPath: root, isDirectory: true)
    let files = [folder.appendingPathComponent("첫 파일.txt"), folder.appendingPathComponent("second file.txt")]
    for (index, file) in files.enumerated() { try Data("fixture-\(index)".utf8).write(to: file) }
    let model = Model(startServices: false)
    model.setFileDragActive(true)
    guard model.expanded && model.section == .shelf else { fatalError("drag hover did not reveal shelf") }
    let providers = files.map { NSItemProvider(object: $0 as NSURL) }
    guard model.receiveFileDrop(providers), !model.receiveFileDrop([NSItemProvider(object: "not a file" as NSString)]),
          droppedFileURL(NSURL(string: "https://example.invalid/file")!) == nil else { fatalError("drop acceptance failed") }
    let deadline = Date().addingTimeInterval(8)
    while Date() < deadline && model.shelfItems.count < files.count { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
    guard Set(model.shelfItems) == Set(files.map(\.standardizedFileURL.path)) else { fatalError("file drop did not add both files") }
    for (index, file) in files.enumerated() {
        model.removeShelf(file.standardizedFileURL.path)
        guard try Data(contentsOf: file) == Data("fixture-\(index)".utf8) else { fatalError("file drop altered original") }
    }
    guard model.shelfItems.isEmpty else { fatalError("shelf reference cleanup failed") }
    print("file drop self-test passed")
} else if CommandLine.arguments.contains("--self-test-shelf") {
    guard let root = ProcessInfo.processInfo.environment["RIUM_SHELF_TEST_ROOT"] else { fatalError("isolated test root required") }
    let fixture = URL(fileURLWithPath: root).appendingPathComponent("fixture.txt")
    try Data("fixture".utf8).write(to: fixture)
    let model = Model(startServices: false); model.reloadShelf(); model.addShelf(fixture)
    guard model.shelfItems.contains(fixture.path) else { fatalError("shelf add failed") }
    model.removeShelf(fixture.path)
    guard model.shelfItems.isEmpty, FileManager.default.fileExists(atPath: fixture.path) else { fatalError("shelf remove altered source") }
    print("shelf self-test passed")
} else if CommandLine.arguments.contains("--self-test-real-screenshot") {
    guard let root = ProcessInfo.processInfo.environment["RIUM_SCREENSHOT_TEST_ROOT"] else { fatalError("isolated test root required") }
    guard ProcessInfo.processInfo.environment["RIUM_SHELF_TEST_ROOT"] != nil else { fatalError("isolated shelf required") }
    let folder = URL(fileURLWithPath: root, isDirectory: true)
    let model = Model(startServices: false)
    let monitor = model.screenshotMonitor
    let shelfContains: (URL) -> Bool = { url in model.shelfItems.contains { URL(fileURLWithPath: $0).resolvingSymlinksInPath() == url.resolvingSymlinksInPath() } }
    let waitUntil: (TimeInterval, () -> Bool) -> Bool = { seconds, condition in
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        return condition()
    }
    monitor.start(directoryOverride: folder)
    guard waitUntil(5, { model.screenshotStatus == "스크린샷 감시 중" }) else { fatalError("screenshot monitor did not start") }
    let unrelated = folder.appendingPathComponent("not-screenshot.png")
    try Data("fixture".utf8).write(to: unrelated)
    let falseAttribute = try PropertyListSerialization.data(fromPropertyList: false, format: .binary, options: 0)
    let set = falseAttribute.withUnsafeBytes { setxattr(unrelated.path, "com.apple.metadata:kMDItemIsScreenCapture", $0.baseAddress, falseAttribute.count, 0, 0) }
    guard set == 0 else { fatalError("false screenshot fixture attribute failed") }
    let capture = folder.appendingPathComponent("real-capture.png")
    let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-x", "-t", "png", capture.path]; process.standardError = FileHandle.nullDevice
    try process.run(); process.waitUntilExit()
    guard process.terminationStatus == 0, waitUntil(8, { shelfContains(capture) }), model.screenshotStatus == "스크린샷: real-capture.png" else { fatalError("actual screenshot did not reach shelf") }
    RunLoop.current.run(until: Date().addingTimeInterval(2.3))
    guard !shelfContains(unrelated) else { fatalError("non-screenshot was misclassified") }
    monitor.stop(); print("real screenshot to isolated shelf self-test passed")
} else if CommandLine.arguments.contains("--self-test-received-airdrop") {
    guard let root = ProcessInfo.processInfo.environment["RIUM_AIRDROP_TEST_ROOT"],
          let original = ProcessInfo.processInfo.environment["RIUM_AIRDROP_EXISTING_FIXTURE"],
          ProcessInfo.processInfo.environment["RIUM_SHELF_TEST_ROOT"] != nil else { fatalError("isolated test root and existing fixture required") }
    guard original.withCString({ isAirDropFile($0) }) == 1 else { fatalError("existing fixture is not marked as AirDrop") }
    let model = Model(startServices: false); let monitor = model.airDropMonitor
    let folder = URL(fileURLWithPath: root, isDirectory: true), copy = folder.appendingPathComponent("received-fixture.png")
    let shelfContains: (URL) -> Bool = { url in model.shelfItems.contains { URL(fileURLWithPath: $0).resolvingSymlinksInPath() == url.resolvingSymlinksInPath() } }
    let waitUntil: (TimeInterval, () -> Bool) -> Bool = { seconds, condition in
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        return condition()
    }
    monitor.start(directoryOverride: folder)
    guard waitUntil(5, { model.airDropStatus == "AirDrop 수신 감시 중" }) else { fatalError("AirDrop monitor did not start") }
    let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto"); process.arguments = [original, copy.path]; process.standardError = FileHandle.nullDevice
    try process.run(); process.waitUntilExit()
    guard process.terminationStatus == 0, waitUntil(8, { shelfContains(copy) }), model.airDropStatus == "AirDrop 수신: received-fixture.png", model.lightCue?.kind == .airDrop else { fatalError("existing AirDrop fixture did not reach shelf and lighting") }
    monitor.stop(); print("previously received AirDrop file to isolated shelf self-test passed")
} else if CommandLine.arguments.contains("--self-test-screenshot-location") {
    guard let root = ProcessInfo.processInfo.environment["RIUM_WATCH_TEST_ROOT"] else { fatalError("isolated test root required") }
    let parent = URL(fileURLWithPath: root, isDirectory: true)
    let first = parent.appendingPathComponent("first", isDirectory: true), second = parent.appendingPathComponent("second", isDirectory: true), third = parent.appendingPathComponent("third", isDirectory: true)
    try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
    try Data("existing".utf8).write(to: second.appendingPathComponent("existing.png"))
    final class SelectedDirectory {
        private let lock = NSLock(); private var current: URL
        init(_ value: URL) { current = value }
        func get() -> URL { lock.lock(); defer { lock.unlock() }; return current }
        func set(_ value: URL) { lock.lock(); defer { lock.unlock() }; current = value }
    }
    let selected = SelectedDirectory(first)
    var ready = 0, waiting = false, files: [URL] = []
    let monitor = ScreenshotMonitor(onStatus: { if $0 == "스크린샷 감시 중" { ready += 1 }; if $0 == "새 스크린샷 폴더 연결 대기 중" { waiting = true } }, onFile: { files.append($0) }, classify: { $0.pathExtension == "png" }, locationProvider: { selected.get() })
    let waitUntil: (TimeInterval, () -> Bool) -> Bool = { seconds, condition in
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        return condition()
    }
    monitor.start(); guard waitUntil(5, { ready == 1 }) else { fatalError("initial screenshot location failed") }
    selected.set(second)
    guard waitUntil(8, { ready == 2 }), files.isEmpty else { fatalError("screenshot location switch or baseline failed") }
    try Data("new".utf8).write(to: second.appendingPathComponent("new.png"))
    guard waitUntil(8, { files.count == 1 }), files[0].lastPathComponent == "new.png" else { fatalError("new location did not detect screenshots") }
    selected.set(third)
    guard waitUntil(8, { waiting }) else { fatalError("unavailable screenshot location not reported") }
    try Data("still watched".utf8).write(to: second.appendingPathComponent("while-waiting.png"))
    guard waitUntil(8, { files.count == 2 }), files[1].lastPathComponent == "while-waiting.png" else { fatalError("previous location stopped during retry") }
    try FileManager.default.createDirectory(at: third, withIntermediateDirectories: true)
    guard waitUntil(8, { ready == 3 }) else { fatalError("screenshot location retry failed") }
    try Data("final".utf8).write(to: third.appendingPathComponent("final.png"))
    guard waitUntil(8, { files.count == 3 }), files[2].lastPathComponent == "final.png" else { fatalError("retried location did not detect screenshots") }
    monitor.stop(); print("screenshot location switch self-test passed")
} else if CommandLine.arguments.contains("--self-test-watch-reconnect") {
    guard let root = ProcessInfo.processInfo.environment["RIUM_WATCH_TEST_ROOT"] else { fatalError("isolated test root required") }
    let parent = URL(fileURLWithPath: root, isDirectory: true)
    let air = parent.appendingPathComponent("air", isDirectory: true), shots = parent.appendingPathComponent("shots", isDirectory: true)
    try FileManager.default.createDirectory(at: air, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: shots, withIntermediateDirectories: true)
    let old = air.appendingPathComponent("old.txt"); try Data("old".utf8).write(to: old)
    try Data("old screenshot".utf8).write(to: shots.appendingPathComponent("new-shot.png"))
    let marker = "0083;abcdef;sharingd;fixture"
    guard marker.withCString({ setxattr(old.path, "com.apple.quarantine", $0, strlen($0), 0, 0) }) == 0 else { fatalError("old fixture marker failed") }
    var airReady = 0, shotReady = 0, airWaiting = false, shotWaiting = false
    var receivedAir: [URL] = [], receivedShots: [URL] = []
    let a = AirDropMonitor(onStatus: { if $0 == "AirDrop 수신 감시 중" { airReady += 1 }; if $0 == "다운로드 폴더 다시 연결 중" { airWaiting = true } }, onFile: { receivedAir.append($0) })
    let s = ScreenshotMonitor(onStatus: { if $0 == "스크린샷 감시 중" { shotReady += 1 }; if $0 == "스크린샷 폴더 다시 연결 중" { shotWaiting = true } }, onFile: { receivedShots.append($0) }, classify: { $0.lastPathComponent == "new-shot.png" })
    let waitUntil: (TimeInterval, () -> Bool) -> Bool = { seconds, condition in
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        return condition()
    }
    a.start(directoryOverride: air); s.start(directoryOverride: shots)
    guard waitUntil(5, { airReady == 1 && shotReady == 1 }), receivedAir.isEmpty, receivedShots.isEmpty else { fatalError("initial monitor baseline failed") }
    try FileManager.default.moveItem(at: air, to: parent.appendingPathComponent("air-old"))
    try FileManager.default.moveItem(at: shots, to: parent.appendingPathComponent("shots-old"))
    guard waitUntil(5, { airWaiting && shotWaiting }) else { fatalError("folder disconnect was not detected") }
    let airReplacement = parent.appendingPathComponent("air-replacement", isDirectory: true), shotReplacement = parent.appendingPathComponent("shots-replacement", isDirectory: true)
    try FileManager.default.createDirectory(at: airReplacement, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: shotReplacement, withIntermediateDirectories: true)
    let newAir = airReplacement.appendingPathComponent("new.txt"), newShot = shotReplacement.appendingPathComponent("new-shot.png")
    try Data("new".utf8).write(to: newAir)
    guard marker.withCString({ setxattr(newAir.path, "com.apple.quarantine", $0, strlen($0), 0, 0) }) == 0 else { fatalError("new fixture marker failed") }
    let sameName = airReplacement.appendingPathComponent("old.txt"); try Data("replacement".utf8).write(to: sameName)
    guard marker.withCString({ setxattr(sameName.path, "com.apple.quarantine", $0, strlen($0), 0, 0) }) == 0 else { fatalError("same-name fixture marker failed") }
    try Data("new".utf8).write(to: newShot)
    try FileManager.default.moveItem(at: airReplacement, to: air)
    try FileManager.default.moveItem(at: shotReplacement, to: shots)
    guard waitUntil(8, { airReady == 2 && shotReady == 2 }) else { fatalError("monitor reconnection failed") }
    guard waitUntil(8, { receivedAir.count == 2 && receivedShots.count == 1 }), Set(receivedAir.map(\.lastPathComponent)) == Set(["new.txt", "old.txt"]), receivedShots.first?.lastPathComponent == "new-shot.png" else { fatalError("new or same-name files not detected after reconnection") }
    a.stop(); s.stop(); print("AirDrop and screenshot reconnection self-test passed")
} else if CommandLine.arguments.contains("--self-test-monitor-cancel") {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("rium-monitor-cancel-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let gate = MonitorDeliveryGate()
    guard let first = gate.start(), gate.start() == nil, gate.matches(first, active: true) else { fatalError("monitor start gate failed") }
    gate.fail(first); guard !gate.matches(first, active: true), let second = gate.start(), second != first else { fatalError("monitor retry gate failed") }
    _ = gate.stop(); guard !gate.matches(second), let third = gate.start(), gate.matches(third, active: true) else { fatalError("monitor cancellation gate failed") }
    let locationStarted = DispatchSemaphore(value: 0), releaseLocation = DispatchSemaphore(value: 0)
    let classificationStarted = DispatchSemaphore(value: 0), releaseClassification = DispatchSemaphore(value: 0)
    var locationCalls = 0, statuses: [String] = [], received: [URL] = []
    let monitor = ScreenshotMonitor(onStatus: { statuses.append($0) }, onFile: { received.append($0) }, classify: { url in
        guard url.lastPathComponent == "fixture.png" else { return false }
        classificationStarted.signal(); _ = releaseClassification.wait(timeout: .now() + 5); return true
    }, locationProvider: {
        locationCalls += 1
        if locationCalls == 1 { locationStarted.signal(); _ = releaseLocation.wait(timeout: .now() + 5) }
        return folder
    })
    monitor.start()
    guard locationStarted.wait(timeout: .now() + 3) == .success else { fatalError("blocked location fixture did not start") }
    monitor.stop(); monitor.start(); releaseLocation.signal()
    func waitUntil(_ seconds: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        return condition()
    }
    guard waitUntil(5, { statuses.contains("스크린샷 감시 중") }) else { fatalError("monitor did not restart after cancellation") }
    try Data("fixture".utf8).write(to: folder.appendingPathComponent("fixture.png"))
    guard classificationStarted.wait(timeout: .now() + 4) == .success else { fatalError("classification fixture did not start") }
    monitor.stop(); releaseClassification.signal()
    guard waitUntil(5, { statuses.last == "스크린샷 감시 꺼짐" }), received.isEmpty else { fatalError("stopped monitor delivered a file") }
    let airStarted = DispatchSemaphore(value: 0), releaseAir = DispatchSemaphore(value: 0)
    var airStatuses: [String] = [], airReceived: [URL] = []
    let air = AirDropMonitor(onStatus: { airStatuses.append($0) }, onFile: { airReceived.append($0) }, classify: { path in
        guard path.hasSuffix("air-fixture.png") else { return false }
        airStarted.signal(); _ = releaseAir.wait(timeout: .now() + 5); return true
    })
    air.start(directoryOverride: folder)
    guard waitUntil(5, { airStatuses.contains("AirDrop 수신 감시 중") }) else { fatalError("AirDrop monitor did not start") }
    try Data("fixture".utf8).write(to: folder.appendingPathComponent("air-fixture.png"))
    guard airStarted.wait(timeout: .now() + 4) == .success else { fatalError("AirDrop classification fixture did not start") }
    air.stop(); releaseAir.signal()
    guard waitUntil(5, { airStatuses.last == "AirDrop 수신 감시 꺼짐" }), airReceived.isEmpty else { fatalError("stopped AirDrop monitor delivered a file") }
    print("monitor cancellation and restart self-test passed")
} else if CommandLine.arguments.contains("--self-test-airdrop") {
    guard let root = ProcessInfo.processInfo.environment["RIUM_AIRDROP_TEST_ROOT"] else { fatalError("isolated test root required") }
    let folder = URL(fileURLWithPath: root, isDirectory: true)
    var ready = false, received: URL?
    let monitor = AirDropMonitor(onStatus: { if $0 == "AirDrop 수신 감시 중" { ready = true } }, onFile: { received = $0 })
    monitor.start(directoryOverride: folder)
    let waitUntil: (TimeInterval, () -> Bool) -> Bool = { seconds, condition in
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        return condition()
    }
    guard waitUntil(5, { ready }) else { fatalError("monitor did not start") }
    let fixture = folder.appendingPathComponent("fixture.txt")
    try Data("fixture".utf8).write(to: fixture)
    let quarantine = "0083;abcdef;sharingd;test"
    let rc = quarantine.withCString { value in setxattr(fixture.path, "com.apple.quarantine", value, strlen(value), 0, 0) }
    guard rc == 0 else { fatalError("fixture attribute failed") }
    guard waitUntil(8, { received != nil }), received?.resolvingSymlinksInPath() == fixture.resolvingSymlinksInPath() else { fatalError("fixture was not detected") }
    monitor.stop(); print("AirDrop monitor self-test passed")
} else if CommandLine.arguments.contains("--self-test-screenshot") {
    guard let root = ProcessInfo.processInfo.environment["RIUM_SCREENSHOT_TEST_ROOT"] else { fatalError("isolated test root required") }
    let folder = URL(fileURLWithPath: root, isDirectory: true)
    var ready = false, received: URL?
    let monitor = ScreenshotMonitor(onStatus: { if $0 == "스크린샷 감시 중" { ready = true } }, onFile: { received = $0 }, classify: { $0.lastPathComponent == "capture-fixture.png" })
    monitor.start(directoryOverride: folder)
    let waitUntil: (TimeInterval, () -> Bool) -> Bool = { seconds, condition in
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        return condition()
    }
    guard waitUntil(5, { ready }) else { fatalError("screenshot monitor did not start") }
    let fixture = folder.appendingPathComponent("capture-fixture.png"); try Data("fixture".utf8).write(to: fixture)
    guard waitUntil(8, { received != nil }), received?.resolvingSymlinksInPath() == fixture.resolvingSymlinksInPath() else { fatalError("screenshot fixture was not detected") }
    monitor.stop(); print("screenshot monitor self-test passed")
} else if CommandLine.arguments.contains("--self-test-agenda") {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    func item(start: TimeInterval, end: TimeInterval, allDay: Bool = false) -> AgendaModel.Item {
        AgendaModel.Item(id: "fixture", title: "fixture", subtitle: "fixture", start: now.addingTimeInterval(start), end: now.addingTimeInterval(end), allDay: allDay)
    }
    guard agendaRelativeLabel(item(start: 30, end: 3600), now: now) == "곧 시작",
          agendaRelativeLabel(item(start: 30 * 60, end: 3600), now: now) == "30분 후",
          agendaRelativeLabel(item(start: 90 * 60, end: 7200), now: now) == "1시간 30분 후",
          agendaRelativeLabel(item(start: -10, end: 3600), now: now) == "진행 중",
          agendaTimeLabel(item(start: 0, end: 86400, allDay: true)) == "종일" else { fatalError("agenda label test failed") }
    print("agenda self-test passed")
} else if CommandLine.arguments.contains("--self-test-current-artwork") {
    guard let helper = Bundle.main.url(forAuxiliaryExecutable: "rium-notch-core") else { fatalError("media helper unavailable") }
    let process = Process(); let pipe = Pipe()
    process.executableURL = helper; process.arguments = ["media", "get"]
    process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
    try process.run(); let output = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    let lines = String(data: output, encoding: .utf8)?.split(separator: "\n") ?? []
    let records = lines.compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
    let row = records.compactMap { $0["data"] as? [String: Any] }.first
    if let encoded = row?["artworkData"] as? String, !encoded.isEmpty {
        guard let data = Data(base64Encoded: encoded), artworkLightColor(data) != nil else { fatalError("current artwork tint failed") }
        print("current artwork tint test passed")
    } else { print("current artwork unavailable; tint test skipped") }
} else if CommandLine.arguments.contains("--self-test-light-preferences") {
    _ = NSApplication.shared
    let domain = "app.rium.notch.lighttest.\(UUID().uuidString)"
    guard let preferences = UserDefaults(suiteName: domain) else { fatalError("isolated preferences unavailable") }
    defer {
        preferences.removePersistentDomain(forName: domain); preferences.synchronize()
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences/\(domain).plist")
        if let data = try? Data(contentsOf: url),
           let contents = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any], contents.isEmpty {
            try? FileManager.default.removeItem(at: url)
        }
    }
    let model = Model(startServices: false)
    model.agentItems = [AgentActivity(id: "fixture", project: "fixture", state: "작업 중", activity: "")]
    let view = NSHostingView(rootView: NotchAmbientLight(model: model).defaultAppStorage(preferences))
    view.frame = NSRect(x: 0, y: 0, width: 1000, height: 90)
    let window = NSWindow(contentRect: view.bounds, styleMask: .borderless, backing: .buffered, defer: false)
    window.isOpaque = false; window.backgroundColor = .clear; window.contentView = view
    func coverage() -> Int {
        RunLoop.current.run(until: Date().addingTimeInterval(0.7))
        view.layoutSubtreeIfNeeded(); view.needsDisplay = true
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("light render unavailable") }
        view.cacheDisplay(in: view.bounds, to: rep)
        var result = 0
        for y in stride(from: 0, to: rep.pixelsHigh, by: 3) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 3) {
                if (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.04 { result += 1 }
            }
        }
        return result
    }
    preferences.set(0.5, forKey: "rium.light.thickness"); let thin = coverage()
    preferences.set(2.0, forKey: "rium.light.thickness"); let thick = coverage()
    preferences.set("narrow", forKey: "rium.light.width"); let narrow = coverage()
    preferences.set("extraLarge", forKey: "rium.light.width"); let wide = coverage()
    preferences.set(false, forKey: "rium.light.enabled"); let off = coverage()
    preferences.set(true, forKey: "rium.light.enabled"); preferences.set(true, forKey: "rium.light.system")
    model.lightCue = NotchLightCue(kind: .systemControl, started: Date()); let eventActive = coverage()
    preferences.set(false, forKey: "rium.light.system"); let eventDisabled = coverage()
    guard thin > 0, thick > thin, narrow > 0, wide > narrow, off == 0, eventActive > 0, eventDisabled > 0 else { fatalError("light preference or event precedence failed: thin=\(thin), thick=\(thick), narrow=\(narrow), wide=\(wide), off=\(off), event=\(eventActive), disabled=\(eventDisabled)") }
    print("light preferences self-test passed")
} else if CommandLine.arguments.contains("--self-test-music-light") {
    guard ambientLightMode(expanded: true, agentActive: true, musicPlaying: true) == .off,
          ambientLightMode(expanded: false, agentActive: true, musicPlaying: true) == .agent,
          ambientLightMode(expanded: false, agentActive: false, musicPlaying: true) == .music,
          ambientLightMode(expanded: false, agentActive: true, musicPlaying: true, eventActive: true) == .off,
          ambientLightMode(expanded: false, agentActive: false, musicPlaying: false) == .off else { fatalError("ambient light precedence failed") }
    guard abs(musicRipplePhase(time: 2.7, offset: 0.5) - 0.5) < 0.00001 else { fatalError("music wave cycle failed") }
    let centerCrest = musicCrestPositions(0.5), edgeCrest = musicCrestPositions(0.0), otherEdgeCrest = musicCrestPositions(1.0)
    guard abs(centerCrest.left - 0.37) < 0.00001, abs(centerCrest.right - 0.63) < 0.00001,
          edgeCrest.left == 0, edgeCrest.peak == 0.01, abs(edgeCrest.right - 0.14) < 0.00001,
          abs(otherEdgeCrest.left - 0.86) < 0.00001, otherEdgeCrest.peak == 0.99, otherEdgeCrest.right == 1 else { fatalError("music crest gradient failed") }
    guard let crestRed = musicCrestColor(NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)).usingColorSpace(.sRGB),
          abs(crestRed.redComponent - 1) < 0.00001, abs(crestRed.greenComponent - 0.28) < 0.00001,
          abs(crestRed.blueComponent - 0.28) < 0.00001 else { fatalError("music crest tint failed") }
    guard abs(musicGlowWidth(notch: 405, arm: 76, screen: 1512) - 662.6) < 0.00001,
          abs(musicGlowWidth(notch: 405, arm: 220, screen: 1512) - 1001) < 0.00001,
          abs(musicGlowWidth(notch: 405, arm: 440, screen: 1512) - 1505.8) < 0.00001,
          musicGlowWidth(notch: 405, arm: 440, screen: 640) == 640,
          musicGlowWidth(notch: 405, arm: .nan, screen: 1512) == 0 else { fatalError("music glow width failed") }
    guard ambientArmRun(preset: "narrow", screenWidth: 1512) == 76,
          ambientArmRun(preset: "medium", screenWidth: 1512) == 130,
          ambientArmRun(preset: "wide", screenWidth: 1512) == 220,
          ambientArmRun(preset: "extraLarge", screenWidth: 1512) == 440,
          ambientArmRun(preset: "extraLarge", screenWidth: 640) == 117.5,
          ambientArmRun(preset: "unknown", screenWidth: 1512) == 220 else { fatalError("light width preset failed") }
    guard let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { fatalError("artwork fixture unavailable") }
    let fixtureRed = NSColor(deviceRed: 0.9, green: 0.1, blue: 0.1, alpha: 1)
    for y in 0..<4 { for x in 0..<4 { image.setColor(fixtureRed, atX: x, y: y) } }
    guard let data = image.representation(using: .png, properties: [:]),
          let tint = artworkLightColor(data)?.usingColorSpace(.sRGB), tint.redComponent > tint.blueComponent,
          artworkLightColor(Data("invalid".utf8)) == nil else { fatalError("artwork tint extraction failed") }
    print("music light self-test passed")
} else if CommandLine.arguments.contains("--self-test-light") {
    let arrival = runningArrivalSegments(elapsed: 0.41)
    guard runningArrivalSegments(elapsed: -0.01).isEmpty,
          runningArrivalSegments(elapsed: 0.82).isEmpty,
          arrival.count == 4, abs(arrival[0].start - 0.202186483251572) < 0.000001,
          abs(arrival[0].start + arrival[1].end - 1) < 0.000001,
          abs(arrival[0].opacity - 0.62) < 0.000001,
          arrival[2].highlight, arrival[3].highlight else { fatalError("agent arrival segment timing failed") }
    let referencePath = lightContour(width: 405, height: 32, armWidth: 220)
    let referenceLength = approximateContourLength(referencePath)
    let approval = otherAgentArrivalSegments(kind: .agentApproval, elapsed: 0.41, pathLength: referenceLength, arm: 220, notchWidth: 405, height: 32)
    let done = otherAgentArrivalSegments(kind: .agentDone, elapsed: 0.36, pathLength: referenceLength, arm: 220, notchWidth: 405, height: 32)
    guard referenceLength > 845, referenceLength < 909, approval.count == 4, done.count == 6,
          abs(approval[2].start + approval[3].end - 1) < 0.000001,
          abs(done[4].start + done[5].end - 1) < 0.000001,
          otherAgentArrivalSegments(kind: .agentDone, elapsed: 0.5, pathLength: referenceLength, arm: 220, notchWidth: 405, height: 32).count == 8,
          otherAgentArrivalSegments(kind: .agentDone, elapsed: 0.72, pathLength: referenceLength, arm: 220, notchWidth: 405, height: 32).isEmpty else { fatalError("agent approval or completion animation failed") }
    let model = Model(startServices: false)
    let running = AgentActivity(id: "fixture", project: "fixture", state: "작업 중", activity: "")
    let waiting = AgentActivity(id: "fixture", project: "fixture", state: "승인 대기 감지", activity: "")
    let finished = AgentActivity(id: "fixture", project: "fixture", state: "완료", activity: "")
    guard agentArrival(previous: [], current: [running], initialized: false) == nil,
          agentArrival(previous: [], current: [running], initialized: true) == .agentRunning,
          agentArrival(previous: [running], current: [running], initialized: true) == nil,
          agentArrival(previous: [running], current: [waiting], initialized: true) == .agentApproval,
          agentArrival(previous: [waiting], current: [finished], initialized: true) == .agentDone else { fatalError("agent light transition failed") }
    let contour = lightContour(width: 405, height: 42).boundingRect
    guard contour.width > 405, contour.height >= 40, rayonCount(armWidth: 48) == 5, rayonCount(armWidth: 220) == 12, rayonCount(armWidth: 1000) == 34 else { fatalError("light contour or ray count failed") }
    model.showLight(.airDrop)
    let first = model.lightCue?.id
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    model.showLight(.clipboard)
    guard model.lightCue?.id != first else { fatalError("new light cue was not installed") }
    RunLoop.current.run(until: Date().addingTimeInterval(2.05))
    guard model.lightCue?.kind == .clipboard else { fatalError("old cue cleared newer light") }
    RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    guard model.lightCue == nil else { fatalError("light did not stop") }
    print("light self-test passed")
} else if CommandLine.arguments.contains("--self-test-hover") {
    let model = Model(startServices: false)
    let reference = Date(timeIntervalSince1970: 1000)
    guard hoverReopenWait(lastCollapse: nil, now: reference) == 0,
          abs(hoverReopenWait(lastCollapse: reference, now: reference.addingTimeInterval(0.1)) - 0.24) < 0.0001,
          hoverReopenWait(lastCollapse: reference, now: reference.addingTimeInterval(0.33)) == 0 else { fatalError("hover cooldown calculation failed") }
    model.handleHover(true)
    guard model.expanded else { fatalError("initial hover did not open immediately") }
    model.handleHover(false); RunLoop.current.run(until: Date().addingTimeInterval(0.1)); model.handleHover(true)
    RunLoop.current.run(until: Date().addingTimeInterval(0.45)); guard model.expanded else { fatalError("reentered hover collapsed") }
    model.handleHover(false); RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    guard !model.expanded else { fatalError("hover collapse failed") }
    model.handleHover(true); guard !model.expanded else { fatalError("reopen cooldown skipped") }
    model.handleHover(false); RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    guard !model.expanded else { fatalError("cancelled reopen expanded") }
    model.handleHover(true); guard model.expanded else { fatalError("hover did not reopen after cooldown") }
    model.autoHideEnabled = false; model.handleHover(false); RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    guard model.expanded else { fatalError("disabled auto-hide collapsed") }
    model.expanded = false; model.hoverEnabled = false; model.handleHover(true); RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    guard !model.expanded else { fatalError("disabled hover expanded") }
    print("hover self-test passed")
} else if CommandLine.arguments.contains("--self-test-render-settings") {
    guard let output = ProcessInfo.processInfo.environment["RIUM_RENDER_TEST_PATH"] else { fatalError("render output required") }
    _ = NSApplication.shared
    let view = NSHostingView(rootView: SettingsView(model: Model(startServices: false), initialPage: ProcessInfo.processInfo.environment["RIUM_SETTINGS_TEST_PAGE"]))
    view.frame = NSRect(x: 0, y: 0, width: 1080, height: 780)
    let window = NSWindow(contentRect: view.bounds, styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = view; view.layoutSubtreeIfNeeded()
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("settings render unavailable") }
    view.cacheDisplay(in: view.bounds, to: rep)
    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("settings render failed") }
    try data.write(to: URL(fileURLWithPath: output), options: .atomic); print("settings render self-test passed")
} else if CommandLine.arguments.contains("--self-test-render-music-light") {
    guard let output = ProcessInfo.processInfo.environment["RIUM_RENDER_TEST_PATH"] else { fatalError("render output required") }
    _ = NSApplication.shared
    let model = Model(startServices: false)
    let view = NSHostingView(rootView: ZStack(alignment: .top) { NotchContainer(model: model); NotchMusicLightFrame(tint: NSColor.systemPink, time: 0.6) })
    view.frame = NSRect(x: 0, y: 0, width: 1100, height: 90)
    let window = NSWindow(contentRect: view.bounds, styleMask: .borderless, backing: .buffered, defer: false)
    window.isOpaque = false; window.backgroundColor = .clear; window.contentView = view
    view.layoutSubtreeIfNeeded()
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("music light render unavailable") }
    view.cacheDisplay(in: view.bounds, to: rep)
    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("music light render failed") }
    try data.write(to: URL(fileURLWithPath: output), options: .atomic); print("music light render self-test passed")
} else if CommandLine.arguments.contains("--self-test-render-ambient") {
    guard let output = ProcessInfo.processInfo.environment["RIUM_RENDER_TEST_PATH"] else { fatalError("render output required") }
    _ = NSApplication.shared
    let model = Model(startServices: false)
    model.agentItems = [AgentActivity(id: "fixture", project: "fixture", state: "작업 중", activity: "")]
    let view = NSHostingView(rootView: ZStack(alignment: .top) { NotchContainer(model: model); NotchAmbientLight(model: model) })
    view.frame = NSRect(x: 0, y: 0, width: 1100, height: 90)
    let window = NSWindow(contentRect: view.bounds, styleMask: .borderless, backing: .buffered, defer: false)
    window.isOpaque = false; window.backgroundColor = .clear; window.contentView = view
    view.layoutSubtreeIfNeeded()
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("ambient render unavailable") }
    view.cacheDisplay(in: view.bounds, to: rep)
    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("ambient render failed") }
    try data.write(to: URL(fileURLWithPath: output), options: .atomic); print("ambient render self-test passed")
} else if CommandLine.arguments.contains("--self-test-render-light") || CommandLine.arguments.contains("--self-test-render-system-light") || CommandLine.arguments.contains("--self-test-render-agent-approval") || CommandLine.arguments.contains("--self-test-render-agent-done") {
    guard let output = ProcessInfo.processInfo.environment["RIUM_RENDER_TEST_PATH"] else { fatalError("render output required") }
    _ = NSApplication.shared
    let model = Model(startServices: false)
    let cueKind: NotchLightCue.Kind = CommandLine.arguments.contains("--self-test-render-agent-approval") ? .agentApproval : (CommandLine.arguments.contains("--self-test-render-agent-done") ? .agentDone : (CommandLine.arguments.contains("--self-test-render-system-light") ? .systemControl : .airDrop))
    model.lightCue = NotchLightCue(kind: cueKind, started: Date().addingTimeInterval(cueKind == .agentApproval || cueKind == .agentDone ? -0.3 : -0.8))
    let view = NSHostingView(rootView: ZStack(alignment: .top) { NotchContainer(model: model); NotchAmbientLight(model: model) })
    view.frame = NSRect(x: 0, y: 0, width: 1000, height: 90)
    let window = NSWindow(contentRect: view.bounds, styleMask: .borderless, backing: .buffered, defer: false)
    window.isOpaque = false; window.backgroundColor = .clear; window.contentView = view
    view.layoutSubtreeIfNeeded()
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("light render unavailable") }
    view.cacheDisplay(in: view.bounds, to: rep)
    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("light render failed") }
    try data.write(to: URL(fileURLWithPath: output), options: .atomic); print("light render self-test passed")
} else if CommandLine.arguments.contains("--self-test-render-timer") || CommandLine.arguments.contains("--self-test-render-media-only") || CommandLine.arguments.contains("--self-test-render-media-timer") {
    guard let output = ProcessInfo.processInfo.environment["RIUM_RENDER_TEST_PATH"] else { fatalError("render output required") }
    _ = NSApplication.shared
    let model = Model(startServices: false); model.cameraExclusion = 185; model.cameraHeight = 32
    if !CommandLine.arguments.contains("--self-test-render-media-only") { model.timerState = 1; model.timerRemaining = 1499 }
    if CommandLine.arguments.contains("--self-test-render-media-only") || CommandLine.arguments.contains("--self-test-render-media-timer") { model.mediaPlaying = true }
    let view = NSHostingView(rootView: NotchContainer(model: model)); view.frame = NSRect(origin: .zero, size: model.collapsedNotchSize)
    let window = NSWindow(contentRect: view.bounds, styleMask: .borderless, backing: .buffered, defer: false); window.contentView = view
    view.layoutSubtreeIfNeeded()
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("timer render unavailable") }
    view.cacheDisplay(in: view.bounds, to: rep)
    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("timer render failed") }
    try data.write(to: URL(fileURLWithPath: output), options: .atomic); print("timer render self-test passed")
} else if CommandLine.arguments.contains("--self-test-render") || CommandLine.arguments.contains("--self-test-render-artwork-home") || CommandLine.arguments.contains("--self-test-render-music-view") || CommandLine.arguments.contains("--self-test-render-music-empty") || CommandLine.arguments.contains("--self-test-render-lyrics-view") || CommandLine.arguments.contains("--self-test-render-monitor") || CommandLine.arguments.contains("--self-test-render-weather") || CommandLine.arguments.contains("--self-test-render-agenda") || CommandLine.arguments.contains("--self-test-render-clipboard") || CommandLine.arguments.contains("--self-test-render-agent-view") {
    guard let output = ProcessInfo.processInfo.environment["RIUM_RENDER_TEST_PATH"] else { fatalError("render output required") }
    _ = NSApplication.shared
    let model = Model(startServices: false); model.expanded = true; model.cpu = "24%"; model.pressure = "정상"
    model.mediaAvailable = true; model.mediaTitle = "테스트 음악"; model.mediaArtist = "Rium"; model.weatherText = "서울  18°  맑음"; model.weatherCity = "서울"; model.weatherCondition = "맑음"; model.weatherTemperature = 18
    if CommandLine.arguments.contains("--self-test-render-agent-view") {
        model.section = .agents
        model.agentItems = [AgentActivity(id: "01234567-89ab-cdef-0123-456789abcdef", project: "Rium Notch", state: "활동 감지", activity: "도구 사용", recentActivities: ["작업 실행", "파일 수정", "도구 사용"], ageSeconds: 8)]
    }
    if CommandLine.arguments.contains("--self-test-render-artwork-home") || CommandLine.arguments.contains("--self-test-render-music-view") || CommandLine.arguments.contains("--self-test-render-lyrics-view") {
        let artwork = NSImage(size: NSSize(width: 120, height: 120))
        artwork.lockFocus()
        NSColor.systemPink.setFill(); NSRect(x: 0, y: 0, width: 60, height: 120).fill()
        NSColor.systemPurple.setFill(); NSRect(x: 60, y: 60, width: 60, height: 60).fill()
        NSColor.systemYellow.setFill(); NSRect(x: 60, y: 0, width: 60, height: 60).fill()
        artwork.unlockFocus(); model.mediaArtwork = artwork; model.mediaAtmosphere = blurredArtwork(artwork)
        guard model.mediaAtmosphere != nil else { fatalError("artwork atmosphere unavailable") }
    }
    if CommandLine.arguments.contains("--self-test-render-music-view") || CommandLine.arguments.contains("--self-test-render-music-empty") || CommandLine.arguments.contains("--self-test-render-lyrics-view") { model.section = .music; model.mediaPlaying = true; model.mediaDuration = 240; model.mediaElapsed = 90 }
    if CommandLine.arguments.contains("--self-test-render-lyrics-view") { model.lyricsEnabled = true; model.lyricLines = parseLyrics(synced: "[00:02.00]첫 번째 시험 문장\n[01:30.00]두 번째 시험 문장\n[02:30.00]세 번째 시험 문장", plain: nil) }
    if CommandLine.arguments.contains("--self-test-render-monitor") {
        model.section = .monitor; model.memory = "8.0 / 16.0 GB"; model.memoryPercent = "50%"; model.pressure = "정상"; model.swap = "0.0 GB"; model.cpuHistory = [10, 18, 14, 24]; model.memoryHistory = [45, 47, 49, 50]
        model.accounts = [Account(id: "fixture", name: "업무 계정", usage: "5시간 사용 42%", detail: "7일 사용 25%", connected: true)]
    }
    if CommandLine.arguments.contains("--self-test-render-clipboard") {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { fatalError("clipboard render image unavailable") }
        let pink = NSColor(deviceRed: 1, green: 0.25, blue: 0.55, alpha: 1)
        for y in 0..<16 { for x in 0..<16 { bitmap.setColor(pink, atX: x, y: y) } }
        guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("clipboard render PNG unavailable") }
        model.section = .clipboard; model.clipboardEnabled = true
        model.clipboardItems = [ClipboardRecord(id: 1, content: .text("복사한 문장이 표시됩니다.")),
                                ClipboardRecord(id: 2, content: .files([URL(fileURLWithPath: "/tmp/기획안.pdf"), URL(fileURLWithPath: "/tmp/참고.png")])),
                                ClipboardRecord(id: 3, content: .image(png, .png))]
    }
    if CommandLine.arguments.contains("--self-test-render-weather") {
        model.section = .weather; model.weatherTimeZoneID = "Asia/Seoul"
        var fixtureHours: [WeatherHour] = []
        for i in 0..<8 {
            let amount: Double? = i == 2 ? nil : Double(i) * 0.3
            let hour = WeatherHour(id: "fixture-\(i)", date: model.now.addingTimeInterval(Double(i) * 3600), temperature: 18 - Double(i), symbol: i % 2 == 0 ? "rain" : "cloudy", precipitation: amount)
            fixtureHours.append(hour)
        }
        model.weatherForecast = fixtureHours
    }
    if CommandLine.arguments.contains("--self-test-render-agenda") { model.section = .agenda }
    model.agenda.events = [AgendaModel.Item(id: "fixture", title: "제작 회의", subtitle: "", start: model.now.addingTimeInterval(1800), end: model.now.addingTimeInterval(5400))]
    let view = NSHostingView(rootView: NotchContainer(model: model)); view.frame = NSRect(origin: .zero, size: model.currentNotchSize)
    let window = NSWindow(contentRect: view.bounds, styleMask: .borderless, backing: .buffered, defer: false); window.contentView = view
    view.layoutSubtreeIfNeeded()
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("render unavailable") }
    view.cacheDisplay(in: view.bounds, to: rep)
    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("render failed") }
    try data.write(to: URL(fileURLWithPath: output), options: .atomic); print("render self-test passed")
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate(); app.delegate = delegate
    app.run()
}
