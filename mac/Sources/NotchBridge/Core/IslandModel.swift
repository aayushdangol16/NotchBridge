import AppKit
import SwiftUI

/// Everything the island view renders. Owned and mutated by `IslandController` (main thread only).
final class IslandModel: ObservableObject {
    /// idle: invisible, looks like the hardware notch · peek: hovered, slightly wider with live items ·
    /// open: dashboard · activity: a temporary card (phone notification) that takes over the island.
    enum Mode: Equatable { case idle, peek, open, activity }
    /// Activities grow in two steps: a compact peek beside the camera, then the full card.
    enum Stage: Equatable { case compact, full }
    enum Tab: String, CaseIterable, Identifiable {
        case home, phone, calendar, shelf, mirror
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .home: return "house.fill"
            case .phone: return "iphone.gen3"
            case .calendar: return "calendar"
            case .shelf: return "tray.full.fill"
            case .mirror: return "camera.fill"
            }
        }
        var title: String {
            switch self {
            case .home: return "Home"
            case .phone: return "Phone"
            case .calendar: return "Agenda"
            case .shelf: return "Shelf"
            case .mirror: return "Mirror"
            }
        }
    }

    @Published var mode: Mode = .idle
    @Published var stage: Stage = .compact
    @Published var tab: Tab = .home
    @Published var hovering = false

    // Current activity: a phone notification, or a system activity (charging, meeting…)
    @Published var notification: PhoneNotification?
    @Published var system: SystemActivity?
    @Published var expanded = false
    @Published var replying = false
    @Published var replyText = ""
    @Published var feedback: String?
    @Published var feedbackIsError = false
    @Published var queued = 0
    @Published var hideDeadline: Date?
    @Published var hideDuration: TimeInterval = 6

    // Geometry
    @Published var notchSize = CGSize(width: 185, height: 32)
    @Published var hasNotch = false

    // Phone status for peek + dashboard
    @Published var phoneName: String?
    @Published var phoneConnected = false
    @Published var phoneBattery: Int?
    @Published var phoneCharging = false
    @Published var phoneRinging = false
    @Published var recent: [PhoneNotification] = []

    // Media (Mac or phone)
    @Published var media: NowPlaying?
    @Published var mediaAccent: NSColor = AccentColor.fallback
    @Published var liveMusicEnabled = true
    /// While idle and music plays, the island shows a small live strip (art + bars) beside the camera.
    var liveVisible: Bool { mode == .idle && liveMusicEnabled && (media?.isPlaying ?? false) }

    // Calendar
    enum CalendarAccess { case off, unknown, granted, denied }
    @Published var events: [CalEvent] = []
    @Published var calendarAccess: CalendarAccess = .off
    @Published var calendarCount = 0
    @Published var selectedDay = Calendar.current.startOfDay(for: Date())
    // New-event form (Agenda tab)
    @Published var addingEvent = false
    @Published var newEventTitle = ""
    @Published var newEventTime = Date()
    @Published var newEventMinutes = 30          // 0 = all day
    /// Typing in the dashboard (reply or new event): don't auto-close it.
    var isTyping: Bool { rowReplyKey != nil || addingEvent }

    // Shelf
    @Published var shelfItems: [ShelfItem] = []
    @Published var shelfIcons: [UUID: NSImage] = [:]
    @Published var transfers: [UUID: Double] = [:]   // shelf item -> send-to-phone progress 0…1
    @Published var dropTargeted = false
    @Published var fileDragActive = false

    // Phone tab interaction
    @Published var openRowKey: String?       // row showing full text + actions
    @Published var rowReplyKey: String?      // row with an inline reply field
    @Published var rowReplyText = ""
    /// Short status line in the dashboard ("Reply sent", "Ringing your phone").
    @Published var toast: String?
    @Published var toastIsError = false

    // Data + actions provided by the app
    var appIcon: (String) -> NSImage? = { _ in nil }
    var accent: (String) -> NSColor = { _ in AccentColor.fallback }
    var onDismiss: (PhoneNotification) -> Void = { _ in }
    var onAction: (PhoneNotification, WireAction) -> Void = { _, _ in }
    var onReply: (PhoneNotification, WireAction, String) -> Void = { _, _, _ in }
    var onCloseActivity: () -> Void = {}
    var onExpandCard: () -> Void = {}
    var onOpenDashboard: () -> Void = {}
    var onCloseDashboard: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var onPairPhone: () -> Void = {}
    var onReshow: (PhoneNotification) -> Void = { _ in }
    /// Click on a notification card: open it (full text, all actions) in the dashboard's Phone tab.
    var onOpenNotification: (PhoneNotification) -> Void = { _ in }
    var onRing: (Bool) -> Void = { _ in }              // true = ring, false = stop
    var onMedia: (MediaCommand) -> Void = { _ in }
    var onSeek: (Double) -> Void = { _ in }          // seconds
    var onClearAll: () -> Void = {}
    var onJoin: (URL) -> Void = { _ in }
    /// title, start, minutes (0 = all day)
    var onAddEvent: (String, Date, Int) -> Void = { _, _, _ in }
    var onDropProviders: ([NSItemProvider]) -> Void = { _ in }
    var onDropFiles: ([URL]) -> Void = { _ in }
    var onDragActivity: () -> Void = {}
    var onShelfRemove: (ShelfItem) -> Void = { _ in }
    var onShelfClear: () -> Void = {}
    var onShelfOpen: (ShelfItem) -> Void = { _ in }
    var onShelfAirDrop: ([ShelfItem]) -> Void = { _ in }
    var onShelfSendToPhone: (ShelfItem) -> Void = { _ in }
    var onCalendarAccess: () -> Void = {}             // ask for access / open Privacy settings
    /// A text field in the dashboard wants focus: make the panel key and keep the dashboard open.
    var onNeedKeyboard: () -> Void = {}
}
