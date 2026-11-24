import AppKit
import SwiftUI

/// Dashboard Agenda tab: this month's calendar (today circled, dots on days with events).
/// Click a day to see its events beside the grid.
struct CalendarTab: View {
    @ObservedObject var model: IslandModel

    private var cal: Calendar { .current }
    private var today: Date { cal.startOfDay(for: Date()) }
    private var monthStart: Date { cal.date(from: cal.dateComponents([.year, .month], from: today)) ?? today }
    /// Selected day, kept inside the current month.
    private var selected: Date {
        cal.isDate(model.selectedDay, equalTo: today, toGranularity: .month) ? model.selectedDay : today
    }

    var body: some View {
        switch model.calendarAccess {
        case .granted:
            HStack(alignment: .top, spacing: 14) {
                MonthGrid(month: monthStart, today: today, selected: selected,
                          eventDays: eventDays) { day in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { model.selectedDay = day }
                }
                .frame(width: 236)
                dayColumn
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

    /// Day-of-month numbers (current month) that have at least one event.
    private var eventDays: Set<Int> {
        var days = Set<Int>()
        guard let range = cal.range(of: .day, in: .month, for: monthStart) else { return days }
        for d in range {
            guard let day = cal.date(byAdding: .day, value: d - 1, to: monthStart) else { continue }
            if !events(on: day).isEmpty { days.insert(d) }
        }
        return days
    }

    func events(on day: Date) -> [CalEvent] {
        guard let next = cal.date(byAdding: .day, value: 1, to: day) else { return [] }
        return model.events.filter { $0.start < next && $0.end > day }
    }

    // MARK: Selected day

    private var dayColumn: some View {
        let list = events(on: selected)
        return VStack(alignment: .leading, spacing: 4) {
            Text(cal.isDate(selected, inSameDayAs: today) ? "Today" : selected.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
            if list.isEmpty {
                Spacer(minLength: 0)
                Text(model.calendarCount == 0 ? "No calendars on this Mac" : "No events")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity)
                if model.calendarCount == 0 {
                    IslandButton(title: "Add an account", icon: "person.crop.circle.badge.plus", style: .secondary) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                Spacer(minLength: 0)
            } else if list.count <= 3 {
                VStack(spacing: 2) { ForEach(list) { EventRow(model: model, event: $0) } }
                Spacer(minLength: 0)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 2) { ForEach(list) { EventRow(model: model, event: $0) } }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

/// The month grid: month title, weekday initials (locale's first weekday), and day numbers.
struct MonthGrid: View {
    let month: Date           // first day of the month
    let today: Date
    let selected: Date
    let eventDays: Set<Int>
    let onSelect: (Date) -> Void

    private var cal: Calendar { .current }

    /// Leading blanks + day numbers, padded to whole weeks.
    private var cells: [Int?] {
        guard let range = cal.range(of: .day, in: .month, for: month) else { return [] }
        let weekday = cal.component(.weekday, from: month)
        let lead = (weekday - cal.firstWeekday + 7) % 7
        var c: [Int?] = Array(repeating: nil, count: lead) + range.map { Optional($0) }
        while c.count % 7 != 0 { c.append(nil) }
        return c
    }

    private var weekdaySymbols: [String] {
        let s = cal.veryShortStandaloneWeekdaySymbols
        let first = cal.firstWeekday - 1
        return Array(s[first...] + s[..<first])
    }

    var body: some View {
        let rows = cells.count / 7
        VStack(spacing: 3) {
            HStack {
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
            }
            HStack(spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, s in
                    Text(s)
                        .font(.system(size: 8.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.35))
                        .frame(maxWidth: .infinity)
                }
            }
            VStack(spacing: rows > 5 ? 0 : 1) {
                ForEach(0..<rows, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { col in
                            dayCell(cells[r * 7 + col])
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ day: Int?) -> some View {
        if let day, let date = cal.date(byAdding: .day, value: day - 1, to: month) {
            let isToday = cal.isDate(date, inSameDayAs: today)
            let isSelected = cal.isDate(date, inSameDayAs: selected)
            let isPast = date < today
            Button { onSelect(date) } label: {
                VStack(spacing: 1) {
                    Text("\(day)")
                        .font(.system(size: 10.5, weight: isToday || isSelected ? .bold : .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isToday ? .white : (isSelected ? .black : .white.opacity(isPast ? 0.4 : 0.85)))
                        .frame(width: 19, height: 15)
                        .background {
                            if isToday {
                                Circle().fill(Color(red: 1, green: 0.27, blue: 0.25))
                            } else if isSelected {
                                Circle().fill(.white)
                            }
                        }
                        .overlay {
                            if isToday && isSelected { Circle().stroke(.white, lineWidth: 1.2).padding(-1.5) }
                        }
                    Circle()
                        .fill(eventDays.contains(day) ? Color.white.opacity(isPast ? 0.35 : 0.75) : .clear)
                        .frame(width: 3, height: 3)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Color.clear.frame(maxWidth: .infinity, minHeight: 19, maxHeight: 19)
        }
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
                } else if !event.isAllDay && event.start > ctx.date {
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
