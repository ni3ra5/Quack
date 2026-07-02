import AppKit
import SwiftUI
import Combine
import QuackKit

/// Owns the below-notch media panel and wires it to NowPlayingService. Panel is
/// created once and shown/hidden (mirrors TemperatureStatusItem). Hover expands;
/// the panel hangs BELOW the notch cutout (the shelved icon-reveal's at-cutout
/// geometry was invisible/unhoverable). No event tap / run-loop source.
@MainActor
final class NotchMediaService: NSObject, ManagedService {
    private let reader = NotchScreenReader()
    private let model = NotchMediaViewModel()
    private let nowPlaying = NowPlayingService()
    private var panel: NotchPanel?
    private var cancellable: AnyCancellable?
    private var wired = false

    private let hoverMargin: CGFloat = 24         // hover strip directly below the notch
    private let contentHeight: CGFloat = 52       // room for art + text + controls
    private let expandedWidth: CGFloat = 320

    func start() {
        reader.onChange = { [weak self] in self?.repositionOrTeardown() }
        reader.startObserving()
        guard reader.currentLayout() != nil else { return }  // no notch yet; onChange will wake us
        buildPanelIfNeeded()
        wireIfNeeded()
        reposition()
    }

    func stop() {
        reader.stopObserving()
        reader.onChange = nil
        cancellable = nil
        wired = false
        nowPlaying.stop()
        panel?.orderOut(nil)
        panel = nil
        model.isOpen = false
        model.track = nil
    }

    /// Wires hover/transport callbacks and starts NowPlayingService exactly once.
    /// Called from both `start()` (notch already present) and
    /// `repositionOrTeardown()` (notch appears later) — idempotent so either
    /// caller can run first without double-wiring.
    private func wireIfNeeded() {
        guard !wired else { return }
        wired = true
        model.onHoverChange = { [weak self] h in self?.handleHover(h) }
        model.onToggle = { [weak self] in self?.nowPlaying.togglePlayPause() }
        model.onNext = { [weak self] in self?.nowPlaying.next() }
        model.onPrevious = { [weak self] in self?.nowPlaying.previous() }
        nowPlaying.start()
        cancellable = nowPlaying.$track.sink { [weak self] t in self?.model.track = t }
    }

    private func buildPanelIfNeeded() {
        guard panel == nil else { return }
        // Placeholder frame; reposition() immediately sets the real, notch-derived frame.
        let p = NotchPanel(contentRect: NSRect(x: 0, y: 0, width: expandedWidth, height: 40))
        guard let content = p.contentView else { return }
        let host = NSHostingView(rootView: NotchMediaView(model: model))
        host.frame = content.bounds
        host.autoresizingMask = [.width, .height]
        content.addSubview(host)
        panel = p
    }

    private func repositionOrTeardown() {
        guard reader.currentLayout() != nil else {
            // Notch disappeared (transient screen reconfig, e.g. monitor flicker).
            // nowPlaying is intentionally left running rather than stopped/restarted
            // here, to avoid churn if the notch reappears momentarily.
            panel?.orderOut(nil); model.isOpen = false; return
        }
        buildPanelIfNeeded()
        wireIfNeeded()
        reposition()
    }

    /// Positions the panel so its top edge is anchored at the BOTTOM of the notch
    /// (`cocoaNotchRect.minY`). The panel hangs downward from there, so content is
    /// NEVER behind the physical cutout regardless of how safeAreaInsets.top varies
    /// across models. NotchShape's flat top corners visually connect to the notch,
    /// preserving the "notch grows downward" effect.
    private func reposition() {
        guard let layout = reader.currentLayout(), let panel else { return }
        let notchBottom = layout.cocoaNotchRect.minY   // Cocoa Y-up: bottom of the notch
        let width = model.isOpen ? expandedWidth : max(layout.cocoaNotchRect.width, 120)
        let height = model.isOpen ? contentHeight : hoverMargin
        let centerX = layout.cocoaNotchRect.midX
        let originX = centerX - width / 2
        let originY = notchBottom - height             // panel hangs DOWN from notch bottom
        model.contentTopInset = 0                      // panel top IS notch bottom; 8pt padding in view
        panel.setFrame(NSRect(x: originX, y: originY, width: width, height: height), display: true)
        panel.orderFrontRegardless()
    }

    private func handleHover(_ hovering: Bool) {
        model.isOpen = hovering
        reposition()
    }
}
