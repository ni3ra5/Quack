import Testing
import Foundation
@testable import QuackKit

@Suite struct CountdownFormatterTests {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func ev(title: String, startOffset: TimeInterval, duration: TimeInterval = 1800) -> MeetingEvent {
        MeetingEvent(id: "1", title: title, start: base.addingTimeInterval(startOffset),
                     end: base.addingTimeInterval(startOffset + duration), calendarID: "c")
    }

    @Test func nilWhenNoMeeting() {
        #expect(CountdownFormatter.menuBarTitle(for: nil, now: base) == nil)
    }

    @Test func underAnHour() {
        #expect(CountdownFormatter.menuBarTitle(for: ev(title: "Standup", startOffset: 300), now: base) == "Standup · in 5m")
    }

    @Test func overAnHour() {
        #expect(CountdownFormatter.menuBarTitle(for: ev(title: "Review", startOffset: 8100), now: base) == "Review · in 2h 15m")
    }

    @Test func exactHours() {
        #expect(CountdownFormatter.menuBarTitle(for: ev(title: "Review", startOffset: 7200), now: base) == "Review · in 2h")
    }

    @Test func inProgress() {
        #expect(CountdownFormatter.menuBarTitle(for: ev(title: "Live", startOffset: -300), now: base) == "Live · now")
    }

    @Test func truncatesLongTitle() {
        let long = "Quarterly Planning and Roadmap Discussion"
        let t = CountdownFormatter.menuBarTitle(for: ev(title: long, startOffset: 300), now: base)
        #expect(t != nil)
        #expect(t!.hasSuffix("· in 5m"))
        #expect(t!.contains("…"))
    }

    @Test func relativeStringsAreMinuteGranular() {
        #expect(CountdownFormatter.relative(45) == "1m")    // sub-minute -> 1m, never seconds
        #expect(CountdownFormatter.relative(0) == "1m")
        #expect(CountdownFormatter.relative(90) == "1m")    // floor
        #expect(CountdownFormatter.relative(120) == "2m")
        #expect(CountdownFormatter.relative(3600) == "1h")
        #expect(CountdownFormatter.relative(8100) == "2h 15m")
    }
}
