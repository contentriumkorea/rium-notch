import Foundation
import AppKit
import UniformTypeIdentifiers

func eventIntersectsCalendarDay(start: Date, end: Date, dayStart: Date, dayEnd: Date) -> Bool {
    guard dayEnd > dayStart, end >= start else { return false }
    if start == end { return start >= dayStart && start < dayEnd }
    return start < dayEnd && end > dayStart
}

func eventIsUpcoming(start: Date, end: Date, now: Date, through: Date) -> Bool {
    (end > now || start >= now) && start < through
}

func eventIsRemainingToday(start: Date, end: Date, now: Date, calendar: Calendar) -> Bool {
    guard end >= start, end > now,
          let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return false }
    return start < tomorrow
}

private struct GoogleCalendarEntry: Decodable {
    let id: String
    let backgroundColor: String?
    let primary: Bool?
    let selected: Bool?
}

private struct GoogleCalendarEvent: Decodable {
    struct Bound: Decodable {
        let date: String?
        let dateTime: String?
        func localDate(in calendar: Calendar) -> Date? {
            if let dateTime { return googleInstant(dateTime) }
            return date.flatMap { googleDay($0, in: calendar) }
        }
    }
    let id: String
    let summary: String?
    let status: String?
    let start: Bound?
    let end: Bound?

    func row(calendar: GoogleCalendarEntry, local: Calendar) -> AgendaModel.Item? {
        guard status != "cancelled", let start, let end,
              let first = start.localDate(in: local), let last = end.localDate(in: local), last >= first
        else { return nil }
        let allDay = start.date != nil
        let color = calendar.backgroundColor.flatMap { parseCalendarColor($0) }
        return .init(id: "\(calendar.id.count):\(calendar.id)\(id)", title: summary ?? "제목 없음",
                     subtitle: allDay ? "종일" : first.formatted(date: .abbreviated, time: .shortened),
                     start: first, end: last, allDay: allDay, color: color)
    }
}

private struct GoogleTaskList: Decodable {
    let id: String
    let title: String?
}

private struct GoogleTask: Decodable {
    let id: String
    let title: String?
    let due: String?
    let status: String?
    let deleted: Bool?

    func row(in list: GoogleTaskList, calendar: Calendar) -> AgendaModel.Item? {
        guard status != "completed", deleted != true else { return nil }
        let date = due.flatMap { googleDay(String($0.prefix(10)), in: calendar) }
        let label = list.title ?? ""
        let subtitle = [label, date?.formatted(date: .abbreviated, time: .omitted) ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
        return .init(id: "\(list.id.count):\(list.id)\(id)", title: title ?? "제목 없음", subtitle: subtitle,
                     start: date, taskLocation: .init(list: list.id, task: id), taskListTitle: list.title)
    }
}

private func googleInstant(_ text: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: text) { return date }
    formatter.formatOptions = .withInternetDateTime
    return formatter.date(from: text)
}

private func googleDay(_ text: String, in calendar: Calendar) -> Date? {
    let parts = text.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    var gregorian = Calendar(identifier: .gregorian)
    gregorian.timeZone = calendar.timeZone
    return gregorian.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
}

private func parseCalendarColor(_ text: String) -> NSColor? {
    guard text.hasPrefix("#"), text.count == 7, let hex = UInt32(text.dropFirst(), radix: 16) else { return nil }
    return NSColor(srgbRed: CGFloat(hex >> 16) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                   blue: CGFloat(hex & 255) / 255, alpha: 1)
}

struct GoogleAgendaWindow {
    let calendar: Calendar
    let now: Date
    let day: DateInterval
    let week: DateInterval
    let month: DateInterval
    let upcomingEnd: Date

    init(now: Date, calendar: Calendar) {
        self.calendar = calendar
        self.now = now
        day = calendar.dateInterval(of: .day, for: now) ?? DateInterval(start: now, duration: 86_400)
        week = calendar.dateInterval(of: .weekOfYear, for: now) ?? day
        month = calendar.dateInterval(of: .month, for: now) ?? day
        upcomingEnd = calendar.date(byAdding: .day, value: 7, to: now) ?? week.end
    }

    func datesWithEvents(_ rows: [AgendaModel.Item], interval: DateInterval) -> Set<Date> {
        var day = interval.start
        var result = Set<Date>()
        while day < interval.end, let next = calendar.date(byAdding: .day, value: 1, to: day), next > day {
            if rows.contains(where: { row in
                guard let start = row.start, let end = row.end else { return false }
                return eventIntersectsCalendarDay(start: start, end: end, dayStart: day, dayEnd: next)
            }) { result.insert(day) }
            day = next
        }
        return result
    }

