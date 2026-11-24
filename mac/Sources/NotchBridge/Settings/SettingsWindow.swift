import AppKit
import ServiceManagement
import SwiftUI

final class SettingsModel: ObservableObject {
    @Published var phoneStatus = "Not paired"
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    var onPair: () -> Void = {}
    var onMirrorChanged: (Bool) -> Void = { _ in }
    var onLiveMusicChanged: (Bool) -> Void = { _ in }
    var onCalendarChanged: (Bool) -> Void = { _ in }
    var onDisplayChanged: () -> Void = {}
    var onVolumeHUDChanged: (Bool) -> Void = { _ in }
    @Published var calendarStatus = ""
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @AppStorage(Prefs.Key.hoverToPeek) private var hoverToPeek = true
    @AppStorage(Prefs.Key.openOnHover) private var openOnHover = false
    @AppStorage(Prefs.Key.haptics) private var haptics = true
    @AppStorage(Prefs.Key.displaySeconds) private var displaySeconds = 6.0
    @AppStorage(Prefs.Key.mirrorToNotificationCenter) private var mirror = false
    @AppStorage(Prefs.Key.liveMusic) private var liveMusic = true
    @AppStorage(Prefs.Key.calendar) private var calendar = true
    @AppStorage(Prefs.Key.meetingReminders) private var meetingReminders = true
    @AppStorage(Prefs.Key.batteryAlerts) private var batteryAlerts = true
    @AppStorage(Prefs.Key.volumeHUD) private var volumeHUD = false
    @AppStorage(Prefs.Key.display) private var display = "auto"
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Notch") {
                Toggle("Peek when the pointer is over the notch", isOn: $hoverToPeek)
                Toggle("Open the dashboard on hover (no click needed)", isOn: $openOnHover)
                Toggle("Haptic tap on new notifications", isOn: $haptics)
                Toggle("Show what's playing beside the camera", isOn: $liveMusic)
                    .onChange(of: liveMusic) { _, on in model.onLiveMusicChanged(on) }
                Toggle("Show volume changes in the notch", isOn: $volumeHUD)
                    .onChange(of: volumeHUD) { _, on in model.onVolumeHUDChanged(on) }
                Picker("Show the island on", selection: $display) {
                    Text("The display with the notch (automatic)").tag("auto")
                    Text("The primary display (menu bar)").tag("primary")
                }
                .onChange(of: display) { _, _ in model.onDisplayChanged() }
                LabeledContent("Gestures") {
                    Text("Click or swipe down to open · swipe up to close · swipe left/right to skip tracks")
                        .foregroundStyle(.secondary)
                }
            }
            Section("Notifications") {
                LabeledContent("Show each card for") {
                    HStack {
                        Slider(value: $displaySeconds, in: 3...15, step: 1).frame(width: 160)
                        Text("\(Int(displaySeconds)) s").monospacedDigit().frame(width: 34, alignment: .trailing)
                    }
                }
                Toggle("Also keep a copy in macOS Notification Center", isOn: $mirror)
                    .onChange(of: mirror) { _, on in model.onMirrorChanged(on) }
            }
            Section("Calendar & battery") {
                Toggle("Show my calendar (Calendar tab, next event on Home)", isOn: $calendar)
                    .onChange(of: calendar) { _, on in model.onCalendarChanged(on) }
                if !model.calendarStatus.isEmpty {
                    Text(model.calendarStatus).font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Remind me 5 minutes before meetings", isOn: $meetingReminders)
                    .disabled(!calendar)
                Toggle("Show charging and low-battery alerts", isOn: $batteryAlerts)
            }
            Section("Phone") {
                LabeledContent("Status", value: model.phoneStatus)
                Button("Pair a phone…") { model.onPair() }
            }
            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                        }
                        model.launchAtLogin = SMAppService.mainApp.status == .enabled
                    }))
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

final class SettingsWindowController {
    let model = SettingsModel()
    private var window: NSWindow?

    func show() {
        model.launchAtLogin = SMAppService.mainApp.status == .enabled
        if window == nil {
            let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "NotchBridge Settings"
            w.contentView = NSHostingView(rootView: SettingsView(model: model))
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
