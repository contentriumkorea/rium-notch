import Foundation
import Darwin
import AppKit
import CoreText
import SwiftUI

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

func memoryPressureFill(_ state: String) -> Double {
    switch state {
    case "주의": 0.5
    case "위험": 1
    default: 0
    }
}

// The one-minute run-queue average is scaled against the available processors.
func cpuPressureFill(load: Double, processors: Int) -> Double? {
    guard load.isFinite, load >= 0, processors > 0 else { return nil }
    let loadPerProcessor = load / Double(processors)
    return min(1, max(0, (loadPerProcessor - 0.5) * 2))
}

func currentCPUPressureFill() -> Double? {
    var load = 0.0
    guard getloadavg(&load, 1) == 1 else { return nil }
    return cpuPressureFill(load: load, processors: ProcessInfo.processInfo.activeProcessorCount)
}

struct CompactMonitorBadge: View {
    static let size: CGFloat = 18

    @ObservedObject var model: Model
    var diameter: CGFloat = CompactMonitorBadge.size
    var showsReadings = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let ramPressure = showsReadings ? memoryPressureFill(model.pressure) : 0
        let cpuPressure = showsReadings ? model.cpuPressureFill ?? 0 : 0
        let pressureTint = Color(red: 1, green: 0.26, blue: 0.29)
        let strokeWidth = diameter * 0.085
        let dotDiameter = diameter * 0.113
        let outerMargin = diameter * 0.01
        let stroke = StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
        let arcInset = outerMargin + strokeWidth / 2
        let center = diameter / 2
        let dotTrackRadius = center - outerMargin - dotDiameter / 2
        // Compensate for the round stroke cap so its visible gap matches the dot spacing.
        let arcStartDegrees = 147.68
        let arcFraction = (540 - 2 * arcStartDegrees) / 360
        let quotaText = (showsReadings ? model.monitorCodexRemaining : nil).map(String.init) ?? "—"
        ZStack {
            ZStack {
                Circle().trim(from: 0, to: arcFraction).stroke(.white, style: stroke)
                Circle().trim(from: 0, to: arcFraction * CGFloat(ramPressure)).stroke(pressureTint, style: stroke)
            }
            .rotationEffect(.degrees(arcStartDegrees))
            .padding(arcInset)
            Canvas { context, size in
                let fontSize = size.height * 0.38
                let standard = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold)
                let font = standard.fontDescriptor.withDesign(.rounded)
                    .flatMap { NSFont(descriptor: $0, size: fontSize) } ?? standard
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: quotaText, attributes: [
                    .font: font, .foregroundColor: NSColor.white
                ]))
                let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
                guard !ink.isEmpty else { return }
                let scale = min(1, size.width * 0.66 / ink.width)
                context.withCGContext { graphics in
                    graphics.translateBy(x: size.width / 2, y: size.height / 2)
                    graphics.scaleBy(x: scale, y: -scale)
                    graphics.textMatrix = .identity
                    graphics.textPosition = CGPoint(x: -ink.midX, y: -ink.midY)
                    CTLineDraw(line, graphics)
                }
            }
            ForEach(0..<4) { index in
                let angle = (126 - 24 * Double(index)) * .pi / 180
                let fill = min(1, max(0, cpuPressure * 4 - Double(index)))
                Circle().fill(.white)
                    .frame(width: dotDiameter, height: dotDiameter)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(pressureTint).frame(width: dotDiameter * fill)
                    }
                    .clipShape(Circle())
                    .position(x: center + dotTrackRadius * cos(angle), y: center + dotTrackRadius * sin(angle))
            }
        }
        .frame(width: diameter, height: diameter)
        .foregroundStyle(.white)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: cpuPressure)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: ramPressure)
        .accessibilityHidden(true)
    }
}
