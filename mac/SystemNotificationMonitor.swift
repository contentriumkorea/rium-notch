import Foundation
import AppKit
import SwiftUI

@_silgen_name("rium_system_notifications_read")
private func rustReadSystemNotifications(_ path: UnsafePointer<CChar>?, _ time: Double, _ id: Int64) -> UnsafeMutablePointer<CChar>?
@_silgen_name("rium_system_notifications_free")
private func rustFreeSystemNotifications(_ pointer: UnsafeMutablePointer<CChar>?)
@_silgen_name("rium_notification_marquee_offset")
private func rustNotificationMarqueeOffset(_ elapsed: Double, _ textWidth: Double) -> Double
@_silgen_name("rium_home_notification_display_nanoseconds")
func rustHomeNotificationDisplayNanoseconds() -> UInt64

private struct NotificationTextWidth: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
struct NotificationMarquee: View {
    let text: String
    let width: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var textWidth: CGFloat = 0
    @State private var started = ProcessInfo.processInfo.systemUptime
    private var label: some View {
        Text(text).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.white.opacity(0.68)).lineLimit(1)
    }
    var body: some View {
        ZStack(alignment: .leading) {
            label.fixedSize().hidden().background(GeometryReader { geometry in
                Color.clear.preference(key: NotificationTextWidth.self, value: geometry.size.width)
            })
            if !reduceMotion && width > 0 && textWidth > width {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { _ in
                    let elapsed = max(0, ProcessInfo.processInfo.systemUptime - started)
                    HStack(spacing: 40) { label.fixedSize(); label.fixedSize() }
                        .offset(x: CGFloat(rustNotificationMarqueeOffset(elapsed, Double(textWidth))))
                }
            } else {
                label.truncationMode(.tail).frame(width: max(0, width), alignment: .trailing)
            }
        }
        .frame(width: max(0, width), alignment: .leading).clipped()
        .onPreferenceChange(NotificationTextWidth.self) { value in
            if value.isFinite && value >= 0 { textWidth = value }
        }
        .onChange(of: text) { _, _ in started = ProcessInfo.processInfo.systemUptime }
    }
}

struct SystemNotificationPeek: Identifiable {
    let id = UUID()
    let source: String
    let title: String
    let subtitle: String
    let body: String
    let databaseIdentity: WatchedFileIdentity?
    let recordID: Int64?
    let deliveredTime: Double?
    init(source: String, title: String, subtitle: String = "", body: String,
         databaseIdentity: WatchedFileIdentity? = nil, recordID: Int64? = nil, deliveredTime: Double? = nil) {
        self.source = source; self.title = title; self.subtitle = subtitle; self.body = body
        self.databaseIdentity = databaseIdentity; self.recordID = recordID
        self.deliveredTime = deliveredTime.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
    }
    func detail(appName: String) -> String {
        systemNotificationDetail(title: title.isEmpty ? appName : title, subtitle: subtitle, body: body)
    }
    var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: source) }
    var appName: String {
        guard let url = appURL else { return "알림" }
        return (Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
    }
}

struct HomeNotificationInbox {
    struct Key: Hashable {
        let source: String
        let databaseIdentity: WatchedFileIdentity?
        let recordID: Int64?
        let deliveredTime: Double?
        let fallback: UUID?
        init(_ item: SystemNotificationPeek) {
            source = item.source; databaseIdentity = item.databaseIdentity; recordID = item.recordID
            deliveredTime = item.deliveredTime
            fallback = item.databaseIdentity == nil || item.recordID == nil || item.deliveredTime == nil ? item.id : nil
        }
    }
    private(set) var items: [SystemNotificationPeek] = []
    private(set) var unread: Set<Key> = []
    private var received: [Key] = []

