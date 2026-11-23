import SwiftUI
import AppKit

@_silgen_name("rium_notch_panel_retention")
private func rustNotchPanelRetention(_ expanded: Int32, _ shell: Int32, _ wasRetained: Int32) -> Int32

@_silgen_name("rium_notification_arrival_envelope")
private func rustNotificationArrivalEnvelope(_ elapsed: Double, _ duration: Double, _ reduceMotion: Int32) -> Double
@_silgen_name("rium_notification_arrival_gauge")
private func rustNotificationArrivalGauge(_ elapsed: Double, _ duration: Double) -> Double

@_silgen_name("rium_notch_arrival_segments")
private func rustNotchArrivalSegments(_ kind: Int32, _ elapsed: Double, _ pathLength: Double,
                                     _ arm: Double, _ notchWidth: Double, _ height: Double, _ shoulderArcLength: Double,
                                     _ output: UnsafeMutablePointer<Double>?, _ capacity: Int32) -> Int32
@_silgen_name("rium_notch_agenda_arrival_segments")
private func rustNotchAgendaArrivalSegments(_ kind: Int32, _ elapsed: Double, _ pathLength: Double,
                                           _ bottomHalfSpan: Double, _ shoulderDistance: Double,
                                           _ output: UnsafeMutablePointer<Double>?, _ capacity: Int32) -> Int32
@_silgen_name("rium_notch_response_halo")
private func rustNotchResponseHalo(_ elapsed: Double, _ notchWidth: Double, _ output: UnsafeMutablePointer<Double>?) -> Int32
@_silgen_name("rium_agent_arrival_arm_run")
private func rustAgentArrivalArmRun(_ preset: Int32, _ screenWidth: Double, _ notchWidth: Double) -> Double
@_silgen_name("rium_notch_shell_contour_metrics")
private func rustLightShellContourMetrics(_ width: Double, _ height: Double, _ bottom: Double, _ shoulder: Double,
                                          _ output: UnsafeMutablePointer<Double>?) -> Int32
@_silgen_name("rium_notch_shortcut_segments")
private func rustNotchShortcutSegments(_ kind: Int32, _ elapsed: Double, _ output: UnsafeMutablePointer<Double>?, _ capacity: Int32) -> Int32
@_silgen_name("rium_notch_shortcut_light_duration")
private func rustNotchShortcutLightDuration(_ kind: Int32) -> Double
@_silgen_name("rium_notch_shortcut_prism")
private func rustNotchShortcutPrism(_ kind: Int32, _ output: UnsafeMutablePointer<Double>?) -> Int32
@_silgen_name("rium_notch_select_all_trace")
private func rustNotchSelectAllTrace(_ elapsed: Double, _ output: UnsafeMutablePointer<Double>?) -> Int32
@_silgen_name("rium_notch_screenshot_flash")
private func rustNotchScreenshotFlash(_ elapsed: Double, _ output: UnsafeMutablePointer<Double>?) -> Int32
@_silgen_name("rium_screenshot_file_glow")
private func rustScreenshotFileGlow(_ elapsed: Double, _ arm: Double, _ length: Double, _ reduceMotion: Int32,
                                    _ output: UnsafeMutablePointer<Double>?) -> Int32
@_silgen_name("rium_notch_area_capture_reticle")
private func rustNotchAreaCaptureReticle(_ elapsed: Double, _ length: Double, _ arm: Double,
                                          _ shoulder: Double, _ side: Double, _ lower: Double,
                                          _ output: UnsafeMutablePointer<Double>?) -> Int32
@_silgen_name("rium_notch_shortcut_quit_crest")
private func rustNotchShortcutQuitCrest(_ elapsed: Double, _ length: Double, _ output: UnsafeMutablePointer<Double>?) -> Int32
@_silgen_name("rium_notch_shortcut_refresh_crest")
private func rustNotchShortcutRefreshCrest(_ elapsed: Double, _ length: Double, _ arm: Double,
                                            _ output: UnsafeMutablePointer<Double>?) -> Int32
@_silgen_name("rium_notch_shortcut_cut_crests")
private func rustNotchShortcutCutCrests(_ elapsed: Double, _ length: Double, _ output: UnsafeMutablePointer<Double>?) -> Int32
@_silgen_name("rium_notch_shortcut_undo_crest")
private func rustNotchShortcutUndoCrest(_ elapsed: Double, _ length: Double, _ arm: Double,
                                         _ output: UnsafeMutablePointer<Double>?) -> Int32
@_silgen_name("rium_notch_case_key_segments")
private func rustCaseKeySegments(_ kind: Int32, _ elapsed: Double, _ pathLength: Double, _ arm: Double, _ output: UnsafeMutablePointer<Double>?, _ capacity: Int32) -> Int32
@_silgen_name("rium_notch_case_key_prism")
private func rustCaseKeyPrism(_ kind: Int32, _ output: UnsafeMutablePointer<Double>?) -> Int32
@_silgen_name("rium_notch_system_hud_segments")
private func rustSystemHUDSegments(_ kind: Int32, _ level: Double, _ elapsed: Double, _ output: UnsafeMutablePointer<Double>?, _ capacity: Int32) -> Int32
@_silgen_name("rium_notch_system_hud_seconds")
func systemHUDSeconds() -> Double
@_silgen_name("rium_notch_system_hud_level")
private func rustSystemHUDLevel(_ previous: Double, _ current: Double, _ elapsed: Double) -> Double
@_silgen_name("rium_notch_system_hud_pulse_energy")
private func rustSystemHUDPulseEnergy(_ previous: Double, _ elapsed: Double) -> Double
@_silgen_name("rium_notch_system_hud_pulse_crest")
private func rustSystemHUDPulseCrest(_ level: Double, _ energy: Double, _ elapsed: Double, _ length: Double, _ output: UnsafeMutablePointer<Double>?) -> Int32
@_silgen_name("rium_notch_system_hud_restore_crests")
private func rustSystemHUDRestoreCrests(_ level: Double, _ energy: Double, _ elapsed: Double, _ length: Double, _ output: UnsafeMutablePointer<Double>?) -> Int32
@_silgen_name("rium_notch_system_hud_limit_flash")
private func rustSystemHUDLimitFlash(_ level: Double, _ energy: Double, _ elapsed: Double) -> Double
@_silgen_name("rium_notch_system_hud_brightness_flare")
private func rustSystemHUDBrightnessFlare(_ direction: Double, _ energy: Double, _ elapsed: Double, _ output: UnsafeMutablePointer<Double>?) -> Int32
@_silgen_name("rium_notch_system_hud_volume_flare")
private func rustSystemHUDVolumeFlare(_ level: Double, _ energy: Double, _ elapsed: Double, _ output: UnsafeMutablePointer<Double>?) -> Int32
@_silgen_name("rium_notch_system_mute_frame")
private func rustSystemMuteFrame(_ elapsed: Double, _ arm: Double, _ length: Double, _ reduced: Int32, _ output: UnsafeMutablePointer<Double>?) -> Int32
@_silgen_name("rium_notch_system_hud_prism")
private func rustSystemHUDPrism(_ kind: Int32, _ output: UnsafeMutablePointer<Double>?) -> Int32
@_silgen_name("rium_notch_music_ripple_phase")
private func rustMusicRipplePhase(_ time: Double, _ offset: Double, _ output: UnsafeMutablePointer<Double>?) -> Int32
@_silgen_name("rium_notch_playback_transition_envelope")
private func rustPlaybackTransitionEnvelope(_ elapsed: Double) -> Double
@_silgen_name("rium_notch_track_skip_reduced_opacity")
private func rustTrackSkipReducedOpacity(_ kind: Int32, _ elapsed: Double) -> Double
@_silgen_name("rium_music_progress_fraction")
private func rustMusicProgressFraction(_ elapsed: Double, _ duration: Double) -> Double
@_silgen_name("rium_notch_music_crest_positions")
private func rustMusicCrestPositions(_ center: Double, _ output: UnsafeMutablePointer<Double>?) -> Int32
@_silgen_name("rium_notch_system_tip_fade")
private func rustSystemTipFade(_ glowWidth: Double, _ output: UnsafeMutablePointer<Double>?) -> Int32
@_silgen_name("rium_notch_timer_pulse")
private func rustTimerPulse(_ time: Double, _ reduceMotion: Int32) -> Double
@_silgen_name("rium_notch_organic_ray_fog")
private func rustOrganicRayFog(_ arm: Double, _ scale: Double, _ output: UnsafeMutablePointer<Double>?) -> Int32
@_silgen_name("rium_notch_organic_ray")
private func rustOrganicRay(_ index: Int32, _ count: Int32, _ side: Int32, _ arm: Double, _ scale: Double,
                            _ thickness: Double, _ output: UnsafeMutablePointer<Double>?) -> Int32
@_silgen_name("rium_notch_humidity_specks")
private func rustHumiditySpecks(_ width: Double, _ height: Double, _ scale: Double,
                                _ output: UnsafeMutablePointer<Double>?, _ capacity: Int) -> Int32
@_silgen_name("rium_notch_idle_light")
private func rustNotchIdleLight(_ time: Double, _ reduceMotion: Int32, _ output: UnsafeMutablePointer<Double>?) -> Int32
@_silgen_name("rium_dictation_aurora_palette")
private func rustDictationAuroraPalette(_ time: Double, _ cycles: Double, _ whiten: Double, _ reduceMotion: Int32,
                                        _ output: UnsafeMutablePointer<Double>?) -> Int32
@_silgen_name("rium_shelf_hover_progress")
private func rustShelfHoverProgress(_ time: Double, _ reduceMotion: Int32, _ output: UnsafeMutablePointer<Double>?) -> Int32
@_silgen_name("rium_shelf_catch_frame")
private func rustShelfCatchFrame(_ elapsed: Double, _ reduceMotion: Int32, _ output: UnsafeMutablePointer<Double>?) -> Int32
@_silgen_name("rium_notch_receiving_tide")
private func rustReceivingTide(_ elapsed: Double, _ clock: Double, _ progress: Double, _ held: Int32,
                               _ reduceMotion: Int32, _ output: UnsafeMutablePointer<Double>?) -> Int32
@_silgen_name("rium_notch_agent_light")
private func rustNotchAgentLight(_ time: Double, _ reduceMotion: Int32, _ output: UnsafeMutablePointer<Double>?) -> Int32
@_silgen_name("rium_notch_question_light")
private func rustNotchQuestionLight(_ time: Double, _ width: Double, _ reduceMotion: Int32, _ output: UnsafeMutablePointer<Double>?) -> Int32
@_silgen_name("rium_notch_question_palette")
private func rustNotchQuestionPalette(_ time: Double, _ reduceMotion: Int32, _ whiten: Double, _ output: UnsafeMutablePointer<Double>?) -> Int32
@_silgen_name("rium_notch_question_highlight")
private func rustNotchQuestionHighlight(_ arm: Double, _ upperArc: Double, _ side: Double, _ lowerArc: Double, _ length: Double, _ output: UnsafeMutablePointer<Double>?) -> Int32
@_silgen_name("rium_agent_organic_palette")
private func rustAgentOrganicPalette(_ time: Double, _ approval: Int32, _ reduceMotion: Int32,
                                     _ whiten: Double, _ output: UnsafeMutablePointer<Double>?) -> Int32
@_silgen_name("rium_timer_contour_crests")
private func rustTimerContourCrests(_ fraction: Double, _ length: Double, _ output: UnsafeMutablePointer<Double>?) -> Int32
@_silgen_name("rium_notch_copy_impact_frame")
private func rustCopyImpactFrame(_ elapsed: Double, _ reduceMotion: Int32, _ output: UnsafeMutablePointer<Double>?) -> Int32
@_silgen_name("rium_notch_copy_sweep_frame")
private func rustCopySweepFrame(_ elapsed: Double, _ outward: Double, _ backward: Double,
                                _ reduceMotion: Int32, _ output: UnsafeMutablePointer<Double>?) -> Int32
@_silgen_name("rium_notch_paste_sweep_frame")
private func rustPasteSweepFrame(_ elapsed: Double, _ travel: Double, _ reduceMotion: Int32,
                                 _ output: UnsafeMutablePointer<Double>?) -> Int32
@_silgen_name("rium_notch_paste_center_band")
private func rustPasteCenterBand(_ elapsed: Double, _ travel: Double, _ reduceMotion: Int32,
                                 _ output: UnsafeMutablePointer<Double>?) -> Int32

let defaultMusicLightColor = NSColor(calibratedRed: 0.55, green: 0.73, blue: 1, alpha: 1)
private let copySweepOut: TimeInterval = 0.34
private let copySweepBack: TimeInterval = 0.34
private let copySweepTrailDelay: TimeInterval = 0.065

func copySweepTrailCenter(elapsed: TimeInterval, reduceMotion: Bool) -> CGFloat? {
    guard elapsed.isFinite, elapsed >= 0 else { return nil }
    var frame = [Double](repeating: 0, count: 2)
    let status = frame.withUnsafeMutableBufferPointer {
        rustCopySweepFrame(max(0, elapsed - copySweepTrailDelay), copySweepOut, copySweepBack,
                           reduceMotion ? 1 : 0, $0.baseAddress)
    }
    return status == 0 ? CGFloat(frame[0]) : nil
}
private let pasteSweepTravel: TimeInterval = 0.42

// Read only a small, evenly spaced sample when the artwork changes. No image
// content or extracted color is written to disk.
func artworkLightColor(_ data: Data) -> NSColor? {
    guard let bitmap = NSBitmapImageRep(data: data) else { return nil }
    return artworkLightColor(bitmap)
}
func artworkLightColor(_ bitmap: NSBitmapImageRep) -> NSColor? {
    guard bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0 else { return nil }
    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, total: CGFloat = 0
    for y in 0..<10 {
        for x in 0..<10 {
            let px = min(bitmap.pixelsWide - 1, (2 * x + 1) * bitmap.pixelsWide / 20)
            let py = min(bitmap.pixelsHigh - 1, (2 * y + 1) * bitmap.pixelsHigh / 20)
            guard let color = bitmap.colorAt(x: px, y: py)?.usingColorSpace(.sRGB), color.alphaComponent > 0.2 else { continue }
            let r = color.redComponent, g = color.greenComponent, b = color.blueComponent
            let brightness = max(r, g, b), saturation = brightness > 0 ? (brightness - min(r, g, b)) / brightness : 0
            let weight = color.alphaComponent * max(0.08, brightness) * (0.35 + saturation)
            red += r * weight; green += g * weight; blue += b * weight; total += weight
        }
    }
    guard total > 0 else { return nil }
    let r = red / total, g = green / total, b = blue / total
    let maxComponent = max(r, g, b)
    guard maxComponent > 0.03 else { return nil }
    let lift = min(1.6, 0.9 / maxComponent)
    return NSColor(srgbRed: min(1, r * lift), green: min(1, g * lift), blue: min(1, b * lift), alpha: 1)
}

enum AmbientLightMode: Equatable { case off, idle, agent, music }
enum AgentAmbientVariant: Hashable { case working, acting, approval, question }
func agentAmbientVariant(waiting: Bool, question: Bool, acting: Bool) -> AgentAmbientVariant {
    if waiting { return question ? .question : .approval }
    return acting ? .acting : .working
}
private func agentLightIsActive(_ agent: AgentActivity) -> Bool {
    agentIsRunning(agent.state) || agentNeedsAttention(agent.state)
}
func agentLightIsActive(_ agents: [AgentActivity]) -> Bool {
    agents.contains(where: agentLightIsActive)
}
func combinedAgentLightState(_ agents: [AgentActivity], assistant: AssistantIndicator, assistantToolRunning: Bool = false, assistantSpeaking: Bool = false) -> (active: Bool, waiting: Bool, question: Bool, acting: Bool) {
    let active = agentLightIsActive(agents) || assistant != .off || assistantSpeaking
    let approval = assistant == .approval || agents.contains { $0.state.hasPrefix("승인 대기") }
    let question = !approval && (assistant == .question || agents.contains { $0.state.hasPrefix("질문 대기") || $0.state.hasPrefix("입력 대기") })
    let waiting = approval || question
    let acting = active && !waiting && ((assistant == .working && assistantToolRunning) || agents.contains {
        agentLightIsActive($0) && ($0.toolRunning || ["도구 실행 감지", "도구 실행 중"].contains($0.state))
    })
    return (active, waiting, question, acting)
}
func ambientLightMode(expanded: Bool, agentActive: Bool, musicPlaying: Bool, eventActive: Bool = false) -> AmbientLightMode {
    // Transient cues are rendered above the persistent state light; keeping
    // it alive prevents a visible blackout between closely spaced actions.
    _ = eventActive
    if agentActive { return .agent }
    if expanded { return .idle }
    return musicPlaying ? .music : .idle
}
func musicRipplePhase(time: TimeInterval, offset: Double) -> Double {
    var result = 0.0
    return rustMusicRipplePhase(time, offset, &result) == 0 ? result : 0
}

private func musicRippleIntensity(at time: TimeInterval, spectrum: SpectrumIntensityTransition?) -> Double {
    // shortcut: the original mapping from spectrum to light is unknown.
    spectrum.map { 0.25 + 0.75 * $0.value(at: time) }
        ?? (abs(sin(time * 2 * .pi / 1.35)) * 0.35 + 0.65)
}

// The original MusicWaveGlow crest clamps its peak and uses a 0.13-wide
// fade on either side. Keep the gradient stops ordered at the screen edges.
func musicCrestPositions(_ center: Double) -> (left: Double, peak: Double, right: Double) {
    var stops = [Double](repeating: 0, count: 3)
    let status = stops.withUnsafeMutableBufferPointer { rustMusicCrestPositions(center, $0.baseAddress) }
    guard status == 0 else { return (0, 0.01, 0.14) }
    return (stops[0], stops[1], stops[2])
}
// MusicWaveGlow lightens each RGB component toward white by 28% at its crest.
func musicCrestColor(_ tint: NSColor, lift amount: CGFloat = 0.28) -> NSColor {
    guard let color = tint.usingColorSpace(.sRGB) else { return tint }
    func lift(_ component: CGFloat) -> CGFloat { component + (1 - component) * amount }
    return NSColor(srgbRed: lift(color.redComponent), green: lift(color.greenComponent), blue: lift(color.blueComponent), alpha: color.alphaComponent)
}
func musicPrismHighlight(_ tint: NSColor) -> NSColor {
    let color = tint.usingColorSpace(.sRGB) ?? .white
    return NSColor(srgbRed: color.redComponent * 0.6, green: color.greenComponent * 0.6,
                   blue: color.blueComponent * 0.6, alpha: 1)
}
func notificationGlowColor(_ tint: NSColor?) -> NSColor {
    guard let tint = tint else { return NSColor(srgbRed: 0.82, green: 0.86, blue: 0.96, alpha: 1) }
    return musicCrestColor(tint, lift: 0.3).withAlphaComponent(1)
}
// AmbientContour includes the shoulder, outset, and width-dependent fade.
func ambientGlowWidth(notch: CGFloat, arm: CGFloat, topCorner: CGFloat, outset: CGFloat) -> CGFloat {
    guard notch.isFinite, arm.isFinite, topCorner.isFinite, outset.isFinite,
          notch >= 0, arm >= 0, topCorner >= 0, outset >= 0 else { return 0 }
    let ratio = arm / 220
    let fade: CGFloat = ratio < 0.65 ? 46.8 : (ratio < 1.45 ? max(22, ratio * 72) : 104.4)
    return notch + 2 * (arm + max(5, topCorner - 2) + outset + fade)
}
func musicGlowWidth(notch: CGFloat, arm: CGFloat, screen: CGFloat) -> CGFloat {
    guard screen.isFinite, screen > 0 else { return 0 }
    return ambientGlowWidth(notch: notch, arm: arm, topCorner: 7, outset: 1)
}
func musicContourFadeFraction(_ width: CGFloat) -> CGFloat {
    var value = 0.0
    return rustSystemTipFade(Double(width), &value) == 0 ? CGFloat(value) : 0.25
}
// Interpolate after fitting the endpoints to the display so the steps remain even.
private func interpolatedLightReach(_ preset: String, narrow: CGFloat, widest: CGFloat) -> CGFloat {
    switch preset {
    case "narrow": return narrow
    case "medium": return narrow + (widest - narrow) / 3
    case "extraLarge": return widest
    default: return narrow + 2 * (widest - narrow) / 3
    }
}

func ambientArmRun(preset: String, screenWidth: CGFloat, notch: CGFloat? = nil) -> CGFloat {
    guard screenWidth.isFinite, screenWidth > 0 else { return 0 }
    let room = max(0, (screenWidth - (notch ?? notchWidth(expanded: false, displayWidth: screenWidth))) / 2)
    return interpolatedLightReach(preset, narrow: min(76, room), widest: min(680, room))
}

func musicArmRun(preset: String, screenWidth: CGFloat, notch: CGFloat) -> CGFloat {
    guard screenWidth.isFinite, screenWidth > 0, notch.isFinite, notch >= 0 else { return 0 }
    return interpolatedLightReach(preset, narrow: 76, widest: 440)
}

func agentLightArmRun(preset: String, screenWidth: CGFloat, notch: CGFloat, collapsed: CGFloat,
                      expanded: CGFloat, reachesScreenEdge: Bool = false) -> CGFloat {
    guard [screenWidth, notch, collapsed, expanded].allSatisfy(\.isFinite), screenWidth > 0 else { return 0 }
    let room = max(0, (screenWidth - notch) / 2)
    let narrow = min(76, room)
    if reachesScreenEdge {
        return interpolatedLightReach(preset, narrow: narrow, widest: room)
    }
    let compact = min(680, room)
    let progress = expanded > collapsed ? min(1, max(0, (notch - collapsed) / (expanded - collapsed))) : 0
    let widest = compact + (max(0, room - 20) - compact) * progress
    return interpolatedLightReach(preset, narrow: narrow, widest: max(narrow, widest))
}

// Transient effects expire independently of the persistent idle illumination.
enum ShortcutAction: Int32, Equatable {
    case cut, undo, save, refresh, print, selectAll, quit, paste, screenshotFull, screenshotArea
    static let configurable: [ShortcutAction] = [.cut, .undo, .save, .refresh, .print, .selectAll, .quit, .screenshotFull, .screenshotArea]
    var preferenceKey: String? {
        switch self {
        case .cut: return "rium.shortcuts.cut"
        case .undo: return "rium.shortcuts.undo"
        case .save: return "rium.shortcuts.save"
        case .refresh: return "rium.shortcuts.refresh"
        case .print: return "rium.shortcuts.print"
        case .selectAll: return "rium.shortcuts.selectAll"
        case .quit: return "rium.shortcuts.quit"
        case .screenshotFull: return "rium.shortcuts.screenshotFull"
        case .screenshotArea: return "rium.shortcuts.screenshotArea"
        case .paste: return nil
        }
    }
    var title: String {
        switch self { case .cut: return "잘라내기"; case .undo: return "실행 취소"; case .save: return "저장"; case .refresh: return "새로고침"; case .print: return "인쇄"; case .selectAll: return "전체 선택"; case .quit: return "종료"; case .paste: return "붙여넣기"; case .screenshotFull: return "전체 화면 캡처"; case .screenshotArea: return "영역 캡처" }
    }
    var keyLabel: String {
        switch self {
        case .cut: return "Command + X"
        case .undo: return "Command + Z"
        case .save: return "Command + S"
        case .refresh: return "Command + R"
        case .print: return "Command + P"
        case .selectAll: return "Command + A"
        case .quit: return "Command + Q"
        case .paste: return "Command + V"
        case .screenshotFull: return "Command + Shift + 3"
        case .screenshotArea: return "Command + Shift + 4"
        }
    }
    var symbol: String {
        switch self { case .cut: return "scissors"; case .undo: return "arrow.uturn.backward"; case .save: return "checkmark"; case .refresh: return "arrow.clockwise"; case .print: return "printer"; case .selectAll: return "checkmark.square"; case .quit: return "power"; case .paste: return "doc.on.clipboard"; case .screenshotFull: return "camera"; case .screenshotArea: return "viewfinder" }
    }
}

