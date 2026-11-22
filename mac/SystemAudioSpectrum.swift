import AppKit
import AudioToolbox
import Combine
import CoreMedia
import ScreenCaptureKit

@_silgen_name("rium_audio_stereo_spectrum")
private func rustAudioStereoSpectrum(_ left: UnsafePointer<Float>, _ right: UnsafePointer<Float>?, _ count: Int,
                                     _ rate: Double, _ previous: UnsafePointer<Double>, _ output: UnsafeMutablePointer<Double>) -> Int32
@_silgen_name("rium_audio_spectrum_expired")
private func rustAudioSpectrumExpired(_ last: Double, _ now: Double) -> Int32
@_silgen_name("rium_collapsed_music_wave_frame")
private func rustSpectrumWaveFrame(_ index: Int32, _ time: Double, _ levels: UnsafePointer<Double>?, _ count: Int, _ reduced: Int32, _ seed: UInt64, _ playbackTime: Double, _ output: UnsafeMutablePointer<Double>) -> Int32
@_silgen_name("rium_audio_wave_transition")
private func rustSpectrumWaveTransition(_ from: Double, _ to: Double, _ elapsed: Double) -> Double

func resetStaleAudioWindow(rolling: inout [[Float]], smoothed: inout [Double], lastSample: TimeInterval, now: TimeInterval) -> Bool {
    guard lastSample > 0, rustAudioSpectrumExpired(lastSample, now) == 1 else { return false }
    rolling = Array(repeating: [], count: rolling.count)
    smoothed = [Double](repeating: 0, count: 6)
    return true
}

func audioCaptureStartStillPending(request: Int, generation: Int, starting: Bool) -> Bool {
    starting && request == generation
}

struct AudioSpectrumRetry {
    private(set) var deadline: TimeInterval?
    private var delay: TimeInterval = 2

    mutating func schedule(at now: TimeInterval) {
        guard now.isFinite else { return }
        deadline = now + delay
        delay = min(60, delay * 2)
    }
    mutating func takeIfDue(at now: TimeInterval) -> Bool {
        guard now.isFinite, let deadline = deadline, now >= deadline else { return false }
        self.deadline = nil
        return true
    }
    mutating func reset() { deadline = nil; delay = 2 }
}

func audioLevelsExpired(last: TimeInterval, now: TimeInterval) -> Bool {
    !last.isFinite || !now.isFinite || now < last || now - last >= 0.4
}

struct SpectrumIntensityTransition {
    let from: Double
    let to: Double?
    let started: TimeInterval

    static func fallback(at time: TimeInterval) -> Double {
        time.isFinite ? (abs(sin(time * 2 * .pi / 1.35)) * 0.35 + 0.40) / 0.75 : 1
    }

    static func receiving(_ target: Double, after previous: Self?, at time: TimeInterval) -> Self {
        Self(from: previous?.value(at: time) ?? fallback(at: time), to: target, started: time)
    }

    func value(at time: TimeInterval) -> Double {
        let target = to ?? Self.fallback(at: time)
        guard time.isFinite, started.isFinite else { return target }
        let progress = min(1, max(0, (time - started) / 0.1))
        return from + (target - from) * progress
    }
}

struct MusicWaveContext {
    let seed: UInt64
    let playbackTime: TimeInterval
    let renderTime: TimeInterval

    static func fallback(at time: TimeInterval) -> Self {
        Self(seed: 0xcbf29ce484222325, playbackTime: time, renderTime: time)
    }
}

func musicWaveSeed(_ source: String, _ title: String) -> UInt64 {
    (source + "\u{1f}" + title).utf8.reduce(UInt64(0xcbf29ce484222325)) { ($0 ^ UInt64($1)) &* 0x100000001b3 }
}

struct MusicWaveFrame {
    let height: Double
    let opacity: Double
}

struct SpectrumWaveTransition {
    let from: [MusicWaveFrame]
    let to: [Double]?
    let started: TimeInterval

    static func targetFrame(_ index: Int, levels: [Double]?, at time: TimeInterval, context: MusicWaveContext? = nil, reduced: Bool = false) -> MusicWaveFrame {
        let fallback = MusicWaveFrame(height: 8, opacity: 0.65)
        guard (0..<6).contains(index), time.isFinite else { return fallback }
        let context = context ?? .fallback(at: time)
        var output = [Double](repeating: 0, count: 2)
        let status = output.withUnsafeMutableBufferPointer { values in
            if let levels = levels, levels.count == 6 {
                return levels.withUnsafeBufferPointer { rustSpectrumWaveFrame(Int32(index), context.renderTime, $0.baseAddress, $0.count, reduced ? 1 : 0, context.seed, context.playbackTime, values.baseAddress!) }
            }
            return rustSpectrumWaveFrame(Int32(index), context.renderTime, nil, 0, reduced ? 1 : 0, context.seed, context.playbackTime, values.baseAddress!)
        }
        guard status == 0, output.allSatisfy(\.isFinite) else { return fallback }
        return MusicWaveFrame(height: output[0], opacity: output[1])
    }

