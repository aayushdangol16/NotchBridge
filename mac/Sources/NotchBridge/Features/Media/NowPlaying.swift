import AppKit

/// What's playing, on the Mac or on the phone.
struct NowPlaying: Equatable {
    enum Source: Equatable { case mac, phone }

    var source: Source
    var title: String
    var artist: String
    var album: String
    var duration: Double?          // seconds
    var elapsed: Double            // seconds at `elapsedAt`
    var elapsedAt: Date
    var rate: Double
    var isPlaying: Bool
    var appName: String
    var appID: String              // bundle id (Mac) or package (phone)
    var artwork: NSImage?
    var artKey: String?
    var updatedAt = Date()

    /// Playback position now, extrapolated while playing.
    func position(at date: Date = Date()) -> Double {
        var p = elapsed
        if isPlaying { p += date.timeIntervalSince(elapsedAt) * (rate > 0 ? rate : 1) }
        if let duration, duration > 0 { p = min(p, duration) }
        return max(0, p)
    }

    var trackID: String { "\(source)|\(appID)|\(title)|\(artist)" }

    static func == (a: NowPlaying, b: NowPlaying) -> Bool {
        a.source == b.source && a.title == b.title && a.artist == b.artist && a.album == b.album &&
            a.isPlaying == b.isPlaying && a.artKey == b.artKey && a.duration == b.duration &&
            abs(a.position() - b.position()) < 1.5
    }
}

enum MediaCommand: String {
    case togglePlayPause = "toggle"
    case next
    case previous = "prev"

    /// MRMediaRemoteSendCommand numbers.
    var macCode: Int {
        switch self {
        case .togglePlayPause: return 2
        case .next: return 4
        case .previous: return 5
        }
    }
}

/// Phone -> Mac "media" payload (see android/.../MediaWatcher.kt).
struct WireMedia: Decodable {
    let active: Bool
    let title: String?
    let artist: String?
    let album: String?
    let duration: Double?      // seconds
    let position: Double?      // seconds at positionAt
    let positionAt: Double?    // epoch seconds
    let rate: Double?
    let playing: Bool?
    let app: String?
    let pkg: String?
    let art: String?           // base64 JPEG, only when it changed
    let artId: String?
}

enum AppNames {
    private static var cache: [String: String] = [:]

    static func name(forBundleID id: String) -> String {
        if let n = cache[id] { return n }
        var name = id.split(separator: ".").last.map(String.init)?.capitalized ?? id
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        cache[id] = name
        return name
    }
}
