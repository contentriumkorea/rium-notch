import SwiftUI
import AppKit

let defaultMusicLightColor = NSColor(calibratedRed: 0.55, green: 0.73, blue: 1, alpha: 1)

// Read only a small, evenly spaced sample when the artwork changes. No image
// content or extracted color is written to disk.
func artworkLightColor(_ data: Data) -> NSColor? {
    guard let bitmap = NSBitmapImageRep(data: data), bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0 else { return nil }
    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, total: CGFloat = 0
    for y in 0..<10 {
        for x in 0..<10 {
            let px = min(bitmap.pixelsWide - 1, (2 * x + 1) * bitmap.pixelsWide / 20)
            let py = min(bitmap.pixelsHigh - 1, (2 * y + 1) * bitmap.pixelsHigh / 20)
            guard let color = bitmap.colorAt(x: px, y: py)?.usingColorSpace(.sRGB), color.alphaComponent > 0.2 else { continue }
            let r = color.redComponent, g = color.greenComponent, b = color.blueComponent
            let brightness = max(r, g, b), saturation = brightness > 0 ? (brightness - min(r, g, b)) / brightness : 0
            let weight = color.alphaComponent * max(0.08, brightness) * (0.35 + saturation)
            red += r * weight; green += g * weight; blue += b * weight; total += weight
        }
    }
    guard total > 0 else { return nil }
    let r = red / total, g = green / total, b = blue / total
    let maxComponent = max(r, g, b)
    guard maxComponent > 0.03 else { return nil }
    let lift = min(1.6, 0.9 / maxComponent)
    return NSColor(srgbRed: min(1, r * lift), green: min(1, g * lift), blue: min(1, b * lift), alpha: 1)
}

enum AmbientLightMode: Equatable { case off, agent, music }
func ambientLightMode(expanded: Bool, agentActive: Bool, musicPlaying: Bool, eventActive: Bool = false) -> AmbientLightMode {
    if expanded || eventActive { return .off }
    if agentActive { return .agent }
    return musicPlaying ? .music : .off
}
func musicRipplePhase(time: TimeInterval, offset: Double) -> Double {
    let raw = time / 2.7 + offset
    return raw - floor(raw)
}
// The original MusicWaveGlow crest clamps its peak and uses a 0.13-wide
// fade on either side. Keep the gradient stops ordered at the screen edges.
func musicCrestPositions(_ center: Double) -> (left: Double, peak: Double, right: Double) {
    let peak = min(0.99, max(0.01, center))
    return (max(0, peak - 0.13), peak, min(1, peak + 0.13))
}
// MusicWaveGlow lightens each RGB component toward white by 28% at its crest.
func musicCrestColor(_ tint: NSColor) -> NSColor {
    guard let color = tint.usingColorSpace(.sRGB) else { return tint }
    func lift(_ component: CGFloat) -> CGFloat { component + (1 - component) * 0.28 }
    return NSColor(srgbRed: lift(color.redComponent), green: lift(color.greenComponent), blue: lift(color.blueComponent), alpha: color.alphaComponent)
}
// MusicWaveGlow.glowWidth adds the shoulder radius (5), glow outset (1)
// and a width-dependent fade to each side of the notch and arm.
func musicGlowWidth(notch: CGFloat, arm: CGFloat, screen: CGFloat) -> CGFloat {
    guard notch.isFinite, arm.isFinite, screen.isFinite, notch >= 0, arm >= 0, screen > 0 else { return 0 }
    let ratio = arm / 220
    let fade: CGFloat = ratio < 0.65 ? 46.8 : (ratio < 1.45 ? max(22, ratio * 72) : 104.4)
    return min(screen, notch + 2 * (arm + 5 + 1 + fade))
}
// Glance's AmbientContour.armRun uses 76, 130, 220 and 440 points for
// narrow, medium, default and extra-large at unit scale. Its screen-dependent
// scale is not yet recovered; bound our unit-scale result to the screen.
func ambientArmRun(preset: String, screenWidth: CGFloat, notch: CGFloat? = nil) -> CGFloat {
    guard screenWidth.isFinite, screenWidth > 0 else { return 0 }
    let requested: CGFloat
    switch preset {
    case "narrow": requested = 76
    case "medium": requested = 130
    case "extraLarge": requested = 440
    default: requested = 220
    }
    return min(requested, max(0, (screenWidth - (notch ?? notchWidth(expanded: false, displayWidth: screenWidth))) / 2))
}

