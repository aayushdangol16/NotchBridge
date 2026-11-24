import AppKit
import SwiftUI

/// Compact strip beside the camera for charging / low battery / a meeting's first beat.
struct SystemCompactBar: View {
    let activity: SystemActivity
    @State private var pulse = false

    private var accent: Color { Color(nsColor: activity.accent) }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: leftIcon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(accent)
                    .scaleEffect(pulse ? 1.15 : 0.9)
                    .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
                Text(leftText)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.leading, 10)
            Spacer(minLength: 0)
            rightSide
                .padding(.trailing, 10)
        }
        .onAppear { pulse = true }
    }

    private var leftIcon: String {
        switch activity {
        case .charging(_, let charging): return charging ? "bolt.fill" : "powerplug.fill"
        case .lowBattery: return "exclamationmark.triangle.fill"
        case .meeting: return "calendar"
        }
    }

    private var leftText: String {
        switch activity {
        case .charging(_, let charging): return charging ? "Charging" : "Plugged in"
        case .lowBattery: return "Low battery"
        case .meeting: return "Meeting"
        }
    }

    @ViewBuilder private var rightSide: some View {
        switch activity {
        case .charging(let level, _):
            BatteryFill(level: level, color: accent)
        case .lowBattery(let level):
            BatteryFill(level: level, color: accent)
        case .meeting(let e):
            Text(minutesUntil(e.start))
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
        }
    }
}

/// "82%" + a battery outline whose fill grows in on appear.
struct BatteryFill: View {
    let level: Int
    let color: Color
    @State private var shown: CGFloat = 0

    var body: some View {
        HStack(spacing: 4) {
            Text("\(level)%")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(color.opacity(0.6), lineWidth: 1.2)
                    .frame(width: 22, height: 11)
                RoundedRectangle(cornerRadius: 1.8, style: .continuous)
                    .fill(color)
                    .frame(width: max(2, 18 * shown), height: 7)
                    .padding(.leading, 2)
            }
            .overlay(alignment: .trailing) {
                Capsule().fill(color.opacity(0.6)).frame(width: 1.6, height: 4).offset(x: 2.4)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.9).delay(0.15)) { shown = CGFloat(min(max(level, 0), 100)) / 100 }
        }
    }
}

func minutesUntil(_ date: Date, now: Date = Date()) -> String {
    let m = Int((date.timeIntervalSince(now) / 60).rounded(.up))
    if m <= 0 { return "now" }
    if m < 60 { return "in \(m)m" }
    let h = m / 60, r = m % 60
    return r == 0 ? "in \(h)h" : "in \(h)h \(r)m"
}

func timeRange(_ e: CalEvent) -> String {
    if e.isAllDay { return "All day" }
    let f = Date.FormatStyle(date: .omitted, time: .shortened)
    return "\(e.start.formatted(f)) – \(e.end.formatted(f))"
}

/// "Meeting in 5 minutes" card.
struct MeetingCard: View {
    @ObservedObject var model: IslandModel
    let event: CalEvent

    private var accent: Color { Color(nsColor: event.color) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(accent)
                    .frame(width: 4, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(event.title)
                            .font(.system(size: 13.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        Spacer(minLength: 4)
                        if model.hovering {
                            CloseButton { model.onCloseActivity() }
                                .transition(.opacity.combined(with: .scale(scale: 0.6)))
                        }
                    }
                    Text([timeRange(event), event.location].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            HStack(spacing: 6) {
                if let url = event.joinURL {
                    IslandButton(title: "Join", icon: "video.fill", style: .primary(accent)) {
                        model.onJoin(url)
                        model.onCloseActivity()
                    }
                }
                Spacer(minLength: 0)
                Text(event.calendarTitle)
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(1)
            }
            CountdownBar(deadline: model.hideDeadline, duration: model.hideDuration, color: accent)
        }
        .padding(.horizontal, 13)
        .padding(.top, 6)
        .padding(.bottom, 9)
        .animation(.easeOut(duration: 0.2), value: model.hovering)
    }
}
