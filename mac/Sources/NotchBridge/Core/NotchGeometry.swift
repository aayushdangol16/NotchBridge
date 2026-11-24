import AppKit

/// Where the notch is: which screen, its size, and screen-space rects for hit testing.
struct NotchGeometry: Equatable {
    var screenFrame: CGRect
    var notchSize: CGSize
    var hasNotch: Bool

    static let fallback = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                        notchSize: CGSize(width: 185, height: 32), hasNotch: false)

    /// "auto": the display with a notch if there is one, else the primary display (menu bar).
    /// "primary": always the primary display, e.g. an external monitor you work on with the lid open.
    static func current() -> NotchGeometry {
        let primary = NSScreen.screens.first
        let screen = Prefs.display == "primary"
            ? primary
            : (NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? primary)
        guard let screen else { return .fallback }
        let frame = screen.frame
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            return NotchGeometry(screenFrame: frame,
                                 notchSize: CGSize(width: frame.width - left.width - right.width,
                                                   height: screen.safeAreaInsets.top),
                                 hasNotch: true)
        }
        return NotchGeometry(screenFrame: frame,
                             notchSize: CGSize(width: 180, height: NSStatusBar.system.thickness),
                             hasNotch: false)
    }

    /// A rect of `size` hanging from the top-center of the screen (screen coordinates, origin bottom-left).
    func topCenterRect(_ size: CGSize) -> CGRect {
        CGRect(x: screenFrame.midX - size.width / 2, y: screenFrame.maxY - size.height,
               width: size.width, height: size.height)
    }

    /// The area that wakes the island from idle: the notch plus a little slack on each side and below.
    var hotZone: CGRect {
        topCenterRect(CGSize(width: notchSize.width + 24, height: notchSize.height + 6))
    }
}
