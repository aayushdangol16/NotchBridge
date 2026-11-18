import AppKit
import SwiftUI

/// Dynamic-Island-style notification view.
///
///   hidden ──► compact (app icon peeks out left of the camera, accent pulse on the right)
///          ──► open (card: app name & time flank the camera, avatar, sender, message, countdown)
struct NotchView: View {
    @ObservedObject var model: NotchModel
    @Namespace private var ns
    @FocusState private var replyFocused: Bool
    @State private var hovering = false

    static let openWidth: CGFloat = 440
    private let wing: CGFloat = 46            // how far the compact peek extends past each side of the notch

    var body: some View {
        ZStack(alignment: .top) {
            if let n = model.current {
                island(n)
            }
        }
        .frame(width: NotchController.panelSize.width, height: NotchController.panelSize.height, alignment: .top)
    }

    // MARK: - Island

    private var radii: (top: CGFloat, bottom: CGFloat) {
        switch model.phase {
        case .hidden: return (6, 10)
        case .compact: return (8, 14)
        case .open: return (14, 30)
        }
    }

    private var width: CGFloat {
        let n = model.notchSize.width
        switch model.phase {
        case .hidden: return n + 2 * radii.top
        case .compact: return n + 2 * wing + 2 * radii.top
        case .open: return Self.openWidth
        }
    }

