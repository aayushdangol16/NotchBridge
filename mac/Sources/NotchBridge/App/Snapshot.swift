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
        let albumArt = icon(colors: [NSColor(srgbRed: 0.95, green: 0.25, blue: 0.35, alpha: 1),
                                     NSColor(srgbRed: 1, green: 0.6, blue: 0.2, alpha: 1)], glyph: "music.note", square: true)
        let song = NowPlaying(source: .mac, title: "Blinding Lights", artist: "The Weeknd", album: "After Hours",
                              duration: 200, elapsed: 74, elapsedAt: Date(), rate: 1, isPlaying: true,
                              appName: "Spotify", appID: "com.spotify.client", artwork: albumArt, artKey: "a")
        let phoneSong = NowPlaying(source: .phone, title: "Resham Firiri", artist: "Nepali Folk", album: "",
                                   duration: 245, elapsed: 30, elapsedAt: Date(), rate: 1, isPlaying: false,
                                   appName: "YouTube Music", appID: "com.google.android.apps.youtube.music",
                                   artwork: nil, artKey: nil)

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

        let now = Date()
        let events = [
            CalEvent(id: "a", title: "Design review", start: now.addingTimeInterval(300), end: now.addingTimeInterval(2100),
                     isAllDay: false, color: .systemPurple, location: "Zoom", calendarTitle: "Work",
                     joinURL: URL(string: "https://zoom.us/j/1")),
            CalEvent(id: "b", title: "Lunch with Sita", start: now.addingTimeInterval(7200), end: now.addingTimeInterval(10800),
                     isAllDay: false, color: .systemOrange, location: "Café", calendarTitle: "Personal", joinURL: nil),
            CalEvent(id: "c", title: "Sprint planning", start: now.addingTimeInterval(90000), end: now.addingTimeInterval(93600),
                     isAllDay: false, color: .systemBlue, location: nil, calendarTitle: "Work", joinURL: nil),
        ]

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
            m.phoneBattery = 82
            m.recent = [msg, wa]
            m.calendarAccess = .granted
            m.events = events
            configure(m)
            return m
        }

        let shots: [(String, IslandModel)] = [
            ("01-peek", model(.peek)),
            ("02-open-home", model(.open)),
            ("03-open-phone", model(.open) { $0.tab = .phone }),
            ("03b-phone-expanded", model(.open) { $0.tab = .phone; $0.openRowKey = msg.key; $0.phoneCharging = true }),
            ("03c-phone-ringing-toast", model(.open) { $0.tab = .phone; $0.phoneRinging = true; $0.phoneBattery = 14; $0.toast = "Ringing your phone" }),
            ("04-open-offline", model(.open) { $0.phoneConnected = false; $0.recent = [] }),
            ("05-activity-compact", model(.activity) { $0.stage = .compact }),
            ("06-activity-card", model(.activity)),
            ("06b-card-short-no-actions", model(.activity, PhoneNotification(
                key: "9", pkg: "com.whatsapp", app: "WhatsApp", title: "Ram", text: "ok 👍", sub: nil, time: Date(),
                actions: [], largeIcon: nil))),
            ("07-card-whatsapp-queued", model(.activity, wa) { $0.queued = 2 }),
            ("08-card-actions", model(.activity) { $0.expanded = true; $0.hovering = true; $0.hideDeadline = nil }),
            ("09-card-sent", model(.activity) { $0.feedback = "Reply sent" }),
            ("14-charging", model(.activity) { $0.notification = nil; $0.system = .charging(level: 64, charging: true); $0.stage = .compact }),
            ("15-low-battery", model(.activity) { $0.notification = nil; $0.system = .lowBattery(level: 10); $0.stage = .compact }),
            ("16-meeting-card", model(.activity) { $0.notification = nil; $0.system = .meeting(events[0]) }),
            ("17-calendar-tab", model(.open) { $0.tab = .calendar }),
            ("18-home-next-event", model(.open)),
            ("19-shelf-empty-drop", model(.open) { $0.tab = .shelf; $0.dropTargeted = true }),
            ("20-shelf-items", model(.open) { m in
                m.tab = .shelf
                let paths = ["/Applications/Safari.app", "/System/Applications/Notes.app", "/System/Library/Desktop Pictures",
                             "/System/Applications/Calculator.app"]
                m.shelfItems = paths.map { ShelfItem(id: UUID(), path: $0, addedAt: Date()) }
                m.transfers = [m.shelfItems[1].id: 0.62]
            }),
            ("21-volume", model(.activity) { $0.notification = nil; $0.system = .volume(level: 62, muted: false); $0.stage = .compact }),
            ("10-idle-live-music", model(.idle) { $0.media = song; $0.mediaAccent = AccentColor.from(albumArt) ?? AccentColor.fallback }),
            ("11-peek-music", model(.peek) { $0.media = song; $0.mediaAccent = AccentColor.from(albumArt) ?? AccentColor.fallback }),
            ("12-home-music", model(.open) { $0.media = song; $0.mediaAccent = AccentColor.from(albumArt) ?? AccentColor.fallback }),
            ("13-home-phone-music-paused", model(.open) { $0.media = phoneSong }),
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

    private static func icon(colors: [NSColor], glyph: String, square: Bool = false) -> NSImage {
        let size = NSSize(width: 96, height: 96)
        return NSImage(size: size, flipped: false) { rect in
            let path = square ? NSBezierPath(rect: rect) : NSBezierPath(ovalIn: rect)
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
