# Notch Icon Reveal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reveal menu-bar icons crushed behind the MacBook notch in a hover-activated panel anchored at the notch, mirroring each hidden icon's live pixels and forwarding clicks to the real item.

**Architecture:** Pure geometry + classification lives in `QuackKit` (unit-tested with scalar/value fixtures, exactly like the existing `ScreenGeometry`). Impure `NSScreen` / `CGWindowList` / `AX` / `CGEvent` reads live in the `Quack` app target (like the existing `WindowMover`). A `ManagedService` (`NotchIconRevealService`) owns an always-present `NSPanel` at the notch; SwiftUI `.onHover` on its content triggers an on-demand scan → mirror → render, and a tap forwards to the real item via AX press with a `CGEvent.postToPid` fallback. The feature is a flag-gated service registered in `AppEnvironment`, following the `TemperatureStatusItem` pattern.

**Tech Stack:** Swift 5.9, SwiftPM (no Xcode project), AppKit + SwiftUI, CoreGraphics (`CGWindowListCopyWindowInfo`, `CGWindowListCreateImage`, `CGPreflightScreenCaptureAccess`), ApplicationServices (Accessibility), Swift Testing (`import Testing`).

## Global Constraints

- **Deployment target:** macOS 13 (`Package.swift` `platforms: [.macOS(.v13)]`). Every API used must be available on macOS 13; gate anything newer with `#available`.
- **Two-target split:** pure, side-effect-free logic goes in `QuackKit` (unit-testable, no GUI/system deps); live system calls go in the `Quack` executable target. Never import AppKit into QuackKit.
- **No new SwiftPM dependencies.** `CGWindowList*` and `CGPreflightScreenCaptureAccess` are in `CoreGraphics`, already linked on the `Quack` target. `AX*`/`CGEvent` are in `ApplicationServices`/`CoreGraphics`, already linked. Do not add packages or `.linkedFramework` entries.
- **CGEvent tap safety (CLAUDE.md):** this feature installs **no** `CGEventTap`. Hover detection is SwiftUI `.onHover`; the only `CGEvent` use is a one-shot **outgoing** `postToPid` click. Do not add a listening tap. The Accessibility dependency means: if AX is revoked, degrade to inert (panel shows nothing / clicks no-op) — reuse `PermissionsManager`'s existing accessibility observation, do not add a second AX observer or a distributed-notification watcher.
- **Status-item reuse rule (CLAUDE.md):** never remove/recreate `NSStatusItem`s to toggle features — this feature adds no status item of its own, so this constraint only means: do not disturb existing items. The panel is an `NSPanel`, not a status item.
- **Built-in display only.** All geometry targets the built-in notched screen (`NSScreen.isBuiltIn`, already defined in `BrightnessController.swift`). No external-display fallback in v1.
- **Coordinate spaces:** x-coordinates are identical between Cocoa (Y-up) and CoreGraphics (Y-down) spaces, so notch **x-span** math is coordinate-system-agnostic and belongs in QuackKit. `CGWindowList` bounds and `CGEvent`/`AX` positions are CG (Y-down, top-left); `NSPanel.setFrameOrigin` is Cocoa (Y-up). Convert only at the app-target boundary.
- **Verification reality:** pure QuackKit tasks are strict TDD via `swift test`. App-target tasks (AppKit/CG glue) are not unit-testable — their cycle is `swift build` (compiles clean) plus, for the final wiring task, manual verification on the real M4 notched MacBook via `Scripts/install.sh`. This is stated honestly per task; do not fabricate unit tests for untestable system glue.
- **Commit style:** end every commit message body with the trailer `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

---

## File Structure

**QuackKit (pure, unit-tested):**
- Create `Sources/QuackKit/Notch/NotchGeometry.swift` — `StatusItemFrame` value type; `NotchGeometry.notchSpan(...)` and `NotchGeometry.crushedItems(...)`.
- Modify `Sources/QuackKit/Permissions/PermissionStatus.swift` — add `.screenRecording` to `PermissionKind`; add `PermissionStatusMapper.screenRecording(hasAccess:)`.
- Modify `Sources/QuackKit/Models/QuackSettings.swift` — add `notchRevealEnabled` flag (stored property, init param, decoder fallback line).
- Modify `Sources/QuackKit/Coordinator/ManagedService.swift` — add `.notchReveal` to `Feature` + its `isEnabled` arm.

**Quack app (impure):**
- Create `Sources/Quack/Notch/NotchScreenReader.swift` — reads built-in `NSScreen` → `NotchGeometry.NotchSpan` + Cocoa notch rect; screen-change observer.
- Create `Sources/Quack/MenuBar/Overflow/StatusItemScanner.swift` — `CGWindowListCopyWindowInfo` → `[StatusItemFrame]` → pure classifier.
- Create `Sources/Quack/MenuBar/Overflow/StatusItemMirror.swift` — `CGWindowListCreateImage` per window → `NSImage`.
- Create `Sources/Quack/MenuBar/Overflow/StatusItemForwarder.swift` — AX press + `CGEvent.postToPid` fallback.
- Create `Sources/Quack/Notch/NotchViewModel.swift` — `ObservableObject` state (`isOpen`, `items`, callbacks).
- Create `Sources/Quack/Notch/NotchPanel.swift` — borderless nonactivating `NSPanel` subclass.
- Create `Sources/Quack/Notch/NotchRevealView.swift` — SwiftUI content + `NotchShape`.
- Create `Sources/Quack/MenuBar/Overflow/NotchIconRevealService.swift` — `ManagedService` wiring it all.
- Modify `Sources/Quack/Permissions/PermissionsManager.swift` — screen-recording refresh/request; `openSystemSettings` arm.
- Modify `Sources/Quack/AppEnvironment.swift` — construct + register the service.
- Modify `Sources/Quack/Settings/SettingsView.swift` — feature toggle + permission prompts.

**Tests:**
- Create `Tests/QuackKitTests/NotchGeometryTests.swift`.
- Modify `Tests/QuackKitTests/PermissionAndCoordinatorTests.swift` — screen-recording mapping.
- Modify `Tests/QuackKitTests/SettingsStoreTests.swift` — `notchRevealEnabled` default + decode fallback.

---

## Task 1: Notch geometry math (QuackKit, pure)

**Files:**
- Create: `Sources/QuackKit/Notch/NotchGeometry.swift`
- Test: `Tests/QuackKitTests/NotchGeometryTests.swift`

**Interfaces:**
- Consumes: nothing (pure, `CoreGraphics` types only).
- Produces:
  - `public struct StatusItemFrame: Equatable, Sendable { public let ownerPID: Int32; public let windowID: UInt32; public let frame: CGRect; public init(ownerPID: Int32, windowID: UInt32, frame: CGRect) }`
  - `public struct NotchSpan: Equatable, Sendable { public let minX: CGFloat; public let maxX: CGFloat; public var width: CGFloat }` (nested as `NotchGeometry.NotchSpan`)
  - `public static func notchSpan(screenMinX: CGFloat, screenWidth: CGFloat, leftAuxWidth: CGFloat, rightAuxWidth: CGFloat) -> NotchGeometry.NotchSpan?`
  - `public static func crushedItems(_ items: [StatusItemFrame], notch: NotchGeometry.NotchSpan) -> [StatusItemFrame]`

- [ ] **Step 1: Write the failing test**

Create `Tests/QuackKitTests/NotchGeometryTests.swift`:

```swift
import Testing
import CoreGraphics
@testable import QuackKit

