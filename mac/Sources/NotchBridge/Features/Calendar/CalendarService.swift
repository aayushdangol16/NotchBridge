import AppKit
import EventKit

/// Today's and tomorrow's events from the Mac's Calendar (every account the Calendar app has:
/// iCloud, Google, Exchange…), plus a "meeting soon" trigger 5 minutes before each timed event.
final class CalendarService {
    /// Main thread.
    var onEvents: ([CalEvent]) -> Void = { _ in }
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
        guard let end = cal.date(byAdding: .day, value: 2, to: cal.startOfDay(for: now)) else { return }
        let predicate = store.predicateForEvents(withStart: cal.startOfDay(for: now), end: end, calendars: nil)
        events = store.events(matching: predicate)
            .filter { $0.endDate > now && !Self.declined($0) && $0.status != .canceled }
            .map(Self.convert)
            .sorted { ($0.isAllDay ? 0 : 1, $0.start) < ($1.isAllDay ? 0 : 1, $1.start) }
        onEvents(events)
    }

    /// Every 30 s: drop finished events and fire reminders for timed events starting within 5 minutes.
    private func tick() {
        let now = Date()
        let before = events.count
        events.removeAll { $0.end <= now }
        if events.count != before { onEvents(events) }
        for e in events where !e.isAllDay && !alerted.contains(e.id) {
            let lead = e.start.timeIntervalSince(now)
            if lead > 0 && lead <= Self.reminderLead {
                alerted.insert(e.id)
                onMeetingSoon(e)
            }
        }
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