// An event is intentionally short-lived: idle lighting should not keep a
// 30-fps animation running indefinitely.
struct NotchLightCue: Identifiable {
    enum Kind { case airDrop, clipboard, shelf, systemControl, agentRunning, agentApproval, agentDone }
    let id = UUID()
    let kind: Kind
    let started: Date
    var duration: TimeInterval {
        switch kind {
        case .agentRunning, .agentApproval: return 0.82
        case .agentDone: return 0.72
        case .clipboard: return 2.4
        default: return 2.0
        }
    }
}

struct AgentArrivalSegment {
    let start: CGFloat
    let end: CGFloat
    let opacity: Double
    let highlight: Bool
}

// Glance 0.4.1 AgentStatusArrivalFrame.segments, running branch. Positions
// are fractions of the contour, with a smoothstep spreading from its center.
func runningArrivalSegments(elapsed: TimeInterval) -> [AgentArrivalSegment] {
    guard elapsed >= 0, elapsed < 0.82 else { return [] }
    let phase = elapsed / 0.82
    let envelope = min(1, phase / 0.09) * min(1, (1 - phase) / 0.24)
    let p = min(1, max(0, (phase - 0.06) / 0.78))
    let spread = p * p * (3 - 2 * p) * 0.5
    let left = 0.5 - spread, right = 0.5 + spread
    return [
        AgentArrivalSegment(start: left, end: min(0.5, left + 0.11), opacity: envelope * 0.62, highlight: false),
        AgentArrivalSegment(start: max(0.5, right - 0.11), end: right, opacity: envelope * 0.62, highlight: false),
        AgentArrivalSegment(start: left - 0.009, end: left + 0.009, opacity: envelope, highlight: true),
        AgentArrivalSegment(start: right - 0.009, end: right + 0.009, opacity: envelope, highlight: true)
    ]
}

// Measure the current contour rather than assuming a fixed Mac or light width.
// Cubic arcs are sampled for the transient highlight's distance calculation.
func approximateContourLength(_ path: Path) -> CGFloat {
    var current = CGPoint.zero
    var length: CGFloat = 0
    func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(b.x - a.x, b.y - a.y) }
    path.cgPath.applyWithBlock { element in
        let e = element.pointee
        switch e.type {
        case .moveToPoint:
            current = e.points[0]
        case .addLineToPoint:
            length += distance(current, e.points[0]); current = e.points[0]
        case .addCurveToPoint:
            let start = current, c1 = e.points[0], c2 = e.points[1], end = e.points[2]
            for step in 1...16 {
                let t = CGFloat(step) / 16, u = 1 - t
                let point = CGPoint(x: u*u*u*start.x + 3*u*u*t*c1.x + 3*u*t*t*c2.x + t*t*t*end.x,
                                    y: u*u*u*start.y + 3*u*u*t*c1.y + 3*u*t*t*c2.y + t*t*t*end.y)
                length += distance(current, point); current = point
            }
        default: break
        }
    }
    return length
}

