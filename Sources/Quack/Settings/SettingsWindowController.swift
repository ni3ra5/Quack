import AppKit
import SwiftUI

/// Owns a real `NSWindow` for settings (instead of SwiftUI's `Settings` scene,
/// whose open behavior is unreliable for an `.accessory` app). Hosts the whole
/// `SettingsRootView` (header + tabs + pane) and always comes to the front.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private weak var env: AppEnvironment?

    func show(env: AppEnvironment) {
        self.env = env
        if window == nil { buildWindow(env: env) }
        window?.center()   // open centered every time (size is fixed below)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    private func buildWindow(env: AppEnvironment) {
        let hosting = NSHostingController(rootView: SettingsRootView().environmentObject(env))
        let window = NSWindow(contentViewController: hosting)
        // Full-size content view so the dark sidebar runs up behind the traffic
        // lights, matching the two-pane layout.
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.title = "Quack Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        // Force the dark look regardless of the system theme.
        window.appearance = NSAppearance(named: .darkAqua)
        // Fix the size up front so `center()` positions it correctly (otherwise
        // it centers a pre-layout window and lands off-centre).
        window.setContentSize(NSSize(width: 760, height: 620))
        self.window = window
    }
}
