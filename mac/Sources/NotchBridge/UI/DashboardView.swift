import AppKit
import SwiftUI

/// The open island (mode .open): Home and Phone tabs below the camera strip.
struct DashboardView: View {
    @ObservedObject var model: IslandModel
    static let contentHeight: CGFloat = 150

    var body: some View {
        Group {
            switch model.tab {
            case .home: home
            case .phone: phone
            case .calendar: CalendarTab(model: model)
            case .shelf: ShelfTab(model: model)
            case .mirror: MirrorTab(model: model)
            }
        }
        .frame(height: Self.contentHeight, alignment: .top)
        .overlay(alignment: .bottom) { toast }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }

    // MARK: Toast

    @ViewBuilder private var toast: some View {
        if let toast = model.toast {
            HStack(spacing: 6) {
                Image(systemName: model.toastIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                Text(toast).lineLimit(1)
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(model.toastIsError ? Color.orange : Color.green)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(Color(white: 0.12)))
            .overlay(Capsule().stroke(.white.opacity(0.08), lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    // MARK: Home

    private var home: some View {
        HStack(alignment: .top, spacing: 12) {
            if let media = model.media {
                NowPlayingCard(model: model, media: media)
                    .frame(width: 228)
            } else {
                clock
            }
            phoneCard
        }
    }

    private var clock: some View {
            TimelineView(.everyMinute) { ctx in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(ctx.date.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute()))
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                        Text(ctx.date.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated))).filter { $0.isLetter })
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    Text(ctx.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                    let upcoming = model.events.filter { $0.end > ctx.date }
                    if let next = upcoming.first(where: { !$0.isAllDay }) ?? upcoming.first {
                        Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { model.tab = .calendar } } label: {
                            NextEventLine(event: next)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 10)
                        .help("Open the Calendar tab")
                    }
                }
            }
            .frame(width: 150, alignment: .leading)
    }

    private var phoneCard: some View {
            VStack(alignment: .leading, spacing: 8) {
                phoneStatusRow
                if !model.recent.isEmpty {
                    VStack(spacing: 2) {
                        ForEach(model.recent.prefix(2)) { n in NotificationRow(model: model, n: n) }
                    }
                } else {
                    Text("No phone notifications yet")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.white.opacity(0.35))
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.06)))
    }

    private var phoneStatusRow: some View {
        HStack(spacing: 6) {
            Circle().fill(model.phoneConnected ? Color.green : Color.white.opacity(0.25)).frame(width: 6, height: 6)
            Text(model.phoneConnected ? (model.phoneName ?? "Phone") : (model.phoneName.map { "\($0) · offline" } ?? "No phone paired"))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
            if model.phoneConnected, let level = model.phoneBattery {
                BatteryView(level: level, charging: model.phoneCharging)
            }
            Spacer(minLength: 0)
            if model.phoneName == nil {
                Button("Pair") { model.onPairPhone() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(.white))
            } else if !model.recent.isEmpty {
                Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { model.tab = .phone } } label: {
                    Text("\(model.recent.count)")
                        .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(.white.opacity(0.85)))
                }
                .buttonStyle(.plain)
                .help("Open the Phone tab")
            }
        }
    }

    // MARK: Phone

    private var phone: some View {
        VStack(alignment: .leading, spacing: 6) {
            phoneHeader
            if model.recent.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: model.phoneConnected ? "checkmark.circle" : "iphone.gen3.slash")
                        .font(.system(size: 20)).foregroundStyle(.white.opacity(0.3))
                    Text(model.phoneConnected ? "All caught up" : "Phone not connected")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.recent.count <= 3 {
                list
            } else {
                ScrollView(.vertical, showsIndicators: false) { list }
            }
        }
    }

    private var phoneHeader: some View {
        HStack(spacing: 8) {
            Circle().fill(model.phoneConnected ? Color.green : Color.white.opacity(0.25)).frame(width: 6, height: 6)
            Text(model.phoneName ?? "No phone")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
            if model.phoneConnected, let level = model.phoneBattery {
                BatteryView(level: level, charging: model.phoneCharging)
            }
            Spacer(minLength: 4)
            if model.phoneConnected {
                IslandButton(title: model.phoneRinging ? "Stop ringing" : "Find phone",
                             icon: model.phoneRinging ? "speaker.slash.fill" : "speaker.wave.2.fill",
                             style: model.phoneRinging ? .primary(.orange) : .secondary) {
                    model.onRing(!model.phoneRinging)
                }
                .help("Ring the phone at full volume, even on silent")
            }
            if !model.recent.isEmpty {
                IslandButton(title: "Clear all", icon: "xmark", style: .destructive) { model.onClearAll() }
                    .help("Dismiss all of these on the phone too")
            }
        }
    }

    private var list: some View {
        VStack(spacing: 2) {
            ForEach(model.recent.prefix(30)) { n in
                PhoneRow(model: model, n: n)
            }
        }
    }
}

// MARK: - Rows

