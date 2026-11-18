import CryptoKit
import Foundation

/// Holds this Mac's identity and the shared AES key the phone receives via QR code.
/// Stored in ~/Library/Application Support/NotchBridge/pairing.json (mode 0600).
final class Pairing {
    static let shared = Pairing()
    static let port: UInt16 = 47821

    private struct Stored: Codable {
        var id: String
        var key: String          // base64 raw 32-byte key
        var device: String?      // last phone that said hello
    }

    private let lock = NSLock()
    private var stored: Stored
    private var symmetricKey: SymmetricKey
    private let fileURL: URL

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchBridge", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("pairing.json")

        if let data = try? Data(contentsOf: fileURL),
           let s = try? JSONDecoder().decode(Stored.self, from: data),
           let raw = Data(base64Encoded: s.key), raw.count == 32 {
            stored = s
            symmetricKey = SymmetricKey(data: raw)
        } else {
            let key = SymmetricKey(size: .bits256)
            symmetricKey = key
            stored = Stored(id: UUID().uuidString, key: key.withUnsafeBytes { Data($0) }.base64EncodedString())
            save()
        }
    }

    var macId: String { lock.withLock { stored.id } }
    var macName: String { Host.current().localizedName ?? "Mac" }

    var pairedDevice: String? {
        get { lock.withLock { stored.device } }
        set { lock.withLock { stored.device = newValue }; save() }
    }

    /// New key: the currently paired phone stops working until it scans the new QR code.
    func reset() {
        lock.withLock {
            let key = SymmetricKey(size: .bits256)
            symmetricKey = key
            stored.key = key.withUnsafeBytes { Data($0) }.base64EncodedString()
            stored.device = nil
        }
        save()
    }

    func seal(_ plain: Data) throws -> Data {
        let key = lock.withLock { symmetricKey }
        guard let combined = try AES.GCM.seal(plain, using: key).combined else {
            throw CocoaError(.coderInvalidValue)
        }
        return combined
    }

    func open(_ box: Data) throws -> Data {
        let key = lock.withLock { symmetricKey }
        return try AES.GCM.open(AES.GCM.SealedBox(combined: box), using: key)
    }

    /// Content of the pairing QR code.
    var pairingURL: String {
        let keyB64url = lock.withLock { stored.key }
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        var c = URLComponents()
        c.scheme = "notchbridge"
        c.host = "pair"
        c.queryItems = [
            URLQueryItem(name: "v", value: "1"),
            URLQueryItem(name: "id", value: macId),
            URLQueryItem(name: "name", value: macName),
            URLQueryItem(name: "key", value: keyB64url),
            URLQueryItem(name: "host", value: Self.localIPv4() ?? ""),
            URLQueryItem(name: "port", value: String(Self.port)),
        ]
        return c.string ?? ""
    }

    private func save() {
        let data = lock.withLock { try? JSONEncoder().encode(stored) }
        guard let data else { return }
        try? data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    /// Best-effort LAN IPv4 (en0 first). Used only as a fallback when Bonjour discovery fails.
    static func localIPv4() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var candidates: [(String, String)] = []
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            guard let addr = ptr.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            let name = String(cString: ptr.pointee.ifa_name)
            guard name.hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                candidates.append((name, String(cString: host)))
            }
        }
        return (candidates.first { $0.0 == "en0" } ?? candidates.first)?.1
    }
}
