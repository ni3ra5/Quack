import Foundation

/// The macOS permissions Quack may need, one per feature group.
public enum PermissionKind: String, CaseIterable, Sendable {
    case notifications
    case calendar
    case accessibility

    public var displayName: String {
        switch self {
        case .notifications: return "Notifications"
        case .calendar: return "Calendar"
        case .accessibility: return "Accessibility"
        }
    }
}

/// Normalized permission state across the different system APIs.
public enum PermissionStatus: String, Sendable {
    case notRequested
    case granted
    case denied

    public var isGranted: Bool { self == .granted }
}

/// Maps raw system authorization integer codes to `PermissionStatus`, kept pure
/// so it can be unit tested without touching the real frameworks.
public enum PermissionStatusMapper {

    /// `EKAuthorizationStatus` raw values:
    /// 0 notDetermined, 1 restricted, 2 denied, 3 authorized (full),
    /// 4 writeOnly (macOS 14+), 5 fullAccess (macOS 14+ alias).
    public static func calendar(fromEventKitRawValue raw: Int) -> PermissionStatus {
        switch raw {
        case 3, 5: return .granted
        case 0: return .notRequested
        default: return .denied   // restricted, denied, writeOnly
        }
    }

    /// `UNAuthorizationStatus` raw values:
    /// 0 notDetermined, 1 denied, 2 authorized, 3 provisional, 4 ephemeral.
    public static func notifications(fromUNRawValue raw: Int) -> PermissionStatus {
        switch raw {
        case 2, 3, 4: return .granted
        case 0: return .notRequested
        default: return .denied
        }
    }

    /// Accessibility is a simple trusted/not-trusted boolean.
    public static func accessibility(isTrusted: Bool) -> PermissionStatus {
        isTrusted ? .granted : .notRequested
    }
}
