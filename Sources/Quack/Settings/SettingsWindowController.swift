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
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    private func buildWindow(env: AppEnvironment) {
        let hosting = NSHostingController(rootView: SettingsRootView().environmentObject(env))
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.title = "Quack Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
    }
}
