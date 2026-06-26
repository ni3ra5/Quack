import Foundation

/// A feature service the coordinator can start and stop. Concrete services
/// (calendar polling, reminders, cursor monitor, gesture monitor) conform; the
/// coordinator never knows their internals, only their lifecycle.
@MainActor
public protocol ManagedService: AnyObject {
    func start()
    func stop()
}

/// Which feature flag controls a given service. Used by `AppCoordinator` to
/// decide which services should be running for a settings value.
public enum Feature: CaseIterable, Sendable {
    case calendar
    case reminders
    case menuBarCountdown
    case brightness
    case windowSwipe
    case windowShortcuts

    public func isEnabled(in settings: QuackSettings) -> Bool {
        switch self {
        case .calendar: return settings.calendarEnabled
        case .reminders: return settings.remindersEnabled
        case .menuBarCountdown: return settings.menuBarCountdownEnabled
        case .brightness: return settings.brightnessEnabled
        case .windowSwipe: return settings.windowSwipeEnabled
        case .windowShortcuts: return settings.windowShortcutsEnabled
        }
    }
}