// Glance's approval and completion frames share an envelope but move the
// highlights in opposite directions. Shoulder fractions here are estimated
// from the actual Rium path; the original's own contour geometry can differ.
func otherAgentArrivalSegments(kind: NotchLightCue.Kind, elapsed: TimeInterval, pathLength: CGFloat, arm: CGFloat, notchWidth: CGFloat, height: CGFloat) -> [AgentArrivalSegment] {
    let duration: TimeInterval = kind == .agentDone ? 0.72 : 0.82
    guard (kind == .agentApproval || kind == .agentDone), elapsed >= 0, elapsed < duration, pathLength > 0 else { return [] }
    let phase = elapsed / duration
    let fadeIn = min(1, phase / 0.09)
    let envelope = fadeIn * min(1, (1 - phase) / 0.24)
    func smooth(_ x: Double) -> Double { let t = min(1, max(0, x)); return t * t * (3 - 2 * t) }
    func part(_ start: CGFloat, _ end: CGFloat, _ opacity: Double, _ highlight: Bool) -> AgentArrivalSegment {
        AgentArrivalSegment(start: start, end: end, opacity: opacity, highlight: highlight)
    }
    let shoulder = max(0, min(20, height / 3, notchWidth / 3))
    if kind == .agentApproval {
        let position = CGFloat(smooth(phase / 0.68)) * (arm + shoulder * .pi / 4) / pathLength
        let mirror = 1 - position, radius = 20 / pathLength
        return [part(max(0, position - 0.1), position + radius, envelope * 0.5, false),
                part(mirror - radius, min(1, mirror + 0.1), envelope * 0.5, false),
                part(position - radius, position + radius, envelope, true),
                part(mirror - radius, mirror + radius, envelope, true)]
    }
    let position = CGFloat(1 - smooth(phase / 0.7)) * arm / pathLength
    let mirror = 1 - position, radius = 16 / pathLength
    let armEnd = (arm + shoulder * .pi / 2) / pathLength
    let armOpacity = fadeIn * pow(max(0, 1 - phase / 0.74), 0.65) * 0.86
    var segments = [part(0, armEnd, armOpacity, false), part(1 - armEnd, 1, armOpacity, false),
                    part(position, min(armEnd, position + 0.14), envelope * 0.72, false),
                    part(max(1 - armEnd, mirror - 0.14), mirror, envelope * 0.72, false),
                    part(position - radius, position + radius, envelope, true),
                    part(mirror - radius, mirror + radius, envelope, true)]
    if phase > 0.58 {
        let flash = sin((phase - 0.58) / 0.42 * .pi) * 0.95
        segments.append(part(0, 0.035, flash, true)); segments.append(part(0.965, 1, flash, true))
    }
    return segments
}

// The light window is above the opaque notch window. Exclude the complete
// notch silhouette after blurring so the glow cannot wash into its interior.
struct OutsideNotchMask: Shape {
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(notchWidth, notchHeight) }
        set { notchWidth = newValue.first; notchHeight = newValue.second }
    }
    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        let notchRect = CGRect(x: rect.midX - notchWidth / 2, y: rect.minY,
                               width: notchWidth, height: notchHeight)
        path.addPath(NotchSilhouette().path(in: notchRect))
        return path
    }
}

// Keep one opaque path alive across state changes. SwiftUI interpolates these
// dimensions instead of inserting a second black view when the notch opens.
var notchAnimationProbe: [CGSize] = []

struct AnimatedNotchBackdrop: Shape {
    var width: CGFloat
    var height: CGFloat
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(width, height) }
        set { width = newValue.first; height = newValue.second }
    }
    func path(in rect: CGRect) -> Path {
        let w = max(0, width), h = max(0, height)
        if CommandLine.arguments.contains("--self-test-notch-animation"), notchAnimationProbe.count < 1000 {
            notchAnimationProbe.append(CGSize(width: w, height: h))
        }
        return NotchSilhouette().path(in: CGRect(x: rect.midX - w / 2, y: rect.minY, width: w, height: h))
    }
}

struct NotchContainer: View {
    static let lightPadding: CGFloat = 48
    @ObservedObject var model: Model
    @AppStorage("rium.light.enabled") private var lightEnabled = true
    @AppStorage("rium.light.clipboard") private var clipboardLight = true
    @AppStorage("rium.light.airdrop") private var airDropLight = true
    @AppStorage("rium.light.shelf") private var shelfLight = true
    @AppStorage("rium.light.system") private var systemLight = true
    @AppStorage("rium.light.agent") private var agentLight = true
    @AppStorage("rium.light.thickness") private var thickness = 0.6

