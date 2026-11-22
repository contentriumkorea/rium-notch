import Foundation
import Combine
import AVFoundation

@_silgen_name("rium_assistant_history_load")
private func assistantHistoryLoad(_ root: UnsafePointer<CChar>, _ length: UnsafeMutablePointer<Int>) -> UnsafeMutablePointer<UInt8>?
@_silgen_name("rium_assistant_history_save")
private func assistantHistorySave(_ root: UnsafePointer<CChar>, _ data: UnsafeRawPointer?, _ length: Int) -> Int32
@_silgen_name("rium_assistant_history_free")
private func assistantHistoryFree(_ data: UnsafeMutablePointer<UInt8>?, _ length: Int)

// State and synthesizer are confined to the main queue; callbacks are forwarded there.
final class AssistantSpeech: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private var synthesizer: AVSpeechSynthesizer?
    private var pending = Set<ObjectIdentifier>()
    private(set) var speaking = false
    var onChange: ((Bool, TimeInterval) -> Void)?

    func speak(_ utterance: AVSpeechUtterance) {
        dispatchPrecondition(condition: .onQueue(.main))
        let synthesizer = self.synthesizer ?? AVSpeechSynthesizer()
        if self.synthesizer == nil {
            synthesizer.delegate = self
            self.synthesizer = synthesizer
        }
        pending.insert(ObjectIdentifier(utterance))
        synthesizer.speak(utterance)
    }

    func stop() {
        dispatchPrecondition(condition: .onQueue(.main))
        pending.removeAll()
        synthesizer?.stopSpeaking(at: .immediate)
        if speaking { speaking = false; onChange?(false, 0) }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.pending.contains(ObjectIdentifier(utterance)) else { return }
            self.speaking = true
            self.onChange?(true, ProcessInfo.processInfo.systemUptime)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString range: NSRange, utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.speaking, self.pending.contains(ObjectIdentifier(utterance)) else { return }
            self.onChange?(true, ProcessInfo.processInfo.systemUptime)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finish(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finish(utterance)
    }

    private func finish(_ utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.pending.remove(ObjectIdentifier(utterance)) != nil, self.pending.isEmpty else { return }
            self.speaking = false
            self.onChange?(false, 0)
        }
    }
}

struct AssistantChatMessage: Codable, Identifiable {
    let id: UUID
    let role: String
    var text: String
    var turnId: String? = nil
    var itemId: String? = nil
    var clientId: String? = nil
}

private struct AssistantSavedHistory: Codable {
    let version: Int
    let threadId: String?
    let turnId: String?
    let outcome: String
    let draft: String
    let messages: [AssistantChatMessage]
    let activeId: UUID?
    let conversations: [AssistantConversation]?
}

struct AssistantConversation: Codable, Identifiable {
    let id: UUID
    let threadId: String?
    let turnId: String?
    let outcome: String
    let draft: String
    let messages: [AssistantChatMessage]
    var title: String {
        let text = messages.first(where: { $0.role == "user" })?.text ?? draft
        let compact = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return compact.isEmpty ? "새 대화" : String(compact.prefix(40))
    }
}

struct AssistantServerRequest: Identifiable {
    let id: UUID
    let method: String
    let parameters: [String: Any]
    let preview: [String: Any]?
    fileprivate let serverID: Any
    fileprivate let raw: Data
    fileprivate var submitted = false
    var isSubmitted: Bool { submitted }
}

enum AssistantIndicator: Equatable { case off, working, approval, question }

func assistantToolStartIsFresh(_ started: TimeInterval, now: TimeInterval) -> Bool {
    started.isFinite && now.isFinite && started > 0 && now >= started && now - started < 0.8
}

func personalAssistantIndicator(phase: AssistantController.Phase, requests: [AssistantServerRequest], overflow: Bool = false) -> AssistantIndicator {
    guard phase == .submitting || phase == .running else { return .off }
    if overflow { return .approval }
    let waiting = requests.filter { !$0.isSubmitted }
    if waiting.contains(where: { $0.method != "item/tool/requestUserInput" }) { return .approval }
    return waiting.isEmpty ? .working : .question
}

