import Foundation
import EventKit
import AppKit

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

private final class ReminderForm: NSObject {
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 132))
    let title = NSTextField(frame: NSRect(x: 0, y: 104, width: 300, height: 24))
    let dateEnabled = NSButton(checkboxWithTitle: "날짜 지정", target: nil, action: nil)
    let timeEnabled = NSButton(checkboxWithTitle: "시간 지정", target: nil, action: nil)
    let date = NSDatePicker(frame: NSRect(x: 0, y: 42, width: 300, height: 24))
    let location = NSTextField(frame: NSRect(x: 0, y: 10, width: 300, height: 24))

    override init() {
        super.init()
        title.placeholderString = "미리 알림 제목"
        location.placeholderString = "장소 메모 (선택 사항)"
        dateEnabled.frame = NSRect(x: 0, y: 74, width: 130, height: 22)
        timeEnabled.frame = NSRect(x: 145, y: 74, width: 130, height: 22)
        dateEnabled.target = self; dateEnabled.action = #selector(update)
        timeEnabled.target = self; timeEnabled.action = #selector(update)
        date.datePickerStyle = .textFieldAndStepper; date.dateValue = Date().addingTimeInterval(3600)
        let controls: [NSView] = [title, dateEnabled, timeEnabled, date, location]
        for control in controls { view.addSubview(control) }
        update()
    }

    @objc private func update() {
        let hasDate = dateEnabled.state == .on
        timeEnabled.isEnabled = hasDate
        date.isEnabled = hasDate
        date.datePickerElements = hasDate && timeEnabled.state == .on ? [.yearMonthDay, .hourMinute] : [.yearMonthDay]
    }
}

func reminderDueComponents(_ date: Date, includeTime: Bool, timeZone: TimeZone = .current) -> DateComponents {
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
    let units: Set<Calendar.Component> = includeTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
    var components = calendar.dateComponents(units, from: date)
    components.calendar = calendar
    components.timeZone = includeTime ? timeZone : nil
    return components
}

private func reminderDueDate(_ components: DateComponents?) -> Date? {
    guard let components = components, components.year != nil, components.month != nil, components.day != nil else { return nil }
    return (components.calendar ?? Calendar(identifier: .gregorian)).date(from: components)
}

private func reminderSubtitle(list: String, due: DateComponents?, date: Date?, formatter: DateFormatter) -> String {
    guard let due, let date else { return list }
    let style: DateFormatter.Style = due.hour == nil ? .none : .short
    if formatter.timeStyle != style { formatter.timeStyle = style }
    let zone = due.timeZone ?? .current
    if formatter.timeZone != zone { formatter.timeZone = zone }
    let label = formatter.string(from: date)
    return list.isEmpty ? label : "\(list) · \(label)"
}

