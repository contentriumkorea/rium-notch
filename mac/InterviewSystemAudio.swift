import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit
import Speech

// Keep a short, bounded bridge while the on-device recognizer restarts.
struct InterviewAudioBacklog<Element> {
    private var samples: [(Element, Int, Int)] = []
    private var frameCount = 0
    private var byteCount = 0
    private let maxFrames = 48_000
    private let maxBytes = 512 * 1024
    private let maxBuffers = 32

    mutating func append(_ sample: Element, frames: Int, bytes: Int) {
        guard frames > 0, frames <= maxFrames, bytes > 0, bytes <= maxBytes else { return }
        while !samples.isEmpty && (samples.count >= maxBuffers || frameCount + frames > maxFrames || byteCount + bytes > maxBytes) {
            let removed = samples.removeFirst()
            frameCount -= removed.1; byteCount -= removed.2
        }
        samples.append((sample, frames, bytes))
        frameCount += frames; byteCount += bytes
    }
    mutating func takeAll() -> [Element] {
        let result = samples.map { $0.0 }
        clear()
        return result
    }
    mutating func clear() {
        samples.removeAll(); frameCount = 0; byteCount = 0
    }
}

// Captures system audio only. Deepgram is used solely when explicitly selected.
final class InterviewSystemAudio: NSObject, SCStreamOutput, SCStreamDelegate {
    var onText: ((String, Bool) -> Void)?
    var onStatus: ((String) -> Void)?
    private let audioQueue = DispatchQueue(label: "app.rium.notch.interview.system-audio", qos: .userInitiated)
    private var stream: SCStream?
    private var task: SFSpeechRecognitionTask?
    private var generation = 0
    private var recognitionCycle = 0
    private var restart: DispatchWorkItem?
    private var startTimeout: DispatchWorkItem?
    private var failures = 0
    // These are accessed only on audioQueue.
    private var audioStream: SCStream?
    private var audioRequest: SFSpeechAudioBufferRecognitionRequest?
    private var bufferingForRestart = false
    private var audioBacklog = InterviewAudioBacklog<CMSampleBuffer>()
    private var audioDeepgram: InterviewDeepgram?

