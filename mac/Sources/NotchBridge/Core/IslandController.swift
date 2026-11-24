import AppKit
import SwiftUI

/// Owns the island: the panel, the state machine and the activity queue.
///
///   idle ──hover──► peek ──click / swipe down──► open (dashboard)
///     ▲   ◄─leave──      ◄──leave / click outside / swipe up──
///     └─ any state ──phone notification──► activity (compact ► full card) ──timeout/close──► back
///
/// Features never touch the window; they call `show(_:)` / `remove(key:)`.
final class IslandController {
    static let panelSize = CGSize(width: 540, height: 320)
    static let peekSeconds: TimeInterval = 0.55

    let model = IslandModel()
    private let panel = NotchPanel()
    private let hover = HoverTracker()
    private(set) var geometry = NotchGeometry.current()
    private var islandSize: CGSize = .zero
    private var pointer = CGPoint(x: -10_000, y: -10_000)
    private(set) var pointerInside = false

    // Activity
    private var queue: [PhoneNotification] = []      // arrived while the user was busy with a card
    private var hideWork: DispatchWorkItem?
    private var token = 0                            // invalidates stale animation callbacks
    private var returnToOpen = false
    private var toastToken = 0

    // Dashboard
    private var closeWork: DispatchWorkItem?

    // Gestures
    private var scrollAccum: CGFloat = 0
    private var scrollAccumX: CGFloat = 0
    private var lastGesture = Date.distantPast

    /// `interactive: false` builds an invisible, untracked instance for `--selftest`.
    init(interactive: Bool = true) {
        let host = NSHostingView(rootView: IslandView(model: model))
        host.frame = CGRect(origin: .zero, size: Self.panelSize)
        panel.contentView = host
        if !interactive { panel.alphaValue = 0 }
        wireModel()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.reposition() }
        // Fullscreen apps live in their own Space; re-assert the panel in whichever Space is active.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.panel.orderFrontRegardless() }

        reposition()
        panel.orderFrontRegardless()

