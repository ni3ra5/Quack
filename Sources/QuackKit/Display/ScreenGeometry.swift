import CoreGraphics

/// A minimal, value-type description of a display, decoupled from `NSScreen`
/// so the geometry math is unit-testable.
public struct ScreenInfo: Equatable, Hashable, Sendable {
    public let id: String
    public let frame: CGRect

    public init(id: String, frame: CGRect) {
        self.id = id
        self.frame = frame
    }

    public var center: CGPoint {
        CGPoint(x: frame.midX, y: frame.midY)
    }
}

public enum SwipeDirection: Equatable, Sendable {
    case left, right, up, down
}

/// Pure geometry helpers shared by `CursorMonitor`, `BrightnessController`,
/// and `WindowMover`.
public enum ScreenGeometry {

    /// The screen whose frame contains `point`. If none contains it (e.g. the
    /// point sits in a gap), returns the screen whose center is nearest.
    public static func screen(containing point: CGPoint, in screens: [ScreenInfo]) -> ScreenInfo? {
        if let hit = screens.first(where: { $0.frame.contains(point) }) {
            return hit
        }
        return screens.min { lhs, rhs in
            distanceSquared(point, lhs.center) < distanceSquared(point, rhs.center)
        }
    }

    /// The adjacent screen in `direction` from `origin`: among screens whose
    /// center lies in that direction, the nearest by center distance.
    public static func adjacentScreen(
        from origin: ScreenInfo,
        direction: SwipeDirection,
        in screens: [ScreenInfo]
    ) -> ScreenInfo? {
        let candidates = screens.filter { other in
            guard other.id != origin.id else { return false }
            let dx = other.center.x - origin.center.x
            let dy = other.center.y - origin.center.y
            // Require the axis to dominate, so a monitor that's mostly ABOVE but
            // slightly to the side isn't treated as "left"/"right" (and vice
            // versa). Y-down coords: "up" = smaller y.
            switch direction {
            case .left:  return dx < 0 && abs(dx) > abs(dy)
            case .right: return dx > 0 && abs(dx) > abs(dy)
            case .up:    return dy < 0 && abs(dy) > abs(dx)
            case .down:  return dy > 0 && abs(dy) > abs(dx)
            }
        }
        return candidates.min { lhs, rhs in
            distanceSquared(origin.center, lhs.center) < distanceSquared(origin.center, rhs.center)
        }
    }

    /// The screen to move to for a swipe vector: the adjacent screen whose
    /// direction from `source` best matches the swipe, and only if that
    /// alignment is within `maxAngleDegrees`. This means a swipe only moves a
    /// window toward a monitor that is actually in that direction — e.g. with a
    /// monitor directly above, a rightward swipe finds nothing.
    ///
    /// Both the swipe vector and screen positions are in the same Y-down space.
    public static func targetScreen(
        forSwipe swipe: CGVector,
        from source: ScreenInfo,
        in screens: [ScreenInfo],
        maxAngleDegrees: Double = 55
    ) -> ScreenInfo? {
        let swipeMag = (swipe.dx * swipe.dx + swipe.dy * swipe.dy).squareRoot()
        guard swipeMag > 0 else { return nil }
        let swipeAngle = atan2(Double(swipe.dy), Double(swipe.dx))
        let maxAngle = maxAngleDegrees * .pi / 180

        var best: (screen: ScreenInfo, angle: Double)?
        for screen in screens where screen.id != source.id {
            let dx = Double(screen.center.x - source.center.x)
            let dy = Double(screen.center.y - source.center.y)
            guard dx != 0 || dy != 0 else { continue }
            let dirAngle = atan2(dy, dx)
            // Smallest absolute angular difference, wrapped to [0, π].
            var diff = abs(dirAngle - swipeAngle)
            if diff > .pi { diff = 2 * .pi - diff }
            if diff <= maxAngle, best == nil || diff < best!.angle {
                best = (screen, diff)
            }
        }
        return best?.screen
    }

    public enum SnapSide: Equatable, Sendable { case left, right }

    /// What a title-bar swipe should do.
    public enum SwipeOutcome: Equatable, Sendable {
        case none
        case move(screenID: String)   // a monitor exists in the swipe direction
        case snap(SnapSide)           // no monitor that way → align to half the screen
    }

    /// Decides the outcome of a swipe: move to an adjacent monitor if one lies in
    /// that direction, otherwise (for horizontal swipes, when `snapEnabled`) snap
    /// the window to that half of the current screen.
    public static func swipeOutcome(
        swipe: CGVector,
        from source: ScreenInfo,
        in screens: [ScreenInfo],
        snapEnabled: Bool,
        minMagnitude: CGFloat
    ) -> SwipeOutcome {
        let magnitude = (swipe.dx * swipe.dx + swipe.dy * swipe.dy).squareRoot()
        guard magnitude >= minMagnitude else { return .none }
        if let target = targetScreen(forSwipe: swipe, from: source, in: screens) {
            return .move(screenID: target.id)
        }
        guard snapEnabled, let dir = direction(forDelta: swipe, minMagnitude: minMagnitude) else { return .none }
        switch dir {
        case .left: return .snap(.left)
        case .right: return .snap(.right)
        case .up, .down: return .none   // only horizontal swipes snap
        }
    }

