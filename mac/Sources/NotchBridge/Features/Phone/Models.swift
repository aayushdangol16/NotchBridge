import AppKit
import Foundation

// MARK: - Wire format (must match android/.../Protocol.kt)
//
// Every WebSocket frame is a binary AES-256-GCM box: nonce(12) | ciphertext | tag(16).
// The plaintext is a UTF-8 JSON object with a "type" field.

struct WireAction: Codable, Hashable {
    let i: Int          // index into Notification.actions on the phone
    let title: String
    let reply: Bool     // true when the action accepts free-form text (RemoteInput)
}

struct WireNotification: Codable {
    let key: String     // StatusBarNotification.key, unique per notification on the phone
    let pkg: String
    let app: String
    let title: String?
    let text: String?
    let sub: String?
    let time: Int64     // ms since epoch
    let actions: [WireAction]?
    let icon: String?   // base64 PNG app icon, sent once per app per connection
    let large: String?  // base64 PNG large icon / avatar
    let silent: Bool?   // low-importance channel: list it, don't pop it
    let alertOnce: Bool?
    let alert: Bool?    // the phone's own verdict: did/would this buzz the phone? (newer phone app)
    let call: Bool?     // incoming call
}

/// Phone -> Mac
struct PhoneMessage: Decodable {
    let type: String            // hello | posted | removed | sync | result | battery | ringing
    let device: String?
    let model: String?
    let n: WireNotification?
    let key: String?
    let list: [WireNotification]?
    let ok: Bool?
    let msg: String?
    let level: Int?             // battery: percent
    let charging: Bool?         // battery
    let on: Bool?               // ringing (find my phone)
}

/// Mac -> Phone
struct MacCommand: Encodable {
    let type: String            // welcome | dismiss | action | reply | ring | ring_stop
    var key: String? = nil
    var i: Int? = nil
    var text: String? = nil
    var name: String? = nil
}

// MARK: - App model

struct PhoneNotification: Identifiable, Equatable {
    var id: String { key }
    let key: String
    let pkg: String
    let app: String
    var title: String
    var text: String
    var sub: String?
    var time: Date
    var actions: [WireAction]
    var largeIcon: NSImage?

    var replyAction: WireAction? { actions.first { $0.reply } }
    var buttonActions: [WireAction] { actions.filter { !$0.reply } }

    static func == (a: PhoneNotification, b: PhoneNotification) -> Bool {
        a.key == b.key && a.title == b.title && a.text == b.text && a.time == b.time
    }
}

extension NSImage {
    static func fromBase64PNG(_ s: String?) -> NSImage? {
        guard let s, let data = Data(base64Encoded: s) else { return nil }
        return NSImage(data: data)
    }
}
