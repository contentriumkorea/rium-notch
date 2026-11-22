import Foundation
import Darwin
import AppKit

@_silgen_name("rium_is_airdrop_file") func isAirDropFile(_ path: UnsafePointer<CChar>) -> Int32
@_silgen_name("rium_airdrop_receive_settle_seconds")
private func airDropReceiveSettleSeconds() -> Double
@_silgen_name("rium_airdrop_receiving_fraction")
private func rustReceivingFraction(_ values: UnsafePointer<Double>?, _ count: Int, _ output: UnsafeMutablePointer<Double>?) -> Int32
@_silgen_name("rium_airdrop_pending_decision")
private func rustAirDropPendingDecision(_ firstSeen: Double, _ now: Double, _ exists: Int32, _ receiving: Int32) -> Int32
@_silgen_name("rium_airdrop_send_result")
private func rustAirDropSendResult(_ input: UnsafePointer<UInt8>?, _ length: Int, _ bundle: UnsafeMutablePointer<UInt8>?, _ capacity: Int) -> Int32

func aggregateReceivingFraction(_ values: [Double?]) -> Double? {
    let input = values.map { $0 ?? -1 }
    var result = 0.0
    let status = input.withUnsafeBufferPointer { rustReceivingFraction($0.baseAddress, $0.count, &result) }
    return status == 1 ? result : nil
}

struct ReceiveProgressSample {
    let root: String
    let direct: Bool
    let fraction: Double?
}
func aggregateReceivingProgress(_ samples: [ReceiveProgressSample]) -> Double? {
    let groups = Dictionary(grouping: samples, by: \.root)
    let fractions: [Double?] = groups.keys.sorted().map { root in
        let group = groups[root] ?? []
        let direct = group.filter(\.direct)
        return aggregateReceivingFraction((direct.isEmpty ? group : direct).map(\.fraction))
    }
    return aggregateReceivingFraction(fractions)
}

enum AirDropShareEvent {
    case prepared(UUID, URL)
    case started(UUID, URL)
    case finished(UUID, URL, success: Bool, cancelled: Bool)
}

final class AirDropSender: NSObject, NSSharingServiceDelegate {
    private struct Pending { let id: UUID; let url: URL; let service: NSSharingService; var started = false }
    private var pending: [ObjectIdentifier: Pending] = [:]
    private let onEvent: (AirDropShareEvent) -> Void

    init(onEvent: @escaping (AirDropShareEvent) -> Void) { self.onEvent = onEvent }

    func send(_ url: URL) -> Bool { send([url]) }
    func send(_ urls: [URL]) -> Bool {
        guard let first = urls.first, urls.allSatisfy({ $0.isFileURL && FileManager.default.fileExists(atPath: $0.path) }),
              let service = NSSharingService(named: .sendViaAirDrop),
              service.canPerform(withItems: urls) else { return false }
        let key = ObjectIdentifier(service)
        guard pending[key] == nil else { return false }
        service.delegate = self
        let id = UUID()
        pending[key] = Pending(id: id, url: first, service: service)
        onEvent(.prepared(id, first))
        service.perform(withItems: urls)
        return true
    }

    func sharingService(_ sharingService: NSSharingService, willShareItems items: [Any]) {
        let key = ObjectIdentifier(sharingService)
        guard var item = pending[key], !item.started else { return }
        item.started = true; pending[key] = item
        onEvent(.started(item.id, item.url))
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        guard let item = pending.removeValue(forKey: ObjectIdentifier(sharingService)) else { return }
        onEvent(.finished(item.id, item.url, success: true, cancelled: false))
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        guard let item = pending.removeValue(forKey: ObjectIdentifier(sharingService)) else { return }
        let failure = error as NSError
        onEvent(.finished(item.id, item.url, success: false, cancelled: failure.domain == NSCocoaErrorDomain && failure.code == NSUserCancelledError))
    }
}

struct WatchedFileIdentity: Hashable {
    let device: Int64
    let inode: UInt64
}
func watchedFileDeliveryMatches(expected: WatchedFileIdentity, actual: WatchedFileIdentity?) -> Bool {
    actual == expected
}

