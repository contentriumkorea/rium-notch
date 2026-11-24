import SwiftUI
import AppKit
import AVFoundation
import Speech
import ApplicationServices

enum SettingsPage: String, CaseIterable, Identifiable {
    case general, appearance, tabs, sounds, notifications, shortcuts, integrations, dictation, voice, interview, permissions, privacy, diagnostics
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: return "일반"
        case .appearance: return "모양"
        case .tabs: return "탭 관리"
        case .sounds: return "사운드"
        case .notifications: return "알림"
        case .shortcuts: return "단축키"
        case .integrations: return "연동"
        case .dictation: return "받아쓰기"
        case .voice: return "음성"
        case .interview: return "면접 코파일럿"
        case .permissions: return "권한"
        case .privacy: return "개인정보"
        case .diagnostics: return "진단"
        }
    }
    var icon: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .appearance: return "rectangle.split.2x1"
        case .tabs: return "rectangle.split.3x1"
        case .sounds: return "speaker.wave.2"
        case .notifications: return "bell"
        case .shortcuts: return "keyboard"
        case .integrations: return "link"
        case .dictation: return "waveform"
        case .voice: return "waveform.circle"
        case .interview: return "person.2.wave.2"
        case .permissions: return "checkmark.shield"
        case .privacy: return "lock.shield"
        case .diagnostics: return "waveform.path.ecg.rectangle"
        }
    }
    var subtitle: String {
        switch self {
        case .general: return "리움 노치의 기본 동작을 설정합니다."
        case .appearance: return "노치의 모습과 빛을 원하는 대로 설정합니다."
        case .tabs: return "펼친 노치에 표시할 탭을 고릅니다."
        case .sounds: return "작업과 알림의 소리를 설정합니다."
        case .notifications: return "중요한 순간을 알려줍니다."
        case .shortcuts: return "자주 쓰는 동작을 빠르게 실행합니다."
        case .integrations: return "음악과 다른 기능을 연결합니다."
        case .dictation: return "말한 내용을 텍스트로 입력합니다."
        case .voice: return "에이전트의 승인 요청에 음성으로 답합니다."
        case .interview: return "면접 음성 인식과 답변 제공자를 설정합니다."
        case .permissions: return "기능에 필요한 접근 권한을 확인합니다."
        case .privacy: return "데이터 사용 방식을 확인합니다."
        case .diagnostics: return "앱의 현재 상태를 확인합니다."
        }
    }
}

private final class SettingsNavigation: ObservableObject {
    @Published var page: SettingsPage = .general
    @Published var appearance: AppearancePage = .cards
}

private enum AppearancePage: String, CaseIterable, Identifiable {
    case cards, agents, light, effects
    var id: String { rawValue }
    var title: String { switch self { case .cards: return "카드"; case .agents: return "에이전트"; case .light: return "빛"; case .effects: return "효과" } }
    var icon: String { switch self { case .cards: return "square.on.square"; case .agents: return "face.smiling"; case .light: return "sparkles"; case .effects: return "wand.and.stars" } }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.system(size: 17, weight: .semibold))
            content
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.125, green: 0.14, blue: 0.17), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous).stroke(.white.opacity(0.11), lineWidth: 1))
    }
}

