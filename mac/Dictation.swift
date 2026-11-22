import AppKit
import AVFoundation
import Speech
import ApplicationServices
import SwiftUI
import Combine
import CryptoKit
import OSLog

@_silgen_name("rium_dictation_selection_matches")
private func dictationSelectionMatches(_ startLocation: Int64, _ startLength: Int64, _ currentLocation: Int64, _ currentLength: Int64) -> Int32
@_silgen_name("rium_dictation_modifier_action")
private func dictationModifierAction(_ current: UInt64, _ required: UInt64, _ holding: Int32, _ blocked: Int32) -> Int32

private let dictationLog = Logger(subsystem: "app.rium.notch", category: "Dictation")
private let dictationModifiers: NSEvent.ModifierFlags = [.function, .control, .option, .shift, .command]

private enum DictationModifierAction: Int32 { case wait, start, finish, cancel }

struct DictationAccess: Equatable {
    let accessibility: Bool
    let speech: SFSpeechRecognizerAuthorizationStatus
    let microphone: AVAuthorizationStatus
    let inputMonitoring: Bool

    static func current() -> Self {
        Self(accessibility: AXIsProcessTrusted(), speech: SFSpeechRecognizer.authorizationStatus(),
             microphone: AVCaptureDevice.authorizationStatus(for: .audio),
             inputMonitoring: CGPreflightListenEventAccess())
    }

    var canTryShortcutCapture: Bool { accessibility || inputMonitoring }

    func missingMessage(requiresAccessibility: Bool = true) -> String? {
        var missing: [String] = []
        if requiresAccessibility && !accessibility { missing.append("손쉬운 사용") }
        if speech != .authorized { missing.append("음성 인식") }
        if microphone != .authorized { missing.append("마이크") }
        return missing.isEmpty ? nil : "\(missing.joined(separator: " · ")) 권한이 필요합니다"
    }
}

enum DictationPermissionPrompt: Equatable {
    case speech, microphone

    func needsRequest(_ access: DictationAccess) -> Bool {
        switch self {
        case .speech: return access.speech == .notDetermined
        case .microphone: return access.microphone == .notDetermined
        }
    }

    var settingsAnchor: String {
        switch self {
        case .speech: return "Privacy_SpeechRecognition"
        case .microphone: return "Privacy_Microphone"
        }
    }

    var requestStatus: String {
        switch self {
        case .speech: return "음성 인식 권한 요청 중"
        case .microphone: return "마이크 권한 요청 중"
        }
    }

    func request(_ completed: @escaping () -> Void) {
        switch self {
        case .speech: SFSpeechRecognizer.requestAuthorization { _ in completed() }
        case .microphone: AVCaptureDevice.requestAccess(for: .audio) { _ in completed() }
        }
    }

    static func activate(_ permission: Self, needsRequest: Bool, request: (Self) -> Void,
                         openSettings: (String) -> Void) {
        if needsRequest { request(permission) }
        else { openSettings(permission.settingsAnchor) }
    }
}

private enum DictationPermissionStep: Equatable {
    case request(DictationPermissionPrompt), accessibility, settings(String), ready

    static func next(accessibility: Bool, speech: SFSpeechRecognizerAuthorizationStatus,
                     microphone: AVAuthorizationStatus) -> Self {
        if speech == .notDetermined { return .request(.speech) }
        if microphone == .notDetermined { return .request(.microphone) }
        if !accessibility { return .accessibility }
        if speech != .authorized { return .settings(DictationPermissionPrompt.speech.settingsAnchor) }
        if microphone != .authorized { return .settings(DictationPermissionPrompt.microphone.settingsAnchor) }
        return .ready
    }
}

struct RecordedDictationShortcut: Hashable {
    let keyCode: UInt16?
    let modifiers: UInt64
    let keyLabel: String

    init?(keyCode: UInt16?, modifiers: UInt64, keyLabel: String) {
        let accepted: NSEvent.ModifierFlags = [.function, .control, .option, .shift, .command]
        let mask = UInt64(accepted.rawValue)
        guard modifiers != 0, modifiers & ~mask == 0, keyLabel.count <= 16, keyLabel.utf8.count <= 128,
              !keyLabel.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        if let code = keyCode {
            let allowed = [NSEvent.ModifierFlags.control, .option, .command].map { UInt64($0.rawValue) }
            guard code <= 126, !(53...63).contains(code), allowed.contains(modifiers), !keyLabel.isEmpty else { return nil }
        } else if modifiers.nonzeroBitCount > 2 || !keyLabel.isEmpty { return nil }
        self.keyCode = keyCode; self.modifiers = modifiers; self.keyLabel = keyLabel
    }

    var label: String {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        let names: [(NSEvent.ModifierFlags, String)] = [(.control, "Control"), (.option, "Option"), (.shift, "Shift"), (.command, "Command"), (.function, "Fn(지구본)")]
        return (names.compactMap { flags.contains($0.0) ? $0.1 : nil } + (keyCode == nil ? [] : [keyLabel])).joined(separator: " + ")
    }
    func matchesKeyDown(keyCode: Int64, flags: CGEventFlags, repeated: Bool) -> Bool {
        guard let expected = self.keyCode else { return false }
        return !repeated && keyCode == Int64(expected) && matchesModifiers(flags)
    }
    func matchesModifiers(_ flags: CGEventFlags) -> Bool {
        let mask: CGEventFlags = [.maskSecondaryFn, .maskControl, .maskAlternate, .maskShift, .maskCommand]
        return flags.intersection(mask).rawValue == modifiers
    }
}

func recordedShortcutKeyLabel(code: Int64, characters: String?) -> String {
    let special: [Int64: String] = [36: "Return", 48: "Tab", 49: "스페이스 바", 51: "Delete", 64: "F17",
                                    79: "F18", 80: "F19", 90: "F20", 96: "F5", 97: "F6", 98: "F7", 99: "F3",
                                    100: "F8", 101: "F9", 103: "F11", 105: "F13", 106: "F16", 107: "F14",
                                    109: "F10", 110: "단축 메뉴 키", 111: "F12", 113: "F15", 114: "도움말 키",
                                    115: "Home", 116: "Page Up", 117: "앞으로 삭제", 118: "F4", 119: "End",
                                    120: "F2", 121: "Page Down", 122: "F1", 123: "왼쪽 방향키", 124: "오른쪽 방향키",
                                    125: "아래 방향키", 126: "위쪽 방향키"]
    if let label = special[code] { return label }
    let text = characters?.uppercased() ?? ""
    return !text.isEmpty && text.count <= 16 && text.utf8.count <= 128 &&
        !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) ? text : "키 \(code)"
}

