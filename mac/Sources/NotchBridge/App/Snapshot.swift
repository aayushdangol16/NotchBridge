import AppKit
import SwiftUI

/// `NotchBridge --snapshot <dir>` renders each notch state to PNG (on a fake wallpaper + menu bar)
/// so the design can be reviewed without screen-recording permission. Not used in normal runs.
@MainActor
enum Snapshot {
    static func run(dir: String) {
        let out = URL(fileURLWithPath: dir, isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let messenger = icon(colors: [NSColor(srgbRed: 0.0, green: 0.55, blue: 1, alpha: 1),
                                      NSColor(srgbRed: 0.65, green: 0.2, blue: 1, alpha: 1),
                                      NSColor(srgbRed: 1, green: 0.35, blue: 0.5, alpha: 1)], glyph: "bubble.left.fill")
        let whatsapp = icon(colors: [NSColor(srgbRed: 0.15, green: 0.83, blue: 0.4, alpha: 1)], glyph: "phone.fill")
        let avatar = icon(colors: [NSColor(srgbRed: 0.95, green: 0.6, blue: 0.4, alpha: 1),
                                   NSColor(srgbRed: 0.8, green: 0.35, blue: 0.45, alpha: 1)], glyph: "person.fill")
        let icons = ["com.facebook.orca": messenger, "com.whatsapp": whatsapp]

        let msg = PhoneNotification(
            key: "1", pkg: "com.facebook.orca", app: "Messenger", title: "Sita Sharma",
            text: "Are we still meeting at 6? I'll bring the notes from today's class 📚",
            sub: nil, time: Date(), actions: [WireAction(i: 0, title: "Reply", reply: true),
                                              WireAction(i: 1, title: "Mark as read", reply: false)],
            largeIcon: avatar)
        let wa = PhoneNotification(
            key: "2", pkg: "com.whatsapp", app: "WhatsApp", title: "Family group",
            text: "Mom: Dinner is ready, come home soon!", sub: nil, time: Date().addingTimeInterval(-180),
            actions: [WireAction(i: 0, title: "Reply", reply: true)], largeIcon: nil)

        func model(_ mode: IslandModel.Mode, _ n: PhoneNotification? = msg, configure: (IslandModel) -> Void = { _ in }) -> IslandModel {
            let m = IslandModel()
            m.notchSize = CGSize(width: 185, height: 32)
            m.hasNotch = true
            m.mode = mode
            m.stage = .full
            m.notification = mode == .activity ? n : nil
            m.appIcon = { icons[$0] }
            m.accent = { pkg in icons[pkg].flatMap(AccentColor.from) ?? AccentColor.fallback }
            m.hideDuration = 6
            m.hideDeadline = Date().addingTimeInterval(3.6)
            m.phoneName = "Aayush's M36"
            m.phoneConnected = true
            m.recent = [msg, wa]
            configure(m)
            return m
        }

        let shots: [(String, IslandModel)] = [
            ("01-peek", model(.peek)),
            ("02-open-home", model(.open)),
            ("03-open-phone", model(.open) { $0.tab = .phone }),
            ("04-open-offline", model(.open) { $0.phoneConnected = false; $0.recent = [] }),
            ("05-activity-compact", model(.activity) { $0.stage = .compact }),
            ("06-activity-card", model(.activity)),
            ("07-card-whatsapp-queued", model(.activity, wa) { $0.queued = 2 }),
            ("08-card-actions", model(.activity) { $0.expanded = true; $0.hovering = true; $0.hideDeadline = nil }),
            ("09-card-sent", model(.activity) { $0.feedback = "Reply sent" }),
        ]

        for (name, m) in shots {
            let view = ZStack(alignment: .top) {
                LinearGradient(colors: [Color(red: 0.16, green: 0.24, blue: 0.42), Color(red: 0.55, green: 0.42, blue: 0.62)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Rectangle().fill(.white.opacity(0.18)).frame(height: 32)   // menu bar
                IslandView(model: m)
            }
            .frame(width: IslandController.panelSize.width, height: IslandController.panelSize.height)
            .environment(\.colorScheme, .dark)

            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let cg = renderer.cgImage,
                  let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { continue }
            try? png.write(to: out.appendingPathComponent("\(name).png"))
            print("wrote \(name).png")
        }
    }

    private static func icon(colors: [NSColor], glyph: String) -> NSImage {
        let size = NSSize(width: 96, height: 96)
        return NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath(ovalIn: rect)
            NSGradient(colors: colors.count > 1 ? colors : colors + colors)?.draw(in: path, angle: -45)
            if let sym = NSImage(systemSymbolName: glyph, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 44, weight: .semibold)) {
                let tinted = NSImage(size: sym.size, flipped: false) { r in
                    sym.draw(in: r)
                    NSColor.white.set()
                    r.fill(using: .sourceAtop)
                    return true
                }
                let s = tinted.size
                tinted.draw(in: NSRect(x: (rect.width - s.width) / 2, y: (rect.height - s.height) / 2, width: s.width, height: s.height))
            }
            return true
        }
    }
}
