import AppKit
import SwiftUI

/// The open island (mode .open): Home and Phone tabs below the camera strip.
struct DashboardView: View {
    @ObservedObject var model: IslandModel
    static let contentHeight: CGFloat = 132

    var body: some View {
        Group {
            switch model.tab {
            case .home: home
            case .phone: phone
            }
        }
        .frame(height: Self.contentHeight, alignment: .top)
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }

    // MARK: Home

    private var home: some View {
        HStack(alignment: .top, spacing: 14) {
            // Clock
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
                }
            }
            .frame(width: 150, alignment: .leading)

            // Phone summary
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
    }

    private var phoneStatusRow: some View {
        HStack(spacing: 6) {
            Circle().fill(model.phoneConnected ? Color.green : Color.white.opacity(0.25)).frame(width: 6, height: 6)
            Text(model.phoneConnected ? (model.phoneName ?? "Phone") : (model.phoneName.map { "\($0) · offline" } ?? "No phone paired"))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
            Spacer(minLength: 0)
            if model.phoneName == nil {
                Button("Pair") { model.onPairPhone() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(.white))
            } else if !model.recent.isEmpty {
                Text("\(model.recent.count)")
                    .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(.white.opacity(0.85)))
            }
        }
    }

    // MARK: Phone

    @ViewBuilder
    private var phone: some View {
        if model.recent.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "bell.slash").font(.system(size: 20)).foregroundStyle(.white.opacity(0.3))
                Text(model.phoneConnected ? "All caught up" : "Phone not connected")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.recent.count <= 4 {
            list
        } else {
            ScrollView(.vertical, showsIndicators: false) { list }
        }
    }

    private var list: some View {
        VStack(spacing: 2) {
            ForEach(model.recent.prefix(25)) { n in
                NotificationRow(model: model, n: n)
            }
        }
    }
}

/// One-line notification row; click to show it again as a card.
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