func shortcutActionEnabled(_ action: ShortcutAction, defaults: UserDefaults = .standard) -> Bool {
    guard let key = action.preferenceKey else { return true }
    return defaults.object(forKey: key) as? Bool ?? true
}

func shortcutLightEnabled(_ action: ShortcutAction, shortcuts: Bool, clipboard: Bool, defaults: UserDefaults = .standard) -> Bool {
    shortcuts && shortcutActionEnabled(action, defaults: defaults) && (action != .paste || clipboard)
}

private func shortcutPrismColors(_ action: ShortcutAction) -> (base: Color, highlight: Color) {
    var rgb = [Double](repeating: 1, count: 6)
    let status = rgb.withUnsafeMutableBufferPointer { rustNotchShortcutPrism(action.rawValue, $0.baseAddress) }
    guard status == 0 else { return (.white, .white) }
    return (Color(red: rgb[0], green: rgb[1], blue: rgb[2]),
            Color(red: rgb[3], green: rgb[4], blue: rgb[5]))
}

private func caseKeyPrismColors(_ action: CaseKeyAction) -> (base: Color, highlight: Color) {
    var rgb = [Double](repeating: 1, count: 6)
    let status = rgb.withUnsafeMutableBufferPointer { rustCaseKeyPrism(action.rawValue, $0.baseAddress) }
    guard status == 0 else { return (.white, .white) }
    return (Color(red: rgb[0], green: rgb[1], blue: rgb[2]),
            Color(red: rgb[3], green: rgb[4], blue: rgb[5]))
}

private func systemHUDPrismColors(_ kind: NotchLightCue.Kind) -> (base: Color, highlight: Color) {
    let palette: Int32
    switch kind {
    case .brightness: palette = 1
    case .mute(true): palette = 2
    default: palette = 0
    }
    var rgb = [Double](repeating: 1, count: 6)
    guard rgb.withUnsafeMutableBufferPointer({ rustSystemHUDPrism(palette, $0.baseAddress) }) == 0 else { return (.white, .white) }
    return (Color(red: rgb[0], green: rgb[1], blue: rgb[2]), Color(red: rgb[3], green: rgb[4], blue: rgb[5]))
}

func shortcutActionForKey(keyCode: UInt16, characters: String?, flags: NSEvent.ModifierFlags) -> ShortcutAction? {
    let modifiers = flags.intersection([.command, .control, .option, .shift, .function])
    if modifiers == [.command, .shift] || modifiers == [.command, .shift, .control] {
        if keyCode == 20 { return .screenshotFull }
        if keyCode == 21 { return .screenshotArea }
    }
    guard modifiers == .command else { return nil }
    let key = characters?.lowercased() ?? ""
    switch key {
    case "x": return .cut
    case "z": return .undo
    case "s": return .save
    case "r": return .refresh
    case "p": return .print
    case "a": return .selectAll
    case "q": return .quit
    case "v": return .paste
    default: break
    }
    // Some input methods omit the character or report Hangul for shortcuts.
    // Preserve character-based shortcuts for other keyboard layouts.
    let isHangul = !key.isEmpty && key.unicodeScalars.allSatisfy { scalar in
        switch scalar.value {
        case 0x1100...0x11FF, 0x3130...0x318F, 0xA960...0xA97F,
             0xAC00...0xD7AF, 0xD7B0...0xD7FF: return true
        default: return false
        }
    }
    guard key.isEmpty || isHangul else { return nil }
    switch keyCode {
    case 7: return .cut
    case 6: return .undo
    case 1: return .save
    case 15: return .refresh
    case 35: return .print
    case 0: return .selectAll
    case 12: return .quit
    case 9: return .paste
    default: return nil
    }
}

enum CaseKeyAction: Int32, Equatable {
    case capsOn, capsOff, shiftHeld
    var title: String { switch self { case .capsOn: return "Caps Lock 켜짐"; case .capsOff: return "Caps Lock 꺼짐"; case .shiftHeld: return "Shift 키" } }
    var symbol: String { self == .shiftHeld ? "shift" : (self == .capsOn ? "capslock.fill" : "capslock") }
}

private extension FocusPhase {
    var lightColor: Color {
        switch self {
        case .focus: return Color(red: 1, green: 0.74, blue: 0.38)
        case .shortBreak: return Color(red: 0.46, green: 0.93, blue: 0.7)
        case .longBreak: return Color(red: 0.44, green: 0.84, blue: 0.96)
        }
    }
}

private let notificationFlashDuration: TimeInterval = 0.78
private let notificationLingerDuration: TimeInterval = 1.4

func lightCueEnabled(_ kind: NotchLightCue.Kind, defaults: UserDefaults = .standard) -> Bool {
    func enabled(_ key: String, default value: Bool = true) -> Bool {
        defaults.object(forKey: key) as? Bool ?? value
    }
    switch kind {
    case .clipboard, .clipboardPaste: return enabled("rium.light.clipboard")
    case .airDrop, .airDropSent: return enabled("rium.light.airdrop")
    case .screenshot: return enabled("rium.light.screenshot")
    case .shelf: return enabled("rium.light.shelf")
    case .systemNotification, .systemControl, .systemLevel, .brightness, .mute: return enabled("rium.light.system")
    case .batterySource, .batteryWarning: return enabled("rium.light.battery")
    case .timerActivation, .timerTransition: return enabled("rium.light.timer")
    case .musicPlayback, .musicTrack, .musicSkip, .musicSkipHunt, .musicSkipArrival: return enabled("rium.light.music")
    case .calendarAdded: return enabled("rium.light.calendarAdded")
    case .reminderAdded: return enabled("rium.light.reminderAdded")
    case .shortcut(let action):
        return shortcutLightEnabled(action, shortcuts: enabled("rium.shortcuts.peeks"), clipboard: enabled("rium.light.clipboard"), defaults: defaults)
    case .caseKey: return enabled("rium.light.caseKeys", default: false)
    case .agentRunning, .agentApproval, .agentQuestion, .agentDone, .agentMessage, .agentFailed, .agentInterrupted: return enabled("rium.light.agent")
    }
}

// shortcut: reference groups several cues before adaptation; compare overlaps after rendering.
func contourSurfaceAdapts(_ kind: NotchLightCue.Kind) -> Bool {
    switch kind {
    case .clipboard, .clipboardPaste, .systemLevel, .brightness, .screenshot, .shelf,
         .shortcut, .caseKey, .calendarAdded, .reminderAdded: return true
    default: return false
    }
}

func lightCueEvictionIndex(_ cues: [NotchLightCue], isEnabled: (NotchLightCue.Kind) -> Bool) -> Int? {
    let removable: (NotchLightCue) -> Bool = { !($0.kind == .caseKey(.shiftHeld) && $0.duration.isInfinite) }
    if let hidden = cues.firstIndex(where: { removable($0) && !isEnabled($0.kind) }) { return hidden }
    return cues.firstIndex(where: removable)
}

struct NotchLightCue: Identifiable {
    enum Kind: Equatable { case airDrop, airDropSent, clipboard, clipboardPaste, screenshot, shelf, systemNotification, systemControl, systemLevel(Int), brightness(Int), mute(Bool), calendarAdded, reminderAdded, batterySource(Int, Bool), batteryWarning(Bool), timerActivation(FocusPhase), timerTransition(FocusPhase), musicPlayback(Bool), musicTrack, musicSkip(Bool), musicSkipHunt(Bool), musicSkipArrival, agentRunning, agentApproval, agentQuestion, agentDone, agentMessage, agentFailed, agentInterrupted, shortcut(ShortcutAction), caseKey(CaseKeyAction) }
    let id = UUID()
    let kind: Kind
    let notificationTint: NSColor?
    let previousSystemLevel: Double?
    let systemPulseEnergy: Double
    let systemDirection: Double
    let restoringSound: Bool
    private let startedUptime: TimeInterval
    private var releasedUptime: TimeInterval?

    // Translate an optional backdated cue once, then keep its animation on the
    // same monotonic clock as the full-screen waves and its dispatch deadline.
    init(kind: Kind, started: Date, referenceDate: Date = Date(),
         referenceUptime: TimeInterval = ProcessInfo.processInfo.systemUptime, notificationTint: NSColor? = nil,
         previousSystemLevel: Double? = nil, systemPulseEnergy: Double = 0.48, systemDirection: Double = 1, restoringSound: Bool = false) {
        self.kind = kind
        self.notificationTint = notificationTint
        self.previousSystemLevel = previousSystemLevel
        self.systemPulseEnergy = systemPulseEnergy
        self.systemDirection = systemDirection
        self.restoringSound = restoringSound
        self.startedUptime = referenceUptime - referenceDate.timeIntervalSince(started)
        self.releasedUptime = nil
    }

    func elapsed(at uptime: TimeInterval) -> TimeInterval {
        max(0, uptime - startedUptime)
    }
    func releasingShift(at uptime: TimeInterval) -> NotchLightCue {
        var copy = self
        copy.releasedUptime = uptime
        return copy
    }
    func shiftReleaseFade(at uptime: TimeInterval) -> Double {
        // shortcut: confirm the original release duration with the held-state geometry.
        guard let releasedUptime else { return 1 }
        return max(0, 1 - max(0, uptime - releasedUptime) / 0.2)
    }
    var isSystemHUD: Bool {
        switch kind { case .systemControl, .systemLevel, .brightness, .mute: return true; default: return false }
    }
    var isBatteryFeedback: Bool {
        switch kind { case .batterySource, .batteryWarning: return true; default: return false }
    }
    var duration: TimeInterval {
        switch kind {
        case .systemNotification: return notificationFlashDuration + notificationLingerDuration
        case .agentRunning, .agentApproval, .agentQuestion: return 0.82
        case .agentMessage: return 0.85
        case .musicSkip: return trackSkipPassDuration
        case .musicSkipHunt: return trackSkipWaitDuration - trackSkipPassDuration
        case .musicSkipArrival: return 0.58
        case .musicPlayback: return 0.85
        case .agentDone, .agentFailed, .agentInterrupted: return 0.72
        case .systemControl, .systemLevel, .brightness, .mute: return systemHUDSeconds()
        case .screenshot: return 1.35
        case .clipboard: return max(copySweepOut + copySweepBack, 0.55) + 0.05
        case .clipboardPaste, .shortcut(.paste): return max(pasteSweepTravel, 0.55) + 0.05
        case .shortcut(let action): return rustNotchShortcutLightDuration(action.rawValue)
        case .caseKey(let action):
            switch action {
            case .capsOn: return 0.78
            case .capsOff: return 0.34
            case .shiftHeld: return releasedUptime.map { max(0, $0 - startedUptime) + 0.2 } ?? .infinity
            }
        case .batterySource: return batteryFeedbackDuration(critical: nil)
        case .batteryWarning(let critical): return batteryFeedbackDuration(critical: critical)
        default: return 2.0
        }
    }
}

func systemLevelTransitionStart(previous: Int?, next: NotchLightCue.Kind, active: NotchLightCue?, now: TimeInterval) -> Double? {
    guard let previous else { return nil }
    let fallback = Double(previous)
    guard now.isFinite, let active else { return fallback }
    let target: Int
    switch (active.kind, next) {
    case let (.systemLevel(old), .systemLevel(_)), let (.brightness(old), .brightness(_)): target = old
    default: return fallback
    }
    guard target == previous else { return fallback }
    let current = rustSystemHUDLevel((active.previousSystemLevel ?? Double(target)) / 100,
                                     Double(target) / 100, active.elapsed(at: now))
    return current.isFinite ? current * 100 : fallback
}

func systemLevelDirection(previous: Int?, next: NotchLightCue.Kind) -> Double {
    let target: Int
    switch next {
    case .systemLevel(let value), .brightness(let value): target = value
    default: return 1
    }
    return previous.map { target >= $0 ? 1 : -1 } ?? 1
}

func systemLevelPulseEnergy(next: NotchLightCue.Kind, active: NotchLightCue?, now: TimeInterval) -> Double {
    guard now.isFinite, let active else { return 0.48 }
    switch (active.kind, next) {
    case (.systemLevel, .systemLevel), (.brightness, .brightness):
        let value = rustSystemHUDPulseEnergy(active.systemPulseEnergy, active.elapsed(at: now))
        return value.isFinite ? value : 0.48
    default: return 0.48
    }
}

func notchEventEnvelope(_ cue: NotchLightCue, at uptime: TimeInterval) -> Double {
    guard uptime.isFinite else { return 0 }
    let elapsed = cue.elapsed(at: uptime)
    let entry = min(1, elapsed / 0.22)
    if cue.kind == .caseKey(.shiftHeld) { return min(entry, cue.shiftReleaseFade(at: uptime)) }
    return max(0, min(entry, (cue.duration - elapsed) / 0.45))
}

struct AgentArrivalSegment {
    let start: CGFloat
    let end: CGFloat
    let opacity: Double
    let highlight: Bool
}

func ambientCrestLayers(line: CGFloat, blur: CGFloat) -> [(spread: CGFloat, line: CGFloat, blur: CGFloat, opacity: Double)] {
    [(1, 3.4 * line, blur + 11, 0.20), (0.78, 1.9 * line, blur + 5, 0.34),
     (0.52, line, blur, 0.62), (0.26, 0.42 * line, 0.3 * blur, 1)]
}

func prismCrestLayers(line: CGFloat, blur: CGFloat, thickness: CGFloat) -> [(spread: CGFloat, line: CGFloat, blur: CGFloat, opacity: Double)] {
    [(1, 3.5 * line, blur + 10, 0.38), (0.7, 1.7 * line, blur + 3, 0.72),
     (0.38, 0.65 * line, 1, 1), (0.17, 1.2 * thickness, 0.5, 0.92)]
}

private func drawAmbientGauge(context: inout GraphicsContext, path: Path, color: Color, opacity: Double, thickness: CGFloat) {
    var halo = context; halo.addFilter(.blur(radius: 15))
    halo.stroke(path, with: .color(color.opacity(opacity * 0.26)),
                style: StrokeStyle(lineWidth: 20 * thickness, lineCap: .round, lineJoin: .round))
    var glow = context; glow.addFilter(.blur(radius: 6))
    glow.stroke(path, with: .color(color.opacity(opacity * 0.44)),
                style: StrokeStyle(lineWidth: 8 * thickness, lineCap: .round, lineJoin: .round))
    var core = context; core.addFilter(.blur(radius: 1.2))
    core.addFilter(.shadow(color: color.opacity(opacity * 0.5), radius: 5))
    core.addFilter(.shadow(color: color.opacity(opacity * 0.28), radius: 12))
    core.stroke(path, with: .color(color.opacity(opacity)),
                style: StrokeStyle(lineWidth: 2.4 * thickness, lineCap: .round, lineJoin: .round))
}

private func drawNotificationArrival(context: inout GraphicsContext, path: Path, elapsed: TimeInterval,
                                     duration: TimeInterval, thickness: CGFloat, reduceMotion: Bool, tint: NSColor?,
                                     fadeArms: Bool) {
    let pulse = rustNotificationArrivalEnvelope(elapsed, notificationFlashDuration, reduceMotion ? 1 : 0)
    let gauge = rustNotificationArrivalGauge(elapsed, duration)
    let opacity = max(pulse, gauge)
    guard opacity > 0 else { return }
    // shortcut: GraphicsContext shadow compositing and contour geometry need reference-frame comparison.
    let color = Color(nsColor: notificationGlowColor(tint))
    context.drawLayer { layer in
        var haze = layer; haze.addFilter(.blur(radius: 10))
        haze.stroke(path, with: .color(color.opacity(opacity * 0.2)),
                    style: StrokeStyle(lineWidth: 1.8 * thickness, lineCap: .round, lineJoin: .round))
        drawAmbientGauge(context: &layer, path: path, color: color, opacity: opacity, thickness: thickness)
        let bounds = path.boundingRect
        if fadeArms, bounds.width >= 1 {
            // shortcut: the reference uses a 20-point fade on its glow frame; our contour bounds need comparison.
            let fade = min(20 / bounds.width, 0.25)
            layer.blendMode = .destinationIn
            layer.fill(Path(bounds.insetBy(dx: -40, dy: -40)), with: .linearGradient(
                Gradient(stops: [.init(color: .clear, location: 0), .init(color: .white, location: fade),
                                 .init(color: .white, location: 1 - fade), .init(color: .clear, location: 1)]),
                startPoint: CGPoint(x: bounds.minX, y: bounds.midY),
                endPoint: CGPoint(x: bounds.maxX, y: bounds.midY)))
        }
    }
}

private func drawAmbientCrest(context: inout GraphicsContext, path: Path, center: CGFloat, spread: CGFloat,
                              color: Color, line: CGFloat, blur: CGFloat, opacity: Double, reach: CGFloat = 1) {
    for (index, layer) in ambientCrestLayers(line: line, blur: blur).enumerated() {
        let start = max(0, center - spread * layer.spread), end = min(1, center + spread * layer.spread)
        guard end > start else { continue }
        var pass = context
        if layer.blur > 0 { pass.addFilter(.blur(radius: layer.blur * reach)) }
        if index == 3 {
            // shortcut: GraphicsContext and SwiftUI shadow compositing need screen comparison.
            pass.addFilter(.shadow(color: color.opacity(opacity * 0.55), radius: 5 * reach))
            pass.addFilter(.shadow(color: color.opacity(opacity * 0.30), radius: 13 * reach))
        }
        pass.stroke(path.trimmedPath(from: start, to: end), with: .color(color.opacity(opacity * layer.opacity)),
                    style: StrokeStyle(lineWidth: layer.line, lineCap: .round, lineJoin: .round))
    }
}

func copyImpactFadeFrame(pathBounds: CGRect, glowWidth: CGFloat) -> CGRect? {
    guard pathBounds.midX.isFinite, pathBounds.minY.isFinite, pathBounds.maxY.isFinite,
          glowWidth.isFinite, glowWidth >= 1 else { return nil }
    return CGRect(x: pathBounds.midX - glowWidth / 2, y: pathBounds.minY - 100,
                  width: glowWidth, height: pathBounds.height + 200)
}

private func drawCopyImpact(context: inout GraphicsContext, path: Path, elapsed: TimeInterval,
                            reduceMotion: Bool, tint: Color, thickness: CGFloat, glowWidth: CGFloat? = nil) {
    let length = approximateContourLength(path)
    guard length > 0 else { return }
    var frame = [Double](repeating: 0, count: 7)
    guard frame.withUnsafeMutableBufferPointer({ rustCopyImpactFrame(elapsed, reduceMotion ? 1 : 0, $0.baseAddress) }) == 0 else { return }
    // shortcut: GraphicsContext and SwiftUI shadow blending need frame comparison.
    context.drawLayer { layer in
        var diffuse = layer
        diffuse.addFilter(.blur(radius: CGFloat(frame[1])))
        diffuse.stroke(path, with: .color(tint.opacity(frame[2])),
                       style: StrokeStyle(lineWidth: CGFloat(frame[0]) * thickness, lineCap: .round, lineJoin: .round))
        if let glowWidth, let fadeFrame = copyImpactFadeFrame(pathBounds: path.boundingRect, glowWidth: glowWidth) {
            let fraction = musicContourFadeFraction(glowWidth)
            let gradient = Gradient(stops: [.init(color: .clear, location: 0), .init(color: .white, location: fraction),
                                            .init(color: .white, location: 1 - fraction), .init(color: .clear, location: 1)])
            layer.blendMode = .destinationIn
            layer.fill(Path(fadeFrame), with: .linearGradient(gradient,
                       startPoint: CGPoint(x: fadeFrame.minX, y: 0), endPoint: CGPoint(x: fadeFrame.maxX, y: 0)))
        }
    }
    drawAmbientCrest(context: &context, path: path, center: 0.5, spread: 70 / length,
                     color: .white, line: 9 * thickness, blur: 2.5, opacity: frame[3])
    drawAmbientCrest(context: &context, path: path, center: 0.5, spread: 140 / length,
                     color: tint, line: 12 * thickness, blur: 6, opacity: frame[4])
    for center in [0.5 - frame[5], 0.5 + frame[5]] {
        drawAmbientCrest(context: &context, path: path, center: CGFloat(center), spread: 22 / length,
                         color: .white, line: 5 * thickness, blur: 1.5, opacity: frame[6])
    }
}

private func drawPrismCrest(context: inout GraphicsContext, path: Path, center: CGFloat, spread: CGFloat,
                            base: Color, highlight: Color, line: CGFloat, blur: CGFloat, opacity: Double, thickness: CGFloat) {
    // shortcut: color ordering and SwiftUI mask compositing need screen comparison.
    let colors: [Color] = [highlight, base, base, .white]
    for (index, layer) in prismCrestLayers(line: line, blur: blur, thickness: thickness).enumerated() {
        let start = max(0, center - spread * layer.spread), end = min(1, center + spread * layer.spread)
        guard end > start else { continue }
        var pass = context; pass.addFilter(.blur(radius: layer.blur))
        pass.stroke(path.trimmedPath(from: start, to: end), with: .color(colors[index].opacity(min(1, opacity * layer.opacity))),
                    style: StrokeStyle(lineWidth: layer.line, lineCap: .round, lineJoin: .round))
    }
}

func musicProgressCrestSpread(progress: CGFloat, pathLength: CGFloat) -> CGFloat? {
    guard progress.isFinite, progress > 0.005, progress < 0.995,
          pathLength.isFinite, pathLength > 0 else { return nil }
    return 17 / pathLength
}

private func drawMusicProgress(context: inout GraphicsContext, path: Path, progress: CGFloat, tint: NSColor, thickness: CGFloat) {
    guard progress.isFinite, progress >= 0 else { return }
    let end = min(progress, 1)
    let color = Color(nsColor: musicCrestColor(tint, lift: 0.14))
    // shortcut: contour direction follows elapsed time by request; shadow compositing needs frame comparison.
    var trace = context; trace.addFilter(.blur(radius: 0.9))
    trace.stroke(path, with: .color(color.opacity(0.1)),
                 style: StrokeStyle(lineWidth: 1.6 * thickness, lineCap: .round, lineJoin: .round))
    guard end > 0 else { return }
    let section = path.trimmedPath(from: 0, to: end)
    var halo = context; halo.addFilter(.blur(radius: 15))
    halo.stroke(section, with: .color(color.opacity(0.34 * 0.26)),
                style: StrokeStyle(lineWidth: 20 * thickness, lineCap: .round, lineJoin: .round))
    var glow = context; glow.addFilter(.blur(radius: 6))
    glow.stroke(section, with: .color(color.opacity(0.34 * 0.44)),
                style: StrokeStyle(lineWidth: 8 * thickness, lineCap: .round, lineJoin: .round))
    var core = context; core.addFilter(.blur(radius: 1.2))
    core.addFilter(.shadow(color: color.opacity(0.34 * 0.5), radius: 5))
    core.addFilter(.shadow(color: color.opacity(0.34 * 0.28), radius: 12))
    core.stroke(section, with: .color(color.opacity(0.34)),
                style: StrokeStyle(lineWidth: 2.4 * thickness, lineCap: .round, lineJoin: .round))
    if let spread = musicProgressCrestSpread(progress: end, pathLength: approximateContourLength(path)) {
        drawAmbientCrest(context: &context, path: path, center: end, spread: spread,
                         color: color, line: 4 * thickness, blur: 2.5, opacity: 0.17)
    }
}

