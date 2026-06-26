import Foundation

/// Formats the menu-bar title from the current/next meeting.
public enum CountdownFormatter {

    public static let maxTitleLength = 22

    /// The menu-bar title string. Returns `nil` when there is no meeting (the
    /// caller then shows a neutral glyph).
    ///
    /// - in progress: `"<title> · now"`
    /// - < 60 min:     `"<title> · in 5m"`
    /// - >= 60 min:    `"<title> · in 2h"` / `"in 2h 15m"`
    public static func menuBarTitle(for meeting: MeetingEvent?, now: Date) -> String? {
        guard let meeting else { return nil }
        let title = truncate(meeting.title)
        if meeting.isInProgress(at: now) {
            return "\(title) · now"
        }
        let remaining = meeting.start.timeIntervalSince(now)
        guard remaining > 0 else { return "\(title) · now" }
        return "\(title) · in \(relative(remaining))"
    }

    /// A short relative-duration string at minute granularity (never seconds):
    /// "1m", "5m", "2h", "2h 15m". Anything under a minute reads as "1m".
    public static func relative(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int(seconds / 60))   // floor, but never below 1m or seconds
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remMinutes = minutes % 60
        return remMinutes == 0 ? "\(hours)h" : "\(hours)h \(remMinutes)m"
    }

    public static func truncate(_ title: String, limit: Int = maxTitleLength) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        let endIndex = trimmed.index(trimmed.startIndex, offsetBy: limit - 1)
        return String(trimmed[..<endIndex]) + "…"
    }
}
