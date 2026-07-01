import AppKit

/// A borderless, non-activating floating panel anchored at the notch. It sits
/// above the menu bar (`.mainMenu + 3`) but never becomes key/main, so it never
/// steals focus from the app underneath. Mirrors the `ToastPresenter` panel
/// recipe, raised a few levels so notch content overlaps the menu-bar band.
final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