    static func target(_ index: Int, levels: [Double]?, at time: TimeInterval, context: MusicWaveContext? = nil) -> Double {
        targetFrame(index, levels: levels, at: time, context: context).height
    }

    static func receiving(_ levels: [Double]?, after previous: Self?, at time: TimeInterval, context: MusicWaveContext? = nil) -> Self {
        let start = (0..<6).map { previous?.frame($0, at: time, context: context) ?? targetFrame($0, levels: nil, at: time, context: context) }
        return Self(from: start, to: levels, started: time)
    }

    func frame(_ index: Int, at time: TimeInterval, context: MusicWaveContext? = nil) -> MusicWaveFrame {
        let target = Self.targetFrame(index, levels: to, at: time, context: context)
        guard from.indices.contains(index), time.isFinite, started.isFinite else { return target }
        let height = rustSpectrumWaveTransition(from[index].height, target.height, time - started)
        let opacity = rustSpectrumWaveTransition(from[index].opacity, target.opacity, time - started)
        guard height.isFinite, opacity.isFinite else { return target }
        return MusicWaveFrame(height: height, opacity: opacity)
    }

    func height(_ index: Int, at time: TimeInterval, context: MusicWaveContext? = nil) -> Double {
        frame(index, at: time, context: context).height
    }
}

// Captures audio only for the explicitly enabled visualizer. Raw samples never
// leave this object and each channel keeps at most 1024 frames.
final class SystemAudioSpectrum: NSObject, ObservableObject, SCStreamOutput, SCStreamDelegate {
    @Published private(set) var levels: [Double]? = nil {
        didSet {
            let now = ProcessInfo.processInfo.systemUptime
            if levels == nil { levelExpiryTimer?.invalidate(); levelExpiryTimer = nil }
            else { scheduleLevelExpiry() }
            if levels != nil || oldValue != nil {
                waveTransition = SpectrumWaveTransition.receiving(levels, after: waveTransition, at: now, context: waveContext?(now))
            }
            guard let levels = levels, !levels.isEmpty, levels.allSatisfy(\.isFinite) else {
                if let current = intensityTransition?.value(at: now) {
                    intensityTransition = SpectrumIntensityTransition(from: current, to: nil, started: now)
                }
                return
            }
            let average = min(1, max(0, levels.reduce(0, +) / Double(levels.count)))
            intensityTransition = SpectrumIntensityTransition.receiving(average, after: intensityTransition, at: now)
        }
    }
    private(set) var intensityTransition: SpectrumIntensityTransition?
    private(set) var waveTransition: SpectrumWaveTransition?
    var waveContext: ((TimeInterval) -> MusicWaveContext)?

    func waveFrame(_ index: Int, at time: TimeInterval, reduced: Bool) -> MusicWaveFrame {
        let context = waveContext?(time)
        if reduced { return SpectrumWaveTransition.targetFrame(index, levels: nil, at: time, context: context, reduced: true) }
        return waveTransition?.frame(index, at: time, context: context)
            ?? SpectrumWaveTransition.targetFrame(index, levels: nil, at: time, context: context)
    }
    @Published private(set) var status = ""
    @Published private(set) var enabled = UserDefaults.standard.bool(forKey: "rium.light.musicSpectrum")
    private let queue = DispatchQueue(label: "app.rium.notch.music-spectrum", qos: .userInitiated)
    private var stream: SCStream?
    private var generation = 0
    private var starting = false
    private var startTimeout: DispatchWorkItem?
    private var failed = false
    private var retry = AudioSpectrumRetry()
    private var playing = false
    private var lighting = true
    private var lastDelivery: TimeInterval?
    private var levelExpiryTimer: Timer?
    // Accessed only from queue, not from the main thread.
    private var audioStream: SCStream?
    private var rolling: [[Float]] = []
    private var smoothed = [Double](repeating: 0, count: 6)
    private var audioSampleRate: Double?
    private var lastUpdate: TimeInterval = 0
    private var lastSample: TimeInterval = 0

    func setEnabled(_ value: Bool) {
        enabled = value
        UserDefaults.standard.set(value, forKey: "rium.light.musicSpectrum")
        failed = false; retry.reset()
        if value && !CGPreflightScreenCaptureAccess() && !CGRequestScreenCaptureAccess() {
            status = "시스템 오디오를 사용하려면 화면 및 시스템 오디오 녹음 권한이 필요합니다."
        }
        reconcile()
    }

    func update(playing: Bool, lighting: Bool) {
        self.playing = playing
        self.lighting = lighting
        reconcile()
    }

