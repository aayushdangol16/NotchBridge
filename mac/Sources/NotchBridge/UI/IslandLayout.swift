import CoreGraphics

/// The island's exact size and corner radii for every state. Single source of truth: the view draws
/// with it and the controller hit-tests with it, so "is the pointer over the island" always matches
/// what's on screen. (Every expanded state has a fixed height, so this can be computed, not measured.)
enum IslandLayout {
    /// Notification cards, meeting cards and the dashboard all open to the same width.
    static let openWidth: CGFloat = 480
    static let peekWing: CGFloat = 38
    static let activityWing: CGFloat = 32
    static let wordsWing: CGFloat = 76                  // battery / volume strips carry a word beside the camera
    /// NotificationCard and MeetingCard body (fixed rows), below the camera strip.
    static let cardBodyHeight: CGFloat = 110
    /// DashboardView body (content + its padding), below the camera strip.
    static var dashboardBodyHeight: CGFloat { DashboardView.contentHeight + 18 }

    static func isCard(_ m: IslandModel) -> Bool {
        m.mode == .activity && m.stage == .full && (m.notification != nil || m.system?.hasCard == true)
    }

    static func radii(_ m: IslandModel) -> (top: CGFloat, bottom: CGFloat) {
        switch m.mode {
        case .idle: return m.liveVisible ? (8, 14) : (6, 10)
        case .peek: return (8, 13)
        case .activity: return isCard(m) ? (14, 28) : (8, 14)
        case .open: return (14, 28)
        }
    }

    static func size(_ m: IslandModel) -> CGSize {
        let notch = m.notchSize
        let top = radii(m).top
        switch m.mode {
        case .idle:
            return CGSize(width: notch.width + 2 * (m.liveVisible ? activityWing : 0) + 2 * top, height: notch.height)
        case .peek:
            return CGSize(width: notch.width + 2 * peekWing + 2 * top, height: notch.height)
        case .activity:
            if isCard(m) { return CGSize(width: openWidth, height: notch.height + cardBodyHeight) }
            let wing = (m.system != nil && m.notification == nil) ? wordsWing : activityWing
            return CGSize(width: notch.width + 2 * wing + 2 * top, height: notch.height)
        case .open:
            return CGSize(width: openWidth, height: notch.height + dashboardBodyHeight)
        }
    }
}
