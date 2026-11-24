import AppKit
import QuickLookThumbnailing

struct ShelfItem: Identifiable, Codable, Equatable {
    let id: UUID
    let path: String
    let addedAt: Date

    var url: URL { URL(fileURLWithPath: path) }
    var name: String { url.lastPathComponent }
    var isDirectory: Bool {
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &dir) && dir.boolValue
    }
    var size: Int64 { (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0 }
}

/// Files parked in the notch. Holds references (not copies); entries whose file disappeared are dropped.
/// Persisted to ~/Library/Application Support/NotchBridge/shelf.json.
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []
    @Published private(set) var thumbnails: [UUID: NSImage] = [:]
    static let maxItems = 30

    private let fileURL: URL

    init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchBridge", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("shelf.json")
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([ShelfItem].self, from: data) {
            items = saved.filter { FileManager.default.fileExists(atPath: $0.path) }
        }
        items.forEach(makeThumbnail)
    }

    /// Adds files (newest first), skipping ones already on the shelf. Returns how many were added.
    @discardableResult
    func add(_ urls: [URL]) -> Int {
        var added = 0
        for url in urls where url.isFileURL {
            let path = url.standardizedFileURL.path
            guard FileManager.default.fileExists(atPath: path), !items.contains(where: { $0.path == path }) else { continue }
            let item = ShelfItem(id: UUID(), path: path, addedAt: Date())
            items.insert(item, at: 0)
            makeThumbnail(item)
            added += 1
        }
        if items.count > Self.maxItems { items.removeLast(items.count - Self.maxItems) }
        if added > 0 { save() }
        return added
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        thumbnails[item.id] = nil
        save()
    }

    func clear() {
        items.removeAll()
        thumbnails.removeAll()
        save()
    }

    func icon(for item: ShelfItem) -> NSImage {
        thumbnails[item.id] ?? NSWorkspace.shared.icon(forFile: item.path)
    }

    private func makeThumbnail(_ item: ShelfItem) {
        let request = QLThumbnailGenerator.Request(fileAt: item.url, size: CGSize(width: 96, height: 96),
                                                   scale: 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] rep, _ in
            guard let rep else { return }
            DispatchQueue.main.async { self?.thumbnails[item.id] = rep.nsImage }
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