enum DictationShortcut: Hashable {
    case fn, controlOption, controlShift, custom(RecordedDictationShortcut)
    static let allCases: [DictationShortcut] = [.fn, .controlOption, .controlShift]
    init?(rawValue: String) {
        switch rawValue {
        case "fn": self = .fn
        case "controlOption": self = .controlOption
        case "controlShift": self = .controlShift
        default:
            guard rawValue.utf8.count <= 512 else { return nil }
            let parts = rawValue.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 4, parts[0] == "custom", let code = UInt16(parts[1]), let flags = UInt64(parts[2]),
                  let bytes = Data(base64Encoded: String(parts[3])), let label = String(data: bytes, encoding: .utf8),
                  let recorded = RecordedDictationShortcut(keyCode: code == UInt16.max ? nil : code, modifiers: flags, keyLabel: label) else { return nil }
            self = .custom(recorded)
        }
    }
    var rawValue: String {
        switch self {
        case .fn: return "fn"
        case .controlOption: return "controlOption"
        case .controlShift: return "controlShift"
        case .custom(let value): return "custom:\(value.keyCode ?? UInt16.max):\(value.modifiers):\(Data(value.keyLabel.utf8).base64EncodedString())"
        }
    }
    var label: String {
        switch self {
        case .fn: return "Fn(지구본)"
        case .controlOption: return "Control + Option"
        case .controlShift: return "Control + Shift"
        case .custom(let value): return value.label
        }
    }
    var requiredFlags: NSEvent.ModifierFlags {
        switch self {
        case .fn: return .function
        case .controlOption: return [.control, .option]
        case .controlShift: return [.control, .shift]
        case .custom(let value): return NSEvent.ModifierFlags(rawValue: UInt(value.modifiers))
        }
    }
}

struct DictationShortcutPicker: View {
    @ObservedObject var controller: DictationController
    var title = "단축키"
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker(title, selection: Binding(get: { controller.shortcut }, set: { controller.setShortcut($0) })) {
                    ForEach(DictationShortcut.allCases, id: \.self) { Text($0.label).tag($0) }
                    if case .custom = controller.shortcut { Text(controller.shortcut.label).tag(controller.shortcut) }
                }
                Button(controller.capturingShortcut ? "기록 취소" : "직접 지정") {
                    if controller.capturingShortcut { controller.cancelShortcutCapture() }
                    else { controller.beginShortcutCapture() }
                }
            }
            if !controller.shortcutCaptureStatus.isEmpty {
                Text(controller.shortcutCaptureStatus).font(.caption).foregroundStyle(.secondary)
            }
        }
        .onDisappear { controller.cancelShortcutCapture() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in controller.cancelShortcutCapture() }
    }
}

private final class DictationPasteboard {
    private let board: NSPasteboard
    private let original: [NSPasteboardItem]
    private let temporaryChangeCount: Int

    init?(_ text: String, board: NSPasteboard) {
        let previousChangeCount = board.changeCount
        guard clipboardAllowsPreview(board) else { return nil }
        var original: [NSPasteboardItem] = []
        var remaining = 24 * 1024 * 1024
        for item in board.pasteboardItems ?? [] {
            let copy = NSPasteboardItem()
            for type in item.types {
                guard !type.rawValue.localizedCaseInsensitiveContains("promis"),
                      let data = item.data(forType: type), data.count <= remaining,
                      copy.setData(data, forType: type) else { return nil }
                remaining -= data.count
            }
            original.append(copy)
        }
        let temporary = NSPasteboardItem()
        guard temporary.setString(text, forType: .string),
              temporary.setData(Data(), forType: .init("org.nspasteboard.TransientType")),
              board.changeCount == previousChangeCount else { return nil }
        board.clearContents()
        guard board.writeObjects([temporary]) else {
            if !original.isEmpty { board.writeObjects(original) }
            return nil
        }
        self.board = board
        self.original = original
        temporaryChangeCount = board.changeCount
    }

    func restore() {
        guard board.changeCount == temporaryChangeCount else { return }
        board.clearContents()
        if !original.isEmpty { board.writeObjects(original) }
    }
}

/// macOS bridge for push-to-talk using the on-device recognizer.
final class DictationController: NSObject, ObservableObject {
    @Published var status = "받아쓰기 준비 전"
    @Published var lastText = ""
    @Published var enabled = false
    @Published private(set) var access = DictationAccess.current()
    @Published private(set) var assistantCaptureActive = false
    private var assistantCaptureCompletion: ((String?) -> Void)?
    @Published private(set) var autoStart: Bool
    @Published private(set) var languageID: String
    @Published private(set) var shortcut: DictationShortcut
    @Published private(set) var handsFreeEnabled: Bool
    @Published private(set) var capturingShortcut = false
    @Published private(set) var shortcutCaptureStatus = ""
    private let preferences: UserDefaults
    private var recognizer: SFSpeechRecognizer?
    private lazy var engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var monitorGeneration: UInt64 = 0
    private var held = false
    private var modifierChordBlocked = false
    private var screenLocked = false
    private var sleeping = false
    var sessionInactive: Bool { screenLocked || sleeping }
    private var handsFree = false
    private var consumedSpaceDown = false
    private var handsFreeTap: CFMachPort?
    private var handsFreeSource: CFRunLoopSource?
    private var customTap: CFMachPort?
    private var customSource: CFRunLoopSource?
    private var customKeyDown = false
    private var customKeyActive = false
    private var customKeyGeneration: UInt64 = 0
    private var captureTap: CFMachPort?
    private var captureSource: CFRunLoopSource?
    private var captureModifiers: UInt64 = 0
    private var captureInvalid = false
    private var captureFinishing = false
    private var captureGeneration: UInt64 = 0
    var onRecordingChange: ((Bool) -> Void)?
    var onFinalizationChange: ((Bool) -> Void)?
    var onWillStart: (() -> Void)?
    var onInputLevel: ((Double) -> Void)?
    private var recording = false {
        didSet {
            guard recording != oldValue else { return }
            onRecordingChange?(recording)
            if !recording { onInputLevel?(0) }
        }
    }
    private var finalReady = false
    private var generation = 0
    private var permissionGeneration = 0
    private var permissionInProgress = false
    private struct InsertionTarget {
        let element: AXUIElement
        let selection: InsertionSelection?
        let value: String?
    }
    private struct InsertionSelection {
        // shortcut: compare the text only for modest selections that expose their full contents.
        static let fingerprintLimit = 16_384
        let range: CFRange
        let fingerprint: SHA256.Digest?

        init(range: CFRange, selectedText: String?) {
            self.range = range
            if 1...Self.fingerprintLimit ~= range.length, let selectedText, selectedText.utf16.count == range.length {
                fingerprint = SHA256.hash(data: Data(selectedText.utf8))
            } else {
                fingerprint = nil
            }
        }

        func replacing(in value: String, with text: String) -> String? {
            let length = value.utf16.count
            guard range.location >= 0, range.location <= length,
                  range.length >= 0, range.length <= length - range.location,
                  let span = Range(NSRange(location: range.location, length: range.length), in: value) else { return nil }
            return value.replacingCharacters(in: span, with: text)
        }

