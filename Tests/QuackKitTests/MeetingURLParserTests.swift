import Testing
import Foundation
@testable import QuackKit

@Suite struct MeetingURLParserTests {

    private func event(location: String? = nil, notes: String? = nil, url: URL? = nil) -> MeetingEvent {
        MeetingEvent(id: "1", title: "Sync", start: .init(), end: .init(),
                     location: location, notes: notes, conferencingURL: url, calendarID: "c")
    }

    @Test func zoom() {
        let u = MeetingURLParser.firstJoinURL(in: "Join: https://us02web.zoom.us/j/1234567890?pwd=abc")
        #expect(u?.absoluteString == "https://us02web.zoom.us/j/1234567890?pwd=abc")
    }

    @Test func googleMeet() {
        let u = MeetingURLParser.firstJoinURL(in: "https://meet.google.com/abc-defg-hij")
        #expect(u?.host == "meet.google.com")
    }

    @Test func teams() {
        let u = MeetingURLParser.firstJoinURL(in: "click https://teams.microsoft.com/l/meetup-join/19%3ameeting")
        #expect(u != nil)
        #expect(u!.absoluteString.contains("teams.microsoft.com/l/meetup-join"))
    }

    @Test func noURL() {
        #expect(MeetingURLParser.firstJoinURL(in: "Room 4B, 3rd floor") == nil)
        #expect(MeetingURLParser.firstJoinURL(in: nil) == nil)
        #expect(MeetingURLParser.firstJoinURL(in: "") == nil)
    }

    @Test func prefersProviderOverGenericLink() {
        let text = "Notes https://example.com/agenda and https://zoom.us/j/99 to join"
        #expect(MeetingURLParser.firstJoinURL(in: text)?.host == "zoom.us")
    }

    @Test func fallsBackToFirstGenericLink() {
        let u = MeetingURLParser.firstJoinURL(in: "see https://example.com/a and https://example.org/b")
        #expect(u?.absoluteString == "https://example.com/a")
    }

    @Test func trimsTrailingPunctuation() {
        let u = MeetingURLParser.firstJoinURL(in: "(https://zoom.us/j/12).")
        #expect(u?.absoluteString == "https://zoom.us/j/12")
    }

    @Test func fieldPriorityConferencingFirst() {
        let e = event(location: "https://zoom.us/j/1", url: URL(string: "https://meet.google.com/xyz"))
        #expect(MeetingURLParser.joinURL(for: e)?.host == "meet.google.com")
    }

    @Test func fieldPriorityLocationBeforeNotes() {
        let e = event(location: "https://zoom.us/j/1", notes: "https://meet.google.com/xyz")
        #expect(MeetingURLParser.joinURL(for: e)?.host == "zoom.us")
    }
}
