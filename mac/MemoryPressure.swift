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

// macOS reports thermal state for the whole system, not just the CPU.
func thermalPressureFill(_ state: ProcessInfo.ThermalState?) -> Double? {
    guard let state else { return nil }
    switch state {
    case .nominal: return 0
    case .fair: return 0.3
    case .serious: return 0.65
    case .critical: return 1
    @unknown default: return nil
    }
}

func thermalPressureLabel(_ state: ProcessInfo.ThermalState?) -> String {
    guard let state else { return "확인 중" }
    switch state {
    case .nominal: return "정상"
    case .fair: return "약간 높음"
    case .serious: return "높음"
    case .critical: return "위험"
    @unknown default: return "조회 불가"
    }
}

private struct MonitorPressureGradient: View, Animatable {
    struct Arc {
        let fraction: Double
        let lineWidth: CGFloat
    }

    var pressure: Double
    var arc: Arc? = nil

    var animatableData: Double {
        get { pressure }
        set { pressure = newValue }
    }

    private func tint(at position: Double, strength: Double) -> Color {
        // Cream orange (#FFDC9C), vivid orange (#FF8100), and red (#FF1230).
        let orangeBlend = min(1, position * 2)
        let redBlend = max(0, position * 2 - 1)
        let green = (220 - 91 * orangeBlend - 111 * redBlend) / 255
        let blue = (156 - 156 * orangeBlend + 48 * redBlend) / 255
        return Color(red: 1,
                     green: 1 - (1 - green) * strength,
                     blue: 1 - (1 - blue) * strength)
    }

    var body: some View {
        let amount = min(1, max(0, pressure))
        let sweep = arc?.fraction ?? 1
        let strength = min(1, amount * 10)
        let first = tint(at: 0, strength: strength)
        let last: Color = amount == 1 ? tint(at: 1, strength: 1) : .white
        let fadeWidth = min(0.18, amount * 0.8, (1 - amount) * 2)
        let solid = amount - fadeWidth
        let fadeMidpoint = solid + fadeWidth * 0.55
        let orangePoint = min(0.5, solid)
        let baseStops: [Gradient.Stop] = [
            .init(color: first, location: 0),
            .init(color: tint(at: orangePoint, strength: strength), location: orangePoint * sweep)
        ]
        let fadeStops: [Gradient.Stop] = amount < 1 ? [
            .init(color: tint(at: solid, strength: strength), location: solid * sweep),
            .init(color: tint(at: fadeMidpoint, strength: strength * 0.45), location: fadeMidpoint * sweep),
            .init(color: last, location: amount * sweep)
        ] : []
        let stops = baseStops + fadeStops + [.init(color: last, location: sweep)]

        if let arc {
            // Extend each endpoint color around its round cap.
            let colors = AngularGradient(stops: stops + [
                .init(color: last, location: sweep + 0.04),
                .init(color: first, location: 0.96),
                .init(color: first, location: 1)
            ], center: .center)
            Circle().trim(from: 0, to: arc.fraction)
                .stroke(colors, style: StrokeStyle(lineWidth: arc.lineWidth, lineCap: .round))
        } else {
            LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
        }
    }
}

struct CompactMonitorBadge: View {
    static let size: CGFloat = 18

    @ObservedObject var model: Model
    var diameter: CGFloat = CompactMonitorBadge.size
    var showsReadings = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let ramPressure = showsReadings ? memoryPressureFill(model.pressure) : 0
        let thermalPressure = showsReadings ? thermalPressureFill(model.systemThermalState) ?? 0 : 0
        let strokeWidth = diameter * 0.085
        let dotDiameter = diameter * 0.113
        let outerMargin = diameter * 0.01
        let arcInset = outerMargin + strokeWidth / 2
        let center = diameter / 2
        let dotTrackRadius = center - outerMargin - dotDiameter / 2
        let dotSpan = 2 * dotTrackRadius * cos(54 * .pi / 180) + dotDiameter
        // Compensate for the round stroke cap so its visible gap matches the dot spacing.
        let arcStartDegrees = 147.68
        let arcFraction = (540 - 2 * arcStartDegrees) / 360
        let quotaText = (showsReadings ? model.monitorCodexRemaining : nil).map(String.init) ?? "—"
        ZStack {
            MonitorPressureGradient(pressure: ramPressure,
                                    arc: .init(fraction: arcFraction, lineWidth: strokeWidth))
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
            MonitorPressureGradient(pressure: thermalPressure)
                .frame(width: dotSpan, height: diameter)
                .frame(width: diameter, height: diameter)
                .mask {
                    ZStack {
                        ForEach(0..<4) { index in
                            let angle = (126 - 24 * Double(index)) * .pi / 180
                            Circle().fill(.white)
                                .frame(width: dotDiameter, height: dotDiameter)
                                .position(x: center + dotTrackRadius * cos(angle), y: center + dotTrackRadius * sin(angle))
                        }
                    }
                }
        }
        .frame(width: diameter, height: diameter)
        .foregroundStyle(.white)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: thermalPressure)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: ramPressure)
        .accessibilityHidden(true)
    }
}