        func matches(_ current: InsertionSelection?) -> Bool {
            guard let current,
                  dictationSelectionMatches(Int64(range.location), Int64(range.length),
                                           Int64(current.range.location), Int64(current.range.length)) == 1 else { return false }
            return fingerprint == nil || fingerprint == current.fingerprint
        }
    }
    private var targetAtStart: InsertionTarget?
    private var pendingPaste: DictationPasteboard?
    private var finalizationTimeout: DispatchWorkItem?
    private var finalizationPending = false {
        didSet { if finalizationPending != oldValue { onFinalizationChange?(finalizationPending) } }
    }

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        self.autoStart = preferences.object(forKey: "rium.dictation.autostart") as? Bool ?? true
        let saved = preferences.string(forKey: "rium.dictation.language") ?? "ko-KR"
        let selected = Self.languageIDs.contains(saved) ? saved : "ko-KR"
        self.languageID = selected
        self.shortcut = DictationShortcut(rawValue: preferences.string(forKey: "rium.dictation.shortcut") ?? "") ?? .fn
        self.handsFreeEnabled = preferences.bool(forKey: "rium.dictation.handsFree")
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

    func beginShortcutCapture() {
        guard !capturingShortcut, !sessionInactive else { return }
        if assistantCaptureActive { cancelAssistantCapture() }
        guard refreshAccess().canTryShortcutCapture || CGRequestListenEventAccess() else {
            shortcutCaptureStatus = "단축키 기록에는 입력 모니터링 권한이 필요합니다"; return
        }
        cancelDictation()
        held = false; handsFree = false; customKeyDown = false; customKeyActive = false; customKeyGeneration &+= 1
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << CGEventType.keyUp.rawValue) | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
            guard let context = context else { return Unmanaged.passUnretained(event) }
            let controller = Unmanaged<DictationController>.fromOpaque(context).takeUnretainedValue()
            return controller.captureShortcutEvent(type, event) ? nil : Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            shortcutCaptureStatus = "단축키 기록을 시작할 수 없습니다"; return
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap); shortcutCaptureStatus = "단축키 기록을 시작할 수 없습니다"; return
        }
        captureTap = tap; captureSource = source; captureModifiers = 0; captureInvalid = false; captureFinishing = false
        captureGeneration &+= 1
        capturingShortcut = true; shortcutCaptureStatus = "원하는 조합을 누르세요. Escape 키로 취소합니다."
        CFRunLoopAddSource(CFRunLoopGetMain(), source, CFRunLoopMode.commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func cancelShortcutCapture() {
        guard capturingShortcut || captureTap != nil else { return }
        captureGeneration &+= 1
        capturingShortcut = false; captureFinishing = false; captureModifiers = 0; captureInvalid = false
        if let source = captureSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, CFRunLoopMode.commonModes) }
        if let tap = captureTap { CFMachPortInvalidate(tap) }
        captureSource = nil; captureTap = nil; shortcutCaptureStatus = ""
    }

    private func captureShortcutEvent(_ type: CGEventType, _ event: CGEvent) -> Bool {
        guard capturingShortcut else { return false }
        let token = captureGeneration
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.capturingShortcut, self.captureGeneration == token else { return }
                self.cancelShortcutCapture(); self.shortcutCaptureStatus = "단축키 기록이 중단됐습니다"
            }
            return false
        }
        let mask: CGEventFlags = [.maskSecondaryFn, .maskControl, .maskAlternate, .maskShift, .maskCommand]
        let flags = event.flags.intersection(mask).rawValue
        if type == .flagsChanged {
            if flags == 0 {
                if !captureInvalid, captureModifiers != 0, !captureFinishing,
                   let value = RecordedDictationShortcut(keyCode: nil, modifiers: captureModifiers, keyLabel: "") {
                    captureFinishing = true
                    DispatchQueue.main.async { [weak self] in self?.finishShortcutCapture(value, generation: token) }
                }
                captureModifiers = 0; captureInvalid = false
            } else if flags.nonzeroBitCount > 2 { captureInvalid = true }
            else if !captureInvalid && flags.nonzeroBitCount >= captureModifiers.nonzeroBitCount { captureModifiers = flags }
            return false
        }
        guard type == .keyDown || type == .keyUp else { return false }
        guard type == .keyDown, !captureFinishing else { return true }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if code == 53 {
            captureFinishing = true
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.capturingShortcut, self.captureGeneration == token else { return }
                self.cancelShortcutCapture()
            }
            return true
        }
        let label = recordedShortcutKeyLabel(code: code, characters: NSEvent(cgEvent: event)?.charactersIgnoringModifiers)
        guard let key = UInt16(exactly: code), let value = RecordedDictationShortcut(keyCode: key, modifiers: flags, keyLabel: label) else {
            captureInvalid = true; shortcutCaptureStatus = "Control, Option 또는 Command 키 하나와 다른 키를 함께 누르세요"
            return true
        }
        captureFinishing = true
        DispatchQueue.main.async { [weak self] in self?.finishShortcutCapture(value, generation: token) }
        return true
    }

    private func finishShortcutCapture(_ value: RecordedDictationShortcut, generation token: UInt64) {
        guard capturingShortcut, captureGeneration == token else { return }
        let flags = NSEvent.ModifierFlags(rawValue: UInt(value.modifiers))
        let selected: DictationShortcut
        if value.keyCode == nil && flags == .function { selected = .fn }
        else if value.keyCode == nil && flags == [.control, .option] { selected = .controlOption }
        else if value.keyCode == nil && flags == [.control, .shift] { selected = .controlShift }
        else { selected = .custom(value) }
        cancelShortcutCapture(); setShortcut(selected)
        shortcutCaptureStatus = "단축키가 저장됐습니다"
    }

    func setAutoStart(_ enabled: Bool) {
        autoStart = enabled; preferences.set(enabled, forKey: "rium.dictation.autostart")
        if enabled { restoreIfAuthorized() } else { disable(persist: false) }
    }

    func setHandsFreeEnabled(_ enabled: Bool) {
        handsFreeEnabled = enabled
        preferences.set(enabled, forKey: "rium.dictation.handsFree")
        removeHandsFreeTap()
        if enabled && self.enabled { installHandsFreeTap() }
    }

    @discardableResult
    private func refreshAccess() -> DictationAccess {
        let current = DictationAccess.current()
        if current != access { access = current }
        return current
    }

    /// Polling only reads current grants. Explicit settings actions request them.
    func restoreIfAuthorized() {
        let current = refreshAccess()
        guard !assistantCaptureActive, !sessionInactive, !permissionInProgress, autoStart || enabled else { return }
        if let message = current.missingMessage() {
            if enabled { disable(persist: false) }
            if status != message { status = message }
            return
        }
        if enabled && handsFreeEnabled && handsFreeTap == nil && current.inputMonitoring { installHandsFreeTap() }
        if enabled, case .custom(let binding) = shortcut, binding.keyCode != nil,
           customTap == nil, current.inputMonitoring { installCustomTap() }
        guard autoStart, !enabled else { return }
        guard let recognizer, recognizer.supportsOnDeviceRecognition else {
            status = "선택한 언어의 기기 내 받아쓰기를 사용할 수 없습니다"
            return
        }
        installMonitors()
    }

    func prepare() {
        guard !assistantCaptureActive else { status = "개인 AI 음성 입력이 진행 중입니다"; return }
        guard !permissionInProgress, !sessionInactive else { return }
        autoStart = true
        preferences.set(true, forKey: "rium.dictation.autostart")
        permissionGeneration += 1
        advancePermissionSetup(generation: permissionGeneration)
    }

    func handlePermissionButton(_ permission: DictationPermissionPrompt) {
        guard !assistantCaptureActive, !permissionInProgress, !sessionInactive else { return }
        DictationPermissionPrompt.activate(permission, needsRequest: permission.needsRequest(refreshAccess()),
            request: { prompt in
                requestPermission(prompt) { [weak self] in self?.restoreIfAuthorized() }
            }, openSettings: Self.openPermissionSettings)
    }

    func openAccessibilitySettings() {
        if !refreshAccess().accessibility {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        }
        Self.openPermissionSettings("Privacy_Accessibility")
    }

    private func requestPermission(_ prompt: DictationPermissionPrompt, completed: @escaping () -> Void) {
        let expected = permissionGeneration
        permissionInProgress = true
        status = prompt.requestStatus
        prompt.request { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.permissionGeneration == expected else { return }
                self.permissionInProgress = false
                completed()
            }
        }
    }

    private func advancePermissionSetup(generation expected: Int) {
        guard autoStart, !sessionInactive, permissionGeneration == expected else { return }
        let current = refreshAccess()
        switch DictationPermissionStep.next(accessibility: current.accessibility,
                                           speech: current.speech, microphone: current.microphone) {
        case .request(let prompt):
            requestPermission(prompt) { [weak self] in
                guard let self else { return }
                if prompt.needsRequest(self.refreshAccess()) { self.restoreIfAuthorized() }
                else { self.advancePermissionSetup(generation: expected) }
            }
        case .accessibility:
            restoreIfAuthorized()
            openAccessibilitySettings()
        case .settings(let anchor):
            restoreIfAuthorized()
            Self.openPermissionSettings(anchor)
        case .ready:
            restoreIfAuthorized()
        }
    }

    private static func openPermissionSettings(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"),
           NSWorkspace.shared.open(url) { return }
        if let url = URL(string: "x-apple.systempreferences:") { NSWorkspace.shared.open(url) }
    }

    /// An explicit assistant request reuses the same on-device recognizer and microphone.
    func beginAssistantCapture(completion: @escaping (String?) -> Void) {
        guard !assistantCaptureActive, !recording, task == nil, !screenLocked, !sleeping,
              !permissionInProgress, !capturingShortcut, !held, !customKeyDown else { status = "다른 음성 입력이 진행 중입니다"; completion(nil); return }
        assistantCaptureActive = true; assistantCaptureCompletion = completion
        permissionGeneration += 1; let token = permissionGeneration
        status = "음성 인식 권한 확인 중"
        SFSpeechRecognizer.requestAuthorization { [weak self] authorization in
            DispatchQueue.main.async {
                guard let self, self.assistantCaptureActive, self.permissionGeneration == token else { return }
                guard authorization == .authorized else {
                    self.status = "음성 인식 권한이 필요합니다"; self.completeAssistantCapture(nil); return
                }
                AVCaptureDevice.requestAccess(for: .audio) { [weak self] allowed in
                    DispatchQueue.main.async {
                        guard let self, self.assistantCaptureActive, self.permissionGeneration == token else { return }
                        guard allowed else { self.status = "마이크 권한이 필요합니다"; self.completeAssistantCapture(nil); return }
                        self.start()
                        if !self.recording { self.completeAssistantCapture(nil) }
                    }
                }
            }
        }
    }

    func finishAssistantCapture() {
        guard assistantCaptureActive else { return }
        if recording { finish() } else { cancelDictation() }
    }

    func cancelAssistantCapture() {
        guard assistantCaptureActive else { return }
        cancelDictation()
    }

    private func completeAssistantCapture(_ text: String?) {
        let completion = assistantCaptureCompletion
        assistantCaptureCompletion = nil; assistantCaptureActive = false
        completion?(text)
    }

    func disable(persist: Bool = true) {
        if persist { autoStart = false; preferences.set(false, forKey: "rium.dictation.autostart") }
        generation += 1; permissionGeneration += 1; monitorGeneration &+= 1; permissionInProgress = false; cancelFinalizationTimeout()
        cancelShortcutCapture(); removeHandsFreeTap(); removeCustomTap()
        pendingPaste?.restore(); pendingPaste = nil
        if let monitor = globalMonitor { NSEvent.removeMonitor(monitor) }; globalMonitor = nil
        if let monitor = localMonitor { NSEvent.removeMonitor(monitor) }; localMonitor = nil
        if recording { engine.stop(); engine.inputNode.removeTap(onBus: 0); recording = false }
        task?.cancel(); task = nil; request = nil; targetAtStart = nil; finalReady = false
        held = false; enabled = false; status = "받아쓰기 꺼짐"
        if assistantCaptureActive { completeAssistantCapture(nil) }
    }

    private func installMonitors() {
        guard !enabled else { return }
        modifierChordBlocked = !NSEvent.modifierFlags.intersection(dictationModifiers).isEmpty
        monitorGeneration &+= 1; let monitorToken = monitorGeneration
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            let flags = event.modifierFlags
            let escape = event.type == .keyDown && event.keyCode == 53 && !event.isARepeat
            let modifiersChanged = event.type == .flagsChanged
            DispatchQueue.main.async {
                guard let self = self, self.monitorGeneration == monitorToken else { return }
                if escape { self.cancelDictation() }
                else if modifiersChanged { self.handleModifiers(flags) }
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            if event.type == .keyDown && event.keyCode == 53 && !event.isARepeat { self?.cancelDictation() }
            else if event.type == .flagsChanged, let self = self { self.handleModifiers(event.modifierFlags) }
            return event
        }
        guard globalMonitor != nil, localMonitor != nil else { disable(persist: false); status = "단축키 감시를 시작할 수 없습니다"; return }
        enabled = true; status = "\(shortcut.label)을 누른 채 말하고 놓으세요"
        if handsFreeEnabled { installHandsFreeTap() }
        if case .custom(let binding) = shortcut, binding.keyCode != nil { installCustomTap() }
    }

    private func handle(_ pressed: Bool) {
        guard enabled, !screenLocked, !sleeping, !capturingShortcut, !assistantCaptureActive, pressed != held else { return }; held = pressed
        if pressed { if !recording { start() } } else if recording && !handsFree { finish() }
    }

    private func handleModifiers(_ flags: NSEvent.ModifierFlags) {
        if case .custom(let binding) = shortcut, binding.keyCode != nil { return }
        let modifiers = flags.intersection(dictationModifiers)
        if modifiers.isEmpty { modifierChordBlocked = false }
        guard enabled, !sessionInactive, !capturingShortcut, !assistantCaptureActive else {
            modifierChordBlocked = !modifiers.isEmpty
            return
        }
        let action = dictationModifierAction(UInt64(modifiers.rawValue), UInt64(shortcut.requiredFlags.rawValue),
                                             held ? 1 : 0, modifierChordBlocked ? 1 : 0)
        switch DictationModifierAction(rawValue: action) {
        case .start: handle(true)
        case .finish:
            modifierChordBlocked = !modifiers.isEmpty
            handle(false)
        case .cancel:
            modifierChordBlocked = true
            if held { held = false; cancelDictation() }
        default: break
        }
    }

    func setScreenLocked(_ locked: Bool) {
        guard locked != screenLocked else { return }
        screenLocked = locked
        if locked { interruptForInactiveSession() }
        else if !sessionInactive { modifierChordBlocked = !NSEvent.modifierFlags.intersection(dictationModifiers).isEmpty }
    }

    func setSleeping(_ sleeping: Bool) {
        guard sleeping != self.sleeping else { return }
        self.sleeping = sleeping
        if sleeping { interruptForInactiveSession() }
        else if !sessionInactive { modifierChordBlocked = !NSEvent.modifierFlags.intersection(dictationModifiers).isEmpty }
    }

    private func interruptForInactiveSession() {
        if permissionInProgress { permissionGeneration += 1; permissionInProgress = false }
        cancelShortcutCapture(); cancelDictation(playSound: false)
        held = false; handsFree = false; customKeyDown = false; customKeyActive = false; customKeyGeneration &+= 1
    }

    private func installCustomTap() {
        guard customTap == nil, case .custom(let binding) = shortcut, binding.keyCode != nil else { return }
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << CGEventType.keyUp.rawValue) | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
            guard let context = context else { return Unmanaged.passUnretained(event) }
            let controller = Unmanaged<DictationController>.fromOpaque(context).takeUnretainedValue()
            return controller.consumeCustomKey(type, event) ? nil : Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { status = "사용자 지정 키 감시를 시작할 수 없습니다"; return }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap); status = "사용자 지정 키 감시를 시작할 수 없습니다"; return
        }
        customTap = tap; customSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, CFRunLoopMode.commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        status = "\(shortcut.label)을 누른 채 말하고 놓으세요"
    }

    private func removeCustomTap() {
        customKeyDown = false; customKeyActive = false; customKeyGeneration &+= 1
        if let source = customSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, CFRunLoopMode.commonModes) }
        if let tap = customTap { CFMachPortInvalidate(tap) }
        customSource = nil; customTap = nil
    }

    private func consumeCustomKey(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            customKeyDown = false; customKeyActive = false; customKeyGeneration &+= 1; held = false
            let token = customKeyGeneration, recordingToken = generation
            if recording {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, self.customKeyGeneration == token, self.generation == recordingToken else { return }
                    self.cancelDictation()
                }
            }
            if type == .tapDisabledByTimeout, let tap = customTap { CGEvent.tapEnable(tap: tap, enable: true) }
            else {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, self.customKeyGeneration == token else { return }
                    self.removeCustomTap(); self.status = "사용자 지정 키 감시가 중단됐습니다"
                }
            }
            return false
        }
        guard !capturingShortcut, !assistantCaptureActive, case .custom(let binding) = shortcut, let key = binding.keyCode else { return false }
        if type == .flagsChanged {
            if customKeyDown && !binding.matchesModifiers(event.flags) {
                customKeyActive = false; let token = customKeyGeneration
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, self.customKeyGeneration == token, !self.customKeyActive else { return }
                    self.handle(false)
                }
            }
            return false
        }
        guard event.getIntegerValueField(.keyboardEventKeycode) == Int64(key) else { return false }
        if type == .keyUp && customKeyDown {
            customKeyDown = false; customKeyActive = false; let token = customKeyGeneration
            DispatchQueue.main.async { [weak self] in guard let self = self, self.customKeyGeneration == token else { return }; self.handle(false) }
            return true
        }
        guard type == .keyDown else { return false }
        if customKeyDown { return true }
        guard enabled, !screenLocked, !sleeping, binding.matchesKeyDown(keyCode: Int64(key), flags: event.flags,
              repeated: event.getIntegerValueField(.keyboardEventAutorepeat) != 0) else { return false }
        customKeyDown = true; customKeyActive = true; customKeyGeneration &+= 1; let token = customKeyGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.customKeyGeneration == token, self.customKeyActive else { return }
            self.handle(true)
        }
        return true
    }

    private func installHandsFreeTap() {
        guard shortcut == .fn else { return }
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                         eventsOfInterest: mask, callback: { _, type, event, context in
            guard let context = context else { return Unmanaged.passUnretained(event) }
            let controller = Unmanaged<DictationController>.fromOpaque(context).takeUnretainedValue()
            return controller.consumeHandsFreeEvent(type, event) ? nil : Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { status = "핸즈프리 단축키 감시를 시작할 수 없습니다"; return }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap); status = "핸즈프리 단축키 감시를 시작할 수 없습니다"; return
        }
        handsFreeTap = tap; handsFreeSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, CFRunLoopMode.commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func removeHandsFreeTap() {
        if handsFree { cancelDictation() }
        handsFree = false; consumedSpaceDown = false
        if let source = handsFreeSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, CFRunLoopMode.commonModes) }
        if let tap = handsFreeTap { CFMachPortInvalidate(tap) }
        handsFreeSource = nil; handsFreeTap = nil
    }

    private func consumeHandsFreeEvent(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            consumedSpaceDown = false
            if handsFree { handsFree = false; DispatchQueue.main.async { [weak self] in self?.cancelDictation() } }
            if type == .tapDisabledByTimeout, let tap = handsFreeTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        guard event.getIntegerValueField(.keyboardEventKeycode) == 49 else { return false }
        if type == .keyUp, consumedSpaceDown { consumedSpaceDown = false; return true }
        guard type == .keyDown else { return false }
        if consumedSpaceDown { return true }
        guard enabled, !screenLocked, !sleeping, !assistantCaptureActive, handsFreeEnabled, shortcut == .fn, recording,
              Self.isHandsFreeCombination(keyCode: 49, flags: event.flags),
              event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return false }
        consumedSpaceDown = true
        handsFree.toggle()
        if handsFree { status = "핸즈프리로 듣는 중… Fn 키와 스페이스 바로 완료" }
        else { DispatchQueue.main.async { [weak self] in self?.finish() } }
        return true
    }

    static func isHandsFreeCombination(keyCode: Int64, flags: CGEventFlags) -> Bool {
        let modifiers: CGEventFlags = [.maskSecondaryFn, .maskControl, .maskAlternate, .maskShift, .maskCommand]
        return keyCode == 49 && flags.intersection(modifiers) == .maskSecondaryFn
    }

    private func focusedElement() -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value = value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func isSecureElement(_ element: AXUIElement) -> Bool {
        var subrole: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole) == .success
            && (subrole as? String) == "AXSecureTextField"
    }

    private func textValue(_ element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func isTextEntry(_ element: AXUIElement) -> Bool {
        var role: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
              let role = role as? String else { return false }
        return role == (kAXTextFieldRole as String) || role == (kAXTextAreaRole as String) || role == "AXSearchField"
    }

    private func isWebEditor(_ element: AXUIElement) -> Bool {
        var current = element
        for _ in 0..<16 {
            var role: CFTypeRef?
            if AXUIElementCopyAttributeValue(current, kAXRoleAttribute as CFString, &role) == .success,
               (role as? String) == "AXWebArea" { return true }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parent) == .success,
                  let parent, CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            current = parent as! AXUIElement
        }
        return false
    }

    private func selectedContent(_ element: AXUIElement) -> InsertionSelection? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let value = raw as! AXValue
        var range = CFRange()
        guard AXValueGetValue(value, .cfRange, &range) else { return nil }
        var text: CFTypeRef?
        if 1...InsertionSelection.fingerprintLimit ~= range.length,
           AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &text) == .success {
            return InsertionSelection(range: range, selectedText: text as? String)
        }
        return InsertionSelection(range: range, selectedText: nil)
    }

    private func start() {
        guard !screenLocked, !sleeping else { return }
        guard !recording, task == nil, pendingPaste == nil else { status = "이전 받아쓰기를 마치는 중입니다"; return }
        if let message = refreshAccess().missingMessage(requiresAccessibility: !assistantCaptureActive) {
            status = message
            return
        }
        let destination: InsertionTarget?
        if assistantCaptureActive { destination = nil }
        else {
            guard let target = focusedElement() else { status = "입력할 텍스트 필드를 선택해 주세요"; return }
            guard !isSecureElement(target) else { status = "보안 입력란에서는 받아쓰기를 사용하지 않습니다"; return }
            destination = InsertionTarget(element: target, selection: selectedContent(target), value: textValue(target))
        }
        guard let recognizer = recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else { status = "기기 내 음성 인식을 사용할 수 없습니다"; return }
        let input = engine.inputNode
        let initialFormat = input.outputFormat(forBus: 0)
        guard initialFormat.sampleRate > 0, initialFormat.channelCount > 0 else { status = "마이크 입력을 사용할 수 없습니다"; return }
        onWillStart?()
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { status = "마이크 입력을 사용할 수 없습니다"; return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        generation += 1; let currentGeneration = generation
        self.request = request; targetAtStart = destination; lastText = ""; finalReady = false
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                self?.handleRecognitionCallback(text: result?.bestTranscription.formattedString,
                                                isFinal: result?.isFinal ?? false,
                                                error: error as NSError?, generation: currentGeneration)
            }
        }
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
            var energy = 0.0
            for index in 0..<count { let value = Double(samples[index * stride]); energy += value * value }
            let measured = sqrt(energy / Double(count)) * 8
            let level = measured.isFinite ? min(1, measured) : 0
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.recording, self.generation == currentGeneration else { return }
                self.onInputLevel?(level)
            }
        }
        do { engine.prepare(); try engine.start() }
        catch {
            generation += 1
            input.removeTap(onBus: 0)
            task?.cancel(); task = nil; self.request = nil; targetAtStart = nil
            status = "마이크를 시작할 수 없습니다"
            return
        }
        recording = true
        status = "듣는 중…"
        FeedbackSound.dictationBegin.play()
    }

    private func handleRecognitionCallback(text: String?, isFinal: Bool, error: NSError?, generation expected: Int) {
        guard generation == expected, !finalReady else { return }
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { lastText = text }
        let noSpeech = error?.domain == "kAFAssistantErrorDomain" && error?.code == 1110
        if isFinal || (noSpeech && finalizationPending && !lastText.isEmpty && !assistantCaptureActive) {
            finalReady = true
            // The recognizer can finalize before the shortcut is released.
            if recording { finish() } else { complete() }
        } else if let error {
            dictationLog.notice("Speech recognition ended with \(error.domain, privacy: .public) \(error.code, privacy: .public)")
            generation += 1
            if recording { engine.stop(); engine.inputNode.removeTap(onBus: 0); recording = false }
            handsFree = false
            cancelFinalizationTimeout()
            request = nil; task = nil; targetAtStart = nil
            status = noSpeech ? "인식된 음성이 없습니다" : "음성 인식에 실패했습니다"
            if !lastText.isEmpty { status += ". 남은 텍스트를 복사할 수 있습니다" }
            if assistantCaptureActive { completeAssistantCapture(nil) }
        }
    }

    private func finish() {
        guard recording else { return }
        handsFree = false
        engine.stop(); engine.inputNode.removeTap(onBus: 0)
        if !finalReady { scheduleFinalizationTimeout() }
        recording = false
        FeedbackSound.dictationEnd.play()
        request?.endAudio()
        status = "변환 중…"
        if finalReady { complete() }
        else if task?.isFinishing == false { task?.finish() }
    }

    private func cancelDictation(playSound: Bool = true) {
        guard recording || finalizationPending || assistantCaptureActive else { return }
        handsFree = false
        generation += 1; permissionGeneration += 1
        if recording {
            engine.stop(); engine.inputNode.removeTap(onBus: 0); recording = false
            request?.endAudio(); if playSound { FeedbackSound.dictationEnd.play() }
        }
        cancelFinalizationTimeout()
        task?.cancel(); task = nil; request = nil; targetAtStart = nil; finalReady = false
        status = lastText.isEmpty ? "받아쓰기를 취소했습니다" : "받아쓰기를 중지했습니다. 텍스트를 복사할 수 있습니다"
        if assistantCaptureActive { completeAssistantCapture(nil) }
    }

    private static func correctedDictationSpacing(_ text: String, languageID: String) -> String {
        guard Locale(identifier: languageID).language.languageCode?.identifier == "ko" else { return text }
        // shortcut: use a small list of known compounds until a local Korean analyzer can verify broader word boundaries.
        let particleOrBoundary = #"(?=(?:(?:에서|에게|으로|까지|부터|에도|에는|에|은|는|이|가|을|를|와|과|도|만|의|로))?(?![\p{L}\p{N}]))"#
        return text
            .replacingOccurrences(of: #"(?<![\p{L}\p{N}])어린이\h+집"# + particleOrBoundary,
                                  with: "어린이집", options: .regularExpression)
            .replacingOccurrences(of: #"(?<![\p{L}\p{N}])(받아|띄어)\h+쓰기"# + particleOrBoundary,
                                  with: "$1쓰기", options: .regularExpression)
    }

    private func complete() {
        generation += 1
        cancelFinalizationTimeout()
        if recording { engine.stop(); engine.inputNode.removeTap(onBus: 0); recording = false }
        defer { request = nil; task = nil; targetAtStart = nil }
        guard !lastText.isEmpty else {
            status = "인식된 음성이 없습니다"
            if assistantCaptureActive { completeAssistantCapture(nil) }
            return
        }
        if assistantCaptureActive {
            status = "음성 입력 완료"; completeAssistantCapture(lastText); return
        }
        lastText = Self.correctedDictationSpacing(lastText, languageID: languageID)
        guard let target = targetAtStart, let current = focusedElement(), CFEqual(target.element, current) else {
            status = "입력란이 바뀌었습니다. 텍스트를 복사해 주세요"
            return
        }
        guard !isSecureElement(current) else { status = "보안 입력란에서는 자동 입력하지 않습니다. 텍스트를 복사해 주세요"; return }
        let selection = selectedContent(current)
        let value = textValue(current)
        if (target.selection.map { !$0.matches(selection) } ?? false)
            || (target.value.map { $0 != value } ?? false) {
            status = "커서 위치나 입력 내용이 바뀌었습니다. 텍스트를 복사해 주세요"
            return
        }
        var pid: pid_t = 0
        guard AXUIElementGetPid(current, &pid) == .success, pid > 0,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
            status = "입력할 앱이 바뀌었습니다. 텍스트를 복사해 주세요"
            return
        }
        let text = lastText
        let expected = value.flatMap { selection?.replacing(in: $0, with: text) }
        let token = generation
        // Codex and web editors may expose a writable AX value without updating their edit buffer.
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.openai.codex" || isWebEditor(current),
           pasteDictation(text, target: current, pid: pid, selection: selection,
                          value: value, expected: expected, token: token) { return }
        let result = AXUIElementSetAttributeValue(current, kAXSelectedTextAttribute as CFString, text as CFString)
        if result != .success {
            dictationLog.notice("Dictation text insertion returned AX error \(result.rawValue, privacy: .public)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
            guard let self, self.generation == token, !self.sessionInactive else { return }
            let updated = self.textValue(current)
            if let expected, updated == expected {
                self.status = "받아쓰기 완료"
            } else if let updated, updated != value {
                self.status = expected == nil ? "받아쓰기 완료" : "입력된 문장을 확인해 주세요"
            } else if result == .success && value == nil {
                self.status = "자동 입력을 요청했습니다"
            } else if (result == .success && value != nil) || result == .attributeUnsupported
                        || result == .notImplemented || result == .failure {
                _ = self.pasteDictation(text, target: current, pid: pid, selection: selection,
                                        value: value, expected: expected, token: token)
            } else {
                self.status = "입력하지 못했습니다. 텍스트를 복사해 주세요"
            }
        }
    }

    private func pasteDictation(_ text: String, target: AXUIElement, pid: pid_t, selection: InsertionSelection?,
                                value: String?, expected: String?, token: Int) -> Bool {
        func targetStillCurrent() -> Bool {
            NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
                && focusedElement().map { CFEqual(target, $0) } == true
                && (selection?.matches(selectedContent(target)) ?? true)
                && textValue(target) == value
                && !isSecureElement(target)
        }
        status = "입력하지 못했습니다. 텍스트를 복사해 주세요"
        guard pendingPaste == nil, isTextEntry(target) || selection != nil,
              CGPreflightPostEventAccess(), targetStillCurrent(),
              let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false),
              let transaction = DictationPasteboard(text, board: .general) else { return false }
        guard targetStillCurrent() else {
            transaction.restore()
            return false
        }
        pendingPaste = transaction
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.postToPid(pid)
        up.postToPid(pid)
        status = "텍스트를 보내는 중…"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            transaction.restore()
            guard let self, self.pendingPaste === transaction else { return }
            self.pendingPaste = nil
            guard self.generation == token else { return }
            let updated = self.textValue(target)
            if let expected, updated == expected {
                self.status = "받아쓰기 완료"
            } else if let updated, updated != value {
                self.status = expected == nil ? "받아쓰기 완료" : "입력된 문장을 확인해 주세요"
            } else {
                self.status = value == nil ? "붙여넣기를 요청했습니다" : "입력하지 못했습니다. 텍스트를 복사해 주세요"
            }
        }
        return true
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
            self.task?.cancel(); self.task = nil; self.request = nil; self.targetAtStart = nil
            self.status = self.lastText.isEmpty ? "음성 변환 시간이 초과됐습니다. 다시 시도해 주세요" : "음성 변환 시간이 초과됐습니다. 텍스트를 복사하거나 다시 시도해 주세요"
            if self.assistantCaptureActive { self.completeAssistantCapture(nil) }
        }
        finalizationTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: timeout)
    }
}

