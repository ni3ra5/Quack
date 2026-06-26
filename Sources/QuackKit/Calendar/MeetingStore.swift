import Foundation
import Combine

/// Pure selection/filtering logic over a list of meetings. Kept separate from
/// `MeetingStore` so it can be unit tested without any Combine/timer machinery.
public enum MeetingSelection {

    /// The meeting to surface "now": an in-progress meeting takes priority,
    /// otherwise the soonest upcoming one. Meetings already ended are ignored.
    ///
    /// All-day events are excluded — they have no meaningful countdown and would
    /// otherwise dominate the menu bar all day. They still appear in `upcoming`.
    public static func currentOrNext(from events: [MeetingEvent], now: Date) -> MeetingEvent? {
        let sorted = events.filter { !$0.isAllDay }.sorted { $0.start < $1.start }
        if let inProgress = sorted.first(where: { $0.isInProgress(at: now) }) {
            return inProgress
        }
        return sorted.first(where: { $0.start > now })
    }

    /// Filters events to those overlapping `window` and, when `calendarIDs` is
    /// non-empty, belonging to one of those calendars.
    public static func filter(
        _ events: [MeetingEvent],
        window: DateInterval,
        calendarIDs: [String]
    ) -> [MeetingEvent] {
        events.filter { event in
            let overlaps = event.end > window.start && event.start < window.end
            guard overlaps else { return false }
            if calendarIDs.isEmpty { return true }
            return calendarIDs.contains(event.calendarID)
        }
    }
}

/// Observable model holding upcoming events and the current/next meeting.
/// Drives the menu-bar title and the reminders. The actual fetching is done by
/// a `CalendarProvider`; refresh is triggered externally (timer + store-changed
/// notification) by the app layer, keeping this type test-friendly.
@MainActor
public final class MeetingStore: ObservableObject {
    @Published public private(set) var upcoming: [MeetingEvent] = []

    /// How far ahead to look for events.
    public var lookaheadWindow: TimeInterval = 24 * 60 * 60

    private let provider: CalendarProvider
    private let calendarIDs: () -> [String]
    private let now: () -> Date

    public init(
        provider: CalendarProvider,
        calendarIDs: @escaping () -> [String] = { [] },
        now: @escaping () -> Date = Date.init
    ) {
        self.provider = provider
        self.calendarIDs = calendarIDs
        self.now = now
    }

    public var currentOrNext: MeetingEvent? {
        MeetingSelection.currentOrNext(from: upcoming, now: now())
    }

    /// The current/next meeting that has a join link, for the toast and menu.
    public var nextJoinableMeeting: MeetingEvent? {
        let n = now()
        return upcoming
            .sorted { $0.start < $1.start }
            .first { ($0.isInProgress(at: n) || $0.start > n) && MeetingURLParser.joinURL(for: $0) != nil }
    }

    @discardableResult
    public func refresh() async -> Bool {
        let start = now()
        let window = DateInterval(start: start, duration: lookaheadWindow)
        do {
            let fetched = try await provider.fetchEvents(window: window)
            let filtered = MeetingSelection.filter(fetched, window: window, calendarIDs: calendarIDs())
                .map { $0.withConferencingURL(MeetingURLParser.joinURL(for: $0)) }
            upcoming = filtered.sorted { $0.start < $1.start }
            return true
        } catch {
            return false
        }
    }

    public func clear() {
        upcoming = []
    }
}
