import Testing
import Foundation
@testable import QuackKit

@Suite struct ReminderEngineTests {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func ev(_ id: String, startOffset: TimeInterval, duration: TimeInterval = 1800,
                    allDay: Bool = false) -> MeetingEvent {
        MeetingEvent(id: id, title: "M-\(id)", start: base.addingTimeInterval(startOffset),
                     end: base.addingTimeInterval(startOffset + duration), calendarID: "c", isAllDay: allDay)
    }

    private func due(_ meetings: [MeetingEvent], leads: [Int] = [10, 1], remindAtStart: Bool = true,
                     at offset: TimeInterval, fired: Set<String> = []) -> [ReminderEngine.Due] {
        ReminderEngine.due(meetings: meetings, leads: leads, remindAtStart: remindAtStart,
                           now: base.addingTimeInterval(offset), fired: fired)
    }

    // MARK: Advance

    @Test func advanceFiresAtLeadInstant() {
        // Meeting at t+600s; at exactly the 10-min mark (t-600 from start = now 0)...
        let m = ev("1", startOffset: 600)
        let result = due([m], leads: [10], at: 0)   // now = start - 600s = 10 min before
        #expect(result.count == 1)
        #expect(result.first?.kind == .advance(minutesRemaining: 10))
        #expect(result.first?.keys == [ReminderEngine.leadKey(m, 10)])
    }

    @Test func advanceNotFiredBeforeLeadInstant() {
        let m = ev("1", startOffset: 3600)   // 60 min away
        #expect(due([m], leads: [10], at: 0).isEmpty)   // 10-min mark not reached
    }

    @Test func advanceCatchesUpLateWithRealMinutes() {
        // 10-min lead, but we only check when the meeting is 3 min away.
        let m = ev("1", startOffset: 180)
        let result = due([m], leads: [10], at: 0)
        #expect(result.first?.kind == .advance(minutesRemaining: 3))   // real remaining, not 10
    }

    @Test func multipleElapsedLeadsCollapseToOneToast() {
        // leads 10 and 5 both elapsed (meeting 3 min away); one toast, both keys.
        let m = ev("1", startOffset: 180)
        let result = due([m], leads: [10, 5], at: 0)
        #expect(result.count == 1)
        #expect(result.first?.kind == .advance(minutesRemaining: 3))
        #expect(Set(result.first?.keys ?? []) == [ReminderEngine.leadKey(m, 10), ReminderEngine.leadKey(m, 5)])
    }

    @Test func advanceNotRepeatedOnceFired() {
        let m = ev("1", startOffset: 600)
        let fired: Set<String> = [ReminderEngine.leadKey(m, 10)]
        #expect(due([m], leads: [10], at: 0, fired: fired).isEmpty)
    }

    @Test func advanceNotFiredOnceStarted() {
        let m = ev("1", startOffset: -60)   // started 1 min ago
        let advances = due([m], leads: [10], at: 0).filter {
            if case .advance = $0.kind { return true } else { return false }
        }
        #expect(advances.isEmpty)
    }

    @Test func minutesRemainingRoundsUpAndFloorsAtOne() {
        let m = ev("1", startOffset: 10)   // 10 seconds away
        #expect(due([m], leads: [10], at: 0).first?.kind == .advance(minutesRemaining: 1))
    }

    // MARK: Reschedule / recurring

    @Test func rescheduledMeetingReArms() {
        // Same id, moved from t+600 to t+1200. The old time's fired key must not
        // suppress the new time's reminder.
        let moved = ev("1", startOffset: 1200)
        let firedForOldTime: Set<String> = [ReminderEngine.leadKey(ev("1", startOffset: 600), 10)]
        // At the new 10-min mark (start - 600 = t+600):
        let result = ReminderEngine.due(meetings: [moved], leads: [10], remindAtStart: false,
                                        now: base.addingTimeInterval(600), fired: firedForOldTime)
        #expect(result.first?.kind == .advance(minutesRemaining: 10))
    }

    @Test func recurringOccurrencesFireIndependently() {
        // Two occurrences share one event id but differ in start.
        let today = ev("daily", startOffset: 600)
        let tomorrow = ev("daily", startOffset: 600 + 86_400)
        // Fire today's; tomorrow's key must be distinct and still unfired.
        let firedToday: Set<String> = [ReminderEngine.leadKey(today, 10)]
        let atTomorrowsMark = base.addingTimeInterval(86_400)   // 10 min before tomorrow's start
        let result = ReminderEngine.due(meetings: [tomorrow], leads: [10], remindAtStart: false,
                                        now: atTomorrowsMark, fired: firedToday)
        #expect(result.first?.kind == .advance(minutesRemaining: 10))
        #expect(ReminderEngine.leadKey(today, 10) != ReminderEngine.leadKey(tomorrow, 10))
    }

    // MARK: Start / join-now

    @Test func startFiresWhileInProgress() {
        let m = ev("1", startOffset: -300, duration: 1800)   // started 5 min ago, 30-min meeting
        let starts = due([m], at: 0).filter { $0.kind == .start }
        #expect(starts.count == 1)   // catch-up: still in progress well past the start
        #expect(starts.first?.keys == [ReminderEngine.startKey(m)])
    }

    @Test func startNotFiredBeforeStart() {
        let m = ev("1", startOffset: 60)   // starts in 1 min
        #expect(due([m], at: 0).filter { $0.kind == .start }.isEmpty)
    }

    @Test func startNotFiredAfterEnd() {
        let m = ev("1", startOffset: -3600, duration: 1800)   // ended 30 min ago
        #expect(due([m], at: 0).filter { $0.kind == .start }.isEmpty)
    }

    @Test func startSuppressedWhenRemindAtStartOff() {
        let m = ev("1", startOffset: -60)
        #expect(due([m], remindAtStart: false, at: 0).filter { $0.kind == .start }.isEmpty)
    }

    @Test func startNotRepeatedOnceFired() {
        let m = ev("1", startOffset: -60)
        let fired: Set<String> = [ReminderEngine.startKey(m)]
        #expect(due([m], at: 0, fired: fired).filter { $0.kind == .start }.isEmpty)
    }

    // MARK: General

    @Test func allDayEventsIgnored() {
        let m = ev("1", startOffset: -60, duration: 86_400, allDay: true)
        #expect(due([m], at: 0).isEmpty)
    }

    // MARK: nextInstant

    @Test func nextInstantIsSoonestFutureLead() {
        let m = ev("1", startOffset: 3600)   // 60 min away
        let next = ReminderEngine.nextInstant(meetings: [m], leads: [10, 1], remindAtStart: true,
                                              now: base, fired: [])
        #expect(next == m.start.addingTimeInterval(-600))   // the 10-min mark, soonest
    }

    @Test func nextInstantSkipsFiredLeads() {
        let m = ev("1", startOffset: 3600)
        let next = ReminderEngine.nextInstant(meetings: [m], leads: [10, 1], remindAtStart: true,
                                              now: base, fired: [ReminderEngine.leadKey(m, 10)])
        #expect(next == m.start.addingTimeInterval(-60))   // now the 1-min mark
    }

    @Test func nextInstantNilWhenNothingUpcoming() {
        let m = ev("1", startOffset: -60)   // already started, all leads past
        let next = ReminderEngine.nextInstant(meetings: [m], leads: [10, 1], remindAtStart: false,
                                              now: base, fired: [])
        #expect(next == nil)
    }
}