@Suite struct NotchGeometryTests {

    // A 1512-wide built-in screen (14" MBP logical width) with 180pt of notch
    // flanked by two auxiliary areas.
    private let screenMinX: CGFloat = 0
    private let screenWidth: CGFloat = 1512

    @Test func notchSpanSitsBetweenTheAuxiliaryAreas() {
        let span = NotchGeometry.notchSpan(
            screenMinX: screenMinX, screenWidth: screenWidth,
            leftAuxWidth: 666, rightAuxWidth: 666
        )
        #expect(span?.minX == 666)
        #expect(span?.maxX == 846)          // 1512 - 666
        #expect(span?.width == 180)
    }

    @Test func notchSpanRespectsScreenOrigin() {
        // A built-in screen positioned to the right of an external display.
        let span = NotchGeometry.notchSpan(
            screenMinX: 1920, screenWidth: 1512,
            leftAuxWidth: 666, rightAuxWidth: 666
        )
        #expect(span?.minX == 2586)         // 1920 + 666
        #expect(span?.maxX == 2766)         // 1920 + 1512 - 666
    }

    @Test func noNotchWhenAuxiliaryWidthsAreZero() {
        #expect(NotchGeometry.notchSpan(
            screenMinX: 0, screenWidth: 1920,
            leftAuxWidth: 0, rightAuxWidth: 0
        ) == nil)
    }

    @Test func noNotchWhenOnlyOneAuxiliarySideIsPresent() {
        #expect(NotchGeometry.notchSpan(
            screenMinX: 0, screenWidth: 1512,
            leftAuxWidth: 666, rightAuxWidth: 0
        ) == nil)
    }

    @Test func crushedItemsAreThoseWhoseMidpointFallsUnderTheNotch() {
        let span = NotchGeometry.notchSpan(
            screenMinX: 0, screenWidth: 1512,
            leftAuxWidth: 666, rightAuxWidth: 666
        )!
        // visible: midX 900 (right of notch)
        let visible = StatusItemFrame(ownerPID: 1, windowID: 10,
            frame: CGRect(x: 884, y: 0, width: 32, height: 24))   // midX 900
        // crushed: midX 756 (inside 666...846)
        let crushed = StatusItemFrame(ownerPID: 2, windowID: 11,
            frame: CGRect(x: 740, y: 0, width: 32, height: 24))   // midX 756
        let result = NotchGeometry.crushedItems([visible, crushed], notch: span)
        #expect(result == [crushed])
    }

    @Test func itemExactlyOnTheNotchEdgeCountsAsCrushed() {
        let span = NotchGeometry.NotchSpan(minX: 666, maxX: 846)
        let onEdge = StatusItemFrame(ownerPID: 3, windowID: 12,
            frame: CGRect(x: 650, y: 0, width: 32, height: 24))   // midX 666 == minX
        #expect(NotchGeometry.crushedItems([onEdge], notch: span) == [onEdge])
    }

    @Test func emptyInputYieldsEmptyOutput() {
        let span = NotchGeometry.NotchSpan(minX: 666, maxX: 846)
        #expect(NotchGeometry.crushedItems([], notch: span).isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter NotchGeometryTests`
Expected: FAIL to build with "cannot find 'NotchGeometry' in scope" / "cannot find 'StatusItemFrame' in scope".

- [ ] **Step 3: Write minimal implementation**

Create `Sources/QuackKit/Notch/NotchGeometry.swift`:

```swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter NotchGeometryTests`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/QuackKit/Notch/NotchGeometry.swift Tests/QuackKitTests/NotchGeometryTests.swift
git commit -m "feat(notch): pure notch-span + crushed-item classification"
```

---

## Task 2: Screen-recording permission kind + mapper (QuackKit, pure)

**Files:**
- Modify: `Sources/QuackKit/Permissions/PermissionStatus.swift`
- Test: `Tests/QuackKitTests/PermissionAndCoordinatorTests.swift`

**Interfaces:**
- Consumes: existing `PermissionStatus`.
- Produces: `PermissionKind.screenRecording` (with `displayName` "Screen Recording"); `PermissionStatusMapper.screenRecording(hasAccess: Bool) -> PermissionStatus`.

- [ ] **Step 1: Write the failing test**

In `Tests/QuackKitTests/PermissionAndCoordinatorTests.swift`, add to the `PermissionStatusMapperTests` suite (after `accessibilityMapping`):

```swift
    @Test func screenRecordingMapping() {
        #expect(PermissionStatusMapper.screenRecording(hasAccess: true) == .granted)
        #expect(PermissionStatusMapper.screenRecording(hasAccess: false) == .notRequested)
    }

    @Test func screenRecordingIsAKnownPermissionKind() {
        #expect(PermissionKind.allCases.contains(.screenRecording))
        #expect(PermissionKind.screenRecording.displayName == "Screen Recording")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PermissionStatusMapperTests`
Expected: FAIL to build with "type 'PermissionKind' has no member 'screenRecording'".

- [ ] **Step 3: Write minimal implementation**

In `Sources/QuackKit/Permissions/PermissionStatus.swift`, add the case to `PermissionKind`:

```swift
public enum PermissionKind: String, CaseIterable, Sendable {
    case notifications
    case calendar
    case accessibility
    case screenRecording

    public var displayName: String {
        switch self {
        case .notifications: return "Notifications"
        case .calendar: return "Calendar"
        case .accessibility: return "Accessibility"
        case .screenRecording: return "Screen Recording"
        }
    }
}
```

Add the mapper function to `PermissionStatusMapper` (after `accessibility(isTrusted:)`):

```swift
    /// Screen Recording is a simple has-access / not boolean, from
    /// `CGPreflightScreenCaptureAccess()`.
    public static func screenRecording(hasAccess: Bool) -> PermissionStatus {
        hasAccess ? .granted : .notRequested
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter PermissionStatusMapperTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/QuackKit/Permissions/PermissionStatus.swift Tests/QuackKitTests/PermissionAndCoordinatorTests.swift
git commit -m "feat(permissions): add Screen Recording permission kind + mapper"
```

---

## Task 3: `notchRevealEnabled` flag + `.notchReveal` feature (QuackKit, pure)

**Files:**
- Modify: `Sources/QuackKit/Models/QuackSettings.swift`
- Modify: `Sources/QuackKit/Coordinator/ManagedService.swift`
- Test: `Tests/QuackKitTests/SettingsStoreTests.swift`

**Interfaces:**
- Consumes: existing `QuackSettings`, `Feature`.
- Produces: `QuackSettings.notchRevealEnabled: Bool` (default `false`); `Feature.notchReveal` (enabled iff `settings.notchRevealEnabled`).

- [ ] **Step 1: Write the failing test**

In `Tests/QuackKitTests/SettingsStoreTests.swift`, add to the `SettingsTests` suite:

```swift
    @Test func notchRevealDefaultsOff() {
        #expect(!QuackSettings().notchRevealEnabled)
    }

    @Test func notchRevealDecodesFromOldBlobAsDefault() throws {
        // A settings blob persisted before this field existed.
        let json = #"{"brightnessEnabled": true}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(QuackSettings.self, from: json)
        #expect(!decoded.notchRevealEnabled)   // missing key -> default false
    }

    @Test func notchRevealFeatureFollowsFlag() {
        var s = QuackSettings()
        s.notchRevealEnabled = true
        #expect(Feature.notchReveal.isEnabled(in: s))
        s.notchRevealEnabled = false
        #expect(!Feature.notchReveal.isEnabled(in: s))
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SettingsTests`
Expected: FAIL to build with "value of type 'QuackSettings' has no member 'notchRevealEnabled'".

- [ ] **Step 3: Write minimal implementation**

In `Sources/QuackKit/Models/QuackSettings.swift`:

1. Add the stored property in the "Feature flags" block (after `cpuTemperatureEnabled`):

```swift
    /// Reveal menu-bar icons hidden behind the MacBook notch in a hover panel.
    public var notchRevealEnabled: Bool
```

2. Add the init parameter (after `cpuTemperatureEnabled: Bool = false,`):

```swift
        notchRevealEnabled: Bool = false,
```

3. Add the assignment in `init(...)` (after `self.cpuTemperatureEnabled = cpuTemperatureEnabled`):

```swift
        self.notchRevealEnabled = notchRevealEnabled
```

4. Add the decoder fallback line in `init(from:)` (after `cpuTemperatureEnabled = v(.cpuTemperatureEnabled, d.cpuTemperatureEnabled)`):

```swift
        notchRevealEnabled = v(.notchRevealEnabled, d.notchRevealEnabled)
```

In `Sources/QuackKit/Coordinator/ManagedService.swift`:

1. Add the case to `Feature` (after `case temperature`):

```swift
    case notchReveal
```

2. Add the arm to `isEnabled(in:)` (after the `.temperature` arm):

```swift
        case .notchReveal: return settings.notchRevealEnabled
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SettingsTests`
Expected: PASS. Also run the full suite to confirm the new `Feature` case didn't break the coordinator tests: `swift test` → all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/QuackKit/Models/QuackSettings.swift Sources/QuackKit/Coordinator/ManagedService.swift Tests/QuackKitTests/SettingsStoreTests.swift
git commit -m "feat(notch): add notchReveal feature flag + settings field"
```

---

## Task 4: PermissionsManager screen-recording support (Quack app)

**Files:**
- Modify: `Sources/Quack/Permissions/PermissionsManager.swift`

**Interfaces:**
- Consumes: `PermissionKind.screenRecording`, `PermissionStatusMapper.screenRecording(hasAccess:)`.
- Produces: `PermissionsManager.refreshScreenRecording()`, `PermissionsManager.requestScreenRecording()`; `.screenRecording` handled in `openSystemSettings(for:)` and included in `refreshAll()`.

This task is AppKit/CoreGraphics glue — not unit-testable. Cycle is `swift build` + manual note.

- [ ] **Step 1: Add CoreGraphics import**

At the top of `Sources/Quack/Permissions/PermissionsManager.swift`, the imports include `AppKit` already; add `import CoreGraphics` if not present (it is needed for `CGPreflightScreenCaptureAccess`).

- [ ] **Step 2: Add refresh + request + settings arm**

Add `refreshScreenRecording()` into `refreshAll()`:

```swift
    func refreshAll() {
        refreshCalendar()
        refreshAccessibility()
        refreshScreenRecording()
        Task { await refreshNotifications() }
    }
```

Add the two methods (place after `refreshAccessibility()`):

```swift
    func refreshScreenRecording() {
        // Non-invasive check — does NOT prompt. `CGRequestScreenCaptureAccess`
        // (in `requestScreenRecording`) is the prompting call.
        statuses[.screenRecording] = PermissionStatusMapper.screenRecording(
            hasAccess: CGPreflightScreenCaptureAccess()
        )
    }
```

Add the request method (place after `requestAccessibilityAccess()`):

```swift
    /// Triggers the system Screen Recording prompt the first time; subsequently
    /// macOS ignores it (the user must toggle in System Settings), so callers
    /// should fall back to `openSystemSettings(for: .screenRecording)`.
    @discardableResult
    func requestScreenRecording() -> Bool {
        let granted = CGRequestScreenCaptureAccess()
        refreshScreenRecording()
        return granted
    }
```

Add the `openSystemSettings(for:)` arm (in the `switch kind`):

```swift
        case .screenRecording: anchor = "Privacy_ScreenCapture"
```

- [ ] **Step 3: Verify it builds**

Run: `swift build`
Expected: builds with no errors. (The `switch kind` in `openSystemSettings` is now exhaustive over all four `PermissionKind` cases — confirm no "switch must be exhaustive" error.)

- [ ] **Step 4: Commit**

```bash
git add Sources/Quack/Permissions/PermissionsManager.swift
git commit -m "feat(permissions): PermissionsManager Screen Recording refresh/request"
```

---

## Task 5: NotchScreenReader (Quack app)

**Files:**
- Create: `Sources/Quack/Notch/NotchScreenReader.swift`

**Interfaces:**
- Consumes: `NotchGeometry.notchSpan(...)`, `NotchGeometry.NotchSpan`, `NSScreen.isBuiltIn` (existing extension in `BrightnessController.swift`).
- Produces:
  - `struct NotchLayout { let screen: NSScreen; let span: NotchGeometry.NotchSpan; let cocoaNotchRect: CGRect }`
  - `@MainActor final class NotchScreenReader` with `func currentLayout() -> NotchLayout?`, `var onChange: (() -> Void)?`, `func startObserving()`, `func stopObserving()`.

App glue — `swift build` cycle.

- [ ] **Step 1: Write the implementation**

Create `Sources/Quack/Notch/NotchScreenReader.swift`:

```swift
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
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/Quack/Notch/NotchScreenReader.swift
git commit -m "feat(notch): NotchScreenReader for built-in notch geometry"
```

---

## Task 6: StatusItemScanner (Quack app)

**Files:**
- Create: `Sources/Quack/MenuBar/Overflow/StatusItemScanner.swift`

**Interfaces:**
- Consumes: `NotchGeometry.NotchSpan`, `NotchGeometry.crushedItems(...)`, `StatusItemFrame`.
- Produces: `enum StatusItemScanner { static func scan(notch: NotchGeometry.NotchSpan, screenXRange: ClosedRange<CGFloat>) -> [StatusItemFrame] }` returning crushed items only, sorted left-to-right by `frame.minX`, excluding Quack's own windows.

App glue — `swift build` cycle. Note: window-layer filtering (`kCGWindowLayer == 25`, the `NSStatusWindowLevel` band) is an undocumented-but-stable convention flagged in the design spec; the constant is isolated here for on-hardware tuning.

- [ ] **Step 1: Write the implementation**

Create `Sources/Quack/MenuBar/Overflow/StatusItemScanner.swift`:

```swift
import AppKit
import CoreGraphics
import QuackKit

/// Enumerates on-screen menu-bar status-item windows via the window server and
/// returns the ones the notch has crushed. Reads live `CGWindowList` data (the
/// impure half); the crushed/visible decision is delegated to the pure
/// `NotchGeometry.crushedItems`, which is unit-tested.
enum StatusItemScanner {

    /// The window layer menu-bar status items report. The system menu bar itself
    /// is layer 24 (`NSMainMenuWindowLevel`); third-party status items sit at 25
    /// (`NSStatusWindowLevel`). Isolated as a constant because it is a stable but
    /// undocumented convention that may need tuning on a future macOS.
    private static let statusWindowLayer = 25

    /// The crushed status items on the built-in screen, left-to-right. `notch`
    /// and `screenXRange` come from `NotchScreenReader.currentLayout()`.
    @MainActor
    static func scan(notch: NotchGeometry.NotchSpan, screenXRange: ClosedRange<CGFloat>) -> [StatusItemFrame] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var items: [StatusItemFrame] = []
        for info in raw {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == statusWindowLayer,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32, pid != ownPID,
                  let windowID = info[kCGWindowNumber as String] as? Int,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = cgRect(fromWindowBounds: boundsDict)
            else { continue }

            // Menu-bar band only: short windows sitting at the top of the built-in
            // screen, within its horizontal extent.
            guard bounds.height <= 40, bounds.minY <= 40,
                  bounds.midX >= screenXRange.lowerBound, bounds.midX <= screenXRange.upperBound
            else { continue }

            items.append(StatusItemFrame(ownerPID: pid, windowID: UInt32(windowID), frame: bounds))
        }

        return NotchGeometry.crushedItems(items, notch: notch)
            .sorted { $0.frame.minX < $1.frame.minX }
    }

    private static func cgRect(fromWindowBounds dict: [String: Any]) -> CGRect? {
        var rect = CGRect.zero
        return CGRectMakeWithDictionaryRepresentation(dict as CFDictionary, &rect) ? rect : nil
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/Quack/MenuBar/Overflow/StatusItemScanner.swift
git commit -m "feat(notch): StatusItemScanner for crushed menu-bar items"
```

---

## Task 7: StatusItemMirror (Quack app)

**Files:**
- Create: `Sources/Quack/MenuBar/Overflow/StatusItemMirror.swift`

**Interfaces:**
- Consumes: `StatusItemFrame` (for `windowID` and `frame`).
- Produces: `enum StatusItemMirror { static func snapshot(of item: StatusItemFrame) -> NSImage? }`.

App glue — `swift build` cycle.

- [ ] **Step 1: Write the implementation**

Create `Sources/Quack/MenuBar/Overflow/StatusItemMirror.swift`:

```swift
import AppKit
import CoreGraphics
import QuackKit

/// Captures a live pixel snapshot of a single status-item window, so the reveal
/// panel shows exactly what the notch is hiding (real battery %, Wi-Fi state,
/// etc.) rather than a generic app icon. Requires Screen Recording permission;
/// returns nil without it, and the caller then omits that item.
enum StatusItemMirror {

    /// A snapshot of just this status item's window. `CGWindowListCreateImage`
    /// is deprecated on macOS 14 in favour of ScreenCaptureKit, but remains
    /// functional through current macOS and is far simpler for a single tiny
    /// capture; ScreenCaptureKit migration is deferred. Returns nil if Screen
    /// Recording is not granted (the call yields nil in that case on 14+).
    static func snapshot(of item: StatusItemFrame) -> NSImage? {
        let cgImage = CGWindowListCreateImage(
            .null,                                   // use the window's own bounds
            .optionIncludingWindow,
            item.windowID,
            [.boundsIgnoreFraming, .bestResolution]
        )
        guard let cgImage else { return nil }
        return NSImage(cgImage: cgImage, size: item.frame.size)
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: builds (a deprecation warning for `CGWindowListCreateImage` on the toolchain's SDK is acceptable and expected — do not treat it as an error).

- [ ] **Step 3: Commit**

```bash
git add Sources/Quack/MenuBar/Overflow/StatusItemMirror.swift
git commit -m "feat(notch): StatusItemMirror snapshots hidden status items"
```

---

## Task 8: StatusItemForwarder (Quack app)

**Files:**
- Create: `Sources/Quack/MenuBar/Overflow/StatusItemForwarder.swift`

**Interfaces:**
- Consumes: `StatusItemFrame` (for `frame` center and `ownerPID`).
- Produces: `enum StatusItemForwarder { static func forward(to item: StatusItemFrame) }`.

App glue — `swift build` cycle.

- [ ] **Step 1: Write the implementation**

Create `Sources/Quack/MenuBar/Overflow/StatusItemForwarder.swift`:

```swift
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
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/Quack/MenuBar/Overflow/StatusItemForwarder.swift
git commit -m "feat(notch): StatusItemForwarder clicks hidden items via AX + CGEvent"
```

---

## Task 9: NotchViewModel + NotchPanel + NotchRevealView (Quack app UI)

**Files:**
- Create: `Sources/Quack/Notch/NotchViewModel.swift`
- Create: `Sources/Quack/Notch/NotchPanel.swift`
- Create: `Sources/Quack/Notch/NotchRevealView.swift`

**Interfaces:**
- Consumes: `StatusItemFrame`.
- Produces:
  - `struct NotchItem: Identifiable { let id: UInt32; let image: NSImage; let source: StatusItemFrame }`
  - `@MainActor final class NotchViewModel: ObservableObject` with `@Published var isOpen: Bool`, `@Published var items: [NotchItem]`, `var onHoverChange: ((Bool) -> Void)?`, `var onTap: ((StatusItemFrame) -> Void)?`.
  - `final class NotchPanel: NSPanel` with `init(contentRect: NSRect)`.
  - `struct NotchRevealView: View` (takes `@ObservedObject var model: NotchViewModel`) and `struct NotchShape: Shape`.

App UI glue — `swift build` cycle; behavior verified in Task 11.

- [ ] **Step 1: Write the view model**

Create `Sources/Quack/Notch/NotchViewModel.swift`:

```swift
import AppKit
import Combine
import QuackKit

/// One revealed icon: a live snapshot of a crushed status item plus the source
/// frame needed to forward a click back to it.
struct NotchItem: Identifiable {
    let id: UInt32          // the source window ID (stable per status item)
    let image: NSImage
    let source: StatusItemFrame
}

/// Observable state for the notch reveal panel. The service sets `items` after a
/// scan and reacts to `onHoverChange` / `onTap`; the SwiftUI view renders it.
@MainActor
final class NotchViewModel: ObservableObject {
    @Published var isOpen = false
    @Published var items: [NotchItem] = []

    /// Called when the cursor enters (true) or leaves (false) the panel content.
    var onHoverChange: ((Bool) -> Void)?
    /// Called when a revealed icon is tapped.
    var onTap: ((StatusItemFrame) -> Void)?
}
```

- [ ] **Step 2: Write the panel**

Create `Sources/Quack/Notch/NotchPanel.swift`:

```swift
import AppKit

/// A borderless, non-activating floating panel anchored at the notch. It sits
/// above the menu bar (`.mainMenu + 3`) but never becomes key/main, so it never
/// steals focus from the app underneath. Mirrors the `ToastPresenter` panel
/// recipe, raised a few levels so notch content overlaps the menu-bar band.
final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
```

- [ ] **Step 3: Write the view + shape**

Create `Sources/Quack/Notch/NotchRevealView.swift`:

```swift
import SwiftUI
import QuackKit

/// A rounded-bottom "notch" shape: square top corners (flush with the screen
/// edge) and rounded bottom corners, so the expanded panel reads as growing out
/// of the physical notch.
struct NotchShape: Shape {
    var bottomRadius: CGFloat = 12

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(bottomRadius, rect.height, rect.width / 2)
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY),
                       control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r),
                       control: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// The reveal panel's content: when hovered, a black rounded strip showing the
/// mirrored crushed icons in a row; each tappable to forward the click. When not
/// hovered it collapses to a bare notch-width sliver that only detects hover.
struct NotchRevealView: View {
    @ObservedObject var model: NotchViewModel

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { hovering in model.onHoverChange?(hovering) }
    }

    @ViewBuilder
    private var content: some View {
        if model.isOpen && !model.items.isEmpty {
            HStack(spacing: 10) {
                ForEach(model.items) { item in
                    Image(nsImage: item.image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 18)
                        .onTapGesture { model.onTap?(item.source) }
                        .help("Reveal hidden menu bar item")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(NotchShape().fill(Color.black))
        } else {
            // Collapsed: invisible hover target the width of the notch.
            Color.black.opacity(0.001)
        }
    }
}
```

- [ ] **Step 4: Verify it builds**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 5: Commit**

```bash
git add Sources/Quack/Notch/NotchViewModel.swift Sources/Quack/Notch/NotchPanel.swift Sources/Quack/Notch/NotchRevealView.swift
git commit -m "feat(notch): reveal panel, view model, and notch shape"
```

---

## Task 10: NotchIconRevealService (Quack app, ManagedService)

**Files:**
- Create: `Sources/Quack/MenuBar/Overflow/NotchIconRevealService.swift`

**Interfaces:**
- Consumes: `NotchScreenReader`, `StatusItemScanner`, `StatusItemMirror`, `StatusItemForwarder`, `NotchPanel`, `NotchViewModel`, `NotchRevealView`, `SettingsStore`, `PermissionsManager`; conforms to `ManagedService`.
- Produces: `@MainActor final class NotchIconRevealService: NSObject, ManagedService` with `init(settings: SettingsStore, permissions: PermissionsManager)` and `start()` / `stop()`.

App glue — `swift build` cycle; end-to-end behavior verified in Task 11.

- [ ] **Step 1: Write the implementation**

Create `Sources/Quack/MenuBar/Overflow/NotchIconRevealService.swift`:

```swift
import AppKit
import SwiftUI
import Combine
import QuackKit

/// Wires the notch reveal feature together: owns the always-present panel at the
/// notch, positions it on the built-in screen, and on hover runs an on-demand
/// scan → mirror → render, forwarding taps to the real hidden items.
///
/// Lifecycle follows `TemperatureStatusItem`: the panel is created once and
/// shown/hidden via `orderFront`/`orderOut` rather than recreated. No event tap
/// is installed (hover is SwiftUI `.onHover`), so the CLAUDE.md freeze rules do
/// not apply; the only Accessibility dependency is the click-forward, which
/// simply no-ops when AX is not granted.
@MainActor
final class NotchIconRevealService: NSObject, ManagedService {
    private let settings: SettingsStore
    private let permissions: PermissionsManager

    private let reader = NotchScreenReader()
    private let model = NotchViewModel()
    private var panel: NotchPanel?

    /// Collapsed panel height (bare hover sliver at the notch height ~ menu bar).
    private let collapsedHeight: CGFloat = 24
    /// Expanded panel height (room for a row of mirrored icons below the notch).
    private let expandedHeight: CGFloat = 40

    init(settings: SettingsStore, permissions: PermissionsManager) {
        self.settings = settings
        self.permissions = permissions
        super.init()
    }

    func start() {
        guard reader.currentLayout() != nil else {
            // No built-in notch → feature inert; still observe in case a notched
            // screen is (re)connected while enabled.
            reader.onChange = { [weak self] in self?.repositionOrTeardown() }
            reader.startObserving()
            return
        }
        buildPanelIfNeeded()
        model.onHoverChange = { [weak self] hovering in self?.handleHover(hovering) }
        model.onTap = { [weak self] item in self?.handleTap(item) }
        reader.onChange = { [weak self] in self?.repositionOrTeardown() }
        reader.startObserving()
        reposition()
    }

    func stop() {
        reader.stopObserving()
        reader.onChange = nil
        panel?.orderOut(nil)
        panel = nil
        model.isOpen = false
        model.items = []
    }

    // MARK: - Panel lifecycle

    private func buildPanelIfNeeded() {
        guard panel == nil else { return }
        let p = NotchPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: collapsedHeight))
        let host = NSHostingView(rootView: NotchRevealView(model: model))
        host.frame = p.contentView!.bounds
        host.autoresizingMask = [.width, .height]
        p.contentView?.addSubview(host)
        panel = p
    }

    /// Re-place the panel at the current notch, or tear down if the built-in
    /// notch went away (e.g. clamshell / display change).
    private func repositionOrTeardown() {
        guard reader.currentLayout() != nil else {
            panel?.orderOut(nil)
            model.isOpen = false
            return
        }
        buildPanelIfNeeded()
        reposition()
    }

    /// Positions the panel centered on the notch, its top flush with the screen
    /// top. Width grows when open so a row of icons has room; stays notch-width
    /// when collapsed. Cocoa (Y-up) coordinates.
    private func reposition() {
        guard let layout = reader.currentLayout(), let panel else { return }
        let width = model.isOpen ? max(layout.span.width, contentWidth()) : layout.span.width
        let height = model.isOpen ? expandedHeight : collapsedHeight
        let centerX = layout.cocoaNotchRect.midX
        let originX = centerX - width / 2
        let originY = layout.screen.frame.maxY - height   // top-anchored
        panel.setFrame(NSRect(x: originX, y: originY, width: width, height: height), display: true)
        panel.orderFrontRegardless()
    }

    private func contentWidth() -> CGFloat {
        // ~28pt per icon (18pt image + spacing) plus horizontal padding.
        CGFloat(model.items.count) * 28 + 32
    }

    // MARK: - Interaction

    private func handleHover(_ hovering: Bool) {
        if hovering {
            // Refresh permissions non-invasively; prompt for Screen Recording
            // once if missing (the pixel mirror needs it).
            permissions.refreshScreenRecording()
            if permissions.status(for: .screenRecording) != .granted {
                _ = permissions.requestScreenRecording()
            }
            model.items = scanAndMirror()
            model.isOpen = true
        } else {
            model.isOpen = false
            model.items = []
        }
        reposition()
    }

    private func scanAndMirror() -> [NotchItem] {
        guard let layout = reader.currentLayout() else { return [] }
        let xRange = layout.screen.frame.minX...layout.screen.frame.maxX
        let crushed = StatusItemScanner.scan(notch: layout.span, screenXRange: xRange)
        return crushed.compactMap { item in
            guard let image = StatusItemMirror.snapshot(of: item) else { return nil }
            return NotchItem(id: item.windowID, image: image, source: item)
        }
    }

    private func handleTap(_ item: StatusItemFrame) {
        guard permissions.status(for: .accessibility) == .granted else {
            permissions.requestAccessibilityAccess()
            return
        }
        StatusItemForwarder.forward(to: item)
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/Quack/MenuBar/Overflow/NotchIconRevealService.swift
git commit -m "feat(notch): NotchIconRevealService wiring scan/mirror/forward"
```

---

## Task 11: Wire into AppEnvironment + Settings UI (Quack app)

**Files:**
- Modify: `Sources/Quack/AppEnvironment.swift`
- Modify: `Sources/Quack/Settings/SettingsView.swift`

**Interfaces:**
- Consumes: `NotchIconRevealService`, `Feature.notchReveal`, `QuackSettings.notchRevealEnabled`, `PermissionKind.screenRecording`.
- Produces: the running feature — registered in the coordinator's service map and toggleable from Settings.

Final integration — `swift build` + **manual verification on the real M4 notched MacBook**.

- [ ] **Step 1: Register the service in AppEnvironment**

In `Sources/Quack/AppEnvironment.swift`:

1. Add the stored property (after `private let temperatureService: TemperatureStatusItem`):

```swift
    private let notchRevealService: NotchIconRevealService
```

2. Construct it in `init` (after `self.temperatureService = TemperatureStatusItem(settings: settings)`):

```swift
        self.notchRevealService = NotchIconRevealService(settings: settings, permissions: permissions)
```

3. Add it to the `services` map (after `.temperature: temperatureService,`):

```swift
            .notchReveal: notchRevealService,
```

- [ ] **Step 2: Add the settings toggle**

In `Sources/Quack/Settings/SettingsView.swift`, the `.windows` tab already renders `WindowSwipeSection`, `DockGesturesSection`, `KeyboardShortcutsSection`. Add a new section to that tab. First, add the section to the pane (in `SettingsPane.body`, the `.windows` case):

```swift
            case .windows:
                WindowSwipeSection()
                DockGesturesSection()
                KeyboardShortcutsSection()
                NotchRevealSection()
```

Then add the section view (place after `DockGesturesSection`):

```swift
// MARK: - Notch reveal

private struct NotchRevealSection: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        let s = env.settingsStore
        Section("Notch") {
            Toggle("Reveal menu bar icons hidden behind the notch", isOn: s.binding(\.notchRevealEnabled))
            Text("Move the pointer to the notch to reveal icons the notch is covering, then click one to open it. Built-in display only.")
                .font(.system(size: 12)).foregroundStyle(.secondary)

            if s.settings.notchRevealEnabled {
                if env.permissions.status(for: .screenRecording) != .granted {
                    HStack {
                        Text("Needs Screen Recording to show the hidden icons.")
                            .font(.system(size: 12)).foregroundStyle(.orange)
                        Button("Grant") { _ = env.permissions.requestScreenRecording() }
                    }
                }
                if env.permissions.status(for: .accessibility) != .granted {
                    HStack {
                        Text("Needs Accessibility to click a revealed icon.")
                            .font(.system(size: 12)).foregroundStyle(.orange)
                        Button("Grant") { env.permissions.requestAccessibilityAccess() }
                    }
                }
            }
        }
    }
}
```

(The Permissions tab's `PermissionsSection` already iterates `PermissionKind.allCases`, so a "Screen Recording" row with an "Open Settings" button now appears there automatically — no change needed.)

- [ ] **Step 3: Verify it builds**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 4: Run the full test suite (guard against regressions)**

Run: `swift test`
Expected: all suites PASS (QuackKit changes from Tasks 1–3 plus untouched existing suites).

- [ ] **Step 5: Install and manually verify on hardware**

Run: `Scripts/install.sh`

Then verify on the built-in notched display:
1. Open Quack Settings → Windows → Notch, enable "Reveal menu bar icons hidden behind the notch".
2. Grant Screen Recording and Accessibility when prompted (or via Settings → Permissions). Per CLAUDE.md, do NOT re-run `install.sh` right after granting — just relaunch: `open /Applications/Quack.app`.
3. Add enough menu bar icons that some are crushed behind the notch (or temporarily widen with other menu-bar apps).
4. Move the pointer to the notch — the panel should expand and show the hidden icons as live snapshots.
5. Click a revealed icon — its real menu (e.g. Wi-Fi, battery) should open.
6. Move the pointer away — the panel collapses.
7. Toggle the feature off in Settings — the panel disappears; toggle on — it returns.

Expected: each step behaves as described. Note in the commit any per-app click-forward misses (accepted per the spec's open risks) and whether the `statusWindowLayer`/band heuristics in `StatusItemScanner` needed adjustment for this hardware.

- [ ] **Step 6: Commit**

```bash
git add Sources/Quack/AppEnvironment.swift Sources/Quack/Settings/SettingsView.swift
git commit -m "feat(notch): register reveal service + settings toggle"
```

---

## Self-Review

**Spec coverage** (checked against `docs/superpowers/specs/2026-07-01-notch-icon-reveal-design.md`):

| Spec item | Task |
|---|---|
| Automatic detection of crushed icons | Tasks 1, 6 |
| Notch geometry via `safeAreaInsets` / `auxiliaryTop{Left,Right}Area` | Tasks 1, 5 |
| Hover-activated panel at the notch | Tasks 9, 10 |
| Live pixel mirror of hidden icons | Task 7 |
| Click forwarding (AX press → CGEvent fallback) | Task 8 |
| Built-in display only | Tasks 5, 10 (`isBuiltIn`, nil-when-no-notch) |
| Screen Recording permission (new) | Tasks 2, 4, 11 |
| Accessibility reused, degrade-on-revoke | Tasks 8, 10 (no-op when not granted) |
| No CGEvent tap / no freeze-rule surface | Tasks 8, 10 (outgoing `postToPid` only) |
| Feature flag + coordinator lifecycle | Tasks 3, 10, 11 |
| `NotchGeometry` math unit-tested | Task 1 |
| `StatusItemScanner` classification unit-tested (pure half) | Task 1 (`crushedItems`) |
| Manual hardware verification | Task 11 |
| No new dependencies | Global Constraints (verified: all APIs in already-linked frameworks) |

Non-goals held: no fence/drag reorg, no external-display fallback, no notifications, no media/clipboard (those are sub-project 2).

**Placeholder scan:** none — every step has concrete code or an exact command with expected output.

**Type consistency:** `StatusItemFrame` (QuackKit, Task 1) is consumed unchanged by Tasks 6/7/8/9/10. `NotchGeometry.NotchSpan` flows Task 1 → 5 (produced) → 6/10 (consumed). `NotchItem` (Task 9) is produced by Task 10's `scanAndMirror()` and consumed by `NotchRevealView` (Task 9). Method names align: `notchSpan`, `crushedItems`, `scan(notch:screenXRange:)`, `snapshot(of:)`, `forward(to:)`, `currentLayout()`, `refreshScreenRecording()`, `requestScreenRecording()`. `Feature.notchReveal` / `QuackSettings.notchRevealEnabled` / `PermissionKind.screenRecording` consistent across Tasks 3/4/10/11.