    @discardableResult
    mutating func receive(_ item: SystemNotificationPeek) -> Bool {
        let key = Key(item)
        guard !received.contains(key) else { return false }
        received.append(key)
        if received.count > 100 { received.removeFirst(received.count - 100) }
        guard item.source != "app.glance.focus-timer" else { return true }
        items.append(item); unread.insert(key)
        if items.count > 20 { unread.remove(Key(items.removeFirst())) }
        return true
    }
    mutating func markRead(_ item: SystemNotificationPeek) { unread.remove(Key(item)) }
    mutating func dismiss(_ item: SystemNotificationPeek) {
        let key = Key(item)
        items.removeAll { Key($0) == key }; unread.remove(key)
    }
}

struct HomeNotificationSlot: ViewModifier {
    @ObservedObject var model: Model
    let slot: HomeSlot
    @AppStorage("rium.systemNotifications.details") private var showDetails = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let item = model.homeNotification(for: slot)
        content.opacity(item == nil ? 1 : 0)
            .allowsHitTesting(item == nil).accessibilityHidden(item != nil)
            .overlay {
                if let item = item {
                    HomeNotificationCard(model: model, item: item,
                                         showDetails: showDetails && !model.systemNotificationPrivacyHidden)
                        .task(id: item.id) { await model.trackHomeNotificationExposure(item, in: slot) }
                        .id(item.id).transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .animation(reduceMotion || model.systemNotificationPrivacyHidden ? nil : .easeInOut(duration: 0.22), value: item?.id)
    }
}

private struct HomeNotificationCard: View {
    @ObservedObject var model: Model
    let item: SystemNotificationPeek
    let showDetails: Bool
    private var appURL: URL? { item.appURL }
    private var appName: String { item.appName }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                if let url = appURL {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit()
                        .frame(width: 20, height: 20).clipShape(RoundedRectangle(cornerRadius: 5))
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "bell.fill").frame(width: 20, height: 20).accessibilityHidden(true)
                }
                Text(appName).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
                Button { model.dismissHomeNotification(item) } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).frame(width: 20, height: 20)
                }.buttonStyle(.plain).accessibilityLabel("이 알림을 노치에서 지우기")
            }
            Button { model.openHomeNotification(item) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(showDetails && !item.title.isEmpty ? item.title : "새 알림")
                        .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    if showDetails {
                        Text(item.detail(appName: appName)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(appURL == nil).accessibilityHint("알림을 보낸 앱 열기")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .riumGlassTile(radius: 24, homeSurface: true)
        // shortcut: card typography and transition need comparison with the running reference.
    }
}

struct HomeNotificationsPage: View {
    @ObservedObject var model: Model
    @AppStorage("rium.systemNotifications.details") private var showDetails = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("알림").font(.system(size: 14, weight: .semibold))
            if model.visibleHomeNotifications.isEmpty {
                Text(model.systemNotificationEnabled ? "표시할 알림이 없습니다." : "알림 감시가 꺼져 있습니다.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(model.visibleHomeNotifications.reversed()) { item in
                            notificationRow(item)
                        }
                    }
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func notificationRow(_ item: SystemNotificationPeek) -> some View {
        let details = showDetails && !model.systemNotificationPrivacyHidden
        return HStack(alignment: .top, spacing: 9) {
            if let url = item.appURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit()
                    .frame(width: 26, height: 26).clipShape(RoundedRectangle(cornerRadius: 6)).accessibilityHidden(true)
            } else {
                Image(systemName: "bell.fill").frame(width: 26, height: 26).accessibilityHidden(true)
            }
            Button { model.openHomeNotification(item) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(item.appName).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                        if model.homeNotificationInbox.unread.contains(HomeNotificationInbox.Key(item)) {
                            Circle().fill(.blue).frame(width: 5, height: 5).accessibilityLabel("읽지 않음")
                        }
                    }
                    Text(details && !item.title.isEmpty ? item.title : "새 알림")
                        .font(.system(size: 12, weight: .medium)).lineLimit(1)
                    if details {
                        let detail = item.detail(appName: item.appName)
                        if !detail.isEmpty { Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(item.appURL == nil).accessibilityHint("알림을 보낸 앱 열기")
            Button { model.dismissHomeNotification(item) } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).frame(width: 22, height: 22)
            }.buttonStyle(.plain).accessibilityLabel("이 알림을 노치에서 지우기")
        }
        .frame(maxWidth: .infinity, alignment: .leading).riumGlassTile(radius: 15)
        // shortcut: notification page layout and row motion need reference-frame comparison.
    }
}
enum SystemNotificationAppearance {
    private static let accents = NSCache<NSString, NSColor>()
    static func accent(for source: String) -> NSColor? {
        guard !source.isEmpty, source.utf8.count <= 512 else { return nil }
        if let cached = accents.object(forKey: source as NSString) { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source),
              let data = NSWorkspace.shared.icon(forFile: url.path).tiffRepresentation,
              let accent = artworkLightColor(data) else { return nil }
        accents.countLimit = 64
        accents.setObject(accent, forKey: source as NSString)
        return accent
    }
}
func enqueueSystemNotification(_ notification: SystemNotificationPeek, into queue: inout [SystemNotificationPeek]) {
    // shortcut: retain the newest 32 until the reference's burst policy is known.
    queue.append(notification)
    if queue.count > 32 { queue.removeFirst(queue.count - 32) }
}
func suspendSystemNotification(_ notification: SystemNotificationPeek, into queue: inout [SystemNotificationPeek]) {
    if queue.count > 31 { queue.removeFirst(queue.count - 31) }
    queue.insert(notification, at: 0)
}

