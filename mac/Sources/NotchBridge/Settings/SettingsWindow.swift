import AppKit
import ServiceManagement
import SwiftUI

final class SettingsModel: ObservableObject {
    @Published var phoneStatus = "Not paired"
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    var onPair: () -> Void = {}
    var onMirrorChanged: (Bool) -> Void = { _ in }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @AppStorage(Prefs.Key.hoverToPeek) private var hoverToPeek = true
    @AppStorage(Prefs.Key.openOnHover) private var openOnHover = false
    @AppStorage(Prefs.Key.haptics) private var haptics = true
    @AppStorage(Prefs.Key.displaySeconds) private var displaySeconds = 6.0
    @AppStorage(Prefs.Key.mirrorToNotificationCenter) private var mirror = false
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Notch") {
                Toggle("Peek when the pointer is over the notch", isOn: $hoverToPeek)
                Toggle("Open the dashboard on hover (no click needed)", isOn: $openOnHover)
                Toggle("Haptic tap on new notifications", isOn: $haptics)
                LabeledContent("Gestures") {
                    Text("Click or swipe down to open · swipe up to close")
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
