import SwiftUI
import Foundation
import AppKit

struct AssistantScrollMeasurement: Equatable {
    let bottom: CGFloat
    let contentHeight: CGFloat
}

struct AssistantScrollTracker {
    var following = true
    private var previous: AssistantScrollMeasurement?
    init() {}

    mutating func update(_ current: AssistantScrollMeasurement, viewportHeight: CGFloat) -> Bool {
        guard current.bottom.isFinite, current.contentHeight.isFinite, viewportHeight.isFinite,
              current.contentHeight >= 0, viewportHeight > 0 else { return false }
        let nearBottom = current.bottom <= viewportHeight + 24
        let grew = previous.map { current.contentHeight > $0.contentHeight + 0.5 } ?? true
        if let previous = previous {
            let movement = current.bottom - previous.bottom - (current.contentHeight - previous.contentHeight)
            if movement > 2 && !nearBottom { following = false }
        }
        if nearBottom { following = true }
        previous = current
        return following && grew
    }
}

private struct AssistantScrollMeasurementKey: PreferenceKey {
    static var defaultValue: AssistantScrollMeasurement? = nil
    static func reduce(value: inout AssistantScrollMeasurement?, nextValue: () -> AssistantScrollMeasurement?) {
        value = nextValue() ?? value
    }
}

