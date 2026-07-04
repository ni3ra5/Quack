import SwiftUI

/// Header row: asterisk + "N agents" left; tokens-today and needs-you pills right.
struct NotchHeaderView: View {
    @ObservedObject var model: NotchContentViewModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "asterisk")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(NotchTheme.orange)
            Text("\(model.agents.count) agent\(model.agents.count == 1 ? "" : "s")")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(NotchTheme.textPrimary)
            Spacer(minLength: 8)
            if let tokens = model.tokensTodayText {
                HStack(spacing: 3) {
                    Image(systemName: "bolt.fill").font(.system(size: 8))
                    Text("\(tokens) today").font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(NotchTheme.orangeSoft)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(NotchTheme.orangeSoft.opacity(0.14)))
            }
            if model.needsYouCount > 0 {
                HStack(spacing: 4) {
                    Circle().fill(NotchTheme.orange).frame(width: 5, height: 5)
                    Text("\(model.needsYouCount) needs you").font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(NotchTheme.orange)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().stroke(NotchTheme.orange, lineWidth: 1))
            }
        }
    }
}
