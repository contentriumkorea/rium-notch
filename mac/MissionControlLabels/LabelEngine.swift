import AppKit
import ApplicationServices
import os

/// 상태 전환·수집 주기 담당. 수집은 직렬 큐, 표시는 메인 스레드에서 수행
final class LabelEngine {
    enum State: String { case inactive, idle, settling, showing }

    /// 초기 실험값. 측정 결과로 조정
    static let idleInterval: TimeInterval = 0.10
    static let openInterval: TimeInterval = 0.05
    static let noPermissionInterval: TimeInterval = 1.0
    static let stableObservationsRequired = 2

    private let log = Logger(subsystem: "com.markhan.MissionControlLabels", category: "engine")
    private let queue = DispatchQueue(label: "com.markhan.MissionControlLabels.collector", qos: .userInitiated)
    private let reader = MissionControlReader()
    private let activeSpaces = ActiveSpaces()
    private var previousSpaces: Set<UInt64>?
    private var trackingUntil = Date.distantPast
    private let resolver: WindowResolver
    private let sessions: SessionCounter
    private let overlay: OverlayController
    let diagnostics = Diagnostics()

    // 워커 큐에서만 접근하는 상태
    private var enabled = false
    private var generation = 0
    private var previousSnapshot: [Thumbnail] = []
    private var stableCount = 0
    private var renderedSnapshot: [Thumbnail]?
    private var retryUntil = Date.distantPast
    private var lastResolve = Date.distantPast
    private var bestLabelCount = 0
    private var wasOpen = false
    private var currentSession: SessionToken

    // 메인에서 읽는 표시용 상태
    private(set) var state: State = .inactive { didSet { onStateChange?(state) } }
    var onStateChange: ((State) -> Void)?
    var onDiagnosticWritten: ((URL?) -> Void)?
    var onPermissionChange: ((Bool) -> Void)?

    init(sessions: SessionCounter, overlay: OverlayController) {
        self.sessions = sessions
        self.overlay = overlay
        self.currentSession = sessions.current
        self.resolver = WindowResolver(excludedPIDs: [ProcessInfo.processInfo.processIdentifier])
    }

    func start() {
        queue.async {
            guard !self.enabled else { return }
            self.enabled = true
            self.generation += 1
            self.tick(generation: self.generation)
        }
    }

    func stop() {
        queue.async {
            self.enabled = false
            self.generation += 1
            self.endSessionIfOpen()
            DispatchQueue.main.async { self.state = .inactive }
        }
    }

    private func setState(_ s: State) {
        DispatchQueue.main.async { if self.state != s { self.state = s } }
    }

    private func schedule(after interval: TimeInterval, generation: Int) {
        queue.asyncAfter(deadline: .now() + interval) { [weak self] in
            self?.tick(generation: generation)
        }
    }

    private func endSessionIfOpen() {
        if wasOpen || renderedSnapshot != nil {
            wasOpen = false
            renderedSnapshot = nil
            retryUntil = .distantPast
            lastResolve = .distantPast
            bestLabelCount = 0
            previousSnapshot = []
            stableCount = 0
            previousSpaces = nil
            trackingUntil = .distantPast
            sessions.advance()
            resolver.invalidateSessionCaches()
            DispatchQueue.main.async { self.overlay.hide() }
        }
    }

    private var lastTrusted: Bool?

