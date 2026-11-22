import AppKit
import Combine
import Sparkle

private final class RiumUpdateDriver: SPUStandardUserDriver {
    private var installApproved = false

    override func showUpdateFound(with item: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        // The Settings button explicitly authorizes installation. Scheduled checks still ask.
        guard state.userInitiated, !item.isInformationOnlyUpdate, !item.isMajorUpgrade else {
            super.showUpdateFound(with: item, state: state, reply: reply)
            return
        }
        super.dismissUpdateInstallation()
        installApproved = true
        reply(.install)
    }

    override func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        if installApproved {
            reply(.install)
        } else {
            super.showReady(toInstallAndRelaunch: reply)
        }
    }

    override func dismissUpdateInstallation() {
        installApproved = false
        super.dismissUpdateInstallation()
    }
}

final class UpdateController: ObservableObject {
    @Published private(set) var canCheck = false
    @Published private(set) var autoCheck = true
    @Published private(set) var status = "새 버전이 있으면 설치하고 앱을 다시 엽니다."
    private var updater: SPUUpdater?

    func start() {
        guard updater == nil else { return }
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "SUEnableAutomaticChecks") == nil,
           let previous = defaults.object(forKey: "rium.update.autoCheck") as? Bool {
            defaults.set(previous, forKey: "SUEnableAutomaticChecks")
        }
        let bundle = Bundle.main
        let driver = RiumUpdateDriver(hostBundle: bundle, delegate: nil)
        let updater = SPUUpdater(hostBundle: bundle, applicationBundle: bundle, userDriver: driver, delegate: nil)
        do {
            try updater.start()
            self.updater = updater
            updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
            updater.publisher(for: \.automaticallyChecksForUpdates).assign(to: &$autoCheck)
        } catch {
            status = "업데이트를 시작할 수 없습니다."
            NSLog("Unable to start Sparkle: %@", error.localizedDescription)
        }
    }

    func check() {
        guard canCheck else { return }
        updater?.checkForUpdates()
    }

    func setAutoCheck(_ enabled: Bool) {
        updater?.automaticallyChecksForUpdates = enabled
    }
}
