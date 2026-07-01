import AppKit
import CoreGraphics
import QuackKit

/// The current notch layout of the built-in display: the screen, the pure
/// horizontal span, and the notch rect in Cocoa (Y-up) coordinates for panel
/// positioning. `cocoaNotchRect` spans the notch width, from the top of the
/// screen down by the safe-area inset (the notch height).
struct NotchLayout {
    let screen: NSScreen
    let span: NotchGeometry.NotchSpan
    let cocoaNotchRect: CGRect
}

/// Reads the built-in display's notch geometry from `NSScreen` and notifies on
/// screen reconfiguration. All `NSScreen` reads happen here so the geometry math
/// (`NotchGeometry`) stays pure and testable — the same split as
/// `WindowMover.screenInfos()` vs `ScreenGeometry`.
@MainActor
final class NotchScreenReader {
    var onChange: (() -> Void)?

    private var observer: NSObjectProtocol?

    /// The built-in notched screen's current layout, or nil when there is no
    /// built-in display or it has no notch (e.g. clamshell to an external, or a
    /// non-notched Mac). Callers treat nil as "feature inactive," not an error.
    func currentLayout() -> NotchLayout? {
        guard let screen = NSScreen.screens.first(where: { $0.isBuiltIn }) else { return nil }
        // Always satisfied on the package's macOS 13 floor; kept as the
        // notch-API version marker (defense-in-depth / SDK clarity).
        guard #available(macOS 12.0, *) else { return nil }   // notch APIs are 12+
        let insets = screen.safeAreaInsets
        guard insets.top > 0 else { return nil }               // no notch
        let leftWidth = screen.auxiliaryTopLeftArea?.width ?? 0
        let rightWidth = screen.auxiliaryTopRightArea?.width ?? 0
        guard let span = NotchGeometry.notchSpan(
            screenMinX: screen.frame.minX,
            screenWidth: screen.frame.width,
            leftAuxWidth: leftWidth,
            rightAuxWidth: rightWidth
        ) else { return nil }
        // Cocoa rect: notch width, anchored at the very top of the screen,
        // extending down by the notch height (safe-area top inset).
        let cocoaRect = CGRect(
            x: span.minX,
            y: screen.frame.maxY - insets.top,
            width: span.width,
            height: insets.top
        )
        return NotchLayout(screen: screen, span: span, cocoaNotchRect: cocoaRect)
    }

    func startObserving() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onChange?() }
        }
    }

    func stopObserving() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }
}
