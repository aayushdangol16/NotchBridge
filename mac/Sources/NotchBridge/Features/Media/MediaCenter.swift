import AppKit
import Combine

/// Decides what the notch player shows and routes its controls.
///
/// Music first: the last music played (Spotify, Music, phone…) is remembered and stays in the notch
/// after pausing. Browsers / video players only take over while they are actually playing (and only
/// after a short moment, so autoplay previews and blips don't hijack it). macOS reports a single
/// "Now Playing" app, so when a browser holds it, Spotify / Music are followed through their own
/// announcements and controlled directly.
final class MediaCenter: ObservableObject {
    @Published private(set) var current: NowPlaying?
    @Published private(set) var accent: NSColor = AccentColor.fallback

    /// A browser / video must keep playing this long before it replaces your music in the notch.
    static let nonMusicDelay: TimeInterval = 2

    private let mac = MacMediaSource()
    private let apps = MusicAppObserver()
    private let memoryStore = MusicMemoryStore()
    private var macNow: NowPlaying?           // what macOS reports as Now Playing (any app)
    private var phoneNow: NowPlaying?
    private var memory: NowPlaying?           // the last music played (Mac music app or phone)
    private var nonMusicSince: Date?          // when the current browser/video item started playing
    private var phoneArt: (id: String, image: NSImage)?
    private var artCache: [String: NSImage] = [:]   // trackID -> artwork
    private var accentKey: String?

    /// Sends a command to the phone (set by AppDelegate).
    var sendToPhone: (MediaCommand) -> Void = { _ in }
    var seekOnPhone: (Double) -> Void = { _ in }

    func start() {
        memory = memoryStore.load()
        if let m = memory, let art = m.artwork { artCache[m.trackID] = art }
        mac.onUpdate = { [weak self] np in self?.macUpdated(np) }
        apps.onUpdate = { [weak self] np, positionKnown in self?.appAnnounced(np, positionKnown: positionKnown) }
        apps.onStopped = { [weak self] appID in
            guard let self, var m = self.memory, m.appID == appID, m.isPlaying else { return }
            m.elapsed = m.position()
            m.elapsedAt = Date()
            m.isPlaying = false
            self.memory = m
            self.recompute()
        }
        mac.start()
        apps.start()
        recompute()
        // Spotify only announces changes; if it's sitting paused, ask it what's loaded.
        AppleScriptPlayer.spotifySnapshot { [weak self] np in
            guard let self, let np, self.memory?.isPlaying != true else { return }
            if self.memory == nil || self.memory?.appID == np.appID || np.isPlaying {
                self.appAnnounced(np, positionKnown: true)
            }
        }
    }

    // MARK: - Sources

