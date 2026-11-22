import Foundation
import IOKit.ps
import Darwin
import notify

@_silgen_name("rium_power_feedback_update")
private func rustPowerFeedbackUpdate(_ seen: UnsafeMutablePointer<UInt8>, _ previousSource: Int32,
                                     _ source: Int32, _ warning: Int32) -> Int32
@_silgen_name("rium_battery_feedback_seconds")
private func rustBatteryFeedbackSeconds(_ critical: Int32) -> Double

func batteryFeedbackDuration(critical: Bool?) -> TimeInterval {
    rustBatteryFeedbackSeconds(critical.map { $0 ? 1 : 0 } ?? -1)
}

final class PowerModel: ObservableObject {
    enum Event { case source(percent: Int, external: Bool), warning(percent: Int, critical: Bool) }
    var onEvent: ((Event) -> Void)?
    @Published var summary = "전원 확인 중"
    @Published var percentage: Int?
    @Published var charging = false
    @Published private(set) var externalPower: Bool?
    private var seenWarnings: UInt8 = 0
    private var notificationTokens: [Int32] = []
    private var timer: Timer?
    init(observeSystem: Bool = true) {
        guard observeSystem else { return }
        refresh()
        for name in ["com.apple.system.powersources.source", "com.apple.system.powersources.lowbattery"] {
            var token: Int32 = 0
            if notify_register_dispatch(name, &token, .main, { [weak self] _ in self?.refresh() }) == 0 { notificationTokens.append(token) }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.refresh() }
    }
    deinit {
        timer?.invalidate()
        for token in notificationTokens { notify_cancel(token) }
    }
    func refresh() {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let list = IOPSCopyPowerSourcesList(info).takeRetainedValue() as NSArray
        for source in list {
            guard let raw = IOPSGetPowerSourceDescription(info, source as CFTypeRef)?.takeUnretainedValue(),
                  let details = raw as NSDictionary?, let current = details[kIOPSCurrentCapacityKey] as? Int,
                  let max = details[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let percent = Swift.max(0, Swift.min(100, Int((Double(current) / Double(max) * 100).rounded())))
            let charging = details[kIOPSIsChargingKey] as? Bool ?? false
            let state = details[kIOPSPowerSourceStateKey] as? String ?? ""
            let source: Bool? = state == kIOPSACPowerValue ? true : (state == kIOPSBatteryPowerValue ? false : nil)
            let systemWarning = IOPSGetBatteryWarningLevel()
            let warning: Int32 = systemWarning == kIOPSLowBatteryWarningFinal ? 2 : (systemWarning == kIOPSLowBatteryWarningEarly ? 1 : 0)
            record(percent: percent, charging: charging, external: source, warning: warning)
            return
        }
        percentage = nil; charging = false; externalPower = nil; summary = "배터리 정보 없음"
    }

    func record(percent: Int, charging: Bool, external: Bool?, warning: Int32) {
        let event = rustPowerFeedbackUpdate(&seenWarnings, externalPower.map { $0 ? 1 : 0 } ?? -1,
                                            external.map { $0 ? 1 : 0 } ?? -1, warning)
        percentage = percent
        self.charging = charging
        externalPower = external
        summary = "배터리 \(percent)%" + (charging ? " · 충전 중" : (external == true ? " · 전원 연결" : ""))
        switch event {
        case 1:
            if let external { onEvent?(.source(percent: percent, external: external)) }
        case 2, 3:
            onEvent?(.warning(percent: percent, critical: event == 3))
        default: break
        }
    }
}
