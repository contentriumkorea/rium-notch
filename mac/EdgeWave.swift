import AppKit
import SwiftUI

@_silgen_name("rium_notch_edge_wave")
private func rustEdgeWave(_ elapsed: Double, _ inward: Int32, _ output: UnsafeMutablePointer<Double>?) -> Int32
@_silgen_name("rium_notch_edge_wave_detail")
private func rustEdgeWaveDetail(_ angle: Double, _ time: Double, _ radius: Double, _ output: UnsafeMutablePointer<Double>?) -> Int32
@_silgen_name("rium_agent_screen_wave")
private func rustAgentScreenWave(_ elapsed: Double, _ output: UnsafeMutablePointer<Double>?) -> Int32
@_silgen_name("rium_edge_wave_fallback_color")
private func rustEdgeWaveFallbackColor(_ r: Double, _ g: Double, _ b: Double, _ opacity: Double, _ style: Int32, _ output: UnsafeMutablePointer<Double>?) -> Int32

func edgeWaveSurfaceStyle(light: Bool, style: String) -> Float {
    light ? (style == "velours" ? 2 : 1) : 0
}

func edgeWaveFallbackColor(_ color: (red: Double, green: Double, blue: Double), opacity: Double, style: Float) -> Color {
    var values = [Double](repeating: 0, count: 4)
    let status = values.withUnsafeMutableBufferPointer {
        rustEdgeWaveFallbackColor(color.red, color.green, color.blue, opacity, Int32(style), $0.baseAddress)
    }
    guard status == 0 else { return Color(red: color.red, green: color.green, blue: color.blue).opacity(opacity) }
    return Color(red: values[0], green: values[1], blue: values[2]).opacity(values[3])
}

extension NotchLightCue.Kind {
    func supportsAgentScreenWave(style: String) -> Bool {
        self == .agentDone || style != "classic"
    }

    var isClipboardScreenWave: Bool {
        switch self {
        case .clipboard, .clipboardPaste, .shortcut(.paste): return true
        default: return false
        }
    }
}

// shortcut: event colors other than completion still need reference comparison.
func edgeWaveTint(_ kind: NotchLightCue.Kind?) -> (red: Double, green: Double, blue: Double) {
    switch kind {
    case .agentApproval?, .agentQuestion?: return (1.0, 0.58, 0.18)
    case .clipboard?: return (0.63, 0.72, 0.95)
    case .clipboardPaste?, .shortcut(.paste)?: return (0.70, 0.61, 0.91)
    case .agentDone?: return (0.20, 0.82, 0.48)
    case .agentFailed?: return (1.0, 0.28, 0.24)
    case .agentInterrupted?: return (0.58, 0.6, 0.65)
    case nil: return (0.38, 0.70, 1.0)
    default: return (0.55, 0.73, 1.0)
    }
}

func agentMetalWaveIDs(previous: Set<UUID>, selected: Set<UUID>, current: [UUID], available: Bool) -> Set<UUID> {
    guard available else { return [] }
    var result = selected.intersection(current)
    for id in current where !previous.contains(id) && result.count < 3 { result.insert(id) }
    return result
}

extension Model {
    var screenWaveIsland: FloatingIslandRenderedGeometry? {
        if let rendered = currentRenderedFloatingIslandGeometry { return rendered }
        guard let target = floatingIslandGeometry, let frame = target.frame(in: target.bounds.screen) else { return nil }
        return FloatingIslandRenderedGeometry(frame: frame, surface: target.bounds.screen, radius: target.radius)
    }
}

/// A click-through full-display wave with a fallback when Metal is unavailable.
struct FullScreenEdgeWave: View {
    @ObservedObject var model: Model
    var body: some View {
        let interval = model.notchGeometryInMotion ? 1.0 / 60.0 : 1.0 / 30.0
        TimelineView(.animation(minimumInterval: interval,
                                paused: model.edgeWaves.isEmpty && model.notchScreenWaves.isEmpty)) { _ in
            let outline = model.renderedNotchOutlineSize ?? model.currentNotchOutlineSize
            let corners = model.renderedNotchCorners ?? model.currentNotchCorners
            AnimatedFullScreenEdgeWave(model: model, notchWidth: outline.width, notchHeight: outline.height,
                                       corners: corners, island: model.screenWaveIsland, now: ProcessInfo.processInfo.systemUptime)
        }
    }
}

