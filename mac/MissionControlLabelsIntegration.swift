import AppKit

/// Owns the Mission Control label engine for the lifetime of Rium Notch.
final class MissionControlLabelsIntegration {
    static let enabledKey = "rium.missionControl.enabled"
    static let standaloneBundleID = "com.markhan.MissionControlLabels"

    private let sessions: SessionCounter
    private let overlay: OverlayController
    private let engine: LabelEngine
    private var workspaceObservers: [NSObjectProtocol] = []

    init() {
        Self.importStandaloneSettingsIfNeeded()
        let sessions = SessionCounter()
        let overlay = OverlayController(sessions: sessions)
        self.sessions = sessions
        self.overlay = overlay
        self.engine = LabelEngine(sessions: sessions, overlay: overlay)
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == Self.standaloneBundleID else { return }
                self?.refresh()
            })
        }
    }

    static var standaloneRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: standaloneBundleID).isEmpty
    }

    private static func importStandaloneSettingsIfNeeded() {
        let defaults = UserDefaults.standard
        guard let previous = defaults.persistentDomain(forName: standaloneBundleID) else { return }
        importStandaloneSettings(previous, into: defaults)
    }

    static func importStandaloneSettings(_ previous: [String: Any], into defaults: UserDefaults) {
        if defaults.object(forKey: OverlayController.anchorDefaultsKey) == nil,
           let value = previous["labelAnchor"] as? String, LabelAnchor(rawValue: value) != nil {
            defaults.set(value, forKey: OverlayController.anchorDefaultsKey)
        }
        if defaults.object(forKey: OverlayController.orderDefaultsKey) == nil,
           let value = previous["labelOrder"] as? String, LabelOrder(rawValue: value) != nil {
            defaults.set(value, forKey: OverlayController.orderDefaultsKey)
        }
        if defaults.object(forKey: OverlayController.showAppIconDefaultsKey) == nil,
           let value = previous["showAppIcon"] as? Bool {
            defaults.set(value, forKey: OverlayController.showAppIconDefaultsKey)
        }
    }

    static func shouldRun(enabled: Bool, standaloneRunning: Bool) -> Bool {
        enabled && !standaloneRunning
    }

    func refresh() {
        let defaults = UserDefaults.standard
        overlay.anchor = LabelAnchor(rawValue: defaults.string(forKey: OverlayController.anchorDefaultsKey) ?? "") ?? .default
        overlay.order = LabelOrder(rawValue: defaults.string(forKey: OverlayController.orderDefaultsKey) ?? "") ?? .default
        overlay.showAppIcon = defaults.bool(forKey: OverlayController.showAppIconDefaultsKey)
        // Restart to immediately redraw an open Mission Control with new settings.
        engine.stop()
        let enabled = defaults.object(forKey: Self.enabledKey) == nil || defaults.bool(forKey: Self.enabledKey)
        // Avoid drawing a second set of labels while the old standalone app runs.
        if Self.shouldRun(enabled: enabled, standaloneRunning: Self.standaloneRunning) { engine.start() }
    }

    func stop() {
        engine.stop()
        overlay.tearDown()
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        workspaceObservers.removeAll()
    }
}
