import AppKit
import CoreGraphics
import QuackKit

/// One external display Quack can control, pairing an `NSScreen` with its DDC
/// index and a stable key used to persist per-display brightness.
struct ControllableDisplay: Identifiable {
    let id: String          // stable key (display name + number)
    let name: String
    let screenNumber: CGDirectDisplayID
    let ddcIndex: Int
    let frame: CGRect
    var supportsDDC: Bool
}

/// Bridges `NSScreen`s to `DDCControl`. Discovers external displays, exposes a
/// stable per-display key for persistence, and applies brightness.
@MainActor
final class BrightnessController: ObservableObject {
    @Published private(set) var displays: [ControllableDisplay] = []

    /// Whether this Mac can do DDC at all (Apple Silicon path only here).
    var isSupportedPlatform: Bool { DDCControl.isAppleSilicon }

    init() {
        refreshDisplays()
    }

    /// Rebuilds the external-display list. External `NSScreen`s are ordered by
    /// x-origin and paired with DDC indices in the same order (the documented
    /// best-effort mapping on Apple Silicon).
    func refreshDisplays() {
        let externalScreens = NSScreen.screens
            .filter { !$0.isBuiltIn }
            .sorted { $0.frame.minX < $1.frame.minX }

        let serviceCount = isSupportedPlatform ? DDCControl.externalDisplayCount() : 0
        Log.brightness.log("refreshDisplays: \(externalScreens.count) external screen(s), \(serviceCount) DDC service(s)")

        var result: [ControllableDisplay] = []
        for (index, screen) in externalScreens.enumerated() {
            let number = screen.displayID
            let key = "\(screen.localizedNameSafe)#\(number)"
            // Treat the display as controllable when a DDC service exists at its
            // index. We do NOT require a successful DDC *read*: many monitors
            // accept brightness writes but never answer reads, so gating on a
            // read would wrongly disable a perfectly controllable display.
            let supports = isSupportedPlatform && index < serviceCount
            result.append(
                ControllableDisplay(
                    id: key,
                    name: screen.localizedNameSafe,
                    screenNumber: number,
                    ddcIndex: index,
                    frame: screen.frame,
                    supportsDDC: supports
                )
            )
        }
        displays = result
    }

    /// The controllable external display whose frame **strictly** contains
    /// `point` (Cocoa global coords). Returns nil when the cursor is on the
    /// built-in display or in a gap — so brightness keys there pass through to
    /// the built-in instead of wrongly hitting an external monitor.
    func display(containing point: CGPoint) -> ControllableDisplay? {
        displays.first { $0.frame.contains(point) }
    }

    @discardableResult
    func setBrightness(_ percent: Int, on display: ControllableDisplay) -> Bool {
        guard display.supportsDDC else { return false }
        return DDCControl.setBrightness(percent, atIndex: display.ddcIndex)
    }

    /// The display's current brightness as a 0…1 fraction read over DDC, or nil
    /// if it doesn't report one.
    func currentFraction(of display: ControllableDisplay) -> Double? {
        guard display.supportsDDC, let value = DDCControl.brightness(atIndex: display.ddcIndex) else { return nil }
        return Double(value) / 100.0
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    var isBuiltIn: Bool {
        CGDisplayIsBuiltin(displayID) != 0
    }

    var localizedNameSafe: String {
        // `localizedName` is macOS 10.15+, always available on our target.
        localizedName.isEmpty ? "Display \(displayID)" : localizedName
    }
}
