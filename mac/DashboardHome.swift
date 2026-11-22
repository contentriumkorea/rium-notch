import SwiftUI

@_silgen_name("rium_weather_dashboard_gauge")
private func rustWeatherDashboardGauge(_ temperature: Double) -> Double

// Dashboard layout reconstructed from the saved appearance preview. Geometry,
// animation and details are provisional until compared against the live app.
struct DashboardHome: View {
    @ObservedObject var model: Model
    @ObservedObject var agenda: AgendaModel
    var flightNamespace: Namespace.ID? = nil

    var body: some View {
        GeometryReader { geometry in
            let available = max(100, geometry.size.width - 3 * notchPanelSpacing)
            HStack(spacing: notchPanelSpacing) {
                music.frame(width: available * 0.39)
                weather.frame(width: available * 0.18)
                calendar.frame(width: available * 0.20)
                centre.frame(width: available * 0.23)
            }
            .background(alignment: .top) {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.white.opacity(0.045))
                    .frame(height: homeCardRowHeight(editing: false))
            }
        }.frame(height: homeCardRowHeight(editing: model.homeEditing))
    }

    private var music: some View {
        Group {
            if model.homeVariant(.music) == "disc" {
                HomeMusicDiscView(model: model).onTapGesture { if !model.homeEditing { model.select(.music) } }
            } else if model.homeVariant(.music) == "wave" {
                HomeMusicWaveView(model: model).onTapGesture { if !model.homeEditing { model.select(.music) } }
            } else if model.homeVariant(.music) == "ring" {
                HomeMusicRingView(model: model).onTapGesture { if !model.homeEditing { model.select(.music) } }
            } else if model.homeVariant(.music) == "cassette" {
                HomeMusicCassetteView(model: model).onTapGesture { if !model.homeEditing { model.select(.music) } }
            } else if model.homeVariant(.music) == "time" {
                HomeMusicTimeView(model: model)
            } else if model.homeVariant(.music) == "source" {
                HomeMusicSourceView(model: model)
            } else if model.homeVariant(.music) == "remote" {
                HomeMusicRemoteView(model: model)
            } else if model.homeVariant(.music) == "album" {
                HomeMusicAlbumView(model: model)
            } else if model.homeVariant(.music) == "ambient" {
                HomeMusicAmbientView(model: model)
            } else if model.homeVariant(.music) == "type" {
                HomeMusicTypeView(model: model).onTapGesture { if !model.homeEditing { model.select(.music) } }
            } else {
                HStack(spacing: 8) {
                    Group {
                        if model.homeVariant(.music) == "artwork" {
                            if let artwork = model.mediaArtwork {
                                Image(nsImage: artwork).resizable().scaledToFill()
                            } else {
                                Image(systemName: "music.note").font(.system(size: 24)).frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(.white.opacity(0.08))
                            }
                        } else {
                            DashboardCassette(model: model)
                        }
                    }.frame(width: 84, height: 60).clipped().clipShape(RoundedRectangle(cornerRadius: 6))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Button { if !model.homeEditing { model.select(.music) } } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.mediaTitle).font(.system(size: 13, weight: .bold)).lineLimit(1)
                                Text(model.mediaArtist.isEmpty ? "음악" : model.mediaArtist)
                                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain)
                        if model.homeVariant(.music) == "lyrics" {
                            Text(activeLyricLine(model.lyricLines, positionKnown: model.mediaPositionKnown, elapsed: model.mediaElapsed)?.text
                                 ?? (model.lyricsEnabled ? model.lyricsStatus : "가사를 켜면 여기에 표시됩니다."))
                                .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(2)
                        } else if model.homeVariant(.music) == "player" {
                            HomeMusicProgressBar(model: model, opacity: 0.7)
                            HStack(spacing: 5) {
                                transport("backward.fill", label: "이전 곡", action: "previous")
                                transport(model.mediaPlaying ? "pause.fill" : "play.fill", label: model.mediaPlaying ? "일시 정지" : "재생", action: "toggle")
                                transport("forward.fill", label: "다음 곡", action: "next")
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 94, maxHeight: 94, alignment: .leading)
        .riumGlassTile(radius: 20, homeSurface: true)
        .homeCardSelection(model, slot: .music)
    }

    private func transport(_ symbol: String, label: String, action: String) -> some View {
        Button { model.controlMedia(action) } label: {
            Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
                .frame(maxWidth: .infinity).frame(height: 20)
                .background(LinearGradient(colors: [.white.opacity(0.18), .black.opacity(0.18)], startPoint: .top, endPoint: .bottom), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.10), lineWidth: 0.6))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!model.mediaAvailable || model.mediaControlPending || model.homeEditing)
            .accessibilityLabel(label)
    }

    private var weather: some View {
        Button { model.select(.weather) } label: {
            if !model.weatherShowingStatus && model.homeVariant(.weather) == "illustrated" {
                HomeWeatherIllustratedView(model: model)
                    .frame(maxWidth: .infinity, minHeight: 94, maxHeight: 94, alignment: .topLeading)
                    .riumGlassTile(radius: 20, homeSurface: true)
            } else if !model.weatherShowingStatus && ["sky", "curve", "range", "days"].contains(model.homeVariant(.weather)) {
                HomeWeatherVisual(model: model, variant: model.homeVariant(.weather))
                    .frame(maxWidth: .infinity, minHeight: 94, maxHeight: 94, alignment: .topLeading)
                    .riumGlassTile(radius: 20, homeSurface: true)
            } else {
                HStack(spacing: 6) {
                    DashboardTemperatureGauge(temperature: model.weatherShowingStatus ? nil : model.weatherTemperature)
                        .frame(width: 42, height: 42).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        if !model.weatherShowingStatus, ["rain", "feels", "humidity", "wind"].contains(model.homeVariant(.weather)) {
                            let metric = homeWeatherMetric(model, variant: model.homeVariant(.weather))
                            Text(metric.value).font(.system(size: 17, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
                            Text(metric.label).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                        } else if !model.weatherShowingStatus, let temperature = model.weatherTemperature {
                            Text(String(format: "%.0f°", temperature.rounded())).font(.system(size: 23, weight: .bold))
                            if model.homeVariant(.weather) == "sentence" {
                                Text(model.weatherCondition).font(.system(size: 9)).lineLimit(2)
                            } else if model.homeVariant(.weather) == "forecast", let hour = mainWeatherPreview(model).first {
                                Text("\(homeWeatherHour(hour.date, timeZoneID: model.weatherTimeZoneID))시 \(String(format: "%.0f°", hour.temperature))")
                                    .font(.system(size: 9)).lineLimit(1)
                            } else {
                                Text(model.weatherCity.isEmpty ? "날씨" : model.weatherCity).font(.system(size: 10)).lineLimit(1)
                            }
                        } else {
                            Text("날씨").font(.system(size: 11, weight: .semibold))
                            Text(model.weatherText).font(.system(size: 9)).lineLimit(2)
                        }
                    }.foregroundStyle(.white)
                }.frame(maxWidth: .infinity, minHeight: 94, maxHeight: 94, alignment: .leading)
                    .riumGlassTile(radius: 20, homeSurface: true)
            }
        }.buttonStyle(.plain).modifier(HomeNotificationSlot(model: model, slot: .weather))
            .homeCardSelection(model, slot: .weather)
    }

    private var calendar: some View {
        Button { model.select(.agenda) } label: {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.97, green: 0.93, blue: 0.69))
                    .rotationEffect(.degrees(-2))
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 2)
                VStack(alignment: .leading, spacing: 3) {
                    if model.homeVariant(.calendar) == "day" {
                        HomeCalendarDayView(agenda: agenda, now: model.now)
                    } else if model.homeVariant(.calendar) == "agenda" {
                        HomeAgendaListView(agenda: agenda, now: model.now, ink: Color(red: 0.09, green: 0.15, blue: 0.31))
                    } else if model.homeVariant(.calendar) == "countdown" {
                        HomeCalendarCountdownView(agenda: agenda, now: model.now, ink: Color(red: 0.09, green: 0.15, blue: 0.31))
                    } else if model.homeVariant(.calendar) == "dial" {
                        HomeCalendarDialView(active: model.expanded, ink: Color(red: 0.09, green: 0.15, blue: 0.31))
                    } else if model.homeVariant(.calendar) == "ringClock" {
                        HomeCalendarRingClockView(ink: Color(red: 0.09, green: 0.15, blue: 0.31))
                    } else if model.homeVariant(.calendar) == "week" {
                        HomeCalendarWeekView(agenda: agenda, now: model.now, ink: Color(red: 0.09, green: 0.15, blue: 0.31))
                    } else if model.homeVariant(.calendar) == "month" {
                        HomeCalendarMonthView(agenda: agenda, now: model.now, ink: Color(red: 0.09, green: 0.15, blue: 0.31))
                    } else if model.homeVariant(.calendar) == "clock" {
                        Text(model.now, style: .time).font(.system(size: 16, weight: .bold))
                        Text(model.now, style: .date).font(.system(size: 10, weight: .medium))
                    } else if model.homeVariant(.calendar) == "date" {
                        Text(model.now, format: .dateTime.month().day()).font(.system(size: 16, weight: .bold))
                        Text(model.now, format: .dateTime.weekday(.wide)).font(.system(size: 10, weight: .medium))
                    } else if let event = agenda.events.first {
                        Text(agendaTimeLabel(event)).font(.system(size: 16, weight: .bold)).lineLimit(1)
                        Text(event.title).font(.system(size: 11, weight: .semibold)).lineLimit(2)
                        Text(agendaRelativeLabel(event, now: model.now)).font(.system(size: 9)).lineLimit(1)
                    } else {
                        Text("다음 일정").font(.system(size: 12, weight: .bold))
                        Text(agenda.calendarStatus).font(.system(size: 10)).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }.foregroundStyle(Color(red: 0.09, green: 0.15, blue: 0.31))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(8)
                Rectangle().fill(Color.white.opacity(0.45)).frame(width: 44, height: 6).rotationEffect(.degrees(-3)).offset(y: -2)
            }.padding(5).frame(maxWidth: .infinity, minHeight: 94, maxHeight: 94)
                .riumGlassTile(radius: 20, homeSurface: true)
        }.buttonStyle(.plain).modifier(HomeNotificationSlot(model: model, slot: .calendar))
            .homeCardSelection(model, slot: .calendar)
    }

    private var centre: some View {
        Button { if model.homeVariant(.centre) == "lumi" { return } else if model.homeVariant(.centre) == "note" { model.editHomeNote() } else if model.homeVariant(.centre) == "agent" && model.homeShowsPersonalAssistant { model.select(.assistant) } else { model.select(homeCentreDestination(model.homeVariant(.centre))) } } label: {
            VStack(alignment: .leading, spacing: 6) {
                if model.homeVariant(.centre) == "focus" {
                    Text("집중 타이머").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(model.timerState == 0 ? String(format: "%02d:00", model.pomodoroFocus)
                         : String(format: "%02llu:%02llu", model.timerRemaining / 60, model.timerRemaining % 60))
                        .font(.system(size: 20, weight: .bold, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.7)
                } else if model.homeVariant(.centre) == "today" {
                    Text("오늘").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(model.now, style: .date).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                } else if model.homeVariant(.centre) == "note" {
                    Text("메모").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(model.homeNote.isEmpty ? "메모 추가" : model.homeNote).font(.system(size: 11)).lineLimit(3)
                } else if model.homeVariant(.centre) == "lumi" {
                    HomeLumiRest(now: model.now)
                } else {
                    Text("에이전트").font(.system(size: 11)).foregroundStyle(.secondary)
                    let active = activeAgentSessionCount(model.agentItems, assistant: model.assistantIndicator, assistantThread: model.assistant.observationThreadID)
                    HStack(spacing: 5) {
                        DashboardAgentLamps(agents: model.agentItems, assistant: model.assistantIndicator,
                                            assistantThread: model.assistant.observationThreadID, assistantState: model.assistantStateLabel)
                        Text(String(format: "%02d", active)).font(.system(size: 20, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 4).background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                        Text("작업").font(.system(size: 9)).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        focusedAgentFace
                    }
                    if model.homeShowsPersonalAssistant {
                        Text("Codex · \(model.assistantStateLabel)").font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                    } else if let agent = model.homeExternalAgent {
                        Text("\(agent.providerName) · \(agent.state)").font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity, minHeight: 94, maxHeight: 94, alignment: .topLeading)
                .riumGlassTile(radius: 20, homeSurface: true)
        }.buttonStyle(.plain).homeCardSelection(model, slot: .centre)
    }
    @ViewBuilder private var focusedAgentFace: some View {
        if model.homeShowsPersonalAssistant {
            let state = model.assistantStateLabel
            let session = AgentSessionKey(source: "", id: model.assistantAnimationID)
            CollapsedAgentFace(waiting: agentNeedsAttention(state), state: state, agentID: session.id, size: 33)
                .frame(width: 33, height: 33)
                .modifier(AgentFlightGeometry(namespace: flightNamespace, session: session, enabled: true))
                .accessibilityHidden(true)
        } else if let agent = model.homeExternalAgent {
            CollapsedAgentFace(waiting: agentNeedsAttention(agent.state), source: agent.source,
                               state: agent.state, agentID: agent.id, size: 33)
                .id(agent.sessionKey)
                .frame(width: 33, height: 33)
                .modifier(AgentFlightGeometry(namespace: flightNamespace, session: agent.sessionKey, enabled: true))
                .accessibilityHidden(true)
        }
    }
}

private struct DashboardTemperatureGauge: View {
    let temperature: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let reading = rustWeatherDashboardGauge(temperature ?? .nan)
        let fraction = reading.isFinite ? reading : 0
        DashboardGaugeDrawing(fraction: fraction, available: reading.isFinite)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: fraction)
    }
}

private struct DashboardGaugeDrawing: View, Animatable {
    var fraction: Double
    let available: Bool
    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height * 0.57)
            let radius = min(size.width, size.height) * 0.43
            for tick in 0...12 {
                let angle = (145 + 250 * Double(tick) / 12) * .pi / 180
                let major = tick % 3 == 0
                let inner = radius * (major ? 0.70 : 0.80)
                var line = Path()
                line.move(to: CGPoint(x: center.x + inner * CGFloat(cos(angle)), y: center.y + inner * CGFloat(sin(angle))))
                line.addLine(to: CGPoint(x: center.x + radius * CGFloat(cos(angle)), y: center.y + radius * CGFloat(sin(angle))))
                context.stroke(line, with: .color(.white.opacity(major ? 0.9 : 0.55)),
                               style: StrokeStyle(lineWidth: major ? 2 : 1, lineCap: .round))
            }
            let angle = (145 + 250 * fraction) * .pi / 180
            var needle = Path()
            needle.move(to: center)
            needle.addLine(to: CGPoint(x: center.x + radius * 0.78 * CGFloat(cos(angle)), y: center.y + radius * 0.78 * CGFloat(sin(angle))))
            context.stroke(needle, with: .color(available ? .orange : .gray), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            context.fill(Path(ellipseIn: CGRect(x: center.x - 3.5, y: center.y - 3.5, width: 7, height: 7)), with: .color(.black))
        }
    }
}

