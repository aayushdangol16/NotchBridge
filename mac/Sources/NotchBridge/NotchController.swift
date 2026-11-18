import AppKit
import SwiftUI

/// Borderless panel that sits over the MacBook notch (or top-center of the screen on Macs without one)
/// and grows down out of it to show a phone notification.
final class NotchPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    // Lets the reply text field receive typing without activating the app.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    // Allow the window to sit on top of the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class NotchModel: ObservableObject {
    /// hidden: same size as the hardware notch · compact: small peek with the app icon · open: full card
    enum Phase { case hidden, compact, open }

    @Published var current: PhoneNotification?
    @Published var phase: Phase = .hidden
    @Published var expanded = false        // showing actions / reply field
    @Published var replying = false
    @Published var replyText = ""
    @Published var feedback: String?       // e.g. "Reply sent"
    @Published var feedbackIsError = false
    @Published var queued = 0              // notifications waiting behind this one
    @Published var hideDeadline: Date?     // drives the countdown bar; nil = paused
    @Published var hideDuration: TimeInterval = 6
    @Published var notchSize = CGSize(width: 200, height: 32)
    @Published var hasNotch = false

    var isVisible: Bool { phase != .hidden }

    var appIcon: (String) -> NSImage? = { _ in nil }
    var accent: (String) -> NSColor = { _ in AccentColor.fallback }
    var onDismiss: (PhoneNotification) -> Void = { _ in }
    var onAction: (PhoneNotification, WireAction) -> Void = { _, _ in }
    var onReply: (PhoneNotification, WireAction, String) -> Void = { _, _, _ in }
    var onClose: () -> Void = {}
    var onHover: (Bool) -> Void = { _ in }
    var onExpand: () -> Void = {}
}

final class NotchController {
    static let panelSize = CGSize(width: 520, height: 340)
    static let displaySeconds: TimeInterval = 6
    static let peekSeconds: TimeInterval = 0.55

    let model = NotchModel()
    private let panel = NotchPanel()
    private var queue: [PhoneNotification] = [] { didSet { model.queued = queue.count } }
    private var hideWork: DispatchWorkItem?
    private var hovering = false
    private var hideToken = 0

    init() {
        let host = NSHostingView(rootView: NotchView(model: model))
        host.frame = CGRect(origin: .zero, size: Self.panelSize)
        panel.contentView = host

        model.onClose = { [weak self] in self?.hide() }
        model.onHover = { [weak self] inside in
            guard let self else { return }
            self.hovering = inside
            if inside { self.cancelHide() } else if !self.model.expanded { self.scheduleHide(after: 2.5) }
        }
        model.onExpand = { [weak self] in
            guard let self else { return }
            self.cancelHide()
            self.panel.makeKey()
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.reposition() }
        reposition()
    }

    func show(_ n: PhoneNotification) {
        if model.current?.key == n.key {
            if model.isVisible {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { model.current = n }
                if !model.expanded && !hovering { scheduleHide(after: Self.displaySeconds) }
            } else {
                // Same notification re-posted while the notch was closing (Messenger does this): reopen it.
                present(n)
            }
            return
        }
        if model.current != nil {
            queue.removeAll { $0.key == n.key }
            queue.append(n)
            if queue.count > 5 { queue.removeFirst(queue.count - 5) }
            // Don't interrupt someone typing a reply; otherwise move on sooner.
            if !model.expanded && !hovering { scheduleHide(after: 1.5) }
            return
        }
        present(n)
    }

    /// The phone removed this notification (read/dismissed there).
    func remove(key: String) {
        queue.removeAll { $0.key == key }
        if model.current?.key == key, !model.replying { hide() }
    }

    /// Shows a short status line ("Reply sent") in the open notch, then closes it.
    func flash(_ message: String, isError: Bool = false, hideAfter: TimeInterval = 1.4) {
        guard model.current != nil else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            model.feedback = message
            model.feedbackIsError = isError
        }
        scheduleHide(after: hideAfter)
    }

    private func present(_ n: PhoneNotification) {
        hideToken += 1   // cancels any close animation still finishing
        let token = hideToken
        reposition()
        model.current = n
        model.expanded = false
        model.replying = false
        model.replyText = ""
        model.feedback = nil
        model.phase = .hidden
        panel.orderFrontRegardless()
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)

        // 1) peek out of the notch with the app icon, 2) bloom into the full card.
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { self.model.phase = .compact }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.peekSeconds) { [weak self] in
            guard let self, token == self.hideToken else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.76)) { self.model.phase = .open }
        }
        scheduleHide(after: Self.displaySeconds + Self.peekSeconds)
    }

    func hide() {
        cancelHide()
        guard model.current != nil, model.isVisible else { return }   // already closing
        hideToken += 1
        let token = hideToken
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            model.phase = .hidden
            model.expanded = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self, token == self.hideToken else { return }
            self.model.current = nil
            self.model.replying = false
            if let next = self.queue.first {
                self.queue.removeFirst()
                self.present(next)
            } else {
                self.panel.orderOut(nil)
            }
        }
    }

    private func scheduleHide(after seconds: TimeInterval) {
        hideWork?.cancel()
        model.hideDuration = seconds
        model.hideDeadline = Date().addingTimeInterval(seconds)
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.hovering, !self.model.replying else { return }
            self.hide()
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func cancelHide() {
        hideWork?.cancel()
        hideWork = nil
        model.hideDeadline = nil
    }

    private func reposition() {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let frame = screen.frame
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            model.hasNotch = true
            model.notchSize = CGSize(width: frame.width - left.width - right.width, height: screen.safeAreaInsets.top)
        } else {
            model.hasNotch = false
            model.notchSize = CGSize(width: 180, height: NSStatusBar.system.thickness)
        }
        let size = Self.panelSize
        panel.setFrame(CGRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height,
                              width: size.width, height: size.height), display: true)
    }
}
