import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum ShelfDrop {
    /// What the island accepts: real files, promised files (Mail/Messages attachments, Photos,
    /// screenshot thumbnails, browser images), raw images and web links.
    static let acceptedTypes: [UTType] = [.fileURL, .image, .url, .data]

    /// Where copies of non-file drops (images, promised files, links) are kept.
    static var filesDirectory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("NotchBridge/Shelf Files", isDirectory: true)

    /// Turns dropped item providers into file URLs, copying anything that isn't already a file.
    static func loadURLs(_ providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []
        func add(_ url: URL?) { if let url { lock.lock(); urls.append(url); lock.unlock() } }
        try? FileManager.default.createDirectory(at: filesDirectory, withIntermediateDirectories: true)

        for p in providers {
            let types = p.registeredTypeIdentifiers
            DebugLog.write("drop: provider types=\(types.prefix(6))")
            if p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                // A real file (Finder, Desktop…)
                group.enter()
                p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                    var url: URL?
                    if let d = item as? Data { url = URL(dataRepresentation: d, relativeTo: nil) }
                    else if let u = item as? URL { url = u }
                    else if let s = item as? String { url = URL(string: s) }
                    if url == nil { DebugLog.write("drop: file url unreadable: \(error?.localizedDescription ?? "unknown")") }
                    add(url)
                    group.leave()
                }
            } else if p.hasItemConformingToTypeIdentifier(UTType.url.identifier), p.canLoadObject(ofClass: NSURL.self) {
                // A web link: keep it as a .webloc that opens in the browser.
                group.enter()
                _ = p.loadObject(ofClass: NSURL.self) { obj, _ in
                    defer { group.leave() }
                    guard let link = obj as? URL, let scheme = link.scheme, scheme.hasPrefix("http") else { return }
                    let dest = uniqueURL(base: link.host ?? "Link", ext: "webloc")
                    let plist: [String: String] = ["URL": link.absoluteString]
                    if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0),
                       (try? data.write(to: dest)) != nil {
                        add(dest)
                    }
                }
            } else if let type = types.first(where: { UTType($0)?.conforms(to: .data) == true && !$0.hasPrefix("dyn.") }) {
                // Promised file or raw data (image, PDF…): copy it into our folder.
                group.enter()
                p.loadFileRepresentation(forTypeIdentifier: type) { tmp, error in
                    defer { group.leave() }
                    guard let tmp else {
                        DebugLog.write("drop: no file for \(type): \(error?.localizedDescription ?? "unknown")")
                        return
                    }
                    let ext = tmp.pathExtension.isEmpty ? (UTType(type)?.preferredFilenameExtension ?? "") : tmp.pathExtension
                    let base = p.suggestedName.flatMap { ($0 as NSString).deletingPathExtension } ?? tmp.deletingPathExtension().lastPathComponent
                    let dest = uniqueURL(base: base.isEmpty ? "Dropped item" : base, ext: ext)
                    do {
                        try FileManager.default.copyItem(at: tmp, to: dest)
                        add(dest)
                    } catch {
                        DebugLog.write("drop: copy failed: \(error.localizedDescription)")
                    }
                }
            }
        }
        group.notify(queue: .main) {
            DebugLog.write("drop: \(providers.count) item(s) -> \(urls.count) file(s)")
            completion(urls)
        }
    }

    /// Same as above, straight from a drag pasteboard (used by the notch drop zone).
    static func loadURLs(from pb: NSPasteboard, completion: @escaping ([URL]) -> Void) {
        try? FileManager.default.createDirectory(at: filesDirectory, withIntermediateDirectories: true)
        DebugLog.write("drop: pasteboard types=\((pb.types ?? []).prefix(6).map(\.rawValue))")

        // 1. Real files
        let files = (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        if !files.isEmpty {
            DebugLog.write("drop: \(files.count) file(s) from pasteboard")
            completion(files)
            return
        }

        // 2. Promised files (Mail / Messages attachments, Photos, screenshot thumbnail, browser images)
        let receivers = (pb.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver]) ?? []
        if !receivers.isEmpty {
            let group = DispatchGroup()
            let lock = NSLock()
            var urls: [URL] = []
            let queue = OperationQueue()
            for r in receivers {
                let expected = max(1, r.fileNames.count)
                for _ in 0..<expected { group.enter() }
                var remaining = expected
                r.receivePromisedFiles(atDestination: filesDirectory, options: [:], operationQueue: queue) { url, error in
                    lock.lock()
                    if error == nil { urls.append(url) } else { DebugLog.write("drop: promise failed: \(error!.localizedDescription)") }
                    let leave = remaining > 0
                    remaining -= 1
                    lock.unlock()
                    if leave { group.leave() }
                }
            }
            let done = { DebugLog.write("drop: \(urls.count) promised file(s)"); completion(urls) }
            if group.wait(timeout: .now() + 0) == .success { done() } else {
                DispatchQueue.global().async {
                    _ = group.wait(timeout: .now() + 15)
                    DispatchQueue.main.async(execute: done)
                }
            }
            return
        }

        // 3. Raw image
        if let image = NSImage(pasteboard: pb), let tiff = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            let dest = uniqueURL(base: "Dropped image", ext: "png")
            if (try? png.write(to: dest)) != nil {
                completion([dest])
                return
            }
        }

        // 4. Web link
        if let links = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let link = links.first(where: { $0.scheme?.hasPrefix("http") == true }) {
            let dest = uniqueURL(base: link.host ?? "Link", ext: "webloc")
            let plist: [String: String] = ["URL": link.absoluteString]
            if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0),
               (try? data.write(to: dest)) != nil {
                completion([dest])
                return
            }
        }
        DebugLog.write("drop: nothing usable on the pasteboard")
        completion([])
    }

    private static func uniqueURL(base: String, ext: String) -> URL {
        let clean = base.replacingOccurrences(of: "/", with: "-")
        var url = filesDirectory.appendingPathComponent(clean).appendingPathExtension(ext)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = filesDirectory.appendingPathComponent("\(clean) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return url
    }
}

