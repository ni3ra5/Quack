import Foundation

/// One scheduled reminder: which meeting, how many minutes before start, the
/// fire date, and a stable identifier for idempotent (re)scheduling.
public struct PlannedReminder: Equatable, Hashable, Sendable {
    public let meetingID: String
    public let leadMinutes: Int
    public let fireDate: Date
    public let title: String
    public let joinURL: URL?

    public var identifier: String { "\(meetingID)-\(leadMinutes)" }

    public init(meetingID: String, leadMinutes: Int, fireDate: Date, title: String, joinURL: URL?) {
        self.meetingID = meetingID
        self.leadMinutes = leadMinutes
        self.fireDate = fireDate
        self.title = title
        self.joinURL = joinURL
    }
}

/// Pure planner: turns meetings + lead times into the set of reminders that
/// should currently be scheduled. The app layer diffs this against what is
/// already pending and adds/removes the difference.
public enum ReminderPlan {

    /// Builds reminders for every (meeting, leadMinutes) whose fire date is
    /// still in the future relative to `now`. Reminders in the past are skipped.
    public static func reminders(
        for meetings: [MeetingEvent],
        leadMinutes: [Int],
        now: Date
    ) -> [PlannedReminder] {
        var result: [PlannedReminder] = []
        let leads = Set(leadMinutes.filter { $0 >= 0 }).sorted()
        for meeting in meetings {
            for lead in leads {
                let fire = meeting.start.addingTimeInterval(-Double(lead) * 60)
                guard fire > now else { continue }
                result.append(
                    PlannedReminder(
                        meetingID: meeting.id,
                        leadMinutes: lead,
                        fireDate: fire,
                        title: meeting.title,
                        joinURL: MeetingURLParser.joinURL(for: meeting)
                    )
                )
            }
        }
        return result.sorted { $0.fireDate < $1.fireDate }
    }

    /// Given the identifiers currently pending and the freshly planned set,
    /// returns which identifiers to remove and which reminders to add.
    public static func diff(
        pending: Set<String>,
        planned: [PlannedReminder]
    ) -> (toRemove: Set<String>, toAdd: [PlannedReminder]) {
        let plannedIDs = Set(planned.map(\.identifier))
        let toRemove = pending.subtracting(plannedIDs)
        let toAdd = planned.filter { !pending.contains($0.identifier) }
        return (toRemove, toAdd)
    }
}