/// Compact row for Home; click to show it again as a card.
struct NotificationRow: View {
    @ObservedObject var model: IslandModel
    let n: PhoneNotification
    @State private var hover = false

    var body: some View {
        Button { model.onReshow(n) } label: {
            HStack(spacing: 8) {
                AvatarView(n: n, size: 24, badge: true, appIcon: model.appIcon(n.pkg), accent: model.accent(n.pkg))
                VStack(alignment: .leading, spacing: 0) {
                    Text(n.title.isEmpty ? n.app : n.title)
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(n.text)
                        .font(.system(size: 10.5, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(ageString(n.time))
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(hover ? 0.08 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Phone tab row: click to expand (full text + actions); hover for quick Reply / action / Clear;
/// reply inline without leaving the dashboard.
struct PhoneRow: View {
    @ObservedObject var model: IslandModel
    let n: PhoneNotification
    @State private var hover = false
    @FocusState private var focused: Bool

    private var expanded: Bool { model.openRowKey == n.key }
    private var replying: Bool { model.rowReplyKey == n.key }
    private var accent: Color { Color(nsColor: model.accent(n.pkg)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: expanded ? .top : .center, spacing: 8) {
                AvatarView(n: n, size: 26, badge: true, appIcon: model.appIcon(n.pkg), accent: model.accent(n.pkg))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(n.title.isEmpty ? n.app : n.title)
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if expanded {
                            Text("· \(n.app)")
                                .font(.system(size: 10, design: .rounded))
                                .foregroundStyle(.white.opacity(0.4))
                                .lineLimit(1)
                        }
                    }
                    Text(n.text)
                        .font(.system(size: 10.5, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(expanded ? 6 : 1)
                        .fixedSize(horizontal: false, vertical: expanded)
                }
                Spacer(minLength: 4)
                if hover || expanded {
                    quickActions
                        .transition(.opacity)
                } else {
                    Text(ageString(n.time))
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    model.openRowKey = expanded ? nil : n.key
                }
            }

            if replying, let action = n.replyAction {
                replyField(action)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(.white.opacity(expanded || replying ? 0.08 : (hover ? 0.05 : 0))))
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
    }

    private var quickActions: some View {
        HStack(spacing: 4) {
            if let reply = n.replyAction {
                RowIconButton(icon: "arrowshape.turn.up.left.fill", help: reply.title.isEmpty ? "Reply" : reply.title,
                              tint: accent) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        model.rowReplyKey = replying ? nil : n.key
                        model.rowReplyText = ""
                    }
                    model.onNeedKeyboard()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { focused = true }
                }
            }
            if let action = n.buttonActions.first {
                RowIconButton(icon: "checkmark", help: action.title, tint: .white) { model.onAction(n, action) }
            }
            RowIconButton(icon: "xmark", help: "Clear (also on the phone)", tint: Color(red: 1, green: 0.42, blue: 0.4)) {
                model.onDismiss(n)
            }
        }
    }

    private func replyField(_ action: WireAction) -> some View {
        let empty = model.rowReplyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(spacing: 8) {
            TextField("", text: $model.rowReplyText,
                      prompt: Text("Reply to \(n.title.isEmpty ? n.app : n.title)…").foregroundStyle(.white.opacity(0.35)))
                .textFieldStyle(.plain)
                .font(.system(size: 11.5, design: .rounded))
                .foregroundStyle(.white)
                .focused($focused)
                .onSubmit { send(action) }
                .onExitCommand { model.rowReplyKey = nil }
            Button { send(action) } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(empty ? .white.opacity(0.4) : .black)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(empty ? Color.white.opacity(0.12) : accent))
            }
            .buttonStyle(.plain)
            .disabled(empty)
        }
        .padding(.leading, 10)
        .padding(.trailing, 3)
        .padding(.vertical, 3)
        .background(Capsule().fill(.white.opacity(0.09)))
        .overlay(Capsule().stroke(accent.opacity(focused ? 0.6 : 0.15), lineWidth: 1))
        .padding(.leading, 34)
    }

    private func send(_ action: WireAction) {
        let text = model.rowReplyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        model.onReply(n, action, text)
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            model.rowReplyKey = nil
            model.rowReplyText = ""
        }
    }
}

struct RowIconButton: View {
    let icon: String
    let help: String
    let tint: Color
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(tint.opacity(hover ? 1 : 0.8))
                .frame(width: 22, height: 22)
                .background(Circle().fill(.white.opacity(hover ? 0.16 : 0.08)))
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hover = $0 }
    }
}

/// Phone battery: a small battery glyph + percent; green bolt while charging, red when low.
struct BatteryView: View {
    let level: Int
    let charging: Bool

    private var symbol: String {
        if charging { return "battery.100percent.bolt" }
        switch level {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private var color: Color {
        if charging { return .green }
        return level <= 20 ? Color(red: 1, green: 0.35, blue: 0.3) : .white.opacity(0.7)
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 10.5))
            Text("\(level)%")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(color)
        .help(charging ? "Phone charging, \(level)%" : "Phone battery \(level)%")
    }
}
