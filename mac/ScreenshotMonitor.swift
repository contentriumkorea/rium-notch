import Foundation
import CoreFoundation
import CoreServices
import Darwin
import ImageIO
import UniformTypeIdentifiers

@_silgen_name("rium_screenshot_shortcut_poll_interval")
private func rustScreenshotShortcutPollInterval(_ age: Double) -> Double

@_silgen_name("rium_screenshot_scan_delay")
private func rustScreenshotScanDelay(_ burstAge: Double) -> Double

@_silgen_name("rium_screenshot_candidate_active")
private func rustScreenshotCandidateActive(_ firstSeen: Double, _ now: Double, _ exists: Int32) -> Int32

func screenshotPendingAfterScan(known: [String: WatchedFileIdentity], current: [String: WatchedFileIdentity],
                                pending: [String: TimeInterval], now: TimeInterval) -> [String: TimeInterval] {
    var previousPaths: [WatchedFileIdentity: [String]] = [:]
    for (path, identity) in known { previousPaths[identity, default: []].append(path) }
    var result: [String: TimeInterval] = [:]
    var usedPaths = Set<String>()
    var newIdentities = Set<WatchedFileIdentity>()
    for path in current.keys.sorted() {
        guard let identity = current[path] else { continue }
        if known[path] == identity {
            if let first = pending[path] { result[path] = first; usedPaths.insert(path) }
        } else if let paths = previousPaths[identity] {
            if let old = paths.sorted().first(where: { current[$0] != identity && pending[$0] != nil && !usedPaths.contains($0) }),
               let first = pending[old] {
                result[path] = first; usedPaths.insert(old)
            }
        } else if newIdentities.insert(identity).inserted {
            result[path] = now
        }
    }
    return result
}

func screenshotPath(for identity: WatchedFileIdentity, in files: [String: WatchedFileIdentity]) -> String? {
    files.keys.sorted().first { files[$0] == identity }
}

/// Watches the configured screenshot directory off the main thread. Only new
/// files with the macOS screenshot metadata flag are surfaced.
final class ScreenshotMonitor {
    private let queue = DispatchQueue(label: "app.rium.notch.screenshots")
    private let onStatus: (String) -> Void
    private let onFile: (URL) -> Void
    private let deliveryGate = MonitorDeliveryGate()
    private var activeToken: UInt64 = 0 // Accessed only on queue.
    private let testClassifier: ((URL) -> Bool)?
    private let locationProvider: () -> URL?
    private var directory: URL?
    private var directoryOverride: URL?
    private var source: DispatchSourceFileSystemObject?
    private var timer: DispatchSourceTimer?
    private var directoryScan: DispatchWorkItem?
    private var directoryBurstStarted: TimeInterval?
    private var metadataRetry: DispatchWorkItem?
    private var shortcutPoll: DispatchSourceTimer?
    private var armedCapture: (date: Date, uptime: TimeInterval, customName: String?)?
    private static let metadataRetryWindow: TimeInterval = 1
    private var known: [String: WatchedFileIdentity] = [:]
    private var pending: [String: TimeInterval] = [:]
    private var previousPending: [String: (identity: WatchedFileIdentity, first: TimeInterval)] = [:]
    private var active = false
    private var waitingForLocation = false
    private var sourceGeneration = 0
    private var lastLocationCheck = Date.distantPast

