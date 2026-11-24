import AppKit

/// Which "now playing" sources count as music (they stay in the notch after pausing) versus
/// browsers / video players (they only show while actually playing).
enum MusicApps {
    static let musicBundleIDs: Set<String> = [
        "com.spotify.client", "com.apple.Music", "com.apple.podcasts", "com.apple.iTunes",
        "com.tidal.desktop", "com.amazon.music", "com.deezer.deezer-desktop", "com.pandora.desktop",
        "com.soundcloud.desktop", "com.ciderapp.Cider", "sh.cider.genten.mac",
    ]

    static func isMusic(_ n: NowPlaying) -> Bool {
        n.source == .phone || musicBundleIDs.contains(n.appID)
    }
}

/// Talks to Spotify / Music directly (AppleScript), for when another app (a browser tab) holds the
/// system's single "Now Playing" slot and MediaRemote commands would go there instead.
/// macOS asks once: "NotchBridge wants to control Spotify".
enum AppleScriptPlayer {
    private static let appNames = ["com.spotify.client": "Spotify", "com.apple.Music": "Music"]

    static func supports(_ appID: String) -> Bool { appNames[appID] != nil }

    static func send(_ cmd: MediaCommand, to appID: String) {
        guard let app = appNames[appID] else { return }
        let verb: String
        switch cmd {
        case .togglePlayPause: verb = "playpause"
        case .next: verb = "next track"
        case .previous: verb = "previous track"
        }
        run("tell application \"\(app)\" to \(verb)")
    }

    static func seek(_ appID: String, to seconds: Double) {
        guard let app = appNames[appID] else { return }
        run("tell application \"\(app)\" to set player position to \(String(format: "%.2f", max(0, seconds)))")
    }

    /// Spotify only: artwork URL of the current track.
    static func spotifyArtworkURL(completion: @escaping (URL?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            var error: NSDictionary?
            let result = NSAppleScript(source: "tell application \"Spotify\" to artwork url of current track")?
                .executeAndReturnError(&error)
            let url = result?.stringValue.flatMap(URL.init(string:))
            DispatchQueue.main.async { completion(url) }
        }
    }

    /// Spotify's current track, if Spotify is already running (never launches it).
    static func spotifySnapshot(completion: @escaping (NowPlaying?) -> Void) {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty else {
            completion(nil)
            return
        }
        let script = """
        tell application "Spotify"
            if player state is stopped then return ""
            set t to current track
            return (name of t) & "\t" & (artist of t) & "\t" & (album of t) & "\t" & (duration of t) & "\t" & (player position as string) & "\t" & (player state as string)
        end tell
        """
        DispatchQueue.global(qos: .utility).async {
            var error: NSDictionary?
            let out = NSAppleScript(source: script)?.executeAndReturnError(&error).stringValue ?? ""
            let f = out.components(separatedBy: "\t")
            var np: NowPlaying?
            if f.count == 6, !f[0].isEmpty {
                np = NowPlaying(source: .mac, title: f[0], artist: f[1], album: f[2],
                                duration: Double(f[3]).map { $0 / 1000 },
                                elapsed: Double(f[4].replacingOccurrences(of: ",", with: ".")) ?? 0,
                                elapsedAt: Date(), rate: 1, isPlaying: f[5] == "playing",
                                appName: "Spotify", appID: "com.spotify.client", artwork: nil, artKey: nil)
            } else if let error {
                DebugLog.write("media: Spotify snapshot failed: \(error[NSAppleScript.errorMessage] ?? "?")")
            }
            DispatchQueue.main.async { completion(np) }
        }
    }

    private static func run(_ source: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let error { DebugLog.write("media: AppleScript failed: \(error[NSAppleScript.errorMessage] ?? "?")") }
        }
    }
}

/// Spotify and Music announce every play/pause/track change with a distributed notification —
/// even when a browser holds "Now Playing". No permission needed.
final class MusicAppObserver {
    /// Main thread. `positionKnown` is false for Music (its announcements have no position).
    var onUpdate: (NowPlaying, _ positionKnown: Bool) -> Void = { _, _ in }
    /// The app stopped (quit / no track): mark it paused.
    var onStopped: (String) -> Void = { _ in }

    private var tokens: [NSObjectProtocol] = []

    func start() {
        let dnc = DistributedNotificationCenter.default()
        tokens.append(dnc.addObserver(forName: Notification.Name("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main) { [weak self] n in
            self?.handle(n.userInfo, appID: "com.spotify.client", appName: "Spotify")
        })
        tokens.append(dnc.addObserver(forName: Notification.Name("com.apple.Music.playerInfo"), object: nil, queue: .main) { [weak self] n in
            self?.handle(n.userInfo, appID: "com.apple.Music", appName: "Music")
        })
    }

    private func handle(_ info: [AnyHashable: Any]?, appID: String, appName: String) {
        guard let info else { return }
        let state = info["Player State"] as? String ?? ""
        guard let title = info["Name"] as? String, !title.isEmpty, state != "Stopped" else {
            onStopped(appID)
            return
        }
        // Spotify: "Duration" in ms, "Playback Position" in s. Music: "Total Time" in ms, no position.
        let durationMs = (info["Duration"] as? NSNumber)?.doubleValue ?? (info["Total Time"] as? NSNumber)?.doubleValue
        let position = (info["Playback Position"] as? NSNumber)?.doubleValue
        let np = NowPlaying(
            source: .mac,
            title: title,
            artist: info["Artist"] as? String ?? "",
            album: info["Album"] as? String ?? "",
            duration: durationMs.map { $0 / 1000 },
            elapsed: position ?? 0,
            elapsedAt: Date(),
            rate: 1,
            isPlaying: state == "Playing",
            appName: appName,
            appID: appID,
            artwork: nil,
            artKey: nil)
        onUpdate(np, position != nil)
    }

    deinit { tokens.forEach(DistributedNotificationCenter.default().removeObserver) }
}

/// The last music played, kept across restarts (~/Library/Application Support/NotchBridge/last-music.*).
final class MusicMemoryStore {
    private struct Saved: Codable {
        var title, artist, album, appID, appName: String
        var duration: Double?
        var elapsed: Double
        var phone: Bool
    }

    private let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("NotchBridge", isDirectory: true)
    private var jsonURL: URL { dir.appendingPathComponent("last-music.json") }
    private var artURL: URL { dir.appendingPathComponent("last-music.png") }
    private var pending: DispatchWorkItem?

    func load() -> NowPlaying? {
        guard let data = try? Data(contentsOf: jsonURL), let s = try? JSONDecoder().decode(Saved.self, from: data) else { return nil }
        let art = NSImage(contentsOf: artURL)
        return NowPlaying(source: s.phone ? .phone : .mac, title: s.title, artist: s.artist, album: s.album,
                          duration: s.duration, elapsed: s.elapsed, elapsedAt: Date(), rate: 1, isPlaying: false,
                          appName: s.appName, appID: s.appID, artwork: art, artKey: art == nil ? nil : "saved",
                          updatedAt: .distantPast)
    }

    /// Debounced: playback updates arrive often.
    func save(_ n: NowPlaying) {
        pending?.cancel()
        let work = DispatchWorkItem { [dir, jsonURL, artURL] in
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let s = Saved(title: n.title, artist: n.artist, album: n.album, appID: n.appID, appName: n.appName,
                          duration: n.duration, elapsed: n.position(), phone: n.source == .phone)
            if let data = try? JSONEncoder().encode(s) { try? data.write(to: jsonURL, options: .atomic) }
            if let art = n.artwork, let tiff = art.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: artURL, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: artURL)
            }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }
}
