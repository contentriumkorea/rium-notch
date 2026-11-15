import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum NotchTab: String, CaseIterable, Identifiable {
    case home, agents, dictation, clipboard, teleprompter
    var id: String { rawValue }
    var title: String {
        switch self { case .home: return "홈"; case .agents: return "작업"; case .dictation: return "받아쓰기"; case .clipboard: return "클립보드"; case .teleprompter: return "프롬프터" }
    }
    var icon: String {
        switch self { case .home: return "square.grid.2x2"; case .agents: return "bubble.left.and.bubble.right"; case .dictation: return "waveform"; case .clipboard: return "clipboard"; case .teleprompter: return "text.alignleft" }
    }
    var section: PanelSection? {
        switch self { case .home: return .home; case .agents: return .agents; case .dictation: return .dictation; case .clipboard: return .clipboard; case .teleprompter: return nil }
    }
    static func normalized(_ raw: [String]?) -> [NotchTab] {
        var result: [NotchTab] = [.home]
        for value in raw ?? [] {
            if let tab = NotchTab(rawValue: value), tab != .home, !result.contains(tab) { result.append(tab) }
        }
        for tab in NotchTab.allCases where !result.contains(tab) { result.append(tab) }
        return result
    }
}

enum HomeSlot: String, CaseIterable, Identifiable {
    case music, centre, weather, calendar
    var id: String { rawValue }
    var title: String { switch self { case .music: return "음악"; case .centre: return "중앙"; case .weather: return "날씨"; case .calendar: return "일정" } }
    var variants: [HomeVariant] {
        switch self {
        case .music: return [.init(id: "player", title: "플레이어", symbol: "play.circle"), .init(id: "artwork", title: "앨범 아트", symbol: "music.note"), .init(id: "lyrics", title: "가사", symbol: "text.quote")]
        case .centre: return [.init(id: "agent", title: "에이전트", symbol: "face.smiling"), .init(id: "today", title: "오늘", symbol: "calendar"), .init(id: "focus", title: "집중", symbol: "timer")]
        case .weather: return [.init(id: "now", title: "현재", symbol: "cloud.sun"), .init(id: "sentence", title: "문장", symbol: "text.alignleft"), .init(id: "forecast", title: "예보", symbol: "cloud.sun.fill")]
        case .calendar: return [.init(id: "next", title: "다음 일정", symbol: "calendar"), .init(id: "date", title: "날짜", symbol: "calendar"), .init(id: "clock", title: "시계", symbol: "clock")]
        }
    }
    var defaultVariant: String { variants[0].id }
}
struct HomeVariant: Identifiable {
    let id: String
    let title: String
    let symbol: String
}

