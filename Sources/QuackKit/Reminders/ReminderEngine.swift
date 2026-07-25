import Foundation

/// Pure decision logic for meeting reminder toasts, driven by a steady poll in
/// the app layer (`ReminderScheduler`). Given the current meetings, configured
/// lead times, and which reminders have already fired, it decides what should
/// fire *now* and the soonest instant a timer should next wake.
///
/// This lives in QuackKit (not the app target) so the actual firing rules are
/// unit-tested — every reminder bug has historically hidden in this logic.
public enum ReminderEngine {

    /// A reminder that should be shown at the queried instant.
    public struct Due: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            /// Advance heads-up for a specific configured lead. Labelled by the
            /// lead (e.g. "in 10 min"), so a toast only ever shows a lead time
            /// the user actually enabled.
            case advance(lead: Int)
            /// "Join now" — the meeting is in progress.
            case start
        }
        public let meeting: MeetingEvent
        public let kind: Kind
        /// Fired-set keys to record so this reminder isn't shown again.
        public let keys: [String]

        public init(meeting: MeetingEvent, kind: Kind, keys: [String]) {
            self.meeting = meeting
            self.kind = kind
            self.keys = keys
        }
    }

    /// How long after a lead's instant a (possibly slightly delayed) reminder
    /// may still fire before it's considered stale. Bounds catch-up so a higher
    /// lead can't drift down into a lower — possibly disabled — lead's time. The
    /// App Nap opt-out keeps timers punctual, so this only needs to absorb brief
    /// coalescing / sleeps, not minutes of drift.
    public static let catchUpGrace: TimeInterval = 150

    /// Stable identifiers include the meeting's start time so a rescheduled
    /// meeting is treated as a fresh reminder rather than reusing stale fired
    /// flags. This also disambiguates recurring occurrences, which all share a
    /// single event id — without the start time only the first occurrence would
    /// ever fire.
    public static func leadKey(_ m: MeetingEvent, _ lead: Int) -> String {
        "\(m.id)-\(slot(m))-\(lead)"
    }
    public static func startKey(_ m: MeetingEvent) -> String {
        "\(m.id)-\(slot(m))-start"
    }
    private static func slot(_ m: MeetingEvent) -> Int { Int(m.start.timeIntervalSince1970) }

    /// Positive, de-duplicated leads, largest first (so a collapsed catch-up
    /// records every elapsed lead's key).
    private static func normalizedLeads(_ leads: [Int]) -> [Int] {
        Set(leads.filter { $0 > 0 }).sorted(by: >)
    }

    /// Reminders to show at `now`. All-day meetings are ignored (no countdown).
    ///
    /// - An advance reminder fires for a configured lead once its instant has
    ///   passed, within `catchUpGrace` (so a brief delay still delivers, but a
    ///   higher lead never drifts into a lower lead's time). Only the largest
    ///   in-window lead fires per check, labelled by that lead.
    /// - The "join now" reminder fires while the meeting is in progress
    ///   (`start <= now < end`), so waking or relaunching mid-meeting still
    ///   surfaces it — not only within a narrow window around the start.
    ///
    /// Idempotent: a key already in `fired` is never re-emitted.
    public static func due(
        meetings: [MeetingEvent],
        leads: [Int],
        remindAtStart: Bool,
        now: Date,
        fired: Set<String>
    ) -> [Due] {
        let leads = normalizedLeads(leads)   // largest first
        var result: [Due] = []
        for m in meetings where !m.isAllDay {
            // The largest lead currently inside its (bounded) fire window.
            if let lead = leads.first(where: { lead in
                let fire = m.start.addingTimeInterval(-Double(lead) * 60)
                return now >= fire
                    && now < fire.addingTimeInterval(catchUpGrace)
                    && now < m.start
                    && !fired.contains(leadKey(m, lead))
            }) {
                result.append(Due(meeting: m, kind: .advance(lead: lead), keys: [leadKey(m, lead)]))
            }
            if remindAtStart, now >= m.start, now < m.end, !fired.contains(startKey(m)) {
                result.append(Due(meeting: m, kind: .start, keys: [startKey(m)]))
            }
        }
        return result
    }

    /// The soonest FUTURE instant at which a reminder will need to fire, for a
    /// precise one-shot timer. Past-but-unfired instants are delivered
    /// immediately by `due`, so they are intentionally not returned here.
    public static func nextInstant(
        meetings: [MeetingEvent],
        leads: [Int],
        remindAtStart: Bool,
        now: Date,
        fired: Set<String>
    ) -> Date? {
        let leads = normalizedLeads(leads)
        var soonest: Date?
        func consider(_ d: Date) {
            guard d > now else { return }
            soonest = min(soonest ?? d, d)
        }
        for m in meetings where !m.isAllDay {
            for lead in leads where !fired.contains(leadKey(m, lead)) {
                consider(m.start.addingTimeInterval(-Double(lead) * 60))
            }
            if remindAtStart, !fired.contains(startKey(m)) { consider(m.start) }
        }
        return soonest
    }
}