    init(onStatus: @escaping (String) -> Void, onFile: @escaping (URL) -> Void, classify: ((URL) -> Bool)? = nil, locationProvider: @escaping () -> URL? = ScreenshotMonitor.configuredDirectory) {
        self.onStatus = onStatus; self.onFile = onFile; self.testClassifier = classify; self.locationProvider = locationProvider
    }
    private static func configuredDirectory() -> URL? {
        let configured = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location")
        return configured.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true).standardizedFileURL }
            ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.standardizedFileURL
    }
    func armShortcutCapture() {
        let date = Date(), uptime = ProcessInfo.processInfo.systemUptime
        let name = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "name")
        queue.async { [self] in
            guard self.active, self.deliveryGate.matches(self.activeToken, active: true) else { return }
            self.finishShortcutCapture()
            self.armedCapture = (date, uptime, name)
            let interval = rustScreenshotShortcutPollInterval(0)
            let poll = DispatchSource.makeTimerSource(queue: self.queue)
            poll.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(30))
            poll.setEventHandler { [weak self] in
                guard let self, self.deliveryGate.matches(self.activeToken, active: true),
                      let capture = self.armedCapture else { return }
                if rustScreenshotShortcutPollInterval(ProcessInfo.processInfo.systemUptime - capture.uptime) > 0 { self.scan() }
                else { self.finishShortcutCapture() }
            }
            self.shortcutPoll = poll
            poll.resume()
        }
    }
    func cancelShortcutCapture() {
        queue.async { self.finishShortcutCapture() }
    }
    private func finishShortcutCapture() {
        shortcutPoll?.cancel()
        shortcutPoll = nil
        armedCapture = nil
    }
    private func classify(_ url: URL) -> Bool {
        if let testClassifier { return testClassifier(url) }
        var info = stat()
        guard lstat(url.path, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else { return false }
        // Spotlight may not index temporary, external, or excluded folders.
        // macOS also stores this boolean as a binary property-list xattr.
        if let direct = Self.screenshotAttribute(url.path) { return direct }
        if let item = MDItemCreate(nil, url.path as CFString),
           let value = MDItemCopyAttribute(item, "kMDItemIsScreenCapture" as CFString) as? Bool { return value }
        guard let capture = armedCapture, info.st_size > 0,
              rustScreenshotShortcutPollInterval(ProcessInfo.processInfo.systemUptime - capture.uptime) > 0,
              url.deletingLastPathComponent().resolvingSymlinksInPath() == directory?.resolvingSymlinksInPath() else { return false }
        let created = Date(timeIntervalSince1970: Double(info.st_birthtimespec.tv_sec) + Double(info.st_birthtimespec.tv_nsec) / 1_000_000_000)
        guard created >= capture.date else { return false }
        let stem = url.deletingPathExtension().lastPathComponent.lowercased()
        // shortcut: untagged captures use Korean, English or the configured name; extend when testing another system locale.
        var names = ["screenshot", "screen shot", "스크린샷", "스크린 샷"]
        if let customName = capture.customName, !customName.isEmpty { names.append(customName.lowercased()) }
        guard names.contains(where: { name in
            stem == name || (stem.hasPrefix(name + " ") && stem.dropFirst(name.count + 1).first?.isNumber == true)
        }), let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image),
            let image = CGImageSourceCreateWithURL(url as CFURL, nil),
            (CGImageSourceGetType(image) as String?) == type.identifier else { return false }
        return CGImageSourceGetStatus(image) == .statusComplete
    }
    private static func screenshotAttribute(_ path: String) -> Bool? {
        let name = "com.apple.metadata:kMDItemIsScreenCapture"
        let size = getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW)
        guard size > 0, size <= 4096 else { return nil }
        var bytes = Data(count: size)
        let read = bytes.withUnsafeMutableBytes { buffer in getxattr(path, name, buffer.baseAddress, size, 0, XATTR_NOFOLLOW) }
        guard read == size, let value = try? PropertyListSerialization.propertyList(from: bytes, options: [], format: nil),
              CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID(), let flag = value as? Bool else { return nil }
        return flag
    }
    private func status(_ value: String) {
        let token = activeToken
        DispatchQueue.main.async { if self.deliveryGate.matches(token) { self.onStatus(value) } }
    }
    func start(directoryOverride: URL? = nil) {
        guard let token = deliveryGate.start() else { return }
        queue.async { [self] in
            guard self.deliveryGate.matches(token, active: true), !self.active else { return }
            self.activeToken = token; self.active = true; self.status("스크린샷 폴더 확인 중")
            self.directoryOverride = directoryOverride?.standardizedFileURL
            self.lastLocationCheck = Date()
            if let directory = self.directoryOverride ?? self.locationProvider()?.standardizedFileURL,
               let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                self.directory = directory; self.known = watchedFileSnapshot(files); self.pending = [:]; self.previousPending = [:]
                if self.attach() { self.status("스크린샷 감시 중"); self.scan() }
                else { self.waitingForLocation = true; self.status("스크린샷 폴더 다시 연결 중") }
            } else {
                self.waitingForLocation = true; self.status("스크린샷 폴더 연결 대기 중")
            }
            guard self.deliveryGate.matches(token, active: true) else { self.active = false; return }
            let timer = DispatchSource.makeTimerSource(queue: self.queue); timer.schedule(deadline: .now() + 2, repeating: 2)
            timer.setEventHandler { [weak self] in
                guard let self = self, self.active else { return }
                if let desired = (self.directoryOverride ?? self.locationProvider())?.standardizedFileURL, desired != self.directory?.standardizedFileURL {
                    if self.switchDirectory(to: desired) { self.lastLocationCheck = Date(); self.waitingForLocation = false; self.status("스크린샷 감시 중"); self.scan() }
                    else {
                        if !self.waitingForLocation { self.waitingForLocation = true; self.status("새 스크린샷 폴더 연결 대기 중") }
                        if !self.pending.isEmpty || !self.previousPending.isEmpty { self.scan() }
                    }
                    return
                }
                self.lastLocationCheck = Date()
                if self.waitingForLocation { self.waitingForLocation = false; if self.source != nil { self.status("스크린샷 감시 중") } }
                if self.source == nil {
                    if self.attach() { self.status("스크린샷 감시 중"); self.scan() }
                    else if !self.previousPending.isEmpty { self.scan() }
                }
                else if self.directoryScan == nil && (!self.pending.isEmpty || !self.previousPending.isEmpty) { self.scan() }
            }; self.timer = timer; timer.resume()
        }
    }
    private func switchDirectory(to newDirectory: URL) -> Bool {
        guard let files = try? FileManager.default.contentsOfDirectory(at: newDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return false }
        let fd = open(newDirectory.path, O_EVTONLY)
        guard fd >= 0 else { return false }
        if directoryScan != nil { scan() }
        source?.cancel(); source = nil
        let now = Date()
        let uptime = ProcessInfo.processInfo.systemUptime
        // shortcut: creation time can precede the setting change by one poll; compare system events when available.
        let cutoff = max(lastLocationCheck, now.addingTimeInterval(-60))
        for (path, first) in pending {
            if let identity = known[path] { previousPending[path] = (identity, first) }
        }
        directory = newDirectory; known = watchedFileSnapshot(files); pending.removeAll()
        for file in files {
            var info = stat()
            guard lstat(file.path, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else { continue }
            let created = Date(timeIntervalSince1970: Double(info.st_birthtimespec.tv_sec) + Double(info.st_birthtimespec.tv_nsec) / 1_000_000_000)
            if created >= cutoff && created <= now && previousPending[file.path]?.identity != known[file.path] { pending[file.path] = uptime }
        }
        installSource(fd: fd)
        return true
    }
    private func attach() -> Bool {
        guard active, let directory = directory,
              (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) != nil else { return false }
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return false }
        installSource(fd: fd)
        return true
    }
    private func installSource(fd: Int32) {
        sourceGeneration += 1
        let generation = sourceGeneration
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete, .revoke], queue: queue)
        source.setEventHandler { [weak self] in
            guard let self = self, self.active, self.sourceGeneration == generation, let event = self.source?.data else { return }
            if !event.intersection([.rename, .delete, .revoke]).isEmpty {
                self.cancelDirectoryScan()
                self.source?.cancel(); self.source = nil; self.status("스크린샷 폴더 다시 연결 중")
            } else if event.contains(.write) {
                self.scheduleDirectoryScan()
            }
        }
        source.setCancelHandler { close(fd) }; self.source = source; source.resume()
    }
    private func scheduleDirectoryScan() {
        let now = ProcessInfo.processInfo.systemUptime
        let started = directoryBurstStarted ?? now
        directoryBurstStarted = started
        directoryScan?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.scan() }
        directoryScan = work
        queue.asyncAfter(deadline: .now() + rustScreenshotScanDelay(now - started), execute: work)
    }
    private func cancelDirectoryScan() {
        directoryScan?.cancel()
        directoryScan = nil
        directoryBurstStarted = nil
    }
    private func scan() {
        cancelDirectoryScan()
        guard active else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let current = directory.flatMap { try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) }
            .map(watchedFileSnapshot)
        for (path, candidate) in previousPending {
            guard previousPending[path]?.identity == candidate.identity else { continue }
            if rustScreenshotCandidateActive(candidate.first, now, 1) != 1 { previousPending.removeValue(forKey: path); continue }
            var info = stat()
            let present = lstat(path, &info) == 0 && (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG)
            let unchanged = present && candidate.identity == WatchedFileIdentity(device: Int64(info.st_dev), inode: UInt64(info.st_ino))
            if !unchanged {
                if let current, let moved = screenshotPath(for: candidate.identity, in: current) {
                    let first = previousPending.values.filter { $0.identity == candidate.identity }.map(\.first).min() ?? candidate.first
                    previousPending = previousPending.filter { $0.value.identity != candidate.identity }
                    known[moved] = candidate.identity
                    pending[moved] = min(pending[moved] ?? first, first)
                    continue
                }
                previousPending.removeValue(forKey: path)
                let parent = URL(fileURLWithPath: path).deletingLastPathComponent()
                if let files = try? FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]),
                   let moved = screenshotPath(for: candidate.identity, in: watchedFileSnapshot(files)),
                   previousPending[moved] == nil {
                    previousPending[moved] = candidate
                }
                continue
            }
            let url = URL(fileURLWithPath: path)
            if classify(url) {
                previousPending = previousPending.filter { $0.value.identity != candidate.identity }
                if let current {
                    for (alias, identity) in current where identity == candidate.identity {
                        known[alias] = identity; pending.removeValue(forKey: alias)
                    }
                }
                deliver(url, identity: candidate.identity, first: candidate.first)
            }
        }
        guard let current else { return }
        pending = screenshotPendingAfterScan(known: known, current: current, pending: pending, now: now)
        known = current
        resolvePending(now: now)
        scheduleMetadataRetry()
    }
    private func resolvePending(now: TimeInterval, recentOnly: Bool = false) {
        for path in Array(pending.keys) {
            guard let first = pending[path] else { continue }
            guard let identity = known[path], rustScreenshotCandidateActive(first, now, 1) == 1 else { pending.removeValue(forKey: path); continue }
            if recentOnly && (now - first >= Self.metadataRetryWindow || watchedFileIdentity(path) != identity) { continue }
            let url = URL(fileURLWithPath: path)
            if classify(url) {
                previousPending = previousPending.filter { $0.value.identity != identity }
                for (alias, sameIdentity) in known where sameIdentity == identity { pending.removeValue(forKey: alias) }
                deliver(url, identity: identity, first: first)
            }
        }
    }
    private func scheduleMetadataRetry() {
        let now = ProcessInfo.processInfo.systemUptime
        guard metadataRetry == nil, pending.values.contains(where: { now - $0 < Self.metadataRetryWindow }) else { return }
        // The capture flag may arrive after the last directory event.
        let retry = DispatchWorkItem { [weak self] in
            guard let self, self.active else { return }
            self.metadataRetry = nil
            self.resolvePending(now: ProcessInfo.processInfo.systemUptime, recentOnly: true)
            self.scheduleMetadataRetry()
        }
        metadataRetry = retry
        queue.asyncAfter(deadline: .now() + 0.2, execute: retry)
    }
    private func deliver(_ url: URL, identity: WatchedFileIdentity, first: TimeInterval) {
        let token = activeToken
        let shortcut = armedCapture?.uptime
        let belongsToShortcut = shortcut.map { first >= $0 } == true && url.deletingLastPathComponent().resolvingSymlinksInPath() == directory?.resolvingSymlinksInPath()
        DispatchQueue.main.async {
            guard self.deliveryGate.matches(token, active: true) else { return }
            guard watchedFileDeliveryMatches(expected: identity, actual: watchedFileIdentity(url.path)) else {
                self.queue.async {
                    guard self.deliveryGate.matches(token, active: true), self.active,
                          rustScreenshotCandidateActive(first, ProcessInfo.processInfo.systemUptime, 1) == 1 else { return }
                    let current = self.known.filter { watchedFileIdentity($0.key) == identity }
                    let parent = url.deletingLastPathComponent()
                    let files = (try? FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                    guard let path = screenshotPath(for: identity, in: current) ?? screenshotPath(for: identity, in: watchedFileSnapshot(files)) else { return }
                    if URL(fileURLWithPath: path).deletingLastPathComponent().standardizedFileURL == self.directory?.standardizedFileURL {
                        self.known[path] = identity
                        self.pending[path] = min(self.pending[path] ?? first, first)
                    } else if self.previousPending[path] == nil {
                        self.previousPending[path] = (identity, first)
                    }
                    self.scan()
                }
                return
            }
            if belongsToShortcut {
                self.queue.async {
                    if self.armedCapture?.uptime == shortcut { self.finishShortcutCapture() }
                }
            }
            self.onFile(url)
        }
    }
    func stop() {
        let token = deliveryGate.stop()
        queue.async {
            self.activeToken = token
            self.active = false; self.sourceGeneration += 1; self.source?.cancel(); self.source = nil; self.timer?.cancel(); self.timer = nil
            self.cancelDirectoryScan()
            self.finishShortcutCapture()
            self.metadataRetry?.cancel(); self.metadataRetry = nil
            self.directory = nil; self.directoryOverride = nil; self.waitingForLocation = false; self.pending.removeAll(); self.previousPending.removeAll(); self.known.removeAll(); self.status("스크린샷 감시 꺼짐")
        }
    }
}
