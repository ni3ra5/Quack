import CoreGraphics

/// A single menu-bar status item as scanned from the window server, decoupled
/// from CoreGraphics' window-info dictionaries so the classification math is
/// unit-testable. `frame` is in CG (Y-down, top-left) global coordinates.
public struct StatusItemFrame: Equatable, Sendable {
    public let ownerPID: Int32
    public let windowID: UInt32
    public let frame: CGRect

    public init(ownerPID: Int32, windowID: UInt32, frame: CGRect) {
        self.ownerPID = ownerPID
        self.windowID = windowID
        self.frame = frame
    }
}

/// Pure notch geometry. The notch's horizontal span is the same number in both
/// Cocoa (Y-up) and CoreGraphics (Y-down) coordinate spaces because only the Y
/// axis flips between them — so all of this is coordinate-system-agnostic and
/// lives here, away from `NSScreen`. Mirrors how `ScreenGeometry` keeps the
/// window-move math testable and separate from `WindowMover`'s `NSScreen` reads.
public enum NotchGeometry {

    /// The horizontal span occupied by the notch, in the same x-space as the
    /// inputs. Nil on a screen without a notch (either auxiliary side absent).
    public struct NotchSpan: Equatable, Sendable {
        public let minX: CGFloat
        public let maxX: CGFloat
        public init(minX: CGFloat, maxX: CGFloat) {
            self.minX = minX
            self.maxX = maxX
        }
        public var width: CGFloat { maxX - minX }
    }

    /// Derives the notch span from a screen's width and the widths of the two
    /// usable auxiliary areas flanking the camera housing. On a notched screen
    /// the notch sits between the right edge of the left area and the left edge
    /// of the right area. Returns nil when either side is absent (no notch) or
    /// the resulting span is degenerate.
    public static func notchSpan(
        screenMinX: CGFloat,
        screenWidth: CGFloat,
        leftAuxWidth: CGFloat,
        rightAuxWidth: CGFloat
    ) -> NotchSpan? {
        guard leftAuxWidth > 0, rightAuxWidth > 0 else { return nil }
        let minX = screenMinX + leftAuxWidth
        let maxX = screenMinX + screenWidth - rightAuxWidth
        guard maxX > minX else { return nil }
        return NotchSpan(minX: minX, maxX: maxX)
    }

    /// The subset of `items` whose horizontal midpoint falls within the notch
    /// span — i.e. items the notch has crushed and hidden. Midpoint-in-span is a
    /// deliberately simple, tunable predicate; the exact threshold is refined
    /// empirically on real hardware (see the design spec's open risks).
    public static func crushedItems(_ items: [StatusItemFrame], notch: NotchSpan) -> [StatusItemFrame] {
        items.filter { $0.frame.midX >= notch.minX && $0.frame.midX <= notch.maxX }
    }
}
