import Foundation
import Combine

@_silgen_name("rium_interview_llm_request") private func interviewLLMRequest(_ bytes: UnsafePointer<UInt8>?, _ length: Int) -> UnsafeMutablePointer<CChar>?
@_silgen_name("rium_interview_llm_stream_event") private func interviewLLMStreamEvent(_ bytes: UnsafePointer<UInt8>?, _ length: Int) -> UnsafeMutablePointer<CChar>?
@_silgen_name("rium_interview_llm_free") private func interviewLLMFree(_ value: UnsafeMutablePointer<CChar>?)

struct InterviewSuggestionEntry: Identifiable {
    let id = UUID()
    let question: String
    let text: String
    let mode: String
    let provider: String
}

final class InterviewSuggestionClient: NSObject, ObservableObject, URLSessionDataDelegate {
    @Published private(set) var text = ""
    @Published private(set) var status = ""
    @Published private(set) var busy = false
    @Published private(set) var history: [InterviewSuggestionEntry] = []
    @Published private(set) var streamingText = ""
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var response = Data()
    private var streamLines: [String] = []
    private var streamEventBytes = 0
    private var receivedBytes = 0
    private var streamDone = false
    private var streamError = false
    private var httpStatus: Int?
    private var oversized = false
    private var activeProvider = ""
    private var activeQuestion = ""
    private var activeMode = ""
    private let responseLimit = 2 * 1024 * 1024
    private let eventLimit = 64 * 1024