    private func island(_ n: PhoneNotification) -> some View {
        let shape = NotchShape(topRadius: radii.top, bottomRadius: radii.bottom)
        let accent = Color(nsColor: model.accent(n.pkg))
        let open = model.phase == .open

        return VStack(spacing: 0) {
            topBar(n, accent: accent)
                .frame(height: model.notchSize.height)
            if open {
                card(n, accent: accent)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .top)).animation(.spring(response: 0.45, dampingFraction: 0.8).delay(0.06)),
                        removal: .opacity.animation(.easeOut(duration: 0.12))))
            }
        }
        .padding(.horizontal, radii.top)
        .frame(width: width, alignment: .top)
        .background {
            ZStack {
                Color.black
                // soft glow of the app's colour behind the avatar
                RadialGradient(colors: [accent.opacity(open ? 0.32 : 0), .clear],
                               center: UnitPoint(x: 0.12, y: 0.35), startRadius: 0, endRadius: 260)
                LinearGradient(colors: [.clear, accent.opacity(open ? 0.08 : 0)], startPoint: .top, endPoint: .bottom)
            }
        }
        .clipShape(shape)
        .overlay {
            // hairline rim that catches the light only along the lower edge
            shape.stroke(
                LinearGradient(colors: [.clear, .white.opacity(hovering ? 0.22 : 0.12)], startPoint: .top, endPoint: .bottom),
                lineWidth: 1)
                .opacity(open ? 1 : 0)
        }
        .shadow(color: .black.opacity(open ? 0.55 : 0), radius: 24, y: 10)
        .shadow(color: accent.opacity(open ? 0.18 : 0), radius: 30, y: 6)
        .scaleEffect(hovering && open && !model.expanded ? 1.015 : 1, anchor: .top)
        .onHover { inside in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { hovering = inside }
            model.onHover(inside)
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: model.expanded)
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: model.replying)
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: model.feedback)
    }

    // MARK: - Top bar (the strip beside the camera)

    @ViewBuilder
    private func topBar(_ n: PhoneNotification, accent: Color) -> some View {
        HStack(spacing: 0) {
            switch model.phase {
            case .hidden:
                Spacer()
            case .compact:
                avatar(n, size: 22, badge: false)
                    .padding(.leading, 12)
                Spacer()
                PulseDot(color: accent)
                    .padding(.trailing, 14)
            case .open:
                HStack(spacing: 6) {
                    appIcon(n, size: 15)
                    Text(n.app)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }
                .padding(.leading, 18)
                .frame(maxWidth: sideWidth, alignment: .leading)
                Spacer(minLength: model.notchSize.width)
                HStack(spacing: 6) {
                    if model.queued > 0 {
                        Text("+\(model.queued)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(accent))
                    }
                    Text(Self.age(n.time))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.trailing, 18)
                .frame(maxWidth: sideWidth, alignment: .trailing)
            }
        }
        .padding(.top, 2)
    }

    private var sideWidth: CGFloat { max(60, (Self.openWidth - model.notchSize.width) / 2 - 14) }

    // MARK: - Card

    private func card(_ n: PhoneNotification, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 13) {
                avatar(n, size: 46, badge: true)
                    .overlay(Circle().stroke(
                        AngularGradient(colors: [accent, accent.opacity(0.2), accent], center: .center),
                        lineWidth: 1.6).padding(-3))
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(n.title.isEmpty ? n.app : n.title)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        if hovering || model.expanded {
                            CloseButton { model.onClose() }
                                .transition(.opacity.combined(with: .scale(scale: 0.6)))
                        }
                    }
                    if !n.text.isEmpty {
                        Text(n.text)
                            .font(.system(size: 13.5))
                            .foregroundStyle(.white.opacity(0.78))
                            .lineSpacing(1.5)
                            .lineLimit(model.expanded ? 10 : 3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let sub = n.sub, !sub.isEmpty, model.expanded {
                        Text(sub).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.45))
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                model.expanded.toggle()
                if model.expanded { model.onExpand() }
            }

            if let feedback = model.feedback {
                HStack(spacing: 7) {
                    Image(systemName: model.feedbackIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    Text(feedback)
                }
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(model.feedbackIsError ? Color.orange : Color.green)
                .frame(maxWidth: .infinity)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else if model.replying, let reply = n.replyAction {
                replyField(n, reply, accent: accent)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else if model.expanded {
                actionRow(n, accent: accent)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if hovering {
                Text("Click for actions")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            }

            CountdownBar(deadline: model.hideDeadline, duration: model.hideDuration, color: accent)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    // MARK: - Pieces

    @ViewBuilder
    private func avatar(_ n: PhoneNotification, size: CGFloat, badge: Bool) -> some View {
        let icon = model.appIcon(n.pkg)
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let large = n.largeIcon {
                    Image(nsImage: large).resizable().scaledToFill()
                } else if let icon {
                    Image(nsImage: icon).resizable().scaledToFit()
                } else {
                    ZStack {
                        Color(nsColor: model.accent(n.pkg)).opacity(0.25)
                        Text(String((n.title.isEmpty ? n.app : n.title).prefix(1)).uppercased())
                            .font(.system(size: size * 0.45, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .matchedGeometryEffect(id: "avatar", in: ns)

            if badge, n.largeIcon != nil, let icon {
                Image(nsImage: icon).resizable().scaledToFit()
                    .frame(width: size * 0.4, height: size * 0.4)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.1, style: .continuous))
                    .padding(1.5)
                    .background(RoundedRectangle(cornerRadius: size * 0.12, style: .continuous).fill(.black))
                    .offset(x: 4, y: 4)
            }
        }
    }

    @ViewBuilder
    private func appIcon(_ n: PhoneNotification, size: CGFloat) -> some View {
        if let icon = model.appIcon(n.pkg) {
            Image(nsImage: icon).resizable().scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
        } else {
            Circle().fill(Color(nsColor: model.accent(n.pkg))).frame(width: size * 0.6, height: size * 0.6)
        }
    }

    private func actionRow(_ n: PhoneNotification, accent: Color) -> some View {
        HStack(spacing: 8) {
            if n.replyAction != nil {
                IslandButton(title: "Reply", icon: "arrowshape.turn.up.left.fill", style: .primary(accent)) {
                    model.replying = true
                    model.onExpand()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { replyFocused = true }
                }
            }
            ForEach(n.buttonActions.prefix(2), id: \.self) { a in
                IslandButton(title: a.title, icon: nil, style: .secondary) { model.onAction(n, a) }
            }
            Spacer(minLength: 0)
            IslandButton(title: "Dismiss", icon: "xmark", style: .destructive) { model.onDismiss(n) }
        }
    }

    private func replyField(_ n: PhoneNotification, _ action: WireAction, accent: Color) -> some View {
        let empty = model.replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(spacing: 8) {
            TextField("", text: $model.replyText, prompt: Text(action.title.isEmpty ? "Reply…" : "\(action.title)…")
                .foregroundStyle(.white.opacity(0.35)))
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .foregroundStyle(.white)
                .focused($replyFocused)
                .onSubmit { send(n, action) }
                .onExitCommand { model.replying = false }
            Button { send(n, action) } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(empty ? .white.opacity(0.4) : .black)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(empty ? Color.white.opacity(0.12) : accent))
            }
            .buttonStyle(.plain)
            .disabled(empty)
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background(Capsule().fill(.white.opacity(0.09)))
        .overlay(Capsule().stroke(accent.opacity(replyFocused ? 0.6 : 0.15), lineWidth: 1))
    }

    private func send(_ n: PhoneNotification, _ action: WireAction) {
        let text = model.replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        model.onReply(n, action, text)
        model.replyText = ""
        model.replying = false
    }

    static func age(_ date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        if s < 60 { return "now" }
        if s < 3600 { return "\(s / 60)m ago" }
        if s < 86400 { return "\(s / 3600)h ago" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

// MARK: - Small components

/// Breathing dot shown on the right of the compact peek.
private struct PulseDot: View {
    let color: Color
    @State private var on = false

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.35)).frame(width: 14, height: 14)
                .scaleEffect(on ? 1.25 : 0.6).opacity(on ? 0 : 1)
            Circle().fill(color).frame(width: 7, height: 7)
                .shadow(color: color, radius: 4)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) { on = true }
        }
    }
}

/// Thin bar that drains until the notch closes; full and dimmed while paused (hovering / interacting).
private struct CountdownBar: View {
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
            .frame(height: 3)
        }
    }
}

private struct CloseButton: View {
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 8.5, weight: .heavy))
                .foregroundStyle(.white.opacity(hover ? 0.9 : 0.55))
                .frame(width: 18, height: 18)
                .background(Circle().fill(.white.opacity(hover ? 0.2 : 0.1)))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Hide (keeps it on the phone)")
    }
}

private struct IslandButton: View {
    enum Style { case primary(Color), secondary, destructive }

    let title: String
    let icon: String?
    let style: Style
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).font(.system(size: 10, weight: .bold)) }
                Text(title).font(.system(size: 12, weight: .semibold, design: .rounded)).lineLimit(1)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
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