private func drawScreenshotFileGlow(context: inout GraphicsContext, path: Path, length: CGFloat, arm: CGFloat,
                                    thickness: CGFloat, elapsed: TimeInterval, reduceMotion: Bool) {
    var frame = [Double](repeating: 0, count: 6)
    let result = frame.withUnsafeMutableBufferPointer {
        rustScreenshotFileGlow(elapsed, Double(arm), Double(length), reduceMotion ? 1 : 0, $0.baseAddress)
    }
    guard result == 0 else { return }
    let tint = Color(red: 0.82, green: 0.74, blue: 1)
    let start = CGFloat(frame[0]), end = CGFloat(frame[1])
    if end > start, frame[2] > 0 {
        let section = path.trimmedPath(from: start, to: end)
        var haze = context; haze.addFilter(.blur(radius: 6))
        haze.stroke(section, with: .color(tint.opacity(frame[2] * 0.55)), style: StrokeStyle(lineWidth: 8 * thickness, lineCap: .round))
        context.stroke(section, with: .color(tint.opacity(frame[2])), style: StrokeStyle(lineWidth: 3 * thickness, lineCap: .round))
    }
    if frame[3] > 0 {
        for position in [frame[0], frame[1]] {
            drawAmbientCrest(context: &context, path: path, center: CGFloat(position), spread: CGFloat(frame[4]),
                             color: tint, line: 8 * thickness, blur: 4, opacity: frame[3])
        }
    }
    if frame[5] > 0 {
        drawAmbientCrest(context: &context, path: path, center: 0.5, spread: 46 / length,
                         color: tint, line: 12 * thickness, blur: 7, opacity: frame[5])
    }
}

func eventArmRun(kind: NotchLightCue.Kind, preset: String, screenWidth: CGFloat,
                 notchWidth: CGFloat, fallback: CGFloat) -> CGFloat {
    // shortcut: mapping Rium's individual AI event labels onto the reference
    // AgentStatusArrivalGlow still needs live state-by-state comparison.
    switch kind {
    case .systemLevel, .brightness:
        // The reference uses extraLarge at 1.1 scale for the normal-notch HUD.
        // shortcut: screen-edge clamping still needs comparison with the reference.
        guard screenWidth.isFinite, notchWidth.isFinite, screenWidth > 0, notchWidth >= 0 else { return 0 }
        return min(748, max(0, (screenWidth - notchWidth) / 2))
    case .mute, .shortcut, .clipboard, .clipboardPaste:
        guard screenWidth.isFinite, notchWidth.isFinite, screenWidth > 0, notchWidth >= 0 else { return 0 }
        return ambientArmRun(preset: preset, screenWidth: screenWidth, notch: notchWidth)
    case .agentRunning, .agentApproval, .agentQuestion, .agentDone, .agentMessage, .agentFailed, .agentInterrupted:
        let setting: Int32
        switch preset { case "narrow": setting = 0; case "medium": setting = 1; case "extraLarge": setting = 3; default: setting = 2 }
        let value = rustAgentArrivalArmRun(setting, Double(screenWidth), Double(notchWidth))
        return value.isFinite ? CGFloat(value) : fallback
    default:
        return fallback
    }
}

// Rust owns the event timeline and returns contour fractions to this native renderer.
private func arrivalSegments(kind: Int32, elapsed: TimeInterval, pathLength: CGFloat = 0,
                             arm: CGFloat = 0, notchWidth: CGFloat = 0, height: CGFloat = 0,
                             shoulderArcLength: CGFloat? = nil) -> [AgentArrivalSegment] {
    readArrivalSegments { output in
        rustNotchArrivalSegments(kind, elapsed, Double(pathLength), Double(arm), Double(notchWidth), Double(height),
                                 Double(shoulderArcLength ?? -1), output, 8)
    }
}

private func readArrivalSegments(_ read: (UnsafeMutablePointer<Double>?) -> Int32) -> [AgentArrivalSegment] {
    var values = [Double](repeating: 0, count: 8 * 4)
    let count = values.withUnsafeMutableBufferPointer { read($0.baseAddress) }
    guard count > 0, count <= 8 else { return [] }
    return (0..<Int(count)).map { index in
        let offset = index * 4
        return AgentArrivalSegment(start: CGFloat(values[offset]), end: CGFloat(values[offset + 1]),
                                   opacity: values[offset + 2], highlight: values[offset + 3] != 0)
    }
}
func runningArrivalSegments(elapsed: TimeInterval) -> [AgentArrivalSegment] {
    arrivalSegments(kind: 0, elapsed: elapsed)
}

// Measure the current contour rather than assuming a fixed Mac or light width.
// Cubic arcs are sampled for the transient highlight's distance calculation.
func approximateContourLength(_ path: Path) -> CGFloat {
    var current = CGPoint.zero
    var subpathStart = CGPoint.zero
    var length: CGFloat = 0
    func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(b.x - a.x, b.y - a.y) }
    path.cgPath.applyWithBlock { element in
        let e = element.pointee
        switch e.type {
        case .moveToPoint:
            current = e.points[0]; subpathStart = current
        case .addLineToPoint:
            length += distance(current, e.points[0]); current = e.points[0]
        case .addQuadCurveToPoint:
            let start = current, control = e.points[0], end = e.points[1]
            for step in 1...16 {
                let t = CGFloat(step) / 16, u = 1 - t
                let point = CGPoint(x: u*u*start.x + 2*u*t*control.x + t*t*end.x,
                                    y: u*u*start.y + 2*u*t*control.y + t*t*end.y)
                length += distance(current, point); current = point
            }
        case .addCurveToPoint:
            let start = current, c1 = e.points[0], c2 = e.points[1], end = e.points[2]
            for step in 1...16 {
                let t = CGFloat(step) / 16, u = 1 - t
                let point = CGPoint(x: u*u*u*start.x + 3*u*u*t*c1.x + 3*u*t*t*c2.x + t*t*t*end.x,
                                    y: u*u*u*start.y + 3*u*u*t*c1.y + 3*u*t*t*c2.y + t*t*t*end.y)
                length += distance(current, point); current = point
            }
        case .closeSubpath:
            length += distance(current, subpathStart); current = subpathStart
        default: break
        }
    }
    return length
}

// Measure the first shoulder with the same metrics and cubic used by the
// visible shell, including intermediate sizes during a morph.
func notchShoulderArcLength(width: CGFloat, height: CGFloat, corners: NotchCorners) -> CGFloat {
    var metrics = [Double](repeating: 0, count: 4)
    let status = metrics.withUnsafeMutableBufferPointer {
        rustLightShellContourMetrics(Double(width), Double(height), Double(corners.bottom), Double(corners.shoulder), $0.baseAddress)
    }
    guard status == 0 else { return 0 }
    let shoulder = CGFloat(metrics[0]), control = CGFloat(metrics[2])
    var path = Path()
    path.move(to: .zero)
    path.addCurve(to: CGPoint(x: shoulder, y: shoulder),
                  control1: CGPoint(x: shoulder - control, y: 0),
                  control2: CGPoint(x: shoulder, y: control))
    return approximateContourLength(path)
}

func notchLowerArcAndSide(width: CGFloat, height: CGFloat, corners: NotchCorners) -> (arc: CGFloat, side: CGFloat)? {
    var metrics = [Double](repeating: 0, count: 4)
    let status = metrics.withUnsafeMutableBufferPointer {
        rustLightShellContourMetrics(Double(width), Double(height), Double(corners.bottom), Double(corners.shoulder), $0.baseAddress)
    }
    guard status == 0 else { return nil }
    let shoulder = CGFloat(metrics[0]), corner = CGFloat(metrics[1]), control = CGFloat(metrics[3])
    var path = Path()
    path.move(to: .zero)
    path.addCurve(to: CGPoint(x: corner, y: corner), control1: CGPoint(x: 0, y: control),
                  control2: CGPoint(x: corner - control, y: corner))
    return (approximateContourLength(path), abs(height - corner - shoulder))
}

private func agentArrivalKind(_ kind: NotchLightCue.Kind) -> Int32? {
    switch kind {
    case .agentRunning: return 0
    case .agentApproval, .agentQuestion: return 1
    case .agentDone, .agentFailed, .agentInterrupted: return 2
    case .agentMessage: return 8
    default: return nil
    }
}

// Shoulder fractions use the Rium path; the original contour can differ.
func otherAgentArrivalSegments(kind: NotchLightCue.Kind, elapsed: TimeInterval, pathLength: CGFloat, arm: CGFloat, notchWidth: CGFloat, height: CGFloat, shoulderArcLength: CGFloat? = nil) -> [AgentArrivalSegment] {
    guard let animation = agentArrivalKind(kind), animation != 0 else { return [] }
    return arrivalSegments(kind: animation, elapsed: elapsed,
                           pathLength: pathLength, arm: arm, notchWidth: notchWidth, height: height, shoulderArcLength: shoulderArcLength)
}

// The light window is above the opaque notch window. Exclude the complete
// notch silhouette after blurring so the glow cannot wash into its interior.
struct OutsideNotchMask: Shape {
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var corners: NotchCorners = .legacy
    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(notchWidth, notchHeight), AnimatablePair(corners.bottom, corners.shoulder)) }
        set { notchWidth = newValue.first.first; notchHeight = newValue.first.second; corners = NotchCorners(bottom: newValue.second.first, shoulder: newValue.second.second) }
    }
    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        let notchRect = CGRect(x: rect.midX - notchWidth / 2, y: rect.minY,
                               width: notchWidth, height: notchHeight)
        path.addPath(NotchSilhouette(corners: corners).path(in: notchRect))
        return path
    }
}

// A second exclusion removes the antialiased boundary itself after the
// silhouette mask. It keeps a half-point guard on either side of the edge,
// including the shoulders and lower rounded corners.
struct OutsideNotchEdgeMask: Shape {
    static let strokeWidth: CGFloat = 1
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var corners: NotchCorners = .legacy
    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(notchWidth, notchHeight), AnimatablePair(corners.bottom, corners.shoulder)) }
        set { notchWidth = newValue.first.first; notchHeight = newValue.first.second; corners = NotchCorners(bottom: newValue.second.first, shoulder: newValue.second.second) }
    }
    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        let notchRect = CGRect(x: rect.midX - notchWidth / 2, y: rect.minY,
                               width: notchWidth, height: notchHeight)
        let edge = NotchSilhouette(corners: corners).path(in: notchRect).cgPath.copy(strokingWithWidth: Self.strokeWidth,
            lineCap: .round, lineJoin: .round, miterLimit: 10)
        path.addPath(Path(edge))
        return path
    }
}

/// Keep the hardware camera cutout protected even if the animated shell
/// temporarily reports a smaller outline during a resize or display reflow.
struct PhysicalNotchExclusion: ViewModifier {
    let width: CGFloat
    let height: CGFloat
    func body(content: Content) -> some View {
        if width.isFinite && height.isFinite && width > 0 && height > 0 {
            // Approximate the fixed hardware cutout independently of the app's shoulder.
            content
                .mask(OutsideNotchMask(notchWidth: width, notchHeight: height, corners: .physical)
                    .fill(style: FillStyle(eoFill: true)).transaction { $0.animation = nil })
                .mask(OutsideNotchEdgeMask(notchWidth: width, notchHeight: height, corners: .physical)
                    .fill(style: FillStyle(eoFill: true)).transaction { $0.animation = nil })
        } else {
            content
        }
    }
}

// Keep one opaque path alive across state changes. SwiftUI interpolates these
// dimensions instead of inserting a second black view when the notch opens.
let notchAnimationDiagnostics = CommandLine.arguments.contains("--self-test-notch-animation")
var notchAnimationProbe: [CGSize] = []
var notchPresentedGeometryProbe: [(time: TimeInterval, size: CGSize)] = []
var notchContentRetentionProbe: [Bool] = []

struct AnimatedNotchBackdrop: Shape {
    var width: CGFloat
    var height: CGFloat
    var corners: NotchCorners = .legacy
    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(width, height), AnimatablePair(corners.bottom, corners.shoulder)) }
        set { width = newValue.first.first; height = newValue.first.second; corners = NotchCorners(bottom: newValue.second.first, shoulder: newValue.second.second) }
    }
    func path(in rect: CGRect) -> Path {
        let w = max(0, width), h = max(0, height)
        if notchAnimationDiagnostics, notchAnimationProbe.count < 1000 {
            notchAnimationProbe.append(CGSize(width: w, height: h))
        }
        return NotchSilhouette(corners: corners).path(in: CGRect(x: rect.midX - w / 2, y: rect.minY, width: w, height: h))
    }
}

private struct NotchOutlineGeometry: Equatable {
    var size: CGSize
    var corners: NotchCorners
}
private struct NotchOutlinePreference: PreferenceKey {
    static var defaultValue = NotchOutlineGeometry(size: .zero, corners: .legacy)
    static func reduce(value: inout NotchOutlineGeometry, nextValue: () -> NotchOutlineGeometry) { value = nextValue() }
}

private struct NotchIsResizingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var notchIsResizing: Bool {
        get { self[NotchIsResizingKey.self] }
        set { self[NotchIsResizingKey.self] = newValue }
    }
}

