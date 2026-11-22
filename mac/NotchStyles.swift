import SwiftUI
import CoreFoundation
import ColorSync

@_silgen_name("rium_notch_uses_virtual_geometry")
private func rustNotchUsesVirtualGeometry(_ screenHeight: Double, _ safeAreaTop: Double) -> Int32

struct NotchCutoutGeometry: Equatable {
    let width: CGFloat
    let height: CGFloat
    let virtualNotch: Bool
}

struct NotchCutoutCache {
    private var cutouts: [String: (size: CGSize, scale: CGFloat, geometry: NotchCutoutGeometry)] = [:]

    mutating func resolve(key: String?, size: CGSize, scale: CGFloat, safeAreaTop: CGFloat,
                          measuredWidth: CGFloat) -> NotchCutoutGeometry {
        let virtualNotch = rustNotchUsesVirtualGeometry(Double(size.height), Double(safeAreaTop)) == 1
        if !virtualNotch, measuredWidth > 0, measuredWidth <= size.width {
            let geometry = NotchCutoutGeometry(width: measuredWidth, height: safeAreaTop, virtualNotch: false)
            if let key { cutouts[key] = (size: size, scale: scale, geometry: geometry) }
            return geometry
        }
        if let key, let cached = cutouts[key], cached.size == size, cached.scale == scale {
            return cached.geometry
        }
        return NotchCutoutGeometry(width: 0, height: 0, virtualNotch: virtualNotch)
    }
}

@_silgen_name("rium_notch_floating_corner")
private func rustNotchFloatingCorner(_ radius: Double, _ width: Double, _ height: Double,
                                     _ output: UnsafeMutablePointer<Double>?) -> Int32
@_silgen_name("rium_notch_floating_top_inset")
private func rustNotchFloatingTopInset(_ menuHeight: Double) -> Double
@_silgen_name("rium_notch_floating_compact_size")
private func rustNotchFloatingCompactSize(_ screenWidth: Double, _ menuHeight: Double, _ mode: Int32,
                                          _ output: UnsafeMutablePointer<Double>?) -> Int32

func floatingIslandCompactSize(screenWidth: CGFloat, menuHeight: CGFloat, mode: Int32) -> CGSize? {
    var values = [Double](repeating: 0, count: 2)
    let status = values.withUnsafeMutableBufferPointer {
        rustNotchFloatingCompactSize(Double(screenWidth), Double(menuHeight), mode, $0.baseAddress)
    }
    return status == 0 ? CGSize(width: values[0], height: values[1]) : nil
}
@_silgen_name("rium_notch_floating_position")
private func rustNotchFloatingPosition(_ screenX: Double, _ width: Double, _ height: Double, _ topInset: Double,
                                       _ virtualScreen: Int32, _ x: Double, _ y: Double, _ normalize: Int32,
                                       _ output: UnsafeMutablePointer<Double>?) -> Int32
@_silgen_name("rium_notch_floating_card_offset")
private func rustNotchFloatingCardOffset(_ screenX: Double, _ screenWidth: Double, _ screenMaxY: Double,
                                        _ notchCenterX: Double, _ cardWidth: Double, _ topOffset: Double,
                                        _ floating: Int32, _ hasCamera: Int32,
                                        _ cameraMinX: Double, _ cameraMaxX: Double, _ cameraMinY: Double,
                                        _ output: UnsafeMutablePointer<Double>?) -> Int32

/// Screen-relative positioning for the island; top offsets measure downward
/// from the display's upper edge rather than from the AppKit screen origin.
struct FloatingIslandPositionBounds: Equatable {
    let screen: CGRect
    let menuHeight: CGFloat
    let virtualNotch: Bool

    func anchor(_ normalized: CGPoint) -> CGPoint? { convert(normalized, normalize: false) }
    func normalized(centerX: CGFloat, topOffset: CGFloat) -> CGPoint? {
        convert(CGPoint(x: centerX, y: topOffset), normalize: true)
    }
    func cardOffset(centerX: CGFloat, width: CGFloat, topOffset: CGFloat, camera: CGRect?) -> CGSize? {
        var values = [Double](repeating: 0, count: 2)
        let status = values.withUnsafeMutableBufferPointer {
            rustNotchFloatingCardOffset(Double(screen.minX), Double(screen.width), Double(screen.maxY),
                Double(centerX), Double(width), Double(topOffset), 1, camera == nil ? 0 : 1,
                Double(camera?.minX ?? 0), Double(camera?.maxX ?? 0), Double(camera?.minY ?? 0), $0.baseAddress)
        }
        return status == 0 ? CGSize(width: values[0], height: values[1]) : nil
    }
    private func convert(_ point: CGPoint, normalize: Bool) -> CGPoint? {
        let inset = rustNotchFloatingTopInset(Double(menuHeight))
        guard inset.isFinite else { return nil }
        var values = [Double](repeating: 0, count: 2)
        let status = values.withUnsafeMutableBufferPointer {
            rustNotchFloatingPosition(Double(screen.minX), Double(screen.width), Double(screen.height), inset,
                                      virtualNotch ? 1 : 0, Double(point.x), Double(point.y), normalize ? 1 : 0, $0.baseAddress)
        }
        return status == 0 ? CGPoint(x: values[0], y: values[1]) : nil
    }
}

