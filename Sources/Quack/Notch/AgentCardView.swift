import SwiftUI
import QuackKit

/// One agent card: status dot + project + branch, one-line status message,
/// then the pill row (status / model / progress).
struct AgentCardView: View {
    let agent: AgentSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Circle().fill(dotColor).frame(width: 8, height: 8)
                Image(systemName: "asterisk")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(NotchTheme.orange)
                Text(agent.project)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NotchTheme.textPrimary).lineLimit(1)
                if let branch = agent.branch {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.branch").font(.system(size: 8))
                        Text(branch).font(.system(size: 10))
                    }
                    .foregroundStyle(NotchTheme.textMuted).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            Text(agent.statusMessage ?? " ")
                .font(.system(size: 11)).foregroundStyle(NotchTheme.textSecondary).lineLimit(1)
            HStack(spacing: 8) {
                statusPill
                if let model = agent.model { grayPill(model) }
                Spacer(minLength: 0)
                if let progress = agent.progress { progressPill(progress) }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(NotchTheme.card))
    }

    private var dotColor: Color {
        switch agent.status {
        case .needsYou: return NotchTheme.orange
        case .working: return NotchTheme.green
        case .idle: return NotchTheme.textMuted
        }
    }

    @ViewBuilder
    private var statusPill: some View {
        switch agent.status {
        case .needsYou:
            pill(icon: "exclamationmark.triangle", text: "NEEDS YOU",
                 fg: NotchTheme.orangeSoft, bg: NotchTheme.orangeSoft.opacity(0.16))
        case .working:
            pill(icon: "bolt.fill", text: "WORKING",
                 fg: NotchTheme.green, bg: NotchTheme.green.opacity(0.14))
        case .idle:
            pill(icon: nil, text: "IDLE",
                 fg: NotchTheme.textMuted, bg: Color.white.opacity(0.08))
        }
    }

    private func pill(icon: String?, text: String, fg: Color, bg: Color) -> some View {
        HStack(spacing: 3) {
            if let icon { Image(systemName: icon).font(.system(size: 7, weight: .bold)) }
            Text(text).font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Capsule().fill(bg))
    }

    private func grayPill(_ text: String) -> some View {
        Text(text).font(.system(size: 9, weight: .medium))
            .foregroundStyle(NotchTheme.textSecondary)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(Color.white.opacity(0.08)))
    }

    private func progressPill(_ progress: Double) -> some View {
        HStack(spacing: 5) {
            Capsule().fill(Color.white.opacity(0.15))
                .frame(width: 24, height: 4)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(agent.status == .needsYou ? NotchTheme.orangeSoft : NotchTheme.green)
                        .frame(width: 24 * progress)
                }
            Text("\(Int((progress * 100).rounded()))%")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(NotchTheme.textSecondary)
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Capsule().fill(Color.white.opacity(0.08)))
    }
}