    var query: [URLQueryItem] {
        let formatter = ISO8601DateFormatter()
        return [
            .init(name: "timeMin", value: formatter.string(from: min(day.start, week.start, month.start))),
            .init(name: "timeMax", value: formatter.string(from: max(upcomingEnd, week.end, month.end))),
            .init(name: "singleEvents", value: "true"), .init(name: "orderBy", value: "startTime")
        ]
    }
}

final class AgendaModel: ObservableObject {
    enum Addition: Equatable { case event, task }
    struct TaskLocation { let list: String; let task: String }
    struct Item: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        var start: Date? = nil
        var end: Date? = nil
        var allDay: Bool = false
        var color: NSColor? = nil
        var taskLocation: TaskLocation? = nil
        var taskListTitle: String? = nil
    }

    var onAdded: ((Addition) -> Void)?
    @Published var events: [Item] = []
    @Published var tasks: [Item] = []
    @Published private(set) var todayEvents: [Item] = []
    @Published private(set) var todayEventCount = 0
    @Published private(set) var weekEventDays: Set<Date> = []
    @Published private(set) var monthEventDays: Set<Date> = []
    @Published private(set) var googleConnected = false
    @Published private(set) var calendarRequesting = false
    @Published private(set) var calendarLoading = false
    @Published private(set) var mutationInProgress = false
    @Published var calendarStatus = "Google 계정 연결 필요"
    @Published var tasksStatus = "Google 계정 연결 필요"
    var calendarReadable: Bool { googleConnected }
    var calendarActionTitle: String { googleConnected ? "새로고침" : "Google 로그인" }
    private var client: GoogleAgendaClient?
    private var session: GoogleAgendaToken?
    private var login: GoogleAgendaLogin?
    private var started = false
    private var refreshGeneration = 0

    init(autoRefresh: Bool = true) { if autoRefresh { start() } }

    func start() {
        guard !started else { return }
        started = true
        client = GoogleAgendaKeychain.load(GoogleAgendaClient.self, account: "client")
        if client != nil { session = GoogleAgendaKeychain.load(GoogleAgendaToken.self, account: "session") }
        googleConnected = session != nil
        refreshAuthorized()
    }

    func invalidateToday() {
        todayEvents = []; todayEventCount = 0; weekEventDays = []; monthEventDays = []
    }

    func loadCalendar() {
        guard !calendarRequesting, !calendarLoading, !mutationInProgress else { return }
        if googleConnected { refreshAuthorized(); return }
        if let client { signIn(client); return }
        let panel = NSOpenPanel()
        panel.title = "Google 데스크톱 OAuth 설정 가져오기"
        panel.message = "Calendar와 Tasks API가 활성화된 Google Cloud 프로젝트의 데스크톱 앱 OAuth JSON을 선택하세요."
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        calendarRequesting = true
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard let self else { return }
            self.calendarRequesting = false
            guard response == .OK, let url = panel.url else { return }
            do {
                guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? .max) <= 131_072 else {
                    throw GoogleAgendaError.configuration
                }
                guard let client = try? GoogleAgendaClient.configuration(from: Data(contentsOf: url)) else {
                    throw GoogleAgendaError.configuration
                }
                try GoogleAgendaKeychain.save(client, account: "client")
                self.client = client
                self.signIn(client)
            } catch { self.calendarStatus = error.localizedDescription }
        }
    }

    private func signIn(_ client: GoogleAgendaClient) {
        calendarRequesting = true
        calendarStatus = "브라우저에서 Google 로그인 진행 중…"
        let login = GoogleAgendaLogin()
        self.login = login
        do {
            try login.start(client) { [weak self] result in
                guard let self else { return }
                self.login = nil
                Task { @MainActor in
                    defer { self.calendarRequesting = false }
                    do {
                        let (code, redirect, verifier) = try result.get()
                        let session = try await client.exchange(code: code, redirect: redirect, verifier: verifier)
                        try GoogleAgendaKeychain.save(session, account: "session")
                        self.session = session
                        self.googleConnected = true
                        self.refreshAuthorized()
                    } catch { self.calendarStatus = error.localizedDescription }
                }
            }
        } catch {
            self.login = nil
            calendarRequesting = false
            calendarStatus = GoogleAgendaError.listener.localizedDescription
        }
    }

    func disconnectGoogle() {
        guard !calendarRequesting, !mutationInProgress else { return }
        do {
            try GoogleAgendaKeychain.disconnect()
            clearSession(status: "Google 계정 연결 필요")
        } catch { calendarStatus = error.localizedDescription }
    }

    private func clearSession(status: String) {
        refreshGeneration &+= 1
        session = nil
        googleConnected = false
        calendarLoading = false
        events = []; tasks = []; invalidateToday()
        calendarStatus = status; tasksStatus = "Google 계정 연결 필요"
    }

    private func handleExpiredSession(_ error: Error) -> Bool {
        guard case GoogleAgendaError.expired = error else { return false }
        try? GoogleAgendaKeychain.disconnect()
        clearSession(status: error.localizedDescription)
        return true
    }

    func refreshAuthorized() {
        guard let client, let session, !calendarLoading, !mutationInProgress else { return }
        refreshGeneration &+= 1
        let generation = refreshGeneration
        let window = GoogleAgendaWindow(now: Date(), calendar: .current)
        calendarLoading = true
        calendarStatus = "일정 불러오는 중…"
        tasksStatus = "할 일 불러오는 중…"
        Task { @MainActor in
            do {
                let renewed = try await client.refresh(session)
                guard generation == self.refreshGeneration else { return }
                try self.cacheRenewal(renewed, previous: session)
                async let calendars = self.fetchCalendar(window: window, token: renewed.accessToken)
                async let tasks = self.fetchTasks(calendar: window.calendar, token: renewed.accessToken)
                let (calendarResult, taskResult) = await (calendars, tasks)
                guard generation == self.refreshGeneration else { return }
                self.calendarLoading = false
                switch calendarResult {
                case .success(let events): self.publishEvents(events, window: window)
                case .failure(let error):
                    if self.handleExpiredSession(error) { return }
                    self.calendarStatus = error.localizedDescription
                }
                switch taskResult {
                case .success(let rows): self.publishTasks(rows)
                case .failure(let error):
                    if !self.handleExpiredSession(error) { self.tasksStatus = error.localizedDescription }
                }
            } catch {
                guard generation == self.refreshGeneration else { return }
                self.calendarLoading = false
                if !self.handleExpiredSession(error) {
                    self.calendarStatus = error.localizedDescription
                    self.tasksStatus = error.localizedDescription
                }
            }
        }
    }

    private func cacheRenewal(_ renewed: GoogleAgendaToken, previous: GoogleAgendaToken) throws {
        if renewed != previous {
            try GoogleAgendaKeychain.save(renewed, account: "session")
            session = renewed
        }
    }

    private func fetchCalendar(window: GoogleAgendaWindow, token: String) async -> Result<[Item], Error> {
        do {
            let host = "www.googleapis.com"
            let calendars = try await GoogleAgendaClient.pages(GoogleCalendarEntry.self, host: host,
                path: ["calendar", "v3", "users", "me", "calendarList"], token: token,
                query: [.init(name: "minAccessRole", value: "reader")])
            let selected = calendars.filter { $0.primary == true || $0.selected == true }
            var rows: [Item] = []
            for calendar in selected {
                let events = try await GoogleAgendaClient.pages(GoogleCalendarEvent.self, host: host,
                    path: ["calendar", "v3", "calendars", calendar.id, "events"], token: token, query: window.query)
                rows += events.compactMap { $0.row(calendar: calendar, local: window.calendar) }
            }
            return .success(rows)
        } catch { return .failure(error) }
    }

    private func fetchTasks(calendar: Calendar, token: String) async -> Result<[Item], Error> {
        do {
            let host = "tasks.googleapis.com"
            let lists = try await GoogleAgendaClient.pages(GoogleTaskList.self, host: host,
                path: ["tasks", "v1", "users", "@me", "lists"], token: token)
            var rows: [Item] = []
            for list in lists {
                let tasks = try await GoogleAgendaClient.pages(GoogleTask.self, host: host,
                    path: ["tasks", "v1", "lists", list.id, "tasks"], token: token,
                    query: [.init(name: "showCompleted", value: "false")])
                rows += tasks.compactMap { $0.row(in: list, calendar: calendar) }
            }
            return .success(rows)
        } catch { return .failure(error) }
    }

    func publishEvents(_ rows: [Item], window: GoogleAgendaWindow) {
        let ordered = rows.sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
        events = Array(ordered.filter { row in
            guard let start = row.start, let end = row.end else { return false }
            return eventIsUpcoming(start: start, end: end, now: window.now, through: window.upcomingEnd)
        }.prefix(20))
        todayEvents = ordered.filter { row in
            guard let start = row.start, let end = row.end else { return false }
            return eventIntersectsCalendarDay(start: start, end: end, dayStart: window.day.start, dayEnd: window.day.end)
        }
        todayEventCount = todayEvents.count
        weekEventDays = window.datesWithEvents(ordered, interval: window.week)
        monthEventDays = window.datesWithEvents(ordered, interval: window.month)
        calendarStatus = events.isEmpty ? "다가오는 일정 없음" : "앞으로 7일"
    }

    private func publishTasks(_ rows: [Item]) {
        tasks = rows.sorted { left, right in
            if left.start != right.start { return (left.start ?? .distantFuture) < (right.start ?? .distantFuture) }
            return left.title.localizedStandardCompare(right.title) == .orderedAscending
        }
        tasksStatus = tasks.isEmpty ? "미완료 항목 없음" : "미완료 항목"
    }

    private func mutate(_ type: Addition, perform: @escaping (String) async throws -> Void, success: @escaping () -> Void) {
        guard let client, let session, !calendarLoading, !mutationInProgress else { return }
        mutationInProgress = true
        Task { @MainActor in
            do {
                let renewed = try await client.refresh(session)
                try self.cacheRenewal(renewed, previous: session)
                try await perform(renewed.accessToken)
                success()
                self.mutationInProgress = false
                self.refreshAuthorized()
            } catch {
                self.mutationInProgress = false
                if !self.handleExpiredSession(error) {
                    if type == .event { self.calendarStatus = error.localizedDescription }
                    else { self.tasksStatus = error.localizedDescription }
                }
            }
        }
    }

    func completeTask(_ item: Item) {
        guard let location = item.taskLocation, tasks.contains(where: { $0.id == item.id }) else { return }
        mutate(.task) { token in
            _ = try await GoogleAgendaClient.request(GoogleTask.self, host: "tasks.googleapis.com",
                path: ["tasks", "v1", "lists", location.list, "tasks", location.task], token: token,
                method: "PATCH", body: ["status": "completed"])
        } success: { [weak self] in
            guard let self else { return }
            self.publishTasks(self.tasks.filter { $0.id != item.id })
        }
    }

    func addTask() {
        guard googleConnected, !calendarLoading, !mutationInProgress,
              let input = agendaEntry(title: "Google Tasks에 추가", timed: false) else { return }
        var body: [String: Any] = ["title": input.title]
        if let date = input.date {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.dateFormat = "yyyy-MM-dd"
            body["due"] = formatter.string(from: date) + "T00:00:00.000Z"
        }
        mutate(.task) { token in
            _ = try await GoogleAgendaClient.request(GoogleTask.self, host: "tasks.googleapis.com",
                path: ["tasks", "v1", "lists", "@default", "tasks"], token: token,
                method: "POST", body: body)
        } success: { [weak self] in self?.onAdded?(.task) }
    }

    func addEvent() {
        guard googleConnected, !calendarLoading, !mutationInProgress,
              let input = agendaEntry(title: "Google Calendar에 추가", timed: true), let start = input.date
        else { return }
        let formatter = ISO8601DateFormatter()
        let body: [String: Any] = [
            "summary": input.title, "start": ["dateTime": formatter.string(from: start)],
            "end": ["dateTime": formatter.string(from: start.addingTimeInterval(3600))]
        ]
        mutate(.event) { token in
            _ = try await GoogleAgendaClient.request(GoogleCalendarEvent.self, host: "www.googleapis.com",
                path: ["calendar", "v3", "calendars", "primary", "events"], token: token, method: "POST", body: body)
        } success: { [weak self] in self?.onAdded?(.event) }
    }

    private func agendaEntry(title: String, timed: Bool) -> (title: String, date: Date?)? {
        let alert = NSAlert(); alert.messageText = title
        let field = NSTextField(frame: NSRect(x: 0, y: 62, width: 270, height: 24))
        field.placeholderString = timed ? "일정 제목" : "할 일 제목"
        let date = NSDatePicker(frame: NSRect(x: 0, y: 0, width: 270, height: 24))
        date.datePickerStyle = .textFieldAndStepper
        date.datePickerElements = timed ? [.yearMonthDay, .hourMinute] : [.yearMonthDay]
        date.dateValue = Date().addingTimeInterval(timed ? 3600 : 0)
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 270, height: 86))
        view.addSubview(field); view.addSubview(date)
        let optionalDate = NSButton(checkboxWithTitle: "마감일 지정", target: nil, action: nil)
        if !timed {
            optionalDate.frame = NSRect(x: 0, y: 30, width: 160, height: 24)
            view.addSubview(optionalDate)
            date.bind(.enabled, to: optionalDate, withKeyPath: "state")
        }
        alert.accessoryView = view
        alert.window.initialFirstResponder = field
        alert.addButton(withTitle: "추가"); alert.addButton(withTitle: "취소")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : (value, timed || optionalDate.state == .on ? date.dateValue : nil)
    }
}

