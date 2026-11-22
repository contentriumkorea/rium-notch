import AppKit
import ImageIO
import SwiftUI

/// Decode a bounded image preview without loading the full-resolution image.
func fileImageThumbnail(_ url: URL, maxPixelSize: Int) -> CGImage? {
    guard url.isFileURL, maxPixelSize > 0, maxPixelSize <= 1024,
          let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateThumbnailAtIndex(source, 0, [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
    ] as CFDictionary)
}

@_silgen_name("rium_screenshot_line_capacity")
func rustScreenshotLineCapacity(_ height: Double) -> Int32

enum ScreenshotCordLayout {
    static let panelWidth: CGFloat = 330
    static let cardSize = CGSize(width: 160, height: 104)
    static let top: CGFloat = 30
    static let spacing: CGFloat = 132

    static func cardRect(index: Int, expanded: Bool) -> CGRect {
        let centerX = panelWidth - (expanded ? 118 : -52)
        return CGRect(x: centerX - cardSize.width / 2, y: top + CGFloat(index) * spacing,
                      width: cardSize.width, height: cardSize.height)
    }
}

@_silgen_name("rium_screenshot_line_create")
private func rustScreenshotLineCreate(_ height: Double) -> UnsafeMutableRawPointer?
@_silgen_name("rium_screenshot_line_free")
private func rustScreenshotLineFree(_ state: UnsafeMutableRawPointer?)
@_silgen_name("rium_screenshot_line_step")
private func rustScreenshotLineStep(_ state: UnsafeMutableRawPointer?, _ elapsed: Double, _ expanded: Int32,
                                    _ count: Int32, _ reduced: Int32, _ output: UnsafeMutablePointer<Double>?, _ length: Int) -> Int32

@_silgen_name("rium_screenshot_line_remap")
private func rustScreenshotLineRemap(_ state: UnsafeMutableRawPointer?, _ indices: UnsafePointer<Int32>?, _ count: Int) -> Int32
@_silgen_name("rium_screenshot_line_grab")
private func rustScreenshotLineGrab(_ state: UnsafeMutableRawPointer?, _ index: Int32, _ x: Double, _ y: Double) -> Int32
@_silgen_name("rium_screenshot_line_move")
private func rustScreenshotLineMove(_ state: UnsafeMutableRawPointer?, _ x: Double, _ y: Double) -> Int32
@_silgen_name("rium_screenshot_line_release")
private func rustScreenshotLineRelease(_ state: UnsafeMutableRawPointer?, _ velocityX: Double, _ velocityY: Double) -> Int32

struct ScreenshotCordCard {
    let center: CGPoint
    let angle: Double

    func contains(_ point: CGPoint) -> Bool {
        let dx = point.x - center.x, dy = point.y - center.y
        let c = cos(angle), s = sin(angle)
        return abs(dx * c + dy * s) <= ScreenshotCordLayout.cardSize.width / 2
            && abs(-dx * s + dy * c) <= ScreenshotCordLayout.cardSize.height / 2
    }
}

final class ScreenshotCordMotion: ObservableObject {
    @Published private(set) var points: [CGPoint] = []
    @Published private(set) var cards: [ScreenshotCordCard] = []
    private var state: UnsafeMutableRawPointer?
    private var timer: Timer?
    private var height: CGFloat = 0
    private var lastTick: TimeInterval = 0
    private var grabbedURL: URL?
    private var grabbedIndex: Int?
    private var knownItems: [URL] = []
    @Published private(set) var systemDraggingURL: URL?
    var isGrabbing: Bool { grabbedURL != nil }

