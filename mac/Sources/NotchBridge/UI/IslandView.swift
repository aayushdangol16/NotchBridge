import AppKit
import SwiftUI

private struct IslandSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

/// Root of the island. One black shape that morphs between:
///   idle      notch-sized, invisible (the hardware notch shows through)
///   peek      a little wider: phone status left of the camera, notification count right
///   activity  compact (avatar + pulse) ► full notification card
///   open      dashboard with tabs
struct IslandView: View {
    @ObservedObject var model: IslandModel
    @Namespace private var ns

    static let cardWidth: CGFloat = 350
    static let dashboardWidth: CGFloat = 480
    private let peekWing: CGFloat = 24
    private let activityWing: CGFloat = 32

    var body: some View {
        ZStack(alignment: .top) {
            island
        }
        .frame(width: IslandController.panelSize.width, height: IslandController.panelSize.height, alignment: .top)
    }

    // MARK: - Geometry per state

    private var isCard: Bool { model.mode == .activity && model.stage == .full && model.notification != nil }

    private var radii: (top: CGFloat, bottom: CGFloat) {
        switch model.mode {
        case .idle: return (6, 10)
        case .peek: return (8, 13)
        case .activity: return model.stage == .full ? (12, 24) : (8, 14)
        case .open: return (14, 28)
        }
    }

    private var width: CGFloat {
        let notch = model.notchSize.width
        switch model.mode {
        case .idle: return notch + 2 * radii.top
        case .peek: return notch + 2 * peekWing + 2 * radii.top
        case .activity: return model.stage == .full ? Self.cardWidth : notch + 2 * activityWing + 2 * radii.top
        case .open: return Self.dashboardWidth
        }
    }

    private var accent: Color {
        model.notification.map { Color(nsColor: model.accent($0.pkg)) } ?? Color(nsColor: AccentColor.fallback)
    }

    // MARK: - Island