/// Access prompts are initiated only by the corresponding user action. Existing
/// full-access grants can be refreshed without requesting access again.
final class AgendaModel: ObservableObject {
    enum Addition: Equatable { case event, reminder }
    var onAdded: ((Addition) -> Void)?
    struct Item: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        var start: Date? = nil
        var end: Date? = nil
        var allDay: Bool = false
        var color: NSColor? = nil
    }
    @Published var events: [Item] = []
    @Published private(set) var todayEvents: [Item] = []
    @Published private(set) var todayEventCount = 0
    @Published private(set) var weekEventDays: Set<Date> = []
    @Published private(set) var monthEventDays: Set<Date> = []
    @Published private(set) var calendarAccess: EKAuthorizationStatus = .notDetermined
    @Published private(set) var calendarRequesting = false
    var calendarReadable: Bool { calendarAccess == .fullAccess }
    @Published private(set) var calendarLoading = false
    @Published var reminders: [Item] = []
    @Published var calendarStatus = "일정 권한 필요"
    @Published var remindersStatus = "미리 알림 권한 필요"
    private lazy var store = EKEventStore()
    private let calendarQueue = DispatchQueue(label: "app.rium.notch.calendar", qos: .utility)
    private var changeObserver: NSObjectProtocol?
    private var refreshWork: DispatchWorkItem?
    private var calendarGeneration = 0
    private(set) var reminderGeneration = 0
    private let observationStarted = Date()
    private var announcedAdditions: [String: Date] = [:]
    private var lastReminderAccess: EKAuthorizationStatus?

    init(autoRefresh: Bool = true) {
        if autoRefresh { start() }
    }

    func start() {
        guard changeObserver == nil else { return }
        changeObserver = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.refreshWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.refreshAuthorized() }
            self.refreshWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }
        refreshAuthorized()
    }

    deinit {
        refreshWork?.cancel()
        if let changeObserver = changeObserver { NotificationCenter.default.removeObserver(changeObserver) }
    }

    func refreshAuthorized() {
        refreshCalendarAccess()
        lastReminderAccess = EKEventStore.authorizationStatus(for: .reminder)
        if lastReminderAccess == .fullAccess { refreshReminders() }
        else { clearReminders(status: "미리 알림 권한 필요") }
    }

    func refreshIfAuthorizationChanged() {
        if EKEventStore.authorizationStatus(for: .event) != calendarAccess || EKEventStore.authorizationStatus(for: .reminder) != lastReminderAccess {
            refreshAuthorized()
        }
    }

    func invalidateToday() {
        todayEvents = []; todayEventCount = 0; weekEventDays = []; monthEventDays = []
    }

    private func refreshCalendarAccess() {
        let access = EKEventStore.authorizationStatus(for: .event)
        if calendarAccess != access { calendarAccess = access }
        guard !calendarRequesting else { return }
        if calendarReadable {
            refreshCalendar()
        } else {
            calendarGeneration += 1
            events = []
            invalidateToday()
            calendarLoading = false
            switch access {
            case .denied, .writeOnly: calendarStatus = "시스템 설정에서 Rium Notch에 캘린더 전체 접근을 허용해 주세요"
            case .restricted: calendarStatus = "이 Mac에서 캘린더 접근이 제한되어 있습니다"
            default: calendarStatus = "일정 권한 필요"
            }
        }
    }

    var calendarActionTitle: String {
        switch calendarAccess {
        case .denied, .writeOnly: return "캘린더 설정 열기"
        default: return "일정 불러오기"
        }
    }

    func loadCalendar() {
        guard !calendarRequesting, !calendarLoading else { return }
        refreshCalendarAccess()
        switch calendarAccess {
        case .fullAccess, .restricted:
            return
        case .denied, .writeOnly:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                NSWorkspace.shared.open(url)
            }
        default:
            calendarRequesting = true
            calendarStatus = "캘린더 접근 요청 중…"
            NSApp.activate(ignoringOtherApps: true)
            let store = self.store
            calendarQueue.async { [weak self] in
                store.requestFullAccessToEvents { _, error in
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        self.calendarRequesting = false
                        self.refreshCalendarAccess()
                        if error != nil && self.calendarAccess == .notDetermined {
                            self.calendarStatus = "캘린더 접근을 요청하지 못했습니다. 다시 시도해 주세요"
                        }
                    }
                }
            }
        }
    }

    private func refreshCalendar() {
        calendarGeneration += 1; let generation = calendarGeneration
        calendarLoading = true
        calendarStatus = "일정 불러오는 중…"
        let store = self.store
        calendarQueue.async { [weak self] in
            guard let self = self else { return }
            let start = Date(), calendar = Calendar.current
            let dayStart = calendar.startOfDay(for: start)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? start
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: start)?.start ?? dayStart
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? dayEnd
            let monthInterval = calendar.dateInterval(of: .month, for: start)
            let monthStart = monthInterval?.start ?? dayStart, monthEnd = monthInterval?.end ?? dayEnd
            let upcomingEnd = calendar.date(byAdding: .day, value: 7, to: start) ?? start
            let end = max(upcomingEnd, weekEnd, monthEnd)
            let predicate = store.predicateForEvents(withStart: min(dayStart, weekStart, monthStart), end: end, calendars: nil)
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "ko_KR"); formatter.dateStyle = .short; formatter.timeStyle = .short
            let fetched = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
            let selected = fetched.filter { eventIsUpcoming(start: $0.startDate, end: $0.endDate, now: start, through: upcomingEnd) }.prefix(20)
            let today = fetched.filter { $0.startDate < dayEnd && ($0.endDate > dayStart || $0.startDate >= dayStart) }
            let weekDates = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
            let weekEventDays = Set(weekDates.filter { date in
                guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { return false }
                return fetched.contains { event in
                    eventIntersectsCalendarDay(start: event.startDate, end: event.endDate, dayStart: date, dayEnd: next)
                }
            }.map { calendar.startOfDay(for: $0) })
            let monthCount = calendar.range(of: .day, in: .month, for: start)?.count ?? 0
            let monthDates = (0..<monthCount).compactMap { calendar.date(byAdding: .day, value: $0, to: monthStart) }
            let monthEventDays = Set(monthDates.filter { date in
                guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { return false }
                return fetched.contains { event in
                    eventIntersectsCalendarDay(start: event.startDate, end: event.endDate, dayStart: date, dayEnd: next)
                }
            }.map { calendar.startOfDay(for: $0) })
            let additions = selected.compactMap { event -> (String, Date)? in
                guard let created = event.creationDate else { return nil }
                return (event.calendarItemIdentifier, created)
            }
            func row(_ event: EKEvent) -> Item {
                Item(id: event.eventIdentifier ?? UUID().uuidString, title: event.title ?? "제목 없음", subtitle: event.isAllDay ? "종일" : formatter.string(from: event.startDate), start: event.startDate, end: event.endDate, allDay: event.isAllDay, color: NSColor(cgColor: event.calendar.cgColor))
            }
            let rows = selected.map(row), todayRows = today.map(row), todayCount = today.count
            DispatchQueue.main.async {
                guard generation == self.calendarGeneration, EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
                self.events = rows; self.todayEvents = todayRows; self.todayEventCount = todayCount; self.weekEventDays = weekEventDays; self.monthEventDays = monthEventDays; self.calendarLoading = false
                self.calendarStatus = rows.isEmpty ? "다가오는 일정 없음" : "앞으로 7일"
                self.announceRecentAdditions(additions, type: .event)
            }
        }
    }

    func loadReminders() {
        store.requestFullAccessToReminders { [weak self] granted, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                guard granted, error == nil else { self.clearReminders(status: "미리 알림 접근을 허용해 주세요"); return }
                self.refreshReminders()
            }
        }
    }

    private func refreshReminders() {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return }
        reminderGeneration += 1; let generation = reminderGeneration
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        store.fetchReminders(matching: predicate) { [weak self] reminders in
            let snapshot = Self.projectReminders(reminders ?? [])
            DispatchQueue.main.async {
                guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return }
                self?.acceptReminderFetch(snapshot.rows, additions: snapshot.additions, generation: generation)
            }
        }
    }

    static func projectReminders(_ reminders: [EKReminder]) -> (rows: [Item], additions: [(String, Date)]) {
        let incomplete = reminders.filter { !$0.isCompleted }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateStyle = .medium
        let rows = incomplete.map { reminder in
            let due = reminder.dueDateComponents
            let date = reminderDueDate(due)
            let subtitle = reminderSubtitle(list: reminder.calendar?.title ?? "", due: due, date: date, formatter: formatter)
            return Item(id: reminder.calendarItemIdentifier, title: reminder.title ?? "제목 없음", subtitle: subtitle, start: date)
        }.sorted { first, second in
            switch (first.start, second.start) {
            case let (a?, b?): return a < b
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return first.title.localizedCaseInsensitiveCompare(second.title) == .orderedAscending
            }
        }
        let additions = incomplete.compactMap { item -> (String, Date)? in
            item.creationDate.map { (item.calendarItemIdentifier, $0) }
        }
        return (rows, additions)
    }

    func acceptReminderFetch(_ rows: [Item], additions: [(String, Date)], generation: Int) {
        guard generation == reminderGeneration else { return }
        publishReminders(rows)
        announceRecentAdditions(additions, type: .reminder)
    }

    private func publishReminders(_ rows: [Item]) {
        reminders = rows
        remindersStatus = rows.isEmpty ? "미완료 항목 없음" : "미완료 항목"
    }

    private func clearReminders(status: String) {
        reminderGeneration &+= 1
        reminders = []
        remindersStatus = status
    }

    // EventKit change notifications do not identify an addition. Only report
    // a visible item with a recent creation date after this observer started;
    // edits, refreshes and old items entering the date window do not qualify.
    private func announceRecentAdditions(_ items: [(String, Date)], type: Addition) {
        let now = Date()
        announcedAdditions = announcedAdditions.filter { now.timeIntervalSince($0.value) < 300 }
        for (id, created) in items where !id.isEmpty {
            let key = "\(type == .event ? "event" : "reminder"):\(id)"
            let age = now.timeIntervalSince(created)
            guard created >= observationStarted, age >= -2, age < 120, announcedAdditions[key] == nil else { continue }
            announcedAdditions[key] = now
            onAdded?(type)
        }
    }

    private func markAddition(_ id: String, type: Addition) {
        guard !id.isEmpty else { return }
        announcedAdditions["\(type == .event ? "event" : "reminder"):\(id)"] = Date()
    }

    func completeReminder(_ id: String) {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
            clearReminders(status: "미리 알림 권한 필요")
            return
        }
        completeReminder(id, find: { store.calendarItem(withIdentifier: $0) as? EKReminder },
                         save: { try store.save($0, commit: true) }, refresh: refreshReminders)
    }

    func completeReminder(_ id: String, find: (String) -> EKReminder?, save: (EKReminder) throws -> Void, refresh: () -> Void) {
        guard reminders.contains(where: { $0.id == id }) else { return }
        guard let reminder = find(id) else { remindersStatus = "항목을 다시 불러와 주세요"; return }
        if !reminder.isCompleted {
            let previousDate = reminder.completionDate
            reminder.isCompleted = true
            reminder.completionDate = Date()
            do {
                try save(reminder)
            } catch {
                reminder.isCompleted = false
                reminder.completionDate = previousDate
                reminderGeneration &+= 1
                remindersStatus = "미리 알림을 완료하지 못했습니다"
                return
            }
        }
        // Refetches started before this commit cannot reinsert the completed row.
        reminderGeneration &+= 1
        publishReminders(reminders.filter { $0.id != id })
        refresh()
    }

    func addReminder() {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess,
              let list = store.defaultCalendarForNewReminders() else { remindersStatus = "미리 알림 접근과 목록을 확인해 주세요"; return }
        let alert = NSAlert(); alert.messageText = "미리 알림 추가"
        let form = ReminderForm(); alert.accessoryView = form.view; alert.window.initialFirstResponder = form.title
        alert.addButton(withTitle: "추가"); alert.addButton(withTitle: "취소"); NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let title = form.title.stringValue.trimmingCharacters(in: .whitespacesAndNewlines); guard !title.isEmpty else { return }
        let item = EKReminder(eventStore: store); item.title = title; item.calendar = list
        if form.dateEnabled.state == .on {
            let includeTime = form.timeEnabled.state == .on
            let due = reminderDueComponents(form.date.dateValue, includeTime: includeTime)
            item.dueDateComponents = due
            if includeTime, let date = due.date { item.addAlarm(EKAlarm(absoluteDate: date)) }
        }
        let location = form.location.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !location.isEmpty { item.location = location }
        do {
            try store.save(item, commit: true)
            markAddition(item.calendarItemIdentifier, type: .reminder)
            onAdded?(.reminder)
            refreshReminders()
        } catch { remindersStatus = "미리 알림을 추가하지 못했습니다" }
    }

    func addEvent() {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess,
              let calendar = store.defaultCalendarForNewEvents else { calendarStatus = "캘린더 접근과 기본 캘린더를 확인해 주세요"; return }
        let alert = NSAlert(); alert.messageText = "일정 추가"
        let field = NSTextField(frame: NSRect(x: 0, y: 32, width: 260, height: 24)); field.placeholderString = "일정 제목"
        let date = NSDatePicker(frame: NSRect(x: 0, y: 0, width: 260, height: 24)); date.datePickerStyle = .textFieldAndStepper; date.datePickerElements = [.yearMonthDay, .hourMinute]; date.dateValue = Date().addingTimeInterval(3600)
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 56)); view.addSubview(field); view.addSubview(date); alert.accessoryView = view
        alert.addButton(withTitle: "추가"); alert.addButton(withTitle: "취소"); NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let title = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines); guard !title.isEmpty else { return }
        let event = EKEvent(eventStore: store); event.title = title; event.calendar = calendar; event.startDate = date.dateValue; event.endDate = date.dateValue.addingTimeInterval(3600)
        do {
            try store.save(event, span: .thisEvent, commit: true)
            markAddition(event.calendarItemIdentifier, type: .event)
            onAdded?(.event)
            refreshCalendar()
        } catch { calendarStatus = "일정을 추가하지 못했습니다" }
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
