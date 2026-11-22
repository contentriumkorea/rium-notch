import AudioToolbox
import CoreMedia
import Foundation

@_silgen_name("rium_deepgram_new") private func deepgramNew() -> UnsafeMutableRawPointer?
@_silgen_name("rium_deepgram_free") private func deepgramFree(_ handle: UnsafeMutableRawPointer?)
@_silgen_name("rium_deepgram_push") private func deepgramPush(_ handle: UnsafeMutableRawPointer?, _ bytes: UnsafePointer<UInt8>?, _ length: Int) -> UnsafeMutablePointer<CChar>?
@_silgen_name("rium_deepgram_free_string") private func deepgramFreeString(_ value: UnsafeMutablePointer<CChar>?)

// All methods and mutable state are confined to the capture's serial audio queue.
// The socket exists only for an explicitly selected Deepgram interview session.
final class InterviewDeepgram: NSObject, URLSessionTaskDelegate {
    private let queue: DispatchQueue
    private let onText: (String, Bool) -> Void
    private let onFailure: () -> Void
    private var session: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var parser: UnsafeMutableRawPointer?
    private var pending: [Data] = []
    private var pendingBytes = 0
    private var sending = false

    init(queue: DispatchQueue, onText: @escaping (String, Bool) -> Void, onFailure: @escaping () -> Void) {
        self.queue = queue; self.onText = onText; self.onFailure = onFailure
        super.init()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Never forward an API key or system audio to a redirected host.
        completionHandler(nil)
    }

    func start(key: String, language: String) -> Bool {
        guard socket == nil, !key.isEmpty, !key.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let parser = deepgramNew() else { return false }
        var components = URLComponents()
        components.scheme = "wss"; components.host = "api.deepgram.com"; components.path = "/v1/listen"
        components.queryItems = [URLQueryItem(name: "model", value: "nova-3"),
            URLQueryItem(name: "language", value: language), URLQueryItem(name: "encoding", value: "linear16"),
            URLQueryItem(name: "sample_rate", value: "48000"), URLQueryItem(name: "channels", value: "1"),
            URLQueryItem(name: "interim_results", value: "true"), URLQueryItem(name: "endpointing", value: "400"),
            URLQueryItem(name: "punctuate", value: "true")]
        guard let url = components.url else { deepgramFree(parser); return false }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil
        var request = URLRequest(url: url); request.setValue("Token \(key)", forHTTPHeaderField: "Authorization")
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        let socket = session.webSocketTask(with: request)
        socket.maximumMessageSize = 65_536
        self.parser = parser; self.session = session; self.socket = socket
        socket.resume(); receive(socket)
        return true
    }

    func stop() {
        let old = socket; socket = nil
        pending.removeAll(keepingCapacity: false); pendingBytes = 0; sending = false
        deepgramFree(parser); parser = nil
        old?.cancel(with: .normalClosure, reason: nil)
        session?.invalidateAndCancel(); session = nil
    }

    private func fail() {
        guard socket != nil else { return }
        stop(); onFailure()
    }

    private func receive(_ expected: URLSessionWebSocketTask) {
        expected.receive { [weak self, weak expected] result in
            guard let self = self, let expected = expected else { return }
            self.queue.async {
                guard self.socket === expected else { return }
                switch result {
                case .failure: self.fail(); return
                case .success(let message):
                    let data: Data
                    switch message {
                    case .string(let text): data = Data(text.utf8)
                    case .data(let value): data = value
                    @unknown default: self.fail(); return
                    }
                    guard !data.isEmpty, data.count <= 65_536,
                          let value = data.withUnsafeBytes({ raw in
                              deepgramPush(self.parser, raw.bindMemory(to: UInt8.self).baseAddress, raw.count)
                          }) else { self.fail(); return }
                    defer { deepgramFreeString(value) }
                    guard let object = try? JSONSerialization.jsonObject(with: Data(String(cString: value).utf8)) as? [String: Any],
                          let kind = object["type"] as? String else { self.fail(); return }
                    if kind == "error" { self.fail(); return }
                    if kind == "text", let text = object["text"] as? String, let finished = object["finished"] as? Bool {
                        self.onText(text, finished)
                    }
                    self.receive(expected)
                }
            }
        }
    }

    private func enqueue(_ data: Data) {
        guard socket != nil else { return }
        // shortcut: bounded queue stops slow sessions; reconnect after real-network validation.
        guard data.count <= 192_000 - pendingBytes else { fail(); return }
        pending.append(data); pendingBytes += data.count
        sendNext()
    }

    private func sendNext() {
        guard !sending, let socket = socket, !pending.isEmpty else { return }
        sending = true
        let data = pending.removeFirst()
        socket.send(.data(data)) { [weak self, weak socket] error in
            guard let self = self, let socket = socket else { return }
            self.queue.async {
                guard self.socket === socket else { return }
                self.pendingBytes -= data.count; self.sending = false
                if error != nil { self.fail() } else { self.sendNext() }
            }
        }
    }

    func consume(_ sampleBuffer: CMSampleBuffer) {
        guard socket != nil, let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let basic = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
              basic.mFormatID == kAudioFormatLinearPCM, basic.mSampleRate == 48_000,
              basic.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              basic.mFormatFlags & kAudioFormatFlagIsPacked != 0,
              basic.mFormatFlags & kAudioFormatFlagIsBigEndian == 0, basic.mBitsPerChannel == 32 else { fail(); return }
        var needed = 0
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer, bufferListSizeNeededOut: &needed, bufferListOut: nil, bufferListSize: 0, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: nil) == noErr,
              needed >= MemoryLayout<AudioBufferList>.size, needed <= 4096 else { fail(); return }
        let memory = UnsafeMutableRawPointer.allocate(byteCount: needed, alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { memory.deallocate() }
        let list = memory.bindMemory(to: AudioBufferList.self, capacity: 1)
        var block: CMBlockBuffer?
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer, bufferListSizeNeededOut: nil, bufferListOut: list, bufferListSize: needed, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment), blockBufferOut: &block) == noErr else { fail(); return }
        withExtendedLifetime(block) {
            let buffers = UnsafeMutableAudioBufferListPointer(list)
            guard !buffers.isEmpty, buffers.count <= 8 else { fail(); return }
            let usable = buffers.compactMap { buffer -> (UnsafePointer<Float>, Int, Int)? in
                let channels = Int(buffer.mNumberChannels)
                guard (1...8).contains(channels), let data = buffer.mData else { return nil }
                return (UnsafePointer(data.assumingMemoryBound(to: Float.self)), channels, Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / channels)
            }
            guard usable.count == buffers.count, let frames = usable.map({ $0.2 }).min(), frames > 0, frames <= 48_000 else { fail(); return }
            var samples = [Int16](); samples.reserveCapacity(frames)
            for frame in 0..<frames {
                var sum: Float = 0; var channels = 0
                for (data, count, _) in usable {
                    for channel in 0..<count { let value = data[frame * count + channel]; sum += value.isFinite ? value : 0; channels += 1 }
                }
                let mono = max(-1, min(1, sum / Float(channels)))
                samples.append(Int16((mono * 32767).rounded()).littleEndian)
            }
            samples.withUnsafeBytes { enqueue(Data($0)) }
        }
    }
}
