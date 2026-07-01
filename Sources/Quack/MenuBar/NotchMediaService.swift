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

    private let collapsedHeight: CGFloat = 6      // thin below-notch hover lip
    private let expandedHeight: CGFloat = 56      // room for art + controls, below the cutout
    private let expandedWidth: CGFloat = 320

    func start() {
        guard reader.currentLayout() != nil else {
            reader.onChange = { [weak self] in self?.repositionOrTeardown() }
            reader.startObserving()
            return
        }
        buildPanelIfNeeded()
        model.onHoverChange = { [weak self] h in self?.handleHover(h) }
        model.onToggle = { [weak self] in self?.nowPlaying.togglePlayPause() }
        model.onNext = { [weak self] in self?.nowPlaying.next() }
        model.onPrevious = { [weak self] in self?.nowPlaying.previous() }
        reader.onChange = { [weak self] in self?.repositionOrTeardown() }
        reader.startObserving()
        nowPlaying.start()
        cancellable = nowPlaying.$track.sink { [weak self] t in self?.model.track = t }
        reposition()
    }

    func stop() {
        reader.stopObserving()
        reader.onChange = nil
        cancellable = nil
        nowPlaying.stop()
        panel?.orderOut(nil)
        panel = nil
        model.isOpen = false
        model.track = nil
    }

    private func buildPanelIfNeeded() {
        guard panel == nil else { return }
        let p = NotchPanel(contentRect: NSRect(x: 0, y: 0, width: expandedWidth, height: collapsedHeight))
        let host = NSHostingView(rootView: NotchMediaView(model: model))
        host.frame = p.contentView!.bounds
        host.autoresizingMask = [.width, .height]
        p.contentView?.addSubview(host)
        panel = p
    }

    private func repositionOrTeardown() {
        guard reader.currentLayout() != nil else {
            panel?.orderOut(nil); model.isOpen = false; return
        }
        buildPanelIfNeeded(); reposition()
    }

    /// Positions the panel centered under the notch. Collapsed = a thin lip just
    /// below the cutout (hover target in visible screen). Expanded = the player,
    /// hanging below the notch. Cocoa (Y-up): top-anchored at the screen top.
    private func reposition() {
        guard let layout = reader.currentLayout(), let panel else { return }
        let width = model.isOpen ? expandedWidth : max(layout.span.width, 120)
        let height = model.isOpen ? expandedHeight : collapsedHeight
        let centerX = layout.cocoaNotchRect.midX
        let originX = centerX - width / 2
        let originY = layout.screen.frame.maxY - height   // hangs down from the top
        panel.setFrame(NSRect(x: originX, y: originY, width: width, height: height), display: true)
        panel.orderFrontRegardless()
    }

    private func handleHover(_ hovering: Bool) {
        model.isOpen = hovering
        reposition()
    }
}
