import AppKit
import Foundation
import Darwin

func suppressBrokenPipeSignal(_ handle: FileHandle) -> Bool {
    fcntl(handle.fileDescriptor, F_SETNOSIGPIPE, 1) != -1
}

@_silgen_name("rium_assistant_speech_chunks_new")
private func rustSpeechChunksNew() -> UnsafeMutableRawPointer?
@_silgen_name("rium_assistant_speech_chunks_consume")
private func rustSpeechChunksConsume(_ state: UnsafeMutableRawPointer?, _ data: UnsafePointer<UInt8>?, _ length: Int, _ complete: Int32) -> UnsafeMutablePointer<CChar>?
@_silgen_name("rium_assistant_speech_chunks_free")
private func rustSpeechChunksFree(_ state: UnsafeMutableRawPointer?)

@_silgen_name("rium_assistant_stream_new")
private func rustAssistantStreamNew(_ thread: UnsafePointer<UInt8>?, _ threadLength: Int,
                                    _ turn: UnsafePointer<UInt8>?, _ turnLength: Int) -> UnsafeMutableRawPointer?
@_silgen_name("rium_assistant_stream_consume")
private func rustAssistantStreamConsume(_ stream: UnsafeMutableRawPointer?, _ data: UnsafePointer<UInt8>?, _ length: Int) -> UnsafeMutablePointer<CChar>?
@_silgen_name("rium_assistant_stream_free")
private func rustAssistantStreamFree(_ stream: UnsafeMutableRawPointer?)
@_silgen_name("rium_assistant_string_free")
private func rustAssistantStringFree(_ value: UnsafeMutablePointer<CChar>?)
@_silgen_name("rium_assistant_request_preview")
private func rustAssistantRequestPreview(_ data: UnsafePointer<UInt8>?, _ length: Int) -> UnsafeMutablePointer<CChar>?
@_silgen_name("rium_assistant_request_response")
private func rustAssistantRequestResponse(_ data: UnsafePointer<UInt8>?, _ length: Int, _ action: Int32,
                                          _ answers: UnsafePointer<UInt8>?, _ answersLength: Int) -> UnsafeMutablePointer<CChar>?
@_silgen_name("rium_assistant_recover_turn")
private func rustAssistantRecoverTurn(_ data: UnsafePointer<UInt8>?, _ length: Int) -> UnsafeMutablePointer<CChar>?

private func assistantDecodedJSON(_ output: UnsafeMutablePointer<CChar>?) -> [String: Any]? {
    guard let output = output else { return nil }
    defer { rustAssistantStringFree(output) }
    guard let data = String(validatingUTF8: output)?.data(using: .utf8) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}

final class AssistantSpeechChunks {
    private let state = rustSpeechChunksNew()
    deinit { rustSpeechChunksFree(state) }

    func consume(_ text: String, complete: Bool) -> (chunks: [String], invalidated: Bool)? {
        guard state != nil else { return nil }
        let result = text.withCString { bytes in
            assistantDecodedJSON(rustSpeechChunksConsume(state, UnsafeRawPointer(bytes).assumingMemoryBound(to: UInt8.self), text.utf8.count, complete ? 1 : 0))
        }
        guard let result, let chunks = result["chunks"] as? [String], let invalidated = result["invalidated"] as? Bool else { return nil }
        return (chunks, invalidated)
    }
}

func assistantRequestPreview(_ request: Data) -> [String: Any]? {
    request.withUnsafeBytes { bytes in assistantDecodedJSON(rustAssistantRequestPreview(bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count)) }
}

func assistantRequestResponse(_ request: Data, action: Int32, answers: [String]) -> [String: Any]? {
    guard let encoded = try? JSONSerialization.data(withJSONObject: answers.map { [$0] }) else { return nil }
    return request.withUnsafeBytes { bytes in
        encoded.withUnsafeBytes { values in
            assistantDecodedJSON(rustAssistantRequestResponse(bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count, action,
                                                               values.bindMemory(to: UInt8.self).baseAddress, values.count))
        }
    }
}

func assistantRecoveredTurn(thread: String, turn: String?, clientID: String?, response: [String: Any]) -> [String: Any]? {
    var input: [String: Any] = ["threadId": thread, "response": response]
    if let turn = turn { input["turnId"] = turn }
    if let clientID = clientID { input["clientId"] = clientID }
    guard let data = try? JSONSerialization.data(withJSONObject: input) else { return nil }
    return data.withUnsafeBytes { bytes in assistantDecodedJSON(rustAssistantRecoverTurn(bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count)) }
}

enum AssistantConnectionError: Error { case unavailable, disconnected, invalidFrame, bufferFull }

/// A turn may emit notifications before the turn/start response arrives.
final class AssistantTurnBuffer {
    private let thread: String
    private var stream: UnsafeMutableRawPointer?
    private var pending: [(data: Data, receivedAt: TimeInterval)] = []
    private var pendingBytes = 0

    init(thread: String) { self.thread = thread }
    deinit { rustAssistantStreamFree(stream) }