private struct DashboardAgentLamps: View {
    let agents: [AgentActivity]
    let assistant: AssistantIndicator
    let assistantThread: String?
    let assistantState: String
    // shortcut: lamp-to-session assignment is inferred from the dashboard preview.
    private func color(_ index: Int) -> Color {
        var states = agents.map(\.state)
        if assistant != .off {
            if let thread = assistantThread, let index = agents.firstIndex(where: { $0.source == "codex" && $0.id == thread }) {
                states[index] = assistantState
            } else { states.insert(assistantState, at: 0) }
        }
        guard index < states.count else { return .gray.opacity(0.25) }
        let state = states[index]
        if agentNeedsAttention(state) { return .orange }
        if state == "실패" { return .red }
        if ["작업 중", "도구 실행 중", "활동 감지", "도구 실행 감지"].contains(state) { return .green }
        return .gray.opacity(0.35)
    }
    var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { column in
                        let light = color(row * 3 + column)
                        Circle().fill(light).frame(width: 5, height: 5)
                            .overlay(Circle().stroke(.black.opacity(0.55), lineWidth: 0.5))
                            .shadow(color: light.opacity(0.45), radius: 2)
                    }
                }
            }
        }.accessibilityHidden(true)
    }
}

struct DashboardCassette: View {
    @ObservedObject var model: Model
    init(model: Model) { self.model = model }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: !model.mediaPlaying || reduceMotion)) { _ in
            let angle = reduceMotion ? 0 : model.currentMediaElapsed(at: ProcessInfo.processInfo.systemUptime) * 90
            Canvas { context, size in
                let sx = size.width / 100, sy = size.height / 70
                context.scaleBy(x: sx, y: sy)
                let shell = Path(roundedRect: CGRect(x: 1, y: 2, width: 98, height: 66), cornerRadius: 7)
                context.fill(shell, with: .color(Color(red: 0.91, green: 0.72, blue: 0.68)))
                context.fill(Path(roundedRect: CGRect(x: 8, y: 8, width: 84, height: 12), cornerRadius: 5), with: .color(.white.opacity(0.24)))
                context.fill(Path(roundedRect: CGRect(x: 18, y: 26, width: 64, height: 25), cornerRadius: 12), with: .color(.black.opacity(0.85)))
                for x in [CGFloat(32), CGFloat(68)] {
                    var wheel = context
                    wheel.translateBy(x: x, y: 38.5); wheel.rotate(by: .degrees(angle)); wheel.translateBy(x: -x, y: -38.5)
                    wheel.fill(Path(ellipseIn: CGRect(x: x - 9, y: 29.5, width: 18, height: 18)), with: .color(.white.opacity(0.9)))
                    wheel.fill(Path(ellipseIn: CGRect(x: x - 3, y: 35.5, width: 6, height: 6)), with: .color(.black))
                    for spoke in 0..<6 {
                        let theta = Double(spoke) * .pi / 3
                        var line = Path(); line.move(to: CGPoint(x: x, y: 38.5))
                        line.addLine(to: CGPoint(x: x + CGFloat(cos(theta)) * 8, y: 38.5 + CGFloat(sin(theta)) * 8))
                        wheel.stroke(line, with: .color(.black.opacity(0.75)), lineWidth: 1.5)
                    }
                }
            }
        }
    }
}
