import AppKit
import SwiftUI

/// Small building blocks shared by the peek, card and dashboard views.

func ageString(_ date: Date) -> String {
    let s = Int(Date().timeIntervalSince(date))
    if s < 60 { return "now" }
    if s < 3600 { return "\(s / 60)m" }
    if s < 86400 { return "\(s / 3600)h" }
    return date.formatted(.dateTime.day().month(.abbreviated))
}

/// Sender photo (or app icon / initial) with an optional little app badge.
struct AvatarView: View {
    let n: PhoneNotification
    let size: CGFloat
    let badge: Bool
    let appIcon: NSImage?
    let accent: NSColor

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let large = n.largeIcon {
                    Image(nsImage: large).resizable().scaledToFill()
                } else if let appIcon {
                    Image(nsImage: appIcon).resizable().scaledToFit()
                } else {
                    ZStack {
                        Color(nsColor: accent).opacity(0.25)
                        Text(String((n.title.isEmpty ? n.app : n.title).prefix(1)).uppercased())
                            .font(.system(size: size * 0.45, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())

            if badge, n.largeIcon != nil, let appIcon {
                Image(nsImage: appIcon).resizable().scaledToFit()
                    .frame(width: size * 0.42, height: size * 0.42)
                    .clipShape(Circle())
                    .padding(1.5)
                    .background(Circle().fill(.black))
                    .offset(x: 3, y: 3)
            }
        }
    }
}

struct AppIconView: View {
    let icon: NSImage?
    let accent: NSColor
    let size: CGFloat

    var body: some View {
        if let icon {
            Image(nsImage: icon).resizable().scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
        } else {
            Circle().fill(Color(nsColor: accent)).frame(width: size * 0.6, height: size * 0.6)
                .frame(width: size, height: size)
        }
    }
}

/// Breathing dot (compact peek of an incoming notification).
struct PulseDot: View {
    let color: Color
    @State private var on = false

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.35)).frame(width: 12, height: 12)
                .scaleEffect(on ? 1.3 : 0.6).opacity(on ? 0 : 1)
            Circle().fill(color).frame(width: 6, height: 6)
                .shadow(color: color, radius: 3)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) { on = true }
        }
    }
}

/// Thin bar that drains until the card closes; full and dimmed while paused.
struct CountdownBar: View {
    let deadline: Date?
    let duration: TimeInterval
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: deadline == nil)) { ctx in
            let fraction: Double = {
                guard let deadline, duration > 0 else { return 1 }
                return min(1, max(0, deadline.timeIntervalSince(ctx.date) / duration))
            }()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.07))
                    Capsule()
                        .fill(LinearGradient(colors: [color.opacity(0.55), color], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * fraction)
                        .opacity(deadline == nil ? 0.35 : 1)
                }
            }
            .frame(height: 2)
        }
    }
}

struct CloseButton: View {
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 7, weight: .heavy))
                .foregroundStyle(.white.opacity(hover ? 0.9 : 0.55))
                .frame(width: 15, height: 15)
                .background(Circle().fill(.white.opacity(hover ? 0.2 : 0.1)))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Hide (keeps it on the phone)")
    }
}

/// Small icon button for the island chrome (tabs, settings).
struct ChromeButton: View {
    let icon: String
    var title: String? = nil
    var selected = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                if let title { Text(title).font(.system(size: 10.5, weight: .semibold, design: .rounded)) }
            }
            .foregroundStyle(.white.opacity(selected ? 1 : (hover ? 0.85 : 0.5)))
            .padding(.horizontal, title == nil ? 6 : 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(.white.opacity(selected ? 0.16 : (hover ? 0.08 : 0))))
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
    }
}

struct IslandButton: View {
    enum Style { case primary(Color), secondary, destructive }

    let title: String
    let icon: String?
    let style: Style
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon).font(.system(size: 8.5, weight: .heavy)) }
                Text(title).font(.system(size: 11, weight: .semibold, design: .rounded)).lineLimit(1)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(background))
            .scaleEffect(hover ? 1.04 : 1)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { hover = h } }
    }

    private var foreground: Color {
        switch style {
        case .primary: return .black
        case .secondary: return .white
        case .destructive: return Color(red: 1, green: 0.42, blue: 0.4)
        }
    }

    private var background: Color {
        switch style {
        case .primary(let c): return hover ? c : c.opacity(0.9)
        case .secondary: return .white.opacity(hover ? 0.18 : 0.1)
        case .destructive: return Color.red.opacity(hover ? 0.24 : 0.14)
        }
    }
}
