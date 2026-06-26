import Foundation

/// A source of calendar events. EventKit and Google both conform; the UI and
/// `MeetingStore` depend only on this abstraction.
public protocol CalendarProvider: Sendable {
    /// Requests read access. Returns whether access is granted.
    func requestAccess() async -> Bool
    /// Fetches events overlapping `window`.
    func fetchEvents(window: DateInterval) async throws -> [MeetingEvent]
}
