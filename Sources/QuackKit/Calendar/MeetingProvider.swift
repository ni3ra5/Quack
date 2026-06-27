import Foundation

/// The video-conferencing provider a join link points at, used to label the
/// toast's join button ("Join Google Meet", "Join Zoom", …).
public enum MeetingProvider: String, Sendable, Equatable {
    case googleMeet, zoom, teams, webex, generic

    public init(url: URL?) {
        guard let s = url?.absoluteString.lowercased() else { self = .generic; return }
        if s.contains("meet.google.com") {
            self = .googleMeet
        } else if s.contains("zoom.us") {
            self = .zoom
        } else if s.contains("teams.microsoft.com") || s.contains("teams.live.com") {
            self = .teams
        } else if s.contains("webex.com") {
            self = .webex
        } else {
            self = .generic
        }
    }

    /// Human name of the provider.
    public var displayName: String {
        switch self {
        case .googleMeet: return "Google Meet"
        case .zoom: return "Zoom"
        case .teams: return "Microsoft Teams"
        case .webex: return "Webex"
        case .generic: return "Meeting"
        }
    }

    /// Label for the join button — provider-specific when known.
    public var joinLabel: String {
        self == .generic ? "Join" : "Join \(displayName)"
    }
}
