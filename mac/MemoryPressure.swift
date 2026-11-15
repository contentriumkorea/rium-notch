import Foundation
import Darwin

/// The sysctl name is an undocumented, read-only macOS interface. Fail closed
/// when the OS does not expose it or returns an unknown pressure value.
func memoryPressureLabel(_ raw: UInt32) -> String? {
    switch UInt(raw) {
    case DispatchSource.MemoryPressureEvent.normal.rawValue: return "정상"
    case DispatchSource.MemoryPressureEvent.warning.rawValue: return "주의"
    case DispatchSource.MemoryPressureEvent.critical.rawValue: return "위험"
    default: return nil
    }
}

/// A previous sysctl reading is not evidence of the current pressure after a
/// later read failure. A dispatch event remains valid until the next event.
func resolvedMemoryPressure(current:String?,lastEvent:String?)->String {
    current ?? lastEvent ?? "조회 불가"
}

func currentMemoryPressure() -> String? {
    var value: UInt32 = 0
    var length = MemoryLayout<UInt32>.size
    guard sysctlbyname("kern.memorystatus_vm_pressure_level", &value, &length, nil, 0) == 0,
          length == MemoryLayout<UInt32>.size else { return nil }
    return memoryPressureLabel(value)
}
