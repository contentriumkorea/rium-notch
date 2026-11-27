import AppKit
import ApplicationServices

/// macOS 버전에 따라 WindowManager 또는 Dock의 Mission Control 트리를 읽는다.
final class MissionControlReader {
    static let dockBundleID = "com.apple.dock"
    static let windowManagerBundleID = "com.apple.WindowManager"
    /// Dock AX 응답 제한 시간(초)
    static let messagingTimeout: Float = 0.3

    private var dockPID: pid_t?
    private var dockElement: AXUIElement?
    private var windowManagerPID: pid_t?
    private var windowManagerElement: AXUIElement?

    /// Dock PID 변경 시 기존 핸들 폐기 후 재생성
    func dockApplication() -> AXUIElement? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.dockBundleID).first else {
            dockPID = nil; dockElement = nil
            return nil
        }
        if dockPID != app.processIdentifier || dockElement == nil {
            let el = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(el, Self.messagingTimeout)
            dockPID = app.processIdentifier
            dockElement = el
        }
        return dockElement
    }

    private func windowManagerApplication() -> AXUIElement? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: Self.windowManagerBundleID).first else {
            windowManagerPID = nil; windowManagerElement = nil
            return nil
        }
        if windowManagerPID != app.processIdentifier || windowManagerElement == nil {
            let el = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(el, Self.messagingTimeout)
            windowManagerPID = app.processIdentifier
            windowManagerElement = el
        }
        return windowManagerElement
    }

    var systemPIDs: Set<pid_t> { Set([dockPID, windowManagerPID].compactMap { $0 }) }

    static func isDisplayGroup(role: String?, identifier: String?) -> Bool {
        guard role == kAXGroupRole as String, let id = identifier else { return false }
        return id == "mc.display" || id.hasPrefix("mc.display.")
    }

    /// WindowManager는 화면별 mc.display 그룹을, 이전 Dock은 mc 그룹을 노출한다.
    func missionControlGroups() -> [AXUIElement] {
        if let manager = windowManagerApplication() {
            let displays = AX.children(manager).filter {
                Self.isDisplayGroup(role: AX.string($0, kAXRoleAttribute), identifier: AX.string($0, kAXIdentifierAttribute))
            }
            if !displays.isEmpty { return displays }
        }
        guard let dock = dockApplication() else { return [] }
        let children = AX.children(dock)
        if let byID = children.first(where: { AX.string($0, kAXIdentifierAttribute) == "mc" }) { return [byID] }
        if let byTitle = children.first(where: {
            AX.string($0, kAXRoleAttribute) == kAXGroupRole as String
                && AX.string($0, kAXTitleAttribute) == "Mission Control"
        }) { return [byTitle] }
        return []
    }

    /// 그룹 아래의 창 썸네일. 상단 Spaces 막대(mc.spaces*) 하위 트리 제외
    func thumbnails(in groups: [AXUIElement]) -> [Thumbnail] {
        var out: [Thumbnail] = []
        for group in groups { collect(group, depth: 0, into: &out) }
        // 연속 관측 비교 안정화를 위해 왼쪽 위부터 읽는 순서로 정렬
        out.sort { a, b in
            if abs(a.frame.minY - b.frame.minY) > 2 { return a.frame.minY < b.frame.minY }
            return a.frame.minX < b.frame.minX
        }
        return out
    }

    private func collect(_ el: AXUIElement, depth: Int, into out: inout [Thumbnail]) {
        guard depth < 12 else { return }
        let identifier = AX.string(el, kAXIdentifierAttribute)
        if let identifier, identifier.hasPrefix("mc.spaces") { return }
        let role = AX.string(el, kAXRoleAttribute)
        if role == kAXButtonRole as String, let frame = AX.frame(el), frame.width >= 8, frame.height >= 8 {
            let title = AX.string(el, kAXTitleAttribute) ?? AX.string(el, kAXDescriptionAttribute) ?? ""
            out.append(Thumbnail(title: title, frame: frame, identifier: identifier,
                                 roleDescription: AX.string(el, kAXRoleDescriptionAttribute)))
            return
        }
        for c in AX.children(el) { collect(c, depth: depth + 1, into: &out) }
    }

    /// 진단용 트리 덤프. 개발 중 명시적으로 켠 경우에 한해 호출
    func dumpTree(_ el: AXUIElement, depth: Int = 0, into s: inout String, maxDepth: Int = 10) {
        guard depth <= maxDepth else { return }
        let pad = String(repeating: "  ", count: depth)
        let role = AX.string(el, kAXRoleAttribute) ?? "?"
        let sub = AX.string(el, kAXSubroleAttribute).map { " sub=\($0)" } ?? ""
        let id = AX.string(el, kAXIdentifierAttribute).map { " id=\"\($0)\"" } ?? ""
        let title = AX.string(el, kAXTitleAttribute).map { " title=\"\($0)\"" } ?? ""
        let desc = AX.string(el, kAXDescriptionAttribute).map { " desc=\"\($0)\"" } ?? ""
        let rd = AX.string(el, kAXRoleDescriptionAttribute).map { " roleDesc=\"\($0)\"" } ?? ""
        let fr = AX.frame(el).map { " frame=\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height))" } ?? ""
        s += "\(pad)\(role)\(sub)\(id)\(title)\(desc)\(rd)\(fr)\n"
        for c in AX.children(el) { dumpTree(c, depth: depth + 1, into: &s, maxDepth: maxDepth) }
    }
}