// shortcut: layout and live response transitions need comparison with the reference assistant page.
struct AssistantPage: View {
    @ObservedObject var model: Model
    @ObservedObject var assistant: AssistantController
    @ObservedObject var dictation: DictationController
    @State private var answers: [UUID: [String: String]] = [:]
    @State private var error = ""
    @State private var voiceRequested = false
    @AppStorage("rium.assistant.speakResponses") private var speakResponses = false
    @State private var scroll = AssistantScrollTracker()
    @State private var deletion: (conversation: UUID, message: UUID)?
    @State private var conversationToDelete: UUID?
    @FocusState private var focus: Field?
    private enum Field: Hashable { case composer, question(UUID, String) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("AI 대화").font(.system(size: 14, weight: .semibold))
                Menu {
                    Button("새 대화") { assistant.newConversation(); scroll = AssistantScrollTracker() }
                        .disabled(!assistant.canChangeConversation || dictation.assistantCaptureActive || assistant.conversations.count >= 50)
                    if !assistant.conversations.isEmpty { Divider() }
                    ForEach(assistant.conversations) { conversation in
                        Menu(conversation.title) {
                            Button("열기") { assistant.selectConversation(conversation.id); scroll = AssistantScrollTracker() }
                            Button("기록에서 제거", role: .destructive) { conversationToDelete = conversation.id }
                        }.disabled(!assistant.canChangeConversation || dictation.assistantCaptureActive)
                    }
                } label: {
                    Text(assistant.currentConversationTitle).lineLimit(1).frame(maxWidth: 130)
                }.disabled(!assistant.canChangeConversation || dictation.assistantCaptureActive).help("대화 선택")
                Text(assistant.status).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    speakResponses.toggle()
                    if !speakResponses { model.stopAssistantSpeech() }
                } label: { Image(systemName: speakResponses ? "speaker.wave.2.fill" : "speaker.slash") }
                    .help(speakResponses ? "AI 음성 응답 끄기" : "AI 음성 응답 켜기")
                    .accessibilityLabel(speakResponses ? "AI 음성 응답 끄기" : "AI 음성 응답 켜기")
                if assistant.phase == .disconnected {
                    Button("연결") { assistant.connect(workingDirectory: FileManager.default.homeDirectoryForCurrentUser) }.disabled(!assistant.historyReady)
                } else {
                    if assistant.phase == .running { Button("중단") { assistant.interrupt() }.disabled(assistant.stopping) }
                    if assistant.phase == .uncertain {
                        Button("상태 다시 확인") {
                            assistant.disconnect()
                            assistant.connect(workingDirectory: FileManager.default.homeDirectoryForCurrentUser)
                        }.disabled(!assistant.historyReady)
                    }
                    Button("연결 종료") { assistant.disconnect() }
                }
            }.buttonStyle(.plain)
            if !assistant.historyError.isEmpty {
                HStack {
                    Text(assistant.historyError).font(.caption).foregroundStyle(.orange)
                    if !assistant.historyReady { Button("다시 불러오기") { assistant.retryHistoryLoad() }.disabled(assistant.historyLoading) }
                }.buttonStyle(.plain)
            }
            if assistant.requestOverflow {
                Text("요청이 너무 많아 일부를 표시할 수 없습니다. 작업을 중단한 뒤 다시 시도해 주세요.")
                    .font(.caption).foregroundStyle(.orange)
            }
            ScrollViewReader { proxy in
              GeometryReader { viewport in
                  messageList(proxy: proxy, viewportHeight: viewport.size.height)
              }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.orange) }
            if voiceRequested { Text(dictation.status).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            if dictation.assistantCaptureActive && dictation.status == "듣는 중…" && !dictation.lastText.isEmpty {
                Text(dictation.lastText).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("질문이나 요청 입력", text: $assistant.draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(1...3).focused($focus, equals: .composer)
                    .disabled(assistant.phase != .ready)
                    .onSubmit { send() }
                Button {
                    voiceRequested = true
                    if dictation.assistantCaptureActive { dictation.finishAssistantCapture() }
                    else { model.startAssistantVoiceCapture() }
                } label: { Image(systemName: dictation.assistantCaptureActive ? "stop.circle.fill" : "mic") }
                    .buttonStyle(.plain).disabled(assistant.phase != .ready && !dictation.assistantCaptureActive)
                    .help(dictation.assistantCaptureActive ? "음성 입력 중지" : "음성으로 입력")
                    .accessibilityLabel(dictation.assistantCaptureActive ? "음성 입력 중지" : "음성으로 입력")
                Button("전송") { send() }.buttonStyle(.plain)
                    .disabled(assistant.phase != .ready || dictation.assistantCaptureActive || assistant.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || assistant.draft.utf8.count > 20_000)
            }
        }
        .font(.system(size: 12))
        .confirmationDialog("이 요청과 답변을 기록에서 제거할까요?", isPresented: Binding(
            get: { deletion != nil }, set: { if !$0 { deletion = nil } }
        ), presenting: deletion) { target in
            Button("기록에서 제거", role: .destructive) {
                assistant.removeTurnHistory(messageID: target.message, conversationID: target.conversation)
                deletion = nil
            }
            Button("취소", role: .cancel) { deletion = nil }
        } message: { _ in
            Text("이 화면의 기록에서만 제거됩니다. AI 서버의 대화와 맥락은 유지됩니다.")
        }
        .confirmationDialog("이 대화를 기록에서 제거할까요?", isPresented: Binding(
            get: { conversationToDelete != nil }, set: { if !$0 { conversationToDelete = nil } }
        ), presenting: conversationToDelete) { id in
            Button("기록에서 제거", role: .destructive) { assistant.removeConversation(id); conversationToDelete = nil }
            Button("취소", role: .cancel) { conversationToDelete = nil }
        } message: { _ in
            Text("이 화면의 기록에서만 제거됩니다. AI 서버의 대화는 유지됩니다.")
        }
        .onChange(of: focus) { _, value in model.setAssistantEditing(value != nil) }
        .onChange(of: assistant.phase) { _, phase in if phase != .ready { dictation.cancelAssistantCapture() } }
        .onChange(of: assistant.activeConversationID) { _, _ in dictation.cancelAssistantCapture() }
        .onChange(of: assistant.requests.map(\.id)) { _, current in
            let active = Set(current)
            answers = answers.filter { active.contains($0.key) }
            if case let .question(id, _)? = focus, !active.contains(id) { focus = nil }
        }
        .onDisappear { model.setAssistantEditing(false); scroll = AssistantScrollTracker() }
    }

    private func send() {
        guard assistant.phase == .ready, !dictation.assistantCaptureActive else { return }
        let text = assistant.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= 20_000 else { return }
        scroll.following = true
        assistant.send(text); error = ""
    }

    @ViewBuilder private func requestCard(_ request: AssistantServerRequest) -> some View {
        let preview = request.preview
        VStack(alignment: .leading, spacing: 7) {
            Text(assistantRequestTitle(request.method))
                .font(.system(size: 12, weight: .semibold))
            if let preview = preview, preview["kind"] as? String == "question", let questions = preview["questions"] as? [[String: Any]] {
                ForEach(Array(questions.enumerated()), id: \.offset) { _, question in questionField(request, question) }
                Button("답변 보내기") { submitQuestions(request, questions: questions) }
                    .disabled(!assistant.canRespond(to: request.id) || questions.contains { value(request, $0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                DisclosureGroup("요청 세부 정보") { requestDetails(request) }.font(.caption)
            } else if let preview = preview, preview["kind"] as? String == "approval" {
                requestDetails(request)
                HStack {
                    Button("거절") { respond(request, action: 0) }.disabled(!assistant.canRespond(to: request.id) || (preview["canDeny"] as? Bool) != true)
                    Button("허용") { respond(request, action: 1) }.disabled(!assistant.canRespond(to: request.id) || (preview["canAllow"] as? Bool) != true)
                }
            } else {
                requestDetails(request)
                Text("이 요청은 여기서 응답할 수 없습니다. 작업을 중단할 수 있습니다.").font(.caption).foregroundStyle(.secondary)
            }
            if !request.isSubmitted && assistant.phase == .running && !assistant.canRespond(to: request.id) {
                Text("현재 작업의 요청인지 확인할 수 없어 응답할 수 없습니다.").font(.caption).foregroundStyle(.secondary)
            }
            if request.isSubmitted { Text("응답 전달 확인 중…").font(.caption).foregroundStyle(.secondary) }
        }.buttonStyle(.plain).padding(9).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    private func messageList(proxy: ScrollViewProxy, viewportHeight: CGFloat) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 7) {
                if assistant.messages.isEmpty && assistant.requests.isEmpty {
                    Text("질문이나 요청을 입력해 주세요.").font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 72, alignment: .center)
                }
                ForEach(assistant.messages) { message in messageView(message) }
                ForEach(assistant.requests) { request in requestCard(request) }
                Color.clear.frame(height: 1).id("assistant-bottom")
            }
            .background(GeometryReader { geometry in
                Color.clear.preference(key: AssistantScrollMeasurementKey.self,
                    value: AssistantScrollMeasurement(bottom: geometry.frame(in: .named("assistant-scroll")).maxY,
                                                      contentHeight: geometry.size.height))
            })
        }
        .coordinateSpace(name: "assistant-scroll")
        .onPreferenceChange(AssistantScrollMeasurementKey.self) { measurement in
            guard let measurement = measurement, scroll.update(measurement, viewportHeight: viewportHeight) else { return }
            DispatchQueue.main.async { if scroll.following { proxy.scrollTo("assistant-bottom", anchor: .bottom) } }
        }
        .onChange(of: viewportHeight) { _, _ in
            if scroll.following { proxy.scrollTo("assistant-bottom", anchor: .bottom) }
        }
        .overlay(alignment: .bottomTrailing) {
            if !scroll.following {
                Button { scroll.following = true; proxy.scrollTo("assistant-bottom", anchor: .bottom) } label: {
                    Image(systemName: "arrow.down").padding(6).background(.thinMaterial, in: Circle())
                }.buttonStyle(.plain).help("최신 답변 보기").accessibilityLabel("최신 답변 보기")
            }
        }
    }

    private func messageView(_ message: AssistantChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(message.role == "user" ? "나" : "AI").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                if message.role == "assistant" {
                    Button {
                        let board = NSPasteboard.general
                        board.clearContents()
                        error = board.setString(message.text, forType: .string) ? "" : "답변을 복사하지 못했습니다."
                    } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.plain).disabled(message.text.isEmpty)
                        .help("답변 복사").accessibilityLabel("AI 답변 복사")
                    Button { deletion = (assistant.activeConversationID, message.id) } label: { Image(systemName: "trash") }
                        .buttonStyle(.plain).disabled(!assistant.canChangeConversation || message.turnId == nil)
                        .help("이 대화 기록에서 제거").accessibilityLabel("이 대화 기록에서 제거")
                }
            }
            Text(message.text).font(.system(size: 12)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }.padding(9).background(.white.opacity(message.role == "user" ? 0.09 : 0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder private func questionField(_ request: AssistantServerRequest, _ question: [String: Any]) -> some View {
        if let id = question["id"] as? String, let title = question["question"] as? String {
            let options = question["options"] as? [String] ?? []
            Text(title).font(.system(size: 12, weight: .medium)).fixedSize(horizontal: false, vertical: true)
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Button { setValue(option, request: request, key: id) } label: {
                    HStack(alignment: .top) {
                        Image(systemName: value(request, question) == option ? "largecircle.fill.circle" : "circle")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option)
                            if let description = assistantOptionDescription(parameters: request.parameters, questionID: id, index: index, label: option) {
                                Text(description).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }.disabled(!assistant.canRespond(to: request.id))
            }
            if options.isEmpty || question["isOther"] as? Bool == true {
                TextField("직접 답변 입력", text: Binding(get: { value(request, question) }, set: { setValue($0, request: request, key: id) }))
                    .textFieldStyle(.roundedBorder).focused($focus, equals: .question(request.id, id)).disabled(!assistant.canRespond(to: request.id))
            }
        }
    }

    private func value(_ request: AssistantServerRequest, _ question: [String: Any]) -> String {
        guard let id = question["id"] as? String else { return "" }
        return answers[request.id]?[id] ?? ""
    }
    private func setValue(_ value: String, request: AssistantServerRequest, key: String) {
        var values = answers[request.id] ?? [:]; values[key] = value; answers[request.id] = values
    }
    private func submitQuestions(_ request: AssistantServerRequest, questions: [[String: Any]]) {
        do {
            try assistant.respond(to: request.id, action: 2, answers: questions.map { value(request, $0) })
            if case let .question(id, _)? = focus, id == request.id { focus = nil }
            error = ""
        }
        catch { self.error = "답변을 확인하고 다시 시도해 주세요." }
    }
    private func respond(_ request: AssistantServerRequest, action: Int32) {
        do { try assistant.respond(to: request.id, action: action); error = "" }
        catch { self.error = "요청을 확인할 수 없습니다. 작업 상태를 확인해 주세요." }
    }
    private func requestDetails(_ request: AssistantServerRequest) -> some View {
        ScrollView {
            Text(details(request.parameters)).font(.system(size: 10, design: .monospaced))
                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxHeight: 110)
    }
    private func details(_ value: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "요청 세부 사항을 표시할 수 없습니다." }
        return text
    }
}
