import Foundation
import UserNotifications

/// Optional mirror into macOS Notification Center, so phone notifications are kept in history.
final class SystemNotifier {
    private let center = UNUserNotificationCenter.current()
    private let defaultsKey = "mirrorToNotificationCenter"

    var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: defaultsKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: defaultsKey)
            if newValue { requestAuthorization() }
        }
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(_ n: PhoneNotification) {
        guard enabled else { return }
        let content = UNMutableNotificationContent()
        content.title = n.title.isEmpty ? n.app : n.title
        content.subtitle = n.title.isEmpty ? "" : n.app
        content.body = n.text
        content.threadIdentifier = n.pkg
        // The notch already got the user's attention; just keep a quiet copy in the list.
        content.interruptionLevel = .passive
        center.add(UNNotificationRequest(identifier: n.key, content: content, trigger: nil))
    }

    func remove(key: String) {
        center.removeDeliveredNotifications(withIdentifiers: [key])
    }
}
