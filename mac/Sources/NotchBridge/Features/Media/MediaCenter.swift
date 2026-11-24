import AppKit
import Combine

/// Merges the Mac's and the phone's Now Playing into the one the island shows, and routes controls.
final class MediaCenter: ObservableObject {
    @Published private(set) var current: NowPlaying?
    @Published private(set) var accent: NSColor = AccentColor.fallback

    private let mac = MacMediaSource()
    private var macNow: NowPlaying?
    private var phoneNow: NowPlaying?
    private var phoneArt: (id: String, image: NSImage)?
    private var accentKey: String?

    /// Sends a command to the phone (set by AppDelegate).
    var sendToPhone: (MediaCommand) -> Void = { _ in }

    func start() {
        mac.onUpdate = { [weak self] np in
            self?.macNow = np
            self?.recompute()
        }
        mac.start()
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
        phoneNow = NowPlaying(
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
        recompute()
    }

    /// Phone disconnected: forget its media.
    func phoneDisconnected() {
        phoneNow = nil
        recompute()
    }

    func send(_ cmd: MediaCommand) {
        guard let c = current else { return }
        switch c.source {
        case .mac: mac.send(cmd)
        case .phone: sendToPhone(cmd)
        }
    }

    /// Prefer whatever is playing; if both are, the Mac (you're at it); if neither, the last one touched.
    private func recompute() {
        let candidates = [macNow, phoneNow].compactMap { $0 }
        let playing = candidates.filter(\.isPlaying)
        let pick: NowPlaying?
        if playing.count > 1 {
            pick = playing.first { $0.source == .mac }
        } else if let p = playing.first {
            pick = p
        } else {
            pick = candidates.max { $0.updatedAt < $1.updatedAt }
        }
        if pick != current {
            if pick?.trackID != current?.trackID || pick?.isPlaying != current?.isPlaying {
                DebugLog.write("media: \(pick.map { "\($0.source) app=\($0.appID) playing=\($0.isPlaying) art=\($0.artwork != nil)" } ?? "none")")
            }
            current = pick
        }

        let key = pick?.artKey ?? pick?.appID
        if key != accentKey {
            accentKey = key
            accent = pick?.artwork.flatMap(AccentColor.from) ?? AccentColor.fallback
        }
    }
}
