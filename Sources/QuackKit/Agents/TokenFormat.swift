import Foundation

/// Compact token counts for the header pill: 215_400 -> "215k", 1_500_000 -> "1.5M".
public enum TokenFormat {
    public static func compact(_ tokens: Int) -> String {
        switch tokens {
        case ..<1000:
            return "\(tokens)"
        case ..<1_000_000:
            return "\(Int((Double(tokens) / 1000).rounded()))k"
        default:
            let m = Double(tokens) / 1_000_000
            return m >= 10 ? "\(Int(m.rounded()))M" : String(format: "%.1fM", m)
        }
    }
}
