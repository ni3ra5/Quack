import Foundation

/// A day's worth of meetings, for the dropdown's grouped list.
public struct DaySection: Identifiable, Equatable, Sendable {
    public let dayStart: Date
    public let events: [MeetingEvent]
    public var id: Date { dayStart }

    public init(dayStart: Date, events: [MeetingEvent]) {
        self.dayStart = dayStart
        self.events = events
    }
}

/// Groups upcoming meetings into day buckets for the menu. All events
/// (including all-day) are included — this drives the list, not the menu-bar
/// title. Within a day, all-day events sort first, then by start time.
public enum MeetingGrouping {

    public static func byDay(_ events: [MeetingEvent], now: Date, calendar: Calendar = .current) -> [DaySection] {
        // Keep events that haven't ended yet.
        let live = events.filter { $0.isAllDay || $0.end > now }
        let grouped = Dictionary(grouping: live) { calendar.startOfDay(for: $0.start) }
        return grouped
            .map { day, evs in
                DaySection(dayStart: day, events: evs.sorted(by: order))
            }
            .sorted { $0.dayStart < $1.dayStart }
    }

    private static func order(_ a: MeetingEvent, _ b: MeetingEvent) -> Bool {
        if a.isAllDay != b.isAllDay { return a.isAllDay }   // all-day first
        return a.start < b.start
    }
}