// A receive may update an existing file or folder without replacing its inode.
// Unknown metadata never counts as a confirmed change.
enum ReceiveFileStamp: Equatable {
    case missing
    case present(device: Int64, inode: UInt64, size: Int64, seconds: Int64, nanoseconds: Int64)
    case unknown
}
func receiveFileStamp(_ path: String) -> ReceiveFileStamp {
    var info = stat()
    guard lstat(path, &info) == 0 else { return errno == ENOENT ? .missing : .unknown }
    let kind = info.st_mode & mode_t(S_IFMT)
    guard kind == mode_t(S_IFREG) || kind == mode_t(S_IFDIR) else { return .unknown }
    return .present(device: Int64(info.st_dev), inode: UInt64(info.st_ino), size: Int64(info.st_size),
                    seconds: Int64(info.st_mtimespec.tv_sec), nanoseconds: Int64(info.st_mtimespec.tv_nsec))
}

func receiveFileChanged(from before: ReceiveFileStamp, to after: ReceiveFileStamp) -> Bool {
    switch (before, after) {
    case (.missing, .present(_, _, _, _, _)): return true
    case (.present(_, _, _, _, _), .present(_, _, _, _, _)): return before != after
    default: return false
    }
}
// Track nested published files without scanning unrelated folder contents.
struct ReceiveContentChanges {
    private var baselines: [String: (root: String, stamp: ReceiveFileStamp)] = [:]
    mutating func update(_ files: [String: String], stamp: (String) -> ReceiveFileStamp) -> Set<String> {
        var changed: Set<String> = []
        for (path, baseline) in baselines where files[path] != baseline.root {
            if receiveFileChanged(from: baseline.stamp, to: stamp(path)) { changed.insert(baseline.root) }
            baselines.removeValue(forKey: path)
        }
        for (path, root) in files where baselines[path] == nil {
            baselines[path] = (root, stamp(path))
        }
        return changed
    }
    mutating func clear() { baselines.removeAll() }
}
enum ReceivePendingDecision: Equatable { case wait, discard, classify }
func receivePendingDecision(firstSeen: TimeInterval, now: TimeInterval, exists: Bool, receiving: Bool) -> ReceivePendingDecision {
    switch rustAirDropPendingDecision(firstSeen, now, exists ? 1 : 0, receiving ? 1 : 0) {
    case 0: return .wait
    case 1: return .classify
    default: return .discard
    }
}

func receivingDirectoryExists(_ path: String) -> Bool {
    var info = stat()
    return lstat(path, &info) == 0 && (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR)
}
func receivingDirectories(roots: Set<String>, maximum: Int = 128, scanLimit: Int = 2048) -> [String: String] {
    guard maximum > 0, scanLimit > 0 else { return [:] }
    var result: [String: String] = [:]
    let validRoots = roots.sorted().filter { receivingDirectoryExists($0) }
    for root in validRoots.prefix(maximum) { result[root] = root }
    var visited = 0
    for root in validRoots where result[root] != nil {
        guard result.count < maximum, visited < scanLimit,
              let enumerator = FileManager.default.enumerator(at: URL(fileURLWithPath: root, isDirectory: true),
                  includingPropertiesForKeys: nil, options: [], errorHandler: { _, _ in true }) else { continue }
        while result.count < maximum, visited < scanLimit, let url = enumerator.nextObject() as? URL {
            visited += 1
            var info = stat()
            guard lstat(url.path, &info) == 0 else {
                enumerator.skipDescendants()
                continue
            }
            // Foundation doesn't traverse links; skipping descendants on a leaf can skip its sibling's subtree.
            guard (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else { continue }
            result[url.standardizedFileURL.path] = root
        }
    }
    return result
}
func receivingFolderScanDue(roots: Set<String>, previous: Set<String>?, now: TimeInterval, last: TimeInterval) -> Bool {
    guard let previous, now.isFinite, last.isFinite, now >= last else { return true }
    return roots != previous || now - last >= 0.5
}
/// Invalidates queued main-thread deliveries immediately when monitoring stops.
/// The worker queue may be waiting for a macOS folder permission dialog.
final class MonitorDeliveryGate {
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var wanted = false
    func start() -> UInt64? {
        lock.lock(); defer { lock.unlock() }
        guard !wanted else { return nil }
        wanted = true; generation &+= 1; return generation
    }
    func stop() -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        wanted = false; generation &+= 1; return generation
    }
    func fail(_ token: UInt64) {
        lock.lock(); defer { lock.unlock() }
        if generation == token { wanted = false }
    }
    func matches(_ token: UInt64, active: Bool = false) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return generation == token && (!active || wanted)
    }
    func currentToken() -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        return generation
    }
}

struct AirDropObservedSend: Equatable {
    let success: Bool
    let bundleID: String?
}

