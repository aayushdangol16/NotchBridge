import AppKit
import SwiftUI

/// `NotchBridge --selftest` drives an invisible IslandController with synthetic pointer positions,
/// gestures and notifications, and checks every state transition. Exit code 0 = all passed.
/// Hosts a NotificationCard at the card's real inner width so its size can be measured.
private struct CardProbe: View {
    @ObservedObject var model: IslandModel
    let n: PhoneNotification
    @Namespace private var ns
    var body: some View {
        NotificationCard(model: model, n: n, accent: .blue, ns: ns).frame(width: IslandView.cardWidth - 24)
    }
}

enum SelfTest {
    static func run() -> Int32 {
        Prefs.registerDefaults()
        // Isolate from the user's settings.
        let d = UserDefaults.standard
        let saved = (d.object(forKey: Prefs.Key.hoverToPeek), d.object(forKey: Prefs.Key.openOnHover),
                     d.object(forKey: Prefs.Key.displaySeconds), d.object(forKey: Prefs.Key.haptics))
        d.set(true, forKey: Prefs.Key.hoverToPeek)
        d.set(false, forKey: Prefs.Key.openOnHover)
        d.set(2.0, forKey: Prefs.Key.displaySeconds)
        d.set(false, forKey: Prefs.Key.haptics)
        defer {
            func restore(_ v: Any?, _ k: String) { if let v { d.set(v, forKey: k) } else { d.removeObject(forKey: k) } }
            restore(saved.0, Prefs.Key.hoverToPeek); restore(saved.1, Prefs.Key.openOnHover)
            restore(saved.2, Prefs.Key.displaySeconds); restore(saved.3, Prefs.Key.haptics)
        }

        let c = IslandController(interactive: false)
        let m = c.model
        let far = CGPoint(x: c.geometry.screenFrame.minX + 20, y: c.geometry.screenFrame.minY + 20)
        let notch = CGPoint(x: c.geometry.hotZone.midX, y: c.geometry.hotZone.midY)
        final class Counter { var n = 0 }
        let failures = Counter()

        func spin(_ s: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
        func check(_ name: String, _ ok: Bool) {
            print("\(ok ? "PASS" : "FAIL")  \(name)  (mode=\(m.mode) stage=\(m.stage) queued=\(m.queued))")
            if !ok { failures.n += 1 }
        }
        func note(_ key: String, _ title: String) -> PhoneNotification {
            PhoneNotification(key: key, pkg: "com.test", app: "Test", title: title, text: "hello",
                              sub: nil, time: Date(), actions: [], largeIcon: nil)
        }

        spin(0.3)
        c.pointerMoved(far); spin(0.2)
        check("starts idle", m.mode == .idle)

        c.pointerMoved(notch); spin(0.3)
        check("hover over notch -> peek", m.mode == .peek && m.hovering)

        c.pointerMoved(far); spin(0.3)
        check("leave -> idle", m.mode == .idle && !m.hovering)

        c.pointerMoved(notch); spin(0.2)
        m.onOpenDashboard(); spin(0.4)
        check("click in peek -> open", m.mode == .open)

        c.pointerMoved(notch); spin(0.6)
        check("open stays open while pointer inside", m.mode == .open)

        c.swipe(down: false); spin(0.4)
        check("swipe up closes (pointer inside -> peek)", m.mode == .peek)

        c.swipe(down: true); spin(0.4)
        check("swipe down opens", m.mode == .open)

        c.pointerMoved(far); spin(0.8)
        check("leaving the dashboard closes it", m.mode == .idle)

        c.show(note("a", "First")); spin(0.6)
        check("notification opens straight into the card (one step)", m.mode == .activity && m.stage == .full)
        let long = PhoneNotification(key: "a", pkg: "com.test", app: "Test", title: "A much longer title that will not fit",
                                     text: String(repeating: "A very long message that wraps onto many lines. ", count: 6),
                                     sub: nil, time: Date(),
                                     actions: [WireAction(i: 0, title: "Reply", reply: true), WireAction(i: 1, title: "Mark as read", reply: false)],
                                     largeIcon: nil)
        // Measure the card's own layout (the invisible test panel doesn't report sizes).
        func cardSize(_ n: PhoneNotification) -> CGSize {
            NSHostingView(rootView: CardProbe(model: m, n: n)).fittingSize
        }
        let shortSize = cardSize(note("s", "Hi"))
        let longSize = cardSize(long)
        m.hovering = true
        let hoverSize = cardSize(long)
        m.hovering = false
        m.replying = true
        let replySize = cardSize(long)
        m.replying = false
        m.feedback = "Reply sent"
        let feedbackSize = cardSize(long)
        m.feedback = nil
        print("  card heights: short=\(shortSize.height) long=\(longSize.height) hover=\(hoverSize.height) reply=\(replySize.height) sent=\(feedbackSize.height)")
        check("card size is uniform (short vs long text, with/without actions)",
              shortSize.height > 60 && shortSize.height == longSize.height)
        check("hovering, replying and the status line keep the same size",
              hoverSize.height == shortSize.height && replySize.height == shortSize.height && feedbackSize.height == shortSize.height)
        c.show(long); spin(0.3)

        c.show(note("b", "Second")); spin(0.2)
        check("burst: newest replaces card, +1", m.notification?.key == "b" && m.queued == 1)

        c.show(note("b", "Second (edited)")); spin(0.2)
        check("same key updates in place", m.notification?.title == "Second (edited)" && m.queued == 1)

        c.remove(key: "b"); spin(0.6)
        check("removed on phone -> card closes", m.mode == .idle && m.notification == nil)

        c.show(note("c", "Timed")); spin(2.0 + IslandController.peekSeconds + 0.7)
        check("card auto-hides after display time", m.mode == .idle)

        c.pointerMoved(notch); spin(0.2)
        m.onOpenDashboard(); spin(0.3)
        c.show(note("d", "While open")); spin(0.3)
        check("notification while dashboard open -> activity", m.mode == .activity)
        m.onOpenNotification(m.notification!); spin(0.4)
        check("clicking the card opens it in the Phone tab", m.mode == .open && m.tab == .phone && m.openRowKey == "d")
        m.openRowKey = nil
        m.tab = .home
        c.show(note("d2", "While open again")); spin(0.3)
        c.pointerMoved(CGPoint(x: c.islandRect.midX, y: c.islandRect.midY)); spin(0.2)
        m.onCloseActivity(); spin(0.6)
        check("closing it returns to the dashboard", m.mode == .open)

        c.toast("Reply sent"); spin(0.2)
        check("toast in the dashboard", m.toast == "Reply sent")
        spin(2.4)
        check("toast clears itself", m.toast == nil)

        m.rowReplyKey = "x"
        c.pointerMoved(far); spin(0.8)
        check("dashboard stays open while typing a reply", m.mode == .open)
        m.rowReplyKey = nil
        c.pointerMoved(notch); spin(0.1)
        c.pointerMoved(far); spin(0.8)
        check("back to idle", m.mode == .idle)

        var commands: [MediaCommand] = []
        m.onMedia = { commands.append($0) }
        m.media = NowPlaying(source: .mac, title: "Song", artist: "Artist", album: "", duration: 100, elapsed: 0,
                             elapsedAt: Date(), rate: 1, isPlaying: true, appName: "Music", appID: "x",
                             artwork: nil, artKey: nil)
        spin(0.4)
        check("music playing -> live strip while idle", m.liveVisible && m.mode == .idle)
        c.pointerMoved(CGPoint(x: c.islandRect.maxX - 8, y: c.islandRect.midY)); spin(0.3)
        check("hovering the live strip (beside the notch) -> peek", m.mode == .peek)
        c.swipeHorizontal(right: false)
        check("swipe left -> next track", commands.last == .next)
        c.swipeHorizontal(right: true)
        check("swipe right -> previous track", commands.last == .previous)
        c.pointerMoved(far); spin(0.4)
        m.media?.isPlaying = false; spin(0.3)
        check("paused -> live strip hides", !m.liveVisible && m.mode == .idle)
        m.media = nil

        // --- Phase 4: battery rules, join links, system activities ---
        typealias B = BatteryMonitor.State
        check("plugging in -> charging activity",
              BatteryMonitor.transitions(from: B(level: 50, charging: false, pluggedIn: false),
                                         to: B(level: 50, charging: true, pluggedIn: true)) == [.charging(level: 50, charging: true)])
        check("dropping to 20% on battery -> low battery",
              BatteryMonitor.transitions(from: B(level: 21, charging: false, pluggedIn: false),
                                         to: B(level: 20, charging: false, pluggedIn: false)) == [.lowBattery(level: 20)])
        check("19% after 20% -> no repeat",
              BatteryMonitor.transitions(from: B(level: 20, charging: false, pluggedIn: false),
                                         to: B(level: 19, charging: false, pluggedIn: false)).isEmpty)
        check("10% -> second warning",
              BatteryMonitor.transitions(from: B(level: 11, charging: false, pluggedIn: false),
                                         to: B(level: 10, charging: false, pluggedIn: false)) == [.lowBattery(level: 10)])
        check("zoom link found in notes",
              CalendarService.joinLink(in: [nil, "Room 4", "Join: https://us02web.zoom.us/j/123456789?pwd=abc."])
                == URL(string: "https://us02web.zoom.us/j/123456789?pwd=abc"))
        check("meet link found in location",
              CalendarService.joinLink(in: ["https://meet.google.com/abc-defg-hij"]) == URL(string: "https://meet.google.com/abc-defg-hij"))
        check("teams link found",
              CalendarService.joinLink(in: ["Click https://teams.microsoft.com/l/meetup-join/19%3ameeting_x%40thread.v2/0 to join"]) != nil)
        check("ordinary link ignored", CalendarService.joinLink(in: ["https://example.com/agenda"]) == nil)

        c.pointerMoved(far); spin(0.3)
        c.showSystem(.charging(level: 80, charging: true)); spin(0.3)
        check("charging -> compact strip", m.mode == .activity && m.system != nil && m.stage == .compact)
        spin(3.5 + 0.7)
        check("charging strip hides itself", m.mode == .idle && m.system == nil)

        let ev = CalEvent(id: "e1", title: "Standup", start: Date().addingTimeInterval(240),
                          end: Date().addingTimeInterval(1800), isAllDay: false, color: .systemPurple,
                          location: nil, calendarTitle: "Work", joinURL: URL(string: "https://meet.google.com/abc-defg-hij"))
        c.showSystem(.meeting(ev)); spin(0.9)
        check("meeting reminder -> full card", m.mode == .activity && m.stage == .full && m.system == .meeting(ev))
        c.show(note("p", "Phone beats meeting")); spin(0.2)
        check("phone notification takes over the meeting", m.notification?.key == "p" && m.system == nil)
        m.onCloseActivity(); spin(0.7)
        check("meeting card comes back afterwards", m.system == .meeting(ev))
        m.onCloseActivity(); spin(0.7)
        check("then idle", m.mode == .idle && m.system == nil)
        c.show(note("q", "Busy")); spin(0.2)
        c.showSystem(.charging(level: 50, charging: true)); spin(0.2)
        check("battery strip dropped while a phone card shows", m.notification?.key == "q" && m.system == nil)
        m.onCloseActivity(); spin(0.7)
        check("nothing left over", m.mode == .idle && m.system == nil && m.notification == nil)

        // --- Phase 5: shelf store + drag to notch ---
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("nb-selftest-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let f1 = tmp.appendingPathComponent("report.pdf"), f2 = tmp.appendingPathComponent("photo.jpg")
        FileManager.default.createFile(atPath: f1.path, contents: Data("a".utf8))
        FileManager.default.createFile(atPath: f2.path, contents: Data("b".utf8))
        let shelf = ShelfStore(directory: tmp)
        check("shelf adds files", shelf.add([f1, f2]) == 2 && shelf.items.count == 2)
        check("shelf skips duplicates", shelf.add([f1]) == 0 && shelf.items.count == 2)
        check("newest first", shelf.items.first?.name == "photo.jpg")
        check("shelf persists", ShelfStore(directory: tmp).items.map(\.name) == ["photo.jpg", "report.pdf"])
        try? FileManager.default.removeItem(at: f2)
        check("missing files dropped on load", ShelfStore(directory: tmp).items.map(\.name) == ["report.pdf"])
        shelf.remove(shelf.items[0])
        check("remove", shelf.items.count == 1)

        c.pointerMoved(far); spin(0.4)
        let nearNotch = CGPoint(x: c.dragZone.maxX - 20, y: c.dragZone.minY + 8)
        c.pointerMoved(nearNotch, fileDrag: false); spin(0.3)
        check("plain pointer beside the notch does nothing", m.mode == .idle)
        c.pointerMoved(nearNotch, fileDrag: true); spin(0.4)
        check("dragging a file toward the notch opens the Shelf", m.mode == .open && m.tab == .shelf && m.fileDragActive)
        c.pointerMoved(far, fileDrag: true); spin(0.8)
        check("dashboard stays open while the file is still being dragged", m.mode == .open)
        c.pointerMoved(far, fileDrag: false); spin(0.8)
        check("drag ends away from the notch -> closes", m.mode == .idle && !m.fileDragActive)
        m.tab = .home

        // --- Phase 6: volume strip ---
        c.showSystem(.volume(level: 40, muted: false)); spin(0.3)
        check("volume change -> strip", m.mode == .activity && m.system == .volume(level: 40, muted: false))
        c.showSystem(.volume(level: 50, muted: false)); spin(0.1)
        check("holding the volume key updates the same strip", m.system == .volume(level: 50, muted: false) && m.mode == .activity)
        spin(1.6 + 0.8)
        check("volume strip hides itself", m.mode == .idle && m.system == nil)
        check("five dashboard tabs", IslandModel.Tab.allCases.count == 5)

        print(failures.n == 0 ? "ALL PASSED" : "\(failures.n) FAILED")
        return failures.n == 0 ? 0 : 1
    }
}
