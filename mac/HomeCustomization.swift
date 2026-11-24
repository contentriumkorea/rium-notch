import AppKit
import SwiftUI
import UniformTypeIdentifiers

@_silgen_name("rium_home_music_wave_height")
private func rustHomeMusicWaveHeight(_ index: Int32, _ time: Double, _ playing: Int32, _ reduceMotion: Int32) -> Double

@_silgen_name("rium_home_source_wave_height")
private func rustHomeSourceWaveHeight(_ index: Int32, _ time: Double, _ playing: Int32, _ reduceMotion: Int32) -> Double

@_silgen_name("rium_home_disc_angle")
private func rustHomeDiscAngle(_ base: Double, _ elapsed: Double) -> Double

@_silgen_name("rium_home_hour_photo")
private func rustHomeHourPhoto(_ hour: Int32) -> Int32

@_silgen_name("rium_home_calendar_bounds")
private func rustHomeCalendarBounds(_ defaultStart: Double, _ defaultEnd: Double,
                                    _ events: UnsafePointer<Double>?, _ count: Int,
                                    _ output: UnsafeMutablePointer<Double>?) -> Int32

enum LocalHourBackdrop {
    private static let cache = NSCache<NSNumber, NSImage>()
    private static let washCache = NSCache<NSNumber, NSImage>()
    static func anchor(at date: Date) -> Int32 {
        rustHomeHourPhoto(Int32(Calendar.current.component(.hour, from: date)))
    }
    static func image(at date: Date) -> NSImage? {
        let hour = anchor(at: date)
        guard hour >= 0 else { return nil }
        let key = NSNumber(value: hour)
        if let image = cache.object(forKey: key) { return image }
        let name = String(format: "hour-%02d", hour)
        guard let url = Bundle.main.url(forResource: name, withExtension: "jpg"), let image = NSImage(contentsOf: url) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
    static func wash(at date: Date) -> NSImage? {
        let key = NSNumber(value: anchor(at: date))
        if let image = washCache.object(forKey: key) { return image }
        guard let image = image(at: date), let wash = blurredArtwork(image) else { return nil }
        washCache.setObject(wash, forKey: key)
        return wash
    }
}

@_silgen_name("rium_music_remaining_fraction")
private func rustHomeMusicRemainingFraction(_ elapsed: Double, _ duration: Double) -> Double

@_silgen_name("rium_weather_feels_like")
func rustWeatherFeelsLike(_ temperature: Double, _ wind: Double, _ humidity: Double) -> Double
@_silgen_name("rium_weather_illustration")
private func rustWeatherIllustration(_ bytes: UnsafePointer<UInt8>?, _ length: Int) -> Int32

@_silgen_name("rium_event_countdown")
private func rustEventCountdown(_ seconds: Double, _ minutes: UnsafeMutablePointer<Int64>?, _ progress: UnsafeMutablePointer<Double>?) -> Int32

@_silgen_name("rium_clock_hand_turns")
private func rustClockHandTurns(_ hour: Int32, _ minute: Int32, _ second: Double, _ output: UnsafeMutablePointer<Double>?) -> Int32

@_silgen_name("rium_home_dial_interval")
private func rustHomeDialInterval(_ active: Int32, _ reduceMotion: Int32, _ lowPower: Int32) -> Double

enum NotchTab: String, CaseIterable, Identifiable {
    case home, agents, notifications, dictation, clipboard, teleprompter, music, weather, agenda, shelf, focus, interview, notes, assistant
    static let defaultTabs: [NotchTab] = [.home, .agents, .dictation, .clipboard, .teleprompter]
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return "홈"; case .agents: return "작업"; case .notifications: return "알림"; case .dictation: return "받아쓰기"; case .clipboard: return "클립보드"; case .teleprompter: return "프롬프터"
        case .music: return "음악"; case .weather: return "날씨"; case .agenda: return "일정"; case .shelf: return "보관함"; case .focus: return "집중"; case .interview: return "면접"; case .notes: return "메모"; case .assistant: return "AI 대화"
        }
    }
    var icon: String {
        switch self {
        case .home: return "square.grid.2x2"; case .agents: return "bubble.left.and.bubble.right"; case .notifications: return "bell"; case .dictation: return "waveform"; case .clipboard: return "clipboard"; case .teleprompter: return "text.alignleft"
        case .music: return "music.note"; case .weather: return "cloud.sun"; case .agenda: return "calendar"; case .shelf: return "tray"; case .focus: return "timer"; case .interview: return "person.2.wave.2"; case .notes: return "note.text"; case .assistant: return "sparkles"
        }
    }
    var section: PanelSection? {
        switch self {
        case .home: return .home; case .agents: return .agents; case .notifications: return .notifications; case .dictation: return .dictation; case .clipboard: return .clipboard; case .teleprompter: return .teleprompter
        case .music: return .music; case .weather: return .weather; case .agenda: return .agenda; case .shelf: return .shelf; case .focus: return .monitor; case .interview: return .interview; case .notes: return .notes; case .assistant: return .assistant
        }
    }
    static func normalized(_ raw: [String]?, preservesHidden: Bool = false) -> [NotchTab] {
        guard let raw = raw else { return defaultTabs }
        var result: [NotchTab] = [.home]
        for value in raw {
            if let tab = NotchTab(rawValue: value), tab != .home, !result.contains(tab) { result.append(tab) }
        }
        if !preservesHidden { for tab in defaultTabs where !result.contains(tab) { result.append(tab) } }
        return result
    }
}

enum HomeSlot: String, CaseIterable, Identifiable {
    case music, centre, weather, calendar
    var id: String { rawValue }
    var title: String { switch self { case .music: return "음악"; case .centre: return "중앙"; case .weather: return "날씨"; case .calendar: return "일정" } }
    var variants: [HomeVariant] {
        switch self {
        case .music: return [.init(id: "player", title: "플레이어", symbol: "play.circle"), .init(id: "artwork", title: "앨범 아트", symbol: "music.note"), .init(id: "album", title: "앨범", symbol: "square.stack"), .init(id: "ambient", title: "앰비언트", symbol: "sparkles"), .init(id: "type", title: "텍스트", symbol: "textformat"), .init(id: "lyrics", title: "가사", symbol: "text.quote"), .init(id: "disc", title: "음반", symbol: "opticaldisc"), .init(id: "wave", title: "파형", symbol: "waveform"), .init(id: "ring", title: "재생 링", symbol: "circle.dotted"), .init(id: "cassette", title: "카세트", symbol: "recordingtape"), .init(id: "time", title: "재생 시간", symbol: "clock"), .init(id: "source", title: "재생 앱", symbol: "app"), .init(id: "remote", title: "리모컨", symbol: "play.circle")]
        case .centre: return [.init(id: "agent", title: "에이전트", symbol: "face.smiling"), .init(id: "today", title: "오늘", symbol: "calendar"), .init(id: "focus", title: "집중", symbol: "timer"), .init(id: "lumi", title: "Rium", symbol: "face.smiling"), .init(id: "note", title: "메모", symbol: "note.text")]
        case .weather: return [.init(id: "now", title: "현재", symbol: "cloud.sun"), .init(id: "sentence", title: "문장", symbol: "text.alignleft"), .init(id: "forecast", title: "예보", symbol: "cloud.sun.fill"), .init(id: "sky", title: "하늘", symbol: "cloud.sun.fill"), .init(id: "illustrated", title: "일러스트", symbol: "sun.max.fill"), .init(id: "days", title: "며칠 예보", symbol: "calendar"), .init(id: "curve", title: "기온 곡선", symbol: "chart.xyaxis.line"), .init(id: "range", title: "예보 범위", symbol: "thermometer.medium"), .init(id: "rain", title: "강수량", symbol: "cloud.rain"), .init(id: "feels", title: "체감 온도", symbol: "thermometer.medium"), .init(id: "humidity", title: "습도", symbol: "humidity"), .init(id: "wind", title: "바람", symbol: "wind")]
        case .calendar: return [.init(id: "next", title: "다음 일정", symbol: "calendar"), .init(id: "date", title: "날짜", symbol: "calendar"), .init(id: "clock", title: "시계", symbol: "clock"), .init(id: "dial", title: "아날로그 시계", symbol: "clock"), .init(id: "ringClock", title: "링 시계", symbol: "clock"), .init(id: "day", title: "오늘 일정", symbol: "calendar.day.timeline.left"), .init(id: "agenda", title: "일정 목록", symbol: "list.bullet"), .init(id: "countdown", title: "일정 카운트다운", symbol: "timer"), .init(id: "week", title: "이번 주", symbol: "calendar"), .init(id: "month", title: "이번 달", symbol: "calendar")]
        }
    }
    var defaultVariant: String { variants[0].id }
}
struct HomeVariant: Identifiable {
    let id: String
    let title: String
    let symbol: String
}

private let notchTabDragType = UTType(exportedAs: "kr.contentrium.rium-notch.tab", conformingTo: .data)

