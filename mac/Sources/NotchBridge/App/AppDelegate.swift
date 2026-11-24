import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let server = BridgeServer()
    private let store = NotificationStore()
    private let island = IslandController()
    private let settingsWindow = SettingsWindowController()
    private let media = MediaCenter()
    private let calendar = CalendarService()
    private let battery = BatteryMonitor()
    private let shelf = ShelfStore()
    private let volume = VolumeMonitor()
    private var transferItems: [String: UUID] = [:]   // transfer id -> shelf item
    private var cancellables = Set<AnyCancellable>()
    private let pairingWindow = PairingWindowController()
    private let systemNotifier = SystemNotifier()
    private var statusItem: NSStatusItem!
    private var status: BridgeServer.Status = .starting

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.registerDefaults()
        setUpStatusItem()
        wireIsland()
        wireSettings()
        wireStore()
        wireServer()

        if systemNotifier.enabled { systemNotifier.requestAuthorization() }
        server.start()
        wireMedia()
        wireCalendarAndBattery()
        wireShelf()
        wireVolume()
        setUpLoginItemOnce()

        if Pairing.shared.pairedDevice == nil {
            pairingWindow.show()
        }
    }

    // MARK: - Wiring

    private func wireServer() {
        server.onStatus = { [weak self] s in
            guard let self else { return }
            self.status = s
            self.pairingWindow.model.status = s
            self.updateStatusIcon()
            self.island.model.phoneConnected = { if case .connected = s { return true } else { return false } }()
            self.island.model.phoneName = Pairing.shared.pairedDevice
            if case .connected = s {} else {
                self.island.model.phoneRinging = false
                self.media.phoneDisconnected()
            }
            self.settingsWindow.model.phoneStatus = self.statusText
            if case .connected = s, self.pairingWindow.isVisible {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.pairingWindow.close() }
            }
        }
        server.onMessage = { [weak self] m in self?.handle(m) }

        pairingWindow.model.onReset = { [weak self] in
            Pairing.shared.reset()
            self?.server.disconnectPhone()
            self?.pairingWindow.model.refresh()
        }
    }

    private func handle(_ m: PhoneMessage) {
        switch m.type {
        case "posted":
            if let n = m.n { store.ingest(n, mayAlert: true) }
        case "removed":
            if let key = m.key {
                DebugLog.write("removed pkg=\(key.split(separator: "|").dropFirst().first ?? "?")")
                store.remove(key: key)
            }
        case "sync":
            DebugLog.write("sync \(m.list?.count ?? 0) notifications (listed, not popped)")
            store.replaceAll(m.list ?? [])
        case "result":
            if m.ok == true {
                island.toast(m.msg ?? "Done")
            } else {
                island.toast(m.msg ?? "The phone couldn't do that", isError: true)
            }
        case "battery":
            island.model.phoneBattery = m.level
            island.model.phoneCharging = m.charging ?? false
        case "ringing":
            island.model.phoneRinging = m.on ?? false
        case "media":
            media.updatePhone(m.m)
        case "file_result":
            if let id = m.id, let item = transferItems.removeValue(forKey: id) {
                island.model.transfers[item] = nil
            }
            let name = m.name.map { "“\($0)”" } ?? "File"
            if m.ok == true {
                island.toast("\(name) sent to your phone")
            } else {
                island.toast(m.msg ?? "The phone couldn't save \(name)", isError: true)
            }
        default:
            break
        }
    }

    private func wireStore() {
        store.onAlert = { [weak self] n in
            self?.island.show(n)
            self?.systemNotifier.post(n)
        }
        store.onRemove = { [weak self] key in
            self?.island.remove(key: key)
            self?.systemNotifier.remove(key: key)
        }
    }

    private func wireIsland() {
        let m = island.model
        m.phoneName = Pairing.shared.pairedDevice
        m.onOpenSettings = { [weak self] in self?.settingsWindow.show() }
        m.onPairPhone = { [weak self] in self?.pairingWindow.show() }
        m.onReshow = { [weak self] n in self?.island.show(n) }
        m.onRing = { [weak self] on in
            guard let self else { return }
            guard case .connected = self.status else {
                self.island.toast("Phone is not connected", isError: true)
                return
            }
            self.server.send(MacCommand(type: on ? "ring" : "ring_stop"))
            self.island.model.phoneRinging = on
        }
        m.onClearAll = { [weak self] in
            guard let self else { return }
            for n in self.store.items {
                self.server.send(MacCommand(type: "dismiss", key: n.key))
                self.store.remove(key: n.key)
            }
        }
        store.$items
            .receive(on: DispatchQueue.main)
            .sink { [weak m] items in m?.recent = items }
            .store(in: &cancellables)
        m.appIcon = { [weak self] pkg in self?.store.icon(for: pkg) }
        m.accent = { [weak self] pkg in self?.store.accent(for: pkg) ?? AccentColor.fallback }
        m.onDismiss = { [weak self] n in
            self?.server.send(MacCommand(type: "dismiss", key: n.key))
            self?.store.remove(key: n.key)   // also closes the notch via onRemove
        }
        m.onAction = { [weak self] n, a in
            self?.server.send(MacCommand(type: "action", key: n.key, i: a.i))
            self?.island.toast("Sent “\(a.title)” to phone")
        }
        m.onReply = { [weak self] n, a, text in
            guard let self else { return }
            guard case .connected = self.status else {
                self.island.toast("Phone is not connected", isError: true)
                return
            }
            self.server.send(MacCommand(type: "reply", key: n.key, i: a.i, text: text))
            self.island.toast("Sending…")
        }
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateStatusIcon()
    }

    private func updateStatusIcon() {
        let symbol: String
        switch status {
        case .connected: symbol = "candybarphone"
        case .failed: symbol = "exclamationmark.triangle"
        default: symbol = "iphone.slash"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "NotchBridge")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = statusText
    }

    private var statusText: String {
        switch status {
        case .starting: return "Starting…"
        case .waiting:
            if let d = Pairing.shared.pairedDevice { return "Waiting for \(d)…" }
            return "Not paired"
        case .connected(let name): return "Connected to \(name)"
        case .failed(let msg): return msg
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let header = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let recent = NSMenuItem(title: "Recent notifications", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        if store.items.isEmpty {
            let empty = NSMenuItem(title: "None yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            sub.addItem(empty)
        }
        for n in store.items.prefix(15) {
            let title = [n.app, n.title].filter { !$0.isEmpty }.joined(separator: " · ")
            let item = NSMenuItem(title: title, action: #selector(reshow(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = n.key
            item.toolTip = n.text
            if let icon = store.icon(for: n.pkg) {
                let small = icon.copy() as! NSImage
                small.size = NSSize(width: 16, height: 16)
                item.image = small
            }
            sub.addItem(item)
        }
        recent.submenu = sub
        menu.addItem(recent)

        menu.addItem(item("Show a test notification", #selector(showTest)))
        menu.addItem(.separator())
        menu.addItem(item("Open dashboard", #selector(openDashboard)))
        menu.addItem(item("Pair phone…", #selector(showPairing)))
        let settings = item("Settings…", #selector(showSettings))
        settings.keyEquivalent = ","
        menu.addItem(settings)

        let mirror = item("Also show in Notification Center", #selector(toggleMirror))
        mirror.state = systemNotifier.enabled ? .on : .off
        menu.addItem(mirror)

        let login = item("Launch at login", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit NotchBridge", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        return i
    }

    @objc private func reshow(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String,
              let n = store.items.first(where: { $0.key == key }) else { return }
        island.show(n)
    }

    @objc private func showTest() {
        island.show(PhoneNotification(
            key: "test-\(UUID().uuidString)", pkg: "test", app: "NotchBridge",
            title: "Hello from your phone 👋",
            text: "This is how Android notifications will look in the island. Hover to keep it open, click to see actions.",
            sub: nil, time: Date(), actions: [], largeIcon: nil))
    }

    @objc private func showPairing() { pairingWindow.show() }

    @objc private func showSettings() { settingsWindow.show() }

    @objc private func openDashboard() { island.openDashboard() }

    private func wireMedia() {
        let m = island.model
        m.liveMusicEnabled = Prefs.liveMusic
        m.onMedia = { [weak self] cmd in self?.media.send(cmd) }
        media.sendToPhone = { [weak self] cmd in
            self?.server.send(MacCommand(type: "media_cmd", cmd: cmd.rawValue))
        }
        media.$current
            .receive(on: DispatchQueue.main)
            .sink { [weak m] np in withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { m?.media = np } }
            .store(in: &cancellables)
        media.$accent
            .receive(on: DispatchQueue.main)
            .sink { [weak m] c in m?.mediaAccent = c }
            .store(in: &cancellables)
        media.start()
    }

    private func wireVolume() {
        volume.onChange = { [weak self] level, muted in self?.island.showSystem(.volume(level: level, muted: muted)) }
        if Prefs.volumeHUD { volume.start() }
        settingsWindow.model.onVolumeHUDChanged = { [weak self] on in
            if on { self?.volume.start() } else { self?.volume.stop() }
        }
        settingsWindow.model.onDisplayChanged = { [weak self] in self?.island.refreshGeometry() }
    }

    /// Daily driver: the first time it runs from /Applications, start it at login (can be turned off in Settings).
    private func setUpLoginItemOnce() {
        let d = UserDefaults.standard
        guard Bundle.main.bundlePath.hasPrefix("/Applications/"), !d.bool(forKey: Prefs.Key.loginItemAutoSetup) else { return }
        d.set(true, forKey: Prefs.Key.loginItemAutoSetup)
        do {
            try SMAppService.mainApp.register()
            DebugLog.write("login item: registered")
        } catch {
            DebugLog.write("login item: \(error.localizedDescription)")
        }
    }

    private func wireShelf() {
        let m = island.model
        shelf.$items.receive(on: DispatchQueue.main).sink { [weak m] items in m?.shelfItems = items }.store(in: &cancellables)
        shelf.$thumbnails.receive(on: DispatchQueue.main).sink { [weak m] t in m?.shelfIcons = t }.store(in: &cancellables)
        m.onDropFiles = { [weak self] urls in
            guard let self else { return }
            let added = self.shelf.add(urls)
            DebugLog.write("drop: shelf added \(added) of \(urls.count)")
            if added > 0 { self.island.toast(added == 1 ? "Added to the shelf" : "Added \(added) files to the shelf") }
        }
        m.onShelfRemove = { [weak self] item in self?.shelf.remove(item) }
        m.onShelfClear = { [weak self] in self?.shelf.clear() }
        m.onShelfOpen = { item in NSWorkspace.shared.open(item.url) }
        m.onShelfAirDrop = { items in
            guard let service = NSSharingService(named: .sendViaAirDrop) else { return }
            NSApp.activate(ignoringOtherApps: true)
            service.perform(withItems: items.map(\.url))
        }
        m.onShelfSendToPhone = { [weak self] item in self?.sendToPhone(item) }
    }

    private func sendToPhone(_ item: ShelfItem) {
        guard case .connected = status else {
            island.toast("Phone is not connected", isError: true)
            return
        }
        guard island.model.transfers[item.id] == nil else { return }
        let id = UUID().uuidString
        transferItems[id] = item.id
        island.model.transfers[item.id] = 0
        let mime = UTType(filenameExtension: item.url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        server.sendFile(item.url, id: id, mime: mime, progress: { [weak self] p in
            guard let self, self.transferItems[id] != nil else { return }
            self.island.model.transfers[item.id] = p
            if p >= 1 {
                // Everything sent; an up-to-date phone answers with file_result within moments.
                DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
                    guard let self, self.transferItems.removeValue(forKey: id) != nil else { return }
                    self.island.model.transfers[item.id] = nil
                    self.island.toast("No answer from the phone. Update the phone app?", isError: true)
                }
            }
        }, failed: { [weak self] msg in
            self?.transferItems[id] = nil
            self?.island.model.transfers[item.id] = nil
            self?.island.toast(msg, isError: true)
        })
    }

    private func wireCalendarAndBattery() {
        let m = island.model
        m.onJoin = { url in NSWorkspace.shared.open(url) }
        m.onCalendarAccess = { [weak self] in self?.calendarAccessAction() }
        calendar.onEvents = { [weak m] events in m?.events = events }
        calendar.onCalendarCount = { [weak m] n in m?.calendarCount = n }
        calendar.onAccess = { [weak self] access in
            self?.island.model.calendarAccess = access
            self?.settingsWindow.model.calendarStatus = Self.describe(access)
        }
        calendar.onMeetingSoon = { [weak self] e in
            guard Prefs.meetingReminders else { return }
            self?.island.showSystem(.meeting(e))
        }
        if Prefs.calendar { calendar.start() }

        battery.onActivity = { [weak self] a in
            guard Prefs.batteryAlerts else { return }
            self?.island.showSystem(a)
        }
        battery.start()
    }

    private func calendarAccessAction() {
        switch island.model.calendarAccess {
        case .off:
            UserDefaults.standard.set(true, forKey: Prefs.Key.calendar)
            calendar.start()
        case .denied:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                NSWorkspace.shared.open(url)
            }
        default:
            break
        }
    }

    private static func describe(_ a: IslandModel.CalendarAccess) -> String {
        switch a {
        case .off: return ""
        case .unknown: return "Waiting for you to allow calendar access…"
        case .granted: return "Calendar access allowed."
        case .denied: return "Calendar access is off. Allow it in System Settings › Privacy & Security › Calendars."
        }
    }

    private func wireSettings() {
        settingsWindow.model.onCalendarChanged = { [weak self] on in
            if on { self?.calendar.start() } else { self?.calendar.stop() }
        }
        settingsWindow.model.onLiveMusicChanged = { [weak self] on in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { self?.island.model.liveMusicEnabled = on }
        }
        settingsWindow.model.phoneStatus = statusText
        settingsWindow.model.onPair = { [weak self] in self?.pairingWindow.show() }
        settingsWindow.model.onMirrorChanged = { [weak self] on in
            if on { self?.systemNotifier.requestAuthorization() }
        }
    }

    @objc private func toggleMirror() { systemNotifier.enabled.toggle() }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change the login item"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}