/// Dashboard Shelf tab: files parked in the notch.
struct ShelfTab: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if model.shelfItems.isEmpty {
                dropHint
            } else if model.shelfItems.count <= 5 {
                tiles
            } else {
                ScrollView(.horizontal, showsIndicators: false) { tiles }
            }
        }
    }

    private var tiles: some View {
        HStack(spacing: 8) {
            ForEach(model.shelfItems) { item in ShelfTile(model: model, item: item) }
        }
        .padding(.vertical, 2)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(model.shelfItems.isEmpty ? "Shelf" : "Shelf · \(model.shelfItems.count)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
            Text("Drag files here to keep them handy")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.white.opacity(0.35))
                .lineLimit(1)
            Spacer(minLength: 4)
            if model.shelfItems.count > 1 {
                IslandButton(title: "AirDrop all", icon: "airplayaudio", style: .secondary) { model.onShelfAirDrop(model.shelfItems) }
                IslandButton(title: "Clear", icon: "xmark", style: .destructive) { model.onShelfClear() }
            }
        }
    }

    private var dropHint: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            .foregroundStyle(.white.opacity(model.dropTargeted ? 0.6 : 0.2))
            .overlay {
                VStack(spacing: 5) {
                    Image(systemName: model.dropTargeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                        .font(.system(size: 22, weight: .medium))
                    Text(model.dropTargeted ? "Drop to add" : "Drop files here")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white.opacity(model.dropTargeted ? 0.9 : 0.4))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeOut(duration: 0.15), value: model.dropTargeted)
    }
}

struct ShelfTile: View {
    @ObservedObject var model: IslandModel
    let item: ShelfItem
    @State private var hover = false

    private var progress: Double? { model.transfers[item.id] }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Image(nsImage: model.shelfIcons[item.id] ?? NSWorkspace.shared.icon(forFile: item.path))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 46, height: 46)
                    .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                    .opacity(progress == nil ? 1 : 0.45)
                if let progress {
                    Circle().stroke(.white.opacity(0.15), lineWidth: 3).frame(width: 30, height: 30)
                    Circle().trim(from: 0, to: progress)
                        .stroke(Color.green, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 30, height: 30)
                        .animation(.linear(duration: 0.2), value: progress)
                }
            }
            .frame(width: 58, height: 50)
            .overlay(alignment: .topTrailing) {
                if hover && progress == nil {
                    Button { model.onShelfRemove(item) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 7, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 15, height: 15)
                            .background(Circle().fill(Color(white: 0.25)))
                    }
                    .buttonStyle(.plain)
                    .help("Remove from shelf (keeps the file)")
                    .offset(x: 2, y: -2)
                }
            }

            Text(item.name)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 70, height: 24, alignment: .top)

            HStack(spacing: 4) {
                RowIconButton(icon: "airplayaudio", help: "AirDrop", tint: .white) { model.onShelfAirDrop([item]) }
                RowIconButton(icon: "iphone.gen3", help: item.isDirectory ? "Folders can't be sent to the phone" : "Send to phone",
                              tint: item.isDirectory ? .white.opacity(0.3) : .green) {
                    if !item.isDirectory { model.onShelfSendToPhone(item) }
                }
            }
            .opacity(hover ? 1 : 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 3)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(hover ? 0.07 : 0)))
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
        .onTapGesture(count: 2) { model.onShelfOpen(item) }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .help("\(item.name)\nDouble-click to open · drag out to use it")
    }
}
