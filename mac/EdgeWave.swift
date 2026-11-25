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

typealias ScreenWaveTint = (red: Double, green: Double, blue: Double)

enum ScreenWaveColorMode: String {
    case automatic
    case notch
    case custom

    func tint(for kind: NotchLightCue.Kind?, baseRGB: Int, customRGB: Int) -> ScreenWaveTint {
        switch self {
        case .automatic: edgeWaveTint(kind)
        case .notch: NotchLightColor.components(baseRGB)
        case .custom: NotchLightColor.components(customRGB)
        }
    }
}

struct ScreenWaveColors: DynamicProperty {
    @AppStorage("rium.light.waveColorMode") var mode = ScreenWaveColorMode.automatic
    @AppStorage("rium.light.waveColor") var customRGB = NotchLightColor.defaultRGB
    @AppStorage("rium.light.baseColor") private var baseRGB = NotchLightColor.defaultRGB

    func tint(for kind: NotchLightCue.Kind?) -> ScreenWaveTint {
        mode.tint(for: kind, baseRGB: baseRGB, customRGB: customRGB)
    }
}

func edgeWaveFallbackColor(_ color: ScreenWaveTint, opacity: Double, style: Float) -> Color {
    var values = [Double](repeating: 0, count: 4)
    let status = values.withUnsafeMutableBufferPointer {
        rustEdgeWaveFallbackColor(color.red, color.green, color.blue, opacity, Int32(style), $0.baseAddress)
    }
    guard status == 0 else { return Color(red: color.red, green: color.green, blue: color.blue).opacity(opacity) }
    return Color(red: values[0], green: values[1], blue: values[2]).opacity(values[3])
}

extension NotchLightCue.Kind {
    func supportsAgentScreenWave(style: String, waveStyle: String = "notch") -> Bool {
        waveStyle == "perimeter" || self == .agentDone || style != "classic"
    }

    var isClipboardScreenWave: Bool {
        switch self {
        case .clipboard, .clipboardPaste, .shortcut(.paste): return true
        default: return false
        }
    }
}

