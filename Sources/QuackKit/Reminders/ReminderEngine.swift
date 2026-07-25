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
            /// Advance heads-up, labelled with the REAL minutes remaining
            /// (rounded up, never below 1) — not the configured lead, so a
            /// catch-up fired late reads correctly.
            case advance(minutesRemaining: Int)
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
    /// - An advance reminder fires once its lead instant has passed while the
    ///   meeting is still upcoming — with NO upper bound, so it survives
    ///   throttled timers (App Nap), sleeps, and launches. Several leads that
    ///   elapsed together collapse into one toast labelled with the real
    ///   minutes remaining.
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
        let leads = normalizedLeads(leads)
        var result: [Due] = []
        for m in meetings where !m.isAllDay {
            let passed = leads.filter { lead in
                let fire = m.start.addingTimeInterval(-Double(lead) * 60)
                return now >= fire && now < m.start && !fired.contains(leadKey(m, lead))
            }
            if !passed.isEmpty {
                let minutes = max(1, Int((m.start.timeIntervalSince(now) / 60).rounded(.up)))
                result.append(Due(meeting: m, kind: .advance(minutesRemaining: minutes),
                                  keys: passed.map { leadKey(m, $0) }))
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