/// Draw the shell and its light in one window from the same rendered dimensions.
private struct LitNotchSurface<Content: View>: View, Animatable {
    @ObservedObject var model: Model
    var width: CGFloat
    var height: CGFloat
    var corners: NotchCorners
    var compactLight: CGFloat
    let content: Content
    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat>> {
        get {
            AnimatablePair(AnimatablePair(width, height),
                           AnimatablePair(AnimatablePair(corners.bottom, corners.shoulder), compactLight))
        }
        set {
            width = newValue.first.first
            height = newValue.first.second
            corners = NotchCorners(bottom: newValue.second.first.first, shoulder: newValue.second.first.second)
            compactLight = newValue.second.second
        }
    }
    var body: some View {
        // Music gives way to the idle contour as the panel opens.
        let lightOpacity = min(1, max(0, compactLight * 2))
        let size = CGSize(width: width, height: height)
        let followsMorph = !notchGeometryClose(size, corners: corners, targetSize: model.currentNotchOutlineSize,
                                               targetCorners: model.currentNotchCorners, tolerance: 0.025)
        GeometryReader { geometry in
            // Resolve the path here so child shapes cannot interpolate it again.
            let edge = AnimatedNotchBackdrop(width: width, height: height, corners: corners)
                .path(in: CGRect(origin: .zero, size: geometry.size))
            ZStack(alignment: .top) {
                AnimatedNotchAmbientLight(model: model, notchWidth: width, notchHeight: height,
                                          corners: corners,
                                          compactLightOpacity: lightOpacity,
                                          behindNotch: true,
                                          morphTime: followsMorph ? ProcessInfo.processInfo.systemUptime : nil)
                edge.fill(.black).allowsHitTesting(false).accessibilityHidden(true)
                content
                    .environment(\.notchIsResizing, followsMorph || model.notchGeometryInMotion)
                    .transaction { if followsMorph { $0.animation = nil } }
                    .modifier(PhysicalNotchExclusion(width: model.cameraExclusion, height: model.cameraHeight))
                    .clipShape(edge)
                if model.compactStatusVisible, let peek = model.visibleClipboardPeek, !model.clipboardBadgeFitsHeader {
                    ClipboardNotchBadge(kind: peek.kind)
                        .position(x: geometry.size.width / 2 + width / 2 + 12,
                                  y: min(height, max(32, model.cameraHeight)) / 2)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .preference(key: NotchOutlinePreference.self, value: NotchOutlineGeometry(size: size, corners: corners))
    }
}

enum NotchGeometryMotion: Equatable {
    case reduced, opening, expanded, compact, bare, shelf, detailFold
    var animation: Animation {
        switch self {
        case .reduced: return .easeOut(duration: 0.12)
        case .opening: return .timingCurve(0.16, 0.72, 0.30, 1, duration: 0.36)
        case .expanded: return .spring(response: 0.30, dampingFraction: 0.86, blendDuration: 0)
        case .compact: return .spring(response: 0.24, dampingFraction: 0.94, blendDuration: 0)
        case .bare: return .spring(response: 0.24, dampingFraction: 1.0, blendDuration: 0)
        case .shelf: return .spring(response: 0.36, dampingFraction: 0.82, blendDuration: 0)
        case .detailFold: return .spring(response: 0.40, dampingFraction: 0.86, blendDuration: 0)
        }
    }
}

@_silgen_name("rium_notch_band_fold_frame")
private func rustNotchBandFoldFrame(_ progress: Double, _ output: UnsafeMutablePointer<Double>?) -> Int32

func notchBandFoldFrame(_ progress: CGFloat) -> [CGFloat]? {
    var values = [Double](repeating: 0, count: 4)
    let status = values.withUnsafeMutableBufferPointer { rustNotchBandFoldFrame(Double(progress), $0.baseAddress) }
    return status == 0 ? values.map { CGFloat($0) } : nil
}

/// Matches the reference modifier's top-anchored scale, blur and opacity.
struct NotchBandFold: AnimatableModifier {
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    func body(content: Content) -> some View {
        let values = notchBandFoldFrame(progress) ?? [1, 1, 0, 1]
        content.scaleEffect(x: values[0], y: values[1], anchor: .top)
            .blur(radius: max(0, values[2]))
            .opacity(Double(min(1, max(0, values[3]))))
    }
}

extension AnyTransition {
    static var notchBandFold: AnyTransition {
        .modifier(active: NotchBandFold(progress: 1), identity: NotchBandFold(progress: 0))
    }
}
func notchGeometryMotion(state: Int32, reduceMotion: Bool, foldingDetail: Bool = false) -> NotchGeometryMotion {
    if reduceMotion { return .reduced }
    if state == 1 && foldingDetail { return .detailFold }
    switch state {
    case 3: return .bare
    case 4: return .shelf
    case 5: return .expanded
    default: return .compact
    }
}

struct NotchContainer: View {
    static let lightPadding: CGFloat = 48
    @ObservedObject var model: Model
    @AppStorage("rium.card.style") private var cardStyle = "liquid"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var retainsExpandedContent = false
    @State private var collapseGeneration = 0

    init(model: Model) { self.model = model }

    var body: some View {
        let outline = model.currentNotchOutlineSize
        let shellState = model.currentNotchShellState
        let keepExpandedContent = rustNotchPanelRetention(model.expanded ? 1 : 0, shellState, retainsExpandedContent ? 1 : 0) != 0
        let retainContentDuringClose = !model.expanded && keepExpandedContent
        let corners = model.currentNotchCorners
        let geometryState = NotchOutlineGeometry(size: outline, corners: corners)
        let motion = notchGeometryMotion(state: shellState, reduceMotion: reduceMotion, foldingDetail: model.foldingDetailToStatus)
        let shellMotion: NotchGeometryMotion = motion == .expanded && model.floatingIslandPlacement == nil ? .opening : motion
        let shellAnimation = model.screenshotDragClosing && !reduceMotion ? Animation.easeOut(duration: 0.2) : shellMotion.animation
        GeometryReader { geometry in
            if let island = model.floatingIslandGeometry, let placement = model.floatingIslandPlacement {
                FloatingIslandSurface(geometry: island, surfaceFrame: placement.bounds.screen, lightModel: model) {
                    ZStack(alignment: .topTrailing) {
                        NotchView(model: model, floatingSize: island.size)
                        if model.expanded {
                            FloatingIslandDragHandle(placementRevision: model.floatingIslandPlacementRevision,
                                                     bounds: placement.bounds, anchor: placement.anchor,
                                                     move: model.moveFloatingIsland)
                                .id(model.floatingIslandPlacementRevision)
                                .padding(4)
                        }
                    }
                }
                .animation(shellAnimation, value: model.expanded)
                .animation(shellAnimation, value: island.size)
            } else {
              ZStack(alignment: .top) {
                LitNotchSurface(model: model, width: outline.width,
                                height: outline.height, corners: corners, compactLight: model.expanded ? 0 : 1,
                                content: ZStack(alignment: .top) {
                    if (model.expanded || retainContentDuringClose) && model.section == .home && cardStyle == "liquid" {
                        let homeOutline = notchOutlineSize(content: model.expandedNotchSize, expanded: true, screenWidth: model.displayWidth)
                        HomeAtmosphere(model: model, width: homeOutline.width, height: homeOutline.height)
                            .transition(.identity)
                    }
                    NotchView(model: model, retainsExpandedContent: retainContentDuringClose)
                        .allowsHitTesting(model.expanded || !retainContentDuringClose)
                        .accessibilityHidden(!model.expanded && retainContentDuringClose)
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top))
                    .animation(shellAnimation, value: geometryState)
                if retainContentDuringClose && !model.expanded {
                    // Old controls stay dormant, but the compact notch still accepts a click.
                    Color.clear
                        .frame(width: outline.width, height: outline.height)
                        .contentShape(NotchContentHitShape(outline: outline, corners: corners))
                        .onTapGesture { model.expanded = true }
                        .accessibilityHidden(true)
                }
            }
              .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            }
        }
        .onChange(of: keepExpandedContent, initial: true) { _, keep in
            retainsExpandedContent = keep
        }
        .onChange(of: retainContentDuringClose) { _, retaining in
            if CommandLine.arguments.contains("--self-test-notch-animation") {
                notchContentRetentionProbe.append(retaining)
            }
        }
        .onChange(of: geometryState) { _, _ in
            if model.floatingIslandPlacement == nil { model.trackNotchGeometryTransition() }
        }
        .onChange(of: model.expanded) { _, expanded in
            collapseGeneration += 1
            if !expanded {
                let generation = collapseGeneration
                // shortcut: fallback duration is provisional until transition frames are compared.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
                    if generation == collapseGeneration && !model.expanded && !model.notchGeometryInMotion {
                        retainsExpandedContent = false
                    }
                }
            }
        }
        .onPreferenceChange(NotchOutlinePreference.self) { geometry in
            model.noteRenderedNotchOutline(geometry.size, corners: geometry.corners)
            // Restore the status as soon as the shell is visually compact.
            if retainsExpandedContent, !model.expanded, geometry.size.width > 0, geometry.size.height > 0,
               notchGeometryClose(geometry.size, corners: geometry.corners, targetSize: model.currentNotchOutlineSize,
                                  targetCorners: model.currentNotchCorners, tolerance: 2) {
                retainsExpandedContent = false
            }
        }
        .onPreferenceChange(FloatingIslandRenderedPreference.self) { geometry in
            model.recordFloatingIslandGeometry(geometry)
        }
        .onChange(of: model.notchGeometryInMotion) { _, moving in
            // Recover if display reflow interrupted the last rendered sample.
            if !moving && !model.expanded {
                retainsExpandedContent = false
            }
        }
    }
}

func shelfCatchLightEnabled(zone: ShelfDropZone, light: Bool, shelf: Bool, airDrop: Bool) -> Bool {
    light && (zone == .airDrop ? airDrop : shelf)
}

private struct ShelfDragHoverLight: View {
    let notchSize: CGSize
    let corners: NotchCorners
    let arm: CGFloat
    let thickness: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            draw(at: 0)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                draw(at: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private func draw(at time: TimeInterval) -> some View {
        Canvas { context, canvas in
            let path = lightContour(width: notchSize.width, height: notchSize.height, armWidth: arm, corners: corners)
                .applying(CGAffineTransform(translationX: (canvas.width - notchSize.width - arm * 2) / 2, y: 0))
            drawShelfHover(context: &context, path: path, travel: arm, time: time,
                           thickness: thickness, reduceMotion: reduceMotion)
        }
    }
}

private struct ShelfCatchLight: View {
    let cue: ShelfCatchCue
    let notchSize: CGSize
    let corners: NotchCorners
    let arm: CGFloat
    let thickness: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { _ in
            Canvas { context, canvas in
                let elapsed = max(0, ProcessInfo.processInfo.systemUptime - cue.started)
                let path = lightContour(width: notchSize.width, height: notchSize.height, armWidth: arm, corners: corners)
                    .applying(CGAffineTransform(translationX: (canvas.width - notchSize.width - arm * 2) / 2, y: 0))
                drawShelfCatch(context: &context, path: path, travel: arm, zone: cue.zone,
                               elapsed: elapsed, thickness: thickness, reduceMotion: reduceMotion)
            }
        }
    }
}

private func drawShelfHover(context: inout GraphicsContext, path: Path, travel: CGFloat,
                           time: TimeInterval, thickness: CGFloat, reduceMotion: Bool) {
    let length = approximateContourLength(path)
    guard length > 0 else { return }
    let tint = Color(red: 0.84, green: 0.89, blue: 1)
    drawAmbientGauge(context: &context, path: path, color: tint, opacity: 0.22, thickness: thickness)
    var progress = [Double](repeating: 0, count: 2)
    guard progress.withUnsafeMutableBufferPointer({ rustShelfHoverProgress(time, reduceMotion ? 1 : 0, $0.baseAddress) }) == 0 else { return }
    // shortcut: contour fraction and blur compositing need reference-frame comparison.
    let outer = travel * 0.1 / length
    let distance = max(0, travel / length - outer)
    let spread = max(24, travel * 0.38) / length
    for (index, value) in progress.enumerated() {
        let center = outer + CGFloat(value) * distance
        for position in [center, 1 - center] {
            drawAmbientCrest(context: &context, path: path, center: position, spread: spread,
                             color: tint, line: index == 0 ? 7 : 4, blur: index == 0 ? 3.5 : 2, opacity: 0.14 + 0.3 * value)
        }
    }
}

private func drawShelfCatch(context: inout GraphicsContext, path: Path, travel: CGFloat, zone: ShelfDropZone,
                           elapsed: TimeInterval, thickness: CGFloat, reduceMotion: Bool) {
    var frame = [Double](repeating: 0, count: 2)
    guard frame.withUnsafeMutableBufferPointer({ rustShelfCatchFrame(elapsed, reduceMotion ? 1 : 0, $0.baseAddress) }) == 0, frame[1] > 0 else { return }
    let length = approximateContourLength(path)
    guard length > 0 else { return }
    let tint = zone == .airDrop ? Color(red: 0.38, green: 0.7, blue: 1) : Color(red: 1, green: 0.8, blue: 0.46)
    drawAmbientGauge(context: &context, path: path, color: tint, opacity: 0.55 * frame[1] * frame[0], thickness: thickness)
    // shortcut: contour fraction and compositing need reference-frame comparison.
    let outer = travel * 0.1 / length
    let center = outer + CGFloat(frame[0]) * max(0, travel / length - outer)
    let spread = max(24, travel * 0.38) / length
    for position in [center, 1 - center] {
        drawAmbientCrest(context: &context, path: path, center: position, spread: spread,
                         color: tint, line: 7, blur: 3.5, opacity: 0.85 * frame[1])
    }
}

func notchEventLightHeight(kind: NotchLightCue.Kind, notchHeight: CGFloat) -> CGFloat {
    notchHeight + (kind == .agentMessage ? 80 : NotchContainer.lightPadding)
}

func notchEventHorizontalPadding(kind: NotchLightCue.Kind, notchWidth: CGFloat, armWidth: CGFloat, corners: NotchCorners) -> CGFloat {
    switch kind {
    case .clipboard, .clipboardPaste, .shortcut(.paste):
        let glowWidth = ambientGlowWidth(notch: notchWidth, arm: armWidth, topCorner: corners.shoulder, outset: 1)
        guard glowWidth > 0 else { return 48 }
        return max(48, (glowWidth - notchWidth - 2 * armWidth) / 2 + 24)
    default: return 48
    }
}

func systemHUDFrameTime(elapsed: TimeInterval, reduceMotion: Bool) -> TimeInterval {
    reduceMotion ? 0.3 : elapsed
}

private func drawSystemPrismGauge(context: inout GraphicsContext, part: Path, base: Color, highlight: Color,
                                  alpha: Double, width: CGFloat, thickness: CGFloat, originX: CGFloat = 0) {
    func shading(_ opacity: Double) -> GraphicsContext.Shading {
        .linearGradient(Gradient(colors: [highlight.opacity(opacity), base.opacity(opacity), highlight.opacity(opacity)]),
                        startPoint: CGPoint(x: originX, y: 0), endPoint: CGPoint(x: originX + width, y: 0))
    }
    var haze = context; haze.addFilter(.blur(radius: 14))
    haze.stroke(part, with: .color(highlight.opacity(alpha * 0.4)), style: StrokeStyle(lineWidth: 27 * thickness, lineCap: .round))
    var glow = context; glow.addFilter(.blur(radius: 5))
    glow.stroke(part, with: .color(base.opacity(alpha * 0.7)), style: StrokeStyle(lineWidth: 11 * thickness, lineCap: .round))
    context.stroke(part, with: shading(alpha), style: StrokeStyle(lineWidth: 3.2 * thickness, lineCap: .round))
    var core = context; core.addFilter(.blur(radius: 0.45))
    core.stroke(part, with: .color(.white.opacity(alpha * 0.72)), style: StrokeStyle(lineWidth: 0.9 * thickness, lineCap: .round))
}

private func drawSystemHUD(_ cue: NotchLightCue, context: inout GraphicsContext, contour: Path,
                           notchWidth: CGFloat, armWidth: CGFloat, originX: CGFloat = 0,
                           elapsed: TimeInterval, envelope: Double, thickness: CGFloat,
                           reduceMotion: Bool, raysEnabled: Bool) -> Bool {
    let systemTime = systemHUDFrameTime(elapsed: elapsed, reduceMotion: reduceMotion)
    let kind: Int32
    let level: Double
    switch cue.kind {
    case .systemLevel(let value), .brightness(let value):
        kind = 0
        level = rustSystemHUDLevel((cue.previousSystemLevel ?? Double(value)) / 100, Double(value) / 100, systemTime)
    case .mute(let muted):
        guard muted || !reduceMotion else { return false }
        kind = muted ? 1 : 2
        level = 0
    default: return false
    }
    let prism = systemHUDPrismColors(cue.kind)
    if kind == 1 {
        var trace = context; trace.addFilter(.blur(radius: 1))
        trace.stroke(contour, with: .color(prism.base.opacity(0.13 * envelope)), style: StrokeStyle(lineWidth: 1.6 * thickness, lineCap: .round))
        let length = approximateContourLength(contour)
        var frame = [Double](repeating: 0, count: 3)
        let status = frame.withUnsafeMutableBufferPointer {
            rustSystemMuteFrame(elapsed, Double(armWidth), Double(length), reduceMotion ? 1 : 0, $0.baseAddress)
        }
        if status == 0, !reduceMotion, frame[1] > frame[0], frame[2] > 0 {
            let part = contour.trimmedPath(from: CGFloat(frame[0]), to: CGFloat(frame[1]))
            drawSystemPrismGauge(context: &context, part: part, base: prism.base, highlight: prism.highlight,
                                 alpha: frame[2] * 0.62, width: notchWidth + 2 * armWidth, thickness: thickness, originX: originX)
            for center in frame.prefix(2) {
                drawPrismCrest(context: &context, path: contour, center: CGFloat(center), spread: 30 / length,
                               base: prism.base, highlight: prism.highlight, line: 6 * thickness,
                               blur: 3, opacity: frame[2] * 0.6, thickness: thickness)
            }
        }
        return true
    }
    if raysEnabled && !reduceMotion && armWidth > 0 {
        drawRayons(context: &context, tint: prism.base, armWidth: armWidth, notchWidth: notchWidth, envelope: envelope, thickness: thickness)
    }
    var values = [Double](repeating: 0, count: 8)
    let count = values.withUnsafeMutableBufferPointer { rustSystemHUDSegments(kind, level, systemTime, $0.baseAddress, 2) }
    if count > 0 && count <= 2 {
        for index in 0..<Int(count) {
            let start = max(0, CGFloat(values[index * 4])), end = min(1, CGFloat(values[index * 4 + 1]))
            guard end > start else { continue }
            let part = contour.trimmedPath(from: start, to: end)
            let alpha = values[index * 4 + 2], highlight = values[index * 4 + 3] != 0
            if kind == 0 {
                drawSystemPrismGauge(context: &context, part: part, base: prism.base, highlight: prism.highlight,
                                     alpha: alpha, width: notchWidth + 2 * armWidth, thickness: thickness, originX: originX)
                continue
            }
            let color = highlight ? prism.highlight : prism.base
            var glow = context; glow.addFilter(.blur(radius: 6))
            glow.stroke(part, with: .color(color.opacity(alpha * 0.35)), style: StrokeStyle(lineWidth: 8 * thickness, lineCap: .round))
            context.stroke(part, with: .color(color.opacity(alpha)), style: StrokeStyle(lineWidth: (highlight ? 2.2 : 1.2) * thickness, lineCap: .round))
        }
    }
    if kind == 0 && !reduceMotion {
        if case .brightness = cue.kind, level > 0 {
            var flare = [Double](repeating: 0, count: 3)
            let result = flare.withUnsafeMutableBufferPointer {
                rustSystemHUDBrightnessFlare(cue.systemDirection, cue.systemPulseEnergy, elapsed, $0.baseAddress)
            }
            if result == 0 && flare[2] > 0 {
                // shortcut: the reference flare color and compositing need screen comparison.
                var glow = context; glow.addFilter(.blur(radius: CGFloat(flare[1])))
                glow.stroke(contour.trimmedPath(from: 0, to: CGFloat(level)),
                            with: .color(prism.base.opacity(flare[2])),
                            style: StrokeStyle(lineWidth: CGFloat(flare[0]) * thickness, lineCap: .round, lineJoin: .round))
            }
        } else if case .systemLevel = cue.kind {
            var flare = [Double](repeating: 0, count: 3)
            let result = flare.withUnsafeMutableBufferPointer {
                rustSystemHUDVolumeFlare(level, cue.systemPulseEnergy, elapsed, $0.baseAddress)
            }
            if result == 0 && flare[1] > flare[0] && flare[2] > 0 {
                // shortcut: the reference flare color and compositing need screen comparison.
                var glow = context; glow.addFilter(.blur(radius: 6))
                glow.stroke(contour.trimmedPath(from: CGFloat(flare[0]), to: CGFloat(flare[1])),
                            with: .color(prism.highlight.opacity(flare[2])),
                            style: StrokeStyle(lineWidth: 16 * thickness, lineCap: .round, lineJoin: .round))
            }
        }
        let length = approximateContourLength(contour)
        var crest = [Double](repeating: 0, count: 4)
        let status = crest.withUnsafeMutableBufferPointer {
            rustSystemHUDPulseCrest(level, cue.systemPulseEnergy, elapsed, Double(length), $0.baseAddress)
        }
        if status == 0 && crest[3] > 0 {
            drawPrismCrest(context: &context, path: contour, center: CGFloat(crest[0]), spread: CGFloat(crest[1]),
                           base: prism.base, highlight: prism.highlight, line: CGFloat(crest[2]) * thickness,
                           blur: 2.5, opacity: crest[3], thickness: thickness)
            let limitFlash = rustSystemHUDLimitFlash(level, cue.systemPulseEnergy, elapsed)
            if limitFlash.isFinite && limitFlash > 0 {
                drawAmbientCrest(context: &context, path: contour, center: CGFloat(crest[0]), spread: 45 / length,
                                 color: prism.base, line: 12 * thickness, blur: 7, opacity: limitFlash)
            }
            if cue.restoringSound {
                var restoring = [Double](repeating: 0, count: 4)
                let result = restoring.withUnsafeMutableBufferPointer {
                    rustSystemHUDRestoreCrests(level, cue.systemPulseEnergy, elapsed, Double(length), $0.baseAddress)
                }
                if result == 0 && restoring[3] > 0 {
                    for center in restoring.prefix(2) {
                        drawPrismCrest(context: &context, path: contour, center: CGFloat(center), spread: CGFloat(restoring[2]),
                                       base: prism.base, highlight: prism.highlight, line: 7 * thickness,
                                       blur: 3, opacity: restoring[3], thickness: thickness)
                    }
                }
            }
        }
    }
    return true
}

private func drawFadingEventSegment(context: inout GraphicsContext, path: Path, tint: Color,
                                    envelope: Double, thickness: CGFloat) {
    var haze = context
    haze.addFilter(.blur(radius: 10))
    haze.stroke(path, with: .color(tint.opacity(0.28 * envelope)), style: StrokeStyle(lineWidth: 10 * thickness, lineCap: .round, lineJoin: .round))
    var glow = context
    glow.addFilter(.blur(radius: 3))
    glow.stroke(path, with: .color(tint.opacity(0.60 * envelope)), style: StrokeStyle(lineWidth: 5 * thickness, lineCap: .round, lineJoin: .round))
    context.stroke(path, with: .color(.white.opacity(0.95 * envelope)), style: StrokeStyle(lineWidth: 1.8 * thickness, lineCap: .round, lineJoin: .round))
}

private func drawShortcutLight(_ action: ShortcutAction, context: inout GraphicsContext, contour: Path,
                               gaugePath: Path, armWidth: CGFloat, elapsed: TimeInterval, envelope: Double,
                               thickness: CGFloat, reduceMotion: Bool,
                               reticleMetrics: () -> (shoulder: CGFloat, side: CGFloat, arc: CGFloat)?) {
    if reduceMotion {
        guard envelope > 0 else { return }
        drawFadingEventSegment(context: &context, path: contour, tint: shortcutPrismColors(action).base,
                               envelope: envelope, thickness: thickness)
        return
    }
    let gradientBounds = gaugePath.boundingRect
    let gradientStart = gradientBounds.minX, gradientWidth = gradientBounds.width
    let prism = shortcutPrismColors(action)
    var values = [Double](repeating: 0, count: 24)
    let count = values.withUnsafeMutableBufferPointer {
        rustNotchShortcutSegments(action.rawValue, elapsed, $0.baseAddress, 6)
    }
    if count > 0 && count <= 6 {
        for index in 0..<Int(count) {
            let start = max(0, CGFloat(values[index * 4]))
            let end = min(1, CGFloat(values[index * 4 + 1]))
            guard end > start else { continue }
            let part = gaugePath.trimmedPath(from: start, to: end)
            let alpha = values[index * 4 + 2]
            let highlight = values[index * 4 + 3] != 0
            if !highlight {
                drawSystemPrismGauge(context: &context, part: part, base: prism.base, highlight: prism.highlight,
                                     alpha: alpha, width: gradientWidth, thickness: thickness, originX: gradientStart)
                continue
            }
            // shortcut: trail color and compositing need reference-frame comparison.
            let shade = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [prism.base.opacity(alpha), prism.highlight.opacity(alpha), prism.base.opacity(alpha)]),
                startPoint: CGPoint(x: gradientStart, y: 0), endPoint: CGPoint(x: gradientStart + gradientWidth, y: 0))
            let refreshTrail = action == .refresh || action == .undo
            var glow = context; glow.addFilter(.blur(radius: refreshTrail ? 10 : 4))
            glow.opacity = 0.4
            glow.stroke(part, with: shade, style: StrokeStyle(lineWidth: (refreshTrail ? 12 : 7) * thickness, lineCap: .round))
            let highlightColor: Color = action == .save ? .white : prism.highlight
            context.stroke(part, with: .color(highlightColor.opacity(alpha)),
                           style: StrokeStyle(lineWidth: 2 * thickness, lineCap: .round))
        }
    }
    if action == .selectAll {
        var frame = [Double](repeating: 0, count: 3)
        let status = frame.withUnsafeMutableBufferPointer { rustNotchSelectAllTrace(elapsed, $0.baseAddress) }
        if status == 0 && frame[2] > 0 {
            var trace = context
            trace.addFilter(.blur(radius: CGFloat(frame[1])))
            trace.stroke(contour, with: .color(prism.highlight.opacity(frame[2])),
                         style: StrokeStyle(lineWidth: CGFloat(frame[0]) * thickness, lineCap: .round))
        }
    }
    if action == .screenshotFull {
        var frame = [Double](repeating: 0, count: 4)
        let status = frame.withUnsafeMutableBufferPointer { rustNotchScreenshotFlash(elapsed, $0.baseAddress) }
        if status == 0 && frame[3] > 0 {
            var trace = context
            trace.addFilter(.blur(radius: CGFloat(frame[2])))
            trace.stroke(contour, with: .color(prism.highlight.opacity(frame[3])),
                         style: StrokeStyle(lineWidth: CGFloat(frame[1]) * thickness, lineCap: .round))
        }
    }
    if action == .screenshotArea, let metrics = reticleMetrics() {
        var frame = [Double](repeating: 0, count: 6)
        let length = approximateContourLength(contour)
        let status = frame.withUnsafeMutableBufferPointer {
            rustNotchAreaCaptureReticle(elapsed, Double(length), Double(armWidth), Double(metrics.shoulder),
                                        Double(metrics.side), Double(metrics.arc), $0.baseAddress)
        }
        if status == 0 && frame[5] > 0 {
            for center in frame.prefix(4) {
                drawPrismCrest(context: &context, path: contour, center: CGFloat(center), spread: CGFloat(frame[4]),
                               base: prism.base, highlight: prism.highlight, line: 6 * thickness,
                               blur: 3, opacity: frame[5], thickness: thickness)
            }
        }
    }
    if action == .quit {
        var frame = [Double](repeating: 0, count: 3)
        let status = frame.withUnsafeMutableBufferPointer {
            rustNotchShortcutQuitCrest(elapsed, Double(approximateContourLength(contour)), $0.baseAddress)
        }
        if status == 0 && frame[2] > 0 && frame[1] > frame[0] {
            drawPrismCrest(context: &context, path: contour, center: 0.5, spread: CGFloat((frame[1] - frame[0]) / 2),
                           base: prism.base, highlight: prism.highlight, line: 5 * thickness,
                           blur: 2, opacity: frame[2], thickness: thickness)
        }
    }
    if action == .refresh || action == .undo {
        var frame = [Double](repeating: 0, count: 3)
        let status = frame.withUnsafeMutableBufferPointer {
            let length = Double(approximateContourLength(contour))
            return action == .refresh
                ? rustNotchShortcutRefreshCrest(elapsed, length, Double(armWidth), $0.baseAddress)
                : rustNotchShortcutUndoCrest(elapsed, length, Double(armWidth), $0.baseAddress)
        }
        if status == 0 && frame[2] > 0 && frame[1] > 0 {
            drawPrismCrest(context: &context, path: contour, center: CGFloat(frame[0]), spread: CGFloat(frame[1]),
                           base: prism.base, highlight: prism.highlight, line: 8 * thickness,
                           blur: 4, opacity: frame[2], thickness: thickness)
        }
    }
    if action == .cut {
        var frame = [Double](repeating: 0, count: 4)
        let status = frame.withUnsafeMutableBufferPointer {
            rustNotchShortcutCutCrests(elapsed, Double(approximateContourLength(contour)), $0.baseAddress)
        }
        if status == 0 && frame[3] > 0 {
            for center in frame.prefix(2) {
                drawPrismCrest(context: &context, path: contour, center: CGFloat(center), spread: CGFloat(frame[2]),
                               base: prism.base, highlight: prism.highlight, line: 8 * thickness,
                               blur: 3.5, opacity: frame[3], thickness: thickness)
            }
        }
    }
}

private func drawAgendaSegments(_ parts: [AgentArrivalSegment], context: inout GraphicsContext,
                                contour: Path, tint: Color, thickness: CGFloat) {
    for item in parts {
        let start = max(0, item.start), end = min(1, item.end)
        guard end > start else { continue }
        let part = contour.trimmedPath(from: start, to: end)
        var glow = context; glow.addFilter(.blur(radius: 5))
        glow.stroke(part, with: .color(tint.opacity(item.opacity * 0.55)), style: StrokeStyle(lineWidth: 8 * thickness, lineCap: .round))
        context.stroke(part, with: .color(tint.opacity(item.opacity)), style: StrokeStyle(lineWidth: (item.highlight ? 3 : 2) * thickness, lineCap: .round))
    }
}

private func drawCaseKeyLight(_ action: CaseKeyAction, context: inout GraphicsContext, contour: Path,
                              armWidth: CGFloat, elapsed: TimeInterval, release: Double, thickness: CGFloat) {
    guard release > 0 else { return }
    let prism = caseKeyPrismColors(action)
    let bounds = contour.boundingRect
    if action == .shiftHeld {
        let fade = min(1, elapsed / 0.07, release)
        var trace = context; trace.addFilter(.blur(radius: 10))
        trace.stroke(contour, with: .color(prism.base.opacity(0.16 * fade)),
                     style: StrokeStyle(lineWidth: 1.8 * thickness, lineCap: .round))
    }
    var values = [Double](repeating: 0, count: 16)
    let length = Double(approximateContourLength(contour))
    let count = values.withUnsafeMutableBufferPointer { rustCaseKeySegments(action.rawValue, elapsed, length, Double(armWidth), $0.baseAddress, 4) }
    if count > 0 && count <= 4 {
        for index in 0..<Int(count) {
            let start = max(0, CGFloat(values[index * 4])), end = min(1, CGFloat(values[index * 4 + 1]))
            guard end > start else { continue }
            let part = contour.trimmedPath(from: start, to: end)
            let alpha = values[index * 4 + 2] * release
            let highlight = values[index * 4 + 3] != 0
            // shortcut: the reference uses additional masked glow layers.
            let shade = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [prism.base.opacity(alpha), prism.highlight.opacity(alpha), prism.base.opacity(alpha)]),
                startPoint: CGPoint(x: bounds.minX, y: 0), endPoint: CGPoint(x: bounds.maxX, y: 0))
            var glow = context; glow.addFilter(.blur(radius: 6)); glow.opacity = 0.4
            glow.stroke(part, with: shade, style: StrokeStyle(lineWidth: 8 * thickness, lineCap: .round))
            context.stroke(part, with: highlight ? .color(prism.highlight.opacity(alpha)) : shade,
                           style: StrokeStyle(lineWidth: (highlight ? 2.4 : 1.6) * thickness, lineCap: .round))
        }
    }
}

private func drawAgentResponseHalo(context: GraphicsContext, elapsed: TimeInterval, notchWidth: CGFloat,
                                   center: CGPoint, tint: Color) {
    var frame = [Double](repeating: 0, count: 3)
    let result = frame.withUnsafeMutableBufferPointer {
        rustNotchResponseHalo(elapsed, Double(notchWidth), $0.baseAddress)
    }
    guard result == 0, frame[2] > 0 else { return }
    let width = CGFloat(frame[0]), height = CGFloat(frame[1])
    let ellipse = CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
    var halo = context
    halo.addFilter(.blur(radius: 13))
    halo.fill(Path(ellipseIn: ellipse), with: .color(tint.opacity(frame[2])))
}

private func drawContourArrivals(_ arrivals: [AgentArrivalSegment], context: inout GraphicsContext,
                                 contour: Path, tint: Color, thickness: CGFloat,
                                 ambientCrests: Bool = false, edgeMaskWidth: CGFloat = 0) {
    for arrival in arrivals {
        let start = max(0, arrival.start), end = min(1, arrival.end)
        guard end > start else { continue }
        let part = contour.trimmedPath(from: start, to: end)
        if arrival.highlight {
            if ambientCrests {
                drawAmbientCrest(context: &context, path: contour, center: (arrival.start + arrival.end) / 2,
                                 spread: (arrival.end - arrival.start) / 2, color: tint,
                                 line: 6 * thickness, blur: 3, opacity: arrival.opacity)
            } else {
                context.stroke(part, with: .color(tint.opacity(arrival.opacity)), style: StrokeStyle(lineWidth: 7 * thickness + edgeMaskWidth, lineCap: .round, lineJoin: .round))
                context.stroke(part, with: .color(.white.opacity(arrival.opacity)), style: StrokeStyle(lineWidth: 1.6 * thickness + edgeMaskWidth, lineCap: .round, lineJoin: .round))
            }
        } else {
            context.stroke(part, with: .color(tint.opacity(arrival.opacity)), style: StrokeStyle(lineWidth: 3.4 * thickness + edgeMaskWidth, lineCap: .round, lineJoin: .round))
        }
    }
}

private func musicArrivalKind(_ kind: NotchLightCue.Kind) -> Int32? {
    switch kind {
    case .musicPlayback(let playing): return playing ? 5 : 6
    case .musicTrack: return 7
    case .musicSkip(let forward): return forward ? 9 : 10
    case .musicSkipArrival: return 11
    case .musicSkipHunt(let forward): return forward ? 12 : 13
    default: return nil
    }
}

