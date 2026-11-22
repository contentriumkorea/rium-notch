import AVFoundation
import Combine
import Speech
import SwiftUI

@_silgen_name("rium_interview_transcript_new") private func interviewNew() -> UnsafeMutableRawPointer?
@_silgen_name("rium_interview_transcript_free") private func interviewFree(_ handle: UnsafeMutableRawPointer?)
@_silgen_name("rium_interview_transcript_partial") private func interviewPartial(_ handle: UnsafeMutableRawPointer?, _ speaker: Int32, _ bytes: UnsafePointer<UInt8>?, _ length: Int) -> Int32
@_silgen_name("rium_interview_transcript_finish") private func interviewFinish(_ handle: UnsafeMutableRawPointer?, _ speaker: Int32) -> Int32
@_silgen_name("rium_interview_transcript_snapshot") private func interviewSnapshot(_ handle: UnsafeMutableRawPointer?) -> UnsafeMutablePointer<CChar>?
@_silgen_name("rium_interview_transcript_free_string") private func interviewFreeString(_ value: UnsafeMutablePointer<CChar>?)

struct InterviewLine: Decodable, Identifiable {
    let id: UInt64
    let speaker: String
    let text: String
}
private struct InterviewSnapshot: Decodable {
    let lines: [InterviewLine]
    let mePartial: String
    let themPartial: String
}
func interviewSessionMatches(active: Bool, current: Int, expected: Int) -> Bool {
    active && current == expected
}
func interviewAutoEligible(active: Bool, enabled: Bool, pending: UInt64?, lastSent: UInt64?, busy: Bool) -> Bool {
    active && enabled && !busy && pending != nil && pending != lastSent
}

// The Rust transcript is accessed on the main queue only; samples are not saved.
final class InterviewController: ObservableObject {
    @Published private(set) var active = false
    @Published private(set) var status = "면접을 시작하면 내 발화를 표시합니다."
    @Published private(set) var lines: [InterviewLine] = []
    @Published private(set) var mePartial = ""
    @Published private(set) var themPartial = ""
    @Published private(set) var systemStatus = ""
    @Published var includeSystemAudio = false
    let suggestions = InterviewSuggestionClient()
    private let transcript = interviewNew()
    private lazy var engine = AVAudioEngine()
    private let systemAudio = InterviewSystemAudio()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var generation = 0
    private var recognitionCycle = 0
    private var restartWork: DispatchWorkItem?
    private var consecutiveFailures = 0
    private var tapInstalled = false
    private var autoWork: DispatchWorkItem?
    private var pendingAutoLine: UInt64?
    private var lastAutoLine: UInt64?
    private var autoInFlight = false
    private var suggestionObservation: AnyCancellable?

    init() {
        systemAudio.onText = { [weak self] text, final in self?.receiveSystemText(text, final: final) }
        systemAudio.onStatus = { [weak self] status in self?.systemStatus = status }
        suggestionObservation = suggestions.$busy.dropFirst().sink { [weak self] busy in
            guard !busy else { return }
            // @Published emits before the value changes; inspect it on the next main-queue turn.
            DispatchQueue.main.async { [weak self] in
                guard let self = self, !self.suggestions.busy else { return }
                self.autoInFlight = false
                self.dispatchPendingSuggestion()
            }
        }
    }

    func start(language: String, includeSystemAudio: Bool) {
        guard !active, transcript != nil else { return }
        // Snapshot the provider for the lifetime of this interview.
        let systemProvider = UserDefaults.standard.string(forKey: "rium.interview.systemProvider") == "deepgram" ? "deepgram" : "local"
        generation += 1; let expected = generation
        consecutiveFailures = 0
        systemStatus = includeSystemAudio ? "시스템 오디오 준비 중…" : ""
        active = true; status = "마이크와 음성 인식 권한 확인 중…"
        SFSpeechRecognizer.requestAuthorization { [weak self] authorization in
            DispatchQueue.main.async {
                guard let self = self, self.active, self.generation == expected else { return }
                guard authorization == .authorized else { self.stop(message: "음성 인식 권한이 필요합니다."); return }
                AVCaptureDevice.requestAccess(for: .audio) { [weak self] allowed in
                    DispatchQueue.main.async {
                        guard let self = self, self.active, self.generation == expected else { return }
                        guard allowed else { self.stop(message: "마이크 권한이 필요합니다."); return }
                        self.startRecognition(language: language, generation: expected)
                        if self.active && includeSystemAudio { self.systemAudio.start(language: language, provider: systemProvider) }
                    }
                }
            }
        }
    }

