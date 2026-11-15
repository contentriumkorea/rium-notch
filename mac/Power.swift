import Foundation
import IOKit.ps

final class PowerModel: ObservableObject {
    @Published var summary = "전원 확인 중"
    @Published var percentage: Int?
    @Published var charging = false
    private var timer: Timer?
    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.refresh() }
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
            self.percentage = percent; self.charging = charging
            self.summary = "배터리 \(percent)%" + (charging ? " · 충전 중" : (state == kIOPSACPowerValue ? " · 전원 연결" : ""))
            return
        }
        percentage = nil; charging = false; summary = "배터리 정보 없음"
    }
}
