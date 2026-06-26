import AppKit
import CoreGraphics
import Combine
import QuackKit

/// Routes the Mac brightness keys (F1/F2) to whichever external display the
/// cursor is on, over DDC — and tracks the active display for the optional
/// "dim inactive display" behavior.
///
/// When the cursor is on an external DDC display, a brightness-key press is
/// applied to that monitor and the event is **consumed** so the built-in
/// display doesn't also change. When the cursor is on the built-in display (or
/// a non-DDC external), keys pass through untouched.
///
/// Consuming key events requires an active event tap, which needs Accessibility
/// permission. Without it, the slider and dim behavior still work; only the
/// F1/F2 routing is unavailable.
@MainActor
final class CursorBrightnessService: ManagedService {
    private let controller: BrightnessController
    private let settings: SettingsStore
    private let permissions: PermissionsManager
    private let diagnostics: DiagnosticsStatus

    // System-defined (NSEvent type 14) brightness key codes.
    private static let brightnessUp: Int32 = 2     // NX_KEYTYPE_BRIGHTNESS_UP
    private static let brightnessDown: Int32 = 3   // NX_KEYTYPE_BRIGHTNESS_DOWN
    private static let auxButtonsSubtype = 8        // NX_SUBTYPE_AUX_CONTROL_BUTTONS

    private var cursorMonitor: Any?
    private var pollTimer: Timer?
    private var keyTap: CFMachPort?
    private var keyTapSource: CFRunLoopSource?
    private var lastDisplayID: String?
    private var started = false
    private var permissionCancellable: AnyCancellable?
    private let hud = BrightnessHUD()

    init(controller: BrightnessController, settings: SettingsStore, permissions: PermissionsManager, diagnostics: DiagnosticsStatus) {
        self.controller = controller
        self.settings = settings
        self.permissions = permissions
        self.diagnostics = diagnostics
    }

    func start() {
        started = true
        controller.refreshDisplays()
        diagnostics.externalDisplayCount = controller.displays.count
        diagnostics.ddcServiceCount = DDCControl.isAppleSilicon ? DDCControl.externalDisplayCount() : 0
        lastDisplayID = nil

        cursorMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            Task { @MainActor in self?.evaluateCursor() }
        }
        let timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluateCursor() }
        }
        timer.tolerance = 0.1
        pollTimer = timer
        evaluateCursor()

        // Install the key tap when granted, but only PROMPT once (here), not on
        // every status poll — repeated prompting was the cause of the dialog
        // reappearing.
        permissionCancellable = permissions.$statuses
            .sink { [weak self] _ in Task { @MainActor in self?.installKeyTapIfGranted() } }
        if permissions.status(for: .accessibility) == .granted {
            installKeyTapIfGranted()
        } else {
            permissions.requestAccessibilityAccess()
        }
    }

    func stop() {
        started = false
        permissionCancellable = nil
        if let cursorMonitor { NSEvent.removeMonitor(cursorMonitor) }
        cursorMonitor = nil
        pollTimer?.invalidate()
        pollTimer = nil
        if let keyTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), keyTapSource, .commonModes)
        }
        if let keyTap { CGEvent.tapEnable(tap: keyTap, enable: false) }
        keyTap = nil
        keyTapSource = nil
        lastDisplayID = nil
        diagnostics.brightnessKeyTapInstalled = false
        // Intentionally makes no DDC writes on stop.
    }

    // MARK: Cursor tracking (dim inactive display)

    private func evaluateCursor() {
        let point = NSEvent.mouseLocation   // Cocoa Y-up global coords
        guard let active = controller.display(containing: point) else {
            lastDisplayID = nil
            return
        }
        guard active.id != lastDisplayID else { return }
        let previousID = lastDisplayID
        lastDisplayID = active.id

        guard settings.settings.dimInactiveDisplay else { return }
        // Restore the now-active display to its stored brightness…
        if let target = settings.settings.displayBrightness[active.id] {
            controller.setBrightness(Int((target * 100).rounded()), on: active)
        }
        // …and dim the one we just left.
        if let previousID, let previous = controller.displays.first(where: { $0.id == previousID }) {
            controller.setBrightness(20, on: previous)
        }
    }

    // MARK: Brightness-key routing

    /// Installs the key tap only when access is granted. Never prompts.
    private func installKeyTapIfGranted() {
        guard started, keyTap == nil, permissions.status(for: .accessibility) == .granted else { return }

        let mask: CGEventMask = 1 << 14   // NSSystemDefined
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,          // active: can consume events
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<CursorBrightnessService>.fromOpaque(refcon).takeUnretainedValue()
                return service.handleSystemDefined(type: type, event: event)
            },
            userInfo: refcon
        ) else {
            Log.brightness.error("Failed to create brightness key tap (Accessibility not effective?)")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        keyTap = tap
        keyTapSource = source
        diagnostics.brightnessKeyTapInstalled = true
        Log.brightness.log("Brightness key tap installed")
    }

    /// Returns nil to swallow the event (when routed to an external display) or
    /// the original event to let it pass through to the built-in display.
    fileprivate func handleSystemDefined(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let passthrough = Unmanaged.passUnretained(event)

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let keyTap { CGEvent.tapEnable(tap: keyTap, enable: true) }
            return passthrough
        }
        guard let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == Self.auxButtonsSubtype else {
            return passthrough
        }

        let data1 = ns.data1
        let keyCode = Int32((data1 & 0xFFFF0000) >> 16)
        let isKeyDown = ((data1 & 0x0000FF00) >> 8) == 0x0A
        guard keyCode == Self.brightnessUp || keyCode == Self.brightnessDown else { return passthrough }

        // Only route when the cursor is on a DDC-capable external display.
        guard let active = controller.display(containing: NSEvent.mouseLocation), active.supportsDDC else {
            return passthrough
        }

        if isKeyDown {
            let current = settings.settings.displayBrightness[active.id]
                ?? controller.currentFraction(of: active)
                ?? 0.8
            let next = BrightnessMath.stepped(
                current: current,
                stepPercent: settings.settings.brightnessStepPercent,
                increase: keyCode == Self.brightnessUp
            )
            settings.update { $0.displayBrightness[active.id] = next }
            controller.setBrightness(Int((next * 100).rounded()), on: active)
            let screen = NSScreen.screens.first { $0.displayID == active.screenNumber }
            hud.show(displayName: active.name, level: next, on: screen)
        }
        // Swallow both key-down and key-up so the built-in display is untouched.
        return nil
    }
}
