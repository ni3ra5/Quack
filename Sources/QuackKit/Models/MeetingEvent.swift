import Foundation

/// A calendar event normalized across providers (EventKit, Google).
///
/// `conferencingURL` is filled in by `MeetingURLParser` when a provider does not
/// already supply a dedicated conferencing link.
public struct MeetingEvent: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let location: String?
    public let notes: String?
    public let conferencingURL: URL?
    public let calendarID: String
    public let isAllDay: Bool
    /// The owning calendar's color as "#RRGGBB", for the menu dot.
    public let calendarColorHex: String?

    public init(
        id: String,
        title: String,
        start: Date,
        end: Date,
        location: String? = nil,
        notes: String? = nil,
        conferencingURL: URL? = nil,
        calendarID: String,
        isAllDay: Bool = false,
        calendarColorHex: String? = nil
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.location = location
        self.notes = notes
        self.conferencingURL = conferencingURL
        self.calendarID = calendarID
        self.isAllDay = isAllDay
        self.calendarColorHex = calendarColorHex
    }

    /// Returns a copy with the conferencing URL replaced.
    public func withConferencingURL(_ url: URL?) -> MeetingEvent {
        MeetingEvent(
            id: id,
            title: title,
            start: start,
            end: end,
            location: location,
            notes: notes,
            conferencingURL: url,
            calendarID: calendarID,
            isAllDay: isAllDay,
            calendarColorHex: calendarColorHex
        )
    }

    /// True when `now` falls within `[start, end)`.
    public func isInProgress(at now: Date) -> Bool {
        now >= start && now < end
    }
}
