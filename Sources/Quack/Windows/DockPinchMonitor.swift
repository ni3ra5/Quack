import AppKit
import Combine
import QuackKit
import CMultitouch

// The MultitouchSupport callback is a context-free C function pointer, so the
// frame stream is routed through a file-scope sink set while the monitor runs.
// `nonisolated(unsafe)` because it's written on the main actor (start/stop) and
// read on the multitouch thread; writes are ordered before cmt_start / after
// cmt_stop, so there's no concurrent access in practice.
private nonisolated(unsafe) var dockPinchSink: ((UnsafePointer<CMTFinger>?, Int32) -> Void)?

private func dockPinchTrampoline(_ fingers: UnsafePointer<CMTFinger>?, _ count: Int32) {
    dockPinchSink?(fingers, count)
}

/// Detects a deliberate two-finger pinch-in over an app's Dock icon and quits
/// that app — Quack's take on Swish's Dock gestures, built on raw trackpad data
/// from `MultitouchSupport` (see `CMultitouch`). Opt-in; requires Accessibility.
///
/// If the private framework is unavailable, `cmt_start` returns false and the
/// feature simply stays off — nothing else in the app is affected.
@MainActor
final class DockPinchMonitor: ManagedService {
    private let settings: SettingsStore
    private let permissions: PermissionsManager
    private let diagnostics: DiagnosticsStatus
    private let indicator = CloseIndicator()
    private let detector = PinchDetector()

    private var started = false
    private var running = false
    private var permissionCancellable: AnyCancellable?
    private var lastFire = Date.distantPast

    init(settings: SettingsStore, permissions: PermissionsManager, diagnostics: DiagnosticsStatus) {
        self.settings = settings
        self.permissions = permissions
        self.diagnostics = diagnostics
        detector.onPinchIn = { [weak self] in
            DispatchQueue.main.async { self?.handlePinch() }
        }
    }

    func start() {
        started = true
        // Start as soon as Accessibility is granted, prompting once.
        permissionCancellable = permissions.$statuses
            .sink { [weak self] _ in Task { @MainActor in self?.startIfGranted() } }
        if permissions.status(for: .accessibility) == .granted {
            startIfGranted()
        } else {
            permissions.requestAccessibilityAccess()
        }
    }

    func stop() {
        started = false
        permissionCancellable = nil
        if running {
            cmt_stop()
            dockPinchSink = nil
            running = false
        }
        diagnostics.dockPinchActive = false
    }

    private func startIfGranted() {
        guard started, !running, permissions.status(for: .accessibility) == .granted else { return }
        let detector = self.detector
        dockPinchSink = { fingers, count in detector.process(fingers, count) }
        if cmt_start(dockPinchTrampoline) {
            running = true
            diagnostics.dockPinchActive = true
            Log.dock.log("Multitouch pinch monitor started")
        } else {
            dockPinchSink = nil
            Log.dock.error("MultitouchSupport unavailable — Dock pinch disabled")
        }
    }

    /// Runs on the main actor when the detector reports a pinch-in. Routes to a
    /// Dock-icon quit or a title-bar window close, depending on what's under the
    /// cursor and which gestures are enabled.
    private func handlePinch() {
        let s = settings.settings
        guard started, s.dockPinchQuitEnabled || s.windowPinchCloseEnabled else { return }
        // Debounce: one action per gesture-and-a-bit, so a single pinch can't
        // double-fire as fingers settle.
        let now = Date()
        guard now.timeIntervalSince(lastFire) > 1.0 else { return }

        // 1) A Dock app icon under the cursor → quit that app.
        if s.dockPinchQuitEnabled, let hit = DockAccessibility.appUnderCursor() {
            let bid = hit.app.bundleIdentifier
            // Never quit Quack itself; skip Finder (it just relaunches).
            if bid == Bundle.main.bundleIdentifier || bid == "com.apple.finder" { return }
            lastFire = now
            indicator.flash(at: hit.iconCenter)
            let name = hit.app.localizedName ?? bid ?? "app"
            let quit = hit.app.terminate()
            Log.dock.log("pinch-to-quit \(name, privacy: .public) -> \(quit ? "terminated" : "refused")")
            return
        }

        // 2) A window's title bar under the cursor → close just that window.
        if s.windowPinchCloseEnabled, closeWindowUnderCursor() { lastFire = now }
    }

    /// Closes the window whose title bar is under the cursor (not the whole app).
    /// Returns whether a window was closed.
    private func closeWindowUnderCursor() -> Bool {
        let mouse = NSEvent.mouseLocation          // Cocoa, Y-up
        let ph = (NSScreen.screens.first { $0.frame.origin == .zero }?.frame.height)
            ?? NSScreen.main?.frame.height ?? 0
        let axPoint = CGPoint(x: mouse.x, y: ph - mouse.y)   // AX, Y-down

        guard let window = AXHelpers.window(at: axPoint),
              !AXHelpers.isOwnWindow(window),
              let frame = AXHelpers.frame(of: window),
              ScreenGeometry.titleBarBand(of: frame, height: 56).contains(axPoint)
        else {
            Log.dock.debug("pinch fired but cursor not on a window title bar")
            return false
        }
        indicator.flash(at: mouse)
        let closed = AXHelpers.close(window)
        Log.dock.log("pinch-to-close window -> \(closed ? "closed" : "refused")")
        return closed
    }
}

/// Pure pinch-recognition over raw touch frames. Lives off the main actor; it is
/// only ever called from the multitouch thread, one frame at a time.
final class PinchDetector {
    var onPinchIn: (() -> Void)?

    private var tracking = false
    private var latched = false
    private var startDistance: Float = 0

    // Tuning: fingers must start at least this far apart, then close by at least
    // this much (normalized trackpad units, 0…1) to count as a deliberate pinch.
    private let minStartSeparation: Float = 0.22
    private let minClose: Float = 0.16
    private let touchingState: Int32 = 4   // MTTouchStateTouching

    func process(_ fingers: UnsafePointer<CMTFinger>?, _ count: Int32) {
        guard let fingers else { reset(); return }

        var a: CMTFinger?
        var b: CMTFinger?
        var touching = 0
        var i = 0
        while i < Int(count) {
            let f = fingers[i]
            if f.state == touchingState {
                touching += 1
                if a == nil { a = f } else if b == nil { b = f }
            }
            i += 1
        }
        guard touching == 2, let p = a, let q = b else { reset(); return }

        let dx = p.x - q.x
        let dy = p.y - q.y
        let dist = (dx * dx + dy * dy).squareRoot()

        if !tracking {
            tracking = true
            latched = false
            startDistance = dist
            return
        }
        // Track the widest separation seen as the baseline (fingers may still be
        // settling on the first frames).
        if dist > startDistance { startDistance = dist }

        if !latched, startDistance >= minStartSeparation, (startDistance - dist) >= minClose {
            latched = true
            onPinchIn?()
        }
    }

    private func reset() {
        tracking = false
        latched = false
        startDistance = 0
    }
}