private func drawMusicArrival(kind: Int32, context: inout GraphicsContext, contour: Path, armWidth: CGFloat,
                               elapsed: TimeInterval, envelope: Double, thickness: CGFloat,
                               reduceMotion: Bool, musicTint: NSColor) {
    guard envelope > 0 else { return }
    let tint = Color(nsColor: musicTint)
    if reduceMotion && kind != 11 {
        let opacity: Double
        switch kind {
        case 5, 6: opacity = rustPlaybackTransitionEnvelope(elapsed) * 0.45
        case 9, 10, 12, 13: opacity = rustTrackSkipReducedOpacity(kind, elapsed)
        default: opacity = envelope * 0.45
        }
        if opacity.isFinite && opacity > 0 {
            drawAmbientGauge(context: &context, path: contour, color: tint, opacity: opacity, thickness: thickness)
        }
        return
    }
    let bounds = contour.boundingRect
    let highlight = Color(nsColor: musicPrismHighlight(musicTint))
    let parts = arrivalSegments(kind: kind, elapsed: elapsed, pathLength: approximateContourLength(contour), arm: armWidth)
    for (index, item) in parts.enumerated() {
        let start = max(0, item.start), end = min(1, item.end)
        guard end > start else { continue }
        let part = contour.trimmedPath(from: start, to: end)
        if kind == 5 || kind == 6 {
            if item.highlight {
                drawPrismCrest(context: &context, path: contour, center: (item.start + item.end) / 2,
                               spread: (item.end - item.start) / 2, base: tint, highlight: highlight,
                               line: (kind == 5 ? 8 : 6) * thickness, blur: kind == 5 ? 3 : 2,
                               opacity: item.opacity, thickness: thickness)
            } else {
                drawSystemPrismGauge(context: &context, part: part, base: tint, highlight: highlight,
                                     alpha: item.opacity, width: bounds.width, thickness: thickness, originX: bounds.minX)
            }
            continue
        }
        if kind == 11 {
            drawSystemPrismGauge(context: &context, part: part, base: tint,
                                 highlight: highlight, alpha: item.opacity,
                                 width: bounds.width, thickness: thickness, originX: bounds.minX)
            continue
        }
        if kind == 9 || kind == 10 || kind == 12 || kind == 13 {
            if item.highlight {
                drawPrismCrest(context: &context, path: contour, center: (item.start + item.end) / 2,
                               spread: (item.end - item.start) / 2, base: tint,
                               highlight: highlight,
                               line: (index == 1 ? 8 : 6) * thickness, blur: index == 1 ? 3 : 3.5,
                               opacity: item.opacity, thickness: thickness)
            } else {
                var trail = context; trail.addFilter(.blur(radius: 6))
                trail.stroke(part, with: .color(tint.opacity(item.opacity)),
                             style: StrokeStyle(lineWidth: 15 * thickness, lineCap: .round, lineJoin: .round))
            }
            continue
        }
        var glow = context; glow.addFilter(.blur(radius: 6))
        glow.stroke(part, with: .color(tint.opacity(item.opacity * 0.5)), style: StrokeStyle(lineWidth: 8 * thickness, lineCap: .round))
        context.stroke(part, with: .color(tint.opacity(item.opacity)), style: StrokeStyle(lineWidth: (item.highlight ? 2 : 3) * thickness, lineCap: .round))
    }
}

struct NotchEventLight: View {
    let cue: NotchLightCue
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    var thickness: CGFloat = 1
    var armWidth: CGFloat = NotchContainer.lightPadding
    var musicTint: NSColor = defaultMusicLightColor
    var corners: NotchCorners = .legacy
    var onLightSurface = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("rium.light.rays") private var addsRays = false
    @AppStorage("rium.light.style") private var lightStyle = "classic"
    private var raysEnabled: Bool { addsRays && lightStyle != "classic" }
    private var horizontalGlowPadding: CGFloat {
        notchEventHorizontalPadding(kind: cue.kind, notchWidth: notchWidth, armWidth: armWidth, corners: corners)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { _ in
            let now = ProcessInfo.processInfo.systemUptime
            let elapsed = cue.elapsed(at: now)
            Canvas { context, size in
                context.translateBy(x: horizontalGlowPadding, y: 0)
                let contour = lightContour(width: notchWidth, height: notchHeight, armWidth: armWidth, corners: corners)
                if cue.kind == .systemNotification {
                    drawNotificationArrival(context: &context, path: contour, elapsed: elapsed, duration: cue.duration,
                                            thickness: thickness, reduceMotion: reduceMotion, tint: cue.notificationTint,
                                            fadeArms: true)
                    return
                }
                if cue.kind == .screenshot {
                    drawScreenshotFileGlow(context: &context, path: contour, length: approximateContourLength(contour),
                                           arm: armWidth, thickness: thickness, elapsed: elapsed, reduceMotion: reduceMotion)
                    return
                }
                if cue.kind == .clipboard || cue.kind == .clipboardPaste || cue.kind == .shortcut(.paste) {
                    // shortcut: compositing and the additional halo need reference-frame comparison.
                    let paste = cue.kind == .clipboardPaste || cue.kind == .shortcut(.paste)
                    let baseTint: Color = paste ? Color(red: 0.72, green: 0.35, blue: 1) : Color(red: 0.12, green: 0.94, blue: 1)
                    let highlightTint: Color = paste ? Color(red: 1, green: 0.18, blue: 0.65) : Color(red: 0.16, green: 0.32, blue: 1)
                    var frame = [Double](repeating: 0, count: 3)
                    let status = frame.withUnsafeMutableBufferPointer { buffer in
                        if paste { return rustPasteSweepFrame(elapsed, pasteSweepTravel, reduceMotion ? 1 : 0, buffer.baseAddress) }
                        return rustCopySweepFrame(elapsed, copySweepOut, copySweepBack, reduceMotion ? 1 : 0, buffer.baseAddress)
                    }
                    let glowWidth = ambientGlowWidth(notch: notchWidth, arm: armWidth, topCorner: corners.shoulder, outset: 1)
                    drawCopyImpact(context: &context, path: contour, elapsed: elapsed,
                                   reduceMotion: reduceMotion, tint: baseTint, thickness: thickness, glowWidth: glowWidth)
                    let fade = paste ? frame[2] : frame[1]
                    let trail = paste ? nil : copySweepTrailCenter(elapsed: elapsed, reduceMotion: reduceMotion)
                    guard status == 0, fade > 0 else { return }
                    let centers = paste && frame[0] != frame[1] ? [CGFloat(frame[0]), CGFloat(frame[1])] : [CGFloat(frame[0])]
                    if raysEnabled {
                        drawRayons(context: &context, tint: baseTint, armWidth: armWidth,
                                   notchWidth: notchWidth, envelope: fade, thickness: thickness)
                    }
                    let contourWidth = notchWidth + 2 * armWidth
                    let glowLeft = (contourWidth - glowWidth) / 2
                    func shading(center: CGFloat, halfWidth: CGFloat, opacity: Double, tint: Color) -> GraphicsContext.Shading {
                        let stops = Gradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .clear, location: max(0, center - halfWidth)),
                            .init(color: tint.opacity(opacity), location: center),
                            .init(color: .clear, location: min(1, center + halfWidth)),
                            .init(color: .clear, location: 1)
                        ])
                        return .linearGradient(stops, startPoint: CGPoint(x: glowLeft, y: 0), endPoint: CGPoint(x: glowLeft + glowWidth, y: 0))
                    }
                    var halo = context; halo.addFilter(.blur(radius: 7))
                    let haloFrames: [(CGFloat, Double)] = {
                        guard paste else { return trail.map { [($0, fade)] } ?? [] }
                        var delayed = [Double](repeating: 0, count: 3)
                        let result = delayed.withUnsafeMutableBufferPointer {
                            rustPasteSweepFrame(max(0, elapsed - 0.07), pasteSweepTravel, reduceMotion ? 1 : 0, $0.baseAddress)
                        }
                        guard result == 0 else { return [] }
                        let positions = delayed[0] == delayed[1] ? [delayed[0]] : [delayed[0], delayed[1]]
                        return positions.map { (CGFloat($0), fade) }
                    }()
                    for (center, opacity) in haloFrames {
                        halo.stroke(contour, with: shading(center: center, halfWidth: paste ? 0.17 : 0.19, opacity: opacity * (paste ? 0.56 : 0.6), tint: baseTint),
                                    style: StrokeStyle(lineWidth: (paste ? 15 : 16) * thickness, lineCap: .round, lineJoin: .round))
                    }
                    for center in centers {
                        let layers: [(half: CGFloat, width: CGFloat, blur: CGFloat, opacity: Double, tint: Color)] = [
                            (0.24, 27, 12, 0.48, highlightTint), (0.14, 12, 5, 0.82, baseTint),
                            (0.09, 4, 0.5, 0.92, baseTint), (0.045, 1.1, 1.2, 1, .white)
                        ]
                        for layer in layers {
                            var layerContext = context
                            if layer.blur > 0 { layerContext.addFilter(.blur(radius: layer.blur)) }
                            layerContext.stroke(contour, with: shading(center: center, halfWidth: layer.half, opacity: fade * layer.opacity, tint: layer.tint),
                                                style: StrokeStyle(lineWidth: layer.width * thickness, lineCap: .round, lineJoin: .round))
                        }
                    }
                    if paste {
                        var band = [Double](repeating: 0, count: 4)
                        let bandStatus = band.withUnsafeMutableBufferPointer {
                            rustPasteCenterBand(elapsed, pasteSweepTravel, reduceMotion ? 1 : 0, $0.baseAddress)
                        }
                        if bandStatus == 0 && band[3] > 0 {
                            // shortcut: band contour blending needs reference-frame comparison.
                            var bandContext = context
                            bandContext.addFilter(.blur(radius: CGFloat(band[2])))
                            bandContext.stroke(contour, with: shading(center: 0.5, halfWidth: CGFloat(band[0]), opacity: fade * band[3], tint: baseTint),
                                               style: StrokeStyle(lineWidth: CGFloat(band[1]) * thickness, lineCap: .round, lineJoin: .round))
                        }
                    }
                    return
                }
                let cycle = cue.duration
                let phase = cycle.isFinite ? min(1, (elapsed.truncatingRemainder(dividingBy: cycle)) / cycle) : 0
                let envelope = notchEventEnvelope(cue, at: now)
                let timerActivation: Bool = { if case .timerActivation = cue.kind { return true }; return false }()
                let airDropCompletion = cue.kind == .airDrop || cue.kind == .airDropSent
                let agentCue = timerActivation || airDropCompletion || agentArrivalKind(cue.kind) != nil
                let start = reduceMotion ? 0.0 : max(0.0, phase * 1.3 - 0.3)
                let end = reduceMotion ? 1.0 : min(1.0, phase * 1.3 + 0.03)
                guard envelope > 0 else { return }
                var segment = Path()
                if agentCue && !reduceMotion {
                    let head = min(0.5, phase * 0.58), tail = max(0, head - 0.13)
                    if head > tail {
                        segment.addPath(contour.trimmedPath(from: 0.5 - head, to: 0.5 - tail))
                        segment.addPath(contour.trimmedPath(from: 0.5 + tail, to: 0.5 + head))
                    }
                } else if start < end { segment = contour.trimmedPath(from: start, to: end) }
                let tint: Color
                switch cue.kind {
                case .clipboard, .clipboardPaste, .screenshot, .systemNotification, .systemControl: tint = .white
                case .systemLevel, .brightness, .mute: tint = systemHUDPrismColors(cue.kind).base
                case .caseKey(let action): tint = caseKeyPrismColors(action).base
                case .shortcut(let action): tint = shortcutPrismColors(action).base
                case .shelf: tint = Color(red: 1, green: 0.8, blue: 0.46)
                case .agentApproval, .agentQuestion: tint = AgentStatusPalette.attention
                case .agentDone: tint = AgentStatusPalette.done
                case .agentFailed: tint = AgentStatusPalette.failure
                case .agentInterrupted: tint = .gray
                case .calendarAdded: tint = .cyan
                case .reminderAdded: tint = .blue
                case .batterySource: tint = .green
                case .batteryWarning(let critical): tint = critical ? .red : .orange
                case .timerActivation(let phase), .timerTransition(let phase): tint = phase.lightColor
                case .musicPlayback, .musicTrack, .musicSkip, .musicSkipHunt, .musicSkipArrival: tint = Color(nsColor: musicTint)
                case .airDrop, .airDropSent: tint = Color(red: 0.55, green: 0.73, blue: 1.0)
                case .agentRunning: tint = AgentStatusPalette.running
                // shortcut: the reference uses this cyan on its response halo;
                // the separate crest color and blending still need comparison.
                case .agentMessage: tint = Color(red: 0.52, green: 0.83, blue: 1)
                }
                if case let .batterySource(percent, external) = cue.kind {
                    let edge = lightContour(width: notchWidth, height: notchHeight, armWidth: 0, corners: corners)
                        .applying(CGAffineTransform(translationX: armWidth, y: 0))
                    drawBatteryLevel(context: &context, path: edge, percent: percent, external: external,
                                     elapsed: elapsed, envelope: envelope, tint: tint, thickness: thickness,
                                     reduceMotion: reduceMotion)
                    return
                }
                if case .batteryWarning = cue.kind {
                    drawBatteryWarning(context: &context, path: contour, elapsed: elapsed, envelope: envelope,
                                       tint: tint, thickness: thickness, reduceMotion: reduceMotion)
                    return
                }
                if case let .shortcut(action) = cue.kind, !reduceMotion {
                    // The print gauge covers the card and does not extend onto the light arms.
                    let gaugePath = action == .print
                        ? lightContour(width: notchWidth, height: notchHeight, armWidth: 0, corners: corners)
                            .applying(CGAffineTransform(translationX: armWidth, y: 0))
                        : contour
                    drawShortcutLight(action, context: &context, contour: contour, gaugePath: gaugePath,
                                      armWidth: armWidth, elapsed: elapsed, envelope: envelope,
                                      thickness: thickness, reduceMotion: false) {
                        guard let lower = notchLowerArcAndSide(width: notchWidth, height: notchHeight, corners: corners) else { return nil }
                        return (notchShoulderArcLength(width: notchWidth, height: notchHeight, corners: corners), lower.side, lower.arc)
                    }
                    return
                }
                if case let .caseKey(action) = cue.kind, !reduceMotion {
                    drawCaseKeyLight(action, context: &context, contour: contour, armWidth: armWidth,
                                     elapsed: elapsed, release: cue.shiftReleaseFade(at: now), thickness: thickness)
                    return
                }
                if drawSystemHUD(cue, context: &context, contour: contour, notchWidth: notchWidth, armWidth: armWidth,
                                 elapsed: elapsed, envelope: envelope, thickness: thickness,
                                 reduceMotion: reduceMotion, raysEnabled: raysEnabled) { return }
                if (cue.kind == .calendarAdded || cue.kind == .reminderAdded) && !reduceMotion {
                    let parts = arrivalSegments(kind: cue.kind == .calendarAdded ? 3 : 4, elapsed: elapsed,
                                                pathLength: approximateContourLength(contour), arm: armWidth,
                                                notchWidth: notchWidth, height: notchHeight,
                                                shoulderArcLength: notchShoulderArcLength(width: notchWidth, height: notchHeight, corners: corners))
                    drawAgendaSegments(parts, context: &context, contour: contour, tint: tint, thickness: thickness)
                    return
                }
                if let kind = musicArrivalKind(cue.kind), !reduceMotion || kind != 7 {
                    drawMusicArrival(kind: kind, context: &context, contour: contour, armWidth: armWidth,
                                     elapsed: elapsed, envelope: envelope, thickness: thickness,
                                     reduceMotion: reduceMotion, musicTint: musicTint)
                    return
                }
                if case .timerTransition = cue.kind {
                    drawTimerTransition(context: &context, contour: contour, elapsed: elapsed,
                                        envelope: envelope, tint: tint, thickness: thickness, reduceMotion: reduceMotion)
                    return
                }
                if cue.kind == .agentMessage && !reduceMotion && lightStyle != "classic" {
                    drawAgentResponseHalo(context: context, elapsed: elapsed, notchWidth: notchWidth,
                                          center: CGPoint(x: armWidth + notchWidth / 2, y: notchHeight + 3), tint: tint)
                }
                if raysEnabled {
                    let halo = cue.isSystemHUD || cue.kind == .clipboard ? Color(red: 0.55, green: 0.73, blue: 1.0) : tint
                    drawRayons(context: &context, tint: halo, armWidth: armWidth, notchWidth: notchWidth, envelope: envelope, thickness: thickness)
                    var soft = context; soft.addFilter(.blur(radius: 8))
                    soft.stroke(contour, with: .color(halo.opacity(0.25 * envelope)), style: StrokeStyle(lineWidth: 8 * thickness, lineCap: .round, lineJoin: .round))
                    var edge = context; edge.addFilter(.blur(radius: 3))
                    edge.stroke(contour, with: .color(halo.opacity(0.55 * envelope)), style: StrokeStyle(lineWidth: 4 * thickness, lineCap: .round, lineJoin: .round))
                    context.stroke(contour, with: .color(.white.opacity(0.72 * envelope)), style: StrokeStyle(lineWidth: 1.6 * thickness, lineCap: .round, lineJoin: .round))
                }
                if agentCue && !reduceMotion {
                    let arrivals = timerActivation || airDropCompletion ? runningArrivalSegments(elapsed: elapsed * 0.41)
                        : (cue.kind == .agentRunning ? runningArrivalSegments(elapsed: elapsed) : otherAgentArrivalSegments(kind: cue.kind, elapsed: elapsed, pathLength: approximateContourLength(contour), arm: armWidth, notchWidth: notchWidth, height: notchHeight, shoulderArcLength: notchShoulderArcLength(width: notchWidth, height: notchHeight, corners: corners)))
                    drawContourArrivals(arrivals, context: &context, contour: contour, tint: tint,
                                        thickness: thickness, ambientCrests: cue.kind == .agentMessage)
                    return
                }
                drawFadingEventSegment(context: &context, path: segment, tint: tint, envelope: envelope, thickness: thickness)
            }
        }
        .frame(width: notchWidth + armWidth * 2 + horizontalGlowPadding * 2,
               height: notchEventLightHeight(kind: cue.kind, notchHeight: notchHeight))
        .mask {
            if cue.isSystemHUD {
                let width = notchWidth + armWidth * 2 + horizontalGlowPadding * 2
                let fraction = systemTipFade(width)
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .white, location: fraction),
                                       .init(color: .white, location: 1 - fraction), .init(color: .clear, location: 1)],
                               startPoint: .leading, endPoint: .trailing)
            } else { Color.white }
        }
        .modifier(ContourSurfaceAdaptation(enabled: onLightSurface && contourSurfaceAdapts(cue.kind)))
    }

    private func systemTipFade(_ width: CGFloat) -> CGFloat {
        var result = 0.0
        return rustSystemTipFade(Double(width), &result) == 0 ? CGFloat(result) : 0
    }
}

func receivingLightElapsed(started: TimeInterval, now: TimeInterval) -> TimeInterval {
    guard started.isFinite, started > 0, now.isFinite else { return 2 }
    return max(0, now - started)
}

private func drawReceivingTide(context: inout GraphicsContext, contour: Path, edge: Path,
                               elapsed: TimeInterval, progress: Double?, held: Bool, reduceMotion: Bool,
                               thickness: CGFloat, surfaceStyle: Float, edgeMaskWidth: CGFloat = 0) {
    var parameters = [Double](repeating: 0, count: 2)
    let status = parameters.withUnsafeMutableBufferPointer {
        rustReceivingTide(elapsed, elapsed, progress ?? 0, held ? 1 : 0, reduceMotion ? 1 : 0, $0.baseAddress)
    }
    let charge = status == 0 ? max(0, min(1.5, parameters[1])) : 0
    let components = edgeWaveTint(nil)
    var halo = context; halo.addFilter(.blur(radius: 8))
    halo.stroke(edge, with: .color(edgeWaveFallbackColor(components, opacity: 0.20 * charge, style: surfaceStyle)), style: StrokeStyle(lineWidth: 9 * thickness, lineCap: .round))
    context.stroke(edge, with: .color(edgeWaveFallbackColor(components, opacity: 0.45 * charge, style: surfaceStyle)), style: StrokeStyle(lineWidth: 2 * thickness + edgeMaskWidth, lineCap: .round))
    if !held {
        // Approximate the radial front with two segments moving along the current contour.
        let distance = CGFloat(min(0.49, max(0, parameters[0] / 1.05 * 0.5)))
        for center in [0.5 - distance, 0.5 + distance] {
            let segment = contour.trimmedPath(from: max(0, center - 0.035), to: min(1, center + 0.035))
            var glow = context; glow.addFilter(.blur(radius: 7))
            glow.stroke(segment, with: .color(edgeWaveFallbackColor(components, opacity: 0.32, style: surfaceStyle)), style: StrokeStyle(lineWidth: 8 * thickness, lineCap: .round))
            context.stroke(segment, with: .color(edgeWaveFallbackColor(components, opacity: 0.7, style: surfaceStyle)), style: StrokeStyle(lineWidth: 1.8 * thickness + edgeMaskWidth, lineCap: .round))
        }
    }
}

