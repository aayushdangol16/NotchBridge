import AppKit
import SwiftUI

/// Dashboard Agenda tab: a 7-day strip (tap a day) and that day's events, with Join for video calls.
struct CalendarTab: View {
    @ObservedObject var model: IslandModel

    private var cal: Calendar { .current }
    private var today: Date { cal.startOfDay(for: Date()) }
    private var days: [Date] { (0..<CalendarService.daysAhead).compactMap { cal.date(byAdding: .day, value: $0, to: today) } }
    /// The selected day, never in the past (the tab may stay open across midnight).
    private var selected: Date { max(model.selectedDay, today) }

    var body: some View {
        switch model.calendarAccess {
        case .granted:
            VStack(spacing: 8) {
                weekStrip
                dayEvents
            }
        case .denied:
            placeholder(icon: "calendar.badge.exclamationmark", text: "Calendar access is off",
                        button: "Open Privacy Settings") { model.onCalendarAccess() }
        case .unknown:
            placeholder(icon: "calendar", text: "Waiting for calendar access…")
        case .off:
            placeholder(icon: "calendar", text: "Calendar is turned off", button: "Turn on") { model.onCalendarAccess() }
        }
    }

    // MARK: Week strip

    private var weekStrip: some View {
        HStack(spacing: 4) {
            ForEach(days, id: \.self) { day in
                DayChip(day: day,
                        isToday: cal.isDate(day, inSameDayAs: today),
                        isSelected: cal.isDate(day, inSameDayAs: selected),
                        eventCount: events(on: day).count)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { model.selectedDay = day }
                    }
            }
        }
    }

    func events(on day: Date) -> [CalEvent] {
        guard let next = cal.date(byAdding: .day, value: 1, to: day) else { return [] }
        return model.events.filter { $0.start < next && $0.end > day }
    }

    // MARK: Events of the selected day

    @ViewBuilder private var dayEvents: some View {
        let list = events(on: selected)
        if list.isEmpty {
            if model.calendarCount == 0 {
                VStack(spacing: 6) {
                    Text("No calendars on this Mac")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                    Text("Add Google, iCloud or Outlook in System Settings › Internet Accounts, then they show up here.")
                        .font(.system(size: 10.5, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                    IslandButton(title: "Open Internet Accounts", icon: "person.crop.circle.badge.plus", style: .secondary) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "sun.max").font(.system(size: 16)).foregroundStyle(.white.opacity(0.3))
                    Text(cal.isDate(selected, inSameDayAs: today) ? "Nothing else today" : "No events")
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if list.count <= 2 {
            VStack(spacing: 2) { ForEach(list) { EventRow(model: model, event: $0) } }
                .frame(maxHeight: .infinity, alignment: .top)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) { ForEach(list) { EventRow(model: model, event: $0) } }
            }
        }
    }

    private func placeholder(icon: String, text: String, button: String? = nil, action: @escaping () -> Void = {}) -> some View {
        VStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(.white.opacity(0.3))
            Text(text).font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.45))
            if let button {
                IslandButton(title: button, icon: nil, style: .secondary, action: action)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One day in the week strip: weekday, date, and a dot per event (up to 3).
private struct DayChip: View {
    let day: Date
    let isToday: Bool
    let isSelected: Bool
    let eventCount: Int
    @State private var hover = false

    var body: some View {
        VStack(spacing: 2) {
            Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                .foregroundStyle(isSelected ? .black.opacity(0.6) : .white.opacity(0.4))
            Text(day.formatted(.dateTime.day()))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(isSelected ? .black : (isToday ? Color(red: 1, green: 0.36, blue: 0.33) : .white))
            HStack(spacing: 2) {
                ForEach(0..<min(eventCount, 3), id: \.self) { _ in
                    Circle().fill(isSelected ? Color.black.opacity(0.55) : Color.white.opacity(0.6)).frame(width: 3.5, height: 3.5)
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(isSelected ? Color.white : .white.opacity(hover ? 0.08 : (isToday ? 0.05 : 0))))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
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
