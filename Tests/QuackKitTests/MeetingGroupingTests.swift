import Testing
import Foundation
@testable import QuackKit

@Suite struct MeetingGroupingTests {
    // A fixed "now": use a calendar-stable instant.
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private let now = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14 22:13 UTC

    private func ev(_ id: String, offset: TimeInterval, allDay: Bool = false, dur: TimeInterval = 1800) -> MeetingEvent {
        MeetingEvent(id: id, title: id, start: now.addingTimeInterval(offset),
                     end: now.addingTimeInterval(offset + dur), calendarID: "c", isAllDay: allDay)
    }

    @Test func groupsByDayInOrder() {
        let today = ev("today", offset: 3600)
        let tomorrow = ev("tomorrow", offset: 26 * 3600)
        let sections = MeetingGrouping.byDay([tomorrow, today], now: now, calendar: cal)
        #expect(sections.count == 2)
        #expect(sections.first?.events.first?.id == "today")
        #expect(sections.last?.events.first?.id == "tomorrow")
    }

    @Test func includesAllDayEventsSortedFirst() {
        let allDay = ev("holiday", offset: 1000, allDay: true)
        let timed = ev("standup", offset: 3600)
        let sections = MeetingGrouping.byDay([timed, allDay], now: now, calendar: cal)
        // Both are the same UTC day here.
        #expect(sections.count == 1)
        #expect(sections.first?.events.map(\.id) == ["holiday", "standup"])
    }

    @Test func dropsEndedTimedEvents() {
        let ended = ev("done", offset: -7200, dur: 1800)   // ended 1.5h ago
        let upcoming = ev("next", offset: 3600)
        let sections = MeetingGrouping.byDay([ended, upcoming], now: now, calendar: cal)
        let ids = sections.flatMap { $0.events.map(\.id) }
        #expect(ids == ["next"])
    }
}
