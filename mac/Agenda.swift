import Foundation
import EventKit
import AppKit

/// Access prompts are initiated only by the corresponding user action. Existing
/// full-access grants can be refreshed without requesting access again.
final class AgendaModel: ObservableObject {
    struct Item: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        var start: Date? = nil
        var end: Date? = nil
        var allDay: Bool = false
    }
    @Published var events: [Item] = []
    @Published var reminders: [Item] = []
    @Published var calendarStatus = "일정 권한 필요"
    @Published var remindersStatus = "미리 알림 권한 필요"
    private let store = EKEventStore()
    private let calendarQueue = DispatchQueue(label: "app.rium.notch.calendar", qos: .utility)
    private var reminderObjects: [String: EKReminder] = [:]
    private var changeObserver: NSObjectProtocol?
    private var refreshWork: DispatchWorkItem?
    private var calendarGeneration = 0
    private var reminderGeneration = 0
    private var lastCalendarAccess = EKEventStore.authorizationStatus(for: .event)
    private var lastReminderAccess = EKEventStore.authorizationStatus(for: .reminder)

    init(autoRefresh: Bool = true) {
        guard autoRefresh else { return }
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
        lastCalendarAccess = EKEventStore.authorizationStatus(for: .event)
        lastReminderAccess = EKEventStore.authorizationStatus(for: .reminder)
        if lastCalendarAccess == .fullAccess { refreshCalendar() }
        else { calendarGeneration += 1; events = []; calendarStatus = "일정 권한 필요" }
        if lastReminderAccess == .fullAccess { refreshReminders() }
        else { reminderGeneration += 1; reminders = []; reminderObjects = [:]; remindersStatus = "미리 알림 권한 필요" }
    }

    func refreshIfAuthorizationChanged() {
        if EKEventStore.authorizationStatus(for: .event) != lastCalendarAccess || EKEventStore.authorizationStatus(for: .reminder) != lastReminderAccess {
            refreshAuthorized()
        }
    }

    func loadCalendar() {
        store.requestFullAccessToEvents { [weak self] granted, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                guard granted, error == nil else { self.events = []; self.calendarStatus = "캘린더 접근을 허용해 주세요"; return }
                self.refreshCalendar()
            }
        }
    }

    private func refreshCalendar() {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
        calendarGeneration += 1; let generation = calendarGeneration
        calendarQueue.async { [weak self] in
            guard let self = self else { return }
            let start = Date(), end = Calendar.current.date(byAdding: .day, value: 7, to: start) ?? start
            let predicate = self.store.predicateForEvents(withStart: start, end: end, calendars: nil)
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "ko_KR"); formatter.dateStyle = .short; formatter.timeStyle = .short
            let rows = self.store.events(matching: predicate).sorted { $0.startDate < $1.startDate }.prefix(20).map {
                Item(id: $0.eventIdentifier ?? UUID().uuidString, title: $0.title ?? "제목 없음", subtitle: $0.isAllDay ? "종일" : formatter.string(from: $0.startDate), start: $0.startDate, end: $0.endDate, allDay: $0.isAllDay)
            }
            DispatchQueue.main.async {
                guard generation == self.calendarGeneration, EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
                self.events = rows; self.calendarStatus = rows.isEmpty ? "다가오는 일정 없음" : "앞으로 7일"
            }
        }
    }

    func loadReminders() {
        store.requestFullAccessToReminders { [weak self] granted, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                guard granted, error == nil else { self.reminders = []; self.reminderObjects = [:]; self.remindersStatus = "미리 알림 접근을 허용해 주세요"; return }
                self.refreshReminders()
            }
        }
    }

    private func refreshReminders() {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return }
        reminderGeneration += 1; let generation = reminderGeneration
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        store.fetchReminders(matching: predicate) { [weak self] reminders in
            let selected = Array((reminders ?? []).prefix(20))
            let rows = selected.map { Item(id: $0.calendarItemIdentifier, title: $0.title ?? "제목 없음", subtitle: $0.calendar.title) }
            DispatchQueue.main.async {
                guard let self = self, generation == self.reminderGeneration, EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return }
                self.reminderObjects = Dictionary(selected.map { ($0.calendarItemIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
                self.reminders = rows; self.remindersStatus = rows.isEmpty ? "미완료 항목 없음" : "미완료 항목"
            }
        }
    }

    func completeReminder(_ id: String) {
        guard let reminder = reminderObjects[id] else { remindersStatus = "항목을 다시 불러와 주세요"; return }
        reminder.isCompleted = true
        do { try store.save(reminder, commit: true); loadReminders() }
        catch { reminder.isCompleted = false; remindersStatus = "미리 알림을 완료하지 못했습니다" }
    }

    func addReminder() {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess,
              let list = store.defaultCalendarForNewReminders() else { remindersStatus = "미리 알림 접근과 목록을 확인해 주세요"; return }
        let alert = NSAlert(); alert.messageText = "미리 알림 추가"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24)); alert.accessoryView = field
        alert.addButton(withTitle: "추가"); alert.addButton(withTitle: "취소"); NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let title = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines); guard !title.isEmpty else { return }
        let item = EKReminder(eventStore: store); item.title = title; item.calendar = list
        do { try store.save(item, commit: true); loadReminders() } catch { remindersStatus = "미리 알림을 추가하지 못했습니다" }
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
        do { try store.save(event, span: .thisEvent, commit: true); loadCalendar() } catch { calendarStatus = "일정을 추가하지 못했습니다" }
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