// shortcut: the shader's spatial noise and exact blending are not yet reproduced.
struct NotchReceivingLight: View {
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let armWidth: CGFloat
    let thickness: CGFloat
    let progress: Double?
    let started: TimeInterval
    var surfaceStyle: Float = 0
    var corners: NotchCorners = .legacy
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var useMetal = false
    @State private var metalFailed = false
    @State private var metalID = UUID()
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { _ in
            let clock = ProcessInfo.processInfo.systemUptime
            let elapsed = receivingLightElapsed(started: started, now: clock)
            let held = reduceMotion || elapsed >= 2
            Group {
            if held && useMetal && !reduceMotion {
                let safeProgress = progress.flatMap { $0.isFinite ? min(1, max(0, $0)) : nil } ?? 0
                EdgeWaveMetal(cue: EdgeWaveCue(id: metalID, started: started, inward: true),
                              notchSize: CGSize(width: notchWidth, height: notchHeight), heldProgress: safeProgress,
                              lightThickness: thickness, surfaceStyle: surfaceStyle) {
                    metalFailed = true; useMetal = false
                }.frame(width: notchWidth + 2 * armWidth + 40, height: notchHeight + NotchContainer.lightPadding)
            } else {
            Canvas { context, _ in
                context.translateBy(x: 20, y: 0)
                let contour = lightContour(width: notchWidth, height: notchHeight, armWidth: armWidth, corners: corners)
                let edge = lightContour(width: notchWidth, height: notchHeight, armWidth: 0, corners: corners)
                    .applying(CGAffineTransform(translationX: armWidth, y: 0))
                drawReceivingTide(context: &context, contour: contour, edge: edge, elapsed: elapsed, progress: progress,
                                  held: held, reduceMotion: reduceMotion, thickness: thickness, surfaceStyle: surfaceStyle)
            }.frame(width: notchWidth + 2 * armWidth + 40, height: notchHeight + NotchContainer.lightPadding)
            }
            }
            .onChange(of: held) { value in
                // Pick once at the held phase boundary; a late Metal pipeline
                // must not replace an already-visible Canvas mid-transfer.
                if value && !reduceMotion && !metalFailed { useMetal = EdgeWaveMetal.available }
            }
        }
        .onAppear { metalFailed = false; useMetal = EdgeWaveMetal.available }
        .onChange(of: started) { _, _ in
            metalFailed = false; useMetal = EdgeWaveMetal.available; metalID = UUID()
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

// Glance's Rayons uses separate arm fog, rays and particles.
func rayonCount(armWidth: CGFloat) -> Int {
    guard armWidth.isFinite else { return 5 }
    return min(34, max(5, Int(min(544, max(40, armWidth - 14)) / 16)))
}
func rayonLayerCenter(armWidth: CGFloat, notchWidth: CGFloat, left: Bool) -> CGFloat {
    let halfRun = max(40, armWidth - 14) / 2
    return left ? armWidth - halfRun : armWidth + notchWidth + halfRun
}
func drawRayons(context: inout GraphicsContext, tint: Color, armWidth: CGFloat, notchWidth: CGFloat, envelope: Double, thickness: CGFloat) {
    guard armWidth > 0, envelope > 0 else { return }
    let count = rayonCount(armWidth: armWidth)
    // shortcut: the common topY is aligned to the canvas until the reference frame is compared.
    let lightTop: CGFloat = 0
    let speckWidth = max(40, armWidth - 14) + 24, speckHeight: CGFloat = 66
    var specks = [Double](repeating: 0, count: 1400 * 4)
    let speckCount = specks.withUnsafeMutableBufferPointer {
        rustHumiditySpecks(Double(speckWidth), Double(speckHeight), 1, $0.baseAddress, $0.count)
    }
    for side in 0..<2 {
        let direction: CGFloat = side == 0 ? -1 : 1
        let origin = side == 0 ? armWidth : armWidth + notchWidth
        let layerCenter = rayonLayerCenter(armWidth: armWidth, notchWidth: notchWidth, left: side == 0)
        // OrganicRaysNotchLight.armFog uses a rounded, vertically graded wash
        // with a separate horizontal fade. Scale and placement still require
        // a live comparison; the shape and fade stops come from static REA.
        var fogParameters = [Double](repeating: 0, count: 7)
        let fogStatus = fogParameters.withUnsafeMutableBufferPointer { rustOrganicRayFog(Double(armWidth), 1, $0.baseAddress) }
        guard fogStatus == 0 else { continue }
        let fogWidth = CGFloat(fogParameters[0]), fogHeight = CGFloat(fogParameters[1])
        let fogRect = CGRect(x: layerCenter - fogWidth / 2, y: lightTop, width: fogWidth, height: fogHeight)
        let leftFade = CGFloat(fogParameters[5]), rightFade = CGFloat(fogParameters[6])
        var fog = context
        fog.addFilter(.blur(radius: 11))
        fog.drawLayer { layer in
            let shape = Path(roundedRect: fogRect, cornerRadius: 10)
            layer.fill(shape, with: .linearGradient(
                Gradient(colors: [tint.opacity(fogParameters[2] * envelope), tint.opacity(fogParameters[3] * envelope), tint.opacity(fogParameters[4])]),
                startPoint: CGPoint(x: fogRect.midX, y: fogRect.minY), endPoint: CGPoint(x: fogRect.midX, y: fogRect.maxY)))
            layer.blendMode = .destinationIn
            layer.fill(Path(fogRect), with: .linearGradient(
                Gradient(stops: [.init(color: .clear, location: 0), .init(color: .white, location: leftFade),
                                 .init(color: .white, location: rightFade), .init(color: .clear, location: 1)]),
                startPoint: CGPoint(x: fogRect.minX, y: fogRect.midY), endPoint: CGPoint(x: fogRect.maxX, y: fogRect.midY)))
        }
        var rayValues = [Double](repeating: 0, count: 5)
        for i in 0..<count {
            let status = rayValues.withUnsafeMutableBufferPointer {
                rustOrganicRay(Int32(i), Int32(count), Int32(direction), Double(armWidth), 1, Double(thickness), $0.baseAddress)
            }
            guard status == 0 else { continue }
            let x = origin + direction * CGFloat(rayValues[0])
            let length = CGFloat(rayValues[1]), width = CGFloat(rayValues[2])
            var ray = Path()
            ray.move(to: CGPoint(x: -width * 0.2, y: 0))
            ray.addLine(to: CGPoint(x: width * 0.2, y: 0))
            ray.addLine(to: CGPoint(x: width / 2, y: length))
            ray.addLine(to: CGPoint(x: -width / 2, y: length)); ray.closeSubpath()
            // shortcut: original scale and vertical anchor require frame comparison.
            var rotated = context
            rotated.translateBy(x: x, y: lightTop)
            rotated.rotate(by: .degrees(rayValues[3]))
            rotated.fill(ray, with: .linearGradient(
                Gradient(colors: [tint.opacity(rayValues[4] * envelope), tint.opacity(rayValues[4] * 0.3 * envelope), .clear]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: length)))
        }
        if speckCount > 0 {
            // shortcut: exact vertical placement and the reference's scale need frame comparison.
            let rect = CGRect(x: layerCenter - speckWidth / 2, y: lightTop, width: speckWidth, height: speckHeight)
            let fade = min(0.3, max(0.08, 30 / speckWidth))
            context.drawLayer { layer in
                for i in 0..<Int(speckCount) {
                    let offset = i * 4, radius = CGFloat(specks[offset + 2])
                    let x = rect.minX + CGFloat(specks[offset]) * rect.width
                    let y = rect.minY + CGFloat(specks[offset + 1]) * rect.height
                    layer.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                               with: .color(tint.opacity(specks[offset + 3] * envelope)))
                }
                layer.blendMode = .destinationIn
                layer.fill(Path(rect), with: .linearGradient(
                    Gradient(stops: [.init(color: .clear, location: 0), .init(color: .white, location: fade),
                                     .init(color: .white, location: 1 - fade), .init(color: .clear, location: 1)]),
                    startPoint: CGPoint(x: rect.minX, y: rect.midY), endPoint: CGPoint(x: rect.maxX, y: rect.midY)))
                layer.fill(Path(rect), with: .linearGradient(
                    Gradient(stops: [.init(color: .white.opacity(0.6), location: 0), .init(color: .white, location: 0.14),
                                     .init(color: .white.opacity(0.5), location: 0.55), .init(color: .clear, location: 1)]),
                    startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
            }
        }
    }
}

struct NotchAmbientLight: View {
    @ObservedObject var model: Model

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !model.notchGeometryInMotion)) { _ in
            // The opaque shell is the source of truth while it animates. A
            // second independently-started spring can otherwise drift inside it.
            let outline = model.renderedNotchOutlineSize ?? model.currentNotchOutlineSize
            let corners = model.renderedNotchCorners ?? model.currentNotchCorners
            AnimatedNotchAmbientLight(model: model, notchWidth: outline.width, notchHeight: outline.height,
                                      corners: corners)
        }
    }
}

/// Exclude the floating shell or its anti-aliased edge after all blurs.
struct FloatingIslandOutsideMask: Shape {
    static let edgeWidth: CGFloat = 1
    let frame: CGRect
    let radius: CGFloat
    let edgeOnly: Bool
    func path(in rect: CGRect) -> Path {
        var result = Path(rect)
        let shell = FloatingIslandShape(radius: radius).path(in: frame)
        if edgeOnly {
            result.addPath(Path(shell.cgPath.copy(strokingWithWidth: Self.edgeWidth, lineCap: .round, lineJoin: .round, miterLimit: 10)))
        } else {
            result.addPath(shell)
        }
        return result
    }
}

func floatingLightEnvelope(elapsed: TimeInterval, duration: TimeInterval) -> Double {
    guard elapsed.isFinite, elapsed >= 0, duration > 0, !duration.isNaN else { return 0 }
    let entry = min(1, elapsed / 0.12)
    guard duration.isFinite else { return entry }
    return max(0, min(entry, (duration - elapsed) / 0.25))
}

func floatingLightReachScale(_ preset: String) -> CGFloat {
    switch preset {
    case "narrow": return 0.50
    case "medium": return 2.0 / 3.0
    case "wide": return 5.0 / 6.0
    default: return 1.0
    }
}

struct NotchLightProfile {
    let thickness: CGFloat
    let intensity: Double

    init(_ setting: CGFloat) {
        let increase = min(2, max(0.5, setting)) - 0.5
        thickness = 0.25 + 0.95 * increase
        intensity = min(1, 0.43 + Double(increase) * 0.8)
    }
}

func drawFloatingHalo(in context: GraphicsContext, path: Path, shading: GraphicsContext.Shading,
                      intensity: Double, active: Bool, thickness: CGFloat, reach: CGFloat) {
    var haze = context
    haze.opacity = intensity * 0.64
    haze.addFilter(.blur(radius: (active ? 7 : 5) * reach))
    haze.stroke(path, with: shading, style: StrokeStyle(lineWidth: (active ? 8 : 4) * thickness, lineCap: .round, lineJoin: .round))
    var core = context
    core.opacity = intensity
    core.addFilter(.blur(radius: 0.65))
    core.stroke(path, with: shading,
                style: StrokeStyle(lineWidth: FloatingIslandOutsideMask.edgeWidth + 1.8 * thickness,
                                   lineCap: .round, lineJoin: .round))
}

private func floatingCueTint(_ kind: NotchLightCue.Kind, musicTint: NSColor) -> Color {
    switch kind {
    case .clipboard: return Color(red: 0.12, green: 0.94, blue: 1)
    case .clipboardPaste, .shortcut(.paste): return Color(red: 0.72, green: 0.35, blue: 1)
    case .shortcut(let action): return shortcutPrismColors(action).base
    case .caseKey(let action): return caseKeyPrismColors(action).base
    case .shelf: return Color(red: 1, green: 0.8, blue: 0.46)
    case .agentApproval, .agentQuestion: return AgentStatusPalette.attention
    case .agentDone: return AgentStatusPalette.done
    case .agentFailed: return AgentStatusPalette.failure
    case .agentInterrupted: return .gray
    case .agentRunning: return AgentStatusPalette.running
    case .agentMessage: return Color(red: 0.52, green: 0.83, blue: 1)
    case .calendarAdded: return .cyan
    case .reminderAdded: return .blue
    case .batterySource: return .green
    case .batteryWarning(let critical): return critical ? .red : .orange
    case .timerActivation(let phase), .timerTransition(let phase): return phase.lightColor
    case .musicPlayback, .musicTrack, .musicSkip, .musicSkipHunt, .musicSkipArrival: return Color(nsColor: musicTint)
    case .airDrop, .airDropSent: return Color(red: 0.55, green: 0.73, blue: 1)
    case .systemLevel, .brightness, .mute: return systemHUDPrismColors(kind).base
    case .screenshot, .systemNotification, .systemControl: return .white
    }
}

private func drawBatteryLevel(context: inout GraphicsContext, path: Path, percent: Int, external: Bool,
                              elapsed: TimeInterval, envelope: Double, tint: Color, thickness: CGFloat,
                              reduceMotion: Bool, edgeMaskWidth: CGFloat = 0) {
    let fraction = CGFloat(min(100, max(0, percent))) / 100
    guard fraction > 0, envelope > 0 else { return }
    let gauge = path.trimmedPath(from: 0.5 - fraction / 2, to: 0.5 + fraction / 2)
    var glow = context
    glow.addFilter(.blur(radius: 5))
    glow.stroke(gauge, with: .color(tint.opacity(0.4 * envelope)),
                style: StrokeStyle(lineWidth: 7 * thickness, lineCap: .round))
    context.stroke(gauge, with: .color(tint.opacity(0.85 * envelope)),
                   style: StrokeStyle(lineWidth: 2 * thickness + edgeMaskWidth, lineCap: .round))
    if external && !reduceMotion {
        let position = 0.5 - fraction / 2 + fraction * CGFloat(musicRipplePhase(time: elapsed, offset: 0))
        let crest = path.trimmedPath(from: max(0, position - 0.015), to: min(1, position + 0.015))
        context.stroke(crest, with: .color(.white.opacity(envelope)),
                       style: StrokeStyle(lineWidth: 2.5 * thickness + edgeMaskWidth, lineCap: .round))
    }
}

private func drawBatteryWarning(context: inout GraphicsContext, path: Path, elapsed: TimeInterval,
                                envelope: Double, tint: Color, thickness: CGFloat,
                                reduceMotion: Bool, edgeMaskWidth: CGFloat = 0) {
    guard envelope > 0 else { return }
    let pulse = rustTimerPulse(elapsed, reduceMotion ? 1 : 0) * envelope
    var glow = context
    glow.addFilter(.blur(radius: 7))
    glow.stroke(path, with: .color(tint.opacity(pulse * 0.5)),
                style: StrokeStyle(lineWidth: 8 * thickness, lineCap: .round))
    context.stroke(path, with: .color(tint.opacity(pulse)),
                   style: StrokeStyle(lineWidth: 2 * thickness + edgeMaskWidth, lineCap: .round))
}

private func drawTimerTransition(context: inout GraphicsContext, contour: Path, elapsed: TimeInterval,
                                 envelope: Double, tint: Color, thickness: CGFloat, reduceMotion: Bool,
                                 edgeMaskWidth: CGFloat = 0) {
    let intensity = rustTimerPulse(elapsed, reduceMotion ? 1 : 0) * envelope
    guard intensity > 0 else { return }
    var glow = context
    glow.addFilter(.blur(radius: 6))
    glow.stroke(contour, with: .color(tint.opacity(intensity * 0.5)), style: StrokeStyle(lineWidth: 8 * thickness, lineCap: .round))
    context.stroke(contour, with: .color(tint.opacity(intensity)), style: StrokeStyle(lineWidth: 2 * thickness + edgeMaskWidth, lineCap: .round))
}

// shortcut: reference floating event positions still need visual comparison.
private func drawFloatingCue(_ cue: NotchLightCue, context: inout GraphicsContext,
                             openContour: Path, thickness: CGFloat, time: TimeInterval,
                             reduceMotion: Bool, musicTint: NSColor,
                             cornerMetrics: () -> (shoulder: CGFloat, side: CGFloat, arc: CGFloat)?) {
    let elapsed = cue.elapsed(at: time)
    if cue.isSystemHUD {
        let envelope = notchEventEnvelope(cue, at: time)
        guard envelope > 0 else { return }
        let bounds = openContour.boundingRect
        if drawSystemHUD(cue, context: &context, contour: openContour, notchWidth: bounds.width,
                         armWidth: 0, originX: bounds.minX, elapsed: elapsed, envelope: envelope,
                         thickness: thickness, reduceMotion: reduceMotion, raysEnabled: false) { return }
    }
    if let kind = musicArrivalKind(cue.kind) {
        drawMusicArrival(kind: kind, context: &context, contour: openContour, armWidth: 0,
                         elapsed: elapsed, envelope: notchEventEnvelope(cue, at: time), thickness: thickness,
                         reduceMotion: reduceMotion, musicTint: musicTint)
        return
    }
    let tint = floatingCueTint(cue.kind, musicTint: musicTint)
    switch cue.kind {
    case let .batterySource(percent, external):
        drawBatteryLevel(context: &context, path: openContour, percent: percent, external: external,
                         elapsed: elapsed, envelope: notchEventEnvelope(cue, at: time), tint: tint,
                         thickness: thickness, reduceMotion: reduceMotion, edgeMaskWidth: FloatingIslandOutsideMask.edgeWidth)
        return
    case .batteryWarning:
        drawBatteryWarning(context: &context, path: openContour, elapsed: elapsed,
                           envelope: notchEventEnvelope(cue, at: time), tint: tint, thickness: thickness,
                           reduceMotion: reduceMotion, edgeMaskWidth: FloatingIslandOutsideMask.edgeWidth)
        return
    case .timerTransition:
        drawTimerTransition(context: &context, contour: openContour, elapsed: elapsed,
                            envelope: notchEventEnvelope(cue, at: time), tint: tint, thickness: thickness,
                            reduceMotion: reduceMotion, edgeMaskWidth: FloatingIslandOutsideMask.edgeWidth)
        return
    case .airDrop, .airDropSent, .timerActivation:
        let envelope = notchEventEnvelope(cue, at: time)
        guard envelope > 0 else { return }
        if reduceMotion {
            drawFadingEventSegment(context: &context, path: openContour, tint: tint, envelope: envelope, thickness: thickness)
        } else {
            drawContourArrivals(runningArrivalSegments(elapsed: elapsed * 0.41), context: &context,
                                contour: openContour, tint: tint, thickness: thickness,
                                edgeMaskWidth: FloatingIslandOutsideMask.edgeWidth)
        }
        return
    case .shelf:
        if let corner = cornerMetrics() {
            drawShelfCatch(context: &context, path: openContour, travel: corner.shoulder + corner.side + corner.arc,
                           zone: .shelf, elapsed: elapsed, thickness: thickness, reduceMotion: reduceMotion)
        }
        return
    default:
        break
    }
    if cue.kind == .systemNotification {
        drawNotificationArrival(context: &context, path: openContour, elapsed: elapsed, duration: cue.duration,
                                thickness: thickness, reduceMotion: reduceMotion, tint: cue.notificationTint,
                                fadeArms: false)
        return
    }
    if cue.kind == .screenshot {
        drawScreenshotFileGlow(context: &context, path: openContour, length: approximateContourLength(openContour), arm: 0,
                               thickness: thickness, elapsed: elapsed, reduceMotion: reduceMotion)
        return
    }
    if cue.kind == .clipboard || cue.kind == .clipboardPaste || cue.kind == .shortcut(.paste) {
        let contourLength = approximateContourLength(openContour)
        guard contourLength > 0 else { return }
        let paste = cue.kind != .clipboard
        var values = [Double](repeating: 0, count: 3)
        let status = values.withUnsafeMutableBufferPointer {
            paste ? rustPasteSweepFrame(elapsed, pasteSweepTravel, reduceMotion ? 1 : 0, $0.baseAddress)
                  : rustCopySweepFrame(elapsed, copySweepOut, copySweepBack, reduceMotion ? 1 : 0, $0.baseAddress)
        }
        drawCopyImpact(context: &context, path: openContour, elapsed: elapsed,
                       reduceMotion: reduceMotion, tint: tint, thickness: thickness)
        let opacity = paste ? values[2] : values[1]
        if status == 0 && opacity > 0 {
            let centers = paste && values[0] != values[1] ? [values[0], values[1]] : [values[0]]
            for center in centers {
                drawAmbientCrest(context: &context, path: openContour, center: CGFloat(center), spread: min(0.24, 80 / contourLength),
                                 color: tint, line: 6 * thickness, blur: 4, opacity: opacity)
            }
        }
        return
    }
    if cue.kind == .calendarAdded || cue.kind == .reminderAdded {
        if reduceMotion {
            let envelope = notchEventEnvelope(cue, at: time)
            guard envelope > 0 else { return }
            drawFadingEventSegment(context: &context, path: openContour, tint: tint, envelope: envelope, thickness: thickness)
        } else if let corner = cornerMetrics() {
            let contourLength = approximateContourLength(openContour)
            // Four equal corners and two sides leave the straight bottom edge.
            let bottomHalfSpan = max(0, (contourLength - 4 * corner.arc - 2 * corner.side) / 2)
            let parts = readArrivalSegments { output in
                rustNotchAgendaArrivalSegments(cue.kind == .calendarAdded ? 3 : 4, elapsed,
                                               Double(contourLength), Double(bottomHalfSpan),
                                               Double(corner.shoulder / 2), output, 8)
            }
            drawAgendaSegments(parts, context: &context, contour: openContour, tint: tint, thickness: thickness)
        }
        return
    }
    if case let .shortcut(action) = cue.kind {
        drawShortcutLight(action, context: &context, contour: openContour, gaugePath: openContour, armWidth: 0,
                          elapsed: elapsed, envelope: notchEventEnvelope(cue, at: time), thickness: thickness,
                          reduceMotion: reduceMotion, reticleMetrics: cornerMetrics)
        return
    }
    if case let .caseKey(action) = cue.kind {
        if reduceMotion {
            let envelope = notchEventEnvelope(cue, at: time)
            guard envelope > 0 else { return }
            drawFadingEventSegment(context: &context, path: openContour, tint: tint, envelope: envelope, thickness: thickness)
        } else {
            drawCaseKeyLight(action, context: &context, contour: openContour, armWidth: 0,
                             elapsed: elapsed, release: cue.shiftReleaseFade(at: time), thickness: thickness)
        }
        return
    }
    if let animation = agentArrivalKind(cue.kind) {
        let envelope = notchEventEnvelope(cue, at: time)
        guard envelope > 0 else { return }
        if reduceMotion {
            drawFadingEventSegment(context: &context, path: openContour, tint: tint, envelope: envelope, thickness: thickness)
        } else {
            let bounds = openContour.boundingRect
            let shoulder = (animation == 1 || animation == 2) ? cornerMetrics()?.shoulder ?? 0 : 0
            // The floating shell has no horizontal arms. Its upper curve supplies the completion travel.
            let travel = animation == 2 ? shoulder / 2 : 0
            let arrivals = animation == 0 ? runningArrivalSegments(elapsed: elapsed)
                : arrivalSegments(kind: animation, elapsed: elapsed, pathLength: approximateContourLength(openContour),
                                  arm: travel, notchWidth: bounds.width, height: bounds.height,
                                  shoulderArcLength: shoulder)
            if cue.kind == .agentMessage {
                drawAgentResponseHalo(context: context, elapsed: elapsed, notchWidth: bounds.width,
                                      center: CGPoint(x: bounds.midX, y: bounds.maxY + 3), tint: tint)
            }
            drawContourArrivals(arrivals, context: &context, contour: openContour, tint: tint,
                                thickness: thickness, ambientCrests: cue.kind == .agentMessage,
                                edgeMaskWidth: FloatingIslandOutsideMask.edgeWidth)
        }
        return
    }
    let length = approximateContourLength(openContour)
    guard length > 0 else { return }
    let opacity = floatingLightEnvelope(elapsed: elapsed, duration: cue.duration)
    guard opacity > 0 else { return }
    let progress = reduceMotion || !cue.duration.isFinite ? 0.5 : min(1, elapsed / cue.duration)
    for center in [0.5 - progress * 0.45, 0.5 + progress * 0.45] {
        drawAmbientCrest(context: &context, path: openContour, center: CGFloat(center), spread: min(0.2, 64 / length),
                         color: tint, line: 4 * thickness, blur: 4, opacity: opacity * 0.75)
    }
}

// shortcut: the floating halo, state timing and layer compositing need reference-frame comparison.
struct FloatingIslandAmbientLight: View {
    @ObservedObject var model: Model
    @ObservedObject private var spectrum: SystemAudioSpectrum
    let frame: CGRect
    let radius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("rium.light.enabled") private var enabled = true
    @AppStorage("rium.light.agent") private var agentEnabled = true
    @AppStorage("rium.light.music") private var musicEnabled = true
    @AppStorage("rium.light.musicProgress") private var musicProgressEnabled = true
    @AppStorage("rium.light.timer") private var timerEnabled = true
    @AppStorage("rium.light.dictation") private var dictationEnabled = true
    @AppStorage("rium.light.airdrop") private var airDropEnabled = true
    @AppStorage("rium.light.clipboard") private var clipboardEnabled = true
    @AppStorage("rium.light.screenshot") private var screenshotEnabled = true
    @AppStorage("rium.light.shelf") private var shelfEnabled = true
    @AppStorage("rium.light.system") private var systemEnabled = true
    @AppStorage("rium.light.battery") private var batteryEnabled = true
    @AppStorage("rium.light.calendarAdded") private var calendarEnabled = true
    @AppStorage("rium.light.reminderAdded") private var reminderEnabled = true
    @AppStorage("rium.shortcuts.peeks") private var shortcutsEnabled = true
    @AppStorage("rium.light.caseKeys") private var caseKeysEnabled = false
    @AppStorage("rium.light.thickness") private var thickness = 0.6
    @AppStorage("rium.light.style") private var lightStyle = "classic"
    @AppStorage("rium.light.baseColor") private var lightBaseColor = NotchLightColor.defaultRGB
    @AppStorage("rium.light.width") private var lightWidth = "extraLarge"
    @AppStorage("rium.light.surfaceStyle") private var surfaceStyle = "neon"

    init(model: Model, frame: CGRect, radius: CGFloat) {
        self.model = model
        self.spectrum = model.musicSpectrum
        self.frame = frame
        self.radius = radius
    }

    private func cueEnabled(_ kind: NotchLightCue.Kind) -> Bool {
        switch kind {
        case .clipboard, .clipboardPaste: return clipboardEnabled
        case .airDrop, .airDropSent: return airDropEnabled
        case .screenshot: return screenshotEnabled
        case .shelf: return shelfEnabled
        case .systemNotification, .systemControl, .systemLevel, .brightness, .mute: return systemEnabled
        case .batterySource, .batteryWarning: return batteryEnabled
        case .timerActivation, .timerTransition: return timerEnabled
        case .musicPlayback, .musicTrack, .musicSkip, .musicSkipHunt, .musicSkipArrival: return musicEnabled
        case .calendarAdded: return calendarEnabled
        case .reminderAdded: return reminderEnabled
        case .shortcut(let action): return shortcutLightEnabled(action, shortcuts: shortcutsEnabled, clipboard: clipboardEnabled)
        case .caseKey: return caseKeysEnabled
        case .agentRunning, .agentApproval, .agentQuestion, .agentDone, .agentMessage, .agentFailed, .agentInterrupted: return agentEnabled
        }
    }