struct SystemNotificationCursor {
    var identity: WatchedFileIdentity?
    var time = -1.0
    var id: Int64 = 0
    mutating func resetUnlessPreserved(_ preserve: Bool) {
        if !preserve { identity = nil; time = -1; id = 0 }
    }
    func request(for current: WatchedFileIdentity) -> (Double, Int64) {
        identity == current ? (time, id) : (-1, 0)
    }
}

func systemNotificationDetail(title: String, subtitle: String, body: String) -> String {
    let sender = title.trimmingCharacters(in: .whitespacesAndNewlines)
    var parts: [String] = []
    for value in [subtitle, body] {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty && text != sender && !parts.contains(text) { parts.append(text) }
    }
    return parts.joined(separator: " ─ ").replacingOccurrences(of: "\n", with: " ")
}

func systemNotificationPayload(_ hex: String, source: String, databaseIdentity: WatchedFileIdentity? = nil,
                               recordID: Int64? = nil, deliveredTime: Double? = nil) -> SystemNotificationPeek? {
    guard !hex.isEmpty, hex.utf8.count <= 131_072, hex.utf8.count.isMultiple(of: 2) else { return nil }
    let bytes = Array(hex.utf8)
    func nibble(_ byte: UInt8) -> UInt8? {
        switch byte { case 48...57: return byte - 48; case 97...102: return byte - 87; default: return nil }
    }
    var data = Data(); data.reserveCapacity(bytes.count / 2)
    for index in stride(from: 0, to: bytes.count, by: 2) {
        guard let high = nibble(bytes[index]), let low = nibble(bytes[index + 1]) else { return nil }
        data.append(high << 4 | low)
    }
    guard let root = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
          let request = root["req"] as? [String: Any] else { return nil }
    func text(_ key: String) -> String {
        guard let raw = request[key] as? String else { return "" }
        return String(raw.prefix(300)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    let title = text("titl"), subtitle = text("subt"), body = text("body")
    guard !title.isEmpty || !subtitle.isEmpty || !body.isEmpty else { return nil }
    return SystemNotificationPeek(source: String(source.prefix(512)), title: title, subtitle: subtitle, body: body,
                                  databaseIdentity: databaseIdentity, recordID: recordID, deliveredTime: deliveredTime)
}

final class SystemNotificationMonitor {
    private let queue = DispatchQueue(label: "app.rium.notch.system-notifications", qos: .utility)
    private let gate = MonitorDeliveryGate()
    private let resetLock = NSLock()
    private var resetPending = true
    private let path = NSHomeDirectory() + "/Library/Group Containers/group.com.apple.usernoted/db2/db"
    private let onStatus: (String) -> Void
    private let onNotification: (SystemNotificationPeek) -> Void
    private var timer: DispatchSourceTimer?
    private var cursor = SystemNotificationCursor()
    private var lastStatus = ""

    init(onStatus: @escaping (String) -> Void, onNotification: @escaping (SystemNotificationPeek) -> Void) {
        self.onStatus = onStatus; self.onNotification = onNotification
    }
    func start(preservingCursor: Bool = false) {
        guard let token = gate.start() else { return }
        queue.async { [self] in
            guard gate.matches(token, active: true) else { return }
            resetLock.lock(); let preserve = preservingCursor && !resetPending; resetPending = false; resetLock.unlock()
            timer?.cancel(); cursor.resetUnlessPreserved(preserve); lastStatus = ""
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: 2, leeway: .milliseconds(250))
            timer.setEventHandler { [weak self] in self?.poll(token) }
            self.timer = timer; timer.resume()
        }
    }
    func stop(preservingCursor: Bool = false) {
        if !preservingCursor { resetLock.lock(); resetPending = true; resetLock.unlock() }
        let token = gate.stop()
        queue.async { [self] in
            guard gate.matches(token) else { return }
            timer?.cancel(); timer = nil; cursor.resetUnlessPreserved(preservingCursor)
        }
    }
    private func status(_ message: String, token: UInt64) {
        guard message != lastStatus else { return }
        lastStatus = message
        DispatchQueue.main.async { [weak self] in
            guard let self, self.gate.matches(token, active: true) else { return }
            self.onStatus(message)
        }
    }
    private func poll(_ token: UInt64) {
        // Bound one drain cycle so stop and other queued work can run.
        for _ in 0..<4 { if !pollBatch(token) { break } }
    }
    private func pollBatch(_ token: UInt64) -> Bool {
        guard gate.matches(token, active: true) else { return false }
        guard let currentIdentity = watchedFileIdentity(path) else { status("시스템 알림 데이터에 접근할 수 없습니다", token: token); return false }
        let (time, id) = cursor.request(for: currentIdentity)
        guard let pointer = path.withCString({ rustReadSystemNotifications($0, time, id) }) else { status("시스템 알림을 읽을 수 없습니다", token: token); return false }
        defer { rustFreeSystemNotifications(pointer) }
        guard gate.matches(token, active: true), watchedFileIdentity(path) == currentIdentity,
              let data = String(validatingUTF8: pointer)?.data(using: .utf8),
              let value = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }
        if let error = value["error"] as? String { status(error, token: token); return false }
        guard let nextTime = value["time"] as? Double, nextTime.isFinite, nextTime >= 0,
              let nextID = (value["id"] as? NSNumber)?.int64Value, nextID >= 0,
              let rows = value["items"] as? [[String: Any]], let hasMore = value["hasMore"] as? Bool else { status("시스템 알림 응답을 읽을 수 없습니다", token: token); return false }
        let own = Bundle.main.bundleIdentifier ?? "app.rium.notch"
        let notifications = rows.compactMap { row -> SystemNotificationPeek? in
            guard let source = row["source"] as? String, source != own,
                  let recordID = (row["id"] as? NSNumber)?.int64Value, recordID >= 0,
                  let deliveredTime = row["time"] as? Double, deliveredTime.isFinite, deliveredTime > 0, deliveredTime <= nextTime,
                  let payload = row["payload"] as? String,
                  let notification = systemNotificationPayload(payload, source: source, databaseIdentity: currentIdentity,
                                                               recordID: recordID, deliveredTime: deliveredTime) else { return nil }
            return notification
        }
        // The worker is blocked while the main queue accepts the cursor and
        // notifications together, so a lock cannot discard an advanced cursor.
        let accepted = DispatchQueue.main.sync { [self] in
            guard gate.matches(token, active: true) else { return false }
            cursor.identity = currentIdentity; cursor.time = nextTime; cursor.id = nextID
            notifications.forEach(onNotification)
            return true
        }
        if accepted { status("시스템 알림 감시 중", token: token) }
        return accepted && hasMore
    }
}