    private func tick(generation: Int) {
        guard enabled, generation == self.generation else { return }

        let trusted = AX.isTrusted()
        if lastTrusted != trusted {
            lastTrusted = trusted
            DispatchQueue.main.async { self.onPermissionChange?(trusted) }
        }
        guard trusted else {
            endSessionIfOpen()
            setState(.inactive)
            schedule(after: Self.noPermissionInterval, generation: generation)
            return
        }

        let groups = reader.missionControlGroups()
        guard let group = groups.first else {
            if wasOpen { log.debug("mission control closed") }
            endSessionIfOpen()
            setState(.idle)
            schedule(after: Self.idleInterval, generation: generation)
            return
        }

        if !wasOpen {
            wasOpen = true
            currentSession = sessions.advance()
            resolver.invalidateSessionCaches()
            trackingUntil = Date().addingTimeInterval(1.0)
            log.debug("mission control opened")
        }

        let currentSpaces = activeSpaces.current()
        if previousSpaces != currentSpaces {
            previousSpaces = currentSpaces
            currentSession = sessions.advance()
            renderedSnapshot = nil
            previousSnapshot = []
            stableCount = 0
            bestLabelCount = 0
            trackingUntil = Date().addingTimeInterval(1.0)
            resolver.invalidateSessionCaches()
            let session = currentSession
            DispatchQueue.main.async { if self.sessions.isCurrent(session) { self.overlay.hide() } }
        }
        let snapshot = reader.thumbnails(in: groups, activeSpaces: currentSpaces)
        if snapshot.isEmpty {
            renderedSnapshot = nil
            previousSnapshot = []
            bestLabelCount = 0
            let session = currentSession
            DispatchQueue.main.async { if self.sessions.isCurrent(session) { self.overlay.hide() } }
            setState(.settling)
            schedule(after: Self.openInterval, generation: generation)
            return
        }
        if currentSpaces != nil && Date() < trackingUntil {
            let outcome = resolver.resolve(snapshot, systemPIDs: reader.systemPIDs, fetchOriginalTitles: false, trackMotion: true)
            let session = currentSession
            DispatchQueue.main.async {
                self.overlay.show(outcome.labels, session: session)
                self.state = .showing
            }
            schedule(after: Self.openInterval, generation: generation)
            return
        }
        let stable = LayoutStability.isStable(previousSnapshot, snapshot)
        stableCount = stable ? stableCount + 1 : 1
        previousSnapshot = snapshot

        if stable && stableCount >= Self.stableObservationsRequired {
            let now = Date()
            let newLayout = renderedSnapshot == nil || !LayoutStability.isStable(renderedSnapshot!, snapshot)
            let shouldRetry = now < retryUntil && now.timeIntervalSince(lastResolve) >= 0.5
            if newLayout || shouldRetry {
                if newLayout { retryUntil = now.addingTimeInterval(3); bestLabelCount = 0 }
                lastResolve = now
                let session = currentSession
                // Show the thumbnail title immediately; resolving original AX titles can take longer.
                let outcome = resolver.resolve(snapshot, systemPIDs: reader.systemPIDs, fetchOriginalTitles: !newLayout)
                let st = outcome.stats
                log.info("resolved thumbnails=\(st.thumbnailCount) unique=\(st.uniqueMatches) ambiguous=\(st.ambiguousMatches) unmatched=\(st.unmatched) titleFallback=\(st.titleUniqueFallbacks) elapsedMs=\(Int(st.elapsed * 1000))")
                renderedSnapshot = snapshot
                if outcome.labels.count >= bestLabelCount {
                    bestLabelCount = outcome.labels.count
                    let labels = outcome.labels
                    DispatchQueue.main.async {
                        self.overlay.show(labels, session: session)
                        self.state = .showing
                    }
                }
                if diagnostics.isArmed {
                    diagnostics.disarm()
                    let url = diagnostics.write(reader: reader, group: group, thumbnails: snapshot,
                                                outcome: outcome, windows: resolver.lastWindows)
                    DispatchQueue.main.async { self.onDiagnosticWritten?(url) }
                }
            }
        } else if renderedSnapshot != nil {
            // 배치 변경(Space 이동, 창 재배치). 즉시 숨기고 재안정까지 대기
            renderedSnapshot = nil
            retryUntil = .distantPast
            bestLabelCount = 0
            DispatchQueue.main.async { self.overlay.hide() }
            setState(.settling)
        } else {
            setState(.settling)
        }
        schedule(after: Self.openInterval, generation: generation)
    }
}