    func grab(url: URL, at point: CGPoint, model: Model) -> Bool {
        tick(model)
        guard grabbedURL == nil, let index = model.cordItems.firstIndex(of: url),
              rustScreenshotLineGrab(state, Int32(clamping: index), Double(point.x), Double(point.y)) == 0 else { return false }
        grabbedURL = url; grabbedIndex = index
        return true
    }
    func move(to point: CGPoint) -> Bool {
        guard grabbedURL != nil else { return false }
        return rustScreenshotLineMove(state, Double(point.x), Double(point.y)) == 1
    }
    func startSystemDrag() { systemDraggingURL = grabbedURL }
    func release(velocity: CGPoint, model: Model) {
        tick(model)
        let url = grabbedURL
        let result = rustScreenshotLineRelease(state, Double(velocity.x), Double(velocity.y))
        grabbedURL = nil; grabbedIndex = nil; systemDraggingURL = nil
        guard let url else { return }
        if result == 1 { model.removeCordFile(url) }
        else if result >= 2, let current = model.cordItems.firstIndex(of: url) {
            let target = min(Int(result - 2), model.cordItems.count - 1)
            if current != target {
                var items = model.cordItems
                items.remove(at: current); items.insert(url, at: target)
                model.cordItems = items
                model.onCordChange?()
            }
        }
    }

    func start(height: CGFloat, model: Model) {
        guard height >= 1, height.isFinite else { stop(); return }
        if state == nil || self.height != height {
            if let state { rustScreenshotLineFree(state) }
            grabbedURL = nil; grabbedIndex = nil; systemDraggingURL = nil; knownItems = []
            state = rustScreenshotLineCreate(Double(height))
            self.height = height
            lastTick = ProcessInfo.processInfo.systemUptime
        }
        guard state != nil else { stop(); return }
        tick(model)
        if timer == nil {
            let next = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self, weak model] _ in
                guard let self, let model else { return }
                self.tick(model)
            }
            RunLoop.main.add(next, forMode: .common)
            timer = next
        }
    }

    private func tick(_ model: Model) {
        if knownItems != model.cordItems {
            let indices = model.cordItems.map { Int32(knownItems.firstIndex(of: $0) ?? -1) }
            let result = indices.withUnsafeBufferPointer { rustScreenshotLineRemap(state, $0.baseAddress, $0.count) }
            guard result == 0 else { return }
            knownItems = model.cordItems
            if let url = grabbedURL {
                grabbedIndex = knownItems.firstIndex(of: url)
                if grabbedIndex == nil { grabbedURL = nil; systemDraggingURL = nil }
            }
        }
        let now = ProcessInfo.processInfo.systemUptime
        let delta = min(0.05, max(0, now - lastTick))
        lastTick = now
        var values = [Double](repeating: 0, count: 34 * 2 + 5 * 3)
        let result = values.withUnsafeMutableBufferPointer {
            rustScreenshotLineStep(state, delta, model.cordExpanded ? 1 : 0, Int32(clamping: model.cordItems.count),
                                   NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 0,
                                   $0.baseAddress, $0.count)
        }
        guard result == 0 else { return }
        points = (0..<34).map { CGPoint(x: values[$0 * 2], y: values[$0 * 2 + 1]) }
        cards = (0..<min(5, model.cordItems.count)).map {
            let index = 68 + $0 * 3
            return ScreenshotCordCard(center: CGPoint(x: values[index], y: values[index + 1]), angle: values[index + 2])
        }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        if let state { rustScreenshotLineFree(state) }
        state = nil; height = 0; lastTick = 0
        grabbedURL = nil; grabbedIndex = nil; systemDraggingURL = nil; knownItems = []
        points = []; cards = []
    }
    deinit { timer?.invalidate(); if let state { rustScreenshotLineFree(state) } }
}

struct ScreenshotCordView: View {
    @ObservedObject var model: Model
    @ObservedObject var motion: ScreenshotCordMotion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { path in
                if let first = motion.points.first {
                    path.move(to: first)
                    for point in motion.points.dropFirst() { path.addLine(to: point) }
                }
            }
            .stroke(.white.opacity(0.42), lineWidth: 1.5)
            .allowsHitTesting(false)
            ForEach(Array(model.cordItems.enumerated()), id: \.element) { index, url in
                if index < motion.cards.count {
                    let card = motion.cards[index]
                    ScreenshotCordItem(url: url, model: model, motion: motion) { model.removeCordFile(url) }
                        .rotationEffect(.radians(card.angle))
                        .opacity(motion.systemDraggingURL == url ? 0 : 1)
                        .position(card.center)
                        .transition(.asymmetric(insertion: .offset(y: -132).combined(with: .opacity),
                                                removal: .offset(y: 150).combined(with: .opacity)))
                }
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.78), value: model.cordItems)
    }
}

