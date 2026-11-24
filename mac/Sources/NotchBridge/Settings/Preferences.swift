import Foundation

/// UserDefaults keys and defaults. Views use `@AppStorage(Prefs.Key.x)`, code uses `Prefs.x`.
enum Prefs {
    enum Key {
        static let hoverToPeek = "hoverToPeek"
        static let openOnHover = "openOnHover"
        static let haptics = "haptics"
        static let displaySeconds = "displaySeconds"
        static let mirrorToNotificationCenter = "mirrorToNotificationCenter"
        static let liveMusic = "liveMusic"
        static let calendar = "calendar"
        static let meetingReminders = "meetingReminders"
        static let batteryAlerts = "batteryAlerts"
        static let volumeHUD = "volumeHUD"
        static let display = "display"              // "auto" | "primary"
        static let loginItemAutoSetup = "loginItemAutoSetup"
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.hoverToPeek: true,
            Key.openOnHover: false,
            Key.haptics: true,
            Key.displaySeconds: 6.0,
            Key.mirrorToNotificationCenter: false,
            Key.liveMusic: true,
            Key.calendar: true,
            Key.meetingReminders: true,
            Key.batteryAlerts: true,
            Key.volumeHUD: false,
            Key.display: "auto",
        ])
    }

    private static var d: UserDefaults { .standard }
    static var hoverToPeek: Bool { d.bool(forKey: Key.hoverToPeek) }
    static var openOnHover: Bool { d.bool(forKey: Key.openOnHover) }
    static var haptics: Bool { d.bool(forKey: Key.haptics) }
    static var displaySeconds: TimeInterval { max(2, d.double(forKey: Key.displaySeconds)) }
    static var liveMusic: Bool { d.bool(forKey: Key.liveMusic) }
    static var calendar: Bool { d.bool(forKey: Key.calendar) }
    static var meetingReminders: Bool { d.bool(forKey: Key.meetingReminders) }
    static var batteryAlerts: Bool { d.bool(forKey: Key.batteryAlerts) }
    static var volumeHUD: Bool { d.bool(forKey: Key.volumeHUD) }
    static var display: String { d.string(forKey: Key.display) ?? "auto" }
}