struct FloatingIslandPlacement: Equatable {
    let displayID: UInt32
    let bounds: FloatingIslandPositionBounds
    let camera: CGRect?
    var anchor: CGPoint
}

/// Geometry shared by the island's eventual surface placement and mouse hit
/// testing. The stored anchor uses AppKit's screen X and a downward top inset.
struct FloatingIslandScreenGeometry: Equatable {
    let bounds: FloatingIslandPositionBounds
    let anchor: CGPoint
    let size: CGSize
    let expanded: Bool
    let camera: CGRect?
    let radius: CGFloat
    var adjustsCard: Bool = false

    func frame() -> CGRect? {
        guard [bounds.screen.minX, bounds.screen.minY, bounds.screen.width, bounds.screen.height,
               anchor.x, anchor.y, size.width, size.height, radius].allSatisfy(\.isFinite),
              bounds.screen.width > 0, bounds.screen.height > 0, anchor.y >= 0,
              size.width > 0, size.height > 0, radius >= 0 else { return nil }
        let offset: CGSize
        if expanded || adjustsCard {
            guard let value = bounds.cardOffset(centerX: anchor.x, width: size.width,
                                                topOffset: anchor.y, camera: camera) else { return nil }
            offset = value
        } else {
            offset = .zero
        }
        let topOffset = min(anchor.y + offset.height, max(0, bounds.screen.height - size.height))
        let rect = CGRect(x: anchor.x - size.width / 2 + offset.width,
                          y: bounds.screen.maxY - topOffset - size.height,
                          width: size.width, height: size.height)
        return [rect.minX, rect.minY, rect.maxX, rect.maxY].allSatisfy(\.isFinite) ? rect : nil
    }

    func contains(screenPoint point: CGPoint) -> Bool {
        guard point.x.isFinite, point.y.isFinite, let frame = frame(), frame.contains(point) else { return false }
        let local = CGPoint(x: point.x - frame.minX, y: frame.maxY - point.y)
        return FloatingIslandShape(radius: radius).path(in: CGRect(origin: .zero, size: frame.size)).contains(local)
    }

    /// Convert from AppKit screen coordinates into the host's top-down view coordinates.
    func frame(in surface: CGRect) -> CGRect? {
        guard [surface.minX, surface.minY, surface.width, surface.height].allSatisfy(\.isFinite),
              surface.width > 0, surface.height > 0, let screenFrame = frame() else { return nil }
        let origin = CGPoint(x: screenFrame.minX - surface.minX, y: surface.maxY - screenFrame.maxY)
        guard origin.x.isFinite, origin.y.isFinite else { return nil }
        return CGRect(origin: origin, size: screenFrame.size)
    }
}

struct FloatingIslandRenderedGeometry: Equatable {
    let frame: CGRect
    let surface: CGRect
    let radius: CGFloat

    func contains(screenPoint point: CGPoint) -> Bool {
        guard [point.x, point.y, frame.minX, frame.minY, frame.width, frame.height,
               surface.minX, surface.maxY, radius].allSatisfy(\.isFinite), frame.width > 0, frame.height > 0 else { return false }
        let local = CGPoint(x: point.x - surface.minX, y: surface.maxY - point.y)
        guard frame.contains(local) else { return false }
        return FloatingIslandShape(radius: radius).path(in: frame).contains(local)
    }
}

struct FloatingIslandRenderedPreference: PreferenceKey {
    static var defaultValue: FloatingIslandRenderedGeometry? = nil
    static func reduce(value: inout FloatingIslandRenderedGeometry?, nextValue: () -> FloatingIslandRenderedGeometry?) {
        if let next = nextValue() { value = next }
    }
}

private struct FloatingIslandAnimatedSurface<Content: View>: View, Animatable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat
    var radius: CGFloat
    let surface: CGRect
    let lightModel: Model?
    let content: Content

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat>> {
        get { AnimatablePair(AnimatablePair(x, y), AnimatablePair(AnimatablePair(width, height), radius)) }
        set { x = newValue.first.first; y = newValue.first.second; width = newValue.second.first.first; height = newValue.second.first.second; radius = newValue.second.second }
    }

    var body: some View {
        let frame = CGRect(x: x, y: y, width: max(0, width), height: max(0, height))
        let radius = max(0, radius)
        let shape = FloatingIslandShape(radius: radius)
        ZStack {
            if let lightModel {
                FloatingIslandAmbientLight(model: lightModel, frame: frame, radius: radius)
            }
            ZStack {
                shape.fill(Color.black)
                content.frame(width: frame.width, height: frame.height).clipShape(shape)
            }
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
        }
        .preference(key: FloatingIslandRenderedPreference.self,
                    value: FloatingIslandRenderedGeometry(frame: frame, surface: surface, radius: radius))
    }
}