    func retryIfAuthorized() {
        guard enabled else { return }
        if CGPreflightScreenCaptureAccess() { failed = false; retry.reset() }
        reconcile()
    }

    private func scheduleLevelExpiry() {
        guard levelExpiryTimer == nil, levels != nil, let last = lastDelivery else { return }
        let delay = max(0.001, last + 0.4 - ProcessInfo.processInfo.systemUptime)
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.levelExpiryTimer = nil
            self.expireStaleLevels()
            self.scheduleLevelExpiry()
        }
        levelExpiryTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func expireStaleLevels() {
        if failed && enabled && playing && lighting && CGPreflightScreenCaptureAccess(),
           retry.takeIfDue(at: ProcessInfo.processInfo.systemUptime) {
            failed = false; reconcile()
        }
        guard levels != nil, let last = lastDelivery,
              audioLevelsExpired(last: last, now: ProcessInfo.processInfo.systemUptime) else { return }
        levels = nil; lastDelivery = nil
        status = "시스템 오디오 신호를 기다리는 중"
    }

    private func markFailure(_ message: String) {
        startTimeout?.cancel(); startTimeout = nil
        failed = true
        retry.schedule(at: ProcessInfo.processInfo.systemUptime)
        status = message
    }

    func stop() {
        generation &+= 1
        startTimeout?.cancel(); startTimeout = nil
        starting = false
        let old = stream
        stream = nil
        levels = nil
        lastDelivery = nil
        queue.async { [weak self, old] in
            guard let self = self, self.audioStream === old else { return }
            self.audioStream = nil; self.rolling.removeAll(keepingCapacity: false); self.lastUpdate = 0; self.lastSample = 0
            self.smoothed = [Double](repeating: 0, count: 6); self.audioSampleRate = nil
        }
        old?.stopCapture(completionHandler: { _ in })
    }

