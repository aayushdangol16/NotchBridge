import AppKit
import Foundation

/// Recent phone notifications plus per-app icon cache. Main thread only.
final class NotificationStore: ObservableObject {
    @Published private(set) var items: [PhoneNotification] = []
    private var appIcons: [String: NSImage] = [:]
    private let maxItems = 50

    /// Called when a notification should pop up (new, or its content changed and it may alert again).
    var onAlert: ((PhoneNotification) -> Void)?
    var onRemove: ((String) -> Void)?

    private var accents: [String: NSColor] = [:]

    func icon(for pkg: String) -> NSImage? { appIcons[pkg] }
    func accent(for pkg: String) -> NSColor { accents[pkg] ?? AccentColor.fallback }

    func ingest(_ w: WireNotification, mayAlert: Bool) {
        if let img = NSImage.fromBase64PNG(w.icon) {
            appIcons[w.pkg] = img
            accents[w.pkg] = AccentColor.from(img)
        }

        let n = PhoneNotification(
            key: w.key,
            pkg: w.pkg,
            app: w.app,
            title: w.title ?? "",
            text: w.text ?? "",
            sub: w.sub,
            time: Date(timeIntervalSince1970: TimeInterval(w.time) / 1000),
            actions: w.actions ?? [],
            largeIcon: NSImage.fromBase64PNG(w.large)
        )

        let existing = items.firstIndex { $0.key == n.key }
        let contentChanged = existing.map { items[$0].title != n.title || items[$0].text != n.text } ?? true
        if let existing { items.remove(at: existing) }
        items.insert(n, at: 0)
        if items.count > maxItems { items.removeLast(items.count - maxItems) }

        // Pop up only when the phone itself alerted for it (it knows whether this is a fresh post or a
        // quiet "alert once" update — WhatsApp re-posts every unread chat that way on each new message),
        // and only if the text actually changed, so pure refreshes (avatar loaded…) stay quiet.
        let silent = w.silent ?? false
        let phoneAlert = w.alert ?? (!silent && !(existing != nil && (w.alertOnce ?? false)))  // older phone app
        let alert = mayAlert && contentChanged && phoneAlert
        DebugLog.write("posted pkg=\(w.pkg) new=\(existing == nil) changed=\(contentChanged) silent=\(silent) " +
                       "alertOnce=\(w.alertOnce ?? false) phoneAlert=\(w.alert.map(String.init) ?? "n/a") " +
                       "mayAlert=\(mayAlert) -> \(alert ? "POP" : "list only")")
        if alert { onAlert?(n) }
    }

    func replaceAll(_ list: [WireNotification]) {
        items.removeAll()
        for w in list.sorted(by: { $0.time < $1.time }) { ingest(w, mayAlert: false) }
    }

    func remove(key: String) {
        items.removeAll { $0.key == key }
        onRemove?(key)
    }
}