    private func macUpdated(_ np: NowPlaying?) {
        var np = np
        if var n = np {
            if let art = n.artwork { artCache[n.trackID] = art } else if let art = artCache[n.trackID] { n.artwork = art; np = n }
            if MusicApps.isMusic(n) { remember(n) }
            if !MusicApps.isMusic(n) && n.isPlaying {
                let continuing = macNow.map { !$0.isPlaying ? false : $0.trackID == n.trackID } ?? false
                if !continuing || nonMusicSince == nil { nonMusicSince = Date() }
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.nonMusicDelay + 0.05) { [weak self] in self?.recompute() }
            } else {
                nonMusicSince = nil
            }
        } else {
            nonMusicSince = nil
        }
        macNow = np
        recompute()
    }

    /// Spotify / Music announced a change (arrives even when a browser holds Now Playing).
    private func appAnnounced(_ np: NowPlaying, positionKnown: Bool) {
        var n = np
        if !positionKnown, let m = memory, m.trackID == n.trackID {
            n.elapsed = m.position()   // Music's announcements carry no position: keep ours
        }
        if let art = artCache[n.trackID] {
            n.artwork = art
        } else if n.appID == "com.spotify.client" {
            fetchSpotifyArtwork(for: n.trackID)
        }
        remember(n)
        recompute()
    }

    func updatePhone(_ m: WireMedia?) {
        guard let m, m.active, let title = m.title, !title.isEmpty else {
            phoneNow = nil
            recompute()
            return
        }
        if let id = m.artId {
            if let b64 = m.art, let data = Data(base64Encoded: b64), let img = NSImage(data: data) { phoneArt = (id, img) }
        } else {
            phoneArt = nil
        }
        let n = NowPlaying(
            source: .phone,
            title: title,
            artist: m.artist ?? "",
            album: m.album ?? "",
            duration: m.duration,
            elapsed: m.position ?? 0,
            elapsedAt: m.positionAt.map { Date(timeIntervalSince1970: $0) } ?? Date(),
            rate: (m.rate ?? 1) > 0 ? (m.rate ?? 1) : 1,
            isPlaying: m.playing ?? false,
            appName: m.app ?? "Phone",
            appID: m.pkg ?? "",
            artwork: phoneArt?.id == m.artId ? phoneArt?.image : nil,
            artKey: m.artId)
        phoneNow = n
        remember(n)
        recompute()
    }

    /// Phone disconnected: forget its live state (the memory of its last song stays).
    func phoneDisconnected() {
        phoneNow = nil
        if var m = memory, m.source == .phone, m.isPlaying {
            m.elapsed = m.position()
            m.elapsedAt = Date()
            m.isPlaying = false
            memory = m
        }
        recompute()
    }

    /// Music becomes the memory when it plays; updates for the same track keep it current.
    private func remember(_ n: NowPlaying) {
        guard MusicApps.isMusic(n) else { return }
        guard n.isPlaying || memory == nil || memory?.trackID == n.trackID else { return }
        var n = n
        if n.artwork == nil, let m = memory, m.trackID == n.trackID { n.artwork = m.artwork; n.artKey = m.artKey }
        memory = n
        memoryStore.save(n)
    }

    private func fetchSpotifyArtwork(for trackID: String) {
        AppleScriptPlayer.spotifyArtworkURL { [weak self] url in
            guard let url else { return }
            URLSession.shared.dataTask(with: url) { data, _, _ in
                guard let data, let img = NSImage(data: data) else { return }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.artCache[trackID] = img
                    if var m = self.memory, m.trackID == trackID {
                        m.artwork = img
                        m.artKey = trackID
                        self.memory = m
                        self.memoryStore.save(m)
                        self.recompute()
                    }
                }
            }.resume()
        }
    }

    // MARK: - Choosing

    /// Pure rule (also used by --selftest):
    /// 1. music that is playing (Mac music app, phone, or Spotify/Music via announcements)
    /// 2. a browser/video that has been playing for `nonMusicDelay`
    /// 3. nothing playing: the last music
    /// 4. no music ever: whatever there is
    static func choose(mac: NowPlaying?, phone: NowPlaying?, memory: NowPlaying?,
                       nonMusicSince: Date?, now: Date = Date()) -> NowPlaying? {
        let macMusic = mac.flatMap { MusicApps.isMusic($0) ? $0 : nil }
        for c in [macMusic, phone, memory] {
            if let c, c.isPlaying { return c }
        }
        if let m = mac, !MusicApps.isMusic(m), m.isPlaying,
           let since = nonMusicSince, now.timeIntervalSince(since) >= nonMusicDelay {
            return m
        }
        if let memory { return memory }
        return phone ?? mac
    }

    private func recompute() {
        let pick = Self.choose(mac: macNow, phone: phoneNow, memory: memory, nonMusicSince: nonMusicSince)
        if pick != current {
            if pick?.trackID != current?.trackID || pick?.isPlaying != current?.isPlaying {
                DebugLog.write("media: \(pick.map { "\($0.source) app=\($0.appID) playing=\($0.isPlaying) art=\($0.artwork != nil)" } ?? "none")")
            }
            current = pick
        }
        let key = pick?.artKey ?? pick?.appID
        if key != accentKey || (pick?.artwork != nil && accent == AccentColor.fallback) {
            accentKey = key
            accent = pick?.artwork.flatMap(AccentColor.from) ?? AccentColor.fallback
        }
    }

    // MARK: - Controls

    /// MediaRemote talks to whatever holds "Now Playing". If the notch shows Spotify/Music but a
    /// browser holds that slot, talk to the app directly instead.
    private func controlsGoDirect(_ c: NowPlaying) -> Bool {
        guard c.source == .mac, AppleScriptPlayer.supports(c.appID) else { return false }
        return macNow?.appID != c.appID
    }

    func send(_ cmd: MediaCommand) {
        guard let c = current else { return }
        if c.source == .phone { sendToPhone(cmd); return }
        if controlsGoDirect(c) { AppleScriptPlayer.send(cmd, to: c.appID) } else { mac.send(cmd) }
    }

    /// Jump to `seconds`. Updates the shown position right away so the bar doesn't snap back
    /// while the player catches up.
    func seek(to seconds: Double) {
        guard var c = current else { return }
        let target = max(0, min(seconds, c.duration ?? seconds))
        switch c.source {
        case .phone: seekOnPhone(target)
        case .mac: if controlsGoDirect(c) { AppleScriptPlayer.seek(c.appID, to: target) } else { mac.seek(to: target) }
        }
        c.elapsed = target
        c.elapsedAt = Date()
        current = c
        if memory?.trackID == c.trackID { memory = c }
        if c.source == .mac, macNow?.trackID == c.trackID { macNow = c }
        if c.source == .phone { phoneNow = c }
    }
}
