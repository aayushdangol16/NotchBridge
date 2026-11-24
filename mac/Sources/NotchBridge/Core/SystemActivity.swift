import AppKit

/// A calendar event as the island needs it.
struct CalEvent: Identifiable, Equatable {
    let id: String              // event identifier + start (recurring events share identifiers)
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: NSColor
    let location: String?
    let calendarTitle: String
    let joinURL: URL?

    static func == (a: CalEvent, b: CalEvent) -> Bool {
        a.id == b.id && a.title == b.title && a.start == b.start && a.end == b.end && a.joinURL == b.joinURL
    }

    func isHappening(at now: Date = Date()) -> Bool { start <= now && now < end }
    /// Show "Join" from 15 minutes before until the end.
    func canJoin(at now: Date = Date()) -> Bool { joinURL != nil && now >= start.addingTimeInterval(-15 * 60) && now < end }
}

/// Island activities that come from the Mac itself (not the phone). Priority below phone notifications.
enum SystemActivity: Equatable {
    case charging(level: Int, charging: Bool)
    case lowBattery(level: Int)
    case meeting(CalEvent)
    case volume(level: Int, muted: Bool)

    /// Same kind of activity (a new volume level updates the strip instead of re-animating it).
    func sameKind(as other: SystemActivity) -> Bool {
        switch (self, other) {
        case (.charging, .charging), (.lowBattery, .lowBattery), (.volume, .volume): return true
        case (.meeting(let a), .meeting(let b)): return a.id == b.id
        default: return false
        }
    }

    /// Meetings open into a full card; battery events stay a compact strip beside the camera.
    var hasCard: Bool {
        if case .meeting = self { return true }
        return false
    }

    var duration: TimeInterval {
        switch self {
        case .charging: return 3.5
        case .lowBattery: return 5
        case .meeting: return 15
        case .volume: return 1.6
        }
    }

    var accent: NSColor {
        switch self {
        case .charging: return NSColor(srgbRed: 0.2, green: 0.85, blue: 0.4, alpha: 1)
        case .lowBattery: return NSColor(srgbRed: 1, green: 0.32, blue: 0.3, alpha: 1)
        case .meeting(let e): return e.color
        case .volume: return NSColor(white: 0.95, alpha: 1)
        }
    }
}
