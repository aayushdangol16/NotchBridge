import AppKit
import SwiftUI

/// Dashboard Calendar tab: today's and tomorrow's events, with Join for video calls.
struct CalendarTab: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        switch model.calendarAccess {
        case .granted:
            if model.events.isEmpty {
                placeholder(icon: "calendar.badge.checkmark", text: "Nothing left today or tomorrow")
            } else if model.events.count <= 3 {
                list
            } else {
                ScrollView(.vertical, showsIndicators: false) { list }
            }
        case .denied:
            placeholder(icon: "calendar.badge.exclamationmark",
                        text: "Calendar access is off",
                        button: "Open Privacy Settings")
        case .unknown:
            placeholder(icon: "calendar", text: "Waiting for calendar access…")
        case .off:
            placeholder(icon: "calendar", text: "Calendar is turned off", button: "Turn on")
        }
    }

    private var list: some View {
        let cal = Calendar.current
        let today = model.events.filter { cal.isDateInToday($0.start) || $0.isHappening() }
        let tomorrow = model.events.filter { !today.contains($0) }
        return VStack(alignment: .leading, spacing: 3) {
            if !today.isEmpty { section("Today", today) }
            if !tomorrow.isEmpty { section("Tomorrow", tomorrow) }
        }
    }

    private func section(_ title: String, _ events: [CalEvent]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.35))
                .padding(.leading, 6)
            ForEach(events) { e in EventRow(model: model, event: e) }
        }
    }

    private func placeholder(icon: String, text: String, button: String? = nil) -> some View {
        VStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(.white.opacity(0.3))
            Text(text).font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.45))
            if let button {
                IslandButton(title: button, icon: nil, style: .secondary) { model.onCalendarAccess() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EventRow: View {
    @ObservedObject var model: IslandModel
    let event: CalEvent
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(Color(nsColor: event.color))
                .frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text(event.title)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text([timeRange(event), event.location].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            TimelineView(.periodic(from: .now, by: 30)) { ctx in
                if event.canJoin(at: ctx.date), let url = event.joinURL {
                    IslandButton(title: "Join", icon: "video.fill", style: .primary(Color(nsColor: event.color))) {
                        model.onJoin(url)
                    }
                } else if event.isHappening(at: ctx.date) {
                    Text("Now").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(.green)
                } else if !event.isAllDay {
                    Text(minutesUntil(event.start, now: ctx.date))
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(hover ? 0.06 : 0)))
        .onHover { hover = $0 }
    }
}

/// One-line "next event" for the Home clock column.
struct NextEventLine: View {
    let event: CalEvent

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(Color(nsColor: event.color)).frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 0) {
                Text(event.title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                Text(event.isAllDay ? "All day" : (event.isHappening() ? "Now" : minutesUntil(event.start)))
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }
}