struct EditableNotchTab: View {
    @ObservedObject var model: Model
    let tab: NotchTab
    private var content: some View {
        Button {
            if model.tabEditing { if tab != .home { model.selectedTab = tab } }
            else if let section = tab.section { model.select(section) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.icon).frame(width: 16)
                if tab == .agents {
                    let count = model.visibleActiveAgentCount
                    if count > 0 { Text("\(count)").font(.system(size: 10, weight: .semibold)).foregroundStyle(.black).padding(.horizontal, 6).padding(.vertical, 2).background(Color.blue, in: Capsule()) }
                }
                if tab == .clipboard && !model.clipboardItems.isEmpty { Text("\(model.clipboardItems.count)").font(.system(size: 10)).foregroundStyle(.secondary) }
                if tab == .notifications && model.visibleNotificationUnreadCount > 0 {
                    Text("\(model.visibleNotificationUnreadCount)").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.black).padding(.horizontal, 6).padding(.vertical, 2).background(Color.blue, in: Capsule())
                }
                if !model.tabEditing, tab.section == model.section { Text(tab.title).lineLimit(1) }
            }
            .padding(.horizontal, 9).frame(minWidth: 52, minHeight: 28)
            .background {
                if !model.tabEditing && tab.section != nil && tab.section == model.section {
                    Capsule().fill(LinearGradient(colors: [.white.opacity(0.26), .white.opacity(0.13)], startPoint: .top, endPoint: .bottom))
                        .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 0.7))
                }
            }
            .overlay(Capsule().stroke(model.tabEditing && tab == model.selectedTab ? .white : .white.opacity(model.tabEditing ? 0.18 : 0), lineWidth: model.tabEditing && tab == model.selectedTab ? 1.5 : 1))
            .opacity(model.tabEditing && tab == .home ? 0.35 : 1)
            .contentShape(Rectangle())
        }.buttonStyle(.plain).help(tab.title).accessibilityLabel(tab.title)
    }
    var body: some View {
        if model.tabEditing && tab != .home {
            content.onDrag {
                model.draggingTab = tab
                let provider = NSItemProvider()
                provider.registerDataRepresentation(forTypeIdentifier: notchTabDragType.identifier, visibility: .ownProcess) { completion in
                    completion(Data(tab.rawValue.utf8), nil)
                    return nil
                }
                return provider
            }
            .onDrop(of: [notchTabDragType], delegate: NotchTabDrop(model: model, target: tab))
        } else { content }
    }
}
private struct NotchTabDrop: DropDelegate {
    let model: Model
    let target: NotchTab
    func validateDrop(info: DropInfo) -> Bool { model.draggingTab != nil && target != .home }
    func dropEntered(info: DropInfo) {
        if let source = model.draggingTab { model.moveTab(source, to: target) }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { model.draggingTab = nil; return true }
}

private let homeEditorSlotLabelHeight: CGFloat = 22

func homeCardRowHeight(editing: Bool) -> CGFloat {
    116 + (editing ? homeEditorSlotLabelHeight : 0)
}

extension View {
    func homeCardSelection(_ model: Model, slot: HomeSlot) -> some View {
        let card = disabled(model.homeEditing)
            .allowsHitTesting(!model.homeEditing)
            .accessibilityHidden(model.homeEditing)
            .overlay {
                if model.homeEditing {
                    Button { model.homeSelectedSlot = slot } label: {
                        RoundedRectangle(cornerRadius: 25, style: .continuous)
                            .strokeBorder(model.homeSelectedSlot == slot ? .white : .clear, lineWidth: 2.5)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(slot.title) 카드 선택")
                }
            }
            .contentShape(Rectangle())
            .contextMenu {
                if model.expanded && model.section == .home && !model.homeEditing && !model.tabEditing &&
                    model.homeNotification(for: slot) == nil {
                    Button("홈 편집…") { model.beginHomeEdit(slot: slot) }
                    Picker("카드 표시", selection: Binding(
                        get: { model.homeVariant(slot) },
                        set: { model.setHomeVariant($0, for: slot) }
                    )) {
                        ForEach(slot.variants) { variant in
                            Text(variant.title).tag(variant.id)
                        }
                    }
                    .pickerStyle(.inline)
                    if slot == .centre && model.homeVariant(slot) == "note" {
                        Divider()
                        Button("메모 편집…") { model.editHomeNote() }
                    }
                }
            }
        return VStack(spacing: 0) {
            card
            if model.homeEditing {
                Button { model.homeSelectedSlot = slot } label: {
                    Text(slot.title)
                        .frame(maxWidth: .infinity)
                        .frame(height: homeEditorSlotLabelHeight, alignment: .bottom)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(model.homeSelectedSlot == slot ? .white : .secondary)
            }
        }
    }
}

struct HomeEditorOptions: View {
    @ObservedObject var model: Model
    var body: some View {
        let slot = model.homeSelectedSlot
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(slot.variants) { variant in
                        Button { model.setHomeVariant(variant.id, for: slot) } label: {
                            VStack(spacing: 5) {
                                HomeVariantPreview(model: model, slot: slot, variant: variant.id)
                                    .frame(width: 112, height: 64)
                                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(model.homeVariant(slot) == variant.id ? .white : .clear, lineWidth: 2))
                                Text(variant.title).font(.system(size: 10, weight: .medium)).foregroundStyle(model.homeVariant(model.homeSelectedSlot) == variant.id ? .white : .secondary)
                            }
                        }.buttonStyle(.plain).accessibilityLabel("\(slot.title) \(variant.title)")
                    }
                }.padding(3)
            }.frame(height: 87)
            HStack {
                Text("홈 배경").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Toggle("Codex 사용량 패널", isOn: Binding(get: { model.homeShowsCodexUsage }, set: { model.setHomeShowsCodexUsage($0) }))
                    .toggleStyle(.switch).controlSize(.mini).font(.system(size: 11))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(HomeBackground.allCases) { background in
                        Button { model.setHomeBackground(background) } label: {
                            VStack(spacing: 4) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10).fill(background.preview)
                                    if background.isTexture {
                                        HomeTextureSurface(background: background, priority: background == model.homeBackground)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                    if background == .hour, let image = LocalHourBackdrop.image(at: model.now) {
                                        Image(nsImage: image).resizable().scaledToFill().frame(width: 116, height: 38)
                                            .clipped().clipShape(RoundedRectangle(cornerRadius: 10)).opacity(0.65)
                                    }
                                    HStack(spacing: 3) { ForEach(0..<4) { _ in RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.09)).overlay(RoundedRectangle(cornerRadius: 3).stroke(.white.opacity(0.14), lineWidth: 0.5)) } }.padding(7)
                                }.frame(width: 116, height: 38)
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(model.homeBackground == background ? .white : .clear, lineWidth: 2))
                                Text(background.title).font(.system(size: 10)).foregroundStyle(model.homeBackground == background ? .white : .secondary)
                            }
                        }.buttonStyle(.plain).accessibilityLabel("홈 배경 \(background.title)")
                    }
                }.padding(3)
            }.frame(height: 61)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct HomeCodexUsagePanel: View {
    static let height: CGFloat = 102
    @ObservedObject var model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Codex 구독 사용 한도").font(.system(size: 12, weight: .semibold))
                Spacer()
                Button { model.listAccounts() } label: {
                    Label("새로고침", systemImage: "arrow.clockwise")
                        .padding(.horizontal, 7).padding(.vertical, 3).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            if model.accounts.isEmpty {
                Text(model.message.isEmpty ? "연결된 계정 없음" : model.message).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                GeometryReader { geometry in
                    let gap: CGFloat = 18
                    let columns = min(model.accounts.count, 2)
                    let columnWidth = (geometry.size.width - CGFloat(columns - 1) * gap) / CGFloat(columns)
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: gap) {
                            ForEach(model.accounts) { account in
                                accountDetails(account)
                                    .frame(width: max(0, columnWidth), height: geometry.size.height, alignment: .topLeading)
                            }
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollIndicators(model.accounts.count > 2 ? .automatic : .hidden)
                }
            }
        }
        .font(.system(size: 11))
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Self.height)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }

    private func accountDetails(_ account: Account) -> some View {
        ViewThatFits(in: .vertical) {
            accountRows(account).fixedSize(horizontal: false, vertical: true)
            ScrollView(.vertical) {
                accountRows(account)
            }
            .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func accountRows(_ account: Account) -> some View {
        let summary = account.secondaryRemaining.flatMap { $0.isWeekly ? $0 : nil } ?? account.remaining
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(account.name).fontWeight(.semibold)
                if let summary, summary.reset.map({ $0 > model.now }) ?? true {
                    Text(summary.isWeekly ? "주간 잔여 \(summary.percent)%" : "\(summary.percent)% 남음")
                        .monospacedDigit().fixedSize()
                }
            }
            Text(account.usage).foregroundStyle(.secondary)
            if !account.detail.isEmpty { Text(account.detail).foregroundStyle(.secondary) }
            if let updatedAt = account.usageUpdatedAt {
                Text("연결됨 · 갱신 \(updatedAt.formatted(date: .omitted, time: .standard))")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            ForEach(Array(account.additionalUsage.enumerated()), id: \.offset) { _, line in
                Text(line).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HomeVariantPreview: View {
    @ObservedObject var model: Model
    let slot: HomeSlot
    let variant: String
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 13).fill(.white.opacity(0.09))
            VStack(alignment: .leading, spacing: 2) {
                switch slot {
                case .music:
                    if variant == "type" {
                        Image(systemName: model.mediaPlaying ? "waveform" : "pause").font(.system(size: 6)).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Text(model.mediaAvailable ? model.mediaTitle : "재생 중인 음악 없음").font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.5)
                        Text(model.mediaArtist).font(.system(size: 6)).foregroundStyle(.secondary).lineLimit(1)
                    } else {
                        HStack(spacing: 4) {
                            Group {
                                if let artwork = model.mediaArtwork { Image(nsImage: artwork).resizable().scaledToFill() }
                                else { Image(systemName: "music.note").font(.system(size: 9)).frame(maxWidth: .infinity, maxHeight: .infinity).background(.white.opacity(0.10)) }
                            }.frame(width: variant == "artwork" ? 35 : 20, height: variant == "artwork" ? 35 : 20).clipShape(RoundedRectangle(cornerRadius: 4))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.mediaTitle).font(.system(size: 6, weight: .semibold)).lineLimit(1)
                                Text(model.mediaArtist.isEmpty ? "음악" : model.mediaArtist).font(.system(size: 5)).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                        if variant == "lyrics" {
                            Text(activeLyricLine(model.lyricLines, positionKnown: model.mediaPositionKnown, elapsed: model.mediaElapsed)?.text ?? "가사").font(.system(size: 7)).lineLimit(1)
                        } else if variant == "disc" {
                            Image(systemName: "opticaldisc").font(.system(size: 17)).foregroundStyle(.white.opacity(0.75))
                        } else if variant == "wave" {
                            Image(systemName: "waveform").font(.system(size: 13)).foregroundStyle(.white.opacity(0.75))
                        } else if variant == "ring" {
                            Image(systemName: "circle.dotted").font(.system(size: 17)).foregroundStyle(.white.opacity(0.75))
                        } else if variant == "cassette" {
                            Image(systemName: "recordingtape").font(.system(size: 17)).foregroundStyle(.white.opacity(0.75))
                        } else if variant == "time" {
                            Text(model.mediaPositionKnown ? homeMusicTime(model.mediaElapsed) : "--:--").font(.system(size: 16, weight: .light)).monospacedDigit()
                        } else if variant == "source" {
                            Text(model.mediaSourceName).font(.system(size: 8)).lineLimit(1)
                        } else if variant == "remote" {
                            HStack { Image(systemName: "backward.fill"); Spacer(); Image(systemName: model.mediaPlaying ? "pause.fill" : "play.fill"); Spacer(); Image(systemName: "forward.fill") }.font(.system(size: 8))
                        } else if variant == "album" {
                            Text(model.mediaAlbum.isEmpty ? "앨범" : model.mediaAlbum).font(.system(size: 7)).lineLimit(1)
                        } else if variant == "ambient" {
                            Image(systemName: "sparkles").font(.system(size: 13)).foregroundStyle(.white.opacity(0.75))
                        } else if variant == "player" {
                            Capsule().fill(.white.opacity(0.18)).frame(height: 1)
                            HStack { Image(systemName: "backward.fill"); Spacer(); Image(systemName: model.mediaPlaying ? "pause.fill" : "play.fill"); Spacer(); Image(systemName: "forward.fill") }.font(.system(size: 6))
                        }
                    }
                case .centre:
                    Text(variant == "focus" ? "집중" : (variant == "today" ? "오늘" : (variant == "note" ? "메모" : (variant == "lumi" ? "Rium" : "에이전트")))).font(.system(size: 6)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if variant == "focus" { Text("25:00").font(.system(size: 17, weight: .light)).monospacedDigit() }
                    else if variant == "today" { Text(model.now, format: .dateTime.day()).font(.system(size: 17, weight: .light)) }
                    else if variant == "note" { Text(model.homeNote.isEmpty ? "메모 추가" : model.homeNote).font(.system(size: 8)).lineLimit(2) }
                    else { HStack { Spacer(); Image(systemName: "face.smiling.fill").font(.system(size: 22)).foregroundStyle(.blue); Spacer() } }
                case .weather:
                    if variant == "sky" {
                        Text("\(model.weatherCondition)\n\(model.weatherCity.isEmpty ? "날씨" : model.weatherCity)")
                            .font(.system(size: 6)).foregroundStyle(.secondary).lineLimit(2)
                        Spacer(minLength: 0)
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            Text(model.weatherTemperature.map { String(format: "%.0f", $0) } ?? "—")
                                .font(.system(size: 21, weight: .light))
                            Text("°").font(.system(size: 10, weight: .light))
                            Spacer(minLength: 0)
                        }.lineLimit(1).minimumScaleFactor(0.5)
                    } else {
                    Text(model.weatherCity.isEmpty ? "날씨" : model.weatherCity).font(.system(size: 6)).foregroundStyle(.secondary).lineLimit(1)
                    Text(model.weatherCondition).font(.system(size: 6)).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                    if variant == "illustrated" { HomeWeatherArtView(symbol: model.weatherSymbol).frame(width: 32, height: 32) }
                    else if variant == "days" { Image(systemName: "calendar").font(.system(size: 18)) }
                    else if variant == "curve" { Image(systemName: "chart.xyaxis.line").font(.system(size: 18)) }
                    else if variant == "range" { Text(homeWeatherRange(model)?.label ?? "예보 없음").font(.system(size: 9)).lineLimit(1) }
                    else if ["rain", "feels", "humidity", "wind"].contains(variant) { Text(homeWeatherMetric(model, variant: variant).value).font(.system(size: 14, weight: .light)).lineLimit(1) }
                    else if variant == "sentence" { Text(model.weatherTemperature.map { String(format: "현재 %.0f°", $0) } ?? "날씨 정보 없음").font(.system(size: 8)).lineLimit(2) }
                    else if variant == "forecast" {
                        if mainWeatherPreview(model).isEmpty { Text("예보 없음").font(.system(size: 7)).foregroundStyle(.secondary) }
                        else { HStack { ForEach(Array(mainWeatherPreview(model).prefix(3))) { hour in VStack(spacing: 2) { Text(homeWeatherHour(hour.date, timeZoneID: model.weatherTimeZoneID)); Text(String(format: "%.0f°", hour.temperature)) }.font(.system(size: 6)); Spacer(minLength: 1) } } }
                    } else { Text(model.weatherTemperature.map { String(format: "%.0f°", $0) } ?? "—").font(.system(size: 17, weight: .light)) }
                    }
                case .calendar:
                    Text(HomeSlot.calendar.variants.first(where: { $0.id == variant })?.title ?? "일정").font(.system(size: 6)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if variant == "date" { Text(model.now, format: .dateTime.day()).font(.system(size: 17, weight: .light)) }
                    else if variant == "clock" { Text(model.now, style: .time).font(.system(size: 14, weight: .light)).lineLimit(1).minimumScaleFactor(0.5) }
                    else if variant == "dial" || variant == "ringClock" { Image(systemName: "clock").font(.system(size: 18)).foregroundStyle(.white.opacity(0.75)) }
                    else if variant == "day" { Text(model.agenda.todayEvents.first?.title ?? (model.agenda.calendarReadable ? "오늘 일정 없음" : "Google 계정 연결 필요")).font(.system(size: 8)).lineLimit(2) }
                    else if variant == "agenda" {
                        let first = model.agenda.events.first { event in
                            guard let start = event.start, let end = event.end else { return false }
                            return eventIsRemainingToday(start: start, end: end, now: model.now, calendar: .current)
                        }
                        Text(first?.title ?? (model.agenda.calendarReadable ? "남은 일정 없음" : "Google 계정 연결 필요")).font(.system(size: 8)).lineLimit(2)
                    }
                    else if variant == "week" { Text(model.now, format: .dateTime.month().day()).font(.system(size: 12, weight: .light)).lineLimit(1) }
                    else if variant == "month" { Text(model.now, format: .dateTime.month(.wide)).font(.system(size: 12, weight: .light)).lineLimit(1) }
                    else if variant == "countdown" {
                        let next = model.agenda.events.first { ($0.end ?? $0.start ?? .distantPast) > model.now }
                        Text(next.map { agendaRelativeLabel($0, now: model.now) } ?? (model.agenda.calendarReadable ? "일정 없음" : "Google 계정 연결 필요"))
                            .font(.system(size: 9)).lineLimit(1)
                    }
                    else { Text(model.agenda.events.first.map { agendaTimeLabel($0) } ?? "일정 없음").font(.system(size: 13, weight: .light)).lineLimit(1) }
                }
            }.padding(8)
        }.clipShape(RoundedRectangle(cornerRadius: 13))
    }
}

// shortcut: Ring tint, text and narrow-screen sizing need reference comparison.
struct HomeCalendarRingClockView: View {
    var ink: Color = .white
    var body: some View {
        TimelineView(.periodic(from: .now, by: 10)) { timeline in
            let parts = Calendar.current.dateComponents([.hour, .minute, .second], from: timeline.date)
            var turns = [Double](repeating: 0, count: 3)
            let status = turns.withUnsafeMutableBufferPointer {
                rustClockHandTurns(Int32(parts.hour ?? 0), Int32(parts.minute ?? 0), Double(parts.second ?? 0), $0.baseAddress)
            }
            GeometryReader { geometry in
                let diameter = min(80, max(0, geometry.size.width * 0.48), geometry.size.height)
                HStack(spacing: 7) {
                    ZStack {
                        Circle().stroke(ink.opacity(0.15), lineWidth: 4)
                        Circle().trim(from: 0, to: status == 0 ? CGFloat(turns[1]) : 0)
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text(timeline.date, style: .time).font(.system(size: min(17, diameter * 0.25), weight: .semibold))
                            .foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.5).monospacedDigit().padding(4)
                    }.frame(width: diameter, height: diameter)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(timeline.date, format: .dateTime.weekday(.wide)).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                        Text(timeline.date, format: .dateTime.month().day()).font(.system(size: 9)).foregroundStyle(ink.opacity(0.65)).lineLimit(1)
                    }.foregroundStyle(ink).frame(maxWidth: .infinity, alignment: .leading)
                }.frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
            }
        }
    }
}

