import SwiftUI

extension Color {
    /// Quack's brand accent — a warm duck yellow.
    static let quackYellow = Color(red: 1.0, green: 0.78, blue: 0.05)   // ~#FFC70D
    static let quackOrange = Color(red: 0.96, green: 0.49, blue: 0.13)
}

extension Color {
    /// Parses "#RRGGBB" (or "RRGGBB"). Returns nil for malformed input.
    init?(hex: String?) {
        guard var h = hex else { return nil }
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let value = Int(h, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}