private struct ScreenshotCordItem: View {
    let url: URL
    let model: Model
    let motion: ScreenshotCordMotion
    let dismiss: () -> Void
    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: thumbnail ?? NSWorkspace.shared.icon(forFile: url.path))
                .resizable().scaledToFit().frame(width: 146, height: 73)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(url.lastPathComponent).font(.system(size: 10)).lineLimit(1)
                .truncationMode(.middle).foregroundStyle(.white)
        }
        .frame(width: ScreenshotCordLayout.cardSize.width, height: ScreenshotCordLayout.cardSize.height)
        .background(.black.opacity(0.87), in: RoundedRectangle(cornerRadius: 10))
        .overlay { ScreenshotCordDragSurface(url: url, model: model, motion: motion, image: thumbnail) }
        .overlay(alignment: .topTrailing) {
            Button(action: dismiss) { Image(systemName: "xmark.circle.fill").font(.system(size: 15)).foregroundStyle(.white) }
                .buttonStyle(.plain).padding(3).accessibilityLabel("보관 줄에서 제거")
        }
        .accessibilityLabel(url.lastPathComponent)
        .onAppear {
            DispatchQueue.global(qos: .utility).async {
                guard let image = fileImageThumbnail(url, maxPixelSize: 240) else { return }
                DispatchQueue.main.async { thumbnail = NSImage(cgImage: image, size: .zero) }
            }
        }
    }
}

private struct ScreenshotCordDragSurface: NSViewRepresentable {
    let url: URL
    let model: Model
    let motion: ScreenshotCordMotion
    let image: NSImage?

    func makeNSView(context: Context) -> ScreenshotCordDragView { ScreenshotCordDragView() }
    func updateNSView(_ view: ScreenshotCordDragView, context: Context) {
        view.url = url; view.model = model; view.motion = motion; view.image = image
    }
}

private final class ScreenshotCordDragView: NSView, NSDraggingSource {
    var url: URL?
    weak var model: Model?
    weak var motion: ScreenshotCordMotion?
    var image: NSImage?
    private var trackingCard = false
    private var systemDragging = false
    private var samples: [(point: CGPoint, time: TimeInterval)] = []

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func position() -> CGPoint? {
        guard let window else { return nil }
        let point = NSEvent.mouseLocation
        return CGPoint(x: point.x - window.frame.minX, y: window.frame.maxY - point.y)
    }

    override func mouseDown(with event: NSEvent) {
        guard let url, let model, let motion, let point = position() else { return }
        if event.clickCount == 2 { NSWorkspace.shared.open(url); return }
        trackingCard = motion.grab(url: url, at: point, model: model)
        samples = [(point, event.timestamp)]
    }

    override func mouseDragged(with event: NSEvent) {
        guard trackingCard, !systemDragging, let point = position(), let motion, let url else { return }
        samples.append((point, event.timestamp))
        if samples.count > 12 { samples.removeFirst(samples.count - 12) }
        let detached = motion.move(to: point)
        guard detached, point.x < -2 || (model?.cordItems.firstIndex(of: url).flatMap { $0 < motion.cards.count ? motion.cards[$0].center.x : nil } ?? 100) < 8 else { return }
        systemDragging = true
        motion.startSystemDrag()
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        item.setDraggingFrame(bounds, contents: image ?? NSWorkspace.shared.icon(forFile: url.path))
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        guard trackingCard, !systemDragging, let motion, let model else { return }
        var velocity = CGPoint.zero
        if let first = samples.first(where: { event.timestamp - $0.time < 0.09 }), let last = samples.last {
            let duration = max(1.0 / 60.0, last.time - first.time)
            velocity = CGPoint(x: (last.point.x - first.point.x) / duration, y: (last.point.y - first.point.y) / duration)
        }
        motion.release(velocity: velocity, model: model)
        trackingCard = false; samples.removeAll()
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if let motion, let model {
            if let window {
                _ = motion.move(to: CGPoint(x: screenPoint.x - window.frame.minX, y: window.frame.maxY - screenPoint.y))
            }
            motion.release(velocity: .zero, model: model)
        }
        trackingCard = false; systemDragging = false; samples.removeAll()
    }
}
