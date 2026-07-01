import AppKit
@preconcurrency import ApplicationServices
import CoreGraphics
import QuackKit

/// Forwards a click to a status item that is physically hidden under the notch.
/// The item's window still occupies logical coordinates there (the notch only
/// hides it visually), so activating it at its real center works. Tries the
/// Accessibility press first (occlusion-independent), then falls back to a
/// synthesized mouse click posted to the owning process (Ice's technique).
///
/// This posts a single OUTGOING event via `postToPid`; it installs no event tap,
/// so the CLAUDE.md tap-freeze rules do not apply here.
enum StatusItemForwarder {

    @MainActor
    static func forward(to item: StatusItemFrame) {
        let center = CGPoint(x: item.frame.midX, y: item.frame.midY)   // CG, Y-down

        // 1) Accessibility press — the clean path; ignores visual occlusion.
        if pressViaAccessibility(at: center) { return }

        // 2) Fallback: synthesize a mouse down/up delivered to the owning app.
        postSyntheticClick(at: center, pid: item.ownerPID)
    }

    /// Returns whether an AX element was found and pressed. (There is no reliable
    /// signal that the app's menu actually opened — a successful press action is
    /// the best available confirmation.)
    private static func pressViaAccessibility(at point: CGPoint) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element) == .success,
              let element else { return false }
        return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    private static func postSyntheticClick(at point: CGPoint, pid: Int32) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                           mouseCursorPosition: point, mouseButton: .left)
        let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                         mouseCursorPosition: point, mouseButton: .left)
        down?.postToPid(pid)
        up?.postToPid(pid)
    }
}
