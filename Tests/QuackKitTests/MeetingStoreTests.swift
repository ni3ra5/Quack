import Testing
import Foundation
@testable import QuackKit

@Suite struct MeetingSelectionTests {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func ev(_ id: String, startOffset: TimeInterval, duration: TimeInterval = 1800, cal: String = "c", title: String? = nil) -> MeetingEvent {
        MeetingEvent(id: id, title: title ?? id, start: base.addingTimeInterval(startOffset),
                     end: base.addingTimeInterval(startOffset + duration), calendarID: cal)
    }

    @Test func picksUpcomingOverInProgress() {
        // The soonest upcoming event wins even when one is in progress.
        let events = [ev("past", startOffset: -3600), ev("now", startOffset: -300), ev("soon", startOffset: 600)]
        #expect(MeetingSelection.currentOrNext(from: events, now: base)?.id == "soon")
    }

    @Test func picksSoonestUpcomingWhenNoneInProgress() {
        let events = [ev("later", startOffset: 7200), ev("soon", startOffset: 600)]
        #expect(MeetingSelection.currentOrNext(from: events, now: base)?.id == "soon")
    }

    @Test func ignoresEndedMeetings() {
        let events = [ev("ended", startOffset: -7200, duration: 1800)]
        #expect(MeetingSelection.currentOrNext(from: events, now: base) == nil)
    }

    @Test func fallsBackToInProgressWhenNothingUpcoming() {
        // With only an in-progress event and nothing after it, show that event.
        let events = [ev("now", startOffset: -300, duration: 1800)]
        #expect(MeetingSelection.currentOrNext(from: events, now: base)?.id == "now")
    }

    @Test func empty() {
        #expect(MeetingSelection.currentOrNext(from: [], now: base) == nil)
    }

    @Test func excludesAllDayFromMenuBarSelection() {
        let allDay = MeetingEvent(id: "ad", title: "Holiday", start: base.addingTimeInterval(-1000),
                                  end: base.addingTimeInterval(80000), calendarID: "c", isAllDay: true)
        let timed = ev("meeting", startOffset: 600)
        // All-day is "in progress" but must be ignored; the timed meeting wins.
        #expect(MeetingSelection.currentOrNext(from: [allDay, timed], now: base)?.id == "meeting")
        // With only an all-day event, the menu bar shows nothing.
        #expect(MeetingSelection.currentOrNext(from: [allDay], now: base) == nil)
    }

    @Test func windowFiltering() {
        let window = DateInterval(start: base, duration: 3600)
        let events = [ev("in", startOffset: 600), ev("outside", startOffset: 7200), ev("overlapStart", startOffset: -300)]
        let filtered = MeetingSelection.filter(events, window: window, calendarIDs: [])
        #expect(Set(filtered.map(\.id)) == ["in", "overlapStart"])
    }

    @Test func calendarIDFiltering() {
        let window = DateInterval(start: base, duration: 3600)
        let events = [ev("keep", startOffset: 600, cal: "work"), ev("drop", startOffset: 600, cal: "personal")]
        let filtered = MeetingSelection.filter(events, window: window, calendarIDs: ["work"])
        #expect(filtered.map(\.id) == ["keep"])
    }
}

private struct StubProvider: CalendarProvider {
    let events: [MeetingEvent]
    func requestAccess() async -> Bool { true }
    func fetchEvents(window: DateInterval) async throws -> [MeetingEvent] { events }
}

@Suite @MainActor struct MeetingStoreTests {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func refreshPopulatesAndSorts() async {
        let e1 = MeetingEvent(id: "b", title: "B", start: base.addingTimeInterval(1200), end: base.addingTimeInterval(3000), calendarID: "c")
        let e2 = MeetingEvent(id: "a", title: "A", start: base.addingTimeInterval(600), end: base.addingTimeInterval(2400), calendarID: "c")
        let store = MeetingStore(provider: StubProvider(events: [e1, e2]), now: { self.base })
        let ok = await store.refresh()
        #expect(ok)
        #expect(store.upcoming.map(\.id) == ["a", "b"])
        #expect(store.currentOrNext?.id == "a")
    }

    @Test func nextJoinableSkipsLinklessMeeting() async {
        let noLink = MeetingEvent(id: "x", title: "No link", start: base.addingTimeInterval(300), end: base.addingTimeInterval(900), calendarID: "c")
        let withLink = MeetingEvent(id: "y", title: "Has link", start: base.addingTimeInterval(600),
                                    end: base.addingTimeInterval(1200), notes: "https://zoom.us/j/5", calendarID: "c")
        let store = MeetingStore(provider: StubProvider(events: [noLink, withLink]), now: { self.base })
        _ = await store.refresh()
        #expect(store.nextJoinableMeeting?.id == "y")
    }
}
