import SwiftUI
import AppKit

private enum SettingsPage: String, CaseIterable, Identifiable {
    case general, appearance, sounds, notifications, shortcuts, integrations, dictation, voice, permissions, privacy, diagnostics
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: return "일반"
        case .appearance: return "모양"
        case .sounds: return "사운드"
        case .notifications: return "알림"
        case .shortcuts: return "단축키"
        case .integrations: return "연동"
        case .dictation: return "받아쓰기"
        case .voice: return "음성"
        case .permissions: return "권한"
        case .privacy: return "개인정보"
        case .diagnostics: return "진단"
        }
    }
    var icon: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .appearance: return "rectangle.split.2x1"
        case .sounds: return "speaker.wave.2"
        case .notifications: return "bell"
        case .shortcuts: return "keyboard"
        case .integrations: return "link"
        case .dictation: return "waveform"
        case .voice: return "waveform.circle"
        case .permissions: return "checkmark.shield"
        case .privacy: return "lock.shield"
        case .diagnostics: return "waveform.path.ecg.rectangle"
        }
    }
    var subtitle: String {
        switch self {
        case .general: return "리움 노치의 기본 동작을 설정합니다."
        case .appearance: return "노치의 모습과 빛을 원하는 대로 설정합니다."
        case .sounds: return "작업과 알림의 소리를 설정합니다."
        case .notifications: return "중요한 순간을 알려줍니다."
        case .shortcuts: return "자주 쓰는 동작을 빠르게 실행합니다."
        case .integrations: return "음악과 다른 기능을 연결합니다."
        case .dictation: return "말한 내용을 텍스트로 입력합니다."
        case .voice: return "목소리로 에이전트와 대화합니다."
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
            configuration.label
            Spacer(minLength: 16)
            Toggle("", isOn: configuration.$isOn).labelsHidden().toggleStyle(.switch)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: Model
    @ObservedObject private var updater: UpdateController
    @ObservedObject private var dictation: DictationController
    @ObservedObject private var navigation: SettingsNavigation
    private var page: SettingsPage { navigation.page }
    private var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "알 수 없음" }
    @AppStorage("rium.light.enabled") private var lightEnabled = true
    @AppStorage("rium.light.agent") private var agentLight = true
    @AppStorage("rium.light.music") private var musicLight = true
    @AppStorage("rium.light.clipboard") private var clipboardLight = true
    @AppStorage("rium.light.airdrop") private var airDropLight = true
    @AppStorage("rium.light.shelf") private var shelfLight = true
    @AppStorage("rium.light.system") private var systemLight = true
    @AppStorage("rium.light.rays") private var raysLight = false
    @AppStorage("rium.light.thickness") private var lightThickness = 0.6
    @AppStorage("rium.light.width") private var lightWidth = "extraLarge"

    init(model: Model, initialPage: String? = nil) {
        self.model = model; self.dictation = model.dictation; self.updater = model.updater
        let navigation = SettingsNavigation()
        if let initialPage = initialPage, let selected = SettingsPage(rawValue: initialPage) { navigation.page = selected }
        if CommandLine.arguments.contains("--self-test-render-settings"),
           let tab = ProcessInfo.processInfo.environment["RIUM_APPEARANCE_TEST_PAGE"],
           let selected = AppearancePage(rawValue: tab) { navigation.appearance = selected }
        self.navigation = navigation
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
            .background(Color(red: 0.105, green: 0.115, blue: 0.135), in: RoundedRectangle(cornerRadius: 25, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 25, style: .continuous).stroke(.white.opacity(0.10), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
            .padding(.top, 42).padding(.trailing, 16).padding(.bottom, 16)
        }
        .frame(width: 1080, height: 780)
        .background(Color(red: 0.066, green: 0.075, blue: 0.09))
        .toggleStyle(SettingsSwitchStyle())
        .preferredColorScheme(.dark)
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
                    ForEach([SettingsPage.general, .appearance, .sounds, .notifications, .shortcuts]) { sidebarButton($0) }
                    sidebarHeading("도구")
                    ForEach([SettingsPage.integrations, .dictation, .voice]) { sidebarButton($0) }
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
        Button { navigation.page = item } label: {
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
                    Button("확인") { updater.check() }.disabled(updater.checking)
                    if updater.releaseURL != nil { Button("릴리스 열기") { updater.openRelease() } }
                }
                Text(updater.status).font(.caption).foregroundStyle(.secondary)
                Toggle("GitHub 릴리스 자동 확인", isOn: Binding(get: { updater.autoCheck }, set: { updater.setAutoCheck($0) }))
                Text("설치는 릴리스 페이지에서 직접 확인합니다.").font(.caption).foregroundStyle(.secondary)
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
                Picker("노치를 표시할 화면", selection: Binding(get: { model.preferredDisplayID ?? 0 }, set: { model.setPreferredDisplay($0) })) {
                    Text("기본 화면").tag(UInt32(0))
                    ForEach(model.availableDisplays) { display in Text(display.name).tag(display.id) }
                    if let id = model.preferredDisplayID, !model.availableDisplays.contains(where: { $0.id == id }) { Text("연결되지 않은 화면").tag(id) }
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
        case .appearance:
            appearanceContent
        case .notifications:
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
            SettingsCard(title: "받아쓰기 단축키") {
                Picker("단축키", selection: Binding(get: { dictation.shortcut }, set: { dictation.setShortcut($0) })) {
                    ForEach(DictationShortcut.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Text("키 조합을 누르고 있는 동안 받아쓰기를 실행합니다.").font(.caption).foregroundStyle(.secondary)
            }
        case .integrations:
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
                Text(dictation.status).font(.caption).foregroundStyle(.secondary)
            }
        case .permissions:
            SettingsCard(title: "접근 권한") {
                HStack {
                    Button("손쉬운 사용") { openPrivacy("Privacy_Accessibility") }
                    Button("마이크") { openPrivacy("Privacy_Microphone") }
                    Button("파일 및 폴더") { openPrivacy("Privacy_FilesAndFolders") }
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
        case .sounds, .voice:
            SettingsCard(title: page.title) {
                Text("이 기능은 아직 구현 중입니다.").foregroundStyle(.secondary)
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
                notchPlacementPreview(title: "다이나믹 아일랜드", detail: "준비 중", floating: true)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("내 스타일 찾기").font(.system(size: 20, weight: .semibold))
                Text("카드의 질감과 모양을 선택합니다.").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                cardStylePreview("글래스", selected: false)
                cardStylePreview("리퀴드 글래스", selected: true)
                cardStylePreview("피지컬", selected: false)
                cardStylePreview("대시보드", selected: false)
            }
        case .agents:
            SettingsCard(title: "에이전트") {
                Text("작업 상태를 노치와 홈 카드에 표시합니다.").foregroundStyle(.secondary)
                Text("캐릭터 선택은 아직 구현 중입니다.").font(.caption).foregroundStyle(.secondary)
            }
        case .light:
            VStack(alignment: .leading, spacing: 7) {
                Text("나만의 빛").font(.system(size: 20, weight: .semibold))
                Text("에이전트가 작업할 때 노치에 표시할 빛을 확인합니다.").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                lightPreview("클래식", file: "appearance-halo-classic", selected: true)
                lightPreview("픽셀", file: "appearance-halo-pixelated")
                lightPreview("볼륨 조명", file: "appearance-halo-lumière")
                lightPreview("광선", file: "appearance-halo-rayons")
                lightPreview("생체 발광", file: "appearance-halo-bio")
                lightPreview("크리스털 프리즘", file: "appearance-halo-prisme")
                lightPreview("구름", file: "appearance-halo-nimbus")
            }
            lightControls
        case .effects:
            lightControls
        }
    }
    private func notchPlacementPreview(title: String, detail: String, floating: Bool) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 13).fill(LinearGradient(colors: [Color(red: 0.27, green: 0.35, blue: 0.51), Color(red: 0.08, green: 0.13, blue: 0.24)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Rectangle().fill(.white.opacity(0.12)).frame(height: 26)
                if floating { Capsule().fill(.black).frame(width: 64, height: 17).padding(.top, 6) }
                else { RoundedRectangle(cornerRadius: 6).fill(.black).frame(width: 92, height: 24).offset(y: -2) }
            }.frame(height: 76).clipped().clipShape(RoundedRectangle(cornerRadius: 13))
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.caption.weight(.semibold))
                    Text(detail).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: floating ? "circle" : "checkmark.circle.fill").foregroundStyle(floating ? Color.secondary : Color.blue)
            }
        }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.125, green: 0.14, blue: 0.17), in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).stroke(floating ? .white.opacity(0.12) : Color.blue, lineWidth: floating ? 1 : 1.5))
            .accessibilityElement(children: .combine)
    }
    private func cardStylePreview(_ title: String, selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            CardStyleIllustration(style: title).frame(height: 70)
            HStack { Text(title).font(.caption.weight(.semibold)); Spacer(); if !selected { Text("준비 중").font(.caption2).foregroundStyle(.secondary) } }
        }.padding(6).frame(maxWidth: .infinity)
            .background(Color(red: 0.125, green: 0.14, blue: 0.17), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? Color.blue : .white.opacity(0.12), lineWidth: selected ? 1.5 : 1))
            .accessibilityElement(children: .combine)
    }
    private func lightPreview(_ title: String, file: String, selected: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .top) {
                Color.black
                RoundedRectangle(cornerRadius: 14).fill(.black).frame(width: 82, height: 25)
                    .overlay(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 12).stroke(Color.cyan.opacity(0.7), lineWidth: 2).blur(radius: 4)
                    }
                RoundedRectangle(cornerRadius: 12).stroke(Color.cyan.opacity(0.55), lineWidth: 1)
                    .frame(width: 82, height: 25)
            }.frame(maxWidth: .infinity).frame(height: 76).clipped().clipShape(RoundedRectangle(cornerRadius: 12))
            HStack { Text(title).font(.caption.weight(.semibold)); Spacer(); if !selected { Text("준비 중").font(.caption2).foregroundStyle(.secondary) } else { Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue) } }
        }.padding(6)
            .background(Color(red: 0.125, green: 0.14, blue: 0.17), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? Color.blue : .white.opacity(0.12), lineWidth: selected ? 1.5 : 1))
            .accessibilityElement(children: .combine)
    }
    private var lightControls: some View {
            SettingsCard(title: "노치 조명") {
                Toggle("노치 조명", isOn: $lightEnabled)
                Group {
                    Toggle("에이전트 상태 조명", isOn: $agentLight)
                    Toggle("음악 재생 중 빛 물결 표시", isOn: $musicLight)
                    Toggle("복사할 때 빛 표시", isOn: $clipboardLight)
                    Toggle("AirDrop 수신 시 빛 표시", isOn: $airDropLight)
                    Toggle("보관함에 담을 때 빛 표시", isOn: $shelfLight)
                    Toggle("음량·밝기 변경 시 빛 표시", isOn: $systemLight)
                    Toggle("광선과 빛 입자", isOn: $raysLight)
                    Picker("빛 너비", selection: $lightWidth) {
                        Text("좁게").tag("narrow"); Text("보통").tag("medium"); Text("넓게").tag("wide"); Text("아주 넓게").tag("extraLarge")
                    }.pickerStyle(.segmented)
                    HStack {
                        Text("빛 두께")
                        Slider(value: $lightThickness, in: 0.5...2, step: 0.05).accessibilityLabel("빛 두께")
                        Text("\(Int((lightThickness * 100).rounded()))%").monospacedDigit().frame(width: 55, alignment: .trailing)
                    }
                }.disabled(!lightEnabled)
                Text("모션 줄이기를 켜면 움직임을 줄입니다.").font(.caption).foregroundStyle(.secondary)
            }
    }
    private func openPrivacy(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") { NSWorkspace.shared.open(url) }
    }
}

// Drawn locally for the settings screen; the original app's preview assets
// are not bundled. The illustrations describe styles, not selectable modes.
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