/// Standalone island shell; its host must supply the same geometry to mouse
/// routing and a surface large enough to contain the whole screen position.
struct FloatingIslandSurface<Content: View>: View {
    let geometry: FloatingIslandScreenGeometry
    let surfaceFrame: CGRect
    let lightModel: Model?
    let content: Content

    init(geometry: FloatingIslandScreenGeometry, surfaceFrame: CGRect, lightModel: Model? = nil,
         @ViewBuilder content: () -> Content) {
        self.geometry = geometry; self.surfaceFrame = surfaceFrame; self.lightModel = lightModel; self.content = content()
    }

    var body: some View {
        GeometryReader { _ in
            if let frame = geometry.frame(in: surfaceFrame) {
                FloatingIslandAnimatedSurface(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height,
                                              radius: geometry.radius, surface: surfaceFrame, lightModel: lightModel, content: content)
            }
        }
    }
}

/// Each gesture translation is measured from the position at drag start,
/// then clamped through the reference's screen-relative bounds.
struct FloatingIslandDragSession {
    let placementRevision: UInt64
    let bounds: FloatingIslandPositionBounds
    let initialAnchor: CGPoint

    func position(translation: CGSize) -> CGPoint? {
        guard [initialAnchor.x, initialAnchor.y, translation.width, translation.height].allSatisfy(\.isFinite),
              let normalized = bounds.normalized(centerX: initialAnchor.x + translation.width,
                                                 topOffset: initialAnchor.y + translation.height) else { return nil }
        return bounds.anchor(normalized)
    }
}

/// Forward each update with the geometry that was active at drag start.
// shortcut: handle styling and drag animation require reference-frame comparison.
struct FloatingIslandDragHandle: View {
    let placementRevision: UInt64
    let bounds: FloatingIslandPositionBounds
    let anchor: CGPoint
    let move: (FloatingIslandDragSession, CGSize, Bool) -> Void
    @State private var session: FloatingIslandDragSession?

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.6))
            .frame(width: 30, height: 24)
            .contentShape(Rectangle())
            .accessibilityLabel("노치 위치 이동")
            // The handle moves with the island, so measure from the fixed host.
            .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .global)
                .onChanged { value in
                    if session == nil {
                        session = FloatingIslandDragSession(placementRevision: placementRevision, bounds: bounds, initialAnchor: anchor)
                    }
                    if let session { move(session, value.translation, false) }
                }
                .onEnded { value in
                    guard let completed = session else { return }
                    session = nil
                    move(completed, value.translation, true)
                })
    }
}

func notchDisplayKey(_ displayID: UInt32) -> String {
    guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
          let string = CFUUIDCreateString(nil, uuid) else { return String(displayID) }
    return string as String
}

/// Positions are stored per display as fractions, so resolution changes use
/// the same position within the new display bounds.
struct FloatingIslandPositions {
    private let defaults: UserDefaults
    private let key = "rium.notch.islandPositions"
    private let displayKey: (UInt32) -> String

    init(defaults: UserDefaults = .standard, displayKey: @escaping (UInt32) -> String = notchDisplayKey) {
        self.defaults = defaults; self.displayKey = displayKey
    }

    func anchor(displayID: UInt32, bounds: FloatingIslandPositionBounds) -> CGPoint? {
        guard displayID != 0 else { return nil }
        let entry = defaults.dictionary(forKey: key)?[displayKey(displayID)] as? [String: Any]
        func fraction(_ value: Any?) -> CGFloat? {
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite, (0...1).contains(number.doubleValue) else { return nil }
            return CGFloat(number.doubleValue)
        }
        let saved: CGPoint
        if let x = fraction(entry?["x"]), let y = fraction(entry?["y"]) {
            saved = CGPoint(x: x, y: y)
        } else {
            saved = CGPoint(x: 0.5, y: 0)
        }
        return bounds.anchor(saved)
    }

    @discardableResult
    func save(displayID: UInt32, centerX: CGFloat, topOffset: CGFloat, bounds: FloatingIslandPositionBounds) -> Bool {
        guard displayID != 0, let position = bounds.normalized(centerX: centerX, topOffset: topOffset) else { return false }
        var positions = defaults.dictionary(forKey: key) ?? [:]
        positions[displayKey(displayID)] = ["x": Double(position.x), "y": Double(position.y)]
        defaults.set(positions, forKey: key)
        return true
    }
}