// shortcut: Dial colors, label arrangement and small-size scaling need reference comparison.
struct HomeCalendarDialView: View {
    let active: Bool
    var ink: Color = .white

    var body: some View {
        GeometryReader { geometry in
            let diameter = min(76, max(0, geometry.size.width * 0.43), geometry.size.height)
            HStack(spacing: 8) {
                ZStack {
                    face
                    HomeCalendarDialHands(active: active, ink: ink)
                }.frame(width: diameter, height: diameter).accessibilityHidden(true)
                Group {
                    if active {
                        TimelineView(.everyMinute) { labels(at: $0.date) }
                    } else {
                        labels(at: .now)
                    }
                }.foregroundStyle(ink).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
        }
    }

    private var face: some View {
        Canvas { context, size in
            let radius = min(size.width, size.height) / 2
            guard radius > 0 else { return }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let face = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: face), with: .color(ink.opacity(0.08)))
            context.stroke(Path(ellipseIn: face.insetBy(dx: 0.5, dy: 0.5)), with: .color(ink.opacity(0.2)), lineWidth: 1)
            for tick in 0..<60 {
                let major = tick % 5 == 0
                if !major && radius < 34 { continue }
                let turn = Double(tick) / 60
                var path = Path()
                path.move(to: homeDialPoint(center, turn: turn, distance: radius * (0.92 - (major ? 0.12 : 0.05))))
                path.addLine(to: homeDialPoint(center, turn: turn, distance: radius * 0.92))
                context.stroke(path, with: .color(ink.opacity(major ? 0.7 : 0.3)),
                               style: StrokeStyle(lineWidth: major ? max(1, radius * 0.035) : 0.7, lineCap: .round))
            }
        }
    }

    private func labels(at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(date, style: .time).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.6)
            Text(date, format: .dateTime.weekday(.wide)).font(.system(size: 9)).foregroundStyle(ink.opacity(0.65)).lineLimit(1)
            Text(date, format: .dateTime.month().day()).font(.system(size: 9)).foregroundStyle(ink.opacity(0.65)).lineLimit(1)
        }
    }
}