struct AirDropLogStreamParser {
    private var line = [UInt8]()
    private var discarding = false

    mutating func consume(_ data: Data) -> [AirDropObservedSend] {
        var events: [AirDropObservedSend] = []
        for byte in data {
            if discarding {
                if byte == 10 { discarding = false }
            } else if byte == 10 {
                if let event = Self.parse(line) { events.append(event) }
                line.removeAll(keepingCapacity: true)
            } else if line.count < 65_536 {
                line.append(byte)
            } else {
                line.removeAll(keepingCapacity: true); discarding = true
            }
        }
        return events
    }

    private static func parse(_ line: [UInt8]) -> AirDropObservedSend? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
              let message = object["eventMessage"] as? String else { return nil }
        let bytes = Array(message.utf8)
        var bundle = [UInt8](repeating: 0, count: 256)
        let status = bytes.withUnsafeBufferPointer { input in
            bundle.withUnsafeMutableBufferPointer { output in
                rustAirDropSendResult(input.baseAddress, input.count, output.baseAddress, output.count)
            }
        }
        guard status == 1 || status == 2 else { return nil }
        let source = String(decoding: bundle.prefix { $0 != 0 }, as: UTF8.self)
        return AirDropObservedSend(success: status == 2, bundleID: source.isEmpty ? nil : source)
    }
}

final class AirDropSendWatcher {
    private let gate = MonitorDeliveryGate()
    private var process: Process?
    private var readSource: DispatchSourceRead?
    private var finishRead: (() -> Void)?
    private var stopRead: (() -> Void)?
    private let readQueue = DispatchQueue(label: "app.rium.notch.airdrop-send-stream", qos: .utility)
    private var launching = false
    private var retry: DispatchWorkItem?
    private var delay: TimeInterval = 2
    private let onResult: (AirDropObservedSend) -> Void
    private let onStatus: (String?) -> Void

