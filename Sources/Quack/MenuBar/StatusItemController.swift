import AppKit
import SwiftUI
import Combine
import QuackKit

/// Owns the menu-bar items: a **duck** item (icon only) and a separate
/// **countdown** item (a 3px rounded calendar-colored bar + the meeting
/// countdown). Both open the same dropdown popover. The CPU-temperature item is
/// a separate controller; this keeps each piece as its own menu-bar element.
@MainActor
final class StatusItemController {
    private let env: AppEnvironment
    private let duckItem: NSStatusItem
    private let countdownItem: NSStatusItem
    private let popover = NSPopover()
    private var cancellable: AnyCancellable?
    private var titleTimer: Timer?

    private let countdownModel = MenuBarCountdownModel()
    private var countdownHost: NSHostingView<MenuBarCountdownView>!

    init(env: AppEnvironment) {
        self.env = env
        countdownItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        duckItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Stable names so the user's ⌘-drag arrangement persists. (macOS controls
        // the actual order; an app can't force absolute position.)
        countdownItem.autosaveName = "quack.countdown"
        duckItem.autosaveName = "quack.duck"

        let host = NSHostingView(rootView: MenuBarCountdownView(model: countdownModel))
        countdownHost = host
        if let button = countdownItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.addSubview(host)
            button.setAccessibilityLabel("Next meeting")
        }

        if let button = duckItem.button {
            button.image = Self.duckImage()
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(openSettings)
            button.setAccessibilityLabel("Quack settings")
        }

        popover.behavior = .transient
        popover.animates = false
        let content = NSHostingController(rootView: MenuContentView().environmentObject(env))
        content.sizingOptions = [.preferredContentSize]
        popover.contentViewController = content

        // Keep the countdown fresh as the clock/meetings change…
        cancellable = env.objectWillChange
            .sink { [weak self] _ in DispatchQueue.main.async { self?.updateCountdown() } }
        // …plus a steady timer so it can't go stale.
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateCountdown() }
        }
        RunLoop.main.add(timer, forMode: .common)
        titleTimer = timer
        updateCountdown()
    }

    private func updateCountdown() {
        let s = env.settingsStore.settings
        duckItem.isVisible = !s.hideDuckIcon
        let meeting = MeetingSelection.currentOrNext(from: env.meetingStore.upcoming, now: env.now)

        guard s.menuBarCountdownEnabled,
              let title = CountdownFormatter.menuBarTitle(for: meeting, now: env.now) else {
            countdownItem.isVisible = false
            return
        }
        countdownModel.text = title
        countdownModel.colorHex = meeting?.calendarColorHex
        countdownItem.isVisible = true

        // Size the item to the hosted view.
        countdownHost.layoutSubtreeIfNeeded()
        let width = countdownHost.fittingSize.width
        countdownItem.length = width
        countdownHost.frame = NSRect(x: 0, y: 0, width: width, height: NSStatusBar.system.thickness)
    }

    @objc private func openSettings() {
        env.showSettings()
    }

    @objc private func togglePopover(_ sender: Any?) {
        let button = (sender as? NSStatusBarButton) ?? duckItem.button
        guard let button else { return }
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
        DuckImage.template(height: 11)
    }
}

final class MenuBarCountdownModel: ObservableObject {
    @Published var text: String = ""
    @Published var colorHex: String?
}

/// The countdown menu-bar element: a 3px rounded calendar-colored left bar
/// followed by the meeting countdown text.
struct MenuBarCountdownView: View {
    @ObservedObject var model: MenuBarCountdownModel

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(Color.white)
                .frame(width: 3, height: 15)
            Text(model.text)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 5)
        .fixedSize()
        .allowsHitTesting(false)   // let the status button receive the click
    }
}