func assistantPresentationMatches(observed: AssistantIndicator, observedTool: Bool,
                                  current: AssistantIndicator, currentTool: Bool) -> Bool {
    observed == current && observedTool == currentTool
}

func assistantRequestTitle(_ method: String) -> String {
    switch method {
    case "item/tool/requestUserInput": return "답변 요청"
    case "item/commandExecution/requestApproval", "execCommandApproval": return "명령 실행 승인 요청"
    case "item/fileChange/requestApproval", "applyPatchApproval": return "파일 변경 승인 요청"
    case "item/permissions/requestApproval": return "권한 승인 요청"
    case "mcpServer/elicitation/request": return "도구 사용 승인 요청"
    default: return "확인이 필요한 요청"
    }
}

func assistantOptionDescription(parameters: [String: Any], questionID: String, index: Int, label: String) -> String? {
    guard index >= 0, let questions = parameters["questions"] as? [[String: Any]],
          let question = questions.first(where: { $0["id"] as? String == questionID }),
          let options = question["options"] as? [[String: Any]], options.indices.contains(index),
          options[index]["label"] as? String == label, let description = options[index]["description"] as? String,
          !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return description
}

/// Personal assistant session; it does not attach to existing Codex chats.
final class AssistantController: ObservableObject {
    enum Phase: Equatable { case disconnected, connecting, ready, submitting, running, uncertain }
    private enum Reply { case success([String: Any]), rejected, uncertain }
    @Published private(set) var phase: Phase = .disconnected {
        didSet { if phase != .running && phase != .submitting { toolRunning = false } }
    }
    @Published private(set) var toolRunning = false
    @Published private(set) var toolBeatAt: TimeInterval?
    @Published private(set) var messages: [AssistantChatMessage] = [] { didSet { scheduleHistorySave() } }
    @Published var draft = "" { didSet { if draft != oldValue { scheduleHistorySave() } } }
    @Published private(set) var requests: [AssistantServerRequest] = []
    @Published private(set) var requestOverflow = false
    @Published private(set) var status = "연결 전"
    @Published private(set) var stopping = false
    @Published private(set) var historyReady = false
    @Published private(set) var historyLoading = false
    @Published private(set) var historyError = ""
    @Published private(set) var conversations: [AssistantConversation] = [] { didSet { scheduleHistorySave() } }
    @Published private(set) var activeConversationID = UUID() { didSet { scheduleHistorySave() } }
    var onMessageCompleted: ((String) -> Void)?
    var onMessageUpdate: ((String, String, Bool) -> Void)?
    var onWillSend: (() -> Void)?
    var onTurnCompleted: (() -> Void)?
    var lastOutcome: String { historyOutcome }
    var observationThreadID: String? { threadID }
    private let connection: AssistantTransport
    private let historyRoot: URL
    private let persistent: Bool
    private let historyQueue = DispatchQueue(label: "app.rium.notch.assistant.history", qos: .utility)
    private var historyWork: DispatchWorkItem?
    private var historyRevision = 0
    private var historyDirty = false
    private var historyOutcome = "none" { didSet { if historyOutcome != oldValue { scheduleHistorySave() } } }
    private var sequence = 0
    private var pending: [Int: (Reply) -> Void] = [:]
    private var threadID: String? { didSet { if threadID != oldValue { scheduleHistorySave() } } }
    private var turnID: String? { didSet { if turnID != oldValue { scheduleHistorySave() } } }
    private var pendingMessageID: UUID?
    private var unsentOutcome: String?
    private var turnBuffer: AssistantTurnBuffer?
    private var itemIndexes: [String: Int] = [:]
    private var completedMessageIDs: Set<String> = []

    init(connection: AssistantTransport = AssistantConnection(), startServices: Bool = false, historyRoot: URL? = nil) {
        self.connection = connection
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        self.historyRoot = historyRoot ?? support.appendingPathComponent("Rium Notch", isDirectory: true)
        persistent = startServices
        connection.onEvent = { [weak self] data, receivedAt in self?.receive(data, receivedAt: receivedAt) }
        connection.onDisconnect = { [weak self] in self?.connectionLost() }
        if startServices { loadHistory() } else { historyReady = true }
    }

