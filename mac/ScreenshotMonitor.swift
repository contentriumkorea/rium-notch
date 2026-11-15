import Foundation
import CoreFoundation
import CoreServices
import Darwin

/// Watches the configured screenshot directory off the main thread. Only new
/// files with the macOS screenshot metadata flag are surfaced.
final class ScreenshotMonitor {
    private let queue = DispatchQueue(label: "app.rium.notch.screenshots")
    private let onStatus: (String) -> Void
    private let onFile: (URL) -> Void
    private let deliveryGate = MonitorDeliveryGate()
    private var activeToken: UInt64 = 0 // Accessed only on queue.
    private let classify: (URL) -> Bool
    private let locationProvider: () -> URL?
    private var directory: URL?
    private var directoryOverride: URL?
    private var source: DispatchSourceFileSystemObject?
    private var timer: DispatchSourceTimer?
    private var known: [String: WatchedFileIdentity] = [:]
    private var pending: [String: Date] = [:]
    private var active = false
    private var waitingForLocation = false
    private var sourceGeneration = 0

    init(onStatus: @escaping (String) -> Void, onFile: @escaping (URL) -> Void, classify: @escaping (URL) -> Bool = ScreenshotMonitor.isScreenshot, locationProvider: @escaping () -> URL? = ScreenshotMonitor.configuredDirectory) {
        self.onStatus = onStatus; self.onFile = onFile; self.classify = classify; self.locationProvider = locationProvider
    }
    private static func configuredDirectory() -> URL? {
        let configured = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location")
        return configured.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true).standardizedFileURL }
            ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.standardizedFileURL
    }
    private static func isScreenshot(_ url: URL) -> Bool {
        var info = stat()
        guard lstat(url.path, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else { return false }
        // Spotlight may not index temporary, external, or excluded folders.
        // macOS also stores this boolean as a binary property-list xattr.
        if let direct = screenshotAttribute(url.path) { return direct }
        guard let item = MDItemCreate(nil, url.path as CFString),
              let value = MDItemCopyAttribute(item, "kMDItemIsScreenCapture" as CFString) else { return false }
        return (value as? Bool) == true
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
            guard let directory = self.directoryOverride ?? self.locationProvider()?.standardizedFileURL,
                  let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
                self.active = false; self.deliveryGate.fail(token); self.status("스크린샷 폴더 접근을 확인해 주세요"); return
            }
            guard self.deliveryGate.matches(token, active: true) else { self.active = false; return }
            self.directory = directory; self.known = watchedFileSnapshot(files); self.pending = [:]
            guard self.attach() else { self.active = false; self.directory = nil; self.deliveryGate.fail(token); self.status("스크린샷 폴더를 감시할 수 없습니다"); return }
            let timer = DispatchSource.makeTimerSource(queue: self.queue); timer.schedule(deadline: .now() + 2, repeating: 2)
            timer.setEventHandler { [weak self] in
                guard let self = self, self.active else { return }
                if let desired = (self.directoryOverride ?? self.locationProvider())?.standardizedFileURL, desired != self.directory?.standardizedFileURL {
                    if self.switchDirectory(to: desired) { self.waitingForLocation = false; self.status("스크린샷 감시 중"); self.scan() }
                    else {
                        if !self.waitingForLocation { self.waitingForLocation = true; self.status("새 스크린샷 폴더 연결 대기 중") }
                        if self.source != nil && !self.pending.isEmpty { self.scan() }
                    }
                    return
                }
                if self.waitingForLocation { self.waitingForLocation = false; if self.source != nil { self.status("스크린샷 감시 중") } }
                if self.source == nil { if self.attach() { self.status("스크린샷 감시 중"); self.scan() } }
                else if !self.pending.isEmpty { self.scan() }
            }; self.timer = timer; timer.resume()
            self.status("스크린샷 감시 중"); self.scan()
        }
    }
    private func switchDirectory(to newDirectory: URL) -> Bool {
        guard let files = try? FileManager.default.contentsOfDirectory(at: newDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return false }
        let fd = open(newDirectory.path, O_EVTONLY)
        guard fd >= 0 else { return false }
        source?.cancel(); source = nil
        directory = newDirectory; known = watchedFileSnapshot(files); pending.removeAll()
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
                self.source?.cancel(); self.source = nil; self.status("스크린샷 폴더 다시 연결 중")
            } else { self.scan() }
        }
        source.setCancelHandler { close(fd) }; self.source = source; source.resume()
    }
    private func scan() {
        guard active, let directory = directory,
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return }
        let current = watchedFileSnapshot(files), now = Date()
        for (path, identity) in current where known[path] != identity { pending[path] = now }; known = current
        for path in Array(pending.keys) {
            guard let first = pending[path] else { continue }
            if current[path] == nil || now.timeIntervalSince(first) > 60 { pending.removeValue(forKey: path); continue }
            let url = URL(fileURLWithPath: path)
            if classify(url) {
                pending.removeValue(forKey: path)
                let token = activeToken
                DispatchQueue.main.async { if self.deliveryGate.matches(token, active: true) { self.onFile(url) } }
            }
        }
    }
    func stop() {
        let token = deliveryGate.stop()
        queue.async {
            self.activeToken = token
            self.active = false; self.sourceGeneration += 1; self.source?.cancel(); self.source = nil; self.timer?.cancel(); self.timer = nil
            self.directory = nil; self.directoryOverride = nil; self.waitingForLocation = false; self.pending.removeAll(); self.known.removeAll(); self.status("스크린샷 감시 꺼짐")
        }
    }
}
