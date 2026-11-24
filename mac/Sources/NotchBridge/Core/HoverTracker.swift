import AppKit

/// Watches the pointer without needing Accessibility permission: a 20 Hz position poll (plus local
/// move events over our own panel), clicks anywhere (to close the dashboard), and scroll gestures.
final class HoverTracker {
    /// Pointer position and whether a file drag (Finder etc.) is in progress.
    var onMove: (CGPoint, Bool) -> Void = { _, _ in }
    var onMouseDownOutside: (CGPoint) -> Void = { _ in }
    var onScroll: (NSEvent) -> Void = { _ in }

    private var monitors: [Any] = []
    private var poll: Timer?
    private var lastPoint = CGPoint(x: -1, y: -1)
    private var lastFileDrag = false
    private var wasPressed = false
    private var dragBaseline = NSPasteboard(name: .drag).changeCount

    /// Drags the shelf can take: files, promised files, images, links.
    private static let droppableTypes: Set<NSPasteboard.PasteboardType> = [
        .fileURL, .URL, .tiff, .png, .pdf,
        NSPasteboard.PasteboardType("public.jpeg"),
        NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url"),
        NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-content-type"),
        NSPasteboard.PasteboardType("com.apple.NSFilePromiseItemMetaData"),
        NSPasteboard.PasteboardType("NSPromiseContentsPboardType"),
        NSPasteboard.PasteboardType("Apple files promise pasteboard type"),
    ]

    func start() {
        // Pointer position is polled (cheap: one read, 20×/s) rather than taken from a global
        // mouse-moved monitor, which makes the window server copy every mouse event into our
        // process and cost a few % CPU whenever the mouse moves. Local events (pointer over our
        // own panel) still update instantly.
        let move: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        if let m = NSEvent.addLocalMonitorForEvents(matching: move, handler: { [weak self] e in self?.tick(); return e }) {
            monitors.append(m)
        }
        // Clicks in other apps = clicks outside the island.
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            self?.onMouseDownOutside(NSEvent.mouseLocation)
        }) {
            monitors.append(m)
        }
        // Scrolls are delivered to our panel when the pointer is over it.
        if let m = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] e in
            self?.onScroll(e)
            return e
        }) {
            monitors.append(m)
        }
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = 0.015
        RunLoop.main.add(t, forMode: .common)
        poll = t
    }

    private func tick() {
        let p = NSEvent.mouseLocation
        // A file drag = left button held + the drag pasteboard changed since the button went down
        // and it carries file URLs. (Only touched while the button is down, so it's cheap.)
        let pressed = NSEvent.pressedMouseButtons & 1 != 0
        var fileDrag = false
        if pressed {
            let pb = NSPasteboard(name: .drag)
            if pb.changeCount != dragBaseline {
                let types = pb.types ?? []
                fileDrag = !Self.droppableTypes.isDisjoint(with: types)
                if fileDrag != lastFileDrag {
                    DebugLog.write("drag: started droppable=\(fileDrag) types=\(types.prefix(5).map(\.rawValue))")
                }
            }
        } else if wasPressed {
            dragBaseline = NSPasteboard(name: .drag).changeCount
        }
        wasPressed = pressed
        guard p != lastPoint || fileDrag != lastFileDrag else { return }
        lastPoint = p
        lastFileDrag = fileDrag
        onMove(p, fileDrag)
    }

    deinit {
        monitors.forEach(NSEvent.removeMonitor)
        poll?.invalidate()
    }
}
