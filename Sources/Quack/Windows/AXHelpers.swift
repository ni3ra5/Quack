import AppKit
import ApplicationServices
import CoreGraphics

/// Thin wrappers over the Accessibility API for finding and moving windows.
/// All coordinates are global, top-left origin, Y-down (the AX / CGEvent space).
enum AXHelpers {

    /// The `AXWindow` element under a global point, walking up from whatever
    /// element is hit until an element with role `AXWindow` is found.
    static func window(at point: CGPoint) -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element)
        guard result == .success, var current = element else { return nil }

        var depth = 0
        while depth < 12 {
            if role(of: current) == kAXWindowRole as String {
                return current
            }
            guard let parent = copyElement(current, attribute: kAXParentAttribute) else { break }
            current = parent
            depth += 1
        }
        // Fall back to the element's owning window attribute.
        return copyElement(element!, attribute: kAXWindowAttribute)
    }

    static func frame(of window: AXUIElement) -> CGRect? {
        guard let position = pointValue(window, attribute: kAXPositionAttribute),
              let size = sizeValue(window, attribute: kAXSizeAttribute) else { return nil }
        return CGRect(origin: position, size: size)
    }

    /// Sets a window's top-left origin. Returns whether the API accepted it.
    @discardableResult
    static func setPosition(_ point: CGPoint, of window: AXUIElement) -> Bool {
        var p = point
        guard let value = AXValueCreate(.cgPoint, &p) else { return false }
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value) == .success
    }

    /// Sets a window's size. Returns whether the API accepted it.
    @discardableResult
    static func setSize(_ size: CGSize, of window: AXUIElement) -> Bool {
        var s = size
        guard let value = AXValueCreate(.cgSize, &s) else { return false }
        return AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value) == .success
    }

    /// Minimizes a window into the Dock (the AX equivalent of clicking its
    /// yellow button). Returns whether the API accepted it.
    @discardableResult
    static func minimize(_ window: AXUIElement) -> Bool {
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success
    }

    /// The focused window of the frontmost application (the one a keyboard
    /// shortcut should act on).
    static func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let win = value, CFGetTypeID(win) == AXUIElementGetTypeID() else { return nil }
        return (win as! AXUIElement)
    }

    /// True when `window` belongs to Quack itself. Manipulating our own window's
    /// frame via AX runs in-process; `WindowMover` does that off the main thread,
    /// which crashes AppKit — so the window features must skip our own windows.
    static func isOwnWindow(_ window: AXUIElement) -> Bool {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success else { return false }
        return pid == ProcessInfo.processInfo.processIdentifier
    }

    /// Brings the window above all others and activates its app, so a window
    /// moved to another screen lands on top.
    static func raise(_ window: AXUIElement) {
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success,
              let app = NSRunningApplication(processIdentifier: pid) else { return }
        if #available(macOS 14.0, *) {
            app.activate()
        } else {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }

    // MARK: - Internals

    private static func role(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private static func copyElement(_ element: AXUIElement, attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value else { return nil }
        // AXUIElement is a CFType; bridge if the runtime type matches.
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func pointValue(_ element: AXUIElement, attribute: String) -> CGPoint? {
        guard let axValue = axValue(element, attribute: attribute) else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(axValue, .cgPoint, &point) ? point : nil
    }

    private static func sizeValue(_ element: AXUIElement, attribute: String) -> CGSize? {
        guard let axValue = axValue(element, attribute: attribute) else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(axValue, .cgSize, &size) ? size : nil
    }

    private static func axValue(_ element: AXUIElement, attribute: String) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }
}