    private func loadHistory() {
        guard persistent, !historyLoading, !historyReady else { return }
        historyLoading = true
        historyError = ""
        historyQueue.async { [weak self] in
            guard let self = self else { return }
            var length = 0
            let saved: AssistantSavedHistory? = self.historyRoot.path.withCString { root in
                guard let bytes = assistantHistoryLoad(root, &length) else { return nil }
                defer { assistantHistoryFree(bytes, length) }
                return try? JSONDecoder().decode(AssistantSavedHistory.self, from: Data(bytes: bytes, count: length))
            }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.historyLoading = false
                guard let saved = saved else { self.historyError = "대화 기록을 읽지 못해 저장을 중지했습니다."; return }
                self.threadID = saved.threadId; self.turnID = saved.turnId; self.messages = saved.messages; self.draft = saved.draft
                self.activeConversationID = saved.activeId ?? UUID(); self.conversations = saved.conversations ?? []
                self.historyOutcome = saved.outcome == "running" ? "unknown" : saved.outcome
                self.historyReady = true
                if self.historyOutcome == "unknown" { self.status = "이전 작업의 종료 상태를 확인해 주세요." }
            }
        }
    }

    func retryHistoryLoad() { loadHistory() }

    private func historyData() -> Data? {
        try? JSONEncoder().encode(AssistantSavedHistory(version: 1, threadId: threadID, turnId: turnID, outcome: historyOutcome, draft: draft, messages: messages, activeId: activeConversationID, conversations: conversations))
    }

    var canChangeConversation: Bool {
        historyReady && (phase == .disconnected || phase == .ready) && historyOutcome != "unknown" && historyOutcome != "running"
    }
    var currentConversationTitle: String { currentConversation.title }
    private var currentConversation: AssistantConversation {
        AssistantConversation(id: activeConversationID, threadId: threadID, turnId: turnID, outcome: historyOutcome, draft: draft, messages: messages)
    }

    func newConversation() {
        guard canChangeConversation, conversations.count < 50 else { return }
        changeConversation(to: AssistantConversation(id: UUID(), threadId: nil, turnId: nil, outcome: "none", draft: "", messages: []))
    }

    func selectConversation(_ id: UUID) {
        guard canChangeConversation, let selected = conversations.first(where: { $0.id == id }) else { return }
        changeConversation(to: selected)
    }

    func removeConversation(_ id: UUID) {
        guard canChangeConversation else { return }
        conversations.removeAll { $0.id == id }
    }

    func removeTurnHistory(messageID: UUID, conversationID: UUID) {
        guard canChangeConversation, conversationID == activeConversationID,
              let turn = messages.first(where: { $0.id == messageID && $0.role == "assistant" })?.turnId else { return }
        messages.removeAll { $0.turnId == turn }
    }

    private func changeConversation(to selected: AssistantConversation) {
        let old = currentConversation
        if phase == .ready { disconnect() }
        conversations.removeAll { $0.id == selected.id }
        conversations.insert(old, at: 0)
        activeConversationID = selected.id; threadID = selected.threadId; turnID = selected.turnId
        messages = selected.messages; draft = selected.draft; historyOutcome = selected.outcome
        status = "연결 전"
    }

    private func scheduleHistorySave() {
        guard persistent, historyReady else { return }
        historyDirty = true; historyRevision += 1
        let revision = historyRevision
        guard let data = historyData() else { historyError = "대화 기록을 저장할 수 없습니다."; return }
        historyWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.historyQueue.async { [weak self] in
                guard let self = self else { return }
                let result = self.historyRoot.path.withCString { root in data.withUnsafeBytes { assistantHistorySave(root, $0.baseAddress, $0.count) } }
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, self.historyRevision == revision else { return }
                    if result == 0 { self.historyDirty = false; self.historyError = "" }
                    else { self.historyError = result == -2 ? "대화 기록이 너무 커서 저장하지 못했습니다." : "대화 기록을 저장하지 못했습니다." }
                }
            }
        }
        historyWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private func persistBeforeSend(_ completion: @escaping (Bool) -> Void) {
        guard persistent else { completion(true); return }
        historyWork?.cancel(); historyWork = nil
        guard historyReady, let data = historyData() else { completion(false); return }
        let revision = historyRevision
        historyQueue.async { [weak self] in
            guard let self = self else { return }
            let result = self.historyRoot.path.withCString { root in data.withUnsafeBytes { assistantHistorySave(root, $0.baseAddress, $0.count) } }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                guard self.phase == .submitting, self.pendingMessageID != nil else { return }
                guard result == 0 else { self.historyError = "대화 기록을 저장하지 못했습니다."; completion(false); return }
                if self.historyRevision != revision { self.persistBeforeSend(completion); return }
                self.historyDirty = false; self.historyError = ""; completion(true)
            }
        }
    }

    func flushHistory() {
        historyWork?.cancel(); historyWork = nil
        guard persistent, historyReady, historyDirty, let data = historyData() else { historyQueue.sync {}; return }
        let result = historyQueue.sync { historyRoot.path.withCString { root in data.withUnsafeBytes { assistantHistorySave(root, $0.baseAddress, $0.count) } } }
        if result == 0 { historyDirty = false; historyError = "" }
        else { historyError = "대화 기록을 저장하지 못했습니다." }
    }

    func connect(workingDirectory: URL) {
        guard phase == .disconnected, historyReady, workingDirectory.isFileURL else { return }
        phase = .connecting; status = "연결 중…"
        do { try connection.connect() } catch { phase = .disconnected; status = "대화 서버를 열 수 없습니다."; return }
        request("initialize", ["clientInfo": ["name": "rium_notch", "title": "Rium Notch", "version": "1.0.0"]]) { [weak self] reply in
            guard let self = self else { return }
            guard case .success = reply else { self.connectionLost(); return }
            do { try self.connection.send(["method": "initialized", "params": [:]]) }
            catch { self.connectionLost(); return }
            let savedThread = self.threadID
            let method = savedThread == nil ? "thread/start" : "thread/resume"
            let parameters: [String: Any] = savedThread.map { ["threadId": $0] } ?? ["cwd": workingDirectory.path]
            self.request(method, parameters) { [weak self] reply in
                guard let self = self else { return }
                guard case .success(let result) = reply,
                      let thread = result["thread"] as? [String: Any],
                      let id = thread["id"] as? String, !id.isEmpty, id.utf8.count <= 256,
                      savedThread == nil || savedThread == id else {
                    self.connectionLost(); return
                }
                if savedThread != nil, (thread["status"] as? [String: Any])?["type"] as? String != "idle" {
                    self.phase = .uncertain; self.historyOutcome = "unknown"; self.status = "이전 작업 상태를 확인할 수 없습니다."; return
                }
                if savedThread != nil, self.historyOutcome == "unknown" {
                    let candidate = self.turnID == nil ? self.messages.last(where: { $0.role == "user" && $0.turnId == nil && $0.clientId != nil }) : nil
                    guard self.turnID != nil || candidate != nil else { self.phase = .uncertain; self.status = "이전 작업을 식별할 수 없습니다."; return }
                    self.recover(thread: id, turn: self.turnID, clientMessage: candidate); return
                }
                self.threadID = id; self.phase = .ready; self.status = "대화 준비됨"
            }
        }
    }

    func send(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard phase == .ready, let threadID = threadID, !text.isEmpty, text.utf8.count <= 20_000 else { return }
        onWillSend?()
        requestOverflow = false; phase = .submitting; status = "전송 중…"; stopping = false
        let previousOutcome = historyOutcome; historyOutcome = "running"
        unsentOutcome = previousOutcome
        turnID = nil; toolBeatAt = nil; turnBuffer = AssistantTurnBuffer(thread: threadID); itemIndexes.removeAll(); completedMessageIDs.removeAll()
        let messageID = UUID()
        let clientID = messageID.uuidString.lowercased()
        pendingMessageID = messageID
        messages.append(AssistantChatMessage(id: messageID, role: "user", text: text, clientId: clientID))
        persistBeforeSend { [weak self] saved in
          guard let self = self, self.phase == .submitting, self.threadID == threadID, self.pendingMessageID == messageID else { return }
          guard saved else {
              self.messages.removeAll { $0.id == messageID }; self.pendingMessageID = nil; self.turnBuffer = nil
              self.unsentOutcome = nil; self.historyOutcome = previousOutcome; self.phase = .ready; self.status = "기록을 저장하지 못해 전송하지 않았습니다."
              return
          }
          self.unsentOutcome = nil
          self.request("turn/start", ["threadId": threadID, "clientUserMessageId": clientID, "input": [["type": "text", "text": text, "text_elements": []]]]) { [weak self] reply in
            guard let self = self, self.phase == .submitting else { return }
            switch reply {
            case .success(let result):
                guard let turn = result["turn"] as? [String: Any], let id = turn["id"] as? String,
                      !id.isEmpty, id.utf8.count <= 256, (self.turnID == nil || self.turnID == id), let buffer = self.turnBuffer else {
                    self.historyOutcome = "unknown"; self.phase = .uncertain; self.status = "작업 시작 여부를 확인할 수 없습니다."; return
                }
                if self.draft.trimmingCharacters(in: .whitespacesAndNewlines) == text { self.draft = "" }
                self.recordTurn(id); self.phase = .running; self.status = "응답 중…"
                do { if let snapshot = try buffer.bind(turn: id) { self.apply(snapshot) } }
                catch { self.historyOutcome = "unknown"; self.phase = .uncertain; self.status = "응답을 처리할 수 없습니다." }
            case .rejected:
                if self.turnID != nil { self.historyOutcome = "unknown"; self.phase = .uncertain; self.status = "작업 시작 여부를 확인할 수 없습니다."; return }
                self.messages.removeAll { $0.id == messageID }
                self.pendingMessageID = nil
                self.historyOutcome = previousOutcome; self.phase = .ready; self.status = "메시지를 전달하지 못했습니다."; self.turnBuffer = nil
            case .uncertain: self.historyOutcome = "unknown"; self.phase = .uncertain; self.status = "전송 여부를 확인할 수 없습니다."
            }
          }
        }
    }

    func interrupt() {
        guard phase == .running, !stopping, let thread = threadID, let turn = turnID else { return }
        stopping = true; status = "중단 요청 중…"
        request("turn/interrupt", ["threadId": thread, "turnId": turn]) { [weak self] reply in
            guard let self = self, self.phase == .running, self.turnID == turn else { return }
            if case .rejected = reply { self.stopping = false; self.status = "중단 요청을 전달하지 못했습니다." }
            else { self.status = "작업 종료를 기다리는 중…" }
        }
    }

    /// Call only after the user responds to the displayed server request.
    func canRespond(to id: UUID) -> Bool {
        guard phase == .running, let turn = turnID else { return false }
        return requests.contains { $0.id == id && !$0.submitted && $0.parameters["turnId"] as? String == turn }
    }
    func respond(to id: UUID, action: Int32, answers: [String] = []) throws {
        guard canRespond(to: id), let index = requests.firstIndex(where: { $0.id == id }) else { throw AssistantConnectionError.invalidFrame }
        guard let response = assistantRequestResponse(requests[index].raw, action: action, answers: answers) else { throw AssistantConnectionError.invalidFrame }
        try connection.send(response)
        requests[index].submitted = true
    }

    func disconnect() {
        if let outcome = unsentOutcome {
            if let id = pendingMessageID { messages.removeAll { $0.id == id } }
            historyOutcome = outcome; unsentOutcome = nil
        } else if phase == .submitting || phase == .running || phase == .uncertain { historyOutcome = "unknown" }
        connection.disconnect(); pending.removeAll(); requests.removeAll(); requestOverflow = false; turnBuffer = nil
        pendingMessageID = nil; stopping = false; phase = .disconnected; status = "연결 전"
    }

    private func recordTurn(_ id: String) {
        turnID = id
        requests.removeAll { request in
            guard let requestTurn = request.parameters["turnId"] as? String else { return false }
            return requestTurn != id
        }
        if let message = pendingMessageID, let index = messages.firstIndex(where: { $0.id == message }) {
            messages[index].turnId = id
        }
    }

    private func recover(thread: String, turn: String?, clientMessage: AssistantChatMessage?) {
        status = "이전 작업 확인 중…"
        request("thread/read", ["threadId": thread, "includeTurns": true]) { [weak self] reply in
            guard let self = self, self.phase == .connecting, self.threadID == thread, self.turnID == turn else { return }
            guard case .success(let result) = reply,
                  let recovered = assistantRecoveredTurn(thread: thread, turn: turn, clientID: clientMessage?.clientId, response: result),
                  let recoveredTurn = recovered["turnId"] as? String,
                  let items = recovered["messages"] as? [[String: Any]], let outcome = recovered["outcome"] as? String else {
                self.phase = .uncertain; self.status = "이전 작업 결과를 확인할 수 없습니다."; return
            }
            let recoveredIDs = Set(items.compactMap { $0["id"] as? String })
            let previous = self.messages.filter { $0.role == "assistant" && $0.turnId == recoveredTurn }
            guard previous.allSatisfy({ message in
                guard let id = message.itemId else { return false }
                return recoveredIDs.contains(id)
            }) else {
                self.phase = .uncertain; self.status = "이전 응답을 안전하게 복구할 수 없습니다."; return
            }
            if let clientMessage = clientMessage, !self.messages.contains(where: { $0.id == clientMessage.id && $0.clientId == clientMessage.clientId }) {
                self.phase = .uncertain; self.status = "이전 요청을 안전하게 확인할 수 없습니다."; return
            }
            for item in items {
                guard let id = item["id"] as? String, let text = item["text"] as? String else { continue }
                if let index = self.messages.firstIndex(where: { $0.role == "assistant" && $0.turnId == recoveredTurn && $0.itemId == id }) {
                    self.messages[index].text = text
                } else { self.messages.append(AssistantChatMessage(id: UUID(), role: "assistant", text: text, turnId: recoveredTurn, itemId: id)) }
            }
            if let clientMessage = clientMessage, let index = self.messages.firstIndex(where: { $0.id == clientMessage.id && $0.clientId == clientMessage.clientId }) {
                self.messages[index].turnId = recoveredTurn
                if self.draft.trimmingCharacters(in: .whitespacesAndNewlines) == clientMessage.text { self.draft = "" }
            }
            self.historyOutcome = outcome; self.turnID = nil; self.phase = .ready
            self.status = outcome == "completed" ? "이전 응답 복구됨" : (outcome == "failed" ? "이전 작업 실패" : "이전 작업 중단됨")
        }
    }

    private func request(_ method: String, _ params: [String: Any], completion: @escaping (Reply) -> Void) {
        sequence += 1; let id = sequence
        pending[id] = completion
        do { try connection.send(["id": id, "method": method, "params": params]) }
        catch { pending.removeValue(forKey: id)?(.uncertain); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.pending.removeValue(forKey: id)?(.uncertain) }
    }

    private func receive(_ data: Data, receivedAt: TimeInterval) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let method = object["method"] as? String
        if method == nil, let id = object["id"] as? Int, let callback = pending.removeValue(forKey: id) {
            if object["error"] != nil { callback(.rejected) }
            else if let result = object["result"] as? [String: Any] { callback(.success(result)) }
            else { callback(.uncertain) }
            return
        }
        guard let method = method, let params = object["params"] as? [String: Any] else { return }
        if let id = object["id"], (id is String || id is NSNumber), let thread = threadID, params["threadId"] as? String == thread {
            guard phase == .submitting || phase == .running,
                  (turnID == nil || params["turnId"] as? String == nil || params["turnId"] as? String == turnID),
                  !requests.contains(where: { sameID($0.serverID, id) }) else { return }
            // shortcut: unretained requests require interrupting the turn; upgrade to a bounded persistent queue to handle more.
            guard requests.count < 32 else { requestOverflow = true; return }
            requests.append(AssistantServerRequest(id: UUID(), method: method, parameters: params, preview: assistantRequestPreview(data), serverID: id, raw: data))
            return
        }
        if method == "serverRequest/resolved", let thread = threadID, params["threadId"] as? String == thread, let id = params["requestId"] {
            requests.removeAll { sameID($0.serverID, id) }; return
        }
        if method == "turn/started", phase == .submitting, let thread = threadID, params["threadId"] as? String == thread,
           let turn = params["turn"] as? [String: Any], let id = turn["id"] as? String, !id.isEmpty, id.utf8.count <= 256 {
            if turnID == nil || turnID == id { recordTurn(id) }
            else { historyOutcome = "unknown"; phase = .uncertain; status = "작업 시작 여부를 확인할 수 없습니다." }
            return
        }
        guard let thread = threadID, params["threadId"] as? String == thread, let buffer = turnBuffer,
              ["item/agentMessage/delta", "item/started", "item/completed", "turn/completed"].contains(method) else { return }
        do { if let snapshot = try buffer.consume(data, receivedAt: receivedAt) { apply(snapshot) } }
        catch { historyOutcome = "unknown"; phase = .uncertain; status = "응답을 처리할 수 없습니다." }
    }

    private func apply(_ snapshot: [String: Any]) {
        let now = ProcessInfo.processInfo.systemUptime
        if snapshot["outcome"] as? String == "", let started = snapshot["toolStartedAt"] as? TimeInterval,
           assistantToolStartIsFresh(started, now: now) { toolBeatAt = started }
        if let running = snapshot["toolRunning"] as? Bool, toolRunning != running { toolRunning = running }
        if let items = snapshot["messages"] as? [[String: Any]] {
            for item in items {
                guard let id = item["id"] as? String, let text = item["text"] as? String else { continue }
                let changed: Bool
                if let index = itemIndexes[id], messages.indices.contains(index) {
                    changed = messages[index].text != text
                    if changed { messages[index].text = text }
                } else {
                    changed = true
                    itemIndexes[id] = messages.count
                    messages.append(AssistantChatMessage(id: UUID(), role: "assistant", text: text, turnId: turnID, itemId: id))
                }
                let complete = item["complete"] as? Bool == true
                if (changed || complete) && !completedMessageIDs.contains(id) { onMessageUpdate?(id, text, complete) }
                if complete, completedMessageIDs.insert(id).inserted { onMessageCompleted?(text) }
            }
        }
        switch snapshot["outcome"] as? String {
        case "completed": historyOutcome = "completed"; phase = .ready; status = "응답 완료"
        case "failed": historyOutcome = "failed"; phase = .ready; status = "작업 실패"
        case "interrupted": historyOutcome = "interrupted"; phase = .ready; status = "작업 중단됨"
        default: return
        }
        stopping = false; turnID = nil; pendingMessageID = nil; turnBuffer = nil; requests.removeAll(); requestOverflow = false
        onTurnCompleted?()
    }

    private func connectionLost() {
        let uncertain = unsentOutcome == nil && (phase == .submitting || phase == .running || phase == .uncertain)
        if let outcome = unsentOutcome {
            if let id = pendingMessageID { messages.removeAll { $0.id == id } }
            historyOutcome = outcome; unsentOutcome = nil
        } else if uncertain { historyOutcome = "unknown" }
        connection.disconnect(); pending.removeAll(); requests.removeAll(); requestOverflow = false; turnBuffer = nil
        pendingMessageID = nil; stopping = false
        phase = uncertain ? .uncertain : .disconnected
        status = uncertain ? "연결이 끊겨 작업 상태를 확인할 수 없습니다." : "대화 서버에 연결하지 못했습니다."
    }

    private func sameID(_ first: Any, _ second: Any) -> Bool {
        guard JSONSerialization.isValidJSONObject([first]), JSONSerialization.isValidJSONObject([second]),
              let a = try? JSONSerialization.data(withJSONObject: [first]),
              let b = try? JSONSerialization.data(withJSONObject: [second]) else { return false }
        return a == b
    }
}
