import SwiftUI
import AppKit
import QuackKit

@main
struct QuackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Quack has no normal windows; it lives entirely in a manually-managed
        // NSStatusItem (see AppDelegate). This empty Settings scene just satisfies
        // the `App` protocol — Quack opens its own settings window.
        Settings { EmptyView() }
    }
}

/// Owns the app environment and the menu-bar status item. We manage a real
/// `NSStatusItem` here rather than a SwiftUI `MenuBarExtra` (which intermittently
/// fails to show its menu-bar icon).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var env: AppEnvironment?
    private var statusController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let env = AppEnvironment()
        self.env = env
        statusController = StatusItemController(env: env)
        env.showSettings()   // open Settings on first launch
    }

    /// Fires when the app is opened again while already running (Finder/Dock/
    /// `open`). LSUIElement apps get this instead of a fresh launch.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        env?.showSettings()
        return true
    }
}
