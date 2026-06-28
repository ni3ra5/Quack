import AppKit
import SwiftUI
import Combine
import QuackKit
import CSMC

/// A separate menu-bar status item showing CPU temperature with a flame icon
/// (à la the `hot` app). Reads the SMC via `CSMC`, polls on a background queue,
/// and tints orange/red as the chip heats up. Clicking it opens a popover with
/// thermal pressure, temperature, and a Settings action. Opt-in.
@MainActor
final class TemperatureStatusItem: NSObject, ManagedService {
    private let settings: SettingsStore
    /// Set by AppEnvironment after construction (opens the Settings window).
    var onOpenSettings: (() -> Void)?

    private var statusItem: NSStatusItem?
    private var timer: Timer?
    private var cancellable: AnyCancellable?
    private var lastTempC: Double = -1

    private let model = TemperatureModel()
    private let popover = NSPopover()

    init(settings: SettingsStore) {
        self.settings = settings
        super.init()
    }

    func start() {
        // Create the status item once and reuse it. Toggling the feature flips
        // `isVisible` instead of removing/re-adding the item — repeatedly
        // removing and recreating status items corrupts the menu-bar layout and
        // can drop *other* apps'/our own items (that's what made the duck vanish).
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.autosaveName = "quack.temperature"
            if let button = item.button {
                let cfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
                let flame = NSImage(systemSymbolName: "flame.fill", accessibilityDescription: "CPU temperature")?
                    .withSymbolConfiguration(cfg)
                flame?.isTemplate = true
                button.image = flame
                button.imagePosition = .imageLeading
                button.imageHugsTitle = true   // minimal gap between flame and value
                button.target = self
                button.action = #selector(togglePopover)
            }
            popover.behavior = .transient
            popover.animates = false
            popover.contentViewController = NSHostingController(
                rootView: TemperaturePopover(model: model) { [weak self] in self?.openSettings() }
            )
            statusItem = item
        }
        statusItem?.isVisible = true

        // Re-render immediately when the unit toggle changes.
        cancellable = settings.objectWillChange
            .sink { [weak self] _ in DispatchQueue.main.async { self?.render() } }

        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    func stop() {
        timer?.invalidate(); timer = nil
        cancellable = nil
        if popover.isShown { popover.performClose(nil) }
        statusItem?.isVisible = false   // hide, don't remove (keeps the layout stable)
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func openSettings() {
        popover.performClose(nil)
        onOpenSettings?()
    }

    /// Reads the SMC off the main thread (the first read enumerates keys), then
    /// updates the button on the main actor.
    private func refresh() {
        DispatchQueue.global(qos: .utility).async {
            let c = csmc_cpu_temperature()
            DispatchQueue.main.async { [weak self] in
                self?.lastTempC = c
                self?.render()
            }
        }
    }

    private func render() {
        // Keep the popover model in sync.
        model.tempC = lastTempC
        model.fahrenheit = settings.settings.temperatureFahrenheit
        model.thermalState = ProcessInfo.processInfo.thermalState

        guard let button = statusItem?.button else { return }
        // Always use the default adaptive menu-bar color (a fixed attributed
        // color flickered between tinted and black/white against the menu bar).
        button.contentTintColor = nil
        // Leading space sets the gap between the flame and the value.
        if lastTempC > 0 {
            let fahrenheit = settings.settings.temperatureFahrenheit
            let value = fahrenheit ? lastTempC * 9 / 5 + 32 : lastTempC
            button.title = " \(Int(value.rounded()))°"
        } else {
            button.title = " --"
        }
        tightenWidth(button)
    }

    /// `variableLength` adds generous system side-insets. Pin the item to the
    /// content width (image + a small gap + text) with only a little padding.
    private func tightenWidth(_ button: NSStatusBarButton) {
        let font = button.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let textWidth = (button.title as NSString).size(withAttributes: [.font: font]).width
        let imageWidth = button.image?.size.width ?? 0
        // imageWidth + textWidth already covers the flame, gap, and value; the
        // small extra is just the side padding — keep it minimal.
        statusItem?.length = ceil(imageWidth + textWidth + 4)
    }
}
