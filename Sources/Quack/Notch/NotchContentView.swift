import SwiftUI
import QuackKit

/// The unified notch panel content and its three states:
/// expanded (hover) / peek (ambient dot) / collapsed (invisible hover target).
struct NotchContentView: View {
    @ObservedObject var model: NotchContentViewModel

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { model.onHoverChange?($0) }
    }

    @ViewBuilder
    private var content: some View {
        if model.isOpen {
            expanded
        } else if model.showsPeek {
            peek
        } else {
            Color.black.opacity(0.001)   // hover target only
        }
    }

    private var expanded: some View {
        VStack(spacing: 0) {
            if model.agentsEnabled {
                VStack(alignment: .leading, spacing: 10) {
                    NotchHeaderView(model: model)
                    if let usage = model.usage { UsageLimitsView(usage: usage) }
                    agentsZone
                }
                .padding(.horizontal, 14)
                .padding(.top, model.contentTopInset + 10)
                .padding(.bottom, 10)
            } else {
                Spacer().frame(height: model.contentTopInset + 6)
            }
            Spacer(minLength: 0)
            if model.mediaEnabled {
                MediaStripView(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(NotchTheme.panel)
        .clipShape(NotchShape())
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var agentsZone: some View {
        if !model.integrationInstalled {
            HStack(spacing: 6) {
                Image(systemName: "asterisk").font(.system(size: 10, weight: .bold))
                    .foregroundStyle(NotchTheme.orange)
                Text("Enable Claude integration in Quack Settings")
                    .font(.system(size: 11)).foregroundStyle(NotchTheme.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if model.agents.isEmpty {
            Text("No active agents")
                .font(.system(size: 11)).foregroundStyle(NotchTheme.textMuted)
        } else if model.agents.count > 3 {
            ScrollView(showsIndicators: false) { cards }
                .frame(maxHeight: 3 * 92 + 2 * 8)
        } else {
            cards
        }
    }

    private var cards: some View {
        VStack(spacing: 8) {
            ForEach(model.agents) { AgentCardView(agent: $0) }
        }
    }

    private var peek: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                Circle()
                    .fill(model.needsYouCount > 0 ? NotchTheme.orange : NotchTheme.green)
                    .frame(width: 6, height: 6)
                Text("\(model.activeCount)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.black))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