        if interactive {
            hover.onMove = { [weak self] p in self?.pointerMoved(p) }
            hover.onMouseDownOutside = { [weak self] p in self?.mouseDownOutside(p) }
            hover.onScroll = { [weak self] e in self?.scrolled(e) }
            hover.start()
        }
    }

    private func wireModel() {
        model.onCloseActivity = { [weak self] in self?.hideActivity() }
        model.onExpandCard = { [weak self] in
            guard let self else { return }
            self.cancelHide()
            self.panel.makeKey()
        }
        model.onNeedKeyboard = { [weak self] in
            guard let self else { return }
            self.closeWork?.cancel()
            self.panel.makeKey()
        }
        model.onOpenDashboard = { [weak self] in self?.openDashboard() }
        model.onCloseDashboard = { [weak self] in self?.closeDashboard() }
        model.onIslandSize = { [weak self] size in
            guard let self, size != self.islandSize else { return }
            self.islandSize = size
            self.pointerMoved(self.pointer)   // the island changed shape under a still pointer
        }
    }

    // MARK: - Pointer

    /// Screen rect of the island as currently laid out.
    var islandRect: CGRect {
        let size = islandSize == .zero ? geometry.notchSize : islandSize
        return geometry.topCenterRect(size)
    }

    func pointerMoved(_ p: CGPoint) {
        pointer = p
        let zone: CGRect
        if model.mode == .idle {
            // The live music strip is visible while idle, so it is hoverable too.
            zone = model.liveVisible ? geometry.hotZone.union(islandRect.insetBy(dx: -6, dy: -6)) : geometry.hotZone
        } else {
            zone = islandRect.insetBy(dx: -6, dy: -6)
        }
        let inside = zone.contains(p)
        if inside != pointerInside {
            pointerInside = inside
            model.hovering = inside
            inside ? pointerEntered() : pointerExited()
        }
        updateMouseCapture()
    }

    /// Only capture clicks while the pointer is actually over the island; everywhere else (and in
    /// idle, where the island is invisible) clicks fall through to the menu bar and apps below.
    private func updateMouseCapture() {
        let capture = pointerInside && (model.mode != .idle || !Prefs.hoverToPeek)
        if panel.ignoresMouseEvents == capture { panel.ignoresMouseEvents = !capture }
    }

    private func pointerEntered() {
        switch model.mode {
        case .idle:
            if Prefs.openOnHover { openDashboard() }
            else if Prefs.hoverToPeek { setMode(.peek, .spring(response: 0.32, dampingFraction: 0.7)) }
        case .open:
            closeWork?.cancel()
        case .activity:
            cancelHide()
        case .peek:
            break
        }
    }

    private func pointerExited() {
        switch model.mode {
        case .peek:
            setMode(.idle, .spring(response: 0.3, dampingFraction: 0.85))
        case .open:
            let work = DispatchWorkItem { [weak self] in
                // Don't yank the dashboard away from someone typing a reply in it.
                guard let self, !self.pointerInside, self.model.rowReplyKey == nil else { return }
                self.closeDashboard()
            }
            closeWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
        case .activity:
            if !model.expanded && !model.replying { scheduleHide(after: 2.5) }
        case .idle:
            break
        }
    }

    private func mouseDownOutside(_ p: CGPoint) {
        guard !islandRect.contains(p) else { return }
        if model.mode == .open { closeDashboard() }
    }

    // MARK: - Gestures

    private func scrolled(_ e: NSEvent) {
        guard pointerInside, e.hasPreciseScrollingDeltas else { return }
        if e.phase == .began { scrollAccum = 0; scrollAccumX = 0 }
        // Positive = fingers moving down / right, whatever the "natural scrolling" setting.
        let inverted = e.isDirectionInvertedFromDevice
        scrollAccum += inverted ? e.scrollingDeltaY : -e.scrollingDeltaY
        scrollAccumX += inverted ? e.scrollingDeltaX : -e.scrollingDeltaX
        guard Date().timeIntervalSince(lastGesture) > 0.5 else { return }
        if abs(scrollAccumX) > 40, abs(scrollAccumX) > abs(scrollAccum) * 1.5, model.media != nil,
           model.mode != .activity {
            swipeHorizontal(right: scrollAccumX > 0)
        } else if scrollAccum > 28 {
            swipe(down: true)
        } else if scrollAccum < -28 {
            swipe(down: false)
        }
    }

    /// Swipe left = next track, swipe right = previous (like flicking a card).
    func swipeHorizontal(right: Bool) {
        scrollAccum = 0
        scrollAccumX = 0
        lastGesture = Date()
        guard model.media != nil else { return }
        model.onMedia(right ? .previous : .next)
        haptic()
    }

    /// Swipe down opens (or expands a card), swipe up closes.
    func swipe(down: Bool) {
        scrollAccum = 0
        scrollAccumX = 0
        lastGesture = Date()
        switch (model.mode, down) {
        case (.idle, true), (.peek, true):
            openDashboard()
        case (.activity, true):
            if model.stage == .full && !model.expanded {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) { model.expanded = true }
                model.onExpandCard()
            }
        case (.open, false):
            closeDashboard()
        case (.activity, false):
            hideActivity()
        default:
            break
        }
    }

    // MARK: - Dashboard

    func openDashboard() {
        guard model.mode != .activity, model.mode != .open else { return }
        closeWork?.cancel()
        setMode(.open, .spring(response: 0.42, dampingFraction: 0.76))
        haptic()
    }

    func closeDashboard() {
        closeWork?.cancel()
        guard model.mode == .open else { return }
        model.rowReplyKey = nil
        model.rowReplyText = ""
        model.openRowKey = nil
        setMode(pointerInside ? .peek : .idle, .spring(response: 0.38, dampingFraction: 0.86))
    }

    private func setMode(_ mode: IslandModel.Mode, _ animation: Animation) {
        withAnimation(animation) { model.mode = mode }
        updateMouseCapture()
    }

    // MARK: - Activities (phone notifications)

    func show(_ n: PhoneNotification) {
        if model.mode == .activity, let current = model.notification {
            if current.key == n.key {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { model.notification = n }
                if !model.expanded && !pointerInside { scheduleHide(after: Prefs.displaySeconds) }
            } else if !model.expanded && !model.replying {
                // Newest wins: swap in place and count the rest ("+N") instead of replaying a backlog.
                withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                    model.notification = n
                    model.queued += 1
                    model.feedback = nil
                }
                haptic()
                if !pointerInside { scheduleHide(after: Prefs.displaySeconds) }
            } else {
                // Busy replying / reading: show only the newest one afterwards.
                queue.removeAll { $0.key == n.key }
                queue.append(n)
                model.queued = queue.count
            }
            return
        }
        model.queued = 0
        present(n)
    }

    /// The phone removed this notification (read or dismissed there).
    func remove(key: String) {
        queue.removeAll { $0.key == key }
        if model.mode == .activity, model.notification?.key == key, !model.replying { hideActivity() }
    }

    /// A short status line ("Reply sent") in the open card, then it closes.
    func flash(_ message: String, isError: Bool = false, hideAfter: TimeInterval = 1.4) {
        guard model.mode == .activity else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            model.feedback = message
            model.feedbackIsError = isError
        }
        scheduleHide(after: hideAfter)
    }

    /// Feedback from the phone ("Reply sent"): in the card if one is showing, else in the dashboard.
    func toast(_ message: String, isError: Bool = false) {
        if model.mode == .activity {
            flash(message, isError: isError, hideAfter: isError ? 3 : 1.4)
            return
        }
        toastToken += 1
        let t = toastToken
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            model.toast = message
            model.toastIsError = isError
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (isError ? 3.5 : 2.2)) { [weak self] in
            guard let self, t == self.toastToken else { return }
            withAnimation(.easeOut(duration: 0.25)) { self.model.toast = nil }
        }
    }

    private func present(_ n: PhoneNotification) {
        token += 1
        let t = token
        closeWork?.cancel()
        returnToOpen = model.mode == .open
        reposition()
        model.notification = n
        model.expanded = false
        model.replying = false
        model.replyText = ""
        model.feedback = nil
        model.stage = .compact
        setMode(.activity, .spring(response: 0.38, dampingFraction: 0.62))
        haptic()
        // 1) peek out of the notch with the avatar, 2) bloom into the full card.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.peekSeconds) { [weak self] in
            guard let self, t == self.token else { return }
            withAnimation(.spring(response: 0.46, dampingFraction: 0.68)) { self.model.stage = .full }
        }
        scheduleHide(after: Prefs.displaySeconds + Self.peekSeconds)
    }

    func hideActivity() {
        cancelHide()
        guard model.mode == .activity else { return }
        token += 1
        let t = token
        let next: IslandModel.Mode = pointerInside ? (returnToOpen ? .open : .peek) : .idle
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            model.mode = next
            model.expanded = false
        }
        updateMouseCapture()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self, t == self.token else { return }
            self.model.notification = nil
            self.model.replying = false
            if let newest = self.queue.last {
                self.model.queued = self.queue.count - 1   // the rest are in Recent / Phone tab
                self.queue.removeAll()
                self.present(newest)
            } else {
                self.model.queued = 0
            }
        }
    }

    private func scheduleHide(after seconds: TimeInterval) {
        hideWork?.cancel()
        model.hideDuration = seconds
        model.hideDeadline = Date().addingTimeInterval(seconds)
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.pointerInside, !self.model.replying else { return }
            self.hideActivity()
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func cancelHide() {
        hideWork?.cancel()
        hideWork = nil
        model.hideDeadline = nil
    }

    // MARK: - Misc

    private func haptic() {
        guard Prefs.haptics else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    private func reposition() {
        geometry = NotchGeometry.current()
        model.notchSize = geometry.notchSize
        model.hasNotch = geometry.hasNotch
        panel.setFrame(geometry.topCenterRect(Self.panelSize), display: true)
    }
}