/// Preserve the in-flight position when a display changes resolution; load
/// the target display's own saved position when switching displays.
func resolveFloatingIslandPlacement(displayID: UInt32, bounds: FloatingIslandPositionBounds, camera: CGRect?,
                                    previous: FloatingIslandPlacement?, positions: FloatingIslandPositions) -> FloatingIslandPlacement? {
    guard displayID != 0 else { return nil }
    let anchor: CGPoint?
    if let previous = previous, previous.displayID == displayID,
       let normalized = previous.bounds.normalized(centerX: previous.anchor.x, topOffset: previous.anchor.y) {
        anchor = bounds.anchor(normalized)
    } else {
        anchor = positions.anchor(displayID: displayID, bounds: bounds)
    }
    guard let anchor = anchor else { return nil }
    return FloatingIslandPlacement(displayID: displayID, bounds: bounds, camera: camera, anchor: anchor)
}

/// Continuous island corners reconstructed from the reference's corner points.
struct FloatingIslandShape: Shape {
    var radius: CGFloat = 28
    var closesTop = true
    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    private func cornerPoints(in rect: CGRect) -> [CGPoint]? {
        var values = [Double](repeating: 0, count: 20)
        let status = values.withUnsafeMutableBufferPointer {
            rustNotchFloatingCorner(Double(radius), Double(rect.width), Double(rect.height), $0.baseAddress)
        }
        guard status == 0 else { return nil }
        return (0..<10).map { CGPoint(x: values[$0 * 2], y: values[$0 * 2 + 1]) }
    }

    func cornerMetrics(in rect: CGRect) -> (shoulder: CGFloat, side: CGFloat, arc: CGFloat)? {
        guard let points = cornerPoints(in: rect) else { return nil }
        var corner = Path()
        corner.move(to: points[0])
        for end in stride(from: 3, through: 9, by: 3) {
            corner.addCurve(to: points[end], control1: points[end - 2], control2: points[end - 1])
        }
        let length = approximateContourLength(corner)
        return (length, max(0, rect.height - 2 * points[9].y), length)
    }

    func path(in rect: CGRect) -> Path {
        guard let points = cornerPoints(in: rect) else { return Path() }
        func point(_ index: Int, mirrorX: Bool, mirrorY: Bool) -> CGPoint {
            let x = points[index].x, y = points[index].y
            return CGPoint(x: mirrorX ? rect.maxX - x : rect.minX + x,
                           y: mirrorY ? rect.maxY - y : rect.minY + y)
        }
        var path = Path()
        path.move(to: point(0, mirrorX: false, mirrorY: false))
        func corner(_ mirrorX: Bool, _ mirrorY: Bool, reversed: Bool) {
            if reversed {
                for end in stride(from: 6, through: 0, by: -3) {
                    path.addCurve(to: point(end, mirrorX: mirrorX, mirrorY: mirrorY),
                                  control1: point(end + 2, mirrorX: mirrorX, mirrorY: mirrorY),
                                  control2: point(end + 1, mirrorX: mirrorX, mirrorY: mirrorY))
                }
            } else {
                for end in stride(from: 3, through: 9, by: 3) {
                    path.addCurve(to: point(end, mirrorX: mirrorX, mirrorY: mirrorY),
                                  control1: point(end - 2, mirrorX: mirrorX, mirrorY: mirrorY),
                                  control2: point(end - 1, mirrorX: mirrorX, mirrorY: mirrorY))
                }
            }
        }
        corner(false, false, reversed: false)
        path.addLine(to: point(9, mirrorX: false, mirrorY: true))
        corner(false, true, reversed: true)
        path.addLine(to: point(0, mirrorX: true, mirrorY: true))
        corner(true, true, reversed: false)
        path.addLine(to: point(9, mirrorX: true, mirrorY: false))
        corner(true, false, reversed: true)
        if closesTop { path.closeSubpath() }
        return path
    }
}

@_silgen_name("rium_notch_shell_contour_y")
private func rustNotchShellContourY(_ x: Double, _ width: Double, _ height: Double,
                                    _ bottom: Double, _ shoulder: Double) -> Double
@_silgen_name("rium_notch_pixel_cell_size")
private func rustNotchPixelCellSize(_ column: UInt32, _ row: UInt32, _ gridSpacing: Double) -> Double
@_silgen_name("rium_notch_pixel_grid_columns")
private func rustNotchPixelGridColumns(_ width: Double, _ gridSpacing: Double) -> UInt32
@_silgen_name("rium_notch_pixel_cell_opacity")
private func rustNotchPixelCellOpacity(_ column: UInt32, _ row: UInt32, _ field: Double, _ fade: Double) -> Double
@_silgen_name("rium_notch_pixel_sample_x")
private func rustNotchPixelSampleX(_ x: Double, _ y: Double) -> Double
@_silgen_name("rium_notch_pixel_sample_y")
private func rustNotchPixelSampleY(_ x: Double, _ y: Double) -> Double
@_silgen_name("rium_notch_pixel_arm_fade")
private func rustNotchPixelArmFade(_ x: Double, _ y: Double, _ width: Double, _ contourHeight: Double,
                                   _ armReach: Double, _ armRun: Double) -> Double