    init(onResult: @escaping (AirDropObservedSend) -> Void, onStatus: @escaping (String?) -> Void) {
        self.onResult = onResult; self.onStatus = onStatus
    }
    func start() {
        precondition(Thread.isMainThread)
        guard let token = gate.start() else { return }
        delay = 2; launch(token)
    }
    func stop() {
        precondition(Thread.isMainThread)
        _ = gate.stop(); retry?.cancel(); retry = nil; launching = false
        let old = process; process = nil
        stopRead?(); stopRead = nil; finishRead = nil; readSource?.cancel(); readSource = nil
        if old?.isRunning == true { old?.terminate() }
        onStatus(nil)
    }
    private func launch(_ token: UInt64) {
        guard gate.matches(token, active: true), process == nil, !launching else { return }
        launching = true
        let child = Process(), output = Pipe()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        child.arguments = ["stream", "--style", "ndjson", "--predicate", "process == \"sharingd\" AND eventMessage CONTAINS \"AirDrop.TransferResult\""]
        child.standardInput = FileHandle.nullDevice; child.standardOutput = output; child.standardError = FileHandle.nullDevice
        let delivery = gate
        child.terminationHandler = { [weak self] child in
            DispatchQueue.main.async { self?.drainAndEnd(token, child: child) }
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard delivery.matches(token, active: true) else { return }
            do { try child.run() }
            catch {
                try? output.fileHandleForReading.close(); try? output.fileHandleForWriting.close()
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, self.gate.matches(token, active: true) else { return }
                    self.launching = false; self.scheduleRetry(token)
                }
                return
            }
            try? output.fileHandleForWriting.close()
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.gate.matches(token, active: true) else {
                    if child.isRunning { child.terminate() }
                    try? output.fileHandleForReading.close()
                    return
                }
                self.launching = false; self.process = child; self.onStatus(nil)
                self.watchOutput(output.fileHandleForReading, child: child, token: token)
                if !child.isRunning { self.drainAndEnd(token, child: child) }
            }
        }
    }
    private func watchOutput(_ reader: FileHandle, child: Process, token: UInt64) {
        assert(Thread.isMainThread)
        let fd = reader.fileDescriptor
        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else {
            try? reader.close(); ended(token, child: child); return
        }
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: readQueue)
        let streamGate = MonitorDeliveryGate()
        guard let streamToken = streamGate.start() else { try? reader.close(); ended(token, child: child); return }
        stopRead = { _ = streamGate.stop() }
        var parser = AirDropLogStreamParser()
        func drain() -> Bool {
            assert(!Thread.isMainThread)
            // Bound the final drain if another process kept the pipe open and keeps writing.
            for _ in 0..<16 {
                var buffer = [UInt8](repeating: 0, count: 65_536)
                let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
                if count > 0 {
                    for event in parser.consume(Data(buffer.prefix(count))) {
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self, self.gate.matches(token, active: true), self.process === child else { return }
                            self.delay = 2; self.onResult(event)
                        }
                    }
                } else if count == 0 { return true }
                else if errno == EINTR { continue }
                else { return errno != EAGAIN && errno != EWOULDBLOCK }
            }
            return false
        }
        source.setEventHandler { [weak self] in
            guard let self = self, self.gate.matches(token, active: true), streamGate.matches(streamToken, active: true) else { return }
            if drain() { DispatchQueue.main.async { [weak self] in self?.ended(token, child: child) } }
        }
        source.setCancelHandler { try? reader.close() }
        finishRead = { [weak self] in
            self?.readQueue.async { [weak self] in
                guard let self = self, self.gate.matches(token, active: true), streamGate.matches(streamToken, active: true) else { return }
                _ = drain()
                DispatchQueue.main.async { [weak self] in self?.ended(token, child: child) }
            }
        }
        readSource = source; source.resume()
    }
    private func drainAndEnd(_ token: UInt64, child: Process) {
        assert(Thread.isMainThread)
        guard gate.matches(token, active: true), process === child else { return }
        finishRead?()
    }
    private func ended(_ token: UInt64, child: Process) {
        assert(Thread.isMainThread)
        guard gate.matches(token, active: true), process === child else { return }
        process = nil; stopRead?(); stopRead = nil; finishRead = nil; readSource?.cancel(); readSource = nil
        if child.isRunning { child.terminate() }
        scheduleRetry(token)
    }
    private func scheduleRetry(_ token: UInt64) {
        guard gate.matches(token, active: true) else { return }
        onStatus("AirDrop 송신 감시 연결 대기 중")
        let wait = delay; delay = min(60, delay * 2)
        let work = DispatchWorkItem { [weak self] in self?.launch(token) }
        retry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: work)
    }
}
func watchedFileSnapshot(_ files: [URL]) -> [String: WatchedFileIdentity] {
    var result: [String: WatchedFileIdentity] = [:]
    for file in files {
        if let identity = watchedFileIdentity(file.path) { result[file.path] = identity }
    }
    return result
}
func watchedFileIdentity(_ path: String) -> WatchedFileIdentity? {
    var info = stat()
    guard lstat(path, &info) == 0 else { return nil }
    return WatchedFileIdentity(device: Int64(info.st_dev), inode: UInt64(info.st_ino))
}

struct CancelledReceiveGuard {
    private var cancelled: [String: WatchedFileIdentity] = [:]
    mutating func record(_ path: String, identity: WatchedFileIdentity?) {
        if let identity = identity { cancelled[path] = identity }
    }
    mutating func begin(_ path: String) { cancelled.removeValue(forKey: path) }
    mutating func blocks(_ path: String, identity: WatchedFileIdentity) -> Bool {
        guard let old = cancelled[path] else { return false }
        if old == identity { return true }
        cancelled.removeValue(forKey: path); return false
    }
    mutating func prune(_ current: [String: WatchedFileIdentity]) {
        cancelled = cancelled.filter { current[$0.key] == $0.value }
    }
    mutating func clear() { cancelled.removeAll() }
}

enum ReceiveDeliveryDecision: Equatable { case deliver, wait, discard }

// Coordinates the main-thread progress callbacks with file classification on the worker queue.
final class ReceiveDeliveryGate {
    private struct Candidate { let path: String; var cancelled: Bool; var interrupted: Bool }
    private let lock = NSLock()
    private var receiving: Set<String> = []
    private var candidates: [UUID: Candidate] = [:]

    func begin(path: String) -> UUID {
        lock.lock(); defer { lock.unlock() }
        let id = UUID(); candidates[id] = Candidate(path: path, cancelled: false, interrupted: false); return id
    }
    func update(paths: Set<String>, cancelled: Set<String>) {
        lock.lock(); defer { lock.unlock() }
        let began = paths.subtracting(receiving)
        receiving = paths
        for id in Array(candidates.keys) {
            guard let item = candidates[id] else { continue }
            if cancelled.contains(item.path) { candidates[id]?.cancelled = true }
            if began.contains(item.path) { candidates[id]?.interrupted = true }
        }
    }
    func finish(_ id: UUID, fileMatches: Bool) -> ReceiveDeliveryDecision {
        lock.lock(); defer { lock.unlock() }
        guard let item = candidates.removeValue(forKey: id), fileMatches, !item.cancelled else { return .discard }
        return item.interrupted || receiving.contains(item.path) ? .wait : .deliver
    }
    func clear() {
        lock.lock(); defer { lock.unlock() }
        receiving.removeAll(); candidates.removeAll()
    }
}

