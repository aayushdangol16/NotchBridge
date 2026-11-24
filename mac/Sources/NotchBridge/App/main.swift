import AppKit

if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
    _ = NSApplication.shared
    MainActor.assumeIsolated { Snapshot.run(dir: CommandLine.arguments[i + 1]) }
    exit(0)
}

// --filetest <file>: serve on port 47899 (not advertised), send <file> to the first client that
// says hello, print the phone's file_result and exit. Used with a fake phone to test transfers.
if let i = CommandLine.arguments.firstIndex(of: "--filetest"), i + 1 < CommandLine.arguments.count {
    _ = NSApplication.shared
    let server = BridgeServer(port: 47899, advertise: false)
    let file = URL(fileURLWithPath: CommandLine.arguments[i + 1])
    var sent = false
    server.onStatus = { s in
        guard case .connected = s, !sent else { return }
        sent = true
        server.sendFile(file, id: "t1", mime: "application/octet-stream",
                        progress: { p in if p >= 1 { print("mac: all chunks sent") } },
                        failed: { msg in print("mac: FAILED \(msg)"); exit(1) })
    }
    server.onMessage = { m in
        if m.type == "file_result" { print("mac: file_result ok=\(m.ok ?? false) msg=\(m.msg ?? "")"); exit(m.ok == true ? 0 : 1) }
    }
    server.start()
    DispatchQueue.main.asyncAfter(deadline: .now() + 60) { print("mac: timeout"); exit(2) }
    RunLoop.main.run()
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