    public enum ArrowKey: Sendable { case up, down, left, right }

    /// What an Option+Command+Arrow shortcut should do to the focused window.
    public enum WindowKeyOutcome: Equatable, Sendable {
        case fill                      // maximize on current screen
        case small                     // centered small window on current screen
        case snap(SnapSide)            // left/right half on current screen
        case move(screenID: String)    // already in that state → move to adjacent monitor
        case none                      // already in that state but no monitor that way
    }

    /// A centered "small" window rect (default 60% of the work area).
    public static func smallRect(of work: CGRect, fraction: CGFloat = 0.6) -> CGRect {
        let w = work.width * fraction, h = work.height * fraction
        return CGRect(x: work.minX + (work.width - w) / 2,
                      y: work.minY + (work.height - h) / 2, width: w, height: h)
    }

    public static func isFilling(_ f: CGRect, _ work: CGRect, tol: CGFloat = 0.06) -> Bool {
        abs(f.minX - work.minX) <= work.width * tol && abs(f.minY - work.minY) <= work.height * tol &&
        abs(f.maxX - work.maxX) <= work.width * tol && abs(f.maxY - work.maxY) <= work.height * tol
    }

    public static func isSmall(_ f: CGRect, _ work: CGRect) -> Bool {
        let s = smallRect(of: work)
        let tol = max(work.width, work.height) * 0.04
        return abs(f.minX - s.minX) <= tol && abs(f.minY - s.minY) <= tol &&
               abs(f.width - s.width) <= tol && abs(f.height - s.height) <= tol
    }

    public static func isAligned(_ f: CGRect, _ work: CGRect, side: SnapSide, tol: CGFloat = 0.06) -> Bool {
        let tx = work.width * tol
        let halfWidthOK = abs(f.width - work.width / 2) <= tx
        switch side {
        case .left: return halfWidthOK && abs(f.minX - work.minX) <= tx
        case .right: return halfWidthOK && abs(f.maxX - work.maxX) <= tx
        }
    }

    /// Decides what an arrow shortcut does: place the window in the target state,
    /// or (if it's already in that state) move it to the adjacent monitor.
    public static func keyOutcome(
        arrow: ArrowKey, windowFrame f: CGRect, work: CGRect,
        source: ScreenInfo, screens: [ScreenInfo]
    ) -> WindowKeyOutcome {
        func adjacent(_ d: SwipeDirection) -> WindowKeyOutcome {
            adjacentScreen(from: source, direction: d, in: screens).map { .move(screenID: $0.id) } ?? .none
        }
        switch arrow {
        case .up:    return isFilling(f, work) ? adjacent(.up) : .fill
        // Down moves straight to the screen below (no "make smaller" step).
        case .down:  return adjacent(.down)
        case .left:  return isAligned(f, work, side: .left) ? adjacent(.left) : .snap(.left)
        case .right: return isAligned(f, work, side: .right) ? adjacent(.right) : .snap(.right)
        }
    }

    /// The left/right half of a work area (used for snapping).
    public static func halfRect(of work: CGRect, side: SnapSide) -> CGRect {
        let halfWidth = work.width / 2
        switch side {
        case .left: return CGRect(x: work.minX, y: work.minY, width: halfWidth, height: work.height)
        case .right: return CGRect(x: work.minX + halfWidth, y: work.minY, width: halfWidth, height: work.height)
        }
    }

    /// Maps `direction` from a 2D drag delta, choosing the dominant axis. Returns
    /// nil when the movement is below `minMagnitude` (i.e. not really a swipe).
    public static func direction(forDelta delta: CGVector, minMagnitude: CGFloat) -> SwipeDirection? {
        let absX = abs(delta.dx)
        let absY = abs(delta.dy)
        guard max(absX, absY) >= minMagnitude else { return nil }
        if absX >= absY {
            return delta.dx < 0 ? .left : .right
        } else {
            return delta.dy < 0 ? .up : .down
        }
    }

