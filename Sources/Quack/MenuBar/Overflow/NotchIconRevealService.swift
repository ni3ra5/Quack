import AppKit
import SwiftUI
import Combine
import QuackKit

/// Wires the notch reveal feature together: owns the always-present panel at the
/// notch, positions it on the built-in screen, and on hover runs an on-demand
/// scan → mirror → render, forwarding taps to the real hidden items.
///
/// Lifecycle follows `TemperatureStatusItem`: the panel is created once and
/// shown/hidden via `orderFront`/`orderOut` rather than recreated. No event tap
/// is installed (hover is SwiftUI `.onHover`), so the CLAUDE.md freeze rules do
/// not apply; the only Accessibility dependency is the click-forward, which
/// simply no-ops when AX is not granted.
@MainActor
final class NotchIconRevealService: NSObject, ManagedService {
    private let settings: SettingsStore
    private let permissions: PermissionsManager

    private let reader = NotchScreenReader()
    private let model = NotchViewModel()
    private var panel: NotchPanel?

    /// Collapsed panel height (bare hover sliver at the notch height ~ menu bar).
    private let collapsedHeight: CGFloat = 24
    /// Expanded panel height (room for a row of mirrored icons below the notch).
    private let expandedHeight: CGFloat = 40

    init(settings: SettingsStore, permissions: PermissionsManager) {
        self.settings = settings
        self.permissions = permissions
        super.init()
    }

    func start() {
        guard reader.currentLayout() != nil else {
            // No built-in notch → feature inert; still observe in case a notched
            // screen is (re)connected while enabled.
            reader.onChange = { [weak self] in self?.repositionOrTeardown() }
            reader.startObserving()
            return
        }
        buildPanelIfNeeded()
        model.onHoverChange = { [weak self] hovering in self?.handleHover(hovering) }
        model.onTap = { [weak self] item in self?.handleTap(item) }
        reader.onChange = { [weak self] in self?.repositionOrTeardown() }
        reader.startObserving()
        reposition()
    }

    func stop() {
        reader.stopObserving()
        reader.onChange = nil
        panel?.orderOut(nil)
        panel = nil
        model.isOpen = false
        model.items = []
    }

    // MARK: - Panel lifecycle

    private func buildPanelIfNeeded() {
        guard panel == nil else { return }
        let p = NotchPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: collapsedHeight))
        let host = NSHostingView(rootView: NotchRevealView(model: model))
        host.frame = p.contentView!.bounds
        host.autoresizingMask = [.width, .height]
        p.contentView?.addSubview(host)
        panel = p
    }

    /// Re-place the panel at the current notch, or tear down if the built-in
    /// notch went away (e.g. clamshell / display change).
    private func repositionOrTeardown() {
        guard reader.currentLayout() != nil else {
            panel?.orderOut(nil)
            model.isOpen = false
            return
        }
        buildPanelIfNeeded()
        reposition()
    }

    /// Positions the panel centered on the notch, its top flush with the screen
    /// top. Width grows when open so a row of icons has room; stays notch-width
    /// when collapsed. Cocoa (Y-up) coordinates.
    private func reposition() {
        guard let layout = reader.currentLayout(), let panel else { return }
        let width = model.isOpen ? max(layout.span.width, contentWidth()) : layout.span.width
        let height = model.isOpen ? expandedHeight : collapsedHeight
        let centerX = layout.cocoaNotchRect.midX
        let originX = centerX - width / 2
        let originY = layout.screen.frame.maxY - height   // top-anchored
        panel.setFrame(NSRect(x: originX, y: originY, width: width, height: height), display: true)
        panel.orderFrontRegardless()
    }

    private func contentWidth() -> CGFloat {
        // ~28pt per icon (18pt image + spacing) plus horizontal padding.
        CGFloat(model.items.count) * 28 + 32
    }

    // MARK: - Interaction

    private func handleHover(_ hovering: Bool) {
        if hovering {
            // Refresh permissions non-invasively; prompt for Screen Recording
            // once if missing (the pixel mirror needs it).
            permissions.refreshScreenRecording()
            if permissions.status(for: .screenRecording) != .granted {
                _ = permissions.requestScreenRecording()
            }
            model.items = scanAndMirror()
            model.isOpen = true
        } else {
            model.isOpen = false
            model.items = []
        }
        reposition()
    }

    private func scanAndMirror() -> [NotchItem] {
        guard let layout = reader.currentLayout() else { return [] }
        let xRange = layout.screen.frame.minX...layout.screen.frame.maxX
        let crushed = StatusItemScanner.scan(notch: layout.span, screenXRange: xRange)
        return crushed.compactMap { item in
            guard let image = StatusItemMirror.snapshot(of: item) else { return nil }
            return NotchItem(id: item.windowID, image: image, source: item)
        }
    }

    private func handleTap(_ item: StatusItemFrame) {
        guard permissions.status(for: .accessibility) == .granted else {
            permissions.requestAccessibilityAccess()
            return
        }
        StatusItemForwarder.forward(to: item)
    }
}