@_silgen_name("rium_notch_pixel_contour_field")
private func rustNotchPixelContourField(_ x: Double, _ y: Double, _ width: Double, _ height: Double,
                                        _ notchWidth: Double, _ notchHeight: Double, _ arm: Double, _ thickness: Double) -> Double
@_silgen_name("rium_notch_pixel_intensity_scale")
private func rustNotchPixelIntensityScale(_ intensity: Double) -> Double
@_silgen_name("rium_notch_pixel_field_bounds")
private func rustNotchPixelFieldBounds(_ width: Double, _ height: Double, _ notchWidth: Double, _ notchHeight: Double,
                                      _ arm: Double, _ thickness: Double, _ output: UnsafeMutablePointer<Double>?) -> Int32

func pixelGridVisibleRange(lower: CGFloat, upper: CGFloat, spacing: CGFloat, count: Int) -> Range<Int> {
    guard lower.isFinite, upper.isFinite, spacing.isFinite, spacing > 0, count > 0 else { return 0..<0 }
    let first = Int(min(CGFloat(count), max(0, floor(lower / spacing))))
    let last = Int(min(CGFloat(count), max(0, ceil(upper / spacing))))
    return first..<max(first, last)
}

enum NotchLightColor {
    static let defaultRGB = 0x52A6FF

    static func color(_ rgb: Int) -> Color {
        Color(.sRGB, red: Double((rgb >> 16) & 255) / 255,
              green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
    }

    static func rgb(_ color: Color) -> Int? {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        func channel(_ value: CGFloat) -> Int { Int((min(1, max(0, value)) * 255).rounded()) }
        return (channel(rgb.redComponent) << 16) | (channel(rgb.greenComponent) << 8) | channel(rgb.blueComponent)
    }
}

func notchStyleTimelinePaused(_ style: String, reduceMotion: Bool) -> Bool {
    reduceMotion || style == "pixel" || style == "rays"
}

func usesCustomAgentLight(_ style: String, waiting: Bool) -> Bool {
    guard !waiting else { return false }
    switch style {
    case "pixel", "volume", "rays", "bio", "prism", "cloud": return true
    default: return false
    }
}

private func notchLightNoise(_ seed: Double) -> Double {
    let value = sin(seed * 12.9898 + 78.233) * 43758.5453
    return value - floor(value)
}

private func islandContourSamples(_ contour: Path, spacing: CGFloat) -> [(CGPoint, CGVector)] {
    var samples: [(CGPoint, CGVector)] = []
    var start = CGPoint.zero, previous = CGPoint.zero
    var next = spacing / 2
    contour.cgPath.flattened(threshold: 0.2).applyWithBlock { pointer in
        let element = pointer.pointee
        if element.type == .moveToPoint {
            start = element.points[0]
            previous = start
            next = spacing / 2
            return
        }
        guard element.type == .addLineToPoint || element.type == .closeSubpath else { return }
        let end = element.type == .closeSubpath ? start : element.points[0]
        let dx = end.x - previous.x, dy = end.y - previous.y
        let length = hypot(dx, dy)
        guard length > 0 else { return }
        let normal = CGVector(dx: -dy / length, dy: dx / length)
        while next < length {
            let fraction = next / length
            samples.append((CGPoint(x: previous.x + dx * fraction, y: previous.y + dy * fraction), normal))
            next += spacing
        }
        next -= length
        previous = end
    }
    return samples
}

func drawFloatingNotchStyle(_ style: String, in context: inout GraphicsContext, contour: Path,
                            tint: Color, time: TimeInterval, strength: Double, thickness: CGFloat, reach: CGFloat) {
    guard !contour.isEmpty, strength > 0 else { return }
    let pulse = 0.75 + 0.25 * sin(time * .pi / 3)
    if style == "volume" || style == "prism" {
        let volume = style == "volume"
        var halo = context
        halo.addFilter(.blur(radius: (volume ? 12 : 4) * reach))
        halo.stroke(contour, with: .color(tint.opacity((volume ? 0.28 : 0.38) * strength * pulse)),
                    style: StrokeStyle(lineWidth: (volume ? 14 : 6) * thickness, lineCap: .round, lineJoin: .round))
        if volume {
            context.stroke(contour, with: .color(tint.opacity(0.32 * strength)), lineWidth: 2.4 * thickness)
            return
        }
    }

    let spacing: CGFloat
    switch style {
    case "pixel": spacing = 4
    case "rays": spacing = 16
    case "bio": spacing = 7
    case "prism": spacing = 61
    case "cloud": spacing = 23
    default: return
    }
    var particles = context
    if style == "cloud" { particles.addFilter(.blur(radius: 9 * reach)) }
    let origin = contour.boundingRect.origin
    for (index, sample) in islandContourSamples(contour, spacing: spacing).enumerated() {
        let (anchor, normal) = sample
        let seed = Double(index + 1)
        let random = notchLightNoise(seed * 2.7)
        func point(out: CGFloat, along: CGFloat = 0) -> CGPoint {
            CGPoint(x: anchor.x + normal.dx * out * reach + normal.dy * along,
                    y: anchor.y + normal.dy * out * reach - normal.dx * along)
        }
        switch style {
        case "pixel":
            for row in 0..<4 {
                let fade = 1 - Double(row) / 4
                guard notchLightNoise(seed * 4.4 + Double(row) * 2.3) < fade else { continue }
                let position = point(out: (2 + CGFloat(row) * 3.8) * thickness)
                let x = round((position.x - origin.x) / 3) * 3 + origin.x
                let y = round((position.y - origin.y) / 3) * 3 + origin.y
                let size = CGFloat(rustNotchPixelCellSize(UInt32(index), UInt32(row), 3))
                context.fill(Path(CGRect(x: x - size / 2, y: y - size / 2, width: size, height: size)),
                             with: .color(tint.opacity((0.18 + 0.56 * random) * fade * strength)))
            }
        case "rays":
            let near = point(out: 2 * thickness)
            let far = point(out: (14 + 27 * random) * thickness, along: (random - 0.5) * 14)
            var ray = Path()
            ray.move(to: near); ray.addLine(to: far)
            let shading = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [tint.opacity((0.25 + 0.35 * random) * strength), .clear]), startPoint: near, endPoint: far)
            context.stroke(ray, with: shading, style: StrokeStyle(lineWidth: (0.7 + random) * thickness, lineCap: .round))
        case "prism":
            let center = point(out: (5 + random * 9) * thickness)
            var glint = Path()
            glint.move(to: CGPoint(x: center.x - 7, y: center.y))
            glint.addLine(to: CGPoint(x: center.x + 7, y: center.y))
            glint.move(to: CGPoint(x: center.x, y: center.y - 6))
            glint.addLine(to: CGPoint(x: center.x, y: center.y + 6))
            context.stroke(glint, with: .color(.white.opacity((0.3 + 0.45 * random) * strength * pulse)), lineWidth: 0.65 * thickness)
        default: // Bio and cloud share the particle placement.
            let cloud = style == "cloud"
            let drift = sin(time * (cloud ? 0.14 : 0.8) + seed) * (cloud ? 3 : 1.8)
            let center = point(out: (3 + random * 11) * thickness, along: drift)
            let radius = (cloud ? 5 + random * 10 : 0.5 + random * 1.5) * thickness
            let alpha = cloud ? 0.09 + random * 0.17 : (0.18 + random * 0.50) * pulse
            let bounds = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            particles.fill(Path(ellipseIn: bounds), with: .color(tint.opacity(alpha * strength)))
        }
    }
}