private struct HomeCalendarDialHands: View {
    let active: Bool
    let ink: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var frozenDate = Date.now
    @State private var minuteDate = Date.now

    var body: some View {
        let interval = rustHomeDialInterval(active ? 1 : 0, reduceMotion ? 1 : 0, lowPower ? 1 : 0)
        Group {
            if interval == 0 {
                draw(at: frozenDate, precision: reduceMotion ? 60 : 1)
            } else if interval == 60 {
                draw(at: minuteDate, precision: interval)
            } else if interval == 1 {
                let start = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
                TimelineView(.periodic(from: start, by: interval)) { draw(at: $0.date, precision: interval) }
            } else {
                TimelineView(.animation(minimumInterval: interval)) { draw(at: $0.date, precision: interval) }
            }
        }
        .onChange(of: active, initial: true) { _, isActive in
            if !isActive { frozenDate = .now }
        }
        .task(id: interval == 60) {
            guard interval == 60 else { return }
            while !Task.isCancelled {
                let now = Date.now
                minuteDate = now
                let next = Calendar.autoupdatingCurrent.dateInterval(of: .minute, for: now)?.end
                let delay = max(0.01, next?.timeIntervalSince(now) ?? 60)
                do { try await Task.sleep(for: .seconds(delay)) }
                catch { return }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange).receive(on: RunLoop.main)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    private func draw(at date: Date, precision: TimeInterval) -> some View {
        let parts = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        let second = precision == 60 ? 0 : Double(parts.second ?? 0)
        let fractional = precision < 1 ? Double(parts.nanosecond ?? 0) / 1_000_000_000 : 0
        return Canvas { context, size in
            let radius = min(size.width, size.height) / 2
            guard radius > 0 else { return }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            var hands = [Double](repeating: 0, count: 3)
            let status = hands.withUnsafeMutableBufferPointer {
                rustClockHandTurns(Int32(parts.hour ?? 0), Int32(parts.minute ?? 0), second + fractional, $0.baseAddress)
            }
            guard status == 0 else { return }
            for (index, length, width) in [(0, 0.50, 0.07), (1, 0.80, 0.045), (2, 0.86, 0.025)] {
                if index == 2 && precision == 60 { continue }
                let turn = hands[index]
                var path = Path()
                path.move(to: index == 2 ? homeDialPoint(center, turn: turn, distance: -0.18 * radius) : center)
                path.addLine(to: homeDialPoint(center, turn: turn, distance: radius * CGFloat(length)))
                context.stroke(path, with: .color(index == 2 ? .accentColor : ink),
                               style: StrokeStyle(lineWidth: max(1, radius * CGFloat(width)), lineCap: .round))
            }
            context.fill(Path(ellipseIn: CGRect(x: center.x - 1.5, y: center.y - 1.5, width: 3, height: 3)), with: .color(ink))
        }
    }
}

private func homeDialPoint(_ center: CGPoint, turn: Double, distance: CGFloat) -> CGPoint {
    let angle = turn * 2 * Double.pi
    return CGPoint(x: center.x + CGFloat(sin(angle)) * distance, y: center.y - CGFloat(cos(angle)) * distance)
}

// shortcut: Event selection, text layout and ring colors need reference comparison.
struct HomeCalendarCountdownView: View {
    @ObservedObject var agenda: AgendaModel
    let now: Date
    var ink: Color = .white
    var body: some View {
        let event = agenda.events.first { ($0.end ?? $0.start ?? .distantPast) > now }
        let seconds = event?.start?.timeIntervalSince(now) ?? .nan
        var minutes: Int64 = 0
        var progress = 0.0
        let available = rustEventCountdown(seconds, &minutes, &progress) == 0
        GeometryReader { geometry in
            let diameter = min(76, max(0, geometry.size.width * 0.42), geometry.size.height)
            HStack(spacing: 7) {
                ZStack {
                    Circle().stroke(ink.opacity(0.15), lineWidth: 3)
                    Circle().trim(from: 0, to: available ? CGFloat(progress) : 0)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
                    if available {
                        VStack(spacing: 0) {
                            Text(minutes <= 0 ? "지금" : (minutes < 60 ? "\(minutes)" : "\((minutes + 59) / 60)"))
                                .font(.system(size: min(18, diameter * 0.30), weight: .semibold)).lineLimit(1).minimumScaleFactor(0.5)
                            if minutes > 0 { Text(minutes < 60 ? "분" : "시간").font(.system(size: min(9, diameter * 0.15))).lineLimit(1) }
                        }.foregroundStyle(ink)
                    } else { Image(systemName: "calendar").font(.system(size: min(16, diameter * 0.27))).foregroundStyle(ink.opacity(0.6)) }
                }.frame(width: diameter, height: diameter).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("다음 일정").font(.system(size: 9)).foregroundStyle(ink.opacity(0.65))
                    Text(event?.title ?? (agenda.calendarReadable ? "일정 없음" : "Google 계정 연결 필요"))
                        .font(.system(size: 11, weight: .semibold)).lineLimit(2)
                    if let event = event { Text(agendaRelativeLabel(event, now: now)).font(.system(size: 9)).foregroundStyle(ink.opacity(0.65)).lineLimit(1) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
        }
    }
}

// shortcut: Event count, typography and marker colors await reference comparison.
struct HomeAgendaListView: View {
    @ObservedObject var agenda: AgendaModel
    let now: Date
    var ink: Color = .white
    var body: some View {
        let calendar = Calendar.current
        let today = agenda.events.filter { event in
            guard let start = event.start, let end = event.end else { return false }
            return eventIsRemainingToday(start: start, end: end, now: now, calendar: calendar)
        }
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("오늘 남은 일정").font(.system(size: 10, weight: .semibold))
                if agenda.calendarReadable && agenda.events.count < 20 { Text("\(today.count)").font(.system(size: 9)).foregroundStyle(ink.opacity(0.6)) }
                Spacer(minLength: 0)
            }
            if !agenda.calendarReadable {
                Text(agenda.calendarStatus).font(.system(size: 10)).foregroundStyle(ink.opacity(0.65)).lineLimit(2)
            } else if agenda.calendarLoading && today.isEmpty {
                Text("일정 불러오는 중…").font(.system(size: 10)).foregroundStyle(ink.opacity(0.65)).lineLimit(1)
            } else if today.isEmpty {
                Text("남은 일정 없음").font(.system(size: 10)).foregroundStyle(ink.opacity(0.65)).lineLimit(1)
            } else {
                ForEach(Array(today.prefix(3).enumerated()), id: \.offset) { _, event in
                    HStack(spacing: 4) {
                        Text(!event.allDay && (event.start ?? now) < calendar.startOfDay(for: now) ? "계속" : agendaTimeLabel(event))
                            .font(.system(size: 9)).foregroundStyle(ink.opacity(0.65)).lineLimit(1)
                        Text(event.title).font(.system(size: 10, weight: .medium)).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
            }
            Spacer(minLength: 0)
        }.foregroundStyle(ink)
    }
}

// shortcut: Compact month-grid typography and markers need reference comparison.
struct HomeCalendarMonthView: View {
    @ObservedObject var agenda: AgendaModel
    let now: Date
    var ink: Color = .white
    var body: some View {
        let calendar = Calendar.current
        let month = calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
        let count = calendar.range(of: .day, in: .month, for: now)?.count ?? 0
        let leading = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
        let rows = (leading + count + 6) / 7
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Text(now, format: .dateTime.year().month(.wide)).font(.system(size: 9, weight: .semibold)).lineLimit(1)
                if !agenda.calendarReadable { Text("Google 계정 연결 필요").font(.system(size: 7)).foregroundStyle(ink.opacity(0.6)).lineLimit(1) }
            }.foregroundStyle(ink)
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { column in
                    let index = (calendar.firstWeekday - 1 + column) % 7
                    Text(symbols.indices.contains(index) ? symbols[index] : "")
                        .font(.system(size: 7)).foregroundStyle(ink.opacity(0.6)).frame(maxWidth: .infinity)
                }
            }
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { column in
                        let ordinal = row * 7 + column - leading
                        if ordinal >= 0 && ordinal < count, let day = calendar.date(byAdding: .day, value: ordinal, to: month) {
                            let isToday = calendar.isDate(day, inSameDayAs: now)
                            Text("\(calendar.component(.day, from: day))")
                                .font(.system(size: 7, weight: isToday ? .bold : .regular))
                                .foregroundStyle(isToday ? Color.white : ink)
                                .frame(width: 12, height: 10)
                                .background(isToday ? Color.accentColor : Color.clear, in: Circle())
                                .overlay(alignment: .bottom) {
                                    if agenda.monthEventDays.contains(calendar.startOfDay(for: day)) {
                                        Circle().fill(isToday ? Color.white : ink.opacity(0.8)).frame(width: 2, height: 2).offset(y: 1)
                                    }
                                }.frame(maxWidth: .infinity)
                        } else { Color.clear.frame(height: 10).frame(maxWidth: .infinity) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// shortcut: Typography and event-dot styling are approximations until reference comparison.
struct HomeCalendarWeekView: View {
    @ObservedObject var agenda: AgendaModel
    let now: Date
    var ink: Color = .white
    var body: some View {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        VStack(alignment: .leading, spacing: 4) {
            Text("이번 주").font(.system(size: 10, weight: .medium)).foregroundStyle(ink.opacity(0.65))
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                ForEach(days, id: \.self) { day in
                    let index = calendar.component(.weekday, from: day) - 1
                    let isToday = calendar.isDate(day, inSameDayAs: now)
                    VStack(spacing: 3) {
                        Text(symbols.indices.contains(index) ? symbols[index] : "")
                            .font(.system(size: 8)).foregroundStyle(ink.opacity(0.65)).lineLimit(1)
                        Text("\(calendar.component(.day, from: day))")
                            .font(.system(size: 10, weight: isToday ? .bold : .regular)).lineLimit(1).minimumScaleFactor(0.6)
                            .foregroundStyle(isToday ? Color.white : ink)
                            .frame(width: 19, height: 19)
                            .background(isToday ? Color.accentColor : Color.clear, in: Circle())
                        Circle().fill(ink.opacity(agenda.weekEventDays.contains(calendar.startOfDay(for: day)) ? 0.8 : 0))
                            .frame(width: 3, height: 3).accessibilityHidden(true)
                    }.frame(maxWidth: .infinity)
                }
            }
            if !agenda.calendarReadable { Text("Google 계정 연결 필요").font(.system(size: 8)).foregroundStyle(ink.opacity(0.6)).lineLimit(1) }
        }
    }
}

// shortcut: text, the present-time indicator and timeline composition need screen comparison.
struct HomeCalendarDayView: View {
    @ObservedObject var agenda: AgendaModel
    let now: Date
    var body: some View {
        let events = homeCalendarTimedEvents(agenda.todayEvents, now: now)
        return VStack(alignment: .leading, spacing: 4) {
            Text("오늘 일정").font(.caption).foregroundStyle(.secondary)
            if !agenda.calendarReadable {
                Text(agenda.calendarStatus).font(.system(size: 11)).lineLimit(2)
            } else if agenda.calendarLoading && agenda.todayEvents.isEmpty {
                Text("일정 불러오는 중…").font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                Spacer(minLength: 0)
                HomeCalendarTimeline(events: events, now: now).frame(height: 14).accessibilityHidden(true)
                if let window = homeCalendarTimelineBounds(events: events, now: now) {
                    HStack {
                        Text(window.start, style: .time)
                        Spacer(minLength: 0)
                        if events.isEmpty { Text("일정 없음") }
                        Spacer(minLength: 0)
                        Text(window.end, style: .time)
                    }.font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }
}

func homeCalendarTimedEvents(_ events: [AgendaModel.Item], now: Date, calendar: Calendar = .current) -> [AgendaModel.Item] {
    events.filter { event in
        guard !event.allDay, let start = event.start else { return false }
        return calendar.isDate(start, inSameDayAs: now)
    }
}

func homeCalendarTimelineBounds(events: [AgendaModel.Item], now: Date, calendar: Calendar = .current) -> (start: Date, end: Date)? {
    let day = calendar.startOfDay(for: now)
    guard let defaultStart = calendar.date(byAdding: .hour, value: 8, to: day),
          let defaultEnd = calendar.date(byAdding: .hour, value: 20, to: day) else { return nil }
    let times = homeCalendarTimedEvents(events, now: now, calendar: calendar).flatMap { event -> [Double] in
        guard let start = event.start else { return [] }
        return [start.timeIntervalSince1970, (event.end ?? start).timeIntervalSince1970]
    }
    var output = [Double](repeating: 0, count: 2)
    let status = times.withUnsafeBufferPointer { input in
        output.withUnsafeMutableBufferPointer { result in
            rustHomeCalendarBounds(defaultStart.timeIntervalSince1970, defaultEnd.timeIntervalSince1970,
                                   input.baseAddress, input.count / 2, result.baseAddress)
        }
    }
    guard status == 0 else { return nil }
    let earliest = Date(timeIntervalSince1970: output[0])
    let start = earliest < defaultStart ? (calendar.dateInterval(of: .hour, for: earliest)?.start ?? earliest) : earliest
    return (start, Date(timeIntervalSince1970: output[1]))
}

// shortcut: layering, marker treatment and original colours need screen comparison.
struct HomeCalendarTimeline: View {
    let events: [AgendaModel.Item]
    let now: Date
    var body: some View {
        Canvas { context, size in
            guard let (start, end) = homeCalendarTimelineBounds(events: events, now: now) else { return }
            let length = end.timeIntervalSince(start)
            guard length > 0, size.width > 0, size.height > 0 else { return }
            context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 3), with: .color(.white.opacity(0.08)))
            let timed = homeCalendarTimedEvents(events, now: now)
            for event in timed {
                guard let rawStart = event.start else { continue }
                let rawEnd = event.end ?? rawStart
                let left = min(1, max(0, rawStart.timeIntervalSince(start) / length))
                let right = min(1, max(0, rawEnd.timeIntervalSince(start) / length))
                let x = min(size.width, CGFloat(left) * size.width + 1)
                let width = min(size.width - x, max(6, CGFloat(max(0, right - left)) * size.width - 2))
                guard width > 0 else { continue }
                let rect = CGRect(x: x, y: 0, width: width, height: size.height)
                let color = event.color.map { Color(nsColor: $0) } ?? .blue
                context.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(color.opacity(rawEnd < now ? 0.4 : 1)))
            }
            let marker = CGFloat(min(1, max(0, now.timeIntervalSince(start) / length))) * size.width
            context.fill(Path(CGRect(x: min(max(0, marker - 0.5), max(0, size.width - 1)), y: 0, width: 1, height: size.height)), with: .color(.white.opacity(0.7)))
        }
    }
}

private enum LocalWeatherArt {
    static let names = ["sun", "moon", "cloud", "rain", "snow", "storm-cloud", "fog", "wind"]
    static let images: [String: NSImage] = {
        var images: [String: NSImage] = [:]
        for name in names {
            if let url = Bundle.main.url(forResource: "weather-art-\(name)", withExtension: "png"), let image = NSImage(contentsOf: url) {
                images[name] = image
            }
        }
        return images
    }()
    static func image(for symbol: String) -> NSImage? {
        let bytes = Array(symbol.utf8)
        let category = bytes.withUnsafeBufferPointer { rustWeatherIllustration($0.baseAddress, $0.count) }
        guard category >= 0, Int(category) < names.count else { return nil }
        return images[names[Int(category)]]
    }
}

struct HomeWeatherArtView: View {
    let symbol: String
    var body: some View {
        Group {
            if let artwork = LocalWeatherArt.image(for: symbol) {
                Image(nsImage: artwork).resizable().scaledToFit()
            } else {
                Image(systemName: weatherIcon(symbol)).resizable().scaledToFit().symbolRenderingMode(.multicolor).padding(4)
            }
        }.accessibilityHidden(true)
    }
}

// shortcut: card spacing and artwork scale need reference-frame comparison.
struct HomeWeatherIllustratedView: View {
    @ObservedObject var model: Model
    var body: some View {
        GeometryReader { geometry in
            let side = min(80, max(0, geometry.size.width * 0.45), geometry.size.height)
            HStack(spacing: 5) {
                HomeWeatherArtView(symbol: model.weatherSymbol).frame(width: side, height: side)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.weatherCity.isEmpty ? "날씨" : model.weatherCity).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                    Text(model.weatherTemperature.map { String(format: "%.0f°", $0) } ?? "—")
                        .font(.system(size: 27, weight: .light)).lineLimit(1).minimumScaleFactor(0.5)
                    Text(model.weatherCondition).font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }.frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
        }
    }
}

// shortcut: the reference's sky text order, forecast range and card spacing still need visual comparison.
struct HomeWeatherSkyView: View {
    @ObservedObject var model: Model

    private var todayForecast: HomeWeatherDay? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = model.weatherTimeZoneID.flatMap(TimeZone.init(identifier:)) ?? .current
        guard let day = homeWeatherDays(model).first, calendar.isDate(day.id, inSameDayAs: model.now) else { return nil }
        return day
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(model.weatherCondition)\n\(model.weatherCity.isEmpty ? "날씨" : model.weatherCity)")
                .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.85))
                .lineSpacing(1).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(model.weatherTemperature.map { String(format: "%.0f", $0) } ?? "—")
                    .font(.system(size: 44, weight: .light)).tracking(-1.7)
                    .lineLimit(1).minimumScaleFactor(0.45)
                Text("°").font(.system(size: 20, weight: .light)).foregroundStyle(.white.opacity(0.7))
                Spacer(minLength: 2)
                if let day = todayForecast {
                    // shortcut: these are the remaining hourly extrema, not a complete daily forecast.
                    Text(String(format: "%.0f° / %.0f°", day.high, day.low))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .accessibilityLabel(String(format: "남은 시간 예보 최고 %.0f도, 최저 %.0f도", day.high, day.low))
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// shortcut: the reference's weather curve and card spacing still need visual comparison.
struct HomeWeatherVisual: View {
    @ObservedObject var model: Model
    let variant: String
    var body: some View {
        if variant == "sky" {
            HomeWeatherSkyView(model: model)
        } else {
        VStack(alignment: .leading, spacing: 3) {
            Text(model.weatherCity.isEmpty ? "날씨" : model.weatherCity).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            if variant == "days" {
                let days = homeWeatherDays(model)
                if days.isEmpty {
                    Spacer(minLength: 0); Text("예보 정보 없음").font(.caption).foregroundStyle(.secondary)
                } else {
                    HStack(alignment: .center, spacing: 3) {
                        ForEach(days) { day in
                            VStack(spacing: 3) {
                                Text(homeWeatherWeekday(day.id, timeZoneID: model.weatherTimeZoneID)).font(.system(size: 9)).foregroundStyle(.secondary)
                                Image(systemName: weatherIcon(day.symbol)).font(.system(size: 13))
                                Text(String(format: "%.0f°/%.0f°", day.low, day.high)).font(.system(size: 9)).lineLimit(1).minimumScaleFactor(0.6)
                            }.frame(maxWidth: .infinity)
                        }
                    }
                    Text("남은 예보 시각 기준").font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1)
                }
            } else if variant == "range" {
                Spacer(minLength: 0)
                Text(homeWeatherRange(model)?.label ?? "예보 정보 없음").font(.system(size: 20, weight: .light)).lineLimit(1).minimumScaleFactor(0.6)
                Text(homeWeatherRange(model).map { "향후 \($0.count)개 시간대의 최저·최고" } ?? "시간별 예보").font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            } else {
                let hours = homeWeatherGraphHours(model)
                if hours.count < 2 {
                    Spacer(minLength: 0); Text("시간별 예보 없음").font(.caption).foregroundStyle(.secondary)
                } else {
                    HStack {
                        Text(String(format: "%.0f°", hours[0].temperature))
                        Spacer()
                        Text(String(format: "%.0f°", hours[hours.count - 1].temperature))
                    }.font(.caption2).foregroundStyle(.secondary)
                    HomeTemperatureCurve(hours: hours).stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                        .frame(height: 30).accessibilityHidden(true)
                    HStack {
                        Text(homeWeatherHour(hours[0].date, timeZoneID: model.weatherTimeZoneID) + "시")
                        Spacer()
                        Text(homeWeatherHour(hours[hours.count - 1].date, timeZoneID: model.weatherTimeZoneID) + "시")
                    }.font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        }
    }
}

struct HomeTemperatureCurve: Shape {
    let hours: [WeatherHour]
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard hours.count > 1, let low = hours.map(\.temperature).min(), let high = hours.map(\.temperature).max() else { return path }
        let range = max(1, high - low)
        let baseline = (low + high - range) / 2
        let plot = rect.insetBy(dx: 1, dy: 1)
        let start = hours[0].date.timeIntervalSinceReferenceDate
        let span = max(1, hours[hours.count - 1].date.timeIntervalSinceReferenceDate - start)
        for (index, hour) in hours.enumerated() {
            let x = plot.minX + plot.width * CGFloat((hour.date.timeIntervalSinceReferenceDate - start) / span)
            let y = plot.maxY - plot.height * CGFloat((hour.temperature - baseline) / range)
            if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }
}

func homeMusicProgress(known: Bool, elapsed: Double, duration: Double) -> Double? {
    guard known else { return nil }
    let remaining = rustHomeMusicRemainingFraction(elapsed, duration)
    return remaining >= 0 ? 1 - remaining : nil
}

struct HomeMusicProgressBar: View {
    let model: Model
    var opacity = 1.0

    var body: some View {
        MediaProgressTimeline(model: model) { elapsed in
            if let progress = homeMusicProgress(known: model.mediaPositionKnown, elapsed: elapsed, duration: model.mediaDuration) {
                GeometryReader { bar in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.15))
                        Capsule().fill(.white.opacity(opacity)).frame(width: bar.size.width * progress)
                    }
                }
                .frame(height: 6)
                .accessibilityRepresentation { ProgressView(value: progress).accessibilityLabel("재생 진행률") }
            } else {
                Capsule().fill(.white.opacity(0.15)).frame(height: 2)
            }
        }
    }
}

private func homeMusicTime(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "0:00" }
    let value = Int(min(max(seconds, 0), 604_800))
    return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) : String(format: "%d:%02d", value / 60, value % 60)
}

// shortcut: text weight, icon color and tile padding need reference-frame comparison.
struct HomeMusicTypeView: View {
    @ObservedObject var model: Model
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: model.mediaPlaying ? "waveform" : "pause")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(model.mediaAvailable ? model.mediaTitle : "재생 중인 음악 없음")
                .font(.system(size: 22, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.5)
            if !model.mediaArtist.isEmpty {
                Text(model.mediaArtist).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
    }
}

// shortcut: Background blend and spacing are approximations until the original is compared visually.
struct HomeMusicAmbientView: View {
    @ObservedObject var model: Model
    var body: some View {
        ZStack {
            GeometryReader { geometry in
                if let atmosphere = model.mediaAtmosphere {
                    Image(nsImage: atmosphere).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped().opacity(0.45)
                }
            }.allowsHitTesting(false).accessibilityHidden(true)
            LinearGradient(colors: [.black.opacity(0.16), .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false).accessibilityHidden(true)
            HStack(alignment: .bottom, spacing: 8) {
                Button { model.select(.music) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Group {
                            if let artwork = model.mediaArtwork { Image(nsImage: artwork).resizable().scaledToFill() }
                            else { Image(systemName: "music.note").font(.system(size: 14)).frame(maxWidth: .infinity, maxHeight: .infinity).background(.white.opacity(0.10)) }
                        }.frame(width: 35, height: 35).clipShape(RoundedRectangle(cornerRadius: 7)).shadow(color: .black.opacity(0.35), radius: 5, y: 2)
                        Text(model.mediaTitle).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                        Text(model.mediaArtist.isEmpty ? "음악" : model.mediaArtist).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).disabled(model.homeEditing)
                Button { model.controlMedia("toggle") } label: {
                    Image(systemName: model.mediaPlaying ? "pause.fill" : "play.fill")
                        .foregroundStyle(.black).frame(width: 32, height: 32).background(.white, in: Circle()).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(!model.mediaAvailable || model.mediaControlPending || model.homeEditing)
                    .accessibilityLabel(model.mediaPlaying ? "일시 정지" : "재생")
            }.padding(4)
        }.clipped()
    }
}

// shortcut: Cover dimensions, compact transport, and typography need reference comparison.
struct HomeMusicAlbumView: View {
    @ObservedObject var model: Model
    var body: some View {
        HStack(spacing: 8) {
            Button { model.select(.music) } label: {
                Group {
                    if let artwork = model.mediaArtwork { Image(nsImage: artwork).resizable().scaledToFill() }
                    else { Image(systemName: "music.note").font(.system(size: 20)).frame(maxWidth: .infinity, maxHeight: .infinity).background(.white.opacity(0.10)) }
                }.frame(width: 62, height: 62).clipShape(RoundedRectangle(cornerRadius: 10))
            }.buttonStyle(.plain).disabled(model.homeEditing).accessibilityLabel("음악 보기")
            VStack(alignment: .leading, spacing: 3) {
                Text(model.mediaTitle).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                Text(model.mediaArtist.isEmpty ? (model.mediaAlbum.isEmpty ? "음악" : model.mediaAlbum) : model.mediaArtist)
                    .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                if !model.mediaAlbum.isEmpty && !model.mediaArtist.isEmpty {
                    Text(model.mediaAlbum).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                HomeMusicProgressBar(model: model, opacity: 0.8)
                HStack(spacing: 7) {
                    Button { model.controlMedia("previous") } label: { Image(systemName: "backward.fill").frame(minWidth: 20, minHeight: 22).contentShape(Rectangle()) }.accessibilityLabel("이전 곡")
                    Button { model.controlMedia("toggle") } label: { Image(systemName: model.mediaPlaying ? "pause.fill" : "play.fill").frame(minWidth: 20, minHeight: 22).contentShape(Rectangle()) }.accessibilityLabel(model.mediaPlaying ? "일시 정지" : "재생")
                    Button { model.controlMedia("next") } label: { Image(systemName: "forward.fill").frame(minWidth: 20, minHeight: 22).contentShape(Rectangle()) }.accessibilityLabel("다음 곡")
                }.font(.system(size: 10)).buttonStyle(.plain)
                    .disabled(!model.mediaAvailable || model.mediaControlPending || model.homeEditing)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// shortcut: Button materials, cover placement, and narrow-width scaling need visual comparison.
struct HomeMusicRemoteView: View {
    @ObservedObject var model: Model

    private func control(_ symbol: String, label: String, action: String, size: CGFloat, prominent: Bool) -> some View {
        Button { model.controlMedia(action) } label: {
            Image(systemName: symbol).font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(prominent ? Color.black : Color.white)
                .frame(width: size, height: size)
                .background(prominent ? Color.white : Color.white.opacity(0.08), in: Circle())
                .overlay(Circle().stroke(.white.opacity(prominent ? 0.1 : 0.23), lineWidth: 1))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!model.mediaAvailable || model.mediaControlPending || model.homeEditing)
            .accessibilityLabel(label)
    }

    var body: some View {
        VStack(spacing: 2) {
            Button { model.select(.music) } label: {
                HStack(spacing: 6) {
                    Group {
                        if let artwork = model.mediaArtwork { Image(nsImage: artwork).resizable().scaledToFill() }
                        else { Image(systemName: "music.note").font(.system(size: 10)).frame(maxWidth: .infinity, maxHeight: .infinity).background(.white.opacity(0.10)) }
                    }.frame(width: 24, height: 24).clipShape(RoundedRectangle(cornerRadius: 5))
                    Text(model.mediaTitle).font(.system(size: 11, weight: .semibold)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                }
            }.buttonStyle(.plain).disabled(model.homeEditing)
            Spacer(minLength: 0)
            GeometryReader { geometry in
                let scale = min(1, max(0, geometry.size.width / 120))
                HStack(spacing: 0) {
                    control("backward.fill", label: "이전 곡", action: "previous", size: 36 * scale, prominent: false)
                    Spacer(minLength: 0)
                    control(model.mediaPlaying ? "pause.fill" : "play.fill", label: model.mediaPlaying ? "일시 정지" : "재생", action: "toggle", size: 48 * scale, prominent: true)
                    Spacer(minLength: 0)
                    control("forward.fill", label: "다음 곡", action: "next", size: 36 * scale, prominent: false)
                }.frame(width: geometry.size.width, height: geometry.size.height)
            }.frame(height: 48)
            Spacer(minLength: 0)
        }
    }
}

// shortcut: Source card proportions and decoration await comparison with the original.
struct HomeMusicSourceView: View {
    @ObservedObject var model: Model
    init(model: Model) { self.model = model }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 9) {
            Button { model.openMediaSource() } label: {
                Group {
                    if let icon = model.mediaSourceIcon { Image(nsImage: icon).resizable().scaledToFit() }
                    else { Image(systemName: "music.note").font(.system(size: 22)).frame(maxWidth: .infinity, maxHeight: .infinity).background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12)) }
                }.frame(width: 50, height: 50)
            }.buttonStyle(.plain).disabled(model.mediaSourceURL == nil || model.homeEditing)
                .accessibilityLabel("\(model.mediaSourceName) 열기")
            VStack(alignment: .leading, spacing: 4) {
                Text(model.mediaSourceName).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                Button { model.select(.music) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.mediaTitle).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Text(model.mediaArtist.isEmpty ? "음악" : model.mediaArtist).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).disabled(model.homeEditing)
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !model.mediaPlaying || reduceMotion)) { timeline in
                    HStack(spacing: 2) {
                        ForEach(0..<14, id: \.self) { index in
                            let height = rustHomeSourceWaveHeight(Int32(index), timeline.date.timeIntervalSinceReferenceDate,
                                                                 model.mediaPlaying ? 1 : 0, reduceMotion ? 1 : 0)
                            Capsule().fill((model.mediaArtwork == nil ? Color.white : Color(nsColor: model.mediaLightColor)).opacity(0.85))
                                .frame(width: 2.5, height: max(0, CGFloat(height)))
                        }
                    }.frame(height: 16).accessibilityHidden(true)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// shortcut: The layout and progress-bar styling are reconstructed from the widget's view structure; visual details are unverified.
struct HomeMusicTimeView: View {
    @ObservedObject var model: Model
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.25, paused: !model.mediaPlaying)) { _ in
            let duration = model.mediaDuration.isFinite ? max(0, model.mediaDuration) : 0
            let elapsed = model.currentMediaElapsed(at: ProcessInfo.processInfo.systemUptime)
            let progress = homeMusicProgress(known: model.mediaPositionKnown, elapsed: elapsed, duration: duration)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Group {
                        if let artwork = model.mediaArtwork { Image(nsImage: artwork).resizable().scaledToFill() }
                        else { Image(systemName: "music.note").font(.system(size: 12)).frame(maxWidth: .infinity, maxHeight: .infinity).background(.white.opacity(0.10)) }
                    }.frame(width: 28, height: 28).clipShape(RoundedRectangle(cornerRadius: 6))
                    Button { model.select(.music) } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(model.mediaTitle).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                            Text(model.mediaArtist.isEmpty ? "음악" : model.mediaArtist).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain).disabled(model.homeEditing)
                    Button { model.controlMedia("toggle") } label: {
                        Image(systemName: model.mediaPlaying ? "pause.fill" : "play.fill").frame(width: 22, height: 22).contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(!model.mediaAvailable || model.mediaControlPending || model.homeEditing)
                        .accessibilityLabel(model.mediaPlaying ? "일시 정지" : "재생")
                }
                Spacer(minLength: 0)
                HStack(alignment: .lastTextBaseline) {
                    Text(model.mediaPositionKnown ? homeMusicTime(elapsed) : "--:--").font(.system(size: 27, weight: .light)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    Spacer(minLength: 2)
                    if progress != nil { Text("−" + homeMusicTime(max(0, duration - elapsed))).font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary).lineLimit(1) }
                }
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.16))
                        if let progress { Capsule().fill(.white.opacity(0.8)).frame(width: max(0, geometry.size.width * progress)) }
                    }
                }.frame(height: 3).accessibilityHidden(true)
            }
        }
    }
}