    private func enabled(_ cue: NotchLightCue) -> Bool {
        switch cue.kind {
        case .clipboard: return clipboardLight
        case .airDrop: return airDropLight
        case .shelf: return shelfLight
        case .systemControl: return systemLight
        case .agentRunning, .agentApproval, .agentDone: return agentLight
        }
    }

    var body: some View {
        let height = model.currentNotchSize.height
        let outline = model.currentNotchOutlineSize
        let spring: Animation = model.expanded
            ? .spring(response: 0.30, dampingFraction: 0.86, blendDuration: 0)
            : .spring(response: 0.34, dampingFraction: 1.0, blendDuration: 0)
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                AnimatedNotchBackdrop(width: outline.width, height: outline.height)
                    .fill(Color.black)
                    .animation(spring, value: outline)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                if model.expanded && model.section == .home {
                    HomeAtmosphere(model: model, width: outline.width)
                        .mask(AnimatedNotchBackdrop(width: outline.width, height: outline.height).fill(Color.white).animation(spring, value: outline))
                }
                NotchView(model: model)
                    .mask(AnimatedNotchBackdrop(width: outline.width, height: outline.height)
                        .fill(Color.white)
                        .animation(spring, value: outline))
                if let cue = model.lightCue, model.expanded, cue.kind == .shelf, lightEnabled, enabled(cue) {
                    NotchEventLight(cue: cue, notchWidth: outline.width, notchHeight: height, thickness: min(2, max(0.5, thickness)))
                        .mask(OutsideNotchMask(notchWidth: outline.width, notchHeight: height).fill(style: FillStyle(eoFill: true)))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
    }
}

struct NotchEventLight: View {
    // Leave room beyond the contour endpoints for its round caps and blur.
    // Canvas clips drawing to its bounds, so ending the path at x = 0 made
    // the light look abruptly cut off instead of fading into the menu bar.
    private static let horizontalGlowPadding: CGFloat = 20
    let cue: NotchLightCue
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    var thickness: CGFloat = 1
    var armWidth: CGFloat = NotchContainer.lightPadding
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("rium.light.rays") private var raysEnabled = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let elapsed = max(0, timeline.date.timeIntervalSince(cue.started))
            Canvas { context, size in
                context.translateBy(x: Self.horizontalGlowPadding, y: 0)
                let contour = lightContour(width: notchWidth, height: notchHeight, armWidth: armWidth)
                let cycle = cue.kind == .clipboard ? 1.2 : cue.duration
                let phase = min(1, (elapsed.truncatingRemainder(dividingBy: cycle)) / cycle)
                let envelope = max(0, min(1, elapsed / 0.22, (cue.duration - elapsed) / 0.45))
                let agentCue = cue.kind == .agentRunning || cue.kind == .agentApproval || cue.kind == .agentDone
                let start = reduceMotion ? 0.0 : max(0.0, phase * 1.3 - 0.3)
                let end = reduceMotion ? 1.0 : min(1.0, phase * 1.3 + 0.03)
                guard envelope > 0 else { return }
                var segment = Path()
                if agentCue && !reduceMotion {
                    let head = min(0.5, phase * 0.58), tail = max(0, head - 0.13)
                    if head > tail {
                        segment.addPath(contour.trimmedPath(from: 0.5 - head, to: 0.5 - tail))
                        segment.addPath(contour.trimmedPath(from: 0.5 + tail, to: 0.5 + head))
                    }
                } else if start < end { segment = contour.trimmedPath(from: start, to: end) }
                let tint: Color
                switch cue.kind {
                case .clipboard, .systemControl: tint = .white
                case .shelf, .agentApproval: tint = .orange
                case .agentDone: tint = .green
                case .airDrop, .agentRunning: tint = Color(red: 0.55, green: 0.73, blue: 1.0)
                }
                if raysEnabled {
                    let halo = cue.kind == .systemControl || cue.kind == .clipboard ? Color(red: 0.55, green: 0.73, blue: 1.0) : tint
                    drawRayons(context: &context, tint: halo, armWidth: armWidth, notchWidth: notchWidth, elapsed: reduceMotion ? 0 : elapsed, envelope: envelope)
                    var soft = context; soft.addFilter(.blur(radius: 8))
                    soft.stroke(contour, with: .color(halo.opacity(0.25 * envelope)), style: StrokeStyle(lineWidth: 8 * thickness, lineCap: .round, lineJoin: .round))
                    var edge = context; edge.addFilter(.blur(radius: 3))
                    edge.stroke(contour, with: .color(halo.opacity(0.55 * envelope)), style: StrokeStyle(lineWidth: 4 * thickness, lineCap: .round, lineJoin: .round))
                    context.stroke(contour, with: .color(.white.opacity(0.72 * envelope)), style: StrokeStyle(lineWidth: 1.6 * thickness, lineCap: .round, lineJoin: .round))
                }
                if agentCue && !reduceMotion {
                    let arrivals = cue.kind == .agentRunning ? runningArrivalSegments(elapsed: elapsed) : otherAgentArrivalSegments(kind: cue.kind, elapsed: elapsed, pathLength: approximateContourLength(contour), arm: armWidth, notchWidth: notchWidth, height: notchHeight)
                    for arrival in arrivals {
                        let start = max(0, arrival.start), end = min(1, arrival.end)
                        guard end > start else { continue }
                        let part = contour.trimmedPath(from: start, to: end)
                        if arrival.highlight {
                            context.stroke(part, with: .color(tint.opacity(arrival.opacity)), style: StrokeStyle(lineWidth: 7 * thickness, lineCap: .round, lineJoin: .round))
                            context.stroke(part, with: .color(.white.opacity(arrival.opacity)), style: StrokeStyle(lineWidth: 1.6 * thickness, lineCap: .round, lineJoin: .round))
                        } else {
                            context.stroke(part, with: .color(tint.opacity(arrival.opacity)), style: StrokeStyle(lineWidth: 3.4 * thickness, lineCap: .round, lineJoin: .round))
                        }
                    }
                    return
                }
                var haze = context
                haze.addFilter(.blur(radius: 10))
                haze.stroke(segment, with: .color(tint.opacity(0.28 * envelope)), style: StrokeStyle(lineWidth: 10 * thickness, lineCap: .round, lineJoin: .round))
                var glow = context
                glow.addFilter(.blur(radius: 3))
                glow.stroke(segment, with: .color(tint.opacity(0.60 * envelope)), style: StrokeStyle(lineWidth: 5 * thickness, lineCap: .round, lineJoin: .round))
                context.stroke(segment, with: .color(.white.opacity(0.95 * envelope)), style: StrokeStyle(lineWidth: 1.8 * thickness, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: notchWidth + armWidth * 2 + Self.horizontalGlowPadding * 2, height: notchHeight + NotchContainer.lightPadding)
    }
}

// Glance's Rayons uses separate arm fog, rays and particles. These generated
// shapes approximate the observed layers without bundling the preview image.
func rayonCount(armWidth: CGFloat) -> Int {
    guard armWidth.isFinite else { return 5 }
    return min(34, max(5, Int(min(544, max(40, armWidth - 14)) / 16)))
}
func drawRayons(context: inout GraphicsContext, tint: Color, armWidth: CGFloat, notchWidth: CGFloat, elapsed: TimeInterval, envelope: Double) {
    guard armWidth > 0, envelope > 0 else { return }
    let count = rayonCount(armWidth: armWidth)
    func fraction(_ seed: Double) -> Double { let v = sin(seed * 12.9898 + 78.233) * 43758.5453; return v - floor(v) }
    for side in 0..<2 {
        let base = side == 0 ? CGFloat(0) : armWidth + notchWidth
        let direction: CGFloat = side == 0 ? 1 : -1
        var fog = context; fog.addFilter(.blur(radius: 12))
        fog.fill(Path(ellipseIn: CGRect(x: base, y: -12, width: armWidth, height: 32)), with: .color(tint.opacity(0.07 * envelope)))
        for i in 0..<count {
            let r = fraction(Double(i + 1) * 3.71 + Double(side) * 11)
            let x = base + CGFloat(r) * armWidth
            let length = CGFloat(12 + fraction(Double(i) * 7.9 + 2) * 31)
            let spread = CGFloat(1.4 + fraction(Double(i) * 5.3 + 8) * 3)
            let shimmer = 0.7 + 0.3 * sin(elapsed * 1.3 + Double(i) * 1.7)
            var ray = Path(); ray.move(to: CGPoint(x: x, y: 2)); ray.addLine(to: CGPoint(x: x + direction * spread, y: length)); ray.addLine(to: CGPoint(x: x + direction * (spread + 1.5), y: length)); ray.closeSubpath()
            context.fill(ray, with: .linearGradient(Gradient(colors: [tint.opacity(0.10 * shimmer * envelope), .clear]), startPoint: CGPoint(x: x, y: 0), endPoint: CGPoint(x: x, y: length)))
            for j in 0..<3 {
                let seed = Double(i * 3 + j + 1) + Double(side) * 71
                let px = base + CGFloat(fraction(seed * 2.3)) * armWidth
                let py = CGFloat(5 + fraction(seed * 5.7) * 43)
                let radius = CGFloat(0.35 + fraction(seed * 8.1) * 0.65)
                let opacity = (0.05 + fraction(seed * 9.2) * 0.13) * shimmer * envelope
                context.fill(Path(ellipseIn: CGRect(x: px, y: py, width: radius * 2, height: radius * 2)), with: .color(tint.opacity(opacity)))
            }
        }
    }
}

// A separate click-through window lets the glow reach the display edges
// without intercepting the user's menu-bar clicks.
struct NotchAmbientLight: View {
    @ObservedObject var model: Model