// Procedural interpretations of the saved Glance style previews. The original
// particle systems and their exact timings are not yet recovered. The caller
// applies the outside-only notch mask after these blurred layers are drawn.
func drawNotchStyle(_ style: String, in context: inout GraphicsContext, size: CGSize,
                            notchSize: CGSize, armRun: CGFloat, tint: Color,
                            time: TimeInterval, strength: Double, thickness: CGFloat = 1, corners: NotchCorners = .legacy) {
    guard style != "classic", size.width > 0, notchSize.width > 0, strength > 0 else { return }
    let contour = ambientContour(width: size.width, notchSize: notchSize, corners: corners)
    let arm = max(0, min(armRun, (size.width - notchSize.width) / 2))
    let left = size.width / 2 - notchSize.width / 2 - arm
    let right = size.width / 2 + notchSize.width / 2 + arm
    let width = max(1, right - left)
    let pulse = 0.75 + 0.25 * sin(time * .pi / 3)
    func contourY(_ x: CGFloat) -> CGFloat {
        let localX = x - (size.width - notchSize.width) / 2
        let y = rustNotchShellContourY(Double(localX), Double(notchSize.width), Double(notchSize.height),
                                      Double(corners.bottom), Double(corners.shoulder))
        return y.isFinite ? CGFloat(y) : 0
    }
    func armShading(_ color: Color, opacity: Double) -> GraphicsContext.Shading {
        // shortcut: the exact end fade needs comparison with the reference.
        .linearGradient(Gradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: color.opacity(opacity), location: 0.16),
            .init(color: color.opacity(opacity), location: 0.84),
            .init(color: .clear, location: 1)
        ]), startPoint: CGPoint(x: left, y: 0), endPoint: CGPoint(x: right, y: 0))
    }
    switch style {
    case "volume":
        var fog = context; fog.addFilter(.blur(radius: 12))
        fog.stroke(contour, with: armShading(tint, opacity: 0.28 * strength * pulse),
                   style: StrokeStyle(lineWidth: 14 * thickness, lineCap: .round, lineJoin: .round))
        context.stroke(contour, with: armShading(.white, opacity: 0.24 * strength),
                       style: StrokeStyle(lineWidth: 2.4 * thickness, lineCap: .round, lineJoin: .round))
    case "rays":
        var rays = context
        rays.translateBy(x: left, y: 0)
        drawRayons(context: &rays, tint: tint, armWidth: arm, notchWidth: notchSize.width,
                   envelope: strength, thickness: thickness)
    case "pixel":
        // shortcut: the parent strength-to-intensity mapping needs reference comparison.
        let intensity = rustNotchPixelIntensityScale(strength)
        guard intensity.isFinite else { return }
        let count = Int(rustNotchPixelGridColumns(Double(size.width), 3))
        let rowCount = Int(rustNotchPixelGridColumns(Double(size.height), 3))
        guard count > 0, rowCount > 0 else { return }
        let spacing = max(3, size.width / CGFloat(count))
        let rowSpacing = max(3, size.height / CGFloat(rowCount))
        var bounds = [Double](repeating: 0, count: 4)
        let status = bounds.withUnsafeMutableBufferPointer {
            rustNotchPixelFieldBounds(Double(size.width), Double(size.height), Double(notchSize.width), Double(notchSize.height),
                                      Double(arm), Double(thickness), $0.baseAddress)
        }
        guard status == 0 else { return }
        let columns = pixelGridVisibleRange(lower: CGFloat(bounds[0]), upper: CGFloat(bounds[1]), spacing: spacing, count: count)
        let rows = pixelGridVisibleRange(lower: CGFloat(bounds[2]), upper: CGFloat(bounds[3]), spacing: rowSpacing, count: rowCount)
        for column in columns {
            let x = (CGFloat(column) + 0.5) * spacing
            for row in rows {
                let y = (CGFloat(row) + 0.5) * rowSpacing
                let sampleX = rustNotchPixelSampleX(Double(x), Double(y))
                let sampleY = rustNotchPixelSampleY(Double(x), Double(y))
                guard sampleX.isFinite, sampleY.isFinite else { continue }
                // shortcut: the original caller's armReach and optional-run
                // mapping still needs frame comparison; these use our geometry.
                let fade = rustNotchPixelArmFade(sampleX, sampleY, Double(size.width), Double(notchSize.height),
                                                 Double((size.width - notchSize.width) / 2), Double(arm))
                guard fade.isFinite, fade * intensity * 0.98 > 0.04 else { continue }
                let field = rustNotchPixelContourField(sampleX, sampleY, Double(size.width), Double(size.height),
                                                       Double(notchSize.width), Double(notchSize.height), Double(arm), Double(thickness)) * intensity
                let alpha = rustNotchPixelCellOpacity(UInt32(column), UInt32(row), field, fade)
                guard alpha.isFinite, alpha > 0 else { continue }
                let cellSize = CGFloat(rustNotchPixelCellSize(UInt32(column), UInt32(row), 3))
                context.fill(Path(CGRect(x: x - cellSize / 2, y: y - cellSize / 2, width: cellSize, height: cellSize)), with: .color(tint.opacity(alpha * strength)))
            }
        }
    case "bio":
        for index in 0..<180 {
            let seed = Double(index + 1)
            let x = left + width * CGFloat(notchLightNoise(seed * 1.7))
            let motion = sin(time * 0.8 + seed) * 1.8
            let y = contourY(x) + 1 + CGFloat(notchLightNoise(seed * 2.7) * 12 + motion)
            let radius = CGFloat(0.5 + notchLightNoise(seed * 6.3) * 1.5) * thickness
            let opacity = (0.18 + notchLightNoise(seed * 8.7) * 0.50) * strength * pulse
            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2)), with: .color(tint.opacity(opacity)))
        }
    case "prism":
        var glow = context; glow.addFilter(.blur(radius: 4))
        glow.stroke(contour, with: armShading(tint, opacity: 0.38 * strength), style: StrokeStyle(lineWidth: 6 * thickness, lineCap: .round))
        for x in [size.width / 2 - notchSize.width / 2, size.width / 2 + notchSize.width / 2] {
            let y = notchSize.height
            var star = Path()
            star.move(to: CGPoint(x: x - 13, y: y)); star.addLine(to: CGPoint(x: x + 13, y: y))
            star.move(to: CGPoint(x: x, y: y - 8)); star.addLine(to: CGPoint(x: x, y: y + 8))
            context.stroke(star, with: .color(.white.opacity(0.45 * strength * pulse)), lineWidth: 0.65 * thickness)
        }
    case "cloud":
        var mist = context; mist.addFilter(.blur(radius: 9))
        for index in 0..<28 {
            let seed = Double(index + 1)
            let drift = CGFloat(sin(time * 0.14 + seed) * 3)
            let x = left + width * CGFloat(notchLightNoise(seed * 1.3)) + drift
            let y = contourY(x) + CGFloat(3 + notchLightNoise(seed * 2.1) * 20)
            let radius = CGFloat(5 + notchLightNoise(seed * 3.1) * 10) * thickness
            mist.fill(Path(ellipseIn: CGRect(x: x - radius, y: y, width: radius * 2, height: radius)),
                      with: .color(tint.opacity((0.09 + notchLightNoise(seed * 4.4) * 0.18) * strength)))
        }
    default: break
    }
}

