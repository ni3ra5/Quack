import AppKit
@preconcurrency import ApplicationServices
import CoreGraphics
import QuackKit

/// Moves an `AXWindow` to an adjacent display. A maximized window stays
/// maximized on the target; a normal window keeps its size and relative
/// position. The move is animated by interpolating position/size over a short
/// duration (the Accessibility API has no built-in animation).
@MainActor
enum WindowMover {

    /// All displays as `ScreenInfo` in AX (Y-down) coordinates.
    static func screenInfos() -> [ScreenInfo] {
        NSScreen.screens.map { screen in
            ScreenInfo(id: String(screen.displayID), frame: CGDisplayBounds(screen.displayID))
        }
    }

    /// Handles a title-bar swipe — acting on the CURRENT screen only:
    /// - up:    fill the screen (fullscreen)
    /// - down:  minimize to the Dock
    /// - left:  snap to the left half (when `snapEnabled`)
    /// - right: snap to the right half (when `snapEnabled`)
    ///
    /// Moving a window to another monitor is intentionally NOT a swipe action —
    /// that lives on the ⌘⌥ + arrow shortcuts instead. Returns whether anything
    /// happened.
    @discardableResult
    static func move(window: AXUIElement, currentFrame: CGRect, swipe: CGVector, snapEnabled: Bool) -> Bool {
        let screens = screenInfos()
        guard let source = ScreenGeometry.screen(containing: CGPoint(x: currentFrame.midX, y: currentFrame.midY), in: screens),
              let direction = ScreenGeometry.direction(forDelta: swipe, minMagnitude: 1)
        else { return false }
        let work = workArea(of: source)

        switch direction {
        case .up:
            AXHelpers.raise(window)
            animate(window: window, from: currentFrame, to: work)
            return true
        case .down:
            return AXHelpers.minimize(window)
        case .left, .right:
            guard snapEnabled else { return false }
            let side: ScreenGeometry.SnapSide = (direction == .left) ? .left : .right
            animate(window: window, from: currentFrame, to: snapDestination(window: window, side: side, work: work))
            return true
        }
    }

    /// Computes the snap rect, flush to the correct edge using the window's
    /// ACTUAL size after attempting to resize to half. Some windows (e.g. System
    /// Settings) refuse to shrink to half-width; if we still placed them at the
    /// half-way point they'd leave a gap. Instead we flush a right-snap to the
    /// right edge (and a left-snap to the left edge) using the real width.
    private static func snapDestination(window: AXUIElement, side: ScreenGeometry.SnapSide, work: CGRect) -> CGRect {
        let half = ScreenGeometry.halfRect(of: work, side: side)   // half width, FULL height
        // Ask for half-size, then read back only the WIDTH — to flush a window
        // that can't shrink to half-width against the correct edge. Height is
        // always the full work-area height (reading height back can return the
        // stale pre-resize value, which left small windows short).
        AXHelpers.setSize(half.size, of: window)
        let actualWidth = AXHelpers.frame(of: window)?.width ?? half.width
        let width = min(actualWidth, work.width)
        let x = (side == .left) ? work.minX : (work.maxX - width)
        return CGRect(x: x, y: work.minY, width: width, height: work.height)
    }

    /// Applies an Option+Command+Arrow shortcut to `window`: fill / small / snap
    /// on the current screen, or move to the adjacent monitor (carrying the same
    /// state) when the window is already in that state.
    static func applyArrow(_ arrow: ScreenGeometry.ArrowKey, window: AXUIElement) {
        guard let frame = AXHelpers.frame(of: window) else { return }
        let screens = screenInfos()
        guard let source = ScreenGeometry.screen(containing: CGPoint(x: frame.midX, y: frame.midY), in: screens)
        else { return }
        let work = workArea(of: source)

        switch ScreenGeometry.keyOutcome(arrow: arrow, windowFrame: frame, work: work, source: source, screens: screens) {
        case .none:
            return
        case .fill:
            animate(window: window, from: frame, to: work)
        case .small:
            animate(window: window, from: frame, to: ScreenGeometry.smallRect(of: work))
        case .snap(let side):
            animate(window: window, from: frame, to: snapDestination(window: window, side: side, work: work))
        case .move(let screenID):
            guard let target = screens.first(where: { $0.id == screenID }) else { return }
            let targetWork = workArea(of: target)
            AXHelpers.raise(window)
            // Carry the current state onto the new monitor.
            switch arrow {
            case .up:    animate(window: window, from: frame, to: targetWork)
            // Down just relocates the window to the screen below, preserving size
            // and relative position.
            case .down:  animate(window: window, from: frame,
                                  to: ScreenGeometry.destinationFrame(windowFrame: frame, from: source, to: target))
            case .left:  animate(window: window, from: frame, to: snapDestination(window: window, side: .left, work: targetWork))
            case .right: animate(window: window, from: frame, to: snapDestination(window: window, side: .right, work: targetWork))
            }
        }
    }

    /// The usable area (excluding menu bar / Dock) of `screen`, in AX (Y-down)
    /// coordinates, derived from the matching `NSScreen.visibleFrame`.
    private static func workArea(of screen: ScreenInfo) -> CGRect {
        guard let ns = NSScreen.screens.first(where: { String($0.displayID) == screen.id }) else { return screen.frame }
        // Flip Cocoa (Y-up, origin bottom-left of primary) to CG (Y-down, top-left).
        let primaryHeight = (NSScreen.screens.first { $0.frame.origin == .zero }?.frame.height) ?? ns.frame.height
        let v = ns.visibleFrame
        return CGRect(x: v.minX, y: primaryHeight - v.maxY, width: v.width, height: v.height)
    }

    /// Slides the window from `start` to `end`. Only the **position** is
    /// animated; any size change is applied once up front. Animating size every
    /// frame forces heavy apps to re-layout repeatedly, which is what made the
    /// move look janky — a single resize plus a smooth glide is far smoother.
    private static func animate(window: AXUIElement, from start: CGRect, to end: CGRect) {
        let resizes = abs(start.width - end.width) > 1 || abs(start.height - end.height) > 1
        let dx = end.minX - start.minX
        let dy = end.minY - start.minY

        // Pace on a background thread: each AX position-set is a synchronous IPC
        // the target app must honor, and some apps are slow at it. Driving this
        // from the main thread froze our UI and made the glide stutter. On a
        // background thread the loop simply waits for each (possibly slow) set
        // to finish before the next — even pacing, no pile-up, main stays free.
        DispatchQueue.global(qos: .userInteractive).async {
            if resizes { AXHelpers.setSize(end.size, of: window) }
            let steps = 30
            let frameDuration = 0.20 / Double(steps)
            for i in 1...steps {
                let p = Double(i) / Double(steps)
                let e = 1 - pow(1 - p, 3)   // ease-out cubic
                AXHelpers.setPosition(
                    CGPoint(x: start.minX + dx * CGFloat(e), y: start.minY + dy * CGFloat(e)),
                    of: window
                )
                Thread.sleep(forTimeInterval: frameDuration)
            }
            if resizes { AXHelpers.setSize(end.size, of: window) }
            AXHelpers.setPosition(end.origin, of: window)
        }
    }
}
