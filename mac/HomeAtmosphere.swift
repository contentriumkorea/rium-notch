import SwiftUI

@_silgen_name("rium_home_texture_rgba")
private func riumHomeTextureRGBA(_ kind: Int32, _ output: UnsafeMutablePointer<UInt8>?, _ length: Int) -> Int32

/// Texture pixels are expensive to synthesize. Keep that work off the UI
/// thread and share one in-flight request between the editor and home view.
private final class HomeTextureImages: ObservableObject {
    static let shared = HomeTextureImages()
    @Published private(set) var images: [HomeBackground: NSImage] = [:]
    private var pending = Set<HomeBackground>()
    private var failed = Set<HomeBackground>()
    private var waiting: [HomeBackground] = []
    private var running: HomeBackground?
    private let queue = DispatchQueue(label: "kr.contentrium.rium-notch.home-textures", qos: .userInitiated)
    private static let width = 960
    private static let height = 260
    private static let bytesPerRow = width * 4

    private static func kind(for background: HomeBackground) -> Int32? {
        switch background {
        case .halftone: return 1
        case .linen: return 2
        case .fluted: return 3
        case .paper: return 4
        case .sand: return 5
        case .opart: return 6
        case .mist: return 7
        case .silk: return 8
        case .ripple: return 9
        case .prism: return 10
        case .topo: return 11
        case .sunset: return 12
        case .marble: return 13
        case .holo: return 14
        case .watercolor: return 15
        case .matcha: return 16
        case .ember: return 17
        case .neon: return 18
        case .caustics: return 19
        case .lowpoly: return 20
        case .terrazzo: return 21
        case .cosmos: return 22
        case .bokeh: return 23
        case .aurora: return 24
        default: return nil
        }
    }

    func request(_ background: HomeBackground, priority: Bool = false) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard Self.kind(for: background) != nil, images[background] == nil, !failed.contains(background) else { return }
        if pending.contains(background) {
            if priority, let index = waiting.firstIndex(of: background), index != 0 {
                waiting.remove(at: index); waiting.insert(background, at: 0)
            }
            return
        }
        pending.insert(background)
        if priority { waiting.insert(background, at: 0) } else { waiting.append(background) }
        startNext()
    }

    private func startNext() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard running == nil, !waiting.isEmpty else { return }
        let background = waiting.removeFirst()
        guard let kind = Self.kind(for: background) else { pending.remove(background); startNext(); return }
        running = background
        queue.async { [weak self] in
            var pixels = [UInt8](repeating: 0, count: Self.bytesPerRow * Self.height)
            let result = pixels.withUnsafeMutableBufferPointer { buffer in
                riumHomeTextureRGBA(kind, buffer.baseAddress, buffer.count)
            }
            let completedPixels = pixels
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.pending.remove(background)
                self.running = nil
                if result == 1, let image = Self.image(from: completedPixels) {
                    self.images[background] = image
                } else {
                    self.failed.insert(background)
                }
                self.startNext()
            }
        }
    }

    private static func image(from pixels: [UInt8]) -> NSImage? {
        guard pixels.count == bytesPerRow * height,
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                            isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: bytesPerRow, bitsPerPixel: 32),
              let destination = bitmap.bitmapData else { return nil }
        pixels.withUnsafeBufferPointer { buffer in
            if let base = buffer.baseAddress { destination.update(from: base, count: buffer.count) }
        }
        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(bitmap)
        return image
    }
}

