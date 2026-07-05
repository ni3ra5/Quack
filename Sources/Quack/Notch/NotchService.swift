import AppKit
import SwiftUI
import Combine
import QuackKit

/// Owns THE one notch panel and aggregates both content sources: now-playing
/// media and Claude agent snapshots. Replaces NotchMediaService — the notch is
/// a single physical spot, so a single service must own the panel, its hover
/// state, and its geometry. Zones start/stop with their settings flags.
/// Same geometry rule as before: panel top anchored at cocoaNotchRect.minY,
/// content hangs DOWN, never behind the physical cutout.
@MainActor
final class NotchService: NSObject, ManagedService {
    private let settings: SettingsStore
    private let reader = NotchScreenReader()
    private let model = NotchContentViewModel()
    private let nowPlaying = NowPlayingService()
    private let agentsService: ClaudeAgentsService
    private var panel: NotchPanel?
    private var cancellables: Set<AnyCancellable> = []
    private var wired = false
    private var mediaRunning = false
    private var agentsRunning = false

    private let hoverMargin: CGFloat = 24
    private let expandedWidth: CGFloat = 420
    private let mediaOnlyContentHeight: CGFloat = 58

    init(settings: SettingsStore, installer: ClaudeConfigInstaller) {
        self.settings = settings
        self.agentsService = ClaudeAgentsService(installer: installer)
    }

    func start() {
        reader.onChange = { [weak self] in self?.repositionOrTeardown() }
        reader.startObserving()
        applyZoneFlags()
        guard reader.currentLayout() != nil else { return }
        buildPanelIfNeeded()
        wireIfNeeded()
        reposition()
    }

    func stop() {
        reader.stopObserving()
        reader.onChange = nil
        cancellables.removeAll()
        wired = false
        if mediaRunning { nowPlaying.stop(); mediaRunning = false }
        if agentsRunning { agentsService.stop(); agentsRunning = false }
        panel?.orderOut(nil)
        panel = nil
        model.isOpen = false
        model.track = nil
        model.agents = []
    }

    private func wireIfNeeded() {
        guard !wired else { return }
        wired = true
        model.onHoverChange = { [weak self] h in self?.handleHover(h) }
        model.onToggle = { [weak self] in self?.nowPlaying.togglePlayPause() }
        model.onNext = { [weak self] in self?.nowPlaying.next() }
        model.onPrevious = { [weak self] in self?.nowPlaying.previous() }
        model.onAgentTap = { [weak self] agent in self?.focusAgent(agent) }

        nowPlaying.$track
            .sink { [weak self] t in self?.model.track = t }
            .store(in: &cancellables)
        agentsService.$agents
            .sink { [weak self] a in self?.model.agents = a; self?.repositionIfNeeded() }
            .store(in: &cancellables)
        agentsService.$integrationInstalled
            .sink { [weak self] i in self?.model.integrationInstalled = i }
            .store(in: &cancellables)
        settings.$settings
            .map { ($0.notchMediaEnabled, $0.notchAgentsEnabled) }
            .removeDuplicates(by: ==)
            .sink { [weak self] _ in self?.applyZoneFlags(); self?.repositionIfNeeded() }
            .store(in: &cancellables)
    }

    /// Starts/stops each zone's data source to match its flag. The coordinator
    /// handles the whole-feature lifecycle; this handles the per-zone one.
    private func applyZoneFlags() {
        let s = settings.settings
        model.mediaEnabled = s.notchMediaEnabled
        model.agentsEnabled = s.notchAgentsEnabled
        if s.notchMediaEnabled != mediaRunning {
            mediaRunning = s.notchMediaEnabled
            mediaRunning ? nowPlaying.start() : nowPlaying.stop()
        }
        if s.notchAgentsEnabled != agentsRunning {
            agentsRunning = s.notchAgentsEnabled
            agentsRunning ? agentsService.start() : agentsService.stop()
        }
        refreshTokensToday()
    }

