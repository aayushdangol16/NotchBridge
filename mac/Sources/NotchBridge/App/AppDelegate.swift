import AppKit
import Combine
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let server = BridgeServer()
    private let store = NotificationStore()
    private let island = IslandController()
    private let settingsWindow = SettingsWindowController()
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
                island.flash(m.msg ?? "Done")
            } else {
                island.flash(m.msg ?? "The phone couldn't do that", isError: true, hideAfter: 3)
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
            self?.island.flash("Sent “\(a.title)” to phone")
        }
        m.onReply = { [weak self] n, a, text in
            guard let self else { return }
            guard case .connected = self.status else {
                self.island.flash("Phone is not connected", isError: true, hideAfter: 3)
                return
            }
            self.server.send(MacCommand(type: "reply", key: n.key, i: a.i, text: text))
            self.island.flash("Sending…", hideAfter: 5)
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

    private func wireSettings() {
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