    private var island: some View {
        let shape = NotchShape(topRadius: radii.top, bottomRadius: radii.bottom)
        let elevated = isCard || model.mode == .open

        return VStack(spacing: 0) {
            topBar
                .frame(height: model.notchSize.height)
            if isCard, let n = model.notification {
                NotificationCard(model: model, n: n, accent: accent, ns: ns)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .top))
                            .animation(.spring(response: 0.45, dampingFraction: 0.8).delay(0.06)),
                        removal: .opacity.animation(.easeOut(duration: 0.12))))
            }
            if model.mode == .open {
                DashboardView(model: model)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top))
                            .animation(.spring(response: 0.42, dampingFraction: 0.8).delay(0.05)),
                        removal: .opacity.animation(.easeOut(duration: 0.1))))
            }
        }
        .padding(.horizontal, radii.top)
        .frame(width: width, alignment: .top)
        .background {
            ZStack {
                Color.black
                RadialGradient(colors: [accent.opacity(isCard ? 0.34 : 0), .clear],
                               center: UnitPoint(x: 0.12, y: 0.4), startRadius: 0, endRadius: 190)
                LinearGradient(colors: [.clear, accent.opacity(isCard ? 0.08 : 0)], startPoint: .top, endPoint: .bottom)
            }
        }
        .clipShape(shape)
        .overlay {
            shape.stroke(
                LinearGradient(colors: [.clear, .white.opacity(model.hovering ? 0.2 : 0.11)], startPoint: .top, endPoint: .bottom),
                lineWidth: 1)
                .opacity(elevated ? 1 : 0)
        }
        .shadow(color: .black.opacity(elevated ? 0.5 : 0), radius: 16, y: 8)
        .shadow(color: accent.opacity(isCard ? 0.2 : 0), radius: 20, y: 4)
        // Idle: invisible — the hardware notch is the island. (On Macs without a notch, nothing at all.)
        .opacity(model.mode == .idle ? 0 : 1)
        .scaleEffect(model.hovering && isCard && !model.expanded ? 1.025 : 1, anchor: .top)
        .contentShape(shape)
        .onTapGesture {
            if model.mode == .peek || model.mode == .idle { model.onOpenDashboard() }
        }
        .background(GeometryReader { g in Color.clear.preference(key: IslandSizeKey.self, value: g.size) })
        .onPreferenceChange(IslandSizeKey.self) { model.onIslandSize($0) }
    }

    // MARK: - Strip beside the camera

    @ViewBuilder
    private var topBar: some View {
        HStack(spacing: 0) {
            switch model.mode {
            case .idle:
                Spacer()
            case .peek:
                peekBar
            case .activity:
                if let n = model.notification {
                    if model.stage == .compact { compactActivityBar(n) } else { cardHeaderBar(n) }
                } else {
                    Spacer()
                }
            case .open:
                dashboardBar
            }
        }
        .padding(.top, 2)
    }

    /// Hover peek: phone link status on the left, notification count (or a hint) on the right.
    private var peekBar: some View {
        HStack(spacing: 0) {
            Image(systemName: model.phoneConnected ? "iphone.gen3.radiowaves.left.and.right" : "iphone.gen3.slash")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(model.phoneConnected ? Color.green : Color.white.opacity(0.4))
                .padding(.leading, 9)
                .transition(.opacity)
            Spacer()
            Group {
                if model.recent.isEmpty {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.45))
                } else {
                    Text(model.recent.count > 9 ? "9+" : "\(model.recent.count)")
                        .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background(Capsule().fill(.white.opacity(0.9)))
                }
            }
            .padding(.trailing, 9)
            .transition(.opacity)
        }
    }

    private func compactActivityBar(_ n: PhoneNotification) -> some View {
        HStack(spacing: 0) {
            AvatarView(n: n, size: 18, badge: false, appIcon: model.appIcon(n.pkg), accent: model.accent(n.pkg))
                .matchedGeometryEffect(id: "avatar", in: ns)
                .padding(.leading, 9)
            Spacer()
            PulseDot(color: accent)
                .padding(.trailing, 11)
        }
    }

    /// Space on each side of the camera inside a strip of the given width.
    private func side(_ total: CGFloat) -> CGFloat {
        max(40, (total - 2 * radii.top - model.notchSize.width) / 2)
    }

    private func cardHeaderBar(_ n: PhoneNotification) -> some View {
        HStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 5) {
                    AppIconView(icon: model.appIcon(n.pkg), accent: model.accent(n.pkg), size: 13)
                    Text(n.app)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                        .fixedSize()
                }
                AppIconView(icon: model.appIcon(n.pkg), accent: model.accent(n.pkg), size: 13)
            }
            .padding(.leading, 14)
            .frame(width: side(Self.cardWidth), alignment: .leading)
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                if model.queued > 0 {
                    Text("+\(model.queued)")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background(Capsule().fill(accent))
                }
                Text(ageString(n.time))
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.trailing, 14)
            .frame(width: side(Self.cardWidth), alignment: .trailing)
        }
    }

    /// Dashboard strip: tabs on the left of the camera, phone dot + settings on the right.
    private var dashboardBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(IslandModel.Tab.allCases) { tab in
                    ChromeButton(icon: tab.icon, title: model.tab == tab ? tab.title : nil, selected: model.tab == tab) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { model.tab = tab }
                    }
                }
            }
            .padding(.leading, 12)
            .frame(width: side(Self.dashboardWidth), alignment: .leading)
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Circle().fill(model.phoneConnected ? Color.green : Color.white.opacity(0.25))
                    .frame(width: 6, height: 6)
                    .help(model.phoneConnected ? "Phone connected" : "Phone offline")
                ChromeButton(icon: "gearshape.fill") { model.onOpenSettings() }
                    .help("Settings")
            }
            .padding(.trailing, 12)
            .frame(width: side(Self.dashboardWidth), alignment: .trailing)
        }
        .transition(.opacity)
    }
}