    func bind(turn: String) throws -> [String: Any]? {
        guard stream == nil else { throw AssistantConnectionError.invalidFrame }
        let threadBytes = Array(thread.utf8), turnBytes = Array(turn.utf8)
        stream = threadBytes.withUnsafeBufferPointer { thread in
            turnBytes.withUnsafeBufferPointer { turn in
                rustAssistantStreamNew(thread.baseAddress, thread.count, turn.baseAddress, turn.count)
            }
        }
        guard stream != nil else { throw AssistantConnectionError.invalidFrame }
        let saved = pending; pending.removeAll(); pendingBytes = 0
        var last: [String: Any]?
        var lastToolStart: TimeInterval?
        for event in saved {
            if let snapshot = try consume(event.data, receivedAt: event.receivedAt) {
                if let started = snapshot["toolStartedAt"] as? TimeInterval { lastToolStart = started }
                last = snapshot
            }
        }
        if let started = lastToolStart { last?["toolStartedAt"] = started }
        return last
    }

    func consume(_ event: Data, receivedAt: TimeInterval = ProcessInfo.processInfo.systemUptime) throws -> [String: Any]? {
        guard let stream = stream else {
            guard pending.count < 1024, event.count <= 2_097_152 - pendingBytes else { throw AssistantConnectionError.bufferFull }
            pending.append((event, receivedAt)); pendingBytes += event.count
            return nil
        }
        let output = event.withUnsafeBytes { bytes in
            rustAssistantStreamConsume(stream, bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count)
        }
        guard let output = output else { throw AssistantConnectionError.invalidFrame }
        defer { rustAssistantStringFree(output) }
        guard let data = String(validatingUTF8: output)?.data(using: .utf8),
              var result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              result["error"] == nil else { throw AssistantConnectionError.invalidFrame }
        if result["toolStarted"] as? Bool == true { result["toolStartedAt"] = receivedAt }
        return (result["changed"] as? Bool) == true ? result : nil
    }
}

/// Kept idle until explicitly connected; all server requests reach the client.
protocol AssistantTransport: AnyObject {
    var onEvent: ((Data, TimeInterval) -> Void)? { get set }
    var onDisconnect: (() -> Void)? { get set }
    func connect() throws
    func send(_ object: [String: Any]) throws
    func disconnect()
}

final class AssistantConnection: AssistantTransport {
    var onEvent: ((Data, TimeInterval) -> Void)?
    var onDisconnect: (() -> Void)?
    private let writeQueue = DispatchQueue(label: "app.rium.notch.assistant.write")
    private var process: Process?
    private var input: FileHandle?
    private var generation: UInt64 = 0
    private var buffer = Data()

    func connect() throws {
        precondition(Thread.isMainThread)
        guard process == nil, let executable = Bundle.main.url(forAuxiliaryExecutable: "rium-notch-core") else { throw AssistantConnectionError.unavailable }
        let child = Process(), incoming = Pipe(), outgoing = Pipe()
        guard suppressBrokenPipeSignal(incoming.fileHandleForWriting) else { throw AssistantConnectionError.unavailable }
        child.executableURL = executable; child.arguments = ["assistant-server"]
        child.standardInput = incoming; child.standardOutput = outgoing; child.standardError = FileHandle.nullDevice
        try child.run()
        // Only the child owns these ends; keeping them open hides EOF or a broken pipe.
        try? incoming.fileHandleForReading.close()
        try? outgoing.fileHandleForWriting.close()
        generation &+= 1; let token = generation
        process = child; input = incoming.fileHandleForWriting; buffer.removeAll()
        let reader = outgoing.fileHandleForReading
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            while true {
                let data = reader.availableData
                if data.isEmpty { break }
                let receivedAt = ProcessInfo.processInfo.systemUptime
                DispatchQueue.main.async { [weak self] in self?.received(data, receivedAt: receivedAt, generation: token) }
            }
            DispatchQueue.main.async { [weak self] in self?.ended(generation: token) }
        }
    }

    func send(_ object: [String: Any]) throws {
        precondition(Thread.isMainThread)
        guard let input = input else { throw AssistantConnectionError.disconnected }
        guard JSONSerialization.isValidJSONObject(object) else { throw AssistantConnectionError.invalidFrame }
        var data = try JSONSerialization.data(withJSONObject: object)
        guard data.count <= 2_097_152 else { throw AssistantConnectionError.bufferFull }
        data.append(10)
        let token = generation, frame = data
        writeQueue.async { [weak self] in
            do { try input.write(contentsOf: frame) }
            catch { DispatchQueue.main.async { [weak self] in self?.ended(generation: token) } }
        }
    }

    func disconnect() {
        precondition(Thread.isMainThread)
        generation &+= 1
        let oldProcess = process, oldInput = input
        process = nil; input = nil; buffer.removeAll()
        writeQueue.async { try? oldInput?.close() }
        if oldProcess?.isRunning == true { oldProcess?.terminate() }
    }

    private func received(_ data: Data, receivedAt: TimeInterval, generation token: UInt64) {
        guard token == generation, process != nil else { return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 10) {
            let line = Data(buffer.prefix(upTo: newline)); buffer.removeSubrange(...newline)
            guard line.count <= 2_097_152 else { ended(generation: token); return }
            onEvent?(line, receivedAt)
            guard token == generation, process != nil else { return }
        }
        if buffer.count > 2_097_152 { ended(generation: token) }
    }

    private func ended(generation token: UInt64) {
        guard token == generation, process != nil else { return }
        disconnect()
        onDisconnect?()
    }
}