    var body: some View {
        AnimatedNotchAmbientLight(model: model, notchWidth: model.collapsedNotchSize.width, notchHeight: model.collapsedNotchSize.height)
            .animation(.spring(response: 0.30, dampingFraction: 0.86, blendDuration: 0), value: model.collapsedNotchSize)
    }
}

// The light is drawn in a separate click-through window. Interpolate its
// contour explicitly so it follows the notch instead of jumping to the final
// width as soon as an activity starts or ends.
struct AnimatedNotchAmbientLight: View, Animatable {
    @ObservedObject var model: Model
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(notchWidth, notchHeight) }
        set { notchWidth = newValue.first; notchHeight = newValue.second }
    }
    private var notchSize: CGSize { CGSize(width: notchWidth, height: notchHeight) }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("rium.light.enabled") private var lightEnabled = true
    @AppStorage("rium.light.agent") private var agentLight = true
    @AppStorage("rium.light.music") private var musicLight = true
    @AppStorage("rium.light.clipboard") private var clipboardLight = true
    @AppStorage("rium.light.airdrop") private var airDropLight = true
    @AppStorage("rium.light.shelf") private var shelfLight = true
    @AppStorage("rium.light.system") private var systemLight = true
    @AppStorage("rium.light.rays") private var raysEnabled = false
    @AppStorage("rium.light.thickness") private var thickness = 0.6
    @AppStorage("rium.light.width") private var lightWidth = "extraLarge"