    private func receiveSystemText(_ text: String, final: Bool) {
        guard active else { return }
        let previousID = lines.last?.id
        if !final && !text.isEmpty { cancelPendingSuggestion() }
        if !text.isEmpty {
            let bytes = Array(text.utf8)
            let accepted = bytes.withUnsafeBufferPointer { interviewPartial(transcript, 1, $0.baseAddress, $0.count) }
            guard accepted == 0 else { systemAudio.stop(); systemStatus = "상대 발화가 너무 길어 인식을 중단했습니다."; return }
        }
        if final { _ = interviewFinish(transcript, 1) }
        refresh()
        if final, let line = lines.last, line.id != previousID, line.speaker == "them" {
            scheduleAutoSuggestion(for: line.id)
        }
    }

    private func cancelPendingSuggestion() {
        autoWork?.cancel(); autoWork = nil; pendingAutoLine = nil
    }

    func setAutoSuggestEnabled(_ enabled: Bool) {
        guard !enabled else { return }
        cancelPendingSuggestion()
        if autoInFlight { autoInFlight = false; suggestions.cancel() }
    }

    private func scheduleAutoSuggestion(for lineID: UInt64) {
        cancelPendingSuggestion()
        guard UserDefaults.standard.bool(forKey: "rium.interview.autoSuggest") else { return }
        pendingAutoLine = lineID
        let expected = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.generation == expected else { return }
            self.autoWork = nil
            self.dispatchPendingSuggestion()
        }
        autoWork = work
        // shortcut: the original turn-settling delay has not yet been recovered.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private func dispatchPendingSuggestion() {
        guard autoWork == nil,
              interviewAutoEligible(active: active, enabled: UserDefaults.standard.bool(forKey: "rium.interview.autoSuggest"),
                                    pending: pendingAutoLine, lastSent: lastAutoLine, busy: suggestions.busy),
              let lineID = pendingAutoLine,
              lines.last(where: { $0.speaker == "them" })?.id == lineID else { return }
        pendingAutoLine = nil; lastAutoLine = lineID
        suggest("answer")
        autoInFlight = suggestions.busy
    }

    private func startRecognition(language: String, generation expected: Int) {
        guard interviewSessionMatches(active: active, current: generation, expected: expected) else { return }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language)),
              recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            stop(message: "선택한 언어의 기기 내 음성 인식을 사용할 수 없습니다."); return
        }
        let input = engine.inputNode, format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { stop(message: "마이크 입력을 사용할 수 없습니다."); return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true; request.shouldReportPartialResults = true
        recognitionCycle += 1; let cycle = recognitionCycle
        let started = ProcessInfo.processInfo.systemUptime
        var hadSpeech = false
        self.request = request
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        tapInstalled = true
        do { engine.prepare(); try engine.start() }
        catch { stop(message: "마이크를 시작하지 못했습니다."); return }
        status = "내 발화를 듣는 중입니다."
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self = self, self.active, self.generation == expected, self.recognitionCycle == cycle else { return }
                if let result = result {
                    let bytes = Array(result.bestTranscription.formattedString.utf8)
                    let accepted = bytes.withUnsafeBufferPointer { interviewPartial(self.transcript, 0, $0.baseAddress, $0.count) }
                    if accepted != 0 { self.stop(message: "발화가 너무 길어 인식을 중단했습니다."); return }
                    if !bytes.isEmpty { hadSpeech = true; self.consecutiveFailures = 0 }
                    if result.isFinal { _ = interviewFinish(self.transcript, 0) }
                    self.refresh()
                    if result.isFinal {
                        let tooQuick = !hadSpeech && ProcessInfo.processInfo.systemUptime - started < 2
                        self.restartRecognition(language: language, generation: expected, failed: tooQuick)
                        return
                    }
                }
                if error != nil {
                    _ = interviewFinish(self.transcript, 0); self.refresh()
                    self.restartRecognition(language: language, generation: expected, failed: true)
                }
            }
        }
    }

    private func stopRecognition() {
        recognitionCycle += 1
        if tapInstalled {
            if engine.isRunning { engine.stop() }
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        request?.endAudio(); request = nil; task?.cancel(); task = nil
    }

    private func restartRecognition(language: String, generation expected: Int, failed: Bool) {
        guard interviewSessionMatches(active: active, current: generation, expected: expected) else { return }
        consecutiveFailures = failed ? consecutiveFailures + 1 : 0
        stopRecognition()
        guard consecutiveFailures < 3 else { stop(message: "음성 인식이 반복해서 중단됐습니다. 다시 시작해 주세요."); return }
        status = "음성 인식을 이어가는 중…"
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, interviewSessionMatches(active: self.active, current: self.generation, expected: expected) else { return }
            self.restartWork = nil
            self.startRecognition(language: language, generation: expected)
        }
        restartWork?.cancel(); restartWork = work
        // shortcut: audio during this short recognizer restart can be missed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    func stop(message: String = "면접 듣기를 중지했습니다.") {
        generation += 1
        systemAudio.stop()
        active = false
        cancelPendingSuggestion()
        if autoInFlight { autoInFlight = false; suggestions.cancel() }
        restartWork?.cancel(); restartWork = nil
        stopRecognition()
        _ = interviewFinish(transcript, 0); _ = interviewFinish(transcript, 1); refresh()
        systemStatus = ""
        status = message
    }

    func suggest(_ mode: String) {
        var recent = lines.map { ["speaker": $0.speaker, "text": $0.text] }
        if !mePartial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { recent.append(["speaker": "me", "text": mePartial]) }
        if !themPartial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { recent.append(["speaker": "them", "text": themPartial]) }
        let preferences = UserDefaults.standard
        suggestions.generate(provider: preferences.string(forKey: "rium.interview.provider") ?? "groq",
                             model: preferences.string(forKey: "rium.interview.model") ?? "",
                             lines: Array(recent.suffix(12)), mode: mode)
    }

    private func refresh() {
        guard let raw = interviewSnapshot(transcript) else { return }
        defer { interviewFreeString(raw) }
        guard let snapshot = try? JSONDecoder().decode(InterviewSnapshot.self, from: Data(bytes: raw, count: strlen(raw))) else { return }
        lines = snapshot.lines; mePartial = snapshot.mePartial; themPartial = snapshot.themPartial
    }

    deinit {
        if suggestions.busy { suggestions.cancel() }
        autoWork?.cancel()
        restartWork?.cancel()
        systemAudio.stop()
        stopRecognition()
        interviewFree(transcript)
    }
}

