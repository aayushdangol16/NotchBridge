import AppKit

/// Reads the Mac's Now Playing info (any app: Spotify, Music, Safari/Chrome/Brave video, …) through
/// libNowPlayingHelper.dylib running inside /usr/bin/perl (see mac/MediaHelper/NowPlayingHelper.m).
final class MacMediaSource {
    /// Main thread. nil = nothing in Now Playing.
    var onUpdate: (NowPlaying?) -> Void = { _ in }
    private(set) var available = true

    private var process: Process?
    private var buffer = Data()
    private var artCache: (id: String, image: NSImage)?
    private var restarts: [Date] = []

    private static let loader = """
    use DynaLoader; my $h = DynaLoader::dl_load_file($ARGV[0], 0) or die DynaLoader::dl_error(); \
    my $s = DynaLoader::dl_find_symbol($h, $ARGV[1]) or die DynaLoader::dl_error(); \
    DynaLoader::dl_install_xsub("main::f", $s); f();
    """

    /// Inside the .app: Contents/Resources. During development: mac/.build/helper.
    static var helperPath: String? {
        var candidates: [URL] = []
        if let res = Bundle.main.resourceURL { candidates.append(res.appendingPathComponent("libNowPlayingHelper.dylib")) }
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        candidates.append(exe.appendingPathComponent("../helper/libNowPlayingHelper.dylib").standardized)
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }?.path
    }

    func start() {
        guard let helper = Self.helperPath else {
            available = false
            DebugLog.write("media: helper library not found")
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = ["-e", Self.loader, helper, "nb_stream"]
        let out = Pipe()
        p.standardOutput = out
        p.standardInput = Pipe()          // closes when we quit -> helper exits
        p.standardError = FileHandle.nullDevice
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let chunk = h.availableData
            DispatchQueue.main.async { self?.consume(chunk) }
        }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.helperExited() }
        }
        do {
            try p.run()
            process = p
        } catch {
            available = false
            DebugLog.write("media: could not start helper: \(error.localizedDescription)")
        }
    }

    func send(_ cmd: MediaCommand) {
        guard let helper = Self.helperPath else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = ["-e", Self.loader, helper, "nb_send"]
        p.environment = ["NB_MEDIA_CMD": String(cmd.macCode)]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    /// Jump to `seconds` in whatever is playing on the Mac.
    func seek(to seconds: Double) {
        guard let helper = Self.helperPath else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = ["-e", Self.loader, helper, "nb_seek"]
        p.environment = ["NB_MEDIA_SEEK": String(format: "%.2f", max(0, seconds))]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    private func helperExited() {
        process = nil
        // Restart unless it keeps dying (then MediaRemote access is probably blocked on this macOS).
        restarts = restarts.filter { $0.timeIntervalSinceNow > -60 } + [Date()]
        if restarts.count > 4 {
            available = false
            DebugLog.write("media: helper keeps exiting; Mac now-playing disabled")
            onUpdate(nil)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.start() }
    }

    private func consume(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        buffer.append(chunk)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            if let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] { handle(obj) }
        }
    }

    private func handle(_ o: [String: Any]) {
        if o["error"] != nil {
            available = false
            return
        }
        if o["empty"] as? Bool == true {
            onUpdate(nil)
            return
        }
        let title = o["title"] as? String ?? ""
        guard !title.isEmpty else { onUpdate(nil); return }

        var artwork: NSImage?
        var artKey: String?
        if let id = (o["artId"] as? NSNumber)?.stringValue {
            artKey = id
            if let b64 = o["art"] as? String, let data = Data(base64Encoded: b64), let img = NSImage(data: data) {
                artCache = (id, img)
            }
            if artCache?.id == id { artwork = artCache?.image }
        }

        let bundle = o["bundle"] as? String ?? ""
        let rate = (o["rate"] as? NSNumber)?.doubleValue ?? 0
        let playing = (o["playing"] as? NSNumber)?.boolValue ?? (rate > 0)
        let ts = (o["timestamp"] as? NSNumber)?.doubleValue
        onUpdate(NowPlaying(
            source: .mac,
            title: title,
            artist: o["artist"] as? String ?? "",
            album: o["album"] as? String ?? "",
            duration: (o["duration"] as? NSNumber)?.doubleValue,
            elapsed: (o["elapsed"] as? NSNumber)?.doubleValue ?? 0,
            elapsedAt: ts.map { Date(timeIntervalSince1970: $0) } ?? Date(),
            rate: rate > 0 ? rate : 1,
            isPlaying: playing,
            appName: bundle.isEmpty ? "Mac" : AppNames.name(forBundleID: bundle),
            appID: bundle,
            artwork: artwork,
            artKey: artKey))
    }

    deinit { process?.terminate() }
}