    var body: some View {
        let eventActive: Bool = model.lightCue.map { cue in
            switch cue.kind {
            case .clipboard: return clipboardLight
            case .airDrop: return airDropLight
            case .shelf: return shelfLight
            case .systemControl: return systemLight
            case .agentRunning, .agentApproval, .agentDone: return agentLight
            }
        } ?? false
        let mode = ambientLightMode(expanded: model.expanded || !lightEnabled, agentActive: agentLight && model.agentItems.contains { ["작업 중", "활동 감지", "도구 실행 감지"].contains($0.state) || $0.state.hasPrefix("승인 대기") }, musicPlaying: musicLight && model.mediaPlaying, eventActive: eventActive)
        let widthScale = min(2, max(0.5, thickness))
        GeometryReader { geometry in
            let armRun = ambientArmRun(preset: lightWidth, screenWidth: geometry.size.width, notch: notchSize.width)
            if mode == .agent {
                let waiting = model.agentItems.contains { $0.state.hasPrefix("승인 대기") }
                Group {
                    if reduceMotion || !raysEnabled {
                        NotchAgentLightFrame(tint: waiting ? .orange : Color(red: 0.32, green: 0.65, blue: 1.0), time: nil, thickness: widthScale, armRun: armRun, rays: raysEnabled, notchSize: notchSize, edgeToEdge: lightWidth == "extraLarge")
                    } else {
                        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                            NotchAgentLightFrame(tint: waiting ? .orange : Color(red: 0.32, green: 0.65, blue: 1.0), time: timeline.date.timeIntervalSinceReferenceDate, thickness: widthScale, armRun: armRun, rays: true, notchSize: notchSize, edgeToEdge: lightWidth == "extraLarge")
                        }
                    }
                }
                .transition(.opacity)
            } else if mode == .music {
                if reduceMotion {
                    NotchMusicLightFrame(tint: model.mediaLightColor, time: nil, thickness: widthScale, armRun: armRun, notchSize: notchSize)
                } else {
                    TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                        NotchMusicLightFrame(tint: model.mediaLightColor, time: timeline.date.timeIntervalSinceReferenceDate, thickness: widthScale, armRun: armRun, notchSize: notchSize)
                    }
                }
            }
        }
        .overlay {
            GeometryReader { geometry in
                if let cue = model.lightCue, !model.expanded, lightEnabled, eventActive {
                    let width = notchSize.width
                    let height = notchSize.height
                    let arm = ambientArmRun(preset: lightWidth, screenWidth: geometry.size.width, notch: width)
                    NotchEventLight(cue: cue, notchWidth: width, notchHeight: height, thickness: widthScale, armWidth: arm)
                        .position(x: geometry.size.width / 2, y: (height + NotchContainer.lightPadding) / 2)
                }
            }
        }
        .mask(OutsideNotchMask(notchWidth: notchWidth, notchHeight: notchHeight).fill(style: FillStyle(eoFill: true)))
        .animation(.easeInOut(duration: 0.35), value: mode)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct NotchAgentLightFrame: View {
    let tint: Color
    let time: TimeInterval?
    let thickness: CGFloat
    let armRun: CGFloat
    let rays: Bool
    var notchSize: CGSize? = nil
    var edgeToEdge = false
    var body: some View {
        Canvas { context, size in
            let whole = ambientContour(width: size.width, notchSize: notchSize)
            let notch = notchSize?.width ?? notchWidth(expanded: false, displayWidth: size.width)
            let span = edgeToEdge ? size.width : min(size.width, notch + armRun * 2)
            let left = (size.width - span) / 2
            if rays {
                var particles = context
                particles.translateBy(x: left, y: 0)
                drawRayons(context: &particles, tint: tint, armWidth: max(0, (span - notch) / 2), notchWidth: notch, elapsed: time ?? 0, envelope: 1)
            }
            func shading(_ opacity: Double) -> GraphicsContext.Shading {
                if edgeToEdge { return .color(tint.opacity(opacity)) }
                return .linearGradient(Gradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: tint.opacity(opacity), location: 0.16),
                    .init(color: tint.opacity(opacity), location: 0.84),
                    .init(color: .clear, location: 1)
                ]), startPoint: CGPoint(x: left, y: 0), endPoint: CGPoint(x: left + span, y: 0))
            }
            var haze = context; haze.addFilter(.blur(radius: 9))
            haze.stroke(whole, with: shading(0.55), style: StrokeStyle(lineWidth: 12 * thickness, lineCap: .round, lineJoin: .round))
            var glow = context; glow.addFilter(.blur(radius: 3))
            glow.stroke(whole, with: shading(0.90), style: StrokeStyle(lineWidth: 5 * thickness, lineCap: .round, lineJoin: .round))
            context.stroke(whole, with: shading(1), style: StrokeStyle(lineWidth: 5 * thickness, lineCap: .round, lineJoin: .round))
        }
    }
}

