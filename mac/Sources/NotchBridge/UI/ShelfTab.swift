import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum ShelfDrop {
    /// File URLs from dropped item providers (Finder, Desktop, most apps).
    static func loadURLs(_ providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var url: URL?
                if let d = item as? Data { url = URL(dataRepresentation: d, relativeTo: nil) }
                else if let u = item as? URL { url = u }
                else if let s = item as? String { url = URL(string: s) }
                if let url { lock.lock(); urls.append(url); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) { completion(urls) }
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
