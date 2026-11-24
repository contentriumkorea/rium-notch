import AppKit
import MetalKit
import SwiftUI

// Distance-field reconstruction based on the reference executable's shader.
// shortcut: compositor blending and notch shoulders need reference-frame comparison.
private let edgeWaveShader = #"""
#include <metal_stdlib>
using namespace metal;
struct WaveUniforms { float4 screen; float4 notch; float4 timing; float4 receiving; float4 style; };
struct VertexOut { float4 position [[position]]; };
vertex VertexOut riumWaveVertex(uint id [[vertex_id]]) {
    float2 p = float2((id << 1) & 2, id & 2);
    VertexOut out; out.position = float4(p * 2.0 - 1.0, 0.0, 1.0); return out;
}
static float random2(float2 p) { return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }
static float valueNoise(float2 p) {
    float2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
    return mix(mix(random2(i), random2(i + float2(1, 0)), f.x),
               mix(random2(i + float2(0, 1)), random2(i + float2(1, 1)), f.x), f.y);
}
static float textureNoise(float2 p) {
    float sum = 0.0, amplitude = 0.5;
    for (int i = 0; i < 4; ++i) { sum += amplitude * valueNoise(p); p = p * 2.03 + float2(1.7, 9.2); amplitude *= 0.5; }
    return sum;
}
static float4 surfaceOutput(float3 light, float style) {
    float peak = max(light.r, max(light.g, light.b));
    if (style > 0.5) {
        float3 rgb = light / max(peak, 0.001);
        float grey = dot(rgb, float3(0.2126, 0.7152, 0.0722));
        bool neon = style < 1.5;
        rgb = clamp(mix(float3(grey), rgb, neon ? 1.04 : 1.0), 0.0, 1.0);
        float white = neon ? min(rgb.r, min(rgb.g, rgb.b)) * 0.12 : 0.0;
        rgb = (rgb - white) / max(1.0 - white, 0.001);
        float alpha = clamp(peak * (neon ? 1.10 : 1.0), 0.0, 1.0);
        return float4(rgb * alpha, alpha);
    }
    return float4(light, clamp(peak * 0.35, 0.0, 1.0));
}
fragment float4 riumWaveFragment(VertexOut in [[stage_in]], constant WaveUniforms& u [[buffer(0)]]) {
    float2 p = in.position.xy;
    float width = max(u.screen.x, 1.0), originX = u.screen.z, originY = u.screen.w;
    float elapsed = max(u.timing.x, 0.0);
    bool agentWave = u.screen.y > 0.5;
    bool incoming = u.notch.w > 0.5;
    bool held = u.receiving.x > 0.5;
    float heldClock = u.receiving.z;
    float t = agentWave ? elapsed : (incoming ? max(2.0 - elapsed, 0.0) : max(elapsed - 0.4, 0.0));
    float phase = clamp((t - 0.1) / 2.25, 0.0, 1.0);
    float radius = 1.05 * (1.0 - pow(1.0 - phase, 1.8)) + 0.015 * sin(phase * M_PI_F) * (1.0 - phase);
    float corner = u.notch.z;
    bool floating = u.style.w > 0.5;
    float halfHeight = u.notch.y * 0.5;
    float centerY = floating ? originY - halfHeight : 0.0;
    float2 box = abs(p - float2(originX, centerY)) - (float2(u.notch.x * 0.5, floating ? halfHeight : originY) - corner);
    float signedDistance = length(max(box, 0.0)) + min(max(box.x, box.y), 0.0) - corner;
    if (signedDistance < 0.0) return float4(0.0);
    float distance = max(signedDistance, 0.0);
    float3 color = u.timing.yzw;
    float charge = held ? (0.85 + 0.15 * u.receiving.y + 0.08 * sin(heldClock * 2.2)) * u.receiving.w : incoming
        ? smoothstep(1.45, 1.9, elapsed) + 0.35 * sin(M_PI_F * clamp((elapsed - 1.9) / 0.6, 0.0, 1.0))
        : smoothstep(0.0, 0.4, elapsed) * (1.0 - 0.75 * smoothstep(0.5, 2.2, elapsed));
    float3 contourLight = float3(0.0);
    // shortcut: this scales both contour lobes; compare the reference's thickness mapping.
    // Distance is measured in drawable pixels; the contour settings are in points.
    float contourDistance = distance / max(u.style.x * u.style.y, 0.5);
    if (!agentWave && charge > 0.001 && contourDistance < 60.0) {
        float2 relative = p - float2(originX, floating ? centerY : originY * 0.5);
        float contourAngle = atan2(relative.x, max(1.0, relative.y));
        float noiseClock = held ? heldClock : elapsed;
        float noise = textureNoise(float2(contourAngle * 7.0 + noiseClock * 1.3, noiseClock * 1.7));
        float life = 0.7 + 1.2 * noise * noise;
        float brightness = exp(-contourDistance / 2.2) * 0.55 * life + exp(-contourDistance / 11.0) * 0.16;
        contourLight = mix(float3(1.0), color, 0.45) * brightness * charge;
    }
    if (held) {
        return surfaceOutput(contourLight, u.style.z);
    }
    if (radius < 0.001) {
        return surfaceOutput(contourLight, u.style.z);
    }
    float2 closest = float2(clamp(p.x, originX - u.notch.x * 0.36, originX + u.notch.x * 0.36), originY);
    float2 q = (p - closest) / width;
    float angle = atan2(q.x, q.y);
    float wobble = (0.035 * sin(3.0 * angle + 2.1 * t) + 0.02 * sin(5.0 * angle - 3.3 * t)
                  + 0.012 * sin(9.0 * angle + 4.7 * t)) * (0.6 + 0.8 * radius);
    float d = (agentWave ? length(q) : distance / width) / (1.0 + wobble);
    if (d - radius > 0.2 || radius - d > 0.6) {
        return surfaceOutput(contourLight, u.style.z);
    }
    float fade = 1.0 - smoothstep(1.5, 2.6, t);
    fade *= smoothstep(-0.12, 0.22, textureNoise(float2(angle * 3.0, t * 0.6)) - 0.55 + (1.7 - t) * 0.5);
    float energy = 1.0 / (1.0 + radius * 1.4);
    float spark = pow(textureNoise(float2(angle * 10.0 + t * 1.5, t * 2.0)), 3.0) * 3.0;
    float rim = exp(-pow((d - radius) / 0.0035, 2.0)) * (0.35 + spark);
    float soft = exp(-abs(d - radius) / 0.045);
    float innerRadius = max(radius - 0.12, 0.0);
    float inner = exp(-abs(d - innerRadius) / 0.035) * step(0.001, innerRadius);
    float wash = smoothstep(0.0, 0.05, radius - d) * exp(-max(radius - d, 0.0) / 0.16)
               * (0.6 + 0.8 * textureNoise(p / width * 3.0 + t * 0.4));
    float3 light = (mix(float3(1.0), color, 0.35) * rim * 0.55 + color * soft * 0.22
                   + color * inner * 0.07 + (color * 0.6 + 0.2) * wash * 0.08) * fade * energy + contourLight;
    return surfaceOutput(light, u.style.z);
}
"""#

func waveMetalMayPrepare(isPreparing: Bool, hasResources: Bool, now: TimeInterval, retryAfter: TimeInterval) -> Bool {
    !isPreparing && !hasResources && now.isFinite && retryAfter.isFinite && now >= retryAfter
}

private struct WaveMetalResources {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let pipeline: MTLRenderPipelineState

    private static let lock = NSLock()
    private static var started = false
    private static var retryAfter: TimeInterval = 0
    private static var stored: WaveMetalResources?
    static var current: WaveMetalResources? {
        lock.lock(); defer { lock.unlock() }; return stored
    }
    static func prepare() {
        lock.lock()
        guard waveMetalMayPrepare(isPreparing: started, hasResources: stored != nil,
                                  now: ProcessInfo.processInfo.systemUptime, retryAfter: retryAfter) else { lock.unlock(); return }
        started = true; lock.unlock()
        DispatchQueue.global(qos: .utility).async {
            let result = Self.makeResources()
            Self.lock.lock()
            Self.stored = result
            Self.started = false
            // shortcut: retry on a later effect after 30 seconds; tune once GPU failures are measured.
            if result == nil { Self.retryAfter = ProcessInfo.processInfo.systemUptime + 30 }
            Self.lock.unlock()
        }
    }
    private static func makeResources() -> WaveMetalResources? {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: edgeWaveShader, options: nil),
              let vertex = library.makeFunction(name: "riumWaveVertex"),
              let fragment = library.makeFunction(name: "riumWaveFragment") else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex; descriptor.fragmentFunction = fragment
        guard let color = descriptor.colorAttachments[0] else { return nil }
        color.pixelFormat = .bgra8Unorm; color.isBlendingEnabled = true
        color.sourceRGBBlendFactor = .one; color.destinationRGBBlendFactor = .oneMinusSourceAlpha
        color.sourceAlphaBlendFactor = .one; color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        return WaveMetalResources(device: device, queue: queue, pipeline: pipeline)
    }
}

private final class EdgeWaveMetalView: MTKView, MTKViewDelegate {
    var cue: EdgeWaveCue?
    var notchSize = CGSize.zero
    var notchOrigin: CGPoint?
    var floatingRadius: CGFloat?
    var heldProgress: Double?
    var lightThickness: CGFloat = 1
    var surfaceStyle: Float = 0
    var tint = edgeWaveTint(nil)
    var onFailure: (() -> Void)?
    private var failureStarted: TimeInterval?
    private var failureReported = false
    override var isOpaque: Bool { false }
    init() {
        super.init(frame: .zero, device: WaveMetalResources.current?.device)
        wantsLayer = true; layer?.isOpaque = false; clearColor = MTLClearColorMake(0, 0, 0, 0)
        colorPixelFormat = .bgra8Unorm; framebufferOnly = true
        preferredFramesPerSecond = 60; isPaused = false; enableSetNeedsDisplay = false
        delegate = self
    }
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func resetFailure() { failureStarted = nil; failureReported = false }
    private func recordFailure(immediate: Bool = false) {
        guard window?.isVisible == true, !failureReported else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if failureStarted == nil { failureStarted = now }
        guard immediate || now - (failureStarted ?? now) >= 0.4 else { return }
        failureReported = true
        let expectedID = cue?.id
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.cue?.id == expectedID else { return }
            self.onFailure?()
        }
    }
    func draw(in view: MTKView) {
        guard let cue = cue else { return }
        if ProcessInfo.processInfo.systemUptime < cue.started { return }
        guard view.window?.isVisible == true else { failureStarted = nil; return }
        guard let resources = WaveMetalResources.current, view.bounds.width > 0,
              view.drawableSize.width > 0, view.drawableSize.height > 0,
              let drawable = currentDrawable, let pass = currentRenderPassDescriptor,
              let command = resources.queue.makeCommandBuffer(), let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            recordFailure(); return
        }
        failureStarted = nil
        let scale = view.drawableSize.width / view.bounds.width
        let width = notchSize.width * scale, height = notchSize.height * scale
        let corner = floatingRadius.map { min($0 * scale, height / 2, width / 2) }
            ?? max(0, min(20 * scale, height / 3, width / 3))
        let originX = notchOrigin.map { $0.x * scale } ?? view.drawableSize.width / 2
        let originY = notchOrigin.map { $0.y * scale } ?? height
        let thickness = lightThickness.isFinite ? min(2, max(0.5, lightThickness)) : 1
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = max(0, now - cue.started)
        let heldClock = receivingLightElapsed(started: cue.started, now: now)
        let uniforms: [Float] = [Float(view.drawableSize.width), cue.agentKind == nil ? 0 : 1, Float(originX), Float(originY),
                                Float(width), Float(height), Float(corner), cue.inward ? 1 : 0,
                                Float(elapsed), Float(tint.red), Float(tint.green), Float(tint.blue),
                                heldProgress == nil ? 0 : 1, Float(min(1, max(0, heldProgress ?? 0))),
                                Float(heldClock), 1,
                                Float(thickness), Float(scale), surfaceStyle, floatingRadius == nil ? 0 : 1]
        encoder.setRenderPipelineState(resources.pipeline)
        uniforms.withUnsafeBufferPointer { values in
            if let base = values.baseAddress { encoder.setFragmentBytes(base, length: values.count * MemoryLayout<Float>.stride, index: 0) }
        }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding(); command.present(drawable)
        command.addCompletedHandler { [weak self] result in
            guard result.status == .error else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.cue?.id == cue.id else { return }
                self.recordFailure(immediate: true)
            }
        }
        command.commit()
    }
}

struct EdgeWaveMetal: NSViewRepresentable {
    let cue: EdgeWaveCue
    let notchSize: CGSize
    var notchOrigin: CGPoint? = nil
    var floatingRadius: CGFloat? = nil
    var heldProgress: Double? = nil
    var lightThickness: CGFloat = 1
    var surfaceStyle: Float = 0
    let tint: ScreenWaveTint
    let onFailure: () -> Void
    static func prepare() { WaveMetalResources.prepare() }
    static var available: Bool {
        if WaveMetalResources.current != nil { return true }
        WaveMetalResources.prepare()
        return false
    }
    func makeNSView(context: Context) -> MTKView { EdgeWaveMetalView() }
    func updateNSView(_ view: MTKView, context: Context) {
        guard let wave = view as? EdgeWaveMetalView else { return }
        if wave.cue?.id != cue.id { wave.resetFailure() }
        wave.cue = cue; wave.notchSize = notchSize; wave.heldProgress = heldProgress
        wave.notchOrigin = notchOrigin; wave.floatingRadius = floatingRadius
        wave.lightThickness = lightThickness; wave.surfaceStyle = surfaceStyle; wave.tint = tint
        wave.onFailure = onFailure
    }
}