struct ReceiveCancellationTracker {
    private var cancelled: Set<String> = []
    mutating func finished(path: String, wasCancelled: Bool, remaining: Set<String>) -> Set<String> {
        if wasCancelled { cancelled.insert(path) }
        guard !remaining.contains(path) else { return [] }
        return cancelled.remove(path) == nil ? [] : [path]
    }
    mutating func clear() { cancelled.removeAll() }
}

/// File progress is a best-effort receiving signal, not proof of AirDrop.
/// Foundation invokes subscriber handlers on the main thread; KVO callbacks hop there.
private final class ReceiveProgressObserver: @unchecked Sendable {
    private var subscriber: Any?
    private var folderSubscribers: [String: (root: String, subscriber: Any)] = [:]
    private var root: URL?
    private var generation: UInt64 = 0
    private var active = false
    private var progresses: [UUID: Progress] = [:]
    private var paths: [UUID: String] = [:]
    private var filePaths: [UUID: String] = [:]
    private var directProgress: Set<UUID> = []
    private var cancellations = ReceiveCancellationTracker()
    private var observations: [UUID: [NSKeyValueObservation]] = [:]
    private var pendingPublish: DispatchWorkItem?
    private let changed: (Bool, Double?, Set<String>, Set<String>, [String: String]) -> Void
    init(changed: @escaping (Bool, Double?, Set<String>, Set<String>, [String: String]) -> Void) { self.changed = changed }

    func start(directory: URL) {
        precondition(Thread.isMainThread)
        if active { stop() }
        active = true; generation &+= 1; let token = generation
        let parent = directory.standardizedFileURL
        root = parent
        subscriber = subscribe(directory: parent, transferRoot: nil, token: token)
    }