// shortcut: event colors other than completion still need reference comparison.
func edgeWaveTint(_ kind: NotchLightCue.Kind?) -> ScreenWaveTint {
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
    @AppStorage("rium.light.waveStyle") private var waveStyle = "notch"
    var body: some View {
        let usesPerimeter = waveStyle == "perimeter" || model.notchScreenWaves.contains { $0.previewStyle == "perimeter" }
        let interval = model.notchGeometryInMotion || usesPerimeter ? 1.0 / 60.0 : 1.0 / 30.0
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
    @AppStorage("rium.light.waveStyle") private var waveStyle = "notch"
    private var waveColors = ScreenWaveColors()
    @State private var metalIDs: Set<UUID> = []

    private func fallBackFromMetal(_ id: UUID) {
        metalIDs.remove(id)
    }

    var body: some View {
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let visibleWaves = model.notchScreenWaves.filter { wave in
            if wave.previewStyle != nil { return true }
            if lowPower { return false }
            if wave.kind.isClipboardScreenWave { return clipboardLight && enabled }
            return agentLight && agentScreenWave && wave.kind.supportsAgentScreenWave(style: lightStyle, waveStyle: waveStyle)
        }
        GeometryReader { geometry in
          let frame = island?.frame ?? CGRect(x: (geometry.size.width - notchWidth) / 2, y: 0,
                                              width: notchWidth, height: notchHeight)
          let origin = CGPoint(x: frame.midX, y: frame.maxY)
          ZStack {
            if lightEnabled && airDropLight && enabled && !reduceMotion {
              ForEach(model.edgeWaves) { cue in
                let tint = waveColors.tint(for: nil)
                Group {
                if waveStyle == "perimeter" {
                    DisplayPerimeterWave(started: cue.started, now: now, tint: tint,
                                         surfaceStyle: edgeWaveSurfaceStyle(light: model.menuBarIsLight, style: surfaceStyle))
                } else if metalIDs.contains(cue.id) {
                    EdgeWaveMetal(cue: cue, notchSize: frame.size, notchOrigin: origin, floatingRadius: island?.radius,
                                  surfaceStyle: edgeWaveSurfaceStyle(light: model.menuBarIsLight, style: surfaceStyle),
                                  tint: tint) { fallBackFromMetal(cue.id) }
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
                        let components = tint
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
                .opacity(waveStyle == "perimeter" ? 1 : notchLightFadeEnvelope(elapsed: now - cue.started,
                                                                                duration: cue.inward ? 2.6 : 3.0))
                .transition(.asymmetric(insertion: .identity, removal: .opacity))
              }
            }
            if lightEnabled && !reduceMotion {
                ForEach(visibleWaves) { wave in
                    let tint = waveColors.tint(for: wave.kind)
                    let usesPerimeter = (wave.previewStyle ?? waveStyle) == "perimeter"
                    Group {
                    // Keep simultaneous full-screen Metal surfaces bounded.
                    if usesPerimeter {
                        DisplayPerimeterWave(started: wave.started, now: now, tint: tint,
                                             surfaceStyle: edgeWaveSurfaceStyle(light: model.menuBarIsLight, style: surfaceStyle))
                    } else if metalIDs.contains(wave.id) {
                        EdgeWaveMetal(cue: EdgeWaveCue(id: wave.id, started: wave.started, inward: false, agentKind: wave.kind),
                                      notchSize: frame.size, notchOrigin: origin, floatingRadius: island?.radius,
                                      surfaceStyle: edgeWaveSurfaceStyle(light: model.menuBarIsLight, style: surfaceStyle),
                                      tint: tint) { fallBackFromMetal(wave.id) }
                    } else {
                        AgentScreenWaveFallback(wave: wave, notchFrame: frame, now: now, tint: tint,
                                                surfaceStyle: edgeWaveSurfaceStyle(light: model.menuBarIsLight, style: surfaceStyle))
                    }
                    }
                    .opacity(usesPerimeter ? 1 : notchLightFadeEnvelope(elapsed: now - wave.started, duration: 2.6))
                    .transition(.asymmetric(insertion: .identity, removal: .opacity))
                }
            }
          }
          .id(waveStyle)
          .transition(.opacity)
          .animation(notchLightFadeAnimation(reduceMotion), value: [lightEnabled, airDropLight, enabled, reduceMotion])
          .animation(notchLightFadeAnimation(reduceMotion), value: model.edgeWaves.map(\.id) + visibleWaves.map(\.id))
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
        .animation(notchLightFadeAnimation(reduceMotion), value: waveStyle)
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

private func perimeterWavePulses(offset: Double) -> [(start: Double, end: Double, weight: Double)] {
    offset >= 0 ? [(0.05, 0.25, 0.25), (0.27, 0.49, 0.40), (0.62, 0.86, 0.35)]
                : [(0.13, 0.34, 0.32), (0.40, 0.64, 0.35), (0.68, 0.90, 0.33)]
}

private func perimeterSmoothStep(_ value: Double) -> Double {
    let x = min(1, max(0, value))
    return x * x * x * (x * (x * 6 - 15) + 10)
}

// Each burst has zero acceleration at its endpoints, so changes of pace flow together.
func perimeterWaveProgress(elapsed: TimeInterval, offset: Double) -> Double {
    let phase = elapsed / 2.25
    guard phase < 1 else { return 1 + 0.22 * (phase - 1) }
    let bursts = perimeterWavePulses(offset: offset).reduce(0.0) { total, pulse in
        total + pulse.weight * perimeterSmoothStep((phase - pulse.start) / (pulse.end - pulse.start))
    }
    return 0.22 * phase + 0.78 * bursts
}

func perimeterWaveSpeed(elapsed: TimeInterval, offset: Double) -> Double {
    let phase = elapsed / 2.25
    guard phase < 1 else { return 0.22 }
    return 0.22 + 0.78 * perimeterWavePulses(offset: offset).reduce(0.0) { total, pulse in
        let x = min(1, max(0, (phase - pulse.start) / (pulse.end - pulse.start)))
        return total + pulse.weight * 30 * x * x * (1 - x) * (1 - x) / (pulse.end - pulse.start)
    }
}

func perimeterWaveRange(elapsed: TimeInterval, offset: Double = 0.9) -> ClosedRange<CGFloat>? {
    guard elapsed.isFinite, elapsed >= 0, elapsed < 2.6 else { return nil }
    let head = CGFloat(perimeterWaveProgress(elapsed: elapsed, offset: offset))
    let start = max(0, head - 0.15), end = min(1, head)
    return start < end ? start...end : nil
}

func perimeterWavePath(size: CGSize) -> Path {
    guard size.width > 8, size.height > 8 else { return Path() }
    let inset: CGFloat = 2
    let left = inset, right = size.width - inset, top = inset, bottom = size.height - inset
    let radius = min(20, (right - left) / 4, (bottom - top) / 4)
    var path = Path()
    path.move(to: CGPoint(x: size.width / 2, y: top))
    path.addLine(to: CGPoint(x: right - radius, y: top))
    path.addQuadCurve(to: CGPoint(x: right, y: top + radius), control: CGPoint(x: right, y: top))
    path.addLine(to: CGPoint(x: right, y: bottom - radius))
    path.addQuadCurve(to: CGPoint(x: right - radius, y: bottom), control: CGPoint(x: right, y: bottom))
    path.addLine(to: CGPoint(x: left + radius, y: bottom))
    path.addQuadCurve(to: CGPoint(x: left, y: bottom - radius), control: CGPoint(x: left, y: bottom))
    path.addLine(to: CGPoint(x: left, y: top + radius))
    path.addQuadCurve(to: CGPoint(x: left + radius, y: top), control: CGPoint(x: left, y: top))
    path.addLine(to: CGPoint(x: size.width / 2, y: top))
    return path
}

struct DisplayPerimeterWave: View {
    let started: TimeInterval
    let now: TimeInterval
    let tint: ScreenWaveTint
    let surfaceStyle: Float

    var body: some View {
        Canvas { context, size in
            let elapsed = now - started
            guard elapsed.isFinite, elapsed >= 0, elapsed < 2.6, size.width > 8, size.height > 8 else { return }
            let path = perimeterWavePath(size: size)
            let fade = notchLightFadeEnvelope(elapsed: elapsed, duration: 2.6, attack: 0.15, release: 0.25)
            let offset = 0.9
            if let range = perimeterWaveRange(elapsed: elapsed, offset: offset) {
                let speed = perimeterWaveSpeed(elapsed: elapsed, offset: offset)
                let burst = perimeterSmoothStep((speed - 0.3) / 2.5)
                let pulse = 0.72 + 0.28 * burst
                let pieces: [(Path, Double)] = (0..<40).map { index in
                    let start = range.lowerBound + (range.upperBound - range.lowerBound) * CGFloat(index) / 40
                    let end = range.lowerBound + (range.upperBound - range.lowerBound) * CGFloat(index + 1) / 40
                    let position = (Double(index) + 0.5) / 40
                    let brightness = pow(sin(.pi * pow(position, 0.8)), 1.5)
                    return (path.trimmedPath(from: start, to: end), brightness)
                }
                for (width, blur, opacity) in [(30.0, 18.0, 0.20), (12.0, 8.0, 0.26), (3.0, 3.0, 0.30)] {
                    var light = context
                    light.addFilter(.blur(radius: blur))
                    light.drawLayer { layer in
                        for (segment, brightness) in pieces {
                            layer.stroke(segment, with: .color(edgeWaveFallbackColor(tint, opacity: opacity * fade * pulse * brightness, style: surfaceStyle)),
                                         style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
                        }
                    }
                }
            }
        }
    }
}

struct AgentScreenWaveFallback: View {
    let wave: NotchScreenWave
    let notchFrame: CGRect
    let now: TimeInterval
    let tint: ScreenWaveTint
    let surfaceStyle: Float
    var body: some View {
        Canvas { context, size in
            let elapsed = now - wave.started
            guard elapsed >= 0, size.width > 0 else { return }
            var frame = [Double](repeating: 0, count: 2)
            guard frame.withUnsafeMutableBufferPointer({ rustAgentScreenWave(elapsed, $0.baseAddress) }) == 0,
                  frame[0] > 0, frame[1] > 0 else { return }
            let components = tint
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
