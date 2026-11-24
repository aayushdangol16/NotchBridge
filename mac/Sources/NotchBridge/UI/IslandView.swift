import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Root of the island. One black shape that morphs between:
///   idle      notch-sized, invisible (the hardware notch shows through)
///   peek      a little wider: phone status left of the camera, notification count right
///   activity  compact (avatar + pulse) ► full notification card
///   open      dashboard with tabs
struct IslandView: View {
    @ObservedObject var model: IslandModel
    @Namespace private var ns

    static let cardWidth: CGFloat = IslandLayout.openWidth
    static let dashboardWidth: CGFloat = IslandLayout.openWidth

    var body: some View {
        ZStack(alignment: .top) {
            island
        }
        .frame(width: IslandController.panelSize.width, height: IslandController.panelSize.height, alignment: .top)
    }

    // MARK: - Geometry per state

    private var isCard: Bool { IslandLayout.isCard(model) }
    private var radii: (top: CGFloat, bottom: CGFloat) { IslandLayout.radii(model) }
    private var size: CGSize { IslandLayout.size(model) }

    private var accent: Color {
        if let n = model.notification { return Color(nsColor: model.accent(n.pkg)) }
        if let s = model.system { return Color(nsColor: s.accent) }
        return Color(nsColor: AccentColor.fallback)
    }

    // MARK: - Island

    private var island: some View {
        let shape = NotchShape(topRadius: radii.top, bottomRadius: radii.bottom)
        let elevated = isCard || model.mode == .open

        return VStack(spacing: 0) {
            topBar
                .frame(height: model.notchSize.height)
            if isCard, model.notification == nil, case .meeting(let e) = model.system {
                MeetingCard(model: model, event: e)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .top))
                            .animation(.spring(response: 0.45, dampingFraction: 0.8).delay(0.06)),
                        removal: .opacity.animation(.easeOut(duration: 0.12))))
            }
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
        .frame(width: size.width, height: size.height, alignment: .top)
        // Pure black, one piece with the hardware notch: no tint, no outline, no hover growth.
        // (Colour lives only in small details: avatar ring, buttons, countdown.)
        .background(Color.black)
        .clipShape(shape)
        .shadow(color: .black.opacity(elevated ? 0.45 : 0), radius: 14, y: 6)
        // Idle: invisible — the hardware notch is the island. (On Macs without a notch, nothing at all.)
        .opacity(model.mode == .idle && !model.liveVisible ? 0 : 1)
        .overlay {
            // Drop highlight while a file is dragged over the island.
            shape.stroke(Color.green.opacity(model.dropTargeted ? 0.85 : 0), lineWidth: 2)
                .animation(.easeOut(duration: 0.15), value: model.dropTargeted)
        }
        .contentShape(shape)
        .onDrop(of: [.fileURL], isTargeted: $model.dropTargeted) { providers in
            model.onDropProviders(providers)
            return true
        }
        .onTapGesture {
            if model.mode == .peek || model.mode == .idle { model.onOpenDashboard() }
        }
    }

    // MARK: - Strip beside the camera

    @ViewBuilder
    private var topBar: some View {
        HStack(spacing: 0) {
            switch model.mode {
            case .idle:
                if model.liveVisible, let media = model.media { liveBar(media) } else { Spacer() }
            case .peek:
                if let media = model.media, media.isPlaying { mediaPeekBar(media) } else { peekBar }
            case .activity:
                if let n = model.notification {
                    if model.stage == .compact { compactActivityBar(n) } else { cardHeaderBar(n) }
                } else if let s = model.system {
                    if case .meeting(let e) = s, model.stage == .full { meetingHeaderBar(e) } else { SystemCompactBar(activity: s) }
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
            Group {
                if model.phoneConnected, let level = model.phoneBattery {
                    BatteryView(level: level, charging: model.phoneCharging)
                } else {
                    Image(systemName: model.phoneConnected ? "iphone.gen3.radiowaves.left.and.right" : "iphone.gen3.slash")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(model.phoneConnected ? Color.green : Color.white.opacity(0.4))
                }
            }
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

    private var mediaAccent: Color { Color(nsColor: model.mediaAccent) }

    /// Idle while music plays: album art left of the camera, dancing bars right of it.
    private func liveBar(_ media: NowPlaying) -> some View {
        HStack(spacing: 0) {
            ArtworkView(media: media, size: 18, accent: mediaAccent)
                .matchedGeometryEffect(id: "art", in: ns)
                .padding(.leading, 9)
            Spacer()
            MusicBars(playing: media.isPlaying, color: mediaAccent)
                .padding(.trailing, 11)
        }
        .transition(.opacity)
    }

    /// Hovered while music plays: art + quick play/pause and next.
    private func mediaPeekBar(_ media: NowPlaying) -> some View {
        HStack(spacing: 0) {
            ArtworkView(media: media, size: 18, accent: mediaAccent)
                .matchedGeometryEffect(id: "art", in: ns)
                .padding(.leading, 9)
            Spacer()
            HStack(spacing: 2) {
                MediaButton(icon: media.isPlaying ? "pause.fill" : "play.fill", size: 9) { model.onMedia(.togglePlayPause) }
                MediaButton(icon: "forward.fill", size: 9) { model.onMedia(.next) }
            }
            .padding(.trailing, 4)
        }
        .transition(.opacity)
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

    private func meetingHeaderBar(_ e: CalEvent) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "calendar").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(nsColor: e.color))
                Text("Next")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.leading, 12)
            .frame(width: side(Self.cardWidth), alignment: .leading)
            Spacer(minLength: 0)
            Text(minutesUntil(e.start))
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundStyle(Color(nsColor: e.color))
                .padding(.trailing, 14)
                .frame(width: side(Self.cardWidth), alignment: .trailing)
        }
    }

    /// Dashboard strip: tabs on the left of the camera, phone dot + settings on the right.
    private var dashboardBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(IslandModel.Tab.allCases) { tab in
                    ChromeButton(icon: tab.icon, selected: model.tab == tab) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { model.tab = tab }
                    }
                    .help(tab.title)
                }
            }
            .padding(.leading, 9)
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
