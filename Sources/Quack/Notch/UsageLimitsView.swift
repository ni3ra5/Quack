import SwiftUI
import QuackKit

/// "Claude" section: 5h and 7d rate-limit bars (green = remaining) with reset info.
struct UsageLimitsView: View {
    let usage: UsageLimits

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "asterisk").font(.system(size: 9, weight: .bold))
                Text("Claude").font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(NotchTheme.textSecondary)
            if let used = usage.fiveHourUsedPercent {
                row(label: "5h", usedPercent: used, resetsAt: usage.fiveHourResetsAt, sameDayReset: true)
            }
            if let used = usage.sevenDayUsedPercent {
                row(label: "7d", usedPercent: used, resetsAt: usage.sevenDayResetsAt, sameDayReset: false)
            }
        }
    }

    private func row(label: String, usedPercent: Double, resetsAt: Date?, sameDayReset: Bool) -> some View {
        let remaining = max(0, min(100, 100 - usedPercent))
        return HStack(spacing: 8) {
            Text(label).font(.system(size: 10)).foregroundStyle(NotchTheme.textMuted)
                .frame(width: 16, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                    Capsule().fill(NotchTheme.green)
                        .frame(width: geo.size.width * remaining / 100)
                }
            }
            .frame(width: 110, height: 5)
            Text(detail(remaining: remaining, resetsAt: resetsAt, sameDayReset: sameDayReset))
                .font(.system(size: 10)).foregroundStyle(NotchTheme.textMuted).lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private func detail(remaining: Double, resetsAt: Date?, sameDayReset: Bool) -> String {
        var text = "\(Int(remaining.rounded()))% left"
        if let resetsAt {
            let f = DateFormatter()
            f.dateFormat = sameDayReset ? "h:mm a" : "MMM d"
            text += " · resets \(f.string(from: resetsAt))"
        }
        return text
    }
}
