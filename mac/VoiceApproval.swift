import AVFoundation
import Combine
import Foundation
import Speech

@_silgen_name("rium_voice_classify")
private func rustVoiceClassify(_ transcript: UnsafePointer<UInt8>?, _ transcriptLength: Int,
                               _ allow: UnsafePointer<UInt8>?, _ allowLength: Int,
                               _ deny: UnsafePointer<UInt8>?, _ denyLength: Int,
                               _ open: UnsafePointer<UInt8>?, _ openLength: Int) -> Int32

enum VoiceApprovalAnswer: Equatable { case allow, deny, open }

/// One explicitly started on-device utterance. This object only returns an
/// interpretation; its caller owns request identity and decision delivery.
final class VoiceApprovalController: ObservableObject {
    @Published private(set) var active = false
    @Published private(set) var status = ""
    @Published private(set) var owner: String?
    @Published private(set) var inputLevel = 0.0
    private lazy var engine = AVAudioEngine()
    private var task: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var timer: DispatchWorkItem?
    private var partialTimer: DispatchWorkItem?
    private var generation = 0
    private var tapInstalled = false
    private var audioEnded = false
    private var callback: ((VoiceApprovalAnswer?) -> Void)?

    static var hasAuthorization: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    /// Only called when the user enables voice answers in Settings.
    func preparePermissions() {
        guard !active else { return }
        generation += 1; let expected = generation
        owner = "authorization"; active = true; status = "음성 권한 확인 중…"
        SFSpeechRecognizer.requestAuthorization { [weak self] authorization in
            DispatchQueue.main.async {
                guard let self = self, self.active, self.generation == expected else { return }
                guard authorization == .authorized else { self.cancel(); self.status = "음성 인식 권한이 필요합니다"; return }
                AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                    DispatchQueue.main.async {
                        guard let self = self, self.active, self.generation == expected else { return }
                        self.cancel(); self.status = granted ? "음성 권한이 허용되었습니다" : "마이크 권한이 필요합니다"
                    }
                }
            }
        }
    }

    func begin(owner: String, language: String, allow: String, deny: String, open: String,
               automatic: Bool = false,
               completion: @escaping (VoiceApprovalAnswer?) -> Void) {
        guard !active else { return }
        if automatic && !Self.hasAuthorization { return }
        generation += 1
        let expected = generation
        self.owner = owner; callback = completion; active = true; status = "음성 인식 권한 확인 중…"
        if automatic { start(language: language, allow: allow, deny: deny, open: open, expected: expected, automatic: true); return }
        SFSpeechRecognizer.requestAuthorization { [weak self] authorization in
            DispatchQueue.main.async {
                guard let self = self, self.generation == expected, self.active else { return }
                guard authorization == .authorized else { self.complete(nil, status: "음성 인식 권한이 필요합니다"); return }
                AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                    DispatchQueue.main.async {
                        guard let self = self, self.generation == expected, self.active else { return }
                        guard granted else { self.complete(nil, status: "마이크 권한이 필요합니다"); return }
                        self.start(language: language, allow: allow, deny: deny, open: open, expected: expected, automatic: false)
                    }
                }
            }
        }
    }

    private func start(language: String, allow: String, deny: String, open: String, expected: Int, automatic: Bool) {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language)),
              recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            complete(nil, status: "기기 내 음성 인식을 사용할 수 없습니다"); return
        }
        let input = engine.inputNode, format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            complete(nil, status: "마이크 입력을 사용할 수 없습니다"); return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = automatic
        self.request = request; audioEnded = false
        var levelFrames = 0
        let levelInterval = max(1, Int(format.sampleRate / 15))
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            levelFrames += Int(buffer.frameLength)
            guard levelFrames >= levelInterval else { return }
            levelFrames = 0
            guard let samples = buffer.floatChannelData?.pointee else { return }
            let count = min(1024, Int(buffer.frameLength)), stride = Int(buffer.stride)
            guard count > 0 else { return }
            var sum = 0.0
            for index in 0..<count { let value = Double(samples[index * stride]); sum += value * value }
            let level = sqrt(sum / Double(count)) * 8
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.active, self.generation == expected else { return }
                self.inputLevel = level.isFinite ? min(1, level) : 0
            }
        }
        tapInstalled = true
        do { engine.prepare(); try engine.start() }
        catch { complete(nil, status: "마이크를 시작할 수 없습니다"); return }
        status = "말씀해 주세요…"
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal == true
            DispatchQueue.main.async {
                guard let self = self, self.active, self.generation == expected else { return }
                if let text = text {
                    let answer = Self.classify(text, allow: allow, deny: deny, open: open)
                    self.partialTimer?.cancel(); self.partialTimer = nil
                    if isFinal { self.complete(answer, status: answer.map { _ in "음성 답변 인식됨" } ?? "답변을 알아듣지 못했습니다") }
                    else if automatic, let answer = answer {
                        // shortcut: stability delay awaits comparison with the reference voice detector.
                        let stable = DispatchWorkItem { [weak self] in
                            guard let self = self, self.active, self.generation == expected else { return }
                            self.complete(answer, status: "음성 답변 인식됨")
                        }
                        self.partialTimer = stable
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75, execute: stable)
                    }
                    if error != nil && !isFinal { self.complete(nil, status: "음성 인식에 실패했습니다") }
                } else if error != nil { self.complete(nil, status: "음성 인식에 실패했습니다") }
            }
        }
        let stop = DispatchWorkItem { [weak self] in
            guard let self = self, self.active, self.generation == expected else { return }
            self.stopAudio()
            self.status = "음성 변환 중…"
            let timeout = DispatchWorkItem { [weak self] in
                guard let self = self, self.active, self.generation == expected else { return }
                self.complete(nil, status: "음성 변환 시간이 초과됐습니다")
            }
            self.timer = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timeout)
        }
        timer = stop
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: stop)
    }

    func cancel() {
        generation += 1; timer?.cancel(); timer = nil; partialTimer?.cancel(); partialTimer = nil
        stopAudio(); task?.cancel(); task = nil; request = nil
        callback = nil; active = false; owner = nil; status = ""; inputLevel = 0
    }

    func cancel(owner: String) { if self.owner == owner { cancel() } }

    private func stopAudio() {
        if tapInstalled {
            if engine.isRunning { engine.stop() }
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if let request = request, !audioEnded { audioEnded = true; request.endAudio() }
    }

    private func complete(_ answer: VoiceApprovalAnswer?, status: String) {
        let completion = callback
        cancel()
        self.status = status
        completion?(answer)
    }

    private static func classify(_ text: String, allow: String, deny: String, open: String) -> VoiceApprovalAnswer? {
        // Speech and text fields can supply canonically equivalent Hangul or
        // accented characters in different Unicode representations.
        let t = Data(text.precomposedStringWithCanonicalMapping.utf8)
        let a = Data(allow.precomposedStringWithCanonicalMapping.utf8)
        let d = Data(deny.precomposedStringWithCanonicalMapping.utf8)
        let o = Data(open.precomposedStringWithCanonicalMapping.utf8)
        let result = t.withUnsafeBytes { tb in a.withUnsafeBytes { ab in d.withUnsafeBytes { db in o.withUnsafeBytes { ob in
            rustVoiceClassify(tb.bindMemory(to: UInt8.self).baseAddress, tb.count,
                              ab.bindMemory(to: UInt8.self).baseAddress, ab.count,
                              db.bindMemory(to: UInt8.self).baseAddress, db.count,
                              ob.bindMemory(to: UInt8.self).baseAddress, ob.count)
        } } } }
        switch result { case 1: return .allow; case 2: return .deny; case 3: return .open; default: return nil }
    }
}