private struct SettingsSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label.accessibilityHidden(true)
            Spacer(minLength: 16)
            Toggle(isOn: configuration.$isOn) { configuration.label }.labelsHidden().toggleStyle(.switch)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: Model
    @ObservedObject private var updater: UpdateController
    @ObservedObject private var dictation: DictationController
    @ObservedObject private var musicSpectrum: SystemAudioSpectrum
    @ObservedObject private var navigation: SettingsNavigation
    var page: SettingsPage { navigation.page }
    private var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "알 수 없음" }
    @AppStorage(agentSwitcherShortcutPreference) private var agentSwitcherShortcutEnabled = false
    @AppStorage("rium.card.style") private var cardStyle = "liquid"
    @AppStorage("rium.light.style") private var lightStyle = "classic"
    @AppStorage("rium.light.baseColor") private var lightBaseColor = NotchLightColor.defaultRGB
    @AppStorage("rium.light.surfaceStyle") private var lightSurfaceStyle = "neon"
    @AppStorage("rium.light.enabled") private var lightEnabled = true
    @AppStorage("rium.light.agent") private var agentLight = true
    @AppStorage("rium.light.agentScreenWave") private var agentScreenWave = true
    @AppStorage("rium.light.agentWaveMode") private var agentWaveMode = "balanced"
    @AppStorage("rium.light.waveStyle") private var waveStyle = "notch"
    private var waveColors = ScreenWaveColors()
    private var idleBrightness = IdleLightSettings()
    @AppStorage("rium.light.dictation") private var dictationLight = true
    @AppStorage("rium.light.music") private var musicLight = true
    @AppStorage("rium.light.musicProgress") private var musicProgressLight = true
    @AppStorage("rium.light.timer") private var timerLight = true
    @AppStorage("rium.light.clipboard") private var clipboardLight = true
    @AppStorage("rium.light.airdrop") private var airDropLight = true
    @AppStorage("rium.light.edgeWave") private var edgeWaveEnabled = true
    @AppStorage("rium.light.screenshot") private var screenshotLight = true
    @AppStorage("rium.light.shelf") private var shelfLight = true
    @AppStorage("rium.light.system") private var systemLight = true
    @AppStorage("rium.light.battery") private var batteryLight = true
    @AppStorage("rium.light.calendarAdded") private var calendarLight = true
    @AppStorage("rium.light.reminderAdded") private var reminderLight = true
    @AppStorage("rium.light.rays") private var raysLight = false
    @AppStorage("rium.light.thickness") private var lightThickness = 0.6
    @AppStorage("rium.light.width") private var lightWidth = "extraLarge"
    @AppStorage("rium.sound.enabled") private var soundsEnabled = true
    @AppStorage("rium.sound.agent") private var agentSounds = false
    @AppStorage("rium.sound.agentMode") private var agentSoundMode = "balanced"
    @AppStorage("rium.sound.dictation") private var dictationSounds = false
    @AppStorage("rium.sound.timer") private var timerSounds = true
    @AppStorage("rium.agent.notifyAttention") private var agentNotifyAttention = true
    @AppStorage("rium.agent.notifyFailure") private var agentNotifyFailure = true
    @AppStorage("rium.agent.notificationDetails") private var agentNotificationDetails = false
    @AppStorage("rium.systemNotifications.details") private var systemNotificationDetails = true
    // shortcut: Korean keywords extend the original English and French defaults.
    @AppStorage("rium.voice.allowWords") private var voiceAllowWords = "네, 응, 허용, 좋아, ok, go, valide, approuve, accepte, oui, yes"
    @AppStorage("rium.voice.denyWords") private var voiceDenyWords = "아니요, 아니, 거절, 취소, stop, non, refuse, annule, no, skip"
    @AppStorage("rium.voice.openWords") private var voiceOpenWords = "열어, 열기, ouvre, open, montre, affiche, app"
    @AppStorage("rium.voice.enabled") private var voiceEnabled = false
    @AppStorage("rium.dictation.previewText") private var dictationPreviewText = false
    @AppStorage("rium.interview.provider") private var interviewProvider = "groq"
    @AppStorage("rium.interview.model") private var interviewModel = ""
    @AppStorage("rium.interview.autoSuggest") private var interviewAutoSuggest = false
    @State private var interviewKey = ""
    @State private var deepgramKey = ""
    @State private var interviewKeyStatus = ""
    @State private var deepgramKeyStatus = ""

    init(model: Model, initialPage: String? = nil) {
        self.model = model; self.dictation = model.dictation; self.updater = model.updater; self.musicSpectrum = model.musicSpectrum
        let navigation = SettingsNavigation()
        if let initialPage = initialPage, let selected = SettingsPage(rawValue: initialPage) { navigation.page = selected }
        if CommandLine.arguments.contains("--self-test-render-settings"),
           let tab = ProcessInfo.processInfo.environment["RIUM_APPEARANCE_TEST_PAGE"],
           let selected = AppearancePage(rawValue: tab) { navigation.appearance = selected }
        self.navigation = navigation
    }

    func navigate(to page: SettingsPage) {
        navigation.page = page
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            sidebar
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(page.title).font(.system(size: 30, weight: .bold, design: .rounded))
                            Text(page.subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: page.icon).font(.system(size: 22, weight: .medium)).accessibilityHidden(true)
                    }.padding(.bottom, 4)
                    pageContent
                }
                .padding(28).frame(maxWidth: .infinity, alignment: .leading)
            }
            .id(page)
            .background(Color(red: 0.105, green: 0.115, blue: 0.135), in: RoundedRectangle(cornerRadius: 25, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 25, style: .continuous).stroke(.white.opacity(0.10), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
            .padding(.top, 42).padding(.trailing, 16).padding(.bottom, 16)
        }
        .frame(width: 1080, height: 780)
        .background(Color(red: 0.066, green: 0.075, blue: 0.09))
        .toggleStyle(SettingsSwitchStyle())
        .preferredColorScheme(.dark)
        .onChange(of: lightEnabled) { _ in
            model.syncMusicSpectrum()
            (NSApp.delegate as? AppDelegate)?.configureShortcutMonitor()
        }
        .onChange(of: clipboardLight) { _ in (NSApp.delegate as? AppDelegate)?.configureShortcutMonitor() }
        .onChange(of: musicLight) { _ in model.syncMusicSpectrum() }
        .onChange(of: interviewProvider) { _ in interviewKey = ""; interviewKeyStatus = "" }
        .onChange(of: interviewAutoSuggest) { enabled in model.interview.setAutoSuggestEnabled(enabled) }
        .onChange(of: page) { _ in interviewKey = ""; deepgramKey = "" }
        .onDisappear { interviewKey = ""; deepgramKey = "" }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let icon = NSImage(contentsOf: url) {
                    Image(nsImage: icon).resizable().interpolation(.high).frame(width: 47, height: 47).accessibilityHidden(true)
                }
                Text("Rium Notch").font(.system(size: 21, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.8)
            }.padding(.horizontal, 18).padding(.top, 48).padding(.bottom, 19)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    sidebarHeading("설정")
                    ForEach([SettingsPage.general, .appearance, .tabs, .sounds, .notifications, .shortcuts]) { sidebarButton($0) }
                    sidebarHeading("도구")
                    ForEach([SettingsPage.integrations, .dictation, .voice, .interview]) { sidebarButton($0) }
                    sidebarHeading("Rium Notch")
                    ForEach([SettingsPage.permissions, .privacy, .diagnostics]) { sidebarButton($0) }
                }
            }
            Text("Rium Notch \(appVersion)").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.bottom, 18)
        }
        .frame(width: 218, height: 780, alignment: .topLeading)
    }
    private func sidebarHeading(_ title: String) -> some View {
        Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 5)
    }
    private func sidebarButton(_ item: SettingsPage) -> some View {
        Button { navigate(to: item) } label: {
            HStack(spacing: 12) {
                Image(systemName: item.icon).font(.system(size: 15, weight: .medium)).frame(width: 19)
                Text(item.title).font(.system(size: 14, weight: page == item ? .semibold : .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(page == item ? Color(red: 0.42, green: 0.70, blue: 1) : .white)
            .padding(.horizontal, 12).frame(height: 28)
            .background(page == item ? Color.blue.opacity(0.27) : .clear, in: RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).padding(.horizontal, 9).accessibilityAddTraits(page == item ? .isSelected : [])
    }

    func tabVisibility(_ tab: NotchTab) -> Binding<Bool> {
        Binding(get: { model.tabOrder.contains(tab) }, set: { shown in
            if shown { model.addTab(tab) }
            else { model.removeTab(tab) }
        })
    }

    private var tabManagementContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard(title: "표시 순서") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.tabOrder) { tab in
                            Label(tab.title, systemImage: tab.icon)
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(.white.opacity(0.08), in: Capsule())
                                .fixedSize()
                        }
                    }
                }
                Text("순서는 노치의 ‘탭 편집’에서 바꿀 수 있습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
                ForEach(NotchTab.allCases.filter { $0 != .home }) { tab in
                    Toggle(isOn: tabVisibility(tab)) {
                        Label(tab.title, systemImage: tab.icon)
                            .font(.system(size: 13, weight: .medium))
                    }
                    .accessibilityLabel("\(tab.title) 탭 표시")
                    .padding(14)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    @ViewBuilder private var pageContent: some View {
        switch page {
        case .general:
            SettingsCard(title: "업데이트") {
                HStack(spacing: 14) {
                    Image(systemName: "arrow.down.circle").font(.system(size: 20))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Rium Notch").fontWeight(.semibold)
                        Text(appVersion).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("업데이트") { updater.check() }
                        .disabled(!updater.canCheck)
                }
                Text(updater.status).font(.caption).foregroundStyle(.secondary)
                Toggle("GitHub 릴리스 자동 확인", isOn: Binding(get: { updater.autoCheck }, set: { updater.setAutoCheck($0) }))
            }
            SettingsCard(title: "창 모양") {
                HStack(spacing: 14) {
                    Image(systemName: "circle.lefthalf.filled").font(.system(size: 20))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("테마").fontWeight(.semibold)
                        Text("설정 창에 적용됩니다.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("어둡게").foregroundStyle(.secondary)
                }
            }
            SettingsCard(title: "기본값") {
                HStack(spacing: 14) {
                    Image(systemName: "globe").font(.system(size: 20))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("언어").fontWeight(.semibold)
                        Text("현재 설정 화면은 한국어로 표시됩니다.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("한국어").foregroundStyle(.secondary)
                }
            }
            SettingsCard(title: "기본 동작") {
                Toggle("로그인할 때 Rium Notch 실행", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                Picker("노치를 표시할 화면", selection: Binding(get: { model.preferredDisplayKey }, set: { model.setPreferredDisplay($0) })) {
                    Text("기본 화면").tag(nil as String?)
                    ForEach(model.availableDisplays) { display in Text(display.name).tag(Optional(display.key)) }
                    if let key = model.preferredDisplayKey, !model.availableDisplays.contains(where: { $0.key == key }) {
                        Text("연결되지 않은 화면").tag(Optional(key))
                    }
                }
                if !model.settingsMessage.isEmpty { Text(model.settingsMessage).font(.caption).foregroundStyle(.secondary) }
            }
            SettingsCard(title: "노치 동작") {
                Toggle("포인터를 올리면 노치 열기", isOn: Binding(get: { model.hoverEnabled }, set: { model.setHoverEnabled($0) }))
                Toggle("포인터가 벗어나면 자동 닫기", isOn: Binding(get: { model.autoHideEnabled }, set: { model.setAutoHideEnabled($0) }))
                HStack {
                    Text("자동 닫기 지연")
                    Slider(value: Binding(get: { model.autoHideDelay }, set: { model.setAutoHideDelay($0) }), in: 0.1...3, step: 0.1).accessibilityLabel("자동 닫기 지연")
                    Text(String(format: "%.1f초", model.autoHideDelay)).monospacedDigit().frame(width: 48, alignment: .trailing)
                }.disabled(!model.autoHideEnabled)
            }
            SettingsCard(title: "원형 시스템 모니터") {
                Toggle("노치에 모니터 표시", isOn: Binding(get: { model.usageTrackingEnabled }, set: { model.setUsageTrackingEnabled($0) }))
                if model.usageTrackingEnabled {
                    Picker("Codex 잔여량 계정", selection: Binding(get: { model.monitorAccountID }, set: { model.setMonitorAccount($0) })) {
                        Text("선택 안 함").tag(nil as String?)
                        ForEach(model.accounts) { account in Text(account.name).tag(Optional(account.id)) }
                        if let id = model.monitorAccountID, !model.accounts.contains(where: { $0.id == id }) {
                            Text("연결되지 않은 계정").tag(Optional(id))
                        }
                    }
                    HStack {
                        Button("ChatGPT 계정 추가…") { model.addAccount() }
                        if let account = model.accounts.first(where: { $0.id == model.monitorAccountID }) {
                            if !account.connected {
                                Button("선택한 계정으로 로그인") { model.login(account.id) }
                            }
                            Button("선택한 계정 연결 해제…", role: .destructive) { model.removeAccount(account) }
                        }
                    }
                    if !model.message.isEmpty { Text(model.message).font(.caption).foregroundStyle(.secondary) }
                    Text("위쪽 호는 RAM 여유와 메모리 압력, 아래쪽 점은 CPU 여유, 가운데 숫자는 선택한 계정의 기본 한도 잔여율입니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        case .appearance:
            appearanceContent
        case .tabs:
            tabManagementContent
        case .notifications:
            SettingsCard(title: "다른 앱의 알림") {
                Toggle("새 알림을 노치에 표시", isOn: Binding(get: { model.systemNotificationEnabled }, set: { model.setSystemNotificationEnabled($0) }))
                Toggle("알림 내용 표시", isOn: $systemNotificationDetails).disabled(!model.systemNotificationEnabled)
                Text("알림은 이 Mac에서만 읽으며, 화면 미러링이나 다른 앱의 마이크·카메라 사용이 감지되면 내용을 숨깁니다. 전체 디스크 접근 권한이 필요할 수 있습니다.")
                    .font(.caption).foregroundStyle(.secondary)
                Text(model.systemNotificationStatus).font(.caption).foregroundStyle(.secondary)
            }
            SettingsCard(title: "날씨") {
                Toggle("강수 예보를 노치에 표시", isOn: Binding(get: { model.weatherAlertsEnabled }, set: { model.setWeatherAlertsEnabled($0) }))
                Text("선택한 도시의 시간당 예상 강수량을 이용합니다. 분 단위 예보나 실제 시작 시각은 아닙니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            SettingsCard(title: "에이전트 알림") {
                Toggle("시스템 알림 표시", isOn: Binding(get: { model.agentNotificationsEnabled }, set: { model.setAgentNotificationsEnabled($0) }))
                Toggle("확인이 필요한 요청", isOn: $agentNotifyAttention).disabled(!model.agentNotificationsEnabled)
                Toggle("오류 및 응답 지연", isOn: $agentNotifyFailure).disabled(!model.agentNotificationsEnabled)
                Toggle("알림에 프로젝트 이름 표시", isOn: $agentNotificationDetails).disabled(!model.agentNotificationsEnabled)
                Text("질문과 요청의 내용은 알림에 표시하지 않습니다. 감지된 화면 미러링이나 다른 앱의 마이크·카메라 사용 중에는 프로젝트 이름을 숨깁니다.")
                    .font(.caption).foregroundStyle(.secondary)
                if !model.agentNotificationStatus.isEmpty { Text(model.agentNotificationStatus).font(.caption).foregroundStyle(.secondary) }
            }
            SettingsCard(title: "집중 타이머") {
                ForEach(PomodoroSetting.allCases, id: \.rawValue) { setting in
                    Stepper(value: Binding(get: { model.pomodoroValue(setting) }, set: { model.setPomodoroValue(setting, $0) }), in: setting.range) {
                        HStack { Text(setting.label); Spacer(); Text("\(model.pomodoroValue(setting))\(setting.unit)").monospacedDigit() }
                    }.accessibilityLabel(setting.label)
                }
                Text("변경한 시간은 다음 단계부터 적용됩니다.").font(.caption).foregroundStyle(.secondary)
                Toggle("완료 시 시스템 알림", isOn: Binding(get: { model.timerNotificationsEnabled }, set: { model.setTimerNotificationsEnabled($0) }))
                Text("앱이 닫혀 있어도 완료 알림을 예약합니다. 알림 방식은 macOS 설정을 따릅니다.").font(.caption).foregroundStyle(.secondary)
                if !model.timerNotificationStatus.isEmpty { Text(model.timerNotificationStatus).font(.caption).foregroundStyle(.secondary) }
            }
        case .shortcuts:
            SettingsCard(title: "작업 전환") {
                Toggle("Control + Option + 스페이스바", isOn: $agentSwitcherShortcutEnabled)
                    .onChange(of: agentSwitcherShortcutEnabled) { _, _ in
                        (NSApp.delegate as? AppDelegate)?.configureShortcutMonitor()
                    }
                Text("다른 앱을 사용 중일 때 노치의 작업 목록을 엽니다. 전역 단축키에는 macOS 권한이 필요합니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            SettingsCard(title: "Command 단축키 미리 보기") {
                Toggle("단축키 미리 보기", isOn: Binding(get: { model.shortcutPeeksEnabled }, set: { model.setShortcutPeeksEnabled($0) }))
                Text("Command 키와 X, Z, S, R, P, A, Q 또는 V 키를 함께 누르거나 Command 키, Shift 키와 숫자 3 또는 4 키로 화면을 캡처하면 아이콘과 빛을 표시합니다. 손쉬운 사용 권한이 필요합니다.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(ShortcutAction.configurable, id: \.rawValue) { action in
                    Toggle("\(action.keyLabel)  \(action.title)", isOn: Binding(
                        get: { shortcutActionEnabled(action) },
                        set: { enabled in
                            guard let key = action.preferenceKey else { return }
                            UserDefaults.standard.set(enabled, forKey: key)
                            model.objectWillChange.send()
                        }
                    )).disabled(!model.shortcutPeeksEnabled)
                }
            }
            SettingsCard(title: "받아쓰기 단축키") {
                DictationShortcutPicker(controller: dictation)
                Text("키 조합을 누르는 동안 받아씁니다. Escape 키로 취소하면 인식된 문구는 복사할 수 있습니다.").font(.caption).foregroundStyle(.secondary)
            }
        case .integrations:
            SettingsCard(title: "스크린샷 보관 줄") {
                Toggle("스크린샷과 AirDrop 파일 표시", isOn: Binding(get: { model.cordEnabled }, set: { model.setCordEnabled($0) }))
                Text("스크린샷과 AirDrop 수신 감시가 켜져 있으면 새 파일을 화면 가장자리에 표시합니다. 파일을 끌어서 사용하거나 보관 줄에서 제거할 수 있습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            SettingsCard(title: "Codex") {
                Text("기존 Codex 세션의 상태를 표시하고, 확인된 대화에 후속 메시지를 보냅니다.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                HStack {
                    Button(model.agentIntegrationBusy ? "연결 중…" : "상태 감지만 설정") { model.installAgentIntegration() }
                    Button("노치 승인 설정") { model.installAgentIntegration(activePermission: true) }
                    Button("훅 해제") { model.removeAgentIntegration() }
                }.disabled(model.agentIntegrationBusy)
                Text("Codex 훅 기능이 켜져 있어야 하며 새 세션부터 적용됩니다. 기존 훅은 유지합니다. 상태 감지만 선택하면 노치 승인은 꺼집니다.")
                    .font(.caption).foregroundStyle(.secondary)
                if !model.agentIntegrationStatus.isEmpty { Text(model.agentIntegrationStatus).font(.caption).foregroundStyle(.secondary) }
            }
            SettingsCard(title: "Codex Desktop") {
                Text("Codex Desktop의 승인 요청과 질문을 노치에서 확인합니다.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                HStack {
                    Button("연동 설정") { model.setDesktopIntegrationEnabled(true) }
                    Button("연동 해제") { model.setDesktopIntegrationEnabled(false) }
                    Button("상태 확인") { model.refreshDesktopIntegration() }
                }.disabled(model.desktopIntegrationBusy)
                Text("설정은 새로 실행한 Codex부터 적용됩니다. 현재 실행 중인 Codex는 자동으로 종료하지 않습니다.")
                    .font(.caption).foregroundStyle(.secondary)
                Text(model.desktopIntegrationStatus).font(.caption).foregroundStyle(.secondary)
            }.onAppear { model.refreshDesktopIntegration() }
            SettingsCard(title: "Claude Code") {
                Text("도구 실행과 확인이 필요한 요청을 감지하고 선택적으로 노치에서 승인합니다.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                HStack {
                    Button(model.claudeIntegrationBusy ? "연결 중…" : "상태 감지만 설정") { model.installClaudeIntegration() }
                    Button("노치 승인 설정") { model.installClaudeIntegration(activePermission: true) }
                    Button("훅 해제") { model.removeClaudeIntegration() }
                }.disabled(model.claudeIntegrationBusy)
                Text("기존 훅을 유지하며 새 세션부터 적용됩니다. 상태 감지만 선택하면 노치 승인은 꺼집니다. 시간 초과 또는 연결 실패 시 Claude에서 직접 승인합니다.")
                    .font(.caption).foregroundStyle(.secondary)
                if !model.claudeIntegrationStatus.isEmpty { Text(model.claudeIntegrationStatus).font(.caption).foregroundStyle(.secondary) }
            }
            SettingsCard(title: "음악") {
                Toggle("동기화 가사", isOn: Binding(get: { model.lyricsEnabled }, set: { model.setLyricsEnabled($0) }))
                Text("가사를 켜면 곡 제목과 아티스트, 재생 시간이 LRCLIB에 전송됩니다.").font(.caption).foregroundStyle(.secondary)
            }
        case .dictation:
            SettingsCard(title: "받아쓰기") {
                Toggle("앱 실행 시 받아쓰기 준비", isOn: Binding(get: { dictation.autoStart }, set: { dictation.setAutoStart($0) }))
                Picker("언어", selection: Binding(get: { dictation.languageID }, set: { dictation.setLanguage($0) })) {
                    ForEach(DictationController.languageIDs, id: \.self) { id in Text(DictationController.languageName(id)).tag(id) }
                }
                Toggle("노치에 받아쓴 문구 표시", isOn: $dictationPreviewText)
                Toggle("Fn 키와 스페이스 바로 핸즈프리 받아쓰기", isOn: Binding(get: { dictation.handsFreeEnabled }, set: { dictation.setHandsFreeEnabled($0) }))
                    .disabled(dictation.shortcut != .fn)
                Text("Fn(지구본) 키를 누른 채 스페이스 바를 눌러 시작하고, 같은 조합을 한 번 더 눌러 완료합니다.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("감지된 통화나 미러링 중에는 문구를 숨깁니다. 화면 녹화와 공유를 모두 감지할 수는 없습니다.")
                    .font(.caption).foregroundStyle(.secondary)
                Button(dictation.enabled ? "받아쓰기 끄기" : "받아쓰기 준비") {
                    dictation.enabled ? dictation.disable() : dictation.prepare()
                }
                Text(dictation.status).font(.caption).foregroundStyle(.secondary)
            }
        case .interview:
            SettingsCard(title: "답변 제공자") {
                Toggle("상대 발화에 답변 자동 제안", isOn: $interviewAutoSuggest)
                Text("켜면 상대의 발화가 끝날 때 최근 전사 최대 12개가 선택한 제공자로 자동 전송됩니다.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("제공자", selection: $interviewProvider) {
                    ForEach(InterviewProvider.allCases) { provider in Text(provider.title).tag(provider.rawValue) }
                }
                TextField("모델 ID", text: $interviewModel)
                    .textFieldStyle(.roundedBorder).accessibilityLabel("면접 답변 모델 ID")
                SecureField("API 키", text: $interviewKey)
                    .textFieldStyle(.roundedBorder).accessibilityLabel("면접 답변 제공자 API 키")
                HStack {
                    Button("키 저장") {
                        guard InterviewProvider(rawValue: interviewProvider) != nil else { interviewKeyStatus = "제공자를 선택해 주세요."; return }
                        let result = InterviewCredentialStore.save(interviewKey, account: interviewProvider)
                        if result == 0 { interviewKey = ""; interviewKeyStatus = "키를 키체인에 저장했습니다." }
                        else { interviewKeyStatus = "키를 저장하지 못했습니다. 입력과 키체인 상태를 확인해 주세요." }
                    }.disabled(interviewKey.isEmpty)
                    Button("저장된 키 삭제") {
                        guard InterviewProvider(rawValue: interviewProvider) != nil else { return }
                        let result = InterviewCredentialStore.remove(account: interviewProvider)
                        interviewKeyStatus = result == 0 ? "저장된 키를 삭제했습니다." : "키를 삭제하지 못했습니다."
                    }
                }
                Text("키는 이 Mac의 키체인에 저장됩니다. 답변을 요청하면 최근 전사가 선택한 제공자로 전송됩니다.")
                    .font(.caption).foregroundStyle(.secondary)
                if !interviewKeyStatus.isEmpty { Text(interviewKeyStatus).font(.caption).foregroundStyle(.secondary) }
            }
            SettingsCard(title: "상대 음성") {
                SecureField("Deepgram API 키", text: $deepgramKey)
                    .textFieldStyle(.roundedBorder).accessibilityLabel("Deepgram API 키")
                HStack {
                    Button("키 저장") {
                        let result = InterviewCredentialStore.save(deepgramKey, account: "deepgram")
                        if result == 0 { deepgramKey = ""; deepgramKeyStatus = "키를 키체인에 저장했습니다." }
                        else { deepgramKeyStatus = "키를 저장하지 못했습니다. 입력과 키체인 상태를 확인해 주세요." }
                    }.disabled(deepgramKey.isEmpty)
                    Button("저장된 키 삭제") {
                        let result = InterviewCredentialStore.remove(account: "deepgram")
                        deepgramKeyStatus = result == 0 ? "저장된 키를 삭제했습니다." : "키를 삭제하지 못했습니다."
                    }
                }
                Text("면접 화면에서 Deepgram을 선택하고 시스템 오디오 인식을 시작하면 소리가 Deepgram으로 전송됩니다. 기본값은 기기 내 인식입니다.")
                    .font(.caption).foregroundStyle(.secondary)
                if !deepgramKeyStatus.isEmpty { Text(deepgramKeyStatus).font(.caption).foregroundStyle(.secondary) }
            }
        case .permissions:
            SettingsCard(title: "접근 권한") {
                TimelineView(.periodic(from: .now, by: 3)) { _ in
                    VStack(spacing: 12) {
                        permissionRow("손쉬운 사용", status: dictation.access.accessibility ? "허용됨" : "허용 필요",
                                      button: dictation.access.accessibility ? "설정 열기" : "권한 요청") {
                            dictation.openAccessibilitySettings()
                        }
                        dictationPermissionRow("마이크", status: microphonePermissionStatus(dictation.access.microphone), permission: .microphone)
                        dictationPermissionRow("음성 인식", status: speechPermissionStatus(dictation.access.speech), permission: .speech)
                        permissionRow("입력 모니터링", status: dictation.access.inputMonitoring ? "앱에서 확인됨" : "시스템 설정에서 확인",
                                      anchor: "Privacy_ListenEvent")
                        permissionRow("파일 및 폴더", status: "시스템 설정에서 확인", anchor: "Privacy_FilesAndFolders")
                        permissionRow("전체 디스크 접근", status: "시스템 설정에서 확인", anchor: "Privacy_AllFiles")
                    }
                }
            }
            SettingsCard(title: "받아쓰기 상태") {
                Text(dictation.access.missingMessage() ?? dictation.status)
                    .font(.caption).foregroundStyle(.secondary)
                if !dictation.access.accessibility {
                    Text("다른 앱에서 Fn(지구본) 키로 받아쓰려면 ‘손쉬운 사용’에서 Rium Notch를 허용하세요.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !dictation.enabled {
                    Button("받아쓰기 준비") { dictation.prepare() }
                }
            }
        case .privacy:
            SettingsCard(title: "데이터") {
                Text("클립보드 기록을 켜면 항목이 이 Mac에 저장됩니다. 날씨와 가사 조회는 해당 제공처를 사용합니다.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
        case .diagnostics:
            SettingsCard(title: "상태") {
                Text("받아쓰기: \(dictation.status)")
                Text(model.weatherDetail).foregroundStyle(.secondary)
            }
        case .sounds:
            SettingsCard(title: "사운드 피드백") {
                Toggle("사운드 피드백", isOn: $soundsEnabled)
                    .onChange(of: soundsEnabled) { _, _ in model.refreshTimerNotificationSound() }
                Toggle("에이전트 상태 알림음", isOn: $agentSounds).disabled(!soundsEnabled)
                Picker("에이전트 소리 빈도", selection: $agentSoundMode) {
                    Text("균형").tag("balanced"); Text("모든 변화").tag("every")
                }.pickerStyle(.segmented).disabled(!soundsEnabled || !agentSounds)
                Text("균형 모드는 가까운 시점의 소리를 합칩니다.").font(.caption).foregroundStyle(.secondary)
                Toggle("받아쓰기 시작 및 종료음", isOn: $dictationSounds).disabled(!soundsEnabled)
                Toggle("타이머 알림음", isOn: $timerSounds).disabled(!soundsEnabled)
                    .onChange(of: timerSounds) { _, _ in model.refreshTimerNotificationSound() }
                Text("앱 실행 중 다른 앱이 카메라·마이크를 사용하거나 화면을 미러링하면 감지된 알림음을 끕니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .voice:
            SettingsCard(title: "음성 답변") {
                Text("에이전트의 권한 요청에 답할 단어를 설정합니다.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                TextField("허용", text: $voiceAllowWords)
                TextField("거절", text: $voiceDenyWords)
                TextField("앱 열기", text: $voiceOpenWords)
                Text("단어는 쉼표로 구분합니다. 설정한 구문 전체를 말하면 해당 요청에 적용합니다.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("기본 단어로 되돌리기") {
                    voiceAllowWords = "네, 응, 허용, 좋아, ok, go, valide, approuve, accepte, oui, yes"
                    voiceDenyWords = "아니요, 아니, 거절, 취소, stop, non, refuse, annule, no, skip"
                    voiceOpenWords = "열어, 열기, ouvre, open, montre, affiche, app"
                }
                Toggle("음성 답변 사용", isOn: $voiceEnabled)
                    .onChange(of: voiceEnabled) { _, enabled in
                        if enabled { model.voiceApproval.preparePermissions() } else { model.voiceApproval.cancel() }
                    }
                Text("접힌 노치에 승인 미리보기가 보일 때만 듣습니다. 노치를 펼치면 버튼으로 답변합니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var appearanceContent: some View {
        HStack(spacing: 2) {
            ForEach(AppearancePage.allCases) { item in
                Button { navigation.appearance = item } label: {
                    Label(item.title, systemImage: item.icon).frame(maxWidth: .infinity).frame(height: 38)
                        .background(navigation.appearance == item ? Color.white.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 11))
                }.buttonStyle(.plain).accessibilityAddTraits(navigation.appearance == item ? .isSelected : [])
            }
        }.padding(4).background(.black.opacity(0.28), in: Capsule())
        switch navigation.appearance {
        case .cards:
            VStack(alignment: .leading, spacing: 7) {
                Text("노치 배치").font(.system(size: 20, weight: .semibold))
                Text("화면에서 노치가 표시되는 방식을 확인합니다.").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 12) {
                notchPlacementPreview(title: "일반 노치", detail: "화면 상단에 붙어 표시됩니다.", floating: false)
                notchPlacementPreview(title: "다이나믹 아일랜드", detail: "떠 있는 노치를 이동할 수 있습니다.", floating: true)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("내 스타일 찾기").font(.system(size: 20, weight: .semibold))
                Text("카드의 질감과 모양을 선택합니다.").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                cardStylePreview("글래스", value: "classic")
                cardStylePreview("리퀴드 글래스", value: "liquid")
                cardStylePreview("피지컬", value: "physical")
                cardStylePreview("대시보드", value: "dashboard")
            }
        case .agents:
            SettingsCard(title: "에이전트") {
                Text("작업 상태를 노치와 홈 카드에 표시합니다.").foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    RiumCharacter(motion: [1, 0, 0], headAngle: 0, face: 0, eyeScale: 1, lamp: 0.62, scaleX: 1, scaleY: 1)
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Rium").font(.system(size: 14, weight: .semibold))
                        Text("작업 상태에 반응하는 리움 캐릭터입니다.").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 14))
            }
        case .light:
            VStack(alignment: .leading, spacing: 7) {
                Text("나만의 빛").font(.system(size: 20, weight: .semibold))
                Text("평소와 에이전트 작업 중에 표시할 노치 조명을 선택합니다.").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            lightDimensions
            ColorPicker("기본 조명 색상", selection: Binding(
                get: { NotchLightColor.color(lightBaseColor) },
                set: { if let rgb = NotchLightColor.rgb($0) { lightBaseColor = rgb } }
            ), supportsOpacity: false)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                lightPreview("클래식", value: "classic")
                lightPreview("픽셀", value: "pixel")
            }
            lightControls
        case .effects:
            lightDimensions
            lightControls
        }
    }
    private func notchPlacementPreview(title: String, detail: String, floating: Bool) -> some View {
        let selected = (model.floatingIslandPlacement != nil) == floating
        return Button {
          (NSApp.delegate as? AppDelegate)?.setFloatingIslandEnabled(floating)
        } label: {
          VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 13).fill(LinearGradient(colors: [Color(red: 0.27, green: 0.35, blue: 0.51), Color(red: 0.08, green: 0.13, blue: 0.24)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Rectangle().fill(.white.opacity(0.12)).frame(height: 26)
                if floating {
                    GeometryReader { geometry in
                        let surface = CGRect(origin: .zero, size: geometry.size)
                        let bounds = FloatingIslandPositionBounds(screen: surface, menuHeight: 26, virtualNotch: false)
                        let island = FloatingIslandScreenGeometry(bounds: bounds, anchor: CGPoint(x: geometry.size.width / 2, y: 6),
                            size: CGSize(width: 64, height: 17), expanded: false, camera: nil, radius: 28)
                        FloatingIslandSurface(geometry: island, surfaceFrame: surface) { Color.clear }
                    }
                }
                else { RoundedRectangle(cornerRadius: 6).fill(.black).frame(width: 92, height: 24).offset(y: -2) }
            }.frame(height: 76).clipped().clipShape(RoundedRectangle(cornerRadius: 13))
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.caption.weight(.semibold))
                    Text(detail).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? Color.blue : Color.secondary)
            }
          }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.125, green: 0.14, blue: 0.17), in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).stroke(selected ? Color.blue : .white.opacity(0.12), lineWidth: selected ? 1.5 : 1))
            .accessibilityElement(children: .combine)
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func cardStylePreview(_ title: String, value: String) -> some View {
        let selected = cardStyle == value
        return Button { cardStyle = value } label: {
            VStack(alignment: .leading, spacing: 8) {
                CardStyleIllustration(style: title).frame(height: 70)
                HStack {
                    Text(title).font(.caption.weight(.semibold)); Spacer()
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue).accessibilityHidden(true) }
                }
            }.padding(6).frame(maxWidth: .infinity)
                .background(Color(red: 0.125, green: 0.14, blue: 0.17), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? Color.blue : .white.opacity(0.12), lineWidth: selected ? 1.5 : 1))
        }.buttonStyle(.plain).accessibilityLabel(title)
            .accessibilityValue(selected ? "선택됨" : "선택 안 됨")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func lightPreview(_ title: String, value: String) -> some View {
        let selected = lightStyle == value
        return Button { lightStyle = value } label: {
            VStack(alignment: .leading, spacing: 8) {
                NotchStyleSample(style: value, widthPreset: lightWidth, lightThickness: lightThickness, tint: NotchLightColor.color(lightBaseColor),
                                 displayWidth: model.displayWidth, liveNotchWidth: model.collapsedNotchSize.width,
                                 floating: model.floatingIslandPlacement != nil)
                    .frame(maxWidth: .infinity).frame(height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                HStack {
                    Text(title).font(.caption.weight(.semibold)); Spacer()
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue).accessibilityHidden(true) }
                }
            }.padding(6)
                .background(Color(red: 0.125, green: 0.14, blue: 0.17), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? Color.blue : .white.opacity(0.12), lineWidth: selected ? 1.5 : 1))
        }.buttonStyle(.plain).accessibilityLabel(title)
            .accessibilityValue(selected ? "선택됨" : "선택 안 됨")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
    private var lightDimensions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("빛 너비", selection: $lightWidth) {
                Text("좁게").tag("narrow"); Text("보통").tag("medium"); Text("넓게").tag("wide"); Text("아주 넓게").tag("extraLarge")
            }.pickerStyle(.segmented)
            HStack {
                Text("빛 두께")
                Slider(value: $lightThickness, in: 0.5...2, step: 0.05).accessibilityLabel("빛 두께")
                Text("\(Int((lightThickness * 100).rounded()))%").monospacedDigit().frame(width: 55, alignment: .trailing)
            }
        }.disabled(!lightEnabled)
    }
    private var lightControls: some View {
            SettingsCard(title: "노치 조명") {
                Toggle("노치 조명", isOn: $lightEnabled)
                Group {
                    HStack {
                        Text("대기 조명 밝기")
                        Slider(value: Binding(get: { idleBrightness.percent }, set: { idleBrightness.percent = $0 }),
                               in: 0...100, step: 1)
                            .accessibilityLabel("대기 조명 밝기")
                        Text(idleBrightness.percent.formatted(.percent.scale(1).precision(.fractionLength(0))))
                            .monospacedDigit().frame(width: 55, alignment: .trailing)
                    }
                    Text("100%는 AI 작업 중 밝기와 같습니다.")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("화면 파동 방식", selection: $waveStyle) {
                        Text("노치에서 퍼짐").tag("notch")
                        Text("화면 테두리 한 바퀴").tag("perimeter")
                    }.pickerStyle(.segmented).disabled(!lightEnabled)
                    Picker("화면 파동 색상", selection: waveColors.$mode) {
                        Text("자동").tag(ScreenWaveColorMode.automatic)
                        Text("노치 기본색").tag(ScreenWaveColorMode.notch)
                        Text("직접 선택").tag(ScreenWaveColorMode.custom)
                    }
                    if waveColors.mode == .custom {
                        ColorPicker("파동 색상 선택", selection: Binding(
                            get: { NotchLightColor.color(waveColors.customRGB) },
                            set: { if let rgb = NotchLightColor.rgb($0) { waveColors.customRGB = rgb } }
                        ), supportsOpacity: false)
                    }
                    Toggle("에이전트 상태 조명", isOn: $agentLight)
                    Toggle("에이전트 상태 변화 시 화면 파동", isOn: $agentScreenWave).disabled(!agentLight)
                    Picker("에이전트 화면 파동 빈도", selection: $agentWaveMode) {
                        Text("균형").tag("balanced")
                        Text("모든 변화").tag("every")
                    }.pickerStyle(.segmented).disabled(!agentLight || !agentScreenWave)
                    Text(waveStyle == "perimeter"
                         ? "에이전트, 복사와 AirDrop 등의 화면 파동이 화면 가장자리를 따라 한 바퀴 돕니다."
                         : lightStyle == "classic"
                         ? "클래식에서는 에이전트가 작업을 마칠 때 화면에 빛이 퍼집니다."
                         : "에이전트가 시작하거나 확인을 요청하거나 작업을 마칠 때 빛이 퍼집니다.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("가까운 시각의 변화는 합쳐질 수 있으며 저전력 모드에서는 표시하지 않습니다.")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("받아쓰기 중 빛 표시", isOn: $dictationLight)
                    Toggle("음악 재생 중 빛 물결 표시", isOn: $musicLight)
                    Toggle("실제 소리에 반응", isOn: Binding(get: { musicSpectrum.enabled }, set: { musicSpectrum.setEnabled($0); model.syncMusicSpectrum() }))
                        .disabled(!lightEnabled || !musicLight)
                    Text(musicSpectrum.status.isEmpty ? "시스템 오디오 수준을 사용합니다. 녹음 파일을 저장하지 않습니다." : musicSpectrum.status)
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("미디어 재생 진행에 따라 노치 테두리 채우기", isOn: $musicProgressLight)
                    Toggle("타이머 빛 게이지", isOn: $timerLight)
                    Toggle("복사 및 붙여넣기 빛 표시", isOn: $clipboardLight)
                    Toggle("AirDrop 송수신 시 빛 표시", isOn: $airDropLight)
                    Toggle("AirDrop·복사·붙여넣기 화면 파동", isOn: $edgeWaveEnabled).disabled(!airDropLight && !clipboardLight)
                    Picker("밝은 메뉴 막대 화면 파동", selection: $lightSurfaceStyle) {
                        Text("네온").tag("neon")
                        Text("벨벳").tag("velours")
                    }.pickerStyle(.segmented)
                    Toggle("스크린샷을 찍을 때 빛 표시", isOn: $screenshotLight)
                    Toggle("보관함에 담을 때 빛 표시", isOn: $shelfLight)
                    Toggle("음량·밝기 변경 시 빛 표시", isOn: $systemLight)
                    Toggle("Caps Lock 및 Shift 키 표시", isOn: Binding(get: { model.caseKeysEnabled }, set: { model.setCaseKeysEnabled($0) }))
                    Text("Caps Lock 변경과 Shift 키를 단독으로 길게 누를 때 표시합니다. 손쉬운 사용 권한이 필요합니다.")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("전원과 배터리 경고 빛 표시", isOn: $batteryLight)
                    Toggle("일정 추가 시 빛 표시", isOn: $calendarLight)
                    Toggle("Google Tasks 추가 시 빛 표시", isOn: $reminderLight)
                    Toggle("이벤트 조명에 광선과 입자 추가", isOn: $raysLight).disabled(lightStyle == "classic")
                }.disabled(!lightEnabled)
                Text("모션 줄이기를 켜면 움직임을 줄입니다.").font(.caption).foregroundStyle(.secondary)
            }
    }
    private func dictationPermissionRow(_ title: String, status: String, permission: DictationPermissionPrompt) -> some View {
        permissionRow(title, status: status, button: permission.needsRequest(dictation.access) ? "권한 요청" : "설정 열기") {
            dictation.handlePermissionButton(permission)
        }
    }

    private func permissionRow(_ title: String, status: String, anchor: String) -> some View {
        permissionRow(title, status: status, button: "설정 열기") { openPrivacy(anchor) }
    }

    private func permissionRow(_ title: String, status: String, button: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer(minLength: 8)
            Text(status).font(.caption).foregroundStyle(.secondary)
            Button(button, action: action)
                .accessibilityLabel("\(title) \(button)")
        }
    }

    private func openPrivacy(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") { NSWorkspace.shared.open(url) }
    }
}

private func microphonePermissionStatus(_ status: AVAuthorizationStatus) -> String {
    switch status {
    case .authorized: return "허용됨"
    case .notDetermined: return "요청 전"
    case .denied: return "허용 안 됨"
    case .restricted: return "시스템에서 제한됨"
    @unknown default: return "확인할 수 없음"
    }
}

private func speechPermissionStatus(_ status: SFSpeechRecognizerAuthorizationStatus) -> String {
    switch status {
    case .authorized: return "허용됨"
    case .notDetermined: return "요청 전"
    case .denied: return "허용 안 됨"
    case .restricted: return "시스템에서 제한됨"
    @unknown default: return "확인할 수 없음"
    }
}

// Drawn locally for the settings screen; the original app's preview assets
// are not bundled; these illustrations are the selection controls' previews.
private struct CardStyleIllustration: View {
    let style: String
    private var dashboard: Bool { style == "대시보드" }
    private var physical: Bool { style == "피지컬" }
    private var glass: Bool { style == "리퀴드 글래스" }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color.black)
                if glass {
                    RadialGradient(colors: [Color.pink.opacity(0.35), .clear], center: UnitPoint(x: 0.25, y: 0.8), startRadius: 0, endRadius: geometry.size.width * 0.45)
                    RadialGradient(colors: [Color.orange.opacity(0.22), .clear], center: UnitPoint(x: 0.75, y: 0.85), startRadius: 0, endRadius: geometry.size.width * 0.38)
                }
                if dashboard {
                    HStack(spacing: 3) {
                        dashboardCard { HStack(spacing: 4) { artwork.frame(width: 23, height: 23); miniLines } }
                        dashboardCard { Image(systemName: "gauge.medium").font(.system(size: 14)); Text("19°").font(.system(size: 9, weight: .bold)) }
                        dashboardCard { RoundedRectangle(cornerRadius: 1).fill(Color.yellow.opacity(0.8)).frame(width: 16, height: 22).rotationEffect(.degrees(-4)) }
                    }.padding(5)
                } else {
                    HStack(spacing: 3) {
                        miniPanel {
                            HStack(spacing: 5) {
                                artwork.frame(width: 24, height: 24)
                                VStack(alignment: .leading, spacing: 3) {
                                    miniLines
                                    Capsule().fill(.pink.opacity(0.7)).frame(width: 22, height: 2)
                                    HStack(spacing: 5) { Image(systemName: "backward.fill"); Image(systemName: "play.fill"); Image(systemName: "forward.fill") }.font(.system(size: 5))
                                }
                            }
                        }
                        miniPanel {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("가사").font(.system(size: 6, weight: .medium)).foregroundStyle(.secondary)
                                Spacer(minLength: 0)
                                HStack(spacing: 2) { ForEach(0..<5) { _ in Capsule().fill(.pink.opacity(0.7)).frame(width: 2, height: 7) } }
                                Spacer(minLength: 0)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.padding(5)
                    if physical {
                        Canvas { context, size in
                            var grid = Path()
                            stride(from: CGFloat(0), through: size.width, by: 3).forEach { x in grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height)) }
                            stride(from: CGFloat(0), through: size.height, by: 3).forEach { y in grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y)) }
                            context.stroke(grid, with: .color(.black.opacity(0.42)), lineWidth: 0.5)
                        }.allowsHitTesting(false)
                    }
                }
            }.clipShape(RoundedRectangle(cornerRadius: 12))
        }.accessibilityHidden(true)
    }
    private var artwork: some View {
        RoundedRectangle(cornerRadius: 4).fill(LinearGradient(colors: [.pink, .purple, .yellow.opacity(0.9), .mint], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
    private var miniLines: some View {
        VStack(alignment: .leading, spacing: 3) {
            Capsule().fill(.white.opacity(0.8)).frame(width: 24, height: 3)
            Capsule().fill(.white.opacity(0.35)).frame(width: 18, height: 2)
        }
    }
    private func miniPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content().padding(5).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(.white.opacity(glass ? 0.06 : 0.035), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(glass ? 0.18 : 0.08), lineWidth: 0.6))
    }
    private func dashboardCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content().frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LinearGradient(colors: [.white.opacity(0.27), .white.opacity(0.13)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.15), lineWidth: 0.5))
    }
}
