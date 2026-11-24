import AppKit
import SwiftUI

/// Album art (or a music-note placeholder), rounded.
struct ArtworkView: View {
    let media: NowPlaying
    let size: CGFloat
    let accent: Color

    var body: some View {
        Group {
            if let art = media.artwork {
                Image(nsImage: art).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [accent.opacity(0.55), accent.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note").font(.system(size: size * 0.45, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }
}

/// Little equalizer bars: dancing while playing, resting while paused. (Animated, not real audio levels.)
struct MusicBars: View {
    let playing: Bool
    let color: Color
    var height: CGFloat = 12

    private let speeds: [Double] = [0.42, 0.33, 0.51, 0.38]
    @State private var up = false

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                Capsule()
                    .fill(color)
                    .frame(width: 2.5, height: height)
                    .scaleEffect(y: playing ? (up ? [0.9, 0.5, 1.0, 0.65][i] : [0.35, 0.95, 0.4, 0.85][i]) : 0.25, anchor: .center)
                    .animation(playing ? .easeInOut(duration: speeds[i]).repeatForever(autoreverses: true) : .easeOut(duration: 0.2),
                               value: up)
            }
        }
        .frame(height: height)
        .onAppear { up = true }
        .onChange(of: playing) { _, _ in up.toggle() }
    }
}

/// Player for the dashboard's Home tab.
struct NowPlayingCard: View {
    @ObservedObject var model: IslandModel
    let media: NowPlaying

    private var accent: Color { Color(nsColor: model.mediaAccent) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                ArtworkView(media: media, size: 58, accent: accent)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: media.source == .phone ? "iphone.gen3" : "laptopcomputer")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(3)
                            .background(Circle().fill(.black.opacity(0.75)))
                            .offset(x: 4, y: 4)
                    }
                VStack(alignment: .leading, spacing: 1) {
                    Text(media.title)
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(media.artist.isEmpty ? media.album : media.artist)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        MusicBars(playing: media.isPlaying, color: accent, height: 8)
                        Text(media.source == .phone ? "\(media.appName) · Phone" : media.appName)
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                    .padding(.top, 3)
                }
                Spacer(minLength: 0)
            }

            progress

            HStack(spacing: 22) {
                Spacer(minLength: 0)
                MediaButton(icon: "backward.fill", size: 13) { model.onMedia(.previous) }
                MediaButton(icon: media.isPlaying ? "pause.fill" : "play.fill", size: 18) { model.onMedia(.togglePlayPause) }
                MediaButton(icon: "forward.fill", size: 13) { model.onMedia(.next) }
                Spacer(minLength: 0)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [accent.opacity(0.22), .white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
    }

    @ViewBuilder private var progress: some View {
        if let duration = media.duration, duration > 1 {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let pos = media.position(at: ctx.date)
                VStack(spacing: 2) {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.12))
                            Capsule().fill(accent).frame(width: g.size.width * min(1, pos / duration))
                        }
                    }
                    .frame(height: 3)
                    HStack {
                        Text(Self.time(pos))
                        Spacer()
                        Text("-" + Self.time(max(0, duration - pos)))
                    }
                    .font(.system(size: 8.5, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.4))
                }
            }
        }
    }

    static func time(_ s: Double) -> String {
        let t = Int(s.rounded())
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
    }
}

struct MediaButton: View {
    let icon: String
    let size: CGFloat
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(.white.opacity(hover ? 1 : 0.85))
                .frame(width: size + 14, height: size + 10)
                .background(Circle().fill(.white.opacity(hover ? 0.12 : 0)))
                .scaleEffect(hover ? 1.08 : 1)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { hover = h } }
    }
}
