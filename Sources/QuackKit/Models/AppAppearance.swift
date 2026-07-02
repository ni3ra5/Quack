import Foundation

/// The user's chosen UI appearance. `system` follows the macOS setting and
/// switches live with it; `light`/`dark` pin the app to one mode. Persisted as
/// its `rawValue` string in `QuackSettings.appearance`. The AppKit mapping to an
/// `NSAppearance` lives in the app layer (see `AppEnvironment.applyAppearance`).
public enum AppAppearance: String, CaseIterable, Sendable, Identifiable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    /// Human label for the settings picker.
    public var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// SF Symbol shown beside each option.
    public var iconName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    /// Parse a persisted raw value, falling back to `.system`.
    public static func from(_ raw: String) -> AppAppearance {
        AppAppearance(rawValue: raw) ?? .system
    }
}
