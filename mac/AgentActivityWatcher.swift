import Foundation
import CoreServices

// The stream owns its callback box; the box does not keep the watcher alive.
private final class AgentActivityCallbackBox {
    weak var watcher: AgentActivityWatcher?
    let generation: UInt64
    init(watcher: AgentActivityWatcher, generation: UInt64) {
        self.watcher = watcher; self.generation = generation
    }
}
private let agentActivityRetain: CFAllocatorRetainCallBack = { info in
    guard let info else { return nil }
    _ = Unmanaged<AgentActivityCallbackBox>.fromOpaque(info).retain()
    return info
}
private let agentActivityRelease: CFAllocatorReleaseCallBack = { info in
    guard let info else { return }
    Unmanaged<AgentActivityCallbackBox>.fromOpaque(info).release()
}

// FSEvents watches entire existing session trees. Paths stay in the local helper.
private let agentActivityFSEventCallback: FSEventStreamCallback = { _, info, count, rawPaths, flags, _ in
    guard let info = info else { return }
    let box = Unmanaged<AgentActivityCallbackBox>.fromOpaque(info).takeUnretainedValue()
    guard let watcher = box.watcher else { return }
    let rootChanged = (0..<count).contains { index in
        flags[index] & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged) != 0
    }
    let paths = Unmanaged<CFArray>.fromOpaque(rawPaths).takeUnretainedValue() as NSArray
    watcher.eventsArrived(rootChanged: rootChanged, paths: paths.compactMap { $0 as? String }, generation: box.generation)
}

final class AgentActivityWatcher {
    private struct RootIdentity: Equatable {
        let path: String
        let device: UInt64
        let inode: UInt64
    }
    private struct SessionFileWatch {
        let token: UUID
        let source: DispatchSourceFileSystemObject
    }

    private let changed: () -> Void
    private let sessionRoots: [String: URL]
    private let candidateRoots: [URL]
    private var roots: [RootIdentity] = []
    private var stream: FSEventStreamRef?
    private var streamGeneration: UInt64 = 0
    private var pending: DispatchWorkItem?
    private var lastDelivery = -Double.infinity
    private var running = false
    private var observedFiles: [String: TimeInterval] = [:]
    private var sessionFiles: [String: SessionFileWatch] = [:]

    init(changed: @escaping () -> Void) {
        self.changed = changed
        let env = ProcessInfo.processInfo.environment
        let home = URL(fileURLWithPath: env["HOME"] ?? NSHomeDirectory(), isDirectory: true)
        let codex = env["CODEX_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? home.appendingPathComponent(".codex", isDirectory: true)
        let claude = env["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? home.appendingPathComponent(".claude", isDirectory: true)
        let codexRoot = codex.appendingPathComponent("sessions", isDirectory: true)
        let claudeRoot = claude.appendingPathComponent("projects", isDirectory: true)
        sessionRoots = ["codex": codexRoot, "claude": claudeRoot]
        candidateRoots = [
            codexRoot,
            claudeRoot,
            home.appendingPathComponent("Library/Application Support/Rium Notch/agent-sessions", isDirectory: true),
            home.appendingPathComponent("Library/Application Support/NotchPilot/codex-sessions", isDirectory: true)
        ]
    }

    // All stream lifecycle and callbacks run on the main queue, matching the
    // Model that owns this watcher. The 10-second fallback calls reconcile so
    // new or replaced roots and temporarily unavailable streams can recover.
    func start() {
        guard !running else { return }
        running = true
        reconcileRoots()
    }

    func reconcileRoots() {
        guard running else { return }
        let manager = FileManager.default
        var seen = Set<String>()
        let current = candidateRoots.compactMap { candidate -> RootIdentity? in
            let path = candidate.standardizedFileURL.resolvingSymlinksInPath().path
            guard seen.insert(path).inserted,
                  let attributes = try? manager.attributesOfItem(atPath: path),
                  attributes[.type] as? FileAttributeType == .typeDirectory,
                  let device = (attributes[.systemNumber] as? NSNumber)?.uint64Value,
                  let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value else { return nil }
            return RootIdentity(path: path, device: device, inode: inode)
        }
        guard current != roots || (stream == nil && !current.isEmpty) else { return }
        if current != roots { cancelSessionFiles() }
        releaseStream()
        roots = current
        guard !current.isEmpty else { return }
        let box = AgentActivityCallbackBox(watcher: self, generation: streamGeneration)
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(box).toOpaque(),
                                           retain: agentActivityRetain, release: agentActivityRelease, copyDescription: nil)
        let paths = current.map(\.path) as CFArray
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagUseCFTypes)
        guard let created = FSEventStreamCreate(kCFAllocatorDefault, agentActivityFSEventCallback, &context, paths,
                                                 FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.20, flags) else { return }
        FSEventStreamSetDispatchQueue(created, DispatchQueue.main)
        guard FSEventStreamStart(created) else {
            FSEventStreamInvalidate(created); FSEventStreamRelease(created)
            return
        }
        stream = created
    }

