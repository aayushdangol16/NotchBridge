import AppKit

if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
    _ = NSApplication.shared
    MainActor.assumeIsolated { Snapshot.run(dir: CommandLine.arguments[i + 1]) }
    exit(0)
}

if CommandLine.arguments.contains("--selftest") {
    _ = NSApplication.shared
    exit(SelfTest.run())
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu-bar only, no Dock icon
app.run()