struct EditableNotchTab: View {
    @ObservedObject var model: Model
    let tab: NotchTab
    private var content: some View {
        Button {
            if model.tabEditing { if tab != .home { model.selectedTab = tab } }
            else if let section = tab.section { model.select(section) }
            else { model.teleprompter.show() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.icon).frame(width: 16)
                if tab == .agents {
                    let count = model.agentItems.filter { ["작업 중", "활동 감지", "도구 실행 감지"].contains($0.state) || $0.state.hasPrefix("승인 대기") }.count
                    if count > 0 { Text("\(count)").font(.system(size: 10, weight: .semibold)).foregroundStyle(.black).padding(.horizontal, 6).padding(.vertical, 2).background(Color.blue, in: Capsule()) }
                }
                if tab == .clipboard && !model.clipboardItems.isEmpty { Text("\(model.clipboardItems.count)").font(.system(size: 10)).foregroundStyle(.secondary) }
                if !model.tabEditing, tab.section == model.section { Text(tab.title).lineLimit(1) }
            }
            .padding(.horizontal, 9).frame(minWidth: 52, minHeight: 28)
            .background(!model.tabEditing && tab.section != nil && tab.section == model.section ? Color.white.opacity(0.18) : Color.clear, in: Capsule())
            .overlay(Capsule().stroke(model.tabEditing && tab == model.selectedTab ? .white : .white.opacity(model.tabEditing ? 0.18 : 0), lineWidth: model.tabEditing && tab == model.selectedTab ? 1.5 : 1))
            .opacity(model.tabEditing && tab == .home ? 0.35 : 1)
        }.buttonStyle(.plain).help(tab.title).accessibilityLabel(tab.title)
    }
    var body: some View {
        if model.tabEditing && tab != .home {
            content.onDrag { model.draggingTab = tab; return NSItemProvider(object: tab.rawValue as NSString) }
                .onDrop(of: [UTType.text], delegate: NotchTabDrop(model: model, target: tab))
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

struct HomeSelectionOverlay: View {
    @ObservedObject var model: Model
    let slot: HomeSlot
    var body: some View {
        if model.homeEditing {
            Button { model.homeSelectedSlot = slot } label: {
                RoundedRectangle(cornerRadius: 25, style: .continuous).fill(Color.clear).contentShape(Rectangle())
                    .overlay(RoundedRectangle(cornerRadius: 25, style: .continuous).stroke(model.homeSelectedSlot == slot ? .white : .clear, lineWidth: 2.5).padding(-3))
            }.buttonStyle(.plain).accessibilityLabel("\(slot.title) 카드 선택")
        }
    }
}

struct HomeEditorOptions: View {
    @ObservedObject var model: Model
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                ForEach(HomeSlot.allCases) { slot in
                    Button(slot.title) { model.homeSelectedSlot = slot }
                        .foregroundStyle(model.homeSelectedSlot == slot ? .white : .secondary)
                        .frame(maxWidth: .infinity)
                }
            }.buttonStyle(.plain).font(.system(size: 11, weight: .semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(model.homeSelectedSlot.variants) { variant in
                        Button { model.setHomeVariant(variant.id, for: model.homeSelectedSlot) } label: {
                            VStack(spacing: 5) {
                                HomeVariantPreview(model: model, slot: model.homeSelectedSlot, variant: variant.id)
                                    .frame(width: 112, height: 64)
                                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(model.homeVariant(model.homeSelectedSlot) == variant.id ? .white : .clear, lineWidth: 2))
                                Text(variant.title).font(.system(size: 10, weight: .medium)).foregroundStyle(model.homeVariant(model.homeSelectedSlot) == variant.id ? .white : .secondary)
                            }
                        }.buttonStyle(.plain).accessibilityLabel("\(model.homeSelectedSlot.title) \(variant.title)")
                    }
                }.padding(3)
            }.frame(height: 87)
            Text("홈 배경").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(HomeBackground.allCases) { background in
                        Button { model.setHomeBackground(background) } label: {
                            VStack(spacing: 4) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10).fill(background.preview)
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
                        Text(model.lyricLines.last(where: { ($0.time ?? .infinity) <= model.mediaElapsed })?.text ?? "가사").font(.system(size: 7)).lineLimit(1)
                    } else if variant == "player" {
                        Capsule().fill(.white.opacity(0.18)).frame(height: 1)
                        HStack { Image(systemName: "backward.fill"); Spacer(); Image(systemName: model.mediaPlaying ? "pause.fill" : "play.fill"); Spacer(); Image(systemName: "forward.fill") }.font(.system(size: 6))
                    }
                case .centre:
                    Text(variant == "focus" ? "집중" : (variant == "today" ? "오늘" : "에이전트")).font(.system(size: 6)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if variant == "focus" { Text("25:00").font(.system(size: 17, weight: .light)).monospacedDigit() }
                    else if variant == "today" { Text(model.now, format: .dateTime.day()).font(.system(size: 17, weight: .light)) }
                    else { HStack { Spacer(); Image(systemName: "face.smiling.fill").font(.system(size: 22)).foregroundStyle(.blue); Spacer() } }
                case .weather:
                    Text(model.weatherCity.isEmpty ? "날씨" : model.weatherCity).font(.system(size: 6)).foregroundStyle(.secondary).lineLimit(1)
                    Text(model.weatherCondition).font(.system(size: 6)).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                    if variant == "sentence" { Text(model.weatherTemperature.map { String(format: "현재 %.0f°", $0) } ?? "날씨 정보 없음").font(.system(size: 8)).lineLimit(2) }
                    else if variant == "forecast" {
                        if mainWeatherPreview(model).isEmpty { Text("예보 없음").font(.system(size: 7)).foregroundStyle(.secondary) }
                        else { HStack { ForEach(Array(mainWeatherPreview(model).prefix(3))) { hour in VStack(spacing: 2) { Text(homeWeatherHour(hour.date, timeZoneID: model.weatherTimeZoneID)); Text(String(format: "%.0f°", hour.temperature)) }.font(.system(size: 6)); Spacer(minLength: 1) } } }
                    } else { Text(model.weatherTemperature.map { String(format: "%.0f°", $0) } ?? "—").font(.system(size: 17, weight: .light)) }
                case .calendar:
                    Text(variant == "next" ? "다음 일정" : (variant == "date" ? "날짜" : "시계")).font(.system(size: 6)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if variant == "date" { Text(model.now, format: .dateTime.day()).font(.system(size: 17, weight: .light)) }
                    else if variant == "clock" { Text(model.now, style: .time).font(.system(size: 14, weight: .light)).lineLimit(1).minimumScaleFactor(0.5) }
                    else { Text(model.agenda.events.first.map { agendaTimeLabel($0) } ?? "일정 없음").font(.system(size: 13, weight: .light)).lineLimit(1) }
                }
            }.padding(8)
        }.clipShape(RoundedRectangle(cornerRadius: 13))
    }
}
enum HomeBackground: String, CaseIterable, Identifiable {
    case dynamic, album, graphite, blue
    var id: String { rawValue }
    var title: String { switch self { case .dynamic: return "다이내믹"; case .album: return "앨범 아트"; case .graphite: return "흑연"; case .blue: return "푸른 빛" } }
    var preview: LinearGradient {
        let colors: [Color]
        switch self { case .dynamic: colors = [.black, .blue.opacity(0.25), .black]; case .album: colors = [.black, .pink.opacity(0.3), .black]; case .graphite: colors = [.black, .gray.opacity(0.35), .black]; case .blue: colors = [.black, .blue.opacity(0.65), .black] }
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }
}
