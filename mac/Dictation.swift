import AppKit
import AVFoundation
import Speech
import ApplicationServices

enum DictationShortcut: String, CaseIterable, Hashable {
    case fn, controlOption, controlShift
    var label: String {
        switch self {
        case .fn: return "Fn(지구본)"
        case .controlOption: return "Control + Option"
        case .controlShift: return "Control + Shift"
        }
    }
    var requiredFlags: NSEvent.ModifierFlags {
        switch self {
        case .fn: return .function
        case .controlOption: return [.control, .option]
        case .controlShift: return [.control, .shift]
        }
    }
    func matches(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.intersection([.function, .control, .option, .shift, .command]) == requiredFlags
    }
}

/// macOS bridge for push-to-talk. Speech is explicitly restricted to the
/// on-device recognizer and the user's clipboard is never overwritten.
final class DictationController: NSObject, ObservableObject {
    @Published var status = "받아쓰기 준비 전"
    @Published var lastText = ""
    @Published var enabled = false
    @Published private(set) var autoStart: Bool
    @Published private(set) var languageID: String
    @Published private(set) var shortcut: DictationShortcut
    private let preferences: UserDefaults
    private var recognizer: SFSpeechRecognizer?
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var held = false
    private var recording = false
    private var finalReady = false
    private var generation = 0
    private var permissionGeneration = 0
    private var permissionInProgress = false
    private var focusAtStart: AXUIElement?
    private var finalizationTimeout: DispatchWorkItem?
    private var finalizationPending = false

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        self.autoStart = preferences.object(forKey: "rium.dictation.autostart") as? Bool ?? true
        let saved = preferences.string(forKey: "rium.dictation.language") ?? "ko-KR"
        let selected = Self.languageIDs.contains(saved) ? saved : "ko-KR"
        self.languageID = selected
        self.shortcut = DictationShortcut(rawValue: preferences.string(forKey: "rium.dictation.shortcut") ?? "") ?? .fn
        self.recognizer = SFSpeechRecognizer(locale: Locale(identifier: selected))
        super.init()
    }

    static let languageIDs: [String] = {
        let identifiers = Set(SFSpeechRecognizer.supportedLocales().map(\.identifier)).union(["ko-KR"])
        return identifiers.sorted { languageName($0).localizedStandardCompare(languageName($1)) == .orderedAscending }
    }()
    static func languageName(_ id: String) -> String {
        Locale(identifier: "ko_KR").localizedString(forIdentifier: id) ?? id
    }
    func setLanguage(_ id: String) {
        guard id != languageID, Self.languageIDs.contains(id) else { return }
        disable(persist: false)
        languageID = id; preferences.set(id, forKey: "rium.dictation.language")
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: id))
        status = "받아쓰기 언어 변경됨"
        restoreIfAuthorized()
    }
    func setShortcut(_ shortcut: DictationShortcut) {
        guard shortcut != self.shortcut else { return }
        disable(persist: false)
        self.shortcut = shortcut; preferences.set(shortcut.rawValue, forKey: "rium.dictation.shortcut")
        status = "받아쓰기 단축키 변경됨"
        restoreIfAuthorized()
    }

    func setAutoStart(_ enabled: Bool) {
        autoStart = enabled; preferences.set(enabled, forKey: "rium.dictation.autostart")
        if enabled { restoreIfAuthorized() } else { disable(persist: false) }
    }

    var accessStatus: (accessibility: Bool, speech: Bool, microphone: Bool) {
        (AXIsProcessTrusted(), SFSpeechRecognizer.authorizationStatus() == .authorized, AVCaptureDevice.authorizationStatus(for: .audio) == .authorized)
    }

    /// Polling only reads existing grants. It must never trigger a macOS
    /// permission dialog or install a listener after the user turns it off.
    func restoreIfAuthorized() {
        guard autoStart || enabled else { return }
        let (trusted, speechAllowed, microphoneAllowed) = accessStatus
        if enabled && (!trusted || !speechAllowed || !microphoneAllowed) {
            disable(persist: false)
            status = "받아쓰기 권한을 다시 확인해 주세요"
        }
        guard autoStart, !enabled, !permissionInProgress else { return }
        guard trusted, speechAllowed, microphoneAllowed else {
            if status != "받아쓰기 권한을 다시 확인해 주세요" { status = "받아쓰기 권한을 다시 확인해 주세요" }
            return
        }
        guard let recognizer = recognizer, recognizer.supportsOnDeviceRecognition else { status = "선택한 언어의 기기 내 받아쓰기를 사용할 수 없습니다"; return }
        installMonitors()
    }

    func prepare() {
        autoStart = true; preferences.set(true, forKey: "rium.dictation.autostart")
        permissionGeneration += 1; permissionInProgress = false; let permissionRequest = permissionGeneration
        guard AXIsProcessTrusted() else { status = "손쉬운 사용 권한을 설정한 뒤 다시 준비해 주세요"; return }
        guard let recognizer = recognizer, recognizer.supportsOnDeviceRecognition else { status = "선택한 언어의 기기 내 받아쓰기를 사용할 수 없습니다"; return }
        permissionInProgress = true
        status = "음성 인식 권한 확인 중"
        SFSpeechRecognizer.requestAuthorization { [weak self] auth in
            DispatchQueue.main.async {
                guard let self = self, self.autoStart, self.permissionGeneration == permissionRequest else { return }
                guard auth == .authorized else { self.permissionInProgress = false; self.status = "음성 인식 권한이 필요합니다"; return }
                AVCaptureDevice.requestAccess(for: .audio) { allowed in
                    DispatchQueue.main.async {
                        guard self.autoStart, self.permissionGeneration == permissionRequest else { return }
                        self.permissionInProgress = false
                        guard allowed else { self.status = "마이크 권한이 필요합니다"; return }
                        self.installMonitors()
                    }
                }
            }
        }
    }

    func disable(persist: Bool = true) {
        if persist { autoStart = false; preferences.set(false, forKey: "rium.dictation.autostart") }
        generation += 1; permissionGeneration += 1; permissionInProgress = false; cancelFinalizationTimeout()
        if let monitor = globalMonitor { NSEvent.removeMonitor(monitor) }; globalMonitor = nil
        if let monitor = localMonitor { NSEvent.removeMonitor(monitor) }; localMonitor = nil
        if recording { engine.stop(); engine.inputNode.removeTap(onBus: 0); recording = false }
        task?.cancel(); task = nil; request = nil; held = false; enabled = false; status = "받아쓰기 꺼짐"
    }

    private func installMonitors() {
        guard !enabled else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let flags = event.modifierFlags
            DispatchQueue.main.async { guard let self = self else { return }; self.handle(self.shortcut.matches(flags)) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            if let self = self { self.handle(self.shortcut.matches(event.modifierFlags)) }; return event
        }
        guard globalMonitor != nil, localMonitor != nil else { disable(persist: false); status = "단축키 감시를 시작할 수 없습니다"; return }
        enabled = true; status = "\(shortcut.label)을 누른 채 말하고 놓으세요"
    }

    private func handle(_ pressed: Bool) {
        guard enabled, pressed != held else { return }; held = pressed
        if pressed { start() } else if recording { finish() }
    }

    private func focusedElement() -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value = value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func start() {
        guard !recording, task == nil else { status = "이전 받아쓰기를 마치는 중입니다"; return }
        guard let focused = focusedElement() else { status = "입력할 텍스트 필드를 선택해 주세요"; return }
        var subrole: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(focused, kAXSubroleAttribute as CFString, &subrole)
        guard (subrole as? String) != "AXSecureTextField" else { status = "보안 입력란에서는 받아쓰기를 사용하지 않습니다"; return }
        guard let recognizer = recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else { status = "기기 내 음성 인식을 사용할 수 없습니다"; return }
        let input = engine.inputNode, format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { status = "마이크 입력을 사용할 수 없습니다"; return }
        let request = SFSpeechAudioBufferRecognitionRequest(); request.requiresOnDeviceRecognition = true; request.shouldReportPartialResults = true
        generation += 1; let currentGeneration = generation
        self.request = request; focusAtStart = focused; lastText = ""; recording = true; finalReady = false
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        do { engine.prepare(); try engine.start() }
        catch { input.removeTap(onBus: 0); self.request = nil; recording = false; focusAtStart = nil; status = "마이크를 시작할 수 없습니다"; return }
        status = "듣는 중…"
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard self.generation == currentGeneration else { return }
                if let result = result { self.lastText = result.bestTranscription.formattedString }
                if let result = result, result.isFinal { self.finalReady = true; if !self.recording { self.complete() } }
                else if error != nil {
                    if self.recording { self.engine.stop(); self.engine.inputNode.removeTap(onBus: 0); self.recording = false }
                    self.cancelFinalizationTimeout()
                    self.request = nil; self.task = nil; self.focusAtStart = nil
                    self.status = self.lastText.isEmpty ? "음성 인식에 실패했습니다" : "입력하지 못했습니다. 텍스트를 복사해 주세요"
                }
            }
        }
    }

    private func finish() {
        guard recording else { return }
        engine.stop(); engine.inputNode.removeTap(onBus: 0); recording = false
        request?.endAudio(); status = "변환 중…"
        if finalReady { complete() } else { scheduleFinalizationTimeout() }
    }

    private func complete() {
        cancelFinalizationTimeout()
        if recording { engine.stop(); engine.inputNode.removeTap(onBus: 0); recording = false }
        defer { request = nil; task = nil; focusAtStart = nil }
        guard !lastText.isEmpty else { status = "인식된 음성이 없습니다"; return }
        guard let target = focusAtStart, let current = focusedElement(), CFEqual(target, current) else { status = "입력란이 바뀌었습니다. 텍스트를 복사해 주세요"; return }
        let result = AXUIElementSetAttributeValue(target, kAXSelectedTextAttribute as CFString, lastText as CFString)
        status = result == .success ? "받아쓰기 완료" : "자동 입력을 지원하지 않습니다. 텍스트를 복사해 주세요"
    }

    private func cancelFinalizationTimeout() {
        finalizationTimeout?.cancel(); finalizationTimeout = nil; finalizationPending = false
    }
    private func scheduleFinalizationTimeout(after delay: TimeInterval = 8) {
        cancelFinalizationTimeout(); finalizationPending = true
        let expectedGeneration = generation
        let timeout = DispatchWorkItem { [weak self] in
            guard let self = self, self.finalizationPending, self.generation == expectedGeneration, !self.recording else { return }
            self.finalizationPending = false; self.finalizationTimeout = nil; self.generation += 1
            self.task?.cancel(); self.task = nil; self.request = nil; self.focusAtStart = nil
            self.status = self.lastText.isEmpty ? "음성 변환 시간이 초과됐습니다. 다시 시도해 주세요" : "음성 변환 시간이 초과됐습니다. 텍스트를 복사하거나 다시 시도해 주세요"
        }
        finalizationTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: timeout)
    }
}

extension DictationController {
    /// Exercise cancellation and stale-callback protection without opening the microphone.
    static func testFinalizationTimeout() -> Bool {
        let controller = DictationController()
        controller.lastText = "시험 문장"
        controller.scheduleFinalizationTimeout(after: 0.05)
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        guard !controller.finalizationPending, controller.lastText == "시험 문장", controller.status.contains("텍스트를 복사"), controller.generation == 1 else { return false }
        controller.status = "대기"; controller.scheduleFinalizationTimeout(after: 0.05); controller.cancelFinalizationTimeout()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        return controller.status == "대기" && controller.generation == 1 && !controller.finalizationPending
    }
}
