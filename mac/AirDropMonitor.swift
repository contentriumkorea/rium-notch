import Foundation
import Darwin

@_silgen_name("rium_is_airdrop_file") func isAirDropFile(_ path: UnsafePointer<CChar>) -> Int32

struct WatchedFileIdentity: Equatable {
    let device: Int64
    let inode: UInt64
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
}
func watchedFileSnapshot(_ files: [URL]) -> [String: WatchedFileIdentity] {
    var result: [String: WatchedFileIdentity] = [:]
    for file in files {
        var info = stat()
        if lstat(file.path, &info) == 0 { result[file.path] = WatchedFileIdentity(device: Int64(info.st_dev), inode: UInt64(info.st_ino)) }
    }
    return result
}

/// Downloads access and directory enumeration occur on a private queue so a
/// pending macOS permission dialog cannot block the notch's main thread.
final class AirDropMonitor {
    private let queue = DispatchQueue(label: "app.rium.notch.airdrop")
    private let onStatus: (String) -> Void
    private let onFile: (URL) -> Void
    private let classify: (String) -> Bool
    private let deliveryGate = MonitorDeliveryGate()
    private var activeToken: UInt64 = 0 // Accessed only on queue.
    private var directory: URL?
    private var source: DispatchSourceFileSystemObject?
    private var timer: DispatchSourceTimer?
    private var known: [String: WatchedFileIdentity] = [:]
    private var pending: [String: Date] = [:]
    private var active = false
    private var sourceGeneration = 0

    init(onStatus: @escaping (String) -> Void, onFile: @escaping (URL) -> Void, classify: @escaping (String) -> Bool = { path in path.withCString { isAirDropFile($0) == 1 } }) {
        self.onStatus = onStatus; self.onFile = onFile; self.classify = classify
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
            guard let directory = directoryOverride ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first,
                  let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
                self.active = false; self.deliveryGate.fail(token); self.status("다운로드 폴더 접근을 확인해 주세요"); return
            }
            guard self.deliveryGate.matches(token, active: true) else { self.active = false; return }
            self.directory = directory; self.known = watchedFileSnapshot(files); self.pending = [:]
            guard self.attach() else { self.active = false; self.directory = nil; self.deliveryGate.fail(token); self.status("다운로드 폴더를 감시할 수 없습니다"); return }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + 2, repeating: 2)
            timer.setEventHandler { [weak self] in
                guard let self = self, self.active else { return }
                if self.source == nil { if self.attach() { self.status("AirDrop 수신 감시 중"); self.scan() } }
                else if !self.pending.isEmpty { self.scan() }
            }
            self.timer = timer; timer.resume(); self.status("AirDrop 수신 감시 중")
            self.scan() // Covers arrivals between the initial listing and source setup.
        }
    }
    private func attach() -> Bool {
        guard active, let directory = directory,
              (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) != nil else { return false }
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return false }
        sourceGeneration += 1
        let generation = sourceGeneration
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete, .revoke], queue: queue)
        source.setEventHandler { [weak self] in
            guard let self = self, self.active, self.sourceGeneration == generation, let event = self.source?.data else { return }
            if !event.intersection([.rename, .delete, .revoke]).isEmpty {
                self.source?.cancel(); self.source = nil; self.status("다운로드 폴더 다시 연결 중")
            } else { self.scan() }
        }
        source.setCancelHandler { close(fd) }; self.source = source; source.resume()
        return true
    }
    private func scan() {
        guard active, let directory = directory,
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return }
        let current = watchedFileSnapshot(files), now = Date()
        for (path, identity) in current where known[path] != identity { pending[path] = now }
        known = current
        for path in Array(pending.keys) {
            guard let firstSeen = pending[path] else { continue }
            if current[path] == nil || now.timeIntervalSince(firstSeen) > 60 { pending.removeValue(forKey: path); continue }
            if classify(path) {
                pending.removeValue(forKey: path)
                let url = URL(fileURLWithPath: path)
                let token = activeToken
                DispatchQueue.main.async { if self.deliveryGate.matches(token, active: true) { self.onFile(url) } }
            }
        }
    }
    func stop() {
        let token = deliveryGate.stop()
        queue.async {
            self.activeToken = token
            self.active = false; self.sourceGeneration += 1; self.source?.cancel(); self.source = nil
            self.timer?.cancel(); self.timer = nil; self.directory = nil; self.pending.removeAll(); self.known.removeAll()
            self.status("AirDrop 수신 감시 꺼짐")
        }
    }
}