struct AgendaEventDay {
    let date: Date?
    let items: [AgendaModel.Item]
}

func agendaEventDays(_ items: [AgendaModel.Item], today: Date, calendar: Calendar) -> [AgendaEventDay] {
    Dictionary(grouping: items) { item in
        item.start.map { max(today, calendar.startOfDay(for: $0)) }
    }
    .map { AgendaEventDay(date: $0.key, items: $0.value) }
    .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
}

extension AgendaModel {
    func prepareAgendaRender(connected: Bool, empty: Bool, now: Date) {
        guard connected else { return }
        googleConnected = true
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        if empty {
            calendarStatus = "다가오는 일정 없음"; tasksStatus = "미완료 항목 없음"
            return
        }
        events = [
            Item(id: "brief", title: "제작 회의", subtitle: "", start: today.addingTimeInterval(10.5 * 3600),
                 color: NSColor(srgbRed: 0.42, green: 0.68, blue: 1, alpha: 1)),
            Item(id: "shoot", title: "브랜드 인터뷰 촬영", subtitle: "", start: today.addingTimeInterval(14 * 3600),
                 color: NSColor(srgbRed: 0.55, green: 0.86, blue: 0.73, alpha: 1)),
            Item(id: "rehearsal", title: "콘텐츠 공개", subtitle: "", start: tomorrow, allDay: true,
                 color: NSColor(srgbRed: 0.78, green: 0.61, blue: 1, alpha: 1)),
            Item(id: "review", title: "편집본 리뷰 및 최종 전달 일정 확인", subtitle: "",
                 start: tomorrow.addingTimeInterval(11 * 3600))
        ]
        tasks = [
            Item(id: "materials", title: "촬영 자료 확인", subtitle: "", start: yesterday, taskListTitle: "제작"),
            Item(id: "edit", title: "클라이언트 검토용 편집본 내보내기", subtitle: "", start: today, taskListTitle: "후반 작업"),
            Item(id: "meeting", title: "다음 회의 안건 정리", subtitle: "", taskListTitle: "스튜디오"),
            Item(id: "budget", title: "제작비 정산", subtitle: "", taskListTitle: "운영"),
            Item(id: "schedule", title: "다음 주 촬영 일정 공유", subtitle: "", taskListTitle: "제작")
        ]
        calendarStatus = "앞으로 7일"; tasksStatus = "미완료 항목"
    }
}

func agendaRelativeLabel(_ item: AgendaModel.Item, now: Date) -> String {
    guard let start = item.start else { return "예정" }
    let remaining = start.timeIntervalSince(now)
    if remaining <= 0 { return item.end.map { $0 > now } == true ? "진행 중" : "예정" }
    if remaining < 60 { return "곧 시작" }
    let minutes = Int(ceil(remaining / 60))
    if minutes < 60 { return "\(minutes)분 후" }
    if minutes < 1_440 {
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "\(hours)시간 후" : "\(hours)시간 \(rest)분 후"
    }
    let formatter = DateFormatter(); formatter.locale = Locale(identifier: "ko_KR"); formatter.dateFormat = "M월 d일"
    return formatter.string(from: start)
}

func agendaTimeLabel(_ item: AgendaModel.Item) -> String {
    if item.allDay { return "종일" }
    guard let start = item.start else { return item.subtitle }
    let formatter = DateFormatter(); formatter.locale = Locale(identifier: "ko_KR"); formatter.dateFormat = "HH:mm"
    return formatter.string(from: start)
}