    func start(language: String, provider: String) {
        stop()
        let key: String?
        if provider == "deepgram" {
            guard let stored = InterviewCredentialStore.read(account: "deepgram"), !stored.isEmpty else {
                onStatus?("설정에서 Deepgram API 키를 저장해 주세요."); return
            }
            key = stored
        } else { key = nil }
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            onStatus?("상대 음성을 인식하려면 화면 및 시스템 오디오 녹음 권한이 필요합니다."); return
        }
        generation += 1; let expected = generation
        failures = 0; onStatus?("시스템 오디오 연결 중…")
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, audioCaptureStartStillPending(request: expected, generation: self.generation,
                                                         starting: self.startTimeout != nil) else { return }
            self.stop(); self.onStatus?("시스템 오디오 연결 시간이 초과됐습니다. 다시 시도해 주세요.")
        }
        startTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: timeout)
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { [weak self] content, error in
            DispatchQueue.main.async {
                guard let self = self, self.generation == expected else { return }
                guard error == nil, let display = content?.displays.first else {
                    self.stop(); self.onStatus?("시스템 오디오를 연결하지 못했습니다."); return
                }
                let config = SCStreamConfiguration()
                config.capturesAudio = true; config.excludesCurrentProcessAudio = true
                config.sampleRate = 48000; config.channelCount = 2
                config.width = 2; config.height = 2; config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
                let candidate = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: config, delegate: self)
                do { try candidate.addStreamOutput(self, type: .audio, sampleHandlerQueue: self.audioQueue) }
                catch { self.stop(); self.onStatus?("시스템 오디오를 준비하지 못했습니다."); return }
                self.stream = candidate
                self.audioQueue.async { [weak self, candidate] in
                    guard let self = self else { return }
                    self.audioStream = candidate
                    if let key = key {
                        let client = InterviewDeepgram(queue: self.audioQueue, onText: { [weak self, weak candidate] text, final in
                            DispatchQueue.main.async {
                                guard let self = self, let candidate = candidate, self.generation == expected, self.stream === candidate else { return }
                                self.onText?(text, final)
                            }
                        }, onFailure: { [weak self, weak candidate] in
                            DispatchQueue.main.async {
                                guard let self = self, let candidate = candidate, self.generation == expected, self.stream === candidate else { return }
                                self.stop(); self.onStatus?("Deepgram 연결 또는 음성 형식을 확인해 주세요.")
                            }
                        })
                        self.audioDeepgram = client
                        if !client.start(key: key, language: language) {
                            DispatchQueue.main.async { [weak self, weak candidate] in
                                guard let self = self, let candidate = candidate, self.generation == expected, self.stream === candidate else { return }
                                self.stop(); self.onStatus?("Deepgram 연결을 준비하지 못했습니다.")
                            }
                        }
                    }
                }
                if key == nil && !self.startRecognizer(language: language, generation: expected) { self.stop(); return }
                candidate.startCapture { [weak self, candidate] error in
                    DispatchQueue.main.async {
                        guard let self = self, self.generation == expected, self.stream === candidate else {
                            candidate.stopCapture(completionHandler: { _ in }); return
                        }
                        if error != nil { self.stop(); self.onStatus?("시스템 오디오를 시작하지 못했습니다.") }
                        else {
                            self.startTimeout?.cancel(); self.startTimeout = nil
                            self.onStatus?("시스템 오디오를 듣는 중입니다.")
                        }
                    }
                }
            }
        }
    }

    private func startRecognizer(language: String, generation expected: Int) -> Bool {
        guard generation == expected, stream != nil,
              let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language)),
              recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            onStatus?("상대 음성의 기기 내 인식을 사용할 수 없습니다."); return false
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true; request.shouldReportPartialResults = true
        recognitionCycle += 1; let cycle = recognitionCycle
        let started = ProcessInfo.processInfo.systemUptime
        var hadSpeech = false
        audioQueue.async { [weak self, request] in
            guard let self else { return }
            self.audioRequest = request
            for buffer in self.audioBacklog.takeAll() { request.appendAudioSampleBuffer(buffer) }
            self.bufferingForRestart = false
        }
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self = self, self.generation == expected, self.recognitionCycle == cycle, self.stream != nil else { return }
                if let result = result {
                    let text = result.bestTranscription.formattedString
                    if !text.isEmpty { hadSpeech = true; self.failures = 0 }
                    self.onText?(text, result.isFinal)
                    if result.isFinal {
                        self.restartRecognizer(language: language, generation: expected,
                                               failed: !hadSpeech && ProcessInfo.processInfo.systemUptime - started < 2)
                        return
                    }
                }
                if error != nil {
                    self.onText?("", true)
                    self.restartRecognizer(language: language, generation: expected, failed: true)
                }
            }
        }
        return true
    }

    private func clearRecognizer(buffering: Bool = false) {
        recognitionCycle += 1
        task?.cancel(); task = nil
        audioQueue.async { [weak self] in
            guard let self else { return }
            self.audioRequest?.endAudio(); self.audioRequest = nil
            self.bufferingForRestart = buffering
            if !buffering { self.audioBacklog.clear() }
        }
    }

    private func restartRecognizer(language: String, generation expected: Int, failed: Bool) {
        guard generation == expected, stream != nil else { return }
        failures = failed ? failures + 1 : 0
        clearRecognizer(buffering: true)
        guard failures < 3 else { stop(); onStatus?("상대 음성 인식이 반복해서 중단됐습니다."); return }
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.generation == expected, self.stream != nil else { return }
            self.restart = nil
            if !self.startRecognizer(language: language, generation: expected) { self.stop() }
        }
        restart?.cancel(); restart = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    func stop() {
        generation += 1
        startTimeout?.cancel(); startTimeout = nil
        restart?.cancel(); restart = nil
        clearRecognizer()
        let previous = stream; stream = nil
        if previous != nil { onText?("", true) }
        audioQueue.async { [self, previous] in
            guard self.audioStream === previous else { return }
            self.audioStream = nil
            self.audioDeepgram?.stop(); self.audioDeepgram = nil
        }
        previous?.stopCapture(completionHandler: { _ in })
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.stream === stream else { return }
            self.stop(); self.onStatus?("시스템 오디오 연결이 중단됐습니다.")
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, audioStream === stream, CMSampleBufferDataIsReady(sampleBuffer) else { return }
        if let request = audioRequest {
            request.appendAudioSampleBuffer(sampleBuffer)
        } else if bufferingForRestart {
            let frames = CMSampleBufferGetNumSamples(sampleBuffer)
            let bytes = CMSampleBufferGetDataBuffer(sampleBuffer).map { CMBlockBufferGetDataLength($0) }
                ?? CMSampleBufferGetTotalSampleSize(sampleBuffer)
            audioBacklog.append(sampleBuffer, frames: frames, bytes: bytes)
        }
        audioDeepgram?.consume(sampleBuffer)
    }
}
