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

    // MARK: Advance — basic

    @Test func advanceFiresAtLeadInstant() {
        // Meeting 10 min out; now = exactly the 10-min mark.
        let m = ev("1", startOffset: 600)
        let result = due([m], leads: [10], at: 0)
        #expect(result.count == 1)
        #expect(result.first?.kind == .advance(lead: 10))
        #expect(result.first?.keys == [ReminderEngine.leadKey(m, 10)])
    }

    @Test func advanceNotFiredBeforeLeadInstant() {
        let m = ev("1", startOffset: 3600)   // 60 min away
        #expect(due([m], leads: [10], at: 0).isEmpty)
    }

    @Test func advanceLabelledByLeadNotRemaining() {
        // Fired a bit late (60s into the grace window) still reads "10", not 9.
        let m = ev("1", startOffset: 600)
        let result = due([m], leads: [10], at: 60)   // 9 min before start
        #expect(result.first?.kind == .advance(lead: 10))
    }

    // MARK: Advance — bounded catch-up (the reported bug)

    @Test func advanceFiresWithinGrace() {
        // A short delay (within grace) still delivers, labelled by its lead.
        let m = ev("1", startOffset: 600)
        let result = due([m], leads: [10], at: ReminderEngine.catchUpGrace - 1)
        #expect(result.first?.kind == .advance(lead: 10))
    }

    @Test func advanceDroppedBeyondGrace() {
        // The exact failure: a 10-min reminder must NOT fire once it's well past
        // its instant (here 5 min before start = 5 min late) and masquerade as a
        // "5 min" reminder.
        let m = ev("1", startOffset: 600)
        let result = due([m], leads: [10], at: 300)   // 5 min before start
        #expect(result.filter { if case .advance = $0.kind { return true }; return false }.isEmpty)
    }

    @Test func disabledLeadNeverProducesToast() {
        // leads = [10, 1] (5 is OFF). Five minutes before start: 10 is out of
        // grace, 5 isn't a lead, 1 isn't due yet → no advance toast at all.
        let m = ev("1", startOffset: 600)
        let advances = due([m], leads: [10, 1], at: 300).filter {
            if case .advance = $0.kind { return true }; return false
        }
        #expect(advances.isEmpty)
    }

    @Test func largestInWindowLeadFires() {
        // leads [10,5]; 5 min before start → 10 is stale, 5 is in-window → "5".
        let m = ev("1", startOffset: 600)
        let result = due([m], leads: [10, 5], at: 300)
        #expect(result.first?.kind == .advance(lead: 5))
    }

    @Test func advanceNotRepeatedOnceFired() {
        let m = ev("1", startOffset: 600)
        let fired: Set<String> = [ReminderEngine.leadKey(m, 10)]
        #expect(due([m], leads: [10], at: 0, fired: fired).isEmpty)
    }

    @Test func advanceNotFiredOnceStarted() {
        let m = ev("1", startOffset: -60)   // started 1 min ago
        let advances = due([m], leads: [10], at: 0).filter {
            if case .advance = $0.kind { return true }; return false
        }
        #expect(advances.isEmpty)
    }

    // MARK: Reschedule / recurring

    @Test func rescheduledMeetingReArms() {
        let moved = ev("1", startOffset: 1200)
        let firedForOldTime: Set<String> = [ReminderEngine.leadKey(ev("1", startOffset: 600), 10)]
        // New 10-min mark = start - 600 = t+600.
        let result = ReminderEngine.due(meetings: [moved], leads: [10], remindAtStart: false,
                                        now: base.addingTimeInterval(600), fired: firedForOldTime)
        #expect(result.first?.kind == .advance(lead: 10))
    }

    @Test func recurringOccurrencesFireIndependently() {
        let today = ev("daily", startOffset: 600)
        let tomorrow = ev("daily", startOffset: 600 + 86_400)
        let firedToday: Set<String> = [ReminderEngine.leadKey(today, 10)]
        let atTomorrowsMark = base.addingTimeInterval(86_400)   // 10 min before tomorrow
        let result = ReminderEngine.due(meetings: [tomorrow], leads: [10], remindAtStart: false,
                                        now: atTomorrowsMark, fired: firedToday)
        #expect(result.first?.kind == .advance(lead: 10))
        #expect(ReminderEngine.leadKey(today, 10) != ReminderEngine.leadKey(tomorrow, 10))
    }

    // MARK: Start / join-now

    @Test func startFiresWhileInProgress() {
        let m = ev("1", startOffset: -300, duration: 1800)   // started 5 min ago
        let starts = due([m], at: 0).filter { $0.kind == .start }
        #expect(starts.count == 1)
        #expect(starts.first?.keys == [ReminderEngine.startKey(m)])
    }

    @Test func startNotFiredBeforeStart() {
        let m = ev("1", startOffset: 60)
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
        let m = ev("1", startOffset: 3600)
        let next = ReminderEngine.nextInstant(meetings: [m], leads: [10, 1], remindAtStart: true,
                                              now: base, fired: [])
        #expect(next == m.start.addingTimeInterval(-600))
    }

    @Test func nextInstantSkipsFiredLeads() {
        let m = ev("1", startOffset: 3600)
        let next = ReminderEngine.nextInstant(meetings: [m], leads: [10, 1], remindAtStart: true,
                                              now: base, fired: [ReminderEngine.leadKey(m, 10)])
        #expect(next == m.start.addingTimeInterval(-60))
    }

    @Test func nextInstantNilWhenNothingUpcoming() {
        let m = ev("1", startOffset: -60)
        let next = ReminderEngine.nextInstant(meetings: [m], leads: [10, 1], remindAtStart: false,
                                              now: base, fired: [])
        #expect(next == nil)
    }
}
