import AppKit
import Combine
import QuackKit
import MediaRemoteAdapter

/// Observable state for the unified notch panel: agent snapshots on top,
/// media strip at the bottom. Replaces NotchMediaViewModel.
@MainActor
final class NotchContentViewModel: ObservableObject {
    @Published var isOpen = false
    @Published var agents: [AgentSnapshot] = []
    @Published var tokensTodayText: String?
    @Published var track: TrackInfo?
    @Published var mediaEnabled = false
    @Published var agentsEnabled = false
    @Published var integrationInstalled = false
    /// Real notch height for this screen; view pads content below the cutout.
    @Published var contentTopInset: CGFloat = 0

    var onHoverChange: ((Bool) -> Void)?
    var onToggle: (() -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onAgentTap: ((AgentSnapshot) -> Void)?

    var needsYouCount: Int { agents.filter { $0.status == .needsYou }.count }
    var activeCount: Int { agents.filter { $0.status != .idle }.count }
    /// Ambient peek shows only when the agents zone is on and something is live.
    var showsPeek: Bool { agentsEnabled && activeCount > 0 }
}