struct NotchStyleAccent: View {
    let style: String
    let tint: Color
    let notchSize: CGSize
    let armRun: CGFloat
    let strength: Double
    let thickness: CGFloat
    var corners: NotchCorners = .legacy
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    init(style: String, tint: Color, notchSize: CGSize, armRun: CGFloat, strength: Double, thickness: CGFloat = 1, corners: NotchCorners = .legacy) {
        self.style = style; self.tint = tint; self.notchSize = notchSize
        self.armRun = armRun; self.strength = strength; self.thickness = thickness; self.corners = corners
    }
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: notchStyleTimelinePaused(style, reduceMotion: reduceMotion))) { _ in
            let time = reduceMotion ? 0 : ProcessInfo.processInfo.systemUptime
            Canvas { context, size in
                drawNotchStyle(style, in: &context, size: size, notchSize: notchSize, armRun: armRun,
                               tint: tint, time: time,
                               strength: strength, thickness: thickness, corners: corners)
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct NotchStyleSample: View {
    let style: String
    let widthPreset: String
    let lightThickness: CGFloat
    let tint: Color
    let displayWidth: CGFloat
    let liveNotchWidth: CGFloat
    var floating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Small swatches need enough contrast to show their diffuse or sparse details.
    private var sampleStrength: Double {
        switch style {
        case "volume": return 2.4
        case "rays": return 1.6
        case "bio": return 1.4
        case "prism": return 1.3
        case "cloud": return 3.2
        default: return 1
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let thickness = min(2, max(0.5, lightThickness))
            if floating {
                let size = geometry.size
                let islandWidth = min(128, size.width * 0.62)
                let frame = CGRect(x: (size.width - islandWidth) / 2, y: (size.height - 20) / 2, width: islandWidth, height: 20)
                let radius: CGFloat = 10
                let path = FloatingIslandShape(radius: radius).path(in: frame)
                let reach = floatingLightReachScale(widthPreset)
                let previewThickness = thickness * 0.72
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: style == "classic" || notchStyleTimelinePaused(style, reduceMotion: reduceMotion))) { _ in
                    let time = reduceMotion ? 0 : ProcessInfo.processInfo.systemUptime
                    Canvas { context, _ in
                        if style == "classic" {
                            drawFloatingHalo(in: context, path: path, shading: .color(tint), intensity: 0.45,
                                             active: true, thickness: previewThickness, reach: reach)
                        } else {
                            drawFloatingNotchStyle(style, in: &context, contour: path, tint: tint,
                                                   time: time, strength: sampleStrength, thickness: previewThickness, reach: reach)
                        }
                    }
                    .mask(FloatingIslandOutsideMask(frame: frame, radius: radius, edgeOnly: false).fill(style: FillStyle(eoFill: true)))
                    .mask(FloatingIslandOutsideMask(frame: frame, radius: radius, edgeOnly: true).fill(style: FillStyle(eoFill: true)))
                    .background { path.fill(.black) }
                }
            } else {
                let notch = CGSize(width: min(82, geometry.size.width * 0.48), height: 23)
                let liveArm = ambientArmRun(preset: widthPreset, screenWidth: displayWidth, notch: liveNotchWidth)
                let liveRoom = (displayWidth - liveNotchWidth) / 2
                let reach = liveRoom > 0 ? liveArm / liveRoom : 0
                let arm = max(0, (geometry.size.width - notch.width) / 2) * reach
                Group {
                    if style == "classic" {
                        NotchAgentLightFrame(tint: tint, time: nil,
                                             thickness: thickness, armRun: arm, acting: true,
                                             thinking: false, notchSize: notch, edgeToEdge: widthPreset == "extraLarge")
                    } else {
                        NotchStyleAccent(style: style, tint: tint, notchSize: notch,
                                         armRun: arm, strength: sampleStrength, thickness: thickness)
                    }
                }
                .mask(OutsideNotchMask(notchWidth: notch.width, notchHeight: notch.height).fill(style: FillStyle(eoFill: true)))
                .mask(OutsideNotchEdgeMask(notchWidth: notch.width, notchHeight: notch.height).fill(style: FillStyle(eoFill: true)))
                .background(alignment: .top) {
                    NotchSilhouette().fill(.black).frame(width: notch.width, height: notch.height)
                }
                .padding(.top, 11)
            }
        }
        .background(Color(white: 0.035))
        .accessibilityHidden(true)
    }
}