    func watchFolders(_ folders: [String: String]) {
        precondition(Thread.isMainThread)
        guard active, let root else { return }
        let activePaths = Set(self.paths.values)
        for path in Array(folderSubscribers.keys) {
            guard let subscription = folderSubscribers[path], folders[path] != subscription.root,
                  !activePaths.contains(subscription.root) else { continue }
            Progress.removeSubscriber(subscription.subscriber); folderSubscribers.removeValue(forKey: path)
        }
        // shortcut: at most 128 candidate folders; extend this when large concurrent transfers are supported.
        for path in folders.keys.sorted() where folderSubscribers[path] == nil && folderSubscribers.count < 128 {
            guard let transferRoot = folders[path] else { continue }
            let folder = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
            let transfer = URL(fileURLWithPath: transferRoot, isDirectory: true).standardizedFileURL
            var info = stat()
            guard transfer.deletingLastPathComponent().path == root.path,
                  folder.pathComponents.starts(with: transfer.pathComponents),
                  lstat(folder.path, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else { continue }
            folderSubscribers[path] = (transferRoot, subscribe(directory: folder, transferRoot: transferRoot, token: generation))
        }
    }

    private func subscribe(directory: URL, transferRoot: String?, token: UInt64) -> Any {
        Progress.addSubscriber(forFileURL: directory, withPublishingHandler: { [weak self] progress in
            precondition(Thread.isMainThread)
            let metadata = progress.userInfo
            guard let self = self, self.active, self.generation == token,
                  metadata[.fileOperationKindKey] as? String == Progress.FileOperationKind.receiving.rawValue,
                  let file = (metadata[.fileURLKey] as? URL)?.standardizedFileURL, file.isFileURL,
                  file.deletingLastPathComponent().path == directory.path else { return nil }
            let id = UUID()
            self.progresses[id] = progress
            self.paths[id] = transferRoot ?? file.path
            self.filePaths[id] = file.path
            if transferRoot == nil { self.directProgress.insert(id) }
            let fractionObservation = progress.observe(\.fractionCompleted, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, self.active, self.generation == token else { return }
                    self.schedulePublish()
                }
            }
            let indeterminateObservation = progress.observe(\.isIndeterminate, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, self.active, self.generation == token else { return }
                    self.schedulePublish()
                }
            }
            self.observations[id] = [fractionObservation, indeterminateObservation]
            self.publish()
            return { [weak self] in
                DispatchQueue.main.async {
                    guard let self = self, self.active, self.generation == token else { return }
                    self.observations.removeValue(forKey: id)
                    if self.progresses[id]?.isCancelled == true {
                        self.finishProgress(id, token: token)
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + airDropReceiveSettleSeconds()) { [weak self] in
                            self?.finishProgress(id, token: token)
                        }
                    }
                }
            }
        })
    }

    private func finishProgress(_ id: UUID, token: UInt64) {
        guard active, generation == token, let path = paths.removeValue(forKey: id) else { return }
        // shortcut: only explicit cancellation is known; verify failed-transfer signals separately.
        let progress = progresses.removeValue(forKey: id)
        filePaths.removeValue(forKey: id)
        directProgress.remove(id)
        let cancelled = cancellations.finished(path: path, wasCancelled: progress?.isCancelled == true,
                                                remaining: Set(paths.values))
        publish(cancelled: cancelled)
    }

    private func schedulePublish() {
        precondition(Thread.isMainThread)
        guard pendingPublish == nil else { return }
        let token = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.active, self.generation == token else { return }
            self.pendingPublish = nil
            self.publish()
        }
        pendingPublish = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    private func publish(cancelled: Set<String> = []) {
        precondition(Thread.isMainThread)
        pendingPublish?.cancel(); pendingPublish = nil
        let activePaths = Set(paths.values)
        var trackedFiles: [String: String] = [:]
        for (id, file) in filePaths { if let root = paths[id] { trackedFiles[file] = root } }
        guard !progresses.isEmpty else { changed(false, nil, [], cancelled, trackedFiles); return }
        let samples = progresses.compactMap { id, progress -> ReceiveProgressSample? in
            guard let path = paths[id] else { return nil }
            let value = progress.fractionCompleted
            let fraction = !progress.isIndeterminate && value.isFinite && value >= 0 ? min(1, value) : nil
            return ReceiveProgressSample(root: path, direct: directProgress.contains(id), fraction: fraction)
        }
        changed(true, aggregateReceivingProgress(samples), activePaths, cancelled, trackedFiles)
    }

    func stop() {
        precondition(Thread.isMainThread)
        active = false; generation &+= 1
        pendingPublish?.cancel(); pendingPublish = nil
        if let subscriber = subscriber { Progress.removeSubscriber(subscriber) }
        for subscription in folderSubscribers.values { Progress.removeSubscriber(subscription.subscriber) }
        folderSubscribers.removeAll(); root = nil
        subscriber = nil; observations.removeAll(); progresses.removeAll(); paths.removeAll(); filePaths.removeAll(); directProgress.removeAll()
        cancellations.clear()
        changed(false, nil, [], [], [:])
    }
}

/// Downloads access and directory enumeration occur on a private queue so a
/// pending macOS permission dialog cannot block the notch's main thread.
final class AirDropMonitor {
    private let queue = DispatchQueue(label: "app.rium.notch.airdrop")
    private let onStatus: (String) -> Void
    private let onFile: (URL) -> Void
    private let classify: (String) -> Bool
    private let onReceiving: (Bool, Double?) -> Void
    private lazy var receiveProgress = ReceiveProgressObserver { [weak self] active, fraction, paths, cancelled, files in
        guard let self = self else { return }
        self.receiveDeliveryGate.update(paths: paths, cancelled: cancelled)
        self.onReceiving(active, fraction)
        let token = self.deliveryGate.currentToken()
        self.queue.async { [weak self] in
            guard let self = self, self.deliveryGate.matches(token, active: true), self.active, !self.progressResetting else { return }
            let began = paths.subtracting(self.receivingPaths)
            let ended = self.receivingPaths.subtracting(paths)
            for path in began {
                self.cancelledReceives.begin(path); self.receivingBaselines[path] = receiveFileStamp(path)
                self.changedReceivingRoots.remove(path)
            }
            self.changedReceivingRoots.formUnion(self.receiveContentChanges.update(files, stamp: receiveFileStamp))
            self.receivingPaths = paths
            for path in ended {
                let contentChanged = self.changedReceivingRoots.remove(path) != nil
                let baseline = self.receivingBaselines.removeValue(forKey: path) ?? .unknown
                if cancelled.contains(path) {
                    self.pending.removeValue(forKey: path)
                    self.cancelledReceives.record(path, identity: watchedFileIdentity(path))
                    continue
                }
                if self.pending[path] != nil || contentChanged || receiveFileChanged(from: baseline, to: receiveFileStamp(path)) {
                    self.pending[path] = ProcessInfo.processInfo.systemUptime - 1
                }
            }
            if !began.isEmpty || !ended.isEmpty { self.scan() }
        }
    }
    private let deliveryGate = MonitorDeliveryGate()
    private let receiveDeliveryGate = ReceiveDeliveryGate()
    private var activeToken: UInt64 = 0 // Accessed only on queue.
    private var directory: URL?
    private var source: DispatchSourceFileSystemObject?
    private var timer: DispatchSourceTimer?
    private var known: [String: WatchedFileIdentity] = [:]
    private var pending: [String: TimeInterval] = [:]
    private var receivingPaths: Set<String> = []
    private var receivingBaselines: [String: ReceiveFileStamp] = [:]
    private var receiveContentChanges = ReceiveContentChanges()
    private var changedReceivingRoots: Set<String> = []
    private var cancelledReceives = CancelledReceiveGuard()
    private var active = false
    private var sourceGeneration = 0
    private var progressResetting = false
    private var initialSince: Date?
    private var folderScanRoots: Set<String>?
    private var folderScanTime: TimeInterval = 0