    private func reconcile() {
        guard enabled && playing && lighting else {
            if stream != nil || starting { stop() }
            if !enabled { status = "" }
            else if !lighting { status = "음악 조명이 켜져 있을 때 사용합니다." }
            else { status = "음악이 재생되면 시스템 오디오에 반응합니다." }
            return
        }
        guard CGPreflightScreenCaptureAccess() else {
            if stream != nil || starting { stop() }
            status = "시스템 오디오를 사용하려면 화면 및 시스템 오디오 녹음 권한이 필요합니다."
            return
        }
        guard stream == nil && !starting && !failed else { return }
        generation &+= 1
        let request = generation
        starting = true
        status = "시스템 오디오 연결 중"
        let timeout = DispatchWorkItem { [weak self] in
            guard let self = self, audioCaptureStartStillPending(request: request, generation: self.generation, starting: self.starting) else { return }
            self.stop()
            self.markFailure("시스템 오디오 연결 시간이 초과되어 다시 시도합니다.")
        }
        startTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: timeout)
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { [weak self] content, error in
            DispatchQueue.main.async {
                guard let self = self, self.generation == request else { return }
                guard error == nil, let display = content?.displays.first else {
                    self.starting = false; self.markFailure("시스템 오디오에 연결하지 못했습니다. 다시 시도합니다."); return
                }
                let config = SCStreamConfiguration()
                config.capturesAudio = true
                config.excludesCurrentProcessAudio = true
                config.sampleRate = 48000
                config.channelCount = 2
                config.width = 2; config.height = 2
                config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let candidate = SCStream(filter: filter, configuration: config, delegate: self)
                do { try candidate.addStreamOutput(self, type: .audio, sampleHandlerQueue: self.queue) }
                catch { self.starting = false; self.markFailure("시스템 오디오를 준비하지 못했습니다. 다시 시도합니다."); return }
                self.stream = candidate
                self.queue.async { [weak self, candidate] in
                    self?.audioStream = candidate; self?.rolling.removeAll(keepingCapacity: false); self?.lastUpdate = 0; self?.lastSample = 0
                    self?.smoothed = [Double](repeating: 0, count: 6); self?.audioSampleRate = nil
                }
                candidate.startCapture { [weak self, candidate] error in
                    DispatchQueue.main.async {
                        guard let self = self, self.generation == request, self.stream === candidate else {
                            candidate.stopCapture(completionHandler: { _ in }); return
                        }
                        self.starting = false
                        self.startTimeout?.cancel(); self.startTimeout = nil
                        if error != nil {
                            self.stream = nil; self.levels = nil; self.lastDelivery = nil
                            self.queue.async { [weak self, candidate] in
                                guard let self = self, self.audioStream === candidate else { return }
                                self.audioStream = nil; self.rolling.removeAll(keepingCapacity: false); self.lastSample = 0
                                self.smoothed = [Double](repeating: 0, count: 6); self.audioSampleRate = nil
                            }
                            self.markFailure("시스템 오디오를 시작하지 못했습니다. 다시 시도합니다.")
                        } else { self.status = self.levels == nil ? "시스템 오디오 신호를 기다리는 중" : "시스템 오디오에 반응 중" }
                    }
                }
            }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.stream === stream else { return }
            self.stream = nil; self.starting = false; self.levels = nil; self.lastDelivery = nil
            self.markFailure("시스템 오디오 연결이 중단됐습니다. 다시 시도합니다.")
            self.queue.async { [weak self, stream] in
                guard let self = self, self.audioStream === stream else { return }
                self.audioStream = nil; self.rolling.removeAll(keepingCapacity: false); self.lastSample = 0
                self.smoothed = [Double](repeating: 0, count: 6); self.audioSampleRate = nil
            }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, CMSampleBufferDataIsReady(sampleBuffer),
              let format = CMSampleBufferGetFormatDescription(sampleBuffer),
              let basic = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
              basic.mFormatID == kAudioFormatLinearPCM,
              basic.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              basic.mFormatFlags & kAudioFormatFlagIsPacked != 0,
              basic.mFormatFlags & kAudioFormatFlagIsBigEndian == 0,
              basic.mBitsPerChannel == 32, basic.mSampleRate.isFinite,
              (8000...192000).contains(basic.mSampleRate) else { return }
        guard audioStream === stream else { return }
        var needed = 0
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer, bufferListSizeNeededOut: &needed, bufferListOut: nil, bufferListSize: 0, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: nil) == noErr,
              needed >= MemoryLayout<AudioBufferList>.size, needed <= 4096 else { return }
        let memory = UnsafeMutableRawPointer.allocate(byteCount: needed, alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { memory.deallocate() }
        let list = memory.bindMemory(to: AudioBufferList.self, capacity: 1)
        var block: CMBlockBuffer?
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer, bufferListSizeNeededOut: nil, bufferListOut: list, bufferListSize: needed, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment), blockBufferOut: &block) == noErr else { return }
        withExtendedLifetime(block) {
            let buffers = UnsafeMutableAudioBufferListPointer(list)
            guard !buffers.isEmpty, buffers.count <= 8 else { return }
            let usable = buffers.compactMap { buffer -> (UnsafePointer<Float>, Int, Int)? in
                let channels = Int(buffer.mNumberChannels)
                guard (1...8).contains(channels), let data = buffer.mData else { return nil }
                let frameCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / channels
                return (UnsafePointer(data.assumingMemoryBound(to: Float.self)), channels, frameCount)
            }
            guard usable.count == buffers.count, let frames = usable.map({ $0.2 }).min(), frames > 0 else { return }
            let channels = usable.flatMap { buffer in
                (0..<buffer.1).map { (data: buffer.0, stride: buffer.1, offset: $0) }
            }
            guard (1...2).contains(channels.count) else { return }
            if audioSampleRate != basic.mSampleRate || rolling.count != channels.count {
                rolling = Array(repeating: [], count: channels.count); smoothed = [Double](repeating: 0, count: 6)
                audioSampleRate = basic.mSampleRate; lastUpdate = 0
            }
            let now = ProcessInfo.processInfo.systemUptime
            if resetStaleAudioWindow(rolling: &rolling, smoothed: &smoothed, lastSample: lastSample, now: now) { lastUpdate = 0 }
            lastSample = now
            let first = max(0, frames - 1024)
            for (index, channel) in channels.enumerated() {
                for frame in first..<frames {
                    let sample = channel.data[frame * channel.stride + channel.offset]
                    rolling[index].append(sample.isFinite ? sample : 0)
                }
                if rolling[index].count > 1024 { rolling[index].removeFirst(rolling[index].count - 1024) }
            }
            guard rolling.allSatisfy({ $0.count >= 1024 }), now - lastUpdate >= 0.1 else { return }
            lastUpdate = now
            var result = [Double](repeating: 0, count: 6)
            let right = rolling.count == 2 ? rolling[1] : []
            let status = rolling[0].withUnsafeBufferPointer { left in
                right.withUnsafeBufferPointer { right in
                    smoothed.withUnsafeBufferPointer { previous in
                        result.withUnsafeMutableBufferPointer { output in
                            rustAudioStereoSpectrum(left.baseAddress!, right.isEmpty ? nil : right.baseAddress,
                                                    left.count, basic.mSampleRate, previous.baseAddress!, output.baseAddress!)
                        }
                    }
                }
            }
            guard status == 0 else { return }
            smoothed = result
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.stream === stream, self.enabled, self.playing, self.lighting else { return }
                guard !audioLevelsExpired(last: now, now: ProcessInfo.processInfo.systemUptime) else { return }
                self.lastDelivery = now
                self.retry.reset()
                self.levels = result
                if self.status != "시스템 오디오에 반응 중" { self.status = "시스템 오디오에 반응 중" }
            }
        }
    }
}