extension DictationController {
    static func testSelectionContentValidation() -> Bool {
        _ = NSApplication.shared
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 100))
        let range = NSRange(location: 0, length: 5)
        func snapshot() -> InsertionSelection {
            let selected = editor.accessibilitySelectedTextRange()
            return InsertionSelection(range: CFRange(location: selected.location, length: selected.length),
                                      selectedText: editor.accessibilitySelectedText())
        }
        editor.string = "바꿀 단어 이후"
        editor.setSelectedRange(range)
        let start = snapshot()
        guard start.fingerprint != nil, start.matches(snapshot()) else { return false }
        editor.replaceCharacters(in: range, with: "새로 쓴글")
        editor.setSelectedRange(range)
        let changed = snapshot()
        let unavailable = InsertionSelection(range: start.range, selectedText: nil)
        return changed.range.location == start.range.location && changed.range.length == start.range.length
            && changed.fingerprint != nil && !start.matches(changed)
            && !start.matches(unavailable) && unavailable.matches(changed)
    }

    static func testPermissionPreparation() -> Bool {
        var requests: [DictationPermissionPrompt] = []
        var anchors: [String] = []
        for permission in [DictationPermissionPrompt.speech, .microphone] {
            for needsRequest in [true, false] {
                DictationPermissionPrompt.activate(permission, needsRequest: needsRequest,
                    request: { requests.append($0) }, openSettings: { anchors.append($0) })
            }
        }
        let missingAccessibility = DictationAccess(accessibility: false, speech: .authorized,
                                                   microphone: .authorized, inputMonitoring: true)
        let firstLaunch = DictationAccess(accessibility: true, speech: .notDetermined,
                                         microphone: .denied, inputMonitoring: false)
        let ready = DictationAccess(accessibility: true, speech: .authorized,
                                    microphone: .authorized, inputMonitoring: false)
        return missingAccessibility.missingMessage() == "손쉬운 사용 권한이 필요합니다"
            && missingAccessibility.missingMessage(requiresAccessibility: false) == nil
            && missingAccessibility.canTryShortcutCapture
            && ready.missingMessage() == nil && ready.canTryShortcutCapture
            && DictationPermissionPrompt.speech.needsRequest(firstLaunch)
            && !DictationPermissionPrompt.microphone.needsRequest(firstLaunch)
            && requests == [.speech, .microphone] && anchors == ["Privacy_SpeechRecognition", "Privacy_Microphone"]
            && DictationPermissionStep.next(accessibility: false, speech: .notDetermined, microphone: .notDetermined) == .request(.speech)
            && DictationPermissionStep.next(accessibility: false, speech: .denied, microphone: .notDetermined) == .request(.microphone)
            && DictationPermissionStep.next(accessibility: false, speech: .authorized, microphone: .authorized) == .accessibility
            && DictationPermissionStep.next(accessibility: true, speech: .denied, microphone: .authorized) == .settings("Privacy_SpeechRecognition")
            && DictationPermissionStep.next(accessibility: true, speech: .authorized, microphone: .denied) == .settings("Privacy_Microphone")
            && DictationPermissionStep.next(accessibility: true, speech: .authorized, microphone: .authorized) == .ready
    }

    static func testAssistantCaptureCancellation() -> Bool {
        let controller = DictationController()
        var completions = 0
        controller.assistantCaptureActive = true
        controller.assistantCaptureCompletion = { text in if text == nil { completions += 1 } }
        let before = controller.permissionGeneration
        controller.cancelAssistantCapture()
        controller.cancelAssistantCapture()
        return !controller.assistantCaptureActive && controller.assistantCaptureCompletion == nil
            && controller.permissionGeneration == before + 1 && completions == 1
    }

    static func testShortcutCaptureIsolation(preferences: UserDefaults) -> Bool {
        let controller = DictationController(preferences: preferences)
        let original = controller.shortcut
        guard let value = RecordedDictationShortcut(keyCode: 8, modifiers: UInt64(NSEvent.ModifierFlags.control.rawValue), keyLabel: "C") else { return false }
        controller.capturingShortcut = true
        controller.captureGeneration = 1
        controller.cancelShortcutCapture()
        controller.captureGeneration &+= 1
        controller.capturingShortcut = true
        controller.finishShortcutCapture(value, generation: 1)
        let unchanged = controller.capturingShortcut && controller.shortcut == original
        controller.cancelShortcutCapture()
        return unchanged
    }

    static func testSleepInterruption() -> Bool {
        let controller = DictationController()
        controller.enabled = true; controller.held = true; controller.handsFree = true
        controller.customKeyDown = true; controller.customKeyActive = true
        controller.lastText = "부분 인식"
        controller.scheduleFinalizationTimeout(after: 60)
        let generation = controller.generation
        controller.setSleeping(true)
        guard !controller.held, !controller.handsFree, !controller.customKeyDown, !controller.customKeyActive,
              !controller.finalizationPending, controller.generation == generation + 1 else { return false }
        controller.handleRecognitionCallback(text: "이전 음성", isFinal: true, error: nil, generation: generation)
        guard controller.lastText == "부분 인식" else { return false }
        controller.handle(true)
        guard !controller.held else { return false }
        controller.setScreenLocked(true)
        controller.setSleeping(false)
        controller.handle(true)
        guard !controller.held else { return false }
        controller.setScreenLocked(false)
        return !controller.sleeping && !controller.screenLocked
    }

    static func testModifierGestureInterruption() -> Bool {
        let controller = DictationController()
        controller.shortcut = .fn
        controller.enabled = true
        controller.held = true
        controller.recognizer = nil
        controller.lastText = "부분 인식"
        controller.scheduleFinalizationTimeout(after: 60)
        let generation = controller.generation
        controller.handleModifiers([.function, .shift])
        guard !controller.held, !controller.finalizationPending, controller.generation == generation + 1 else { return false }
        controller.handleModifiers(.function)
        controller.handleRecognitionCallback(text: "이전 결과", isFinal: true, error: nil, generation: generation)
        guard !controller.held, controller.lastText == "부분 인식" else { return false }
        controller.handleModifiers([])
        return !controller.held
    }

    /// Verify stale recognition callbacks without creating a speech task.
    static func testCompatibleTextInsertion() -> Bool {
        let selection = InsertionSelection(range: CFRange(location: 2, length: 2), selectedText: "🙂")
        guard selection.replacing(in: "한글🙂!", with: "시험") == "한글시험!",
              selection.replacing(in: "한글", with: "시험") == nil else { return false }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let item = NSPasteboardItem()
        let type = NSPasteboard.PasteboardType("app.rium.notch.fixture")
        item.setString("기존", forType: .string)
        item.setData(Data([1, 2, 3]), forType: type)
        guard board.writeObjects([item]),
              let first = DictationPasteboard("문장", board: board),
              board.string(forType: .string) == "문장", !clipboardAllowsPreview(board) else { return false }
        first.restore()
        guard board.string(forType: .string) == "기존", board.data(forType: type) == Data([1, 2, 3]),
              let second = DictationPasteboard("다른 문장", board: board) else { return false }
        board.clearContents()
        board.setString("사용자 복사", forType: .string)
        second.restore()
        return board.string(forType: .string) == "사용자 복사"
    }

    static func testRecognitionCallbackIsolation() -> Bool {
        guard correctedDictationSpacing("아이는 어린이 집에 갑니다. 받아 쓰기를 확인합니다.", languageID: "ko-KR")
                == "아이는 어린이집에 갑니다. 받아쓰기를 확인합니다.",
              correctedDictationSpacing("이 담이는 어린이집에서 왔어요.\n한 개 주세요.", languageID: "ko_KR")
                == "이 담이는 어린이집에서 왔어요.\n한 개 주세요.",
              correctedDictationSpacing("어린이 집들이에 갑니다. 받아\n쓰기", languageID: "ko-KR")
                == "어린이 집들이에 갑니다. 받아\n쓰기",
              correctedDictationSpacing("어린이 집에", languageID: "en-US") == "어린이 집에" else { return false }
        let controller = DictationController()
        controller.handleRecognitionCallback(text: "완료", isFinal: false, error: nil, generation: 0)
        controller.handleRecognitionCallback(text: " ", isFinal: true, error: nil, generation: 0)
        guard controller.generation == 1, controller.lastText == "완료" else { return false }
        let completedStatus = controller.status
        controller.handleRecognitionCallback(text: "오래된 결과", isFinal: false, error: NSError(domain: "kAFAssistantErrorDomain", code: 1101), generation: 0)
        guard controller.lastText == "완료", controller.status == completedStatus else { return false }
        controller.generation += 1; controller.finalReady = false
        controller.handleRecognitionCallback(text: "부분 결과", isFinal: false, error: nil, generation: 2)
        controller.handleRecognitionCallback(text: nil, isFinal: false, error: NSError(domain: "kAFAssistantErrorDomain", code: 1101), generation: 2)
        let failedStatus = controller.status
        controller.handleRecognitionCallback(text: "오래된 결과", isFinal: true, error: nil, generation: 2)
        guard controller.generation == 3, controller.lastText == "부분 결과", controller.status == failedStatus else { return false }
        controller.finalReady = false
        controller.lastText = ""
        controller.handleRecognitionCallback(text: nil, isFinal: false,
                                             error: NSError(domain: "kAFAssistantErrorDomain", code: 1110), generation: 3)
        return controller.generation == 4 && controller.status == "인식된 음성이 없습니다"
    }

    /// Exercise cancellation and stale-callback protection without opening the microphone.
    static func testFinalizationTimeout() -> Bool {
        let controller = DictationController()
        var transitions: [Bool] = []
        controller.onFinalizationChange = { transitions.append($0) }
        controller.lastText = "시험 문장"
        controller.scheduleFinalizationTimeout(after: 0.05)
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        guard !controller.finalizationPending, controller.lastText == "시험 문장", controller.status.contains("텍스트를 복사"), controller.generation == 1 else { return false }
        controller.status = "대기"; controller.scheduleFinalizationTimeout(after: 0.05); controller.cancelFinalizationTimeout()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        return controller.status == "대기" && controller.generation == 1 && !controller.finalizationPending && transitions == [true, false, true, false]
    }
}
