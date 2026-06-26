import Foundation
import EventKit
import AppKit
import QuackKit

/// "#RRGGBB" for an `NSColor`, converting to sRGB first.
private func hexString(from color: NSColor) -> String? {
    guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
    let r = Int((rgb.redComponent * 255).rounded())
    let g = Int((rgb.greenComponent * 255).rounded())
    let b = Int((rgb.blueComponent * 255).rounded())
    return String(format: "#%02X%02X%02X", r, g, b)
}

/// A single calendar within an account, for the settings UI.
struct CalendarInfo: Identifiable, Hashable {
    let id: String
    let title: String
}

/// An account (EKSource) and the calendars it provides.
struct CalendarAccountInfo: Identifiable, Hashable {
    let id: String
    let title: String
    let calendars: [CalendarInfo]
}

/// Reads events from the system calendar database via EventKit. This already
/// aggregates Google / Exchange / iCloud accounts the user added to macOS,
/// covering most "calendar sync" needs without any third-party API.
final class EventKitProvider: CalendarProvider, @unchecked Sendable {
    private let permissions: PermissionsManager

    init(permissions: PermissionsManager) {
        self.permissions = permissions
    }

    func requestAccess() async -> Bool {
        await permissions.requestCalendarAccess()
    }

    func fetchEvents(window: DateInterval) async throws -> [MeetingEvent] {
        // Only proceed if we currently have access; never trigger a prompt here.
        guard hasAccess else { return [] }

        // Use a FRESH EKEventStore each fetch. A long-lived store keeps returning
        // stale data even after reset() — which is why the only thing that fixed
        // a changed meeting was relaunching the app (a new store). A new store
        // reads the current calendar database, just like a fresh launch does.
        let store = EKEventStore()
        store.refreshSourcesIfNecessary()   // pull remote (Google/iCloud) edits

        let calendars = store.calendars(for: .event)
        let predicate = store.predicateForEvents(
            withStart: window.start,
            end: window.end,
            calendars: calendars.isEmpty ? nil : calendars
        )
        let ekEvents = store.events(matching: predicate)
        return ekEvents.compactMap { Self.map($0) }
    }

    /// All event calendars, for the settings picker.
    func availableCalendars() -> [(id: String, title: String)] {
        guard hasAccess else { return [] }
        return EKEventStore().calendars(for: .event).map { ($0.calendarIdentifier, $0.title) }
    }

    /// Calendars grouped by account (EKSource) for the settings UI.
    func availableAccounts() -> [CalendarAccountInfo] {
        guard hasAccess else { return [] }
        let store = EKEventStore()
        store.refreshSourcesIfNecessary()
        let grouped = Dictionary(grouping: store.calendars(for: .event)) {
            $0.source?.sourceIdentifier ?? "unknown"
        }
        return grouped.map { sourceID, calendars in
            CalendarAccountInfo(
                id: sourceID,
                title: calendars.first?.source?.title ?? "Account",
                calendars: calendars
                    .map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title) }
                    .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            )
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Reads access directly from EventKit (nonisolated), avoiding a hop to the
    /// main-actor `PermissionsManager` from background fetches.
    private var hasAccess: Bool {
        let raw = Int(EKEventStore.authorizationStatus(for: .event).rawValue)
        return PermissionStatusMapper.calendar(fromEventKitRawValue: raw) == .granted
    }

    private static func map(_ event: EKEvent) -> MeetingEvent? {
        guard let start = event.startDate, let end = event.endDate else { return nil }
        // EKEvent.eventIdentifier can be nil for some detached occurrences; fall
        // back to a composite key so reminders stay stable.
        let id = event.eventIdentifier ?? "\(event.calendarItemIdentifier)-\(start.timeIntervalSince1970)"
        return MeetingEvent(
            id: id,
            title: event.title ?? "(No title)",
            start: start,
            end: end,
            location: event.location,
            notes: event.notes,
            conferencingURL: nil,    // filled by MeetingURLParser in MeetingStore
            calendarID: event.calendar?.calendarIdentifier ?? "",
            isAllDay: event.isAllDay,
            calendarColorHex: event.calendar?.color.flatMap(hexString(from:))
        )
    }
}