struct NotchMusicLightFrame: View {
    let tint: NSColor
    let time: TimeInterval?
    var thickness: CGFloat = 1
    var armRun: CGFloat = 220
    var notchSize: CGSize? = nil

    var body: some View {
        Canvas { context, size in
            let baseTint = Color(nsColor: tint)
            let crestTint = Color(nsColor: musicCrestColor(tint))
            let whole = ambientContour(width: size.width, notchSize: notchSize)
            let breath = time.map { 0.5 + 0.5 * sin($0 * 2 * .pi / 3.4) } ?? 0.5
            let glowWidth = musicGlowWidth(notch: notchSize?.width ?? notchWidth(expanded: false, displayWidth: size.width), arm: armRun, screen: size.width)
            let left = (size.width - glowWidth) / 2
            let start = CGPoint(x: left, y: 0), end = CGPoint(x: left + glowWidth, y: 0)
            let baseGradient = Gradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: baseTint.opacity(0.10 + breath * 0.05), location: 0.15),
                .init(color: baseTint.opacity(0.10 + breath * 0.05), location: 0.85),
                .init(color: .clear, location: 1)
            ])
            let baseShading = GraphicsContext.Shading.linearGradient(baseGradient, startPoint: start, endPoint: end)
            var base = context
            base.addFilter(.blur(radius: 7))
            base.stroke(whole, with: baseShading, style: StrokeStyle(lineWidth: 7 * thickness, lineCap: .round, lineJoin: .round))
            context.stroke(whole, with: baseShading, style: StrokeStyle(lineWidth: 1.1 * thickness, lineCap: .round, lineJoin: .round))
            guard let time = time else { return }
            let intensity = abs(sin(time * 2 * .pi / 1.35)) * 0.35 + 0.65
            for offset in [0.0, 0.5] {
                let phase = musicRipplePhase(time: time, offset: offset)
                let opacity = (1 - phase * 0.7) * intensity * 0.34
                for center in [0.5 - phase * 0.48, 0.5 + phase * 0.48] {
                    let crest = musicCrestPositions(center)
                    let gradient = Gradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .clear, location: crest.left),
                        .init(color: crestTint.opacity(opacity), location: crest.peak),
                        .init(color: .clear, location: crest.right),
                        .init(color: .clear, location: 1)
                    ])
                    let shading = GraphicsContext.Shading.linearGradient(gradient, startPoint: start, endPoint: end)
                    var glow = context
                    glow.addFilter(.blur(radius: 5))
                    glow.stroke(whole, with: shading, style: StrokeStyle(lineWidth: 10 * thickness, lineCap: .round, lineJoin: .round))
                    context.stroke(whole, with: shading, style: StrokeStyle(lineWidth: 2.5 * thickness, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }
}

