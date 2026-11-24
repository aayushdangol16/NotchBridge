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
        case home, phone
        var id: String { rawValue }
        var icon: String { self == .home ? "house.fill" : "iphone.gen3" }
        var title: String { self == .home ? "Home" : "Phone" }
    }

    @Published var mode: Mode = .idle
    @Published var stage: Stage = .compact
    @Published var tab: Tab = .home
    @Published var hovering = false

    // Current activity (a phone notification) and its interaction state
    @Published var notification: PhoneNotification?
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
    var onRing: (Bool) -> Void = { _ in }              // true = ring, false = stop
    var onMedia: (MediaCommand) -> Void = { _ in }
    var onClearAll: () -> Void = {}
    /// A text field in the dashboard wants focus: make the panel key and keep the dashboard open.
    var onNeedKeyboard: () -> Void = {}
    /// The view reports the island's laid-out size so the controller can hit-test it on screen.
    var onIslandSize: (CGSize) -> Void = { _ in }
}
