import AppKit

/// An always-present, invisible drag destination over the notch (plus a little margin).
///
/// The island panel is click-through while idle, so it can't receive drags then. This small window
/// sits just below it and lets macOS itself tell us "a file is being dragged over the notch" —
/// no guessing from mouse state. Dropping right on it works too.
final class NotchDropZone {
    var onDragEnter: () -> Void = {}
    var onDragActivity: () -> Void = {}
    var onDrop: (NSPasteboard) -> Void = { _ in }

    private let panel: NSPanel
    private let view: DropZoneView

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // One below the island panel: when the island is open and capturing, it gets the drag instead.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        view = DropZoneView()
        panel.contentView = view
        view.zone = self
    }

    func place(over rect: CGRect) {
        panel.setFrame(rect, display: true)
        panel.orderFrontRegardless()
    }

    func reassert() { panel.orderFrontRegardless() }

    /// Pasteboard types the zone (and the island) accept.
    static let types: [NSPasteboard.PasteboardType] = [
        .fileURL, .URL, .tiff, .png, .pdf,
        NSPasteboard.PasteboardType("public.jpeg"),
        NSPasteboard.PasteboardType(kPasteboardTypeFileURLPromise),
        NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-content-type"),
        NSPasteboard.PasteboardType("com.apple.NSFilePromiseItemMetaData"),
    ] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
}

private final class DropZoneView: NSView {
    weak var zone: NotchDropZone?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes(NotchDropZone.types)
        // Practically invisible, but not 100 % transparent so the window server treats it as a target.
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0, alpha: 0.005).cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        DebugLog.write("drag: entered the notch drop zone")
        zone?.onDragEnter()
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        zone?.onDragActivity()
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        DebugLog.write("drop: released on the notch drop zone")
        zone?.onDrop(sender.draggingPasteboard)
        return true
    }
}