// shortcut: disc details are a visual approximation pending reference comparison.
struct HomeMusicDiscView: View {
    @ObservedObject var model: Model
    init(model: Model) { self.model = model }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var discAngle = 0.0
    @State private var rotationStarted: TimeInterval?

    private func angle(at now: TimeInterval) -> Double {
        guard let start = rotationStarted else { return discAngle }
        return rustHomeDiscAngle(discAngle, max(0, now - start))
    }

    private func updateRotation() {
        let now = ProcessInfo.processInfo.systemUptime
        discAngle = angle(at: now)
        rotationStarted = model.mediaPlaying && !reduceMotion ? now : nil
    }

    var body: some View {
        HStack(spacing: 9) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !model.mediaPlaying || reduceMotion)) { _ in
                ZStack {
                    Circle().fill(LinearGradient(colors: [.black, .white.opacity(0.25), .black], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Circle().stroke(.white.opacity(0.18), lineWidth: 1).padding(5)
                    Circle().stroke(.white.opacity(0.12), lineWidth: 1).padding(10)
                    Group {
                        if let artwork = model.mediaArtwork { Image(nsImage: artwork).resizable().scaledToFill() }
                        else { Image(systemName: "music.note").font(.system(size: 11)).frame(maxWidth: .infinity, maxHeight: .infinity).background(.white.opacity(0.16)) }
                    }.frame(width: 29, height: 29).clipShape(Circle())
                }.frame(width: 66, height: 66)
                    .rotationEffect(.degrees(angle(at: ProcessInfo.processInfo.systemUptime)))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(model.mediaTitle).font(.system(size: 12, weight: .semibold)).lineLimit(2)
                Text(model.mediaArtist.isEmpty ? "음악" : model.mediaArtist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { updateRotation() }
        .onChange(of: model.mediaPlaying) { _, _ in updateRotation() }
        .onChange(of: reduceMotion) { _, _ in updateRotation() }
        .onDisappear { discAngle = angle(at: ProcessInfo.processInfo.systemUptime); rotationStarted = nil }
    }
}

struct HomeMusicWaveView: View {
    @ObservedObject var model: Model
    init(model: Model) { self.model = model }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.mediaTitle).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            Spacer(minLength: 0)
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !model.mediaPlaying || reduceMotion)) { timeline in
                let elapsed = model.currentMediaElapsed(at: ProcessInfo.processInfo.systemUptime)
                let progress = homeMusicProgress(known: model.mediaPositionKnown, elapsed: elapsed, duration: model.mediaDuration) ?? 0
                Canvas { context, size in
                    let count = 26
                    // shortcut: Scale down in unusually narrow containers; original narrow-layout behavior is unverified.
                    let scale = min(1, max(0, size.width / 153))
                    let barWidth = 3 * scale, step = 6 * scale
                    let startX = (size.width - 153 * scale) / 2
                    let activeCount = Int((progress * Double(count)).rounded())
                    let tint = model.mediaArtwork == nil ? Color.white : Color(nsColor: model.mediaLightColor)
                    for index in 0..<count {
                        let rawHeight = rustHomeMusicWaveHeight(Int32(index), timeline.date.timeIntervalSinceReferenceDate,
                                                              model.mediaPlaying ? 1 : 0, reduceMotion ? 1 : 0)
                        let height = min(size.height, max(0, CGFloat(rawHeight) * scale))
                        let rect = CGRect(x: startX + CGFloat(index) * step, y: (size.height - height) / 2,
                                          width: barWidth, height: height)
                        context.fill(Path(roundedRect: rect, cornerRadius: rect.width / 2),
                                     with: .color(index < activeCount ? tint : .white.opacity(0.26)))
                    }
                }.frame(height: 36).accessibilityHidden(true)
            }
        }
    }
}

