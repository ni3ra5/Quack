import Foundation

/// Formats the menu-bar title from the current/next meeting.
public enum CountdownFormatter {

    public static let maxTitleLength = 16

    /// Meetings further away than this are not shown in the menu bar.
    public static let menuBarHorizon: TimeInterval = 8 * 3600

    /// The menu-bar title string. Returns `nil` when there is no meeting, or the
    /// next one starts more than 8 hours out (the caller then shows just the duck).
    ///
    /// - in progress:  `"<title> · now"`
    /// - < 2 hours:    `"<title> · in 5m"` / `"<title> · in 1h 20m"`
    /// - 2–8 hours:    `"<title> · in 3.5hr"` (rounded to the half hour)
    public static func menuBarTitle(for meeting: MeetingEvent?, now: Date) -> String? {
        guard let meeting else { return nil }
        let title = truncate(meeting.title)
        if meeting.isInProgress(at: now) {
            return "\(title) · now"
        }
        let remaining = meeting.start.timeIntervalSince(now)
        guard remaining > 0 else { return "\(title) · now" }
        guard remaining <= menuBarHorizon else { return nil }   // > 8h: don't show
        return "\(title) · in \(menuBarRelative(remaining))"
    }

    /// Menu-bar countdown text: minute precision under 2 hours, then half-hour
    /// decimal hours ("3.5hr", "4hr") from 2 up to 8 hours.
    public static func menuBarRelative(_ seconds: TimeInterval) -> String {
        if seconds < 2 * 3600 {
            let minutes = max(1, Int(seconds / 60))
            if minutes < 60 { return "\(minutes)m" }
            let hours = minutes / 60
            let remMinutes = minutes % 60
            return remMinutes == 0 ? "\(hours)h" : "\(hours)h \(remMinutes)m"
        }
        // Round to the nearest half hour and show as a decimal.
        let halfHours = (seconds / 1800).rounded()
        let hours = halfHours / 2
        if hours == hours.rounded() { return "\(Int(hours))hr" }
        return String(format: "%.1fhr", hours)
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