    func generate(provider: String, model: String, lines: [[String: String]], mode: String) {
        guard !busy, let selected = InterviewProvider(rawValue: provider) else { return }
        guard let key = InterviewCredentialStore.read(account: provider), !key.isEmpty else {
            status = "설정에서 제공자의 API 키를 저장해 주세요."; return
        }
        let input: [String: Any] = ["provider": provider, "model": model, "lines": lines, "mode": mode, "previous": mode == "answer" ? "" : text]
        guard let data = try? JSONSerialization.data(withJSONObject: input),
              let raw = data.withUnsafeBytes({ interviewLLMRequest($0.bindMemory(to: UInt8.self).baseAddress, $0.count) }) else {
            status = "모델 ID와 전사 내용을 확인해 주세요."; return
        }
        defer { interviewLLMFree(raw) }
        guard let prepared = try? JSONSerialization.jsonObject(with: Data(bytes: raw, count: strlen(raw))) as? [String: Any],
              let address = prepared["url"] as? String, let url = URL(string: address),
              url.scheme == "https", url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil, url.host == selected.apiHost,
              let body = prepared["body"], JSONSerialization.isValidJSONObject(body),
              let encoded = try? JSONSerialization.data(withJSONObject: body), encoded.count <= 96 * 1024 else {
            status = "답변 요청을 만들지 못했습니다."; return
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 45)
        request.httpMethod = "POST"; request.httpBody = encoded
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if selected == .anthropic {
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        } else { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        self.session = session; response.removeAll(keepingCapacity: false); streamLines.removeAll(keepingCapacity: false)
        httpStatus = nil; oversized = false; receivedBytes = 0; streamEventBytes = 0; streamDone = false; streamError = false; streamingText = ""
        activeProvider = provider
        let latestQuestion = lines.last(where: { $0["speaker"] == "them" })?["text"] ?? ""
        activeQuestion = mode == "answer" ? latestQuestion : (history.last?.question ?? latestQuestion)
        activeMode = mode
        busy = true; status = "답변을 만드는 중…"
        let task = session.dataTask(with: request); self.task = task; task.resume()
    }

    func cancel() {
        let previous = session
        session = nil; task = nil; busy = false; response.removeAll(keepingCapacity: false)
        streamLines.removeAll(keepingCapacity: false); streamingText = ""
        activeProvider = ""; activeQuestion = ""; activeMode = ""
        previous?.invalidateAndCancel()
        status = "답변 요청을 취소했습니다."
    }

    func clearHistory() {
        guard !busy else { return }
        history.removeAll(keepingCapacity: false); text = ""; status = "답변 기록을 지웠습니다."
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard self.session === session, self.task === dataTask, let http = response as? HTTPURLResponse else { completionHandler(.cancel); return }
        httpStatus = http.statusCode
        if response.expectedContentLength > Int64(responseLimit) { oversized = true; completionHandler(.cancel) }
        else { completionHandler(.allow) }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard self.session === session, self.task === dataTask else { return }
        guard data.count <= responseLimit - receivedBytes else { oversized = true; dataTask.cancel(); return }
        receivedBytes += data.count
        guard let code = httpStatus, (200...299).contains(code) else { return }
        response.append(data)
        while let newline = response.firstIndex(of: 10) {
            let lineData = response.subdata(in: response.startIndex..<newline)
            response.removeSubrange(response.startIndex...newline)
            guard lineData.count <= eventLimit else { oversized = true; dataTask.cancel(); return }
            guard var line = String(data: lineData, encoding: .utf8) else { streamError = true; dataTask.cancel(); return }
            if line.hasSuffix("\r") { line.removeLast() }
            if line.isEmpty {
                guard consumeStreamEvent() else { streamError = true; dataTask.cancel(); return }
            } else if line.hasPrefix("data:") {
                guard lineData.count <= eventLimit - streamEventBytes else { oversized = true; dataTask.cancel(); return }
                streamEventBytes += lineData.count
                var value = String(line.dropFirst(5))
                if value.hasPrefix(" ") { value.removeFirst() }
                streamLines.append(value)
            }
        }
        if response.count > eventLimit { oversized = true; dataTask.cancel() }
    }

    private func consumeStreamEvent() -> Bool {
        guard !streamLines.isEmpty else { return true }
        let value = streamLines.joined(separator: "\n")
        streamLines.removeAll(keepingCapacity: false)
        streamEventBytes = 0
        guard !streamDone else { return false }
        let input: [String: Any] = ["provider": activeProvider, "data": value]
        guard let data = try? JSONSerialization.data(withJSONObject: input),
              let raw = data.withUnsafeBytes({ interviewLLMStreamEvent($0.bindMemory(to: UInt8.self).baseAddress, $0.count) }) else { return false }
        defer { interviewLLMFree(raw) }
        guard let event = try? JSONSerialization.jsonObject(with: Data(bytes: raw, count: strlen(raw))) as? [String: Any],
              event["error"] as? Bool != true else { return false }
        if let delta = event["text"] as? String, !delta.isEmpty {
            guard streamingText.utf8.count + delta.utf8.count <= 32 * 1024 else { return false }
            streamingText += delta
        }
        if event["done"] as? Bool == true { streamDone = true }
        return true
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard self.session === session, self.task === task else { return }
        defer {
            self.session = nil; self.task = nil; busy = false; response.removeAll(keepingCapacity: false)
            streamLines.removeAll(keepingCapacity: false); streamingText = ""
            activeProvider = ""; activeQuestion = ""; activeMode = ""
            session.finishTasksAndInvalidate()
        }
        guard !oversized else { status = "응답이 너무 커서 처리하지 않았습니다."; return }
        guard !streamError else { status = "스트리밍 응답을 읽지 못했습니다."; return }
        guard let code = httpStatus, (200...299).contains(code) else {
            status = httpStatus.map { "제공자 요청 실패 (HTTP \($0))" } ?? "제공자에 연결하지 못했습니다."; return
        }
        guard error == nil else { status = "답변을 받는 중 연결이 끊겼습니다."; return }
        guard streamDone, response.isEmpty, streamLines.isEmpty else { status = "답변 수신이 완료되기 전에 연결이 종료됐습니다."; return }
        let answer = streamingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { status = "제공자의 답변이 비어 있습니다."; return }
        text = answer
        history.append(InterviewSuggestionEntry(question: activeQuestion, text: answer, mode: activeMode, provider: activeProvider))
        if history.count > 100 { history.removeFirst(history.count - 100) }
        status = "답변 제안을 받았습니다."
    }
}

extension InterviewProvider {
    var apiHost: String {
        switch self {
        case .groq: return "api.groq.com"
        case .gemini: return "generativelanguage.googleapis.com"
        case .openrouter: return "openrouter.ai"
        case .anthropic: return "api.anthropic.com"
        case .openai: return "api.openai.com"
        }
    }
}