    /// Optional header-pill enrichment from the third-party usage.db
    /// aggregator. Synchronous (single indexed SUM query) — acceptable on
    /// main for v1, matching this service's other sync file reads. Hides
    /// (nil) when the agents zone is off or the db is missing/unreadable.
    private func refreshTokensToday() {
        guard settings.settings.notchAgentsEnabled else {
            model.tokensTodayText = nil
            return
        }
        let dbPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/usage.db").path
        model.tokensTodayText = TokensTodayReader.todayOutputTokens(dbPath: dbPath)
            .map(TokenFormat.compact)
    }

    private func buildPanelIfNeeded() {
        guard panel == nil else { return }
        let p = NotchPanel(contentRect: NSRect(x: 0, y: 0, width: expandedWidth, height: 40))
        guard let content = p.contentView else { return }
        let host = NSHostingView(rootView: NotchContentView(model: model))
        host.frame = content.bounds
        host.autoresizingMask = [.width, .height]
        content.addSubview(host)
        panel = p
    }

    private func repositionOrTeardown() {
        guard reader.currentLayout() != nil else {
            panel?.orderOut(nil); model.isOpen = false; return
        }
        buildPanelIfNeeded()
        wireIfNeeded()
        reposition()
    }

    private func repositionIfNeeded() {
        // Card count / zone flags change the expanded height while open, and
        // the peek pill needs the panel present while closed.
        reposition()
    }

    /// Collapsed/peek: a strip hanging below the notch cutout (menu bar stays
    /// usable). Expanded: a curtain from the very top of the screen — the panel
    /// covers the menu-bar band and the cutout, and `contentTopInset` pushes
    /// the content below the physical camera housing so nothing renders
    /// behind it (CLAUDE.md geometry rule).
    private func reposition() {
        guard let layout = reader.currentLayout(), let panel else { return }
        let notchBottom = layout.cocoaNotchRect.minY
        let notchHeight = layout.cocoaNotchRect.height
        let screenTop = layout.screen.frame.maxY
        let width = model.isOpen ? expandedWidth : max(layout.cocoaNotchRect.width, 120)
        let centerX = layout.cocoaNotchRect.midX
        let originX = centerX - width / 2
        let height: CGFloat
        let originY: CGFloat
        if model.isOpen {
            height = expandedHeight() + notchHeight   // content + the covered cutout band
            originY = screenTop - height              // curtain: top edge at screen top
            model.contentTopInset = notchHeight       // content starts below the cutout
        } else {
            height = hoverMargin
            originY = notchBottom - height            // strip hangs below the notch
            model.contentTopInset = 0
        }
        panel.setFrame(NSRect(x: originX, y: originY, width: width, height: height), display: true)
        panel.orderFrontRegardless()
    }

    /// Expanded height from visible zones. Constants match the Task 9 views;
    /// tuned on hardware in Task 12.
    private func expandedHeight() -> CGFloat {
        var h: CGFloat = 10                                     // top padding
        if model.agentsEnabled {
            h += 30                                             // header row
            if !model.integrationInstalled || model.agents.isEmpty {
                h += 28                                         // CTA / empty row
            } else {
                let visible = min(model.agents.count, 3)
                h += CGFloat(visible) * 100 + CGFloat(visible - 1) * 8
            }
            h += 10                                             // zone bottom pad
        } else {
            h += mediaOnlyContentHeight - 10
        }
        if model.mediaEnabled { h += 58 }                       // pinned strip
        return min(h, 480)
    }

    private func handleHover(_ hovering: Bool) {
        model.isOpen = hovering
        if hovering { refreshTokensToday() }
        reposition()
    }

    /// Click-to-focus: activate the app hosting the agent's session; fall back
    /// to revealing the project folder when the host is gone/unknown.
    private func focusAgent(_ agent: AgentSnapshot) {
        if let pid = agent.hostPID,
           let app = NSRunningApplication(processIdentifier: pid_t(pid)),
           !app.isTerminated {
            if #available(macOS 14.0, *) {
                app.activate()
            } else {
                app.activate(options: [.activateIgnoringOtherApps])
            }
            return
        }
        Log.claude.info("focusAgent: no live host for session \(agent.sessionID, privacy: .public)")
    }
}