    var body: some View {
        if enabled && !model.hoverSuspended {
            let cues = model.visibleLightCues.filter { cueEnabled($0.kind) }
            let state = combinedAgentLightState(model.externalAgentItems, assistant: model.assistantIndicator, assistantToolRunning: model.assistantToolRunning, assistantSpeaking: model.assistantSpeaking)
            let active = agentEnabled && state.active
            let waiting = active && state.waiting
            let customStyle = active && usesCustomAgentLight(lightStyle, waiting: waiting)
            let dictating = dictationEnabled && model.dictationDisplayActive
            let playingMusic = musicEnabled && model.mediaLightPlaying && !dictating
            let spectrumIntensity = spectrum.intensityTransition
            let showsMusicProgress = musicEnabled && musicProgressEnabled && model.showsMusicProgress
            let receiving = airDropEnabled && model.receivingFile
            let shelfHover = model.fileDragActive && (shelfEnabled || airDropEnabled)
            let shelfCatch = model.shelfCatchCue.flatMap { cue in
                shelfCatchLightEnabled(zone: cue.zone, light: enabled, shelf: shelfEnabled, airDrop: airDropEnabled) ? cue : nil
            }
            let paused = cues.isEmpty && shelfCatch == nil &&
                (reduceMotion || (!shelfHover && !receiving && !dictating && customStyle && !showsMusicProgress && notchStyleTimelinePaused(lightStyle, reduceMotion: false)))
            // Shell motion has its own interpolated geometry; only the quiet breathing light needs fewer ticks.
            let animatedFeedback = active || playingMusic || receiving || dictating || showsMusicProgress ||
                shelfHover || shelfCatch != nil || !cues.isEmpty
            let profile = NotchLightProfile(thickness)
            let interval = animatedFeedback ? 1.0 / 30.0 : 1.0 / 8.0
            TimelineView(.animation(minimumInterval: interval, paused: paused)) { timeline in
                let time = ProcessInfo.processInfo.systemUptime
                let progressPath = FloatingIslandShape(radius: radius, closesTop: false).path(in: frame)
                let path = Path {
                    $0.addPath(progressPath)
                    $0.closeSubpath()
                }
                let strokeScale = profile.thickness
                let dictationTime = reduceMotion ? 0.6 : timeline.date.timeIntervalSinceReferenceDate
                let dictationColors = dictating ? dictationAuroraColors(time: dictationTime, reduceMotion: reduceMotion) : nil
                Canvas { context, _ in
                    let reach = floatingLightReachScale(lightWidth)
                    let question = state.question
                    let acting = active && state.acting
                    let styleTint = NotchLightColor.color(lightBaseColor)
                    if customStyle {
                        drawFloatingNotchStyle(lightStyle, in: &context, contour: path, tint: styleTint,
                                               time: reduceMotion ? 0 : time, strength: acting ? 1 : 0.78,
                                               thickness: strokeScale, reach: reach)
                    } else {
                        var palette = [Double](repeating: 0, count: 41 * 3)
                        let paletteStatus = waiting ? palette.withUnsafeMutableBufferPointer {
                            question
                                ? rustNotchQuestionPalette(0, 1, 0, $0.baseAddress)
                                : rustAgentOrganicPalette(0, 1, 1, 0, $0.baseAddress)
                        } : -1
                        let brightness = NotchLightBrightness(time: reduceMotion ? nil : time, variation: active ? 0.21 : 0.31)
                        let left = CGPoint(x: frame.minX, y: frame.midY), right = CGPoint(x: frame.maxX, y: frame.midY)
                        let gradient: GraphicsContext.Shading
                        if waiting && paletteStatus == 0 {
                            let stops = (0..<41).map { index in
                                let location = CGFloat(index) / 40
                                return Gradient.Stop(color: Color(red: palette[index * 3], green: palette[index * 3 + 1],
                                                                  blue: palette[index * 3 + 2]).opacity(brightness.at(location)),
                                                     location: location)
                            }
                            gradient = .linearGradient(Gradient(stops: stops), startPoint: CGPoint(x: frame.minX, y: frame.midY), endPoint: CGPoint(x: frame.maxX, y: frame.midY))
                        } else {
                            let tint = playingMusic && !active ? Color(nsColor: model.mediaLightColor) : styleTint
                            gradient = .linearGradient(brightness.gradient(tint, opacity: 1, fadesAtEnds: false),
                                                       startPoint: left, endPoint: right)
                        }
                        var pulse = [Double](repeating: 1, count: 3)
                        _ = pulse.withUnsafeMutableBufferPointer { rustNotchIdleLight(time, reduceMotion ? 1 : 0, $0.baseAddress) }
                        let intensity = active ? 0.45 : (playingMusic ? 0.22 : 0.17 * pulse[0])
                        drawFloatingHalo(in: context, path: path, shading: gradient, intensity: intensity,
                                         active: active, thickness: strokeScale, reach: reach)
                        if !active && !playingMusic && usesCustomAgentLight(lightStyle, waiting: false) {
                            drawFloatingNotchStyle(lightStyle, in: &context, contour: path, tint: styleTint,
                                                   time: reduceMotion ? 0 : time, strength: 0.38,
                                                   thickness: strokeScale, reach: reach)
                        }
                    }
                    if playingMusic && !active && !reduceMotion {
                        let intensity = musicRippleIntensity(at: time, spectrum: spectrumIntensity)
                        let tint = Color(nsColor: musicCrestColor(model.mediaLightColor))
                        let spread = 0.08 * reach
                        var ripple = context
                        ripple.addFilter(.blur(radius: 3 * reach))
                        for offset in [0.0, 0.5] {
                            let phase = musicRipplePhase(time: time, offset: offset)
                            var pair = Path()
                            for center in [0.5 - phase * 0.48, 0.5 + phase * 0.48] {
                                pair.addPath(progressPath.trimmedPath(from: max(0, center - spread), to: min(1, center + spread)))
                            }
                            ripple.stroke(pair, with: .color(tint.opacity((1 - phase * 0.7) * intensity * 0.34)),
                                          style: StrokeStyle(lineWidth: 6 * strokeScale, lineCap: .round, lineJoin: .round))
                        }
                    }
                    if showsMusicProgress {
                        let fraction = rustMusicProgressFraction(model.currentMediaElapsed(at: time), model.mediaDuration)
                        if fraction >= 0 {
                            drawMusicProgress(context: &context, path: progressPath, progress: CGFloat(fraction),
                                              tint: model.mediaLightColor, thickness: strokeScale)
                        }
                    }
                    if let dictationColors {
                        drawDictationAurora(context: &context, path: progressPath, notchWidth: frame.width,
                                            level: model.dictationLevel, time: dictationTime, thickness: strokeScale,
                                            colors: dictationColors, reach: reach, edgeMaskWidth: FloatingIslandOutsideMask.edgeWidth)
                    }
                    if receiving {
                        let elapsed = receivingLightElapsed(started: model.receivingFileStarted, now: time)
                        drawReceivingTide(context: &context, contour: progressPath, edge: progressPath, elapsed: elapsed,
                                          progress: model.receivingFileProgress, held: reduceMotion || elapsed >= 2,
                                          reduceMotion: reduceMotion, thickness: strokeScale,
                                          surfaceStyle: edgeWaveSurfaceStyle(light: model.menuBarIsLight, style: surfaceStyle),
                                          edgeMaskWidth: FloatingIslandOutsideMask.edgeWidth)
                    }
                }
                .overlay {
                    if timerEnabled {
                        TimerNotchLight(model: model, thickness: strokeScale, edgeMaskWidth: FloatingIslandOutsideMask.edgeWidth) { _ in progressPath }
                    }
                }
                .overlay {
                    if !cues.isEmpty || shelfHover || shelfCatch != nil {
                        Canvas { context, _ in
                            let corners = FloatingIslandShape(radius: radius).cornerMetrics(in: frame)
                            if let corners {
                                let travel = corners.shoulder + corners.side + corners.arc
                                if shelfHover {
                                    drawShelfHover(context: &context, path: progressPath, travel: travel, time: time,
                                                   thickness: strokeScale, reduceMotion: reduceMotion)
                                }
                                if let shelfCatch {
                                    drawShelfCatch(context: &context, path: progressPath, travel: travel, zone: shelfCatch.zone,
                                                   elapsed: max(0, time - shelfCatch.started), thickness: strokeScale, reduceMotion: reduceMotion)
                                }
                            }
                            for cue in cues {
                                drawFloatingCue(cue, context: &context, openContour: progressPath, thickness: strokeScale,
                                                time: time, reduceMotion: reduceMotion, musicTint: model.mediaLightColor) { corners }
                            }
                        }
                    }
                }
                .opacity(profile.intensity)
                .mask(FloatingIslandOutsideMask(frame: frame, radius: radius, edgeOnly: false).fill(style: FillStyle(eoFill: true)))
                .mask(FloatingIslandOutsideMask(frame: frame, radius: radius, edgeOnly: true).fill(style: FillStyle(eoFill: true)))
                .modifier(PhysicalNotchExclusion(width: model.cameraExclusion, height: model.cameraHeight))
                .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
    }
}

struct AnimatedNotchAmbientLight: View {
    @ObservedObject var model: Model
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var corners: NotchCorners = .legacy
    var compactLightOpacity: CGFloat? = nil
    var behindNotch = false
    var morphTime: TimeInterval? = nil
    private var notchSize: CGSize { CGSize(width: notchWidth, height: notchHeight) }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("rium.light.enabled") private var lightEnabled = true
    @AppStorage("rium.light.style") private var lightStyle = "classic"
    @AppStorage("rium.light.baseColor") private var lightBaseColor = NotchLightColor.defaultRGB
    @AppStorage("rium.light.surfaceStyle") private var surfaceStyle = "neon"
    @AppStorage("rium.light.agent") private var agentLight = true
    @AppStorage("rium.light.dictation") private var dictationLight = true
    @AppStorage("rium.light.music") private var musicLight = true
    @AppStorage("rium.light.musicProgress") private var musicProgressLight = true
    @AppStorage("rium.light.timer") private var timerLight = true
    @AppStorage("rium.light.clipboard") private var clipboardLight = true
    @AppStorage("rium.light.airdrop") private var airDropLight = true
    @AppStorage("rium.light.screenshot") private var screenshotLight = true
    @AppStorage("rium.light.shelf") private var shelfLight = true
    @AppStorage("rium.light.system") private var systemLight = true
    @AppStorage("rium.light.battery") private var batteryLight = true
    @AppStorage("rium.light.calendarAdded") private var calendarLight = true
    @AppStorage("rium.light.reminderAdded") private var reminderLight = true
    @AppStorage("rium.light.thickness") private var thickness = 0.6
    @AppStorage("rium.light.width") private var lightWidth = "extraLarge"

    var body: some View {
        let enabledCues = model.visibleLightCues.filter { cue in
            switch cue.kind {
            case .clipboard, .clipboardPaste: return clipboardLight
            case .airDrop, .airDropSent: return airDropLight
            case .screenshot: return screenshotLight
            case .shelf: return shelfLight
            case .systemNotification, .systemControl, .systemLevel, .brightness, .mute: return systemLight
            case .batterySource, .batteryWarning: return batteryLight
            case .timerActivation, .timerTransition: return timerLight
            case .musicPlayback, .musicTrack, .musicSkip, .musicSkipHunt, .musicSkipArrival: return musicLight
            case .calendarAdded: return calendarLight
            case .reminderAdded: return reminderLight
            case .shortcut(let action): return shortcutLightEnabled(action, shortcuts: shortcutPeeksPreference(UserDefaults.standard.object(forKey: "rium.shortcuts.peeks") as? Bool), clipboard: clipboardLight)
            case .caseKey: return UserDefaults.standard.bool(forKey: "rium.light.caseKeys")
            case .agentRunning, .agentApproval, .agentQuestion, .agentDone, .agentMessage, .agentFailed, .agentInterrupted: return agentLight
            }
        }
        let eventActive = !enabledCues.isEmpty
        let state = combinedAgentLightState(model.externalAgentItems, assistant: model.assistantIndicator, assistantToolRunning: model.assistantToolRunning, assistantSpeaking: model.assistantSpeaking)
        // Keep the compact layer mounted so its opacity can follow the shell.
        let expandedForLight = compactLightOpacity == nil && model.expanded
        let compactLightPaused = compactLightOpacity == 0 && !model.notchGeometryInMotion
        let compactTransition: AnyTransition = compactLightOpacity.map { $0 < 1 ? .identity : .opacity } ?? .opacity
        let mode: AmbientLightMode = lightEnabled ? ambientLightMode(expanded: expandedForLight, agentActive: agentLight && state.active, musicPlaying: musicLight && model.mediaLightPlaying, eventActive: eventActive) : .off
        let agentVariant = agentAmbientVariant(waiting: state.waiting, question: state.question, acting: state.acting)
        let profile = NotchLightProfile(thickness)
        let widthScale = profile.thickness
        let lighting = GeometryReader { geometry in
            // Allow room for the lower question halo and its blur around the contour.
            let glowHeight = min(geometry.size.height, notchHeight + 2 * NotchContainer.lightPadding)
            let armRun = ambientArmRun(preset: lightWidth, screenWidth: geometry.size.width, notch: notchSize.width)
            let tint = NotchLightColor.color(lightBaseColor)
            if mode == .idle || (mode == .music && (compactLightOpacity ?? 1) < 1) {
                contourFrames(every: 1.0 / 20.0) { time in
                    NotchIdleLightFrame(time: time,
                                        thickness: widthScale, armRun: armRun, notchSize: notchSize,
                                        corners: corners, tint: tint, lightStyle: lightStyle)
                }
                .frame(height: glowHeight, alignment: .top)
                .opacity(mode == .music ? 1 - (compactLightOpacity ?? 1) : 1)
                .transition(compactTransition)
            }
            if mode == .agent {
                let waiting = state.waiting
                let usesCustomStyle = usesCustomAgentLight(lightStyle, waiting: waiting)
                let agentArmRun = agentLightArmRun(preset: lightWidth, screenWidth: geometry.size.width,
                    notch: notchSize.width, collapsed: model.collapsedNotchSize.width,
                    expanded: model.expandedNotchSize.width + 72, reachesScreenEdge: !usesCustomStyle)
                let question = state.question
                let acting = state.acting
                // Keep a continuous contour under the animated accent while it resizes.
                NotchIdleLightFrame(time: nil, thickness: widthScale, armRun: agentArmRun,
                                    notchSize: notchSize, corners: corners, tint: waiting ? .orange : tint,
                                    lightStyle: "classic", isAgentUnderlay: true)
                    .frame(height: glowHeight, alignment: .top)
                    .opacity(0.64)
                Group {
                    if usesCustomStyle {
                        NotchStyleAccent(style: lightStyle, tint: tint,
                                         notchSize: notchSize, armRun: agentArmRun, strength: acting ? 1 : 0.78,
                                         thickness: widthScale, corners: corners, morphTime: morphTime)
                            .modifier(ContourSurfaceAdaptation(enabled: model.menuBarIsLight))
                    } else {
                        contourFrames(every: 1.0 / 60.0) { time in
                            NotchAgentLightFrame(tint: waiting ? .orange : tint, time: time, thickness: widthScale, armRun: agentArmRun, acting: acting, thinking: !acting && !waiting, question: question, approval: waiting && !question, notchSize: notchSize, edgeToEdge: lightWidth == "extraLarge", corners: corners, onLightSurface: model.menuBarIsLight)
                        }
                    }
                }
                .frame(height: usesCustomStyle ? geometry.size.height : glowHeight, alignment: .top)
                .id(agentVariant)
                .transition(.opacity)
            } else if mode == .music {
              let musicArm = musicArmRun(preset: lightWidth, screenWidth: geometry.size.width, notch: notchSize.width)
              let frame = NotchMusicLightFrame(tint: model.mediaLightColor, time: nil, thickness: widthScale,
                                               armRun: musicArm, notchSize: notchSize, corners: corners,
                                               onLightSurface: model.menuBarIsLight)
              Group {
                if reduceMotion || compactLightPaused {
                    frame
                } else {
                    AnimatedMusicContour(spectrum: model.musicSpectrum, frame: frame)
                }
              }
              .frame(height: glowHeight, alignment: .top)
              .opacity(compactLightOpacity ?? 1)
              .transition(compactTransition)
            }
        }
        .overlay {
            GeometryReader { geometry in
                if lightEnabled {
                    if musicLight && musicProgressLight && model.showsMusicProgress {
                        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { _ in
                            let elapsed = model.currentMediaElapsed(at: ProcessInfo.processInfo.systemUptime)
                            let fraction = rustMusicProgressFraction(elapsed, model.mediaDuration)
                            if fraction >= 0 {
                                Canvas { context, size in
                                    let path = lightContour(width: notchSize.width, height: notchSize.height, armWidth: 0, corners: corners)
                                        .applying(CGAffineTransform(translationX: (size.width - notchSize.width) / 2, y: 0))
                                    drawMusicProgress(context: &context, path: path, progress: CGFloat(fraction),
                                                      tint: model.mediaLightColor, thickness: widthScale)
                                }
                            }
                        }
                    }
                    if dictationLight && model.dictationDisplayActive {
                        DictationNotchLight(notchSize: notchSize, level: model.dictationLevel,
                                            thickness: widthScale, armRun: ambientArmRun(preset: lightWidth,
                                                screenWidth: geometry.size.width, notch: notchSize.width), corners: corners)
                            .modifier(ContourSurfaceAdaptation(enabled: model.menuBarIsLight))
                    }
                    if timerLight {
                        TimerNotchLight(model: model, thickness: widthScale) { rect in
                            lightContour(width: notchSize.width, height: notchSize.height, armWidth: 0, corners: corners)
                                .applying(CGAffineTransform(translationX: rect.midX - notchSize.width / 2, y: rect.minY))
                        }
                        .modifier(ContourSurfaceAdaptation(enabled: model.menuBarIsLight))
                    }
                    if airDropLight && model.receivingFile {
                        let width = notchSize.width, height = notchSize.height
                        let room = max(0, (geometry.size.width - width) / 2)
                        let arm = interpolatedLightReach(lightWidth, narrow: min(76, room), widest: max(0, room - 20))
                        NotchReceivingLight(notchWidth: width, notchHeight: height, armWidth: arm,
                                            thickness: widthScale, progress: model.receivingFileProgress, started: model.receivingFileStarted,
                                            surfaceStyle: edgeWaveSurfaceStyle(light: model.menuBarIsLight, style: surfaceStyle), corners: corners)
                            .position(x: geometry.size.width / 2, y: (height + NotchContainer.lightPadding) / 2)
                    }
                    ForEach(enabledCues) { cue in
                        let width = notchSize.width
                        let height = notchSize.height
                        let room = max(0, (geometry.size.width - width) / 2)
                        let arm = interpolatedLightReach(lightWidth, narrow: min(76, room), widest: max(0, room - 20))
                        NotchEventLight(cue: cue, notchWidth: width, notchHeight: height, thickness: widthScale,
                                        armWidth: eventArmRun(kind: cue.kind, preset: lightWidth, screenWidth: geometry.size.width,
                                                              notchWidth: width, fallback: arm),
                                        musicTint: model.mediaLightColor, corners: corners, onLightSurface: model.menuBarIsLight)
                            .position(x: geometry.size.width / 2, y: notchEventLightHeight(kind: cue.kind, notchHeight: height) / 2)
                    }
                    let shelfArm = ambientArmRun(preset: lightWidth, screenWidth: geometry.size.width, notch: notchSize.width)
                    if model.fileDragActive && (shelfLight || airDropLight) {
                        ShelfDragHoverLight(notchSize: notchSize, corners: corners, arm: shelfArm, thickness: widthScale)
                    }
                    if let cue = model.shelfCatchCue,
                       shelfCatchLightEnabled(zone: cue.zone, light: lightEnabled, shelf: shelfLight, airDrop: airDropLight) {
                        ShelfCatchLight(cue: cue, notchSize: notchSize, corners: corners, arm: shelfArm, thickness: widthScale)
                    }
                }
            }
        }
        // shortcut: mapping the reference glow transition onto persistent modes needs visual comparison.
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .timingCurve(0.32, 0, 0.23, 1, duration: 0.34), value: mode)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .timingCurve(0.32, 0, 0.23, 1, duration: 0.34), value: agentVariant)
        .opacity(profile.intensity)
        Group {
            if behindNotch {
                lighting
            } else {
                lighting.mask(OutsideNotchMask(notchWidth: notchWidth, notchHeight: notchHeight, corners: corners)
                    .fill(style: FillStyle(eoFill: true)).transaction { $0.animation = nil })
            }
        }
        .modifier(PhysicalNotchExclusion(width: model.cameraExclusion, height: model.cameraHeight))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func contourFrames<Frame: View>(every interval: TimeInterval, paused: Bool = false,
                                            @ViewBuilder frame: @escaping (TimeInterval?) -> Frame) -> some View {
        TimelineView(.animation(minimumInterval: interval, paused: paused || reduceMotion || morphTime != nil)) { _ in
            frame(reduceMotion ? nil : (morphTime ?? ProcessInfo.processInfo.systemUptime))
        }
    }
}

private func dictationAuroraColors(time: TimeInterval, reduceMotion: Bool) -> (background: Gradient, aurora: Gradient, core: Gradient)? {
    func palette(time: TimeInterval, cycles: Double, whiten: Double) -> Gradient? {
        var colors = [Double](repeating: 0, count: 41 * 3)
        guard colors.withUnsafeMutableBufferPointer({ rustDictationAuroraPalette(time, cycles, whiten, reduceMotion ? 1 : 0, $0.baseAddress) }) == 0 else { return nil }
        return Gradient(stops: (0...40).map { index in
            let offset = index * 3
            return .init(color: Color(red: colors[offset], green: colors[offset + 1], blue: colors[offset + 2]), location: CGFloat(index) / 40)
        })
    }

    guard let background = palette(time: time, cycles: 1.6, whiten: 0),
          let aurora = palette(time: time, cycles: 0.9, whiten: 0),
          let core = palette(time: time, cycles: 0.9, whiten: 0.45) else { return nil }
    return (background, aurora, core)
}

private func drawDictationAurora(context: inout GraphicsContext, path: Path, notchWidth: CGFloat,
                                 level: Double, time: TimeInterval, thickness: CGFloat,
                                 colors: (background: Gradient, aurora: Gradient, core: Gradient),
                                 reach: CGFloat = 1, edgeMaskWidth: CGFloat = 0) {
    let sound = level.isFinite ? min(1, max(0, level)) : 0
    let bounds = path.boundingRect
    guard bounds.width > 0 else { return }
    let start = CGPoint(x: bounds.minX, y: 0), end = CGPoint(x: bounds.maxX, y: 0)
    let pulse = 0.5 + 0.5 * sin(time.truncatingRemainder(dividingBy: 10) * (1.4 * .pi))
    // shortcut: the reference's individual masks and highlight placement need frame comparison.
    context.drawLayer { layer in
        var soft = layer; soft.opacity = 0.3 + 0.15 * pulse
        soft.addFilter(.blur(radius: (12 + 4 * sound) * reach))
        soft.stroke(path, with: .linearGradient(colors.background, startPoint: start, endPoint: end),
                    style: StrokeStyle(lineWidth: 5 * thickness, lineCap: .round, lineJoin: .round))
        var haze = layer; haze.opacity = 0.45 + 0.30 * sound
        haze.addFilter(.blur(radius: (12 + 4 * sound) * reach))
        haze.stroke(path, with: .linearGradient(colors.aurora, startPoint: start, endPoint: end),
                    style: StrokeStyle(lineWidth: (8 + 7 * sound) * thickness, lineCap: .round, lineJoin: .round))
        var bright = layer; bright.opacity = 0.45 + 0.25 * sound
        bright.stroke(path, with: .linearGradient(colors.core, startPoint: start, endPoint: end),
                      style: StrokeStyle(lineWidth: (1.8 + 1.4 * sound) * thickness + edgeMaskWidth, lineCap: .round, lineJoin: .round))
        layer.drawLayer { highlight in
            var glow = highlight; glow.opacity = 0.45 + 0.30 * sound
            glow.stroke(path, with: .linearGradient(colors.core, startPoint: start, endPoint: end),
                        style: StrokeStyle(lineWidth: (1.8 + 1.4 * sound) * thickness + edgeMaskWidth, lineCap: .round, lineJoin: .round))
            highlight.blendMode = .destinationIn
            highlight.fill(Path(bounds.insetBy(dx: -60, dy: -60)), with: .radialGradient(
                Gradient(colors: [.white, .white.opacity(0.08)]),
                center: CGPoint(x: bounds.midX, y: bounds.midY),
                startRadius: 0, endRadius: max(1, notchWidth * 0.38)))
        }
        let fade = min(0.25, 20 / bounds.width)
        layer.blendMode = .destinationIn
        layer.fill(Path(bounds.insetBy(dx: -60, dy: -60)), with: .linearGradient(
            Gradient(stops: [.init(color: .clear, location: 0), .init(color: .white, location: fade),
                             .init(color: .white, location: 1 - fade), .init(color: .clear, location: 1)]),
            startPoint: start, endPoint: end))
    }
}

private struct DictationNotchLight: View {
    let notchSize: CGSize
    let level: Double
    let thickness: CGFloat
    let armRun: CGFloat
    let corners: NotchCorners
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let time = reduceMotion ? 0.6 : timeline.date.timeIntervalSinceReferenceDate
            if let colors = dictationAuroraColors(time: time, reduceMotion: reduceMotion) {
                Canvas { context, size in
                    let path = lightContour(width: notchSize.width, height: notchSize.height, armWidth: armRun, corners: corners)
                        .applying(CGAffineTransform(translationX: (size.width - notchSize.width - 2 * armRun) / 2, y: 0))
                    drawDictationAurora(context: &context, path: path, notchWidth: notchSize.width,
                                        level: level, time: time, thickness: thickness, colors: colors)
                }
            }
        }
    }
}

