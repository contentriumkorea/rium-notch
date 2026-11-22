import AppKit
import AVFoundation

@_silgen_name("rium_sound_cue_admit")
private func rustSoundCueAdmit(_ kind: Int32, _ previous: Int32, _ elapsed: Double, _ free: Int32) -> Int32

enum FeedbackSound {
    case agentRunning, agentAttention, agentDone, agentFailed, agentMessage, dictationBegin, dictationEnd, timer
    private static let lock = NSLock()
    private static var lastCue: (kind: Int32, time: TimeInterval)?
    private static var timerAlarm: NSSound?
    private static var timerAlarmStop: DispatchWorkItem?
    static var timerAlarmIsPlaying: Bool { timerAlarm != nil }

    static var timerEnabled: Bool {
        let defaults = UserDefaults.standard
        return (defaults.object(forKey: "rium.sound.enabled") as? Bool ?? true)
            && (defaults.object(forKey: "rium.sound.timer") as? Bool ?? true)
    }

    static var quietForPrivacy: Bool {
        // shortcut: device use and mirroring do not detect every call; extend when a reliable signal is available.
        NSScreen.screens.contains(where: { displayIdentifier($0).map { CGDisplayIsInMirrorSet($0) != 0 } ?? false })
            || AVCaptureDevice.devices(for: .audio).contains(where: \.isInUseByAnotherApplication)
            || AVCaptureDevice.devices(for: .video).contains(where: \.isInUseByAnotherApplication)
    }

    static func startTimerAlarm() {
        stopTimerAlarm()
        guard timerEnabled, !quietForPrivacy,
              let sound = NSSound(named: NSSound.Name("Glass"))?.copy() as? NSSound else { return }
        sound.volume = 0.3; sound.loops = true
        guard sound.play() else { return }
        timerAlarm = sound
        let stop = DispatchWorkItem { stopTimerAlarm() }
        timerAlarmStop = stop
        DispatchQueue.main.asyncAfter(deadline: .now() + timerAlarmSoundSeconds(), execute: stop)
        // shortcut: the system sound replaces the reference's bundled alarm until its audio is compared.
    }

    static func stopTimerAlarm() {
        timerAlarmStop?.cancel(); timerAlarmStop = nil
        timerAlarm?.stop(); timerAlarm = nil
    }

    func play(previewVisible: Bool = true) {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "rium.sound.enabled") as? Bool ?? true else { return }
        let key: String
        let name: String
        let cue: Int32?
        switch self {
        case .agentRunning: key = "rium.sound.agent"; name = "Tink"; cue = 2
        case .agentAttention: key = "rium.sound.agent"; name = "Ping"; cue = 0
        case .agentDone: key = "rium.sound.agent"; name = "Glass"; cue = 1
        // shortcut: the reference has no separate failed cue; this mapping needs comparison.
        case .agentFailed: key = "rium.sound.agent"; name = "Basso"; cue = 0
        case .agentMessage: key = "rium.sound.agent"; name = "Pop"; cue = 3
        case .dictationBegin: key = "rium.sound.dictation"; name = "Tink"; cue = 4
        case .dictationEnd: key = "rium.sound.dictation"; name = "Pop"; cue = 5
        case .timer: key = "rium.sound.timer"; name = "Glass"; cue = nil
        }
        guard defaults.object(forKey: key) as? Bool ?? (key == "rium.sound.timer") else { return }
        guard !Self.quietForPrivacy, let sound = NSSound(named: NSSound.Name(name)) else { return }
        if let cue = cue {
            let free = defaults.string(forKey: "rium.sound.agentMode") == "every"
            if cue == 2 && !free && !previewVisible { return }
            let now = ProcessInfo.processInfo.systemUptime
            Self.lock.lock()
            let previous = Self.lastCue
            let allowed = rustSoundCueAdmit(cue, previous?.kind ?? -1, max(0, now - (previous?.time ?? now)), free ? 1 : 0) == 1
            if allowed { Self.lastCue = (cue, now) }
            Self.lock.unlock()
            guard allowed else { return }
        }
        sound.volume = 0.3
        if sound.isPlaying { sound.stop() }
        sound.play()
    }
}
