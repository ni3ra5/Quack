import AppKit
import CoreGraphics
import Combine
import QuackKit

/// Global keyboard shortcuts for window management: the configured modifier
/// (default ⌘⌥) + arrow keys. Installs a `CGEventTap` for key-down events,
/// applies the matching action to the focused window, and consumes the event.
/// Requires Accessibility permission.
@MainActor
final class HotkeyMonitor: ManagedService {
    private let settings: SettingsStore
    private let permissions: PermissionsManager

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var started = false
    private var permissionCancellable: AnyCancellable?

    // Arrow key codes.
    private static let keyLeft: Int64 = 123, keyRight: Int64 = 124, keyDown: Int64 = 125, keyUp: Int64 = 126

    init(settings: SettingsStore, permissions: PermissionsManager) {
        self.settings = settings
        self.permissions = permissions
    }

    func start() {
        started = true
        permissionCancellable = permissions.$statuses
            .sink { [weak self] _ in Task { @MainActor in self?.installTapIfGranted() } }
        if permissions.status(for: .accessibility) == .granted {
            installTapIfGranted()
        } else {
            permissions.requestAccessibilityAccess()
        }
    }

    func stop() {
        started = false
        permissionCancellable = nil
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        runLoopSource = nil
        eventTap = nil
    }

    private func installTapIfGranted() {
        guard started, eventTap == nil, permissions.status(for: .accessibility) == .granted else { return }
        let mask: CGEventMask = 1 << CGEventType.keyDown.rawValue
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                return monitor.handleKey(type: type, event: event)
            },
            userInfo: refcon
        ) else {
            Log.swipe.error("Failed to create hotkey tap (Accessibility not effective?)")
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        Log.swipe.log("Window-shortcut hotkey tap installed")
    }

    private func requiredFlags() -> CGEventFlags {
        let m = settings.settings.windowShortcutModifiers
        var flags = CGEventFlags()
        if m & 0b0001 != 0 { flags.insert(.maskCommand) }
        if m & 0b0010 != 0 { flags.insert(.maskAlternate) }
        if m & 0b0100 != 0 { flags.insert(.maskControl) }
        if m & 0b1000 != 0 { flags.insert(.maskShift) }
        return flags
    }

    fileprivate func handleKey(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let passthrough = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return passthrough
        }
        guard type == .keyDown else { return passthrough }

        let required = requiredFlags()
        guard !required.isEmpty else { return passthrough }   // never hijack plain arrows
        let relevant: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        guard event.flags.intersection(relevant) == required else { return passthrough }

        let arrow: ScreenGeometry.ArrowKey
        switch event.getIntegerValueField(.keyboardEventKeycode) {
        case Self.keyUp: arrow = .up
        case Self.keyDown: arrow = .down
        case Self.keyLeft: arrow = .left
        case Self.keyRight: arrow = .right
        default: return passthrough
        }

        if let window = AXHelpers.focusedWindow() {
            WindowMover.applyArrow(arrow, window: window)
        }
        return nil   // consume — we handled it
    }
}