// shortcut: proportions and texture of these cards need reference comparison.
struct HomeMusicRingView: View {
    @ObservedObject var model: Model
    init(model: Model) { self.model = model }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 9) {
            TimelineView(.animation(minimumInterval: 0.25, paused: !model.mediaPlaying || reduceMotion)) { _ in
                let elapsed = model.currentMediaElapsed(at: ProcessInfo.processInfo.systemUptime)
                let fraction = homeMusicProgress(known: model.mediaPositionKnown, elapsed: elapsed, duration: model.mediaDuration) ?? 0
                ZStack {
                    Circle().stroke(.white.opacity(0.16), lineWidth: 3)
                    Circle().trim(from: 0, to: fraction).stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
                    Group {
                        if let artwork = model.mediaArtwork { Image(nsImage: artwork).resizable().scaledToFill() }
                        else { Image(systemName: "music.note").font(.system(size: 14)).frame(maxWidth: .infinity, maxHeight: .infinity).background(.white.opacity(0.10)) }
                    }.frame(width: 45, height: 45).clipShape(Circle())
                }.frame(width: 58, height: 58)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(model.mediaTitle).font(.system(size: 12, weight: .semibold)).lineLimit(2)
                Text(model.mediaArtist.isEmpty ? "음악" : model.mediaArtist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct HomeMusicCassetteView: View {
    @ObservedObject var model: Model
    var body: some View {
        HStack(spacing: 9) {
            DashboardCassette(model: model).frame(width: 75, height: 53).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.mediaTitle).font(.system(size: 12, weight: .semibold)).lineLimit(2)
                Text(model.mediaArtist.isEmpty ? "음악" : model.mediaArtist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

enum HomeBackground: String, CaseIterable, Identifiable {
    case dynamic, album, hour, graphite, blue
    // Follow the reference HomeTexture enum's ordering in the editor.
    case aurora, mist, sand, silk, prism, fluted, paper, halftone, topo, ripple, neon, bokeh
    case marble, watercolor, linen, terrazzo, sunset, caustics, cosmos, ember, holo, lowpoly, opart, matcha
    var id: String { rawValue }
    var isTexture: Bool {
        switch self { case .fluted, .halftone, .linen, .paper, .sand, .opart, .mist, .silk, .ripple, .prism, .topo, .sunset, .marble, .holo, .watercolor, .matcha, .ember, .neon, .caustics, .lowpoly, .terrazzo, .cosmos, .bokeh, .aurora: return true; default: return false }
    }
    var title: String {
        switch self {
        case .dynamic: return "다이내믹"
        case .album: return "앨범 아트"
        case .hour: return "시간대"
        case .graphite: return "흑연"
        case .blue: return "푸른 빛"
        case .fluted: return "세로 골"
        case .halftone: return "하프톤"
        case .linen: return "리넨"
        case .paper: return "종이"
        case .sand: return "모래"
        case .opart: return "옵아트"
        case .mist: return "안개"
        case .silk: return "실크"
        case .ripple: return "물결"
        case .prism: return "프리즘"
        case .topo: return "등고선"
        case .sunset: return "노을"
        case .marble: return "대리석"
        case .holo: return "홀로그램"
        case .watercolor: return "수채화"
        case .matcha: return "말차"
        case .ember: return "불씨"
        case .neon: return "네온"
        case .caustics: return "물빛 반사"
        case .lowpoly: return "로우 폴리"
        case .terrazzo: return "테라조"
        case .cosmos: return "우주"
        case .bokeh: return "보케"
        case .aurora: return "오로라"
        }
    }
    var preview: LinearGradient {
        let colors: [Color]
        switch self {
        case .dynamic: colors = [.black, .blue.opacity(0.25), .black]
        case .album: colors = [.black, .pink.opacity(0.3), .black]
        case .hour: colors = [.black, .orange.opacity(0.25), .blue.opacity(0.25)]
        case .graphite: colors = [.black, .gray.opacity(0.35), .black]
        case .blue: colors = [.black, .blue.opacity(0.65), .black]
        case .fluted, .halftone, .linen: colors = [.black, .gray.opacity(0.2), .black]
        case .paper: colors = [.gray.opacity(0.5), .white.opacity(0.7)]
        case .sand: colors = [.brown.opacity(0.6), .orange.opacity(0.4)]
        case .opart: colors = [.black, .gray, .black]
        case .mist: colors = [.gray, .white, .blue.opacity(0.5)]
        case .silk: colors = [.brown.opacity(0.4), .white, .brown.opacity(0.3)]
        case .ripple: colors = [.blue.opacity(0.7), .cyan, .blue]
        case .prism: colors = [.pink.opacity(0.7), .cyan.opacity(0.7)]
        case .topo: colors = [.black, .teal, .black]
        case .sunset: colors = [.purple, .orange, .yellow]
        case .marble: colors = [.white, .gray, .white]
        case .holo: colors = [.pink, .cyan, .purple]
        case .watercolor: colors = [.pink.opacity(0.6), .blue.opacity(0.5), .green.opacity(0.5)]
        case .matcha: colors = [.green.opacity(0.4), .green.opacity(0.8)]
        case .ember: colors = [.black, .orange, .red]
        case .neon: colors = [.purple, .pink, .cyan]
        case .caustics: colors = [.cyan, .blue, .white]
        case .lowpoly: colors = [.blue, .purple]
        case .terrazzo: colors = [.white, .orange.opacity(0.5), .white]
        case .cosmos: colors = [.black, .purple, .blue]
        case .bokeh: colors = [.brown, .orange, .yellow]
        case .aurora: colors = [.pink, .purple, .cyan]
        }
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }
}
