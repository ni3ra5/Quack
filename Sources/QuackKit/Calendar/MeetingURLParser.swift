import Foundation

/// Extracts a join link from a meeting. Scans, in priority order:
/// `conferencingURL` (already-known), then `location`, then `notes`.
///
/// Among links found in a single text field, a recognized provider link
/// (Zoom / Meet / Teams / Webex) wins over a generic `https://` link; if there
/// are several, the first recognized provider link wins, else the first URL.
public enum MeetingURLParser {

    /// Ordered list of provider host/path signatures we recognize.
    private static let providerSignatures: [String] = [
        "zoom.us/j/",
        "zoom.us/w/",
        "meet.google.com/",
        "teams.microsoft.com/l/meetup-join",
        "teams.microsoft.com/l/meeting",
        "teams.live.com/meet",
        "webex.com/meet",
        "webex.com/join",
    ]

    /// Matches http(s) URLs. Trailing punctuation is trimmed afterward.
    private static let urlRegex = try! NSRegularExpression(
        pattern: #"https?://[^\s<>"')\]]+"#,
        options: [.caseInsensitive]
    )

    public static func joinURL(for event: MeetingEvent) -> URL? {
        if let url = event.conferencingURL { return url }
        for field in [event.location, event.notes] {
            if let url = firstJoinURL(in: field) { return url }
        }
        return nil
    }

    /// Public for unit testing of raw-text extraction.
    public static func firstJoinURL(in text: String?) -> URL? {
        guard let text, !text.isEmpty else { return nil }
        let matches = urlMatches(in: text)
        guard !matches.isEmpty else { return nil }
        // Prefer a recognized provider link.
        for candidate in matches {
            let lower = candidate.lowercased()
            if providerSignatures.contains(where: { lower.contains($0) }) {
                return URL(string: candidate)
            }
        }
        // Otherwise, the first URL found.
        return URL(string: matches[0])
    }

    private static func urlMatches(in text: String) -> [String] {
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        return urlRegex.matches(in: text, range: range).map { match in
            trimmedTrailingPunctuation(ns.substring(with: match.range))
        }
    }

    private static func trimmedTrailingPunctuation(_ s: String) -> String {
        var end = s
        while let last = end.last, ".,;:!?)]}>\"'".contains(last) {
            end.removeLast()
        }
        return end
    }
}
