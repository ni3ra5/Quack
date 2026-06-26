import AppKit
import SwiftUI
import Combine
import QuackKit

/// Owns a real `NSStatusItem` instead of SwiftUI's `MenuBarExtra`, which
/// intermittently fails to register its menu-bar item. The duck is a template
/// image (adapts to the menu bar), the countdown is the button title, and the
/// dropdown is `MenuContentView` shown in a popover.
@MainActor
final class StatusItemController {
    private let env: AppEnvironment
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var cancellable: AnyCancellable?
    private var titleTimer: Timer?

    init(env: AppEnvironment) {
        self.env = env
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = Self.duckImage()
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(togglePopover)
            button.setAccessibilityLabel("Quack")
        }

        popover.behavior = .transient
        popover.animates = false
        let host = NSHostingController(rootView: MenuContentView().environmentObject(env))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host

        // Keep the countdown title fresh as the clock/meetings change…
        cancellable = env.objectWillChange
            .sink { [weak self] _ in DispatchQueue.main.async { self?.updateTitle() } }
        // …plus a dedicated timer so the title can't go stale even if the
        // Combine forwarding misses a beat (recomputes from current data).
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateTitle() }
        }
        RunLoop.main.add(timer, forMode: .common)
        titleTimer = timer
        updateTitle()
    }

    private func updateTitle() {
        guard let button = statusItem.button else { return }
        let s = env.settingsStore.settings
        let meeting = MeetingSelection.currentOrNext(from: env.meetingStore.upcoming, now: env.now)
        if s.menuBarCountdownEnabled, let title = CountdownFormatter.menuBarTitle(for: meeting, now: env.now) {
            button.title = " \(title)"
        } else {
            button.title = ""
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            env.refreshCalendarNow()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    /// The duck glyph as a template image (AppKit-drawn — reliable, unlike
    /// ImageRenderer on a SwiftUI Canvas, which produced a blank image).
    private static func duckImage() -> NSImage {
        DuckImage.template(height: 17)
    }
}