/// Uses the notch backdrop's rendered dimensions for both origin and mask.
private struct AnimatedFullScreenEdgeWave: View {
    @ObservedObject var model: Model
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var corners: NotchCorners
    let island: FloatingIslandRenderedGeometry?
    let now: TimeInterval
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("rium.light.enabled") private var lightEnabled = true
    @AppStorage("rium.light.airdrop") private var airDropLight = true
    @AppStorage("rium.light.edgeWave") private var enabled = true
    @AppStorage("rium.light.clipboard") private var clipboardLight = true
    @AppStorage("rium.light.agent") private var agentLight = true
    @AppStorage("rium.light.agentScreenWave") private var agentScreenWave = true
    @AppStorage("rium.light.style") private var lightStyle = "classic"
    @AppStorage("rium.light.surfaceStyle") private var surfaceStyle = "neon"
    @State private var metalIDs: Set<UUID> = []

    private func fallBackFromMetal(_ id: UUID) {
        metalIDs.remove(id)
    }

    var body: some View {
        let visibleWaves = model.notchScreenWaves.filter { wave in
            wave.kind.isClipboardScreenWave ? clipboardLight && enabled : agentLight && agentScreenWave && wave.kind.supportsAgentScreenWave(style: lightStyle)
        }
        GeometryReader { geometry in
          let frame = island?.frame ?? CGRect(x: (geometry.size.width - notchWidth) / 2, y: 0,
                                              width: notchWidth, height: notchHeight)
          let origin = CGPoint(x: frame.midX, y: frame.maxY)
          ZStack {
            if lightEnabled && airDropLight && enabled && !reduceMotion {
              ForEach(model.edgeWaves) { cue in
                if metalIDs.contains(cue.id) {
                    EdgeWaveMetal(cue: cue, notchSize: frame.size, notchOrigin: origin, floatingRadius: island?.radius,
                                  surfaceStyle: edgeWaveSurfaceStyle(light: model.menuBarIsLight, style: surfaceStyle)) { fallBackFromMetal(cue.id) }
                } else {
                    let elapsed = max(0, now - cue.started)
                    let parameters: [Double] = {
                        var values = [Double](repeating: 0, count: 2)
                        let result = values.withUnsafeMutableBufferPointer { rustEdgeWave(elapsed, cue.inward ? 1 : 0, $0.baseAddress) }
                        return result == 0 ? values : [0, 0]
                    }()
                    Canvas { context, size in
                        let radius = CGFloat(parameters[0]) * size.width
                        let fade = max(0, min(1, parameters[1]))
                        guard radius > 1, fade > 0, size.width > 0 else { return }
                        let halfLip = frame.width * 0.36
                        let components = edgeWaveTint(nil)
                        let style = edgeWaveSurfaceStyle(light: model.menuBarIsLight, style: surfaceStyle)
                        let time = cue.inward ? max(0, 2 - elapsed) : max(0, elapsed - 0.4)
                        var bands = [Path](repeating: Path(), count: 8)
                        var innerBands = [Path](repeating: Path(), count: 8)
                        let count = 72
                        let samples: [(angle: Double, detail: [Double])] = (0...count).map { index in
                            let angle = -Double.pi / 2 + Double(index) * Double.pi / Double(count)
                            var detail = [Double](repeating: 0, count: 3)
                            if detail.withUnsafeMutableBufferPointer({ rustEdgeWaveDetail(angle, time, parameters[0], $0.baseAddress) }) != 0 {
                                detail = [0, 0, 0]
                            }
                            return (angle, detail)
                        }
                        for index in 0..<count {
                            let start = samples[index], end = samples[index + 1]
                            let offset = index < count / 2 ? -halfLip : halfLip
                            func point(_ sample: (angle: Double, detail: [Double])) -> CGPoint {
                                let displacedRadius = radius * CGFloat(1 + sample.detail[0])
                                return CGPoint(x: origin.x + offset + displacedRadius * CGFloat(sin(sample.angle)),
                                               y: origin.y + displacedRadius * CGFloat(cos(sample.angle)))
                            }
                            let startStrength = start.detail[1] * (0.35 + start.detail[2])
                            let endStrength = end.detail[1] * (0.35 + end.detail[2])
                            let strength = min(1, max(0, (startStrength + endStrength) / 2))
                            let band = min(7, Int(strength * 8))
                            bands[band].move(to: point(start)); bands[band].addLine(to: point(end))
                            if parameters[0] > 0.12 {
                                func innerPoint(_ sample: (angle: Double, detail: [Double])) -> CGPoint {
                                    let innerRadius = (radius - size.width * 0.12) * CGFloat(1 + sample.detail[0])
                                    return CGPoint(x: origin.x + offset + innerRadius * CGFloat(sin(sample.angle)),
                                                   y: origin.y + innerRadius * CGFloat(cos(sample.angle)))
                                }
                                innerBands[band].move(to: innerPoint(start)); innerBands[band].addLine(to: innerPoint(end))
                            }
                            if index == count / 2 {
                                let displacedRadius = radius * CGFloat(1 + start.detail[0])
                                bands[band].move(to: CGPoint(x: origin.x - halfLip, y: origin.y + displacedRadius))
                                bands[band].addLine(to: CGPoint(x: origin.x + halfLip, y: origin.y + displacedRadius))
                                if parameters[0] > 0.12 {
                                    let innerRadius = (radius - size.width * 0.12) * CGFloat(1 + start.detail[0])
                                    innerBands[band].move(to: CGPoint(x: origin.x - halfLip, y: origin.y + innerRadius))
                                    innerBands[band].addLine(to: CGPoint(x: origin.x + halfLip, y: origin.y + innerRadius))
                                }
                            }
                        }
                        // shortcut: segmented strokes approximate the shader's distance field, wash, and additive blending until visual comparison.
                        var soft = context; soft.addFilter(.blur(radius: 12))
                        var inner = context; inner.addFilter(.blur(radius: 12))
                        let energy = 1 / (1 + parameters[0] * 1.4)
                        for (index, path) in bands.enumerated() where index > 0 {
                            let strength = Double(index + 1) / Double(bands.count) * fade * energy
                            soft.stroke(path, with: .color(edgeWaveFallbackColor(components, opacity: 0.08 * strength, style: style)),
                                        style: StrokeStyle(lineWidth: max(12, size.width * 0.045), lineCap: .round))
                            context.stroke(path, with: .color(edgeWaveFallbackColor(components, opacity: 0.45 * strength, style: style)),
                                           style: StrokeStyle(lineWidth: max(1.5, size.width * 0.0035), lineCap: .round))
                            // shortcut: a blurred stroke approximates the reference's inner distance-field lobe.
                            inner.stroke(innerBands[index], with: .color(edgeWaveFallbackColor(components, opacity: 0.07 * strength, style: style)),
                                         style: StrokeStyle(lineWidth: max(4, size.width * 0.035), lineCap: .round))
                        }
                    }
                }
              }
            }
            if lightEnabled && !reduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled {
                ForEach(visibleWaves) { wave in
                    // Keep simultaneous full-screen Metal surfaces bounded.
                    if metalIDs.contains(wave.id) {
                        EdgeWaveMetal(cue: EdgeWaveCue(id: wave.id, started: wave.started, inward: false, agentKind: wave.kind),
                                      notchSize: frame.size, notchOrigin: origin, floatingRadius: island?.radius,
                                      surfaceStyle: edgeWaveSurfaceStyle(light: model.menuBarIsLight, style: surfaceStyle)) { fallBackFromMetal(wave.id) }
                    } else {
                        AgentScreenWaveFallback(wave: wave, notchFrame: frame, now: now,
                                                surfaceStyle: edgeWaveSurfaceStyle(light: model.menuBarIsLight, style: surfaceStyle))
                    }
                }
            }
          }
          // Mask the composited waves once so overlapping effects share the same silhouette.
          .mask {
              Group {
                  if let island {
                      FloatingIslandOutsideMask(frame: frame, radius: island.radius, edgeOnly: false)
                          .fill(style: FillStyle(eoFill: true))
                  } else {
                      OutsideNotchMask(notchWidth: notchWidth, notchHeight: notchHeight, corners: corners)
                          .fill(style: FillStyle(eoFill: true))
                  }
              }.transaction { $0.animation = nil }
          }
          .mask {
              Group {
                  if let island {
                      FloatingIslandOutsideMask(frame: frame, radius: island.radius, edgeOnly: true)
                          .fill(style: FillStyle(eoFill: true))
                  } else {
                      OutsideNotchEdgeMask(notchWidth: notchWidth, notchHeight: notchHeight, corners: corners)
                          .fill(style: FillStyle(eoFill: true))
                  }
              }.transaction { $0.animation = nil }
          }
          .modifier(PhysicalNotchExclusion(width: model.cameraExclusion, height: model.cameraHeight))
        }
        .onAppear {
            let current = model.edgeWaves.map(\.id) + model.notchScreenWaves.map(\.id)
            metalIDs = agentMetalWaveIDs(previous: [], selected: [], current: current, available: EdgeWaveMetal.available)
        }
        .onChange(of: model.edgeWaves.map(\.id) + model.notchScreenWaves.map(\.id)) { previous, current in
            metalIDs = agentMetalWaveIDs(previous: Set(previous), selected: metalIDs, current: current,
                                        available: EdgeWaveMetal.available)
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct AgentScreenWaveFallback: View {
    let wave: NotchScreenWave
    let notchFrame: CGRect
    let now: TimeInterval
    let surfaceStyle: Float
    var body: some View {
        Canvas { context, size in
            let elapsed = now - wave.started
            guard elapsed >= 0, size.width > 0 else { return }
            var frame = [Double](repeating: 0, count: 2)
            guard frame.withUnsafeMutableBufferPointer({ rustAgentScreenWave(elapsed, $0.baseAddress) }) == 0,
                  frame[0] > 0, frame[1] > 0 else { return }
            let components = edgeWaveTint(wave.kind)
            let radius = CGFloat(frame[0]) * size.width
            let halfLip = notchFrame.width * 0.36
            let count = 72
            var bands = [Path](repeating: Path(), count: 8)
            var innerBands = [Path](repeating: Path(), count: 8)
            let samples: [(angle: Double, detail: [Double])] = (0...count).map { index in
                let angle = -Double.pi / 2 + Double(index) * Double.pi / Double(count)
                var detail = [Double](repeating: 0, count: 3)
                _ = detail.withUnsafeMutableBufferPointer { rustEdgeWaveDetail(angle, elapsed, frame[0], $0.baseAddress) }
                return (angle, detail)
            }
            for index in 0..<count {
                let start = samples[index], end = samples[index + 1]
                let side = index < count / 2 ? -halfLip : halfLip
                func point(_ sample: (angle: Double, detail: [Double])) -> CGPoint {
                    let displaced = radius * CGFloat(1 + sample.detail[0])
                    return CGPoint(x: notchFrame.midX + side + displaced * CGFloat(sin(sample.angle)),
                                   y: notchFrame.maxY + displaced * CGFloat(cos(sample.angle)))
                }
                let startStrength = start.detail[1] * (0.35 + start.detail[2])
                let endStrength = end.detail[1] * (0.35 + end.detail[2])
                let strength = min(1, max(0, (startStrength + endStrength) / 2))
                let band = min(7, Int(strength * 8))
                bands[band].move(to: point(start))
                bands[band].addLine(to: point(end))
                if frame[0] > 0.12 {
                    func innerPoint(_ sample: (angle: Double, detail: [Double])) -> CGPoint {
                        let innerRadius = (radius - size.width * 0.12) * CGFloat(1 + sample.detail[0])
                        return CGPoint(x: notchFrame.midX + side + innerRadius * CGFloat(sin(sample.angle)),
                                       y: notchFrame.maxY + innerRadius * CGFloat(cos(sample.angle)))
                    }
                    innerBands[band].move(to: innerPoint(start)); innerBands[band].addLine(to: innerPoint(end))
                }
                if index == count / 2 {
                    let displaced = radius * CGFloat(1 + start.detail[0])
                    bands[band].move(to: CGPoint(x: notchFrame.midX - halfLip, y: notchFrame.maxY + displaced))
                    bands[band].addLine(to: CGPoint(x: notchFrame.midX + halfLip, y: notchFrame.maxY + displaced))
                    if frame[0] > 0.12 {
                        let innerRadius = (radius - size.width * 0.12) * CGFloat(1 + start.detail[0])
                        innerBands[band].move(to: CGPoint(x: notchFrame.midX - halfLip, y: notchFrame.maxY + innerRadius))
                        innerBands[band].addLine(to: CGPoint(x: notchFrame.midX + halfLip, y: notchFrame.maxY + innerRadius))
                    }
                }
            }
            // shortcut: segmented strokes approximate the GPU's wash and blending.
            var glow = context; glow.addFilter(.blur(radius: 12))
            var inner = context; inner.addFilter(.blur(radius: 12))
            let energy = frame[1] / (1 + frame[0] * 1.4)
            for (index, path) in bands.enumerated() where index > 0 {
                let strength = Double(index + 1) / Double(bands.count) * energy
                glow.stroke(path, with: .color(edgeWaveFallbackColor(components, opacity: 0.08 * strength, style: surfaceStyle)), lineWidth: max(12, size.width * 0.045))
                context.stroke(path, with: .color(edgeWaveFallbackColor(components, opacity: 0.45 * strength, style: surfaceStyle)), lineWidth: max(1.5, size.width * 0.0035))
                // shortcut: a blurred stroke approximates the reference's inner distance-field lobe.
                inner.stroke(innerBands[index], with: .color(edgeWaveFallbackColor(components, opacity: 0.07 * strength, style: surfaceStyle)), lineWidth: max(4, size.width * 0.035))
            }
        }
    }
}
