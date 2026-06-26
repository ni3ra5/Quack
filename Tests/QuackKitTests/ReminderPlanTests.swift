import Testing
import Foundation
@testable import QuackKit

@Suite struct ReminderPlanTests {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func ev(_ id: String, startOffset: TimeInterval, notes: String? = nil) -> MeetingEvent {
        MeetingEvent(id: id, title: "M-\(id)", start: base.addingTimeInterval(startOffset),
                     end: base.addingTimeInterval(startOffset + 1800), notes: notes, calendarID: "c")
    }

    @Test func producesOneReminderPerLeadInFuture() {
        let plan = ReminderPlan.reminders(for: [ev("1", startOffset: 3600)], leadMinutes: [10, 5], now: base)
        #expect(plan.count == 2)
        #expect(plan.map(\.identifier).sorted() == ["1-10", "1-5"])
    }

    @Test func fireDatesAreCorrect() {
        let m = ev("1", startOffset: 3600)
        let plan = ReminderPlan.reminders(for: [m], leadMinutes: [10], now: base)
        #expect(plan.first?.fireDate == m.start.addingTimeInterval(-600))
    }

    @Test func skipsPastLeadTimes() {
        // Meeting starts in 4 minutes; a 5-minute lead is already in the past.
        let plan = ReminderPlan.reminders(for: [ev("1", startOffset: 240)], leadMinutes: [5, 1], now: base)
        #expect(plan.map(\.leadMinutes) == [1])
    }

    @Test func deduplicatesLeadTimes() {
        let plan = ReminderPlan.reminders(for: [ev("1", startOffset: 3600)], leadMinutes: [10, 10, 5], now: base)
        #expect(plan.count == 2)
    }

    @Test func carriesJoinURL() {
        let m = ev("1", startOffset: 3600, notes: "https://zoom.us/j/42")
        let plan = ReminderPlan.reminders(for: [m], leadMinutes: [5], now: base)
        #expect(plan.first?.joinURL?.host == "zoom.us")
    }

    @Test func diffAddsAndRemoves() {
        let planned = ReminderPlan.reminders(for: [ev("1", startOffset: 3600)], leadMinutes: [10, 5], now: base)
        let (toRemove, toAdd) = ReminderPlan.diff(pending: ["1-10", "stale-99"], planned: planned)
        #expect(toRemove == ["stale-99"])
        #expect(toAdd.map(\.identifier) == ["1-5"])
    }

    @Test func diffIdempotentWhenInSync() {
        let planned = ReminderPlan.reminders(for: [ev("1", startOffset: 3600)], leadMinutes: [10, 5], now: base)
        let (toRemove, toAdd) = ReminderPlan.diff(pending: Set(planned.map(\.identifier)), planned: planned)
        #expect(toRemove.isEmpty)
        #expect(toAdd.isEmpty)
    }
}