    /// Repositions `windowFrame` onto `target`, preserving its position relative
    /// to its current `source` screen and clamping so it stays fully on-screen.
    public static func reposition(
        windowFrame: CGRect,
        from source: ScreenInfo,
        to target: ScreenInfo
    ) -> CGRect {
        // Relative offset within the source screen (0...1).
        let relX = source.frame.width > 0 ? (windowFrame.minX - source.frame.minX) / source.frame.width : 0
        let relY = source.frame.height > 0 ? (windowFrame.minY - source.frame.minY) / source.frame.height : 0
        var newX = target.frame.minX + relX * target.frame.width
        var newY = target.frame.minY + relY * target.frame.height
        // Clamp to keep the window fully visible on the target.
        let maxX = target.frame.maxX - windowFrame.width
        let maxY = target.frame.maxY - windowFrame.height
        newX = min(max(newX, target.frame.minX), max(maxX, target.frame.minX))
        newY = min(max(newY, target.frame.minY), max(maxY, target.frame.minY))
        return CGRect(x: newX, y: newY, width: windowFrame.width, height: windowFrame.height)
    }

    /// Whether `windowFrame` effectively fills `screen` (maximized / full).
    /// Uses area coverage so menu-bar/Dock insets don't disqualify it.
    public static func fillsScreen(_ windowFrame: CGRect, _ screen: ScreenInfo, threshold: CGFloat = 0.9) -> Bool {
        let inter = windowFrame.intersection(screen.frame)
        guard !inter.isNull, screen.frame.width > 0, screen.frame.height > 0 else { return false }
        let coverage = (inter.width * inter.height) / (screen.frame.width * screen.frame.height)
        return coverage >= threshold
    }

    /// Re-creates a maximized window's edge insets on the target screen, so a
    /// full window stays full (preserving the menu-bar/Dock gaps it had).
    public static func fillEquivalent(windowFrame: CGRect, from source: ScreenInfo, to target: ScreenInfo) -> CGRect {
        let left = windowFrame.minX - source.frame.minX
        let top = windowFrame.minY - source.frame.minY
        let right = source.frame.maxX - windowFrame.maxX
        let bottom = source.frame.maxY - windowFrame.maxY
        return CGRect(
            x: target.frame.minX + left,
            y: target.frame.minY + top,
            width: max(target.frame.width - left - right, 1),
            height: max(target.frame.height - top - bottom, 1)
        )
    }

    /// Picks the destination frame for a window moved to `target`, preserving
    /// edge alignment and full-size per axis:
    /// - maximized → stays maximized;
    /// - flush-left / flush-right (and/or full-height) → same alignment on target;
    /// - otherwise → relative position, same size.
    public static func destinationFrame(windowFrame w: CGRect, from src: ScreenInfo, to tgt: ScreenInfo) -> CGRect {
        if fillsScreen(w, src) {
            return fillEquivalent(windowFrame: w, from: src, to: tgt)
        }

        let tol: CGFloat = 8
        let s = src.frame, t = tgt.frame
        let left = w.minX - s.minX        // insets from each source edge
        let right = s.maxX - w.maxX
        let top = w.minY - s.minY
        let bottom = s.maxY - w.maxY

        let leftSnap = left <= tol
        let rightSnap = right <= tol
        let bottomSnap = bottom <= tol
        let topSnap = top <= tol
        let fullWidth = w.width >= s.width * 0.9
        let fullHeight = w.height >= s.height * 0.9

        // Horizontal axis.
        var newWidth = w.width
        var newX: CGFloat
        if fullWidth || (leftSnap && rightSnap) {
            newWidth = max(t.width - left - right, 1)
            newX = t.minX + left
        } else if rightSnap {
            newX = t.maxX - right - w.width
        } else if leftSnap {
            newX = t.minX + left
        } else {
            let rel = s.width > 0 ? (w.minX - s.minX) / s.width : 0
            newX = t.minX + rel * t.width
        }

        // Vertical axis (note: full-height keeps the top inset, e.g. menu bar).
        var newHeight = w.height
        var newY: CGFloat
        if fullHeight || (topSnap && bottomSnap) {
            newHeight = max(t.height - top - bottom, 1)
            newY = t.minY + top
        } else if bottomSnap {
            newY = t.maxY - bottom - w.height
        } else if topSnap {
            newY = t.minY + top
        } else {
            let rel = s.height > 0 ? (w.minY - s.minY) / s.height : 0
            newY = t.minY + rel * t.height
        }

        newX = min(max(newX, t.minX), max(t.maxX - newWidth, t.minX))
        newY = min(max(newY, t.minY), max(t.maxY - newHeight, t.minY))
        return CGRect(x: newX, y: newY, width: newWidth, height: newHeight)
    }

    /// The top title-bar band of a window frame (AX coords, Y-down: band is at
    /// the window's minY).
    public static func titleBarBand(of windowFrame: CGRect, height: CGFloat = 28) -> CGRect {
        CGRect(x: windowFrame.minX, y: windowFrame.minY, width: windowFrame.width, height: min(height, windowFrame.height))
    }

    private static func distanceSquared(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return dx * dx + dy * dy
    }
}
