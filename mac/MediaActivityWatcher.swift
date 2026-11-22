import Darwin
import Foundation

struct MediaEventStreamParser {
    private var line = Data()
    private var discarding = false
    mutating func consume(_ data: Data) -> Bool {
        var changed = false
        for byte in data {
            if discarding {
                if byte == 10 { discarding = false }
            } else if byte == 10 {
                if let value = try? JSONSerialization.jsonObject(with: line, options: [.fragmentsAllowed]),
                   value is [String: Any] || value is NSNull { changed = true }
                line.removeAll(keepingCapacity: true)
            } else if line.count < 262_144 {
                line.append(byte)
            } else { line.removeAll(keepingCapacity: true); discarding = true }
        }
        return changed
    }
}

/// Uses the bundled adapter's metadata stream only as a signal to refresh.
final class MediaActivityWatcher {
    private let gate = MonitorDeliveryGate()
    private let onChange: () -> Void
    private var process: Process?
    private var readSource: DispatchSourceRead?
    private let readQueue = DispatchQueue(label: "app.rium.notch.media-stream", qos: .utility)
    private var launching = false
    private var retry: DispatchWorkItem?
    private var refresh: DispatchWorkItem?
    private var delay: TimeInterval = 2
    private var lastRefresh: TimeInterval = 0

    init(onChange: @escaping () -> Void) { self.onChange = onChange }

    func start() {
        precondition(Thread.isMainThread)
        guard let token = gate.start() else { return }
        delay = 2; lastRefresh = 0; launch(token)
    }
    func stop() {
        precondition(Thread.isMainThread)
        _ = gate.stop(); retry?.cancel(); refresh?.cancel(); retry = nil; refresh = nil; launching = false
        let old = process; process = nil
        readSource?.cancel(); readSource = nil
        if old?.isRunning == true { old?.terminate() }
    }
    private func launch(_ token: UInt64) {
        guard gate.matches(token, active: true), process == nil, !launching,
              let root = Bundle.main.resourceURL?.appendingPathComponent("mediaremote-adapter", isDirectory: true) else { return }
        launching = true
        let child = Process(), output = Pipe()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        child.arguments = [root.appendingPathComponent("mediaremote-adapter.pl").path,
                           root.appendingPathComponent("MediaRemoteAdapter.framework").path,
                           "stream", "--no-artwork", "--allow-missing-title", "--debounce=100"]
        child.standardInput = FileHandle.nullDevice; child.standardOutput = output; child.standardError = FileHandle.nullDevice
        let delivery = gate
        child.terminationHandler = { [weak self] child in
            DispatchQueue.main.async { self?.ended(token, child: child) }
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
                self.launching = false; self.process = child
                guard child.isRunning else {
                    try? output.fileHandleForReading.close()
                    self.ended(token, child: child)
                    return
                }
                self.watchOutput(output.fileHandleForReading, child: child, token: token)
            }
        }
    }

    private func watchOutput(_ reader: FileHandle, child: Process, token: UInt64) {
        assert(Thread.isMainThread)
        let fd = reader.fileDescriptor
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: readQueue)
        var parser = MediaEventStreamParser()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        source.setEventHandler { [weak self] in
            guard let self = self, self.gate.matches(token, active: true) else { return }
            // An open pipe can wait for the requested length with FileHandle.
            let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if count < 0 && (errno == EINTR || errno == EAGAIN) { return }
            guard count > 0 else {
                DispatchQueue.main.async { [weak self] in self?.ended(token, child: child) }
                return
            }
            if parser.consume(Data(buffer.prefix(count))) {
                DispatchQueue.main.async { [weak self] in self?.received(token, child: child) }
            }
        }
        source.setCancelHandler { try? reader.close() }
        readSource = source
        source.resume()
    }

    private func received(_ token: UInt64, child: Process) {
        assert(Thread.isMainThread)
        guard gate.matches(token, active: true), process === child else { return }
        delay = 2
        guard refresh == nil else { return }
        let wait = max(0, 0.75 - (ProcessInfo.processInfo.systemUptime - lastRefresh))
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.gate.matches(token, active: true) else { return }
            self.refresh = nil; self.lastRefresh = ProcessInfo.processInfo.systemUptime; self.onChange()
        }
        refresh = work; DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: work)
    }
    private func ended(_ token: UInt64, child: Process) {
        assert(Thread.isMainThread)
        guard gate.matches(token, active: true), process === child else { return }
        process = nil
        readSource?.cancel(); readSource = nil
        if child.isRunning { child.terminate() }
        // The final stream event can race with process termination.
        onChange()
        scheduleRetry(token)
    }
    private func scheduleRetry(_ token: UInt64) {
        guard gate.matches(token, active: true) else { return }
        let wait = delay; delay = min(60, delay * 2)
        let work = DispatchWorkItem { [weak self] in self?.launch(token) }
        retry = work; DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: work)
    }
}