    init(onStatus: @escaping (String) -> Void, onFile: @escaping (URL) -> Void, onReceiving: @escaping (Bool, Double?) -> Void = { _, _ in }, classify: @escaping (String) -> Bool = { path in path.withCString { isAirDropFile($0) == 1 } }) {
        self.onStatus = onStatus; self.onFile = onFile; self.onReceiving = onReceiving; self.classify = classify
    }
    private func status(_ message: String) {
        let token = activeToken
        DispatchQueue.main.async { if self.deliveryGate.matches(token) { self.onStatus(message) } }
    }
    func start(directoryOverride: URL? = nil) {
        guard let token = deliveryGate.start() else { return }
        queue.async { [self] in
            guard self.deliveryGate.matches(token, active: true), !self.active else { return }
            self.activeToken = token; self.active = true
            self.status("다운로드 폴더 확인 중")
            self.initialSince = Date(); self.known.removeAll(); self.pending.removeAll(); self.folderScanRoots = nil
            self.directory = directoryOverride ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            if self.attach() { self.status("AirDrop 수신 감시 중"); self.scan() }
            else { self.status("다운로드 폴더 연결 대기 중") }
            guard self.deliveryGate.matches(token, active: true) else { self.active = false; return }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + 1, repeating: 1)
            timer.setEventHandler { [weak self] in
                guard let self = self, self.active else { return }
                if self.directory == nil { self.directory = directoryOverride ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first }
                if self.source == nil { if self.attach() { self.status("AirDrop 수신 감시 중"); self.scan() } }
                else if !self.pending.isEmpty || self.receivingPaths.contains(where: receivingDirectoryExists) { self.scan() }
            }
            self.timer = timer; timer.resume()
        }
    }
    private func attach() -> Bool {
        guard active, !progressResetting, let directory = directory,
              let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return false }
        let files = entries.map(\.standardizedFileURL)
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return false }
        if let since = initialSince {
            let now = Date(), uptime = ProcessInfo.processInfo.systemUptime
            let cutoff = max(since, now.addingTimeInterval(-60))
            known = watchedFileSnapshot(files)
            // shortcut: creation dates can precede a completed transfer; compare live transfer events when available.
            for file in files {
                var info = stat()
                guard lstat(file.path, &info) == 0 else { continue }
                let kind = info.st_mode & mode_t(S_IFMT)
                guard kind == mode_t(S_IFREG) || kind == mode_t(S_IFDIR) else { continue }
                let created = Date(timeIntervalSince1970: Double(info.st_birthtimespec.tv_sec) + Double(info.st_birthtimespec.tv_nsec) / 1_000_000_000)
                if created >= cutoff && created <= now { pending[file.path] = uptime }
            }
            initialSince = nil
        }
        sourceGeneration += 1
        let generation = sourceGeneration
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete, .revoke], queue: queue)
        source.setEventHandler { [weak self] in
            guard let self = self, self.active, self.sourceGeneration == generation, let event = self.source?.data else { return }
            if !event.intersection([.rename, .delete, .revoke]).isEmpty {
                self.source?.cancel(); self.source = nil; self.status("다운로드 폴더 다시 연결 중")
                self.progressResetting = true
                self.folderScanRoots = nil
                self.receivingPaths.removeAll(); self.receivingBaselines.removeAll()
                self.receiveContentChanges.clear(); self.changedReceivingRoots.removeAll()
                let token = self.activeToken
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, self.deliveryGate.matches(token, active: true) else { return }
                    self.receiveProgress.stop(); self.receiveDeliveryGate.clear()
                    self.queue.async { [weak self] in
                        guard let self = self, self.active, self.sourceGeneration == generation,
                              self.deliveryGate.matches(token, active: true) else { return }
                        self.progressResetting = false
                    }
                }
            } else { self.scan() }
        }
        source.setCancelHandler { close(fd) }; self.source = source; source.resume()
        let token = activeToken
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.deliveryGate.matches(token, active: true) else { return }
            self.receiveProgress.start(directory: directory)
        }
        return true
    }
    private func scan() {
        guard active, let directory = directory,
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return }
        let current = watchedFileSnapshot(files.map(\.standardizedFileURL)), now = ProcessInfo.processInfo.systemUptime
        cancelledReceives.prune(current)
        for (path, identity) in current where known[path] != identity {
            if !cancelledReceives.blocks(path, identity: identity) { pending[path] = now }
        }
        known = current
        let roots = Set(pending.keys).union(receivingPaths)
        if receivingFolderScanDue(roots: roots, previous: folderScanRoots, now: now, last: folderScanTime) {
            folderScanRoots = roots; folderScanTime = now
            let folders = receivingDirectories(roots: roots)
            let token = activeToken
            DispatchQueue.main.async { [weak self] in
                guard let self, self.deliveryGate.matches(token, active: true) else { return }
                self.receiveProgress.watchFolders(folders)
            }
        }
        for path in Array(pending.keys) {
            guard let firstSeen = pending[path] else { continue }
            if let identity = current[path], cancelledReceives.blocks(path, identity: identity) { pending.removeValue(forKey: path); continue }
            switch receivePendingDecision(firstSeen: firstSeen, now: now, exists: current[path] != nil,
                                          receiving: receivingPaths.contains(path)) {
            case .discard: pending.removeValue(forKey: path); continue
            case .wait: continue
            case .classify: break
            }
            // Foundation's publish callback had a short opportunity to identify an in-flight receive.
            guard let identity = current[path] else { continue }
            let attempt = receiveDeliveryGate.begin(path: path)
            guard classify(path) else { _ = receiveDeliveryGate.finish(attempt, fileMatches: false); continue }
            pending.removeValue(forKey: path)
            let url = URL(fileURLWithPath: path), token = activeToken
            DispatchQueue.main.async {
                let matches = self.deliveryGate.matches(token, active: true) &&
                    watchedFileDeliveryMatches(expected: identity, actual: watchedFileIdentity(path))
                switch self.receiveDeliveryGate.finish(attempt, fileMatches: matches) {
                case .deliver: self.onFile(url)
                case .discard: break
                case .wait:
                    self.queue.async {
                        guard self.deliveryGate.matches(token, active: true), self.active,
                              watchedFileDeliveryMatches(expected: identity, actual: watchedFileIdentity(path)),
                              !self.cancelledReceives.blocks(path, identity: identity) else { return }
                        self.pending[path] = ProcessInfo.processInfo.systemUptime - 1
                    }
                }
            }
        }
    }
    func stop() {
        let token = deliveryGate.stop()
        if Thread.isMainThread { if deliveryGate.matches(token) { receiveProgress.stop(); receiveDeliveryGate.clear() } }
        else { DispatchQueue.main.async { [weak self] in
            guard let self = self, self.deliveryGate.matches(token) else { return }
            self.receiveProgress.stop(); self.receiveDeliveryGate.clear()
        } }
        queue.async {
            self.activeToken = token
            self.active = false; self.sourceGeneration += 1; self.source?.cancel(); self.source = nil
            self.timer?.cancel(); self.timer = nil; self.directory = nil; self.progressResetting = false; self.initialSince = nil; self.folderScanRoots = nil
            self.pending.removeAll(); self.receivingPaths.removeAll(); self.receivingBaselines.removeAll(); self.cancelledReceives.clear(); self.known.removeAll()
            self.receiveContentChanges.clear(); self.changedReceivingRoots.removeAll()
            self.status("AirDrop 수신 감시 꺼짐")
        }
    }
}