/// A restrained, procedural wash for the expanded home. The camera area stays black.
struct HomeAtmosphere: View {
    @ObservedObject var model: Model
    let width: CGFloat
    private var tint: Color { Color(nsColor: model.mediaLightColor) }
    private var hasAgent: Bool { model.showsCollapsedAgent }
    var body: some View {
        let height: CGFloat = 178
        Canvas { context, size in
            let area = CGRect(origin: .zero, size: size)
            let base: Color = model.homeBackground == .graphite ? .white : Color(red: 0.55, green: 0.68, blue: 0.82)
            context.fill(Path(area), with: .linearGradient(
                Gradient(stops: [.init(color: .clear, location: 0), .init(color: base.opacity(0.045), location: 0.35), .init(color: base.opacity(0.09), location: 1)]),
                startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: height)))
            let agentTint = Color(red: 0.25, green: 0.52, blue: 0.82)
            if model.homeBackground == .dynamic || model.homeBackground == .blue {
                let strength = model.homeBackground == .blue ? 0.34 : (hasAgent ? 0.28 : 0.14)
                let center = CGPoint(x: size.width * 0.58, y: size.height * 0.65)
                context.fill(Path(area), with: .radialGradient(
                    Gradient(colors: [agentTint.opacity(strength), agentTint.opacity(strength * 0.40), .clear]),
                    center: center, startRadius: 0, endRadius: size.width * 0.50))
            }
            if (model.homeBackground == .dynamic || model.homeBackground == .album) && model.mediaArtwork != nil {
                let strength = model.homeBackground == .album ? 0.30 : 0.20
                let center = CGPoint(x: size.width * 0.18, y: size.height * 0.54)
                context.fill(Path(area), with: .radialGradient(
                    Gradient(colors: [tint.opacity(strength), tint.opacity(strength * 0.30), .clear]),
                    center: center, startRadius: 0, endRadius: size.width * 0.35))
            }
            // Fixed seed avoids flicker as status and playback information update.
            for i in 0..<1600 {
                let x = CGFloat((i &* 67_631 &+ 7_919) % 10_007) / 10_007 * size.width
                let y = CGFloat((i &* 2_039 &+ 571) % 8_191) / 8_191 * size.height
                let opacity = Double((i &* 17) % 7 + 1) * 0.005
                context.fill(Path(CGRect(x: x, y: y, width: 0.45, height: 0.45)), with: .color(.white.opacity(opacity)))
            }
        }
        .frame(width: width, height: height)
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .white.opacity(0.65), location: 0.18), .init(color: .white, location: 0.48), .init(color: .white.opacity(0.85), location: 1)], startPoint: .top, endPoint: .bottom))
        .padding(.top, 32)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A fixed, non-animated texture so redrawing a card does not make its background shimmer.
struct HomeTextureSurface: View {
    let background: HomeBackground
    let priority: Bool
    @ObservedObject private var textures = HomeTextureImages.shared

    init(background: HomeBackground, priority: Bool = false) { self.background = background; self.priority = priority }

    var body: some View {
        Group {
            if let image = textures.images[background] {
                GeometryReader { geometry in
                    // The reference frames the resizable texture directly,
                    // without an aspect-fill crop.
                    Image(nsImage: image).resizable()
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                }
            } else {
                approximateTexture
            }
        }
        .onAppear { textures.request(background, priority: priority) }
        .onChange(of: background) { _, newValue in textures.request(newValue, priority: priority) }
        .onChange(of: priority) { _, selected in if selected { textures.request(background, priority: true) } }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var approximateTexture: some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 0 else { return }
            let rect = CGRect(origin: .zero, size: size)
            context.fill(Path(rect), with: .linearGradient(
                Gradient(colors: [Color(white: 0.035), Color(white: 0.14), Color(white: 0.04)]),
                startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))

            // shortcut: The loading and allocation-failure placeholder does not
            // reproduce the original procedural texture.
            switch background {
            case .fluted:
                let step: CGFloat = 12
                let count = min(Int(ceil(size.width / step)), 300)
                for index in 0..<count {
                    let x = CGFloat(index) * step
                    let stripe = CGRect(x: x, y: 0, width: step, height: size.height)
                    context.fill(Path(stripe), with: .linearGradient(
                        Gradient(colors: [.black.opacity(0.3), .white.opacity(0.13), .clear, .black.opacity(0.25)]),
                        startPoint: CGPoint(x: x, y: 0), endPoint: CGPoint(x: x + step, y: 0)))
                }
            case .halftone:
                let spacing: CGFloat = 9
                let columns = min(Int(ceil(size.width / spacing)) + 1, 300)
                let rows = min(Int(ceil(size.height / spacing)) + 1, 100)
                for row in 0..<rows {
                    for column in 0..<columns {
                        let x = CGFloat(column) * spacing + (row.isMultiple(of: 2) ? 0 : spacing / 2)
                        let y = CGFloat(row) * spacing
                        let radius: CGFloat = 1.2 + 0.8 * x / size.width
                        let dot = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                        context.fill(Path(ellipseIn: dot), with: .color(.white.opacity(0.12)))
                    }
                }
            case .linen:
                let step: CGFloat = 4
                let columns = min(Int(ceil(size.width / step)), 900)
                let rows = min(Int(ceil(size.height / step)), 250)
                for column in 0..<columns {
                    let x = CGFloat(column) * step
                    let opacity = column.isMultiple(of: 3) ? 0.08 : 0.035
                    context.fill(Path(CGRect(x: x, y: 0, width: 0.7, height: size.height)), with: .color(.white.opacity(opacity)))
                }
                for row in 0..<rows {
                    let y = CGFloat(row) * step
                    let opacity = row.isMultiple(of: 3) ? 0.07 : 0.025
                    context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 0.7)), with: .color(.white.opacity(opacity)))
                }
            default:
                break
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