// shortcut: the original contour geometry and brightness need frame comparison.
private struct TimerNotchGauge: Shape {
    var fraction: CGFloat
    let contour: (CGRect) -> Path
    var animatableData: CGFloat {
        get { fraction }
        set { fraction = newValue }
    }
    func path(in rect: CGRect) -> Path {
        let progress = min(1, max(0, fraction))
        guard progress > 0 else { return Path() }
        return contour(rect).trimmedPath(from: 0.5 - progress / 2, to: 0.5 + progress / 2)
    }
}

// shortcut: the reference's fluid-edge glow envelope still needs visual comparison.
private struct TimerContourCrests: View, Animatable {
    var fraction: CGFloat
    let color: Color
    let thickness: CGFloat
    let contour: (CGRect) -> Path
    var animatableData: CGFloat {
        get { fraction }
        set { fraction = newValue }
    }
    var body: some View {
        Canvas { context, size in
            let path = contour(CGRect(origin: .zero, size: size))
            var values = [Double](repeating: 0, count: 3)
            let status = values.withUnsafeMutableBufferPointer {
                rustTimerContourCrests(Double(fraction), Double(approximateContourLength(path)), $0.baseAddress)
            }
            if status == 0 && fraction > 0 {
                for center in values.prefix(2) {
                    drawAmbientCrest(context: &context, path: path, center: CGFloat(center), spread: CGFloat(values[2]),
                                     color: color, line: 3.8 * thickness, blur: 2.4, opacity: 0.15)
                }
            }
        }
    }
}

// shortcut: the reference's expanded timer layering still needs visual comparison.
struct TimerNotchLight: View {
    @ObservedObject var model: Model
    let thickness: CGFloat
    var edgeMaskWidth: CGFloat = 0
    let contour: (CGRect) -> Path
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        if model.showsTimerAlarmLight {
            let color = (model.timerAlarmPhase ?? model.timerPhase).lightColor
            TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1.0 / 30.0)) { _ in
                let now = ProcessInfo.processInfo.systemUptime
                let fraction = CGFloat(model.timerAlarmProgress(at: now))
                let pulse = rustTimerPulse(now, reduceMotion ? 1 : 0)
                ZStack {
                    TimerNotchGauge(fraction: fraction, contour: contour)
                        .stroke(color.opacity(pulse), style: StrokeStyle(lineWidth: 2 * thickness + edgeMaskWidth, lineCap: .round))
                        .shadow(color: color.opacity(pulse * 0.6), radius: 5)
                    if !reduceMotion && fraction > 0 {
                        TimerContourCrests(fraction: fraction, color: color, thickness: thickness, contour: contour)
                    }
                }
            }
        } else if [1, 2].contains(model.timerState), let duration = model.timerDuration {
            let fraction = timerFraction(model.timerRemaining, duration)
            if fraction >= 0 {
                ZStack {
                    TimerNotchGauge(fraction: CGFloat(fraction), contour: contour)
                        .stroke(model.timerPhase.lightColor.opacity(model.timerState == 2 ? 0.24 : 0.45),
                                style: StrokeStyle(lineWidth: 1.5 * thickness + edgeMaskWidth, lineCap: .round))
                    if model.timerState == 1 && !reduceMotion {
                        TimerContourCrests(fraction: CGFloat(fraction),
                                           color: model.timerPhase.lightColor, thickness: thickness, contour: contour)
                    }
                }
                .animation(reduceMotion ? nil : .linear(duration: 0.8), value: fraction)
            }
        }
    }
}

// The contour stays put while neighboring sections brighten independently.
struct NotchLightBrightness {
    private static let rhythms: [(period: Double, phase: Double)] = [
        (11, 0.7), (7, 2.4), (13, 0.1), (9, 3.8), (12, 1.6)
    ]
    private let values: [Double]

    init(time: TimeInterval?, variation: Double) {
        values = Self.rhythms.map { rhythm in
            guard let time else { return 1 }
            let phase = time.truncatingRemainder(dividingBy: rhythm.period) / rhythm.period
            return 1 - variation * (0.5 + 0.5 * sin(2 * .pi * phase + rhythm.phase))
        }
    }

    func at(_ position: CGFloat) -> Double {
        let sample = min(1, max(0, position)) * CGFloat(values.count - 1)
        let index = Int(sample)
        return values[index] + (values[min(index + 1, values.count - 1)] - values[index]) * Double(sample - CGFloat(index))
    }

    func gradient(_ tint: Color, opacity: Double, fadesAtEnds: Bool = true) -> Gradient {
        let inset = fadesAtEnds ? 0.15 : 0
        let stops: [Gradient.Stop] = values.enumerated().map { index, value in
            .init(color: tint.opacity(opacity * value),
                  location: CGFloat(inset + (1 - 2 * inset) * Double(index) / Double(values.count - 1)))
        }
        return Gradient(stops: fadesAtEnds ? [.init(color: .clear, location: 0)] + stops + [.init(color: .clear, location: 1)] : stops)
    }
}

func idleLightSpan(screenWidth: CGFloat, notchWidth: CGFloat, armRun: CGFloat) -> CGFloat {
    guard screenWidth.isFinite, notchWidth.isFinite, armRun.isFinite, screenWidth > 0 else { return 0 }
    return min(screenWidth, max(0, notchWidth) + max(0, armRun) * 2)
}

struct NotchIdleLightFrame: View {
    let time: TimeInterval?
    let thickness: CGFloat
    let armRun: CGFloat
    let notchSize: CGSize
    var corners: NotchCorners = .legacy
    let tint: Color
    let lightStyle: String
    var isAgentUnderlay = false

    var body: some View {
        // A vector stroke can advance with the shell without waiting for a Canvas frame.
        GeometryReader { geometry in
            var frame = [Double](repeating: 1, count: 3)
            let result = frame.withUnsafeMutableBufferPointer {
                rustNotchIdleLight(time ?? 0, time == nil ? 1 : 0, $0.baseAddress)
            }
            let size = geometry.size
            let span = idleLightSpan(screenWidth: size.width, notchWidth: notchSize.width, armRun: armRun)
            if result == 0 && span > 0 {
                let contour = ambientContour(width: size.width, notchSize: notchSize, corners: corners)
                let left = (size.width - span) / 2
                let start = UnitPoint(x: left / size.width, y: 0)
                let end = UnitPoint(x: (left + span) / size.width, y: 0)
                let brightness = NotchLightBrightness(time: time, variation: 0.31)
                // Leave a visible edge after the opaque shell covers the inside half of the stroke.
                let core = isAgentUnderlay ? (opacity: 0.21, width: 2.6 * thickness)
                    : (opacity: 0.38, width: 0.9 + 2 * thickness)
                ZStack {
                    if usesCustomAgentLight(lightStyle, waiting: false) {
                        Canvas { context, size in
                            drawNotchStyle(lightStyle, in: &context, size: size, notchSize: notchSize, armRun: armRun,
                                           tint: tint, time: time ?? 0, strength: 0.22,
                                           thickness: thickness, corners: corners)
                        }
                    }
                    contour.stroke(LinearGradient(gradient: brightness.gradient(tint, opacity: 0.19 * frame[1]),
                                                   startPoint: start, endPoint: end),
                                   style: StrokeStyle(lineWidth: 4.5 * thickness, lineCap: .round, lineJoin: .round))
                        .blur(radius: 4.5)
                    contour.stroke(LinearGradient(gradient: brightness.gradient(tint, opacity: core.opacity * frame[0]),
                                                   startPoint: start, endPoint: end),
                                   style: StrokeStyle(lineWidth: core.width, lineCap: .round, lineJoin: .round))
                        .blur(radius: 0.6)
                }
            }
        }
    }
}

struct NotchAgentLightFrame: View {
    let tint: Color
    let time: TimeInterval?
    let thickness: CGFloat
    let armRun: CGFloat
    let acting: Bool
    let thinking: Bool
    var question = false
    var approval = false
    var notchSize: CGSize? = nil
    var edgeToEdge = false
    var corners: NotchCorners = .legacy
    var onLightSurface = false
    var body: some View {
        Canvas { context, size in
            let whole = ambientContour(width: size.width, notchSize: notchSize, corners: corners)
            let notch = notchSize?.width ?? notchWidth(expanded: false, displayWidth: size.width)
            let span = edgeToEdge ? size.width : min(size.width, notch + armRun * 2)
            let left = (size.width - span) / 2
            let brightness = NotchLightBrightness(time: time, variation: acting ? 0.23 : (thinking ? 0.16 : 0.18))
            func questionPalette(whiten: Double) -> [Color] {
                guard question else { return [] }
                var values = [Double](repeating: 0, count: 41 * 3)
                let result = values.withUnsafeMutableBufferPointer { rustNotchQuestionPalette(0, 1, whiten, $0.baseAddress) }
                guard result == 0 else { return [] }
                return (0..<41).map { Color(red: values[$0 * 3], green: values[$0 * 3 + 1], blue: values[$0 * 3 + 2]) }
            }
            let questionColors = questionPalette(whiten: 0)
            let questionHighlightColors = questionPalette(whiten: 0.25)
            let organicColors: [Color] = {
                guard approval else { return [] }
                var values = [Double](repeating: 0, count: 41 * 3)
                let result = values.withUnsafeMutableBufferPointer {
                    rustAgentOrganicPalette(0, approval ? 1 : 0, 1, 0, $0.baseAddress)
                }
                guard result == 0 else { return [] }
                return (0..<41).map { Color(red: values[$0 * 3], green: values[$0 * 3 + 1], blue: values[$0 * 3 + 2]) }
            }()
            func questionGradient(_ colors: [Color], opacity: Double, fadeEnds: Bool) -> Gradient {
                Gradient(stops: colors.enumerated().map { index, color in
                    let location = Double(index) / 40
                    let fade = fadeEnds ? min(1, location / 0.16, (1 - location) / 0.16) : 1
                    return .init(color: color.opacity(opacity * fade * brightness.at(CGFloat(location))), location: CGFloat(location))
                })
            }
            var questionPulse = 0.0
            if question {
                var frame = [Double](repeating: 0, count: 3)
                let status = frame.withUnsafeMutableBufferPointer {
                    rustNotchQuestionLight(time ?? 0, Double(notch), time == nil ? 1 : 0, $0.baseAddress)
                }
                if status == 0 {
                    questionPulse = frame[0]
                    let width = CGFloat(frame[1]), height = CGFloat(frame[2])
                    let center = CGPoint(x: size.width / 2, y: (notchSize?.height ?? notchHeight(expanded: false, section: .home)) + 6)
                    let ellipse = CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
                    // shortcut: question-halo blending needs reference-frame comparison.
                    var halo = context; halo.addFilter(.blur(radius: 13))
                    let opacity = 0.52
                    if questionColors.isEmpty {
                        halo.fill(Path(ellipseIn: ellipse), with: .color(tint.opacity(opacity)))
                    } else {
                        halo.fill(Path(ellipseIn: ellipse), with: .linearGradient(questionGradient(questionColors, opacity: opacity, fadeEnds: false),
                            startPoint: CGPoint(x: ellipse.minX, y: center.y), endPoint: CGPoint(x: ellipse.maxX, y: center.y)))
                    }
                }
            }
            var motion = [Double](repeating: 0, count: 4)
            let motionStatus = motion.withUnsafeMutableBufferPointer {
                rustNotchAgentLight(time ?? 0, time == nil ? 1 : 0, $0.baseAddress)
            }
            if motionStatus != 0 { motion = [1, 1, 0.5, 0] }
            func shading(_ opacity: Double) -> GraphicsContext.Shading {
                if !questionColors.isEmpty {
                    return .linearGradient(questionGradient(questionColors, opacity: opacity, fadeEnds: !edgeToEdge),
                        startPoint: CGPoint(x: left, y: 0), endPoint: CGPoint(x: left + span, y: 0))
                }
                if !organicColors.isEmpty {
                    // shortcut: edge fade and SwiftUI colour-space blending still need screen comparison.
                    return .linearGradient(questionGradient(organicColors, opacity: opacity, fadeEnds: !edgeToEdge),
                        startPoint: CGPoint(x: left, y: 0), endPoint: CGPoint(x: left + span, y: 0))
                }
                return .linearGradient(brightness.gradient(tint, opacity: opacity, fadesAtEnds: !edgeToEdge),
                    startPoint: CGPoint(x: left, y: 0), endPoint: CGPoint(x: left + span, y: 0))
            }
            if question {
                var haze = context; haze.addFilter(.blur(radius: 5))
                haze.stroke(whole, with: shading(0.44), style: StrokeStyle(lineWidth: CGFloat(5 + 2 * questionPulse) * thickness, lineCap: .round, lineJoin: .round))
                let height = notchSize?.height ?? notchHeight(expanded: false, section: .home)
                let arm = max(0, (span - notch) / 2)
                let contour = lightContour(width: notch, height: height, armWidth: arm, corners: corners)
                    .applying(CGAffineTransform(translationX: left, y: 0))
                if let lower = notchLowerArcAndSide(width: notch, height: height, corners: corners) {
                    var range = [Double](repeating: 0, count: 2)
                    let status = range.withUnsafeMutableBufferPointer {
                        rustNotchQuestionHighlight(Double(arm), Double(notchShoulderArcLength(width: notch, height: height, corners: corners)),
                            Double(lower.side), Double(lower.arc), Double(approximateContourLength(contour)), $0.baseAddress)
                    }
                    if status == 0 {
                        let lowerContour = contour.trimmedPath(from: CGFloat(range[0]), to: CGFloat(range[1]))
                        var bloom = context; bloom.addFilter(.blur(radius: 6))
                        bloom.stroke(lowerContour, with: shading(0.48),
                                     style: StrokeStyle(lineWidth: CGFloat(8 + 3 * questionPulse) * thickness, lineCap: .round, lineJoin: .round))
                        var highlight = context; highlight.addFilter(.blur(radius: 0.8))
                        let colors = questionHighlightColors.isEmpty ? questionColors : questionHighlightColors
                        let ink: GraphicsContext.Shading = colors.isEmpty ? .color(tint.opacity(0.62))
                            : .linearGradient(questionGradient(colors, opacity: 0.62, fadeEnds: !edgeToEdge),
                                startPoint: CGPoint(x: left, y: 0), endPoint: CGPoint(x: left + span, y: 0))
                        highlight.stroke(lowerContour, with: ink,
                                         style: StrokeStyle(lineWidth: 2 * thickness, lineCap: .round, lineJoin: .round))
                    }
                }
            } else {
                let ink = shading(1)
                var haze = context
                haze.opacity *= 0.30 * motion[1]
                haze.addFilter(.blur(radius: 7))
                haze.stroke(whole, with: ink, style: StrokeStyle(lineWidth: 8 * thickness, lineCap: .round, lineJoin: .round))
                var glow = context
                glow.opacity *= 0.64 * motion[0]
                glow.addFilter(.blur(radius: 2.6))
                glow.stroke(whole, with: ink, style: StrokeStyle(lineWidth: 4 * thickness, lineCap: .round, lineJoin: .round))
                var core = context
                core.opacity *= min(0.85, 0.85 * motion[0])
                core.addFilter(.blur(radius: 0.65))
                core.stroke(whole, with: ink, style: StrokeStyle(lineWidth: 2.2 * thickness, lineCap: .round, lineJoin: .round))
            }

        }
        .modifier(ContourSurfaceAdaptation(enabled: onLightSurface))
    }
}

private enum LightSurfaceShader {
    static let density: Float = 2.2
    static let saturation: Double = 1.45

    static let contour: Shader? = {
        guard let url = Bundle.main.url(forResource: "LightSurface", withExtension: "metallib") else { return nil }
        let function = ShaderFunction(library: ShaderLibrary(url: url), name: "riumLightOnLight")
        return function.dynamicallyCall(withArguments: [.float(density), .float(Float(saturation)), .float(0.85), .float(1)])
    }()
}

private struct AnimatedMusicContour: View {
    @ObservedObject var spectrum: SystemAudioSpectrum
    var frame: NotchMusicLightFrame

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { _ in
            currentFrame()
        }
    }

    private func currentFrame() -> NotchMusicLightFrame {
        var result = frame
        result.time = ProcessInfo.processInfo.systemUptime
        result.spectrumIntensity = spectrum.intensityTransition
        return result
    }
}

struct NotchMusicLightFrame: View {
    let tint: NSColor
    var time: TimeInterval?
    var thickness: CGFloat = 1
    var armRun: CGFloat = 220
    var notchSize: CGSize? = nil
    var spectrumIntensity: SpectrumIntensityTransition? = nil
    var corners: NotchCorners = .legacy
    var onLightSurface = false

    var body: some View {
        Canvas { context, size in
            let crestTint = Color(nsColor: musicCrestColor(tint))
            let whole = ambientContour(width: size.width, notchSize: notchSize, corners: corners)
            let breath = time.map { 0.5 + 0.5 * sin($0 * 2 * .pi / 3.4) } ?? 0.5
            let glowWidth = musicGlowWidth(notch: notchSize?.width ?? notchWidth(expanded: false, displayWidth: size.width), arm: armRun, screen: size.width)
            let left = (size.width - glowWidth) / 2
            let start = CGPoint(x: left, y: 0), end = CGPoint(x: left + glowWidth, y: 0)
            context.drawLayer { layer in
                var base = layer
                base.addFilter(.blur(radius: 8))
                base.stroke(whole, with: .color(crestTint.opacity(0.10 + breath * 0.06)), style: StrokeStyle(lineWidth: 11 * thickness, lineCap: .round, lineJoin: .round))
                var edge = layer
                edge.addFilter(.blur(radius: 1.4))
                edge.stroke(whole, with: .color(crestTint.opacity(0.16 + breath * 0.10)), style: StrokeStyle(lineWidth: 2.2 * thickness, lineCap: .round, lineJoin: .round))
                if let time = time {
                    let intensity = musicRippleIntensity(at: time, spectrum: spectrumIntensity)
                    for offset in [0.0, 0.5] {
                        let phase = musicRipplePhase(time: time, offset: offset)
                        let opacity = (1 - phase * 0.7) * intensity * 0.34
                        // MusicWaveGlow.ripple offsets paired crests by phase × 0.48.
                        for center in [0.5 - phase * 0.48, 0.5 + phase * 0.48] {
                            let crest = musicCrestPositions(center)
                            let gradient = Gradient(stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .clear, location: crest.left),
                                .init(color: crestTint.opacity(opacity), location: crest.peak),
                                .init(color: .clear, location: crest.right),
                                .init(color: .clear, location: 1)
                            ])
                            let shading = GraphicsContext.Shading.linearGradient(gradient, startPoint: start, endPoint: end)
                            var glow = layer
                            glow.addFilter(.blur(radius: 3))
                            glow.stroke(whole, with: shading, style: StrokeStyle(lineWidth: 6 * thickness, lineCap: .round, lineJoin: .round))
                        }
                    }
                }
                let fade = musicContourFadeFraction(glowWidth)
                let mask = Gradient(stops: [.init(color: .clear, location: 0), .init(color: .white, location: fade),
                                            .init(color: .white, location: 1 - fade), .init(color: .clear, location: 1)])
                layer.blendMode = .destinationIn
                layer.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(mask, startPoint: start, endPoint: end))
            }
        }
        .modifier(ContourSurfaceAdaptation(enabled: onLightSurface))
    }
}

private struct ContourSurfaceAdaptation: ViewModifier {
    private static let densityMatrix: ColorMatrix = {
        var matrix = ColorMatrix()
        matrix.a4 = LightSurfaceShader.density
        return matrix
    }()
    let enabled: Bool
    @AppStorage("rium.light.surfaceStyle") private var surfaceStyle = "neon"
    @ViewBuilder func body(content: Content) -> some View {
        if enabled {
            Group {
                if let shader = LightSurfaceShader.contour {
                    content.padding(60).compositingGroup().colorEffect(shader).padding(-60)
                } else {
                    // shortcut: the matrix preserves density, with selective color correction requiring the Metal shader.
                    content.hidden().overlay {
                        GeometryReader { geometry in
                            let size = geometry.size
                            Canvas { context, _ in
                                guard let light = context.resolveSymbol(id: 0) else { return }
                                context.addFilter(.colorMatrix(Self.densityMatrix))
                                context.draw(light, at: .zero, anchor: .topLeading)
                            } symbols: {
                                content.frame(width: size.width, height: size.height)
                                    .padding(60).saturation(LightSurfaceShader.saturation).tag(0)
                            }
                            .frame(width: size.width + 120, height: size.height + 120)
                            .position(x: size.width / 2, y: size.height / 2)
                        }
                    }
                }
            }
            .shadow(color: .black.opacity(surfaceStyle == "velours" ? 0.24 : 0), radius: 14)
        } else {
            content
        }
    }
}

func ambientContour(width screenWidth: CGFloat, notchSize: CGSize? = nil, corners: NotchCorners = .legacy) -> Path {
    let screen = max(0, screenWidth)
    let width = min(screen, max(0, notchSize?.width ?? notchWidth(expanded: false, displayWidth: screen)))
    let height = max(0, notchSize?.height ?? notchHeight(expanded: false, section: .home))
    let left = (screen - width) / 2
    var path = Path()
    path.move(to: CGPoint(x: 0, y: 0))
    path.addLine(to: CGPoint(x: left, y: 0))
    appendNotchContour(to: &path, in: CGRect(x: left, y: 0, width: width, height: height), corners: corners)
    path.addLine(to: CGPoint(x: screen, y: 0))
    return path
}

// The reference binary describes an open contour, with extended upper arms
// and rounded lower corners. This shape follows the app's current silhouette.
func lightContour(width: CGFloat, height: CGFloat, armWidth: CGFloat = NotchContainer.lightPadding, corners: NotchCorners = .legacy) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: 0, y: 0))
    path.addLine(to: CGPoint(x: armWidth, y: 0))
    appendNotchContour(to: &path, in: CGRect(x: armWidth, y: 0, width: width, height: height), corners: corners)
    path.addLine(to: CGPoint(x: width + armWidth * 2, y: 0))
    return path
}