func ambientContour(width screenWidth: CGFloat, notchSize: CGSize? = nil) -> Path {
    let width = notchSize?.width ?? notchWidth(expanded: false, displayWidth: screenWidth)
    let offset = (screenWidth - width - NotchContainer.lightPadding * 2) / 2
    var path = lightContour(width: width, height: notchSize?.height ?? notchHeight(expanded: false, section: .home))
        .applying(CGAffineTransform(translationX: offset, y: 0))
    path.move(to: CGPoint(x: 0, y: 0)); path.addLine(to: CGPoint(x: max(0, offset), y: 0))
    path.move(to: CGPoint(x: min(screenWidth, offset + width + NotchContainer.lightPadding * 2), y: 0))
    path.addLine(to: CGPoint(x: screenWidth, y: 0))
    return path
}

// The reference binary describes an open contour, with extended upper arms
// and rounded lower corners. This shape follows the app's current silhouette.
func lightContour(width: CGFloat, height: CGFloat, armWidth: CGFloat = NotchContainer.lightPadding) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: 0, y: 0))
    path.addLine(to: CGPoint(x: armWidth, y: 0))
    appendNotchContour(to: &path, in: CGRect(x: armWidth, y: 0, width: width, height: height))
    path.addLine(to: CGPoint(x: width + armWidth * 2, y: 0))
    return path
}
