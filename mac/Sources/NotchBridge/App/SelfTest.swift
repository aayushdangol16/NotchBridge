import AppKit

/// `NotchBridge --selftest` drives an invisible IslandController with synthetic pointer positions,
/// gestures and notifications, and checks every state transition. Exit code 0 = all passed.
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
        var failures = 0

        func spin(_ s: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
        func check(_ name: String, _ ok: Bool) {
            print("\(ok ? "PASS" : "FAIL")  \(name)  (mode=\(m.mode) stage=\(m.stage) queued=\(m.queued))")
            if !ok { failures += 1 }
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

        c.show(note("a", "First")); spin(0.2)
        check("notification -> activity (compact)", m.mode == .activity && m.stage == .compact)
        spin(0.6)
        check("compact -> full card", m.stage == .full)

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
        c.pointerMoved(CGPoint(x: c.islandRect.midX, y: c.islandRect.midY)); spin(0.2)
        m.onCloseActivity(); spin(0.6)
        check("closing it returns to the dashboard", m.mode == .open)

        c.pointerMoved(far); spin(0.8)
        check("back to idle", m.mode == .idle)

        print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
        return failures == 0 ? 0 : 1
    }
}