    func watchSessionFiles(_ files: [(provider: String, relativePath: String)]) {
        guard running else { return }
        let paths = Set(sessionRoots.flatMap { provider, directory -> [String] in
            let root = directory.standardizedFileURL.resolvingSymlinksInPath()
            return Array(files.lazy.filter { $0.provider == provider }.compactMap { file -> String? in
                let relative = file.relativePath
                guard relative.utf8.count <= 2048, relative.hasSuffix(".jsonl"), !relative.hasPrefix("/"),
                      !relative.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
                let path = root.appendingPathComponent(relative).standardizedFileURL.resolvingSymlinksInPath().path
                return path.hasPrefix(root.path + "/") ? path : nil
            }.prefix(8))
        })
        for path in Set(sessionFiles.keys).subtracting(paths) {
            sessionFiles.removeValue(forKey: path)?.source.cancel()
        }
        for path in paths where sessionFiles[path] == nil {
            let fd = open(path, O_EVTONLY | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { continue }
            var metadata = stat()
            guard fstat(fd, &metadata) == 0, metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
                close(fd)
                continue
            }
            let token = UUID()
            let invalidated: DispatchSource.FileSystemEvent = [.delete, .rename, .revoke]
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd,
                eventMask: [.write, .extend, invalidated], queue: .main)
            source.setCancelHandler { close(fd) }
            source.setEventHandler { [weak self] in
                guard let self, let watched = self.sessionFiles[path], watched.token == token else { return }
                if !watched.source.data.intersection(invalidated).isEmpty {
                    self.sessionFiles.removeValue(forKey: path)?.source.cancel()
                }
                self.eventsArrived(rootChanged: false, paths: [path], generation: self.streamGeneration)
            }
            sessionFiles[path] = SessionFileWatch(token: token, source: source)
            source.resume()
        }
    }

    private func cancelSessionFiles() {
        for watch in sessionFiles.values { watch.source.cancel() }
        sessionFiles.removeAll()
    }

    fileprivate func eventsArrived(rootChanged: Bool, paths: [String], generation: UInt64) {
        guard running, generation == streamGeneration else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let transcriptRoots = sessionRoots.values.map { $0.standardizedFileURL.resolvingSymlinksInPath().path + "/" }
        observedFiles = observedFiles.filter { now >= $0.value && now - $0.value < 86400 }
        for path in paths where transcriptRoots.contains(where: { path.hasPrefix($0) }) && path.hasSuffix(".jsonl") && path.utf8.count <= 2048
            && !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            observedFiles[path] = now
        }
        if observedFiles.count > 64 {
            observedFiles = Dictionary(uniqueKeysWithValues: observedFiles.sorted { $0.value > $1.value }.prefix(64).map { ($0.key, $0.value) })
        }
        if rootChanged { DispatchQueue.main.async { [weak self] in self?.reconcileRoots() } }
        guard pending == nil else { return }
        // Coalesce bursts while bounding latency and Rust helper churn. Do not
        // move the deadline on later events: sustained activity still refreshes.
        let delay = max(0.25, 0.75 - (ProcessInfo.processInfo.systemUptime - lastDelivery))
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.running else { return }
            self.pending = nil
            self.lastDelivery = ProcessInfo.processInfo.systemUptime
            self.changed()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func observedSessionPaths() -> [String] {
        let now = ProcessInfo.processInfo.systemUptime
        return observedFiles.filter { now >= $0.value && now - $0.value < 86400 }
            .sorted { $0.value > $1.value }.map(\.key)
    }

    private func releaseStream() {
        streamGeneration &+= 1
        guard let existing = stream else { return }
        stream = nil
        FSEventStreamStop(existing)
        FSEventStreamInvalidate(existing)
        FSEventStreamRelease(existing)
    }

    func stop() {
        guard running else { return }
        running = false
        pending?.cancel(); pending = nil
        cancelSessionFiles()
        releaseStream(); roots = []; observedFiles = [:]
    }

    static func testStaleCallbackLifetime() -> Bool {
        var watcher: AgentActivityWatcher? = AgentActivityWatcher(changed: {})
        watcher?.running = true; watcher?.streamGeneration = 2
        let box = AgentActivityCallbackBox(watcher: watcher!, generation: 1)
        box.watcher?.eventsArrived(rootChanged: false, paths: [], generation: box.generation)
        guard watcher?.pending == nil else { return false }
        watcher = nil
        return box.watcher == nil
    }

    deinit { stop() }
}