struct InterviewView: View {
    @ObservedObject var model: Model
    @ObservedObject var interview: InterviewController
    @ObservedObject var suggestions: InterviewSuggestionClient
    var detached = false
    @AppStorage("rium.interview.systemProvider") private var systemProvider = "local"
    init(model: Model, interview: InterviewController, suggestions: InterviewSuggestionClient, detached: Bool = false) {
        self.model = model; self.interview = interview; self.suggestions = suggestions; self.detached = detached
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("면접 코파일럿").font(.system(size: 14, weight: .semibold))
                Spacer()
                if detached {
                    Button("노치로 돌아가기") { model.onReturnInterviewToNotch?() }.buttonStyle(.plain)
                } else {
                    Button("별도 창") { model.onOpenInterviewWindow?() }.buttonStyle(.plain)
                        .disabled(model.onOpenInterviewWindow == nil)
                }
                Button(interview.active ? "중지" : "시작") {
                    if interview.active { interview.stop() } else { model.startInterview(includeSystemAudio: interview.includeSystemAudio) }
                }.buttonStyle(.plain).disabled(!interview.active && model.dictationRecording)
            }
            Text(interview.status).font(.caption).foregroundStyle(.secondary)
            Toggle("시스템 오디오도 인식", isOn: $interview.includeSystemAudio).disabled(interview.active).font(.caption)
            if interview.includeSystemAudio {
                Picker("상대 음성 인식", selection: $systemProvider) {
                    Text("기기 내 인식").tag("local")
                    Text("Deepgram").tag("deepgram")
                }.disabled(interview.active).font(.caption)
                Text(systemProvider == "deepgram" ? "면접을 시작하면 Mac의 시스템 오디오가 Deepgram으로 실시간 전송되며 요금이 발생할 수 있습니다." : "Mac에서 재생되는 소리를 기기에서 전사합니다.")
                    .font(.caption2).foregroundStyle(.secondary)
                if !interview.systemStatus.isEmpty { Text(interview.systemStatus).font(.caption2).foregroundStyle(.secondary) }
            }
            ScrollViewReader { proxy in
              ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(interview.lines) { line in
                        Label(line.text, systemImage: line.speaker == "me" ? "mic.fill" : "speaker.wave.2.fill")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !interview.mePartial.isEmpty {
                        Label(interview.mePartial, systemImage: "mic.fill").foregroundStyle(.secondary)
                    }
                    if !interview.themPartial.isEmpty {
                        Label(interview.themPartial, systemImage: "speaker.wave.2.fill").foregroundStyle(.secondary)
                    }
                    if !suggestions.history.isEmpty {
                        Divider()
                        HStack {
                            Text("답변 제안 기록").fontWeight(.semibold)
                            Spacer()
                            Button("기록 지우기") { suggestions.clearHistory() }.buttonStyle(.plain).disabled(suggestions.busy)
                        }
                        ForEach(suggestions.history) { suggestion in
                            VStack(alignment: .leading, spacing: 4) {
                                if suggestion.mode != "answer" {
                                    Text(suggestion.mode == "develop" ? "자세히" : (suggestion.mode == "next" ? "이어서" : "짧게"))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                if !suggestion.question.isEmpty { Text(suggestion.question).foregroundStyle(.secondary) }
                                Text(suggestion.text).frame(maxWidth: .infinity, alignment: .leading)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            if suggestion.id != suggestions.history.last?.id { Divider() }
                        }
                    }
                    if !suggestions.streamingText.isEmpty {
                        Divider()
                        Text("답변 생성 중").fontWeight(.semibold)
                        Text(suggestions.streamingText).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Color.clear.frame(height: 1).id("interview-bottom")
                }.font(.system(size: 12)).textSelection(.enabled)
              }
              .onChange(of: suggestions.streamingText) { value in
                  if !value.isEmpty { proxy.scrollTo("interview-bottom", anchor: .bottom) }
              }
              .onChange(of: suggestions.history.count) { _ in
                  if !suggestions.history.isEmpty { proxy.scrollTo("interview-bottom", anchor: .bottom) }
              }
            }.frame(maxHeight: .infinity, alignment: .top)
            HStack {
                Button("답변 제안") { interview.suggest("answer") }.disabled(suggestions.busy)
                if !suggestions.text.isEmpty {
                    Button("자세히") { interview.suggest("develop") }.disabled(suggestions.busy)
                    Button("이어서") { interview.suggest("next") }.disabled(suggestions.busy)
                    Button("짧게") { interview.suggest("shorter") }.disabled(suggestions.busy)
                }
                if suggestions.busy { Button("취소") { suggestions.cancel() } }
            }.buttonStyle(.plain).font(.caption)
            Text(suggestions.status.isEmpty ? "제안을 요청하면 최근 전사 최대 12개가 선택한 제공자로 전송됩니다." : suggestions.status)
                .font(.caption2).foregroundStyle(.secondary)
            Text("앱을 종료하면 전사와 답변 기록이 지워집니다.").font(.caption2).foregroundStyle(.secondary)
        }
    }
}
