import AppKit
import EventKit

/// Today's and tomorrow's events from the Mac's Calendar (every account the Calendar app has:
/// iCloud, Google, Exchange…), plus a "meeting soon" trigger 5 minutes before each timed event.
final class CalendarService {
    /// Main thread.
    var onEvents: ([CalEvent]) -> Void = { _ in }
    /// How many event calendars this Mac has (0 = no accounts added to the Calendar app).
    var onCalendarCount: (Int) -> Void = { _ in }
    static let daysAhead = 7
    var onAccess: (IslandModel.CalendarAccess) -> Void = { _ in }
    var onMeetingSoon: (CalEvent) -> Void = { _ in }

    static let reminderLead: TimeInterval = 5 * 60

    private let store = EKEventStore()
    private var timer: Timer?
    private var observer: NSObjectProtocol?
    private var alerted = Set<String>()
    private var events: [CalEvent] = []
    private(set) var running = false

    func start() {
        guard !running else { return }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            begin()
        case .notDetermined:
            onAccess(.unknown)
            store.requestFullAccessToEvents { [weak self] granted, _ in
                DispatchQueue.main.async {
                    if granted { self?.begin() } else { self?.onAccess(.denied) }
                }
            }
        default:
            onAccess(.denied)
        }
    }

    func stop() {
        running = false
        timer?.invalidate()
        timer = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        events = []
        onEvents([])
        onAccess(.off)
    }

    private func begin() {
        running = true
        onAccess(.granted)
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.reload()
        }
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        timer = t
        reload()
        tick()
    }

    private func reload() {
        let cal = Calendar.current
        let now = Date()
        // The whole current month (for the month grid), and at least a week ahead (for reminders).
        guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)),
              let nextMonth = cal.date(byAdding: .month, value: 1, to: monthStart),
              let weekAhead = cal.date(byAdding: .day, value: Self.daysAhead, to: cal.startOfDay(for: now)) else { return }
        let predicate = store.predicateForEvents(withStart: monthStart, end: max(nextMonth, weekAhead), calendars: nil)
        events = store.events(matching: predicate)
            .filter { !Self.declined($0) && $0.status != .canceled }
            .map(Self.convert)
            .sorted { ($0.isAllDay ? 0 : 1, $0.start) < ($1.isAllDay ? 0 : 1, $1.start) }
        onEvents(events)
        let calendars = store.calendars(for: .event)
        onCalendarCount(calendars.count)
        let sources = Set(calendars.map { $0.source.title }).sorted()
        DebugLog.write("calendar: \(calendars.count) calendar(s) from [\(sources.joined(separator: ", "))], \(events.count) event(s) this month")
    }

    /// Every 30 s: drop finished events and fire reminders for timed events starting within 5 minutes.
    private func tick() {
        let now = Date()
        for e in events where !e.isAllDay && !alerted.contains(e.id) {
            let lead = e.start.timeIntervalSince(now)
            if lead > 0 && lead <= Self.reminderLead {
                alerted.insert(e.id)
                onMeetingSoon(e)
            }
        }
    }

    /// Adds an event to the default calendar (iCloud, Google… whatever Calendar.app uses for new events).
    /// `minutes == 0` = all-day. Returns an error message, or nil on success.
    func addEvent(title: String, start: Date, minutes: Int) -> String? {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return "Calendar access is off" }
        let writable = { (c: EKCalendar?) -> EKCalendar? in c?.allowsContentModifications == true ? c : nil }
        guard let calendar = writable(store.defaultCalendarForNewEvents)
                ?? store.calendars(for: .event).first(where: { $0.allowsContentModifications }) else {
            return "No calendar you can add events to"
        }
        let e = EKEvent(eventStore: store)
        e.title = title
        e.calendar = calendar
        if minutes == 0 {
            let day = Calendar.current.startOfDay(for: start)
            e.isAllDay = true
            e.startDate = day
            e.endDate = day
        } else {
            e.startDate = start
            e.endDate = start.addingTimeInterval(TimeInterval(minutes * 60))
        }
        if let link = Self.joinLink(in: [title]) { e.url = link }
        do {
            try store.save(e, span: .thisEvent, commit: true)
            DebugLog.write("calendar: added an event to \(calendar.source.title)")
            reload()
            return nil
        } catch {
            return "Couldn't save: \(error.localizedDescription)"
        }
    }

    /// Sensible start for a new event on `day`: the next half hour if it's today, else 9:00.
    static func defaultStart(on day: Date, now: Date = Date()) -> Date {
        let cal = Calendar.current
        if cal.isDate(day, inSameDayAs: now) {
            let next = cal.nextDate(after: now, matching: DateComponents(minute: 30), matchingPolicy: .nextTime) ?? now
            let nextHour = cal.nextDate(after: now, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? now
            return min(next, nextHour)
        }
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
    }

    private static func declined(_ e: EKEvent) -> Bool {
        e.attendees?.first(where: { $0.isCurrentUser })?.participantStatus == .declined
    }

    private static func convert(_ e: EKEvent) -> CalEvent {
        CalEvent(
            id: "\(e.eventIdentifier ?? e.calendarItemIdentifier)|\(e.startDate.timeIntervalSince1970)",
            title: e.title?.isEmpty == false ? e.title! : "Untitled event",
            start: e.startDate,
            end: e.endDate,
            isAllDay: e.isAllDay,
            color: e.calendar?.color ?? .systemBlue,
            location: e.location?.isEmpty == false ? e.location : nil,
            calendarTitle: e.calendar?.title ?? "Calendar",
            joinURL: joinLink(in: [e.url?.absoluteString, e.location, e.notes]))
    }

    private static let joinPattern = try! NSRegularExpression(
        pattern: #"https?://[^\s<>"']*(zoom\.us/(j|my|w|s)/|meet\.google\.com/[a-z]|teams\.microsoft\.com/l/meetup-join|teams\.live\.com/meet|webex\.com/(meet|join|[a-z0-9.]+/j\.php)|whereby\.com/|facetime\.apple\.com/join|chime\.aws/)[^\s<>"']*"#,
        options: [.caseInsensitive])

    /// First video-call link in the event's URL, location or notes.
    static func joinLink(in fields: [String?]) -> URL? {
        for case let text? in fields {
            let range = NSRange(text.startIndex..., in: text)
            if let m = joinPattern.firstMatch(in: text, range: range), let r = Range(m.range, in: text) {
                let s = text[r].trimmingCharacters(in: CharacterSet(charactersIn: ").,;>"))
                if let url = URL(string: s) { return url }
            }
        }
        return nil
    }
}
