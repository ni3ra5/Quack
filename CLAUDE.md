# Quack — project notes for contributors (and AI agents)

A native macOS menu-bar utility (SwiftPM, no Xcode project). Build/run with
`./Scripts/install.sh` — see "Seeing changes" below.

## ⚠️ CRITICAL: CGEvent input taps must not freeze the Mac

Quack intercepts input with active `CGEvent` taps (F1/F2 brightness routing,
⌘⌥+arrow window shortcuts, two-finger swipe). Done naively, **toggling Quack's
Accessibility permission freezes the entire Mac** (all mouse/keyboard input
hangs). This cost ~15 debugging rounds. Follow BOTH rules for every tap:

1. **Run the tap on a dedicated background thread — never `CFRunLoopGetMain()`.**
   An active tap on the main run loop gates every input event through the main
   thread; any stall (a slow DDC/AX call, the TCC transition) freezes all input.
   Use `EventTapThread` (or `BrightnessKeyTap`). Do slow work (DDC writes, AX
   window moves) off the tap thread via `DispatchQueue.main.async`.

2. **Use MonitorControl's stop/recreate lifecycle** (the only thing that fully
   fixed it — mirrors `macmade/MonitorControl`'s `MediaKeyTapManager`):
   - Observe the `com.apple.accessibility.api` distributed notification.
   - On ANY change, after a **0.1s delay**, **fully stop AND recreate** the tap
     (new instance; the old one's port is `CFMachPortInvalidate`d).
   - **Never gate on `AXIsProcessTrusted()`** — it returns STALE values right
     after a toggle (brightness kept working seconds after Accessibility was
     turned off). `CGEvent.tapCreate` itself returns nil when not trusted, so
     recreating unconditionally is safe.
   - **Never re-enable on `tapDisabledByUserInput`** (that's the revoke event;
     re-enabling loops and freezes). Only re-enable on `tapDisabledByTimeout`.
   - Never leave a stale disabled-but-alive tap: macOS reactivates it on the
     next grant and that reactivation freezes input.

**Reference implementation:** `CursorBrightnessService.reinstallKeyTap`. Each tap
is individually switchable in `Sources/Quack/Windows/InputTaps.swift`.
`.listenOnly` taps don't gate input (can't freeze), but use the same lifecycle
for consistency.

## ⚠️ Moving/resizing Chromium windows (Chrome, Claude, Electron)

Chromium-based apps turn on `AXEnhancedUserInterface` as soon as an assistive
client attaches. While it is on, Chromium handles `AXPosition`/`AXSize` itself:
it animates them (the window visibly jitters) and clamps the result to its own,
often stale, idea of the display work area — a fill on a 2560x1440 external came
back as 2560x1326, and sometimes at the *built-in* screen's size. Native apps
(Finder, Slack) are unaffected, which makes it look like a geometry bug.

`WindowMover.animate` therefore, per move: turns `AXEnhancedUserInterface` off,
applies the frame, turns it back on. Two more rules it relies on:

- **Grow only after the move.** AppKit clamps a window to the screen it is
  currently on, measured from its current origin, so a resize issued before the
  move is truncated (2560 wide asked at x = -130 gave 2280) and the later move
  does not restore it. Shrinks are safe to apply up front.
- **Set origin → size → origin, verify, retry** — but stop as soon as the app
  returns the same size twice; that is its real maximum and retrying only makes
  the window jitter.

## Seeing changes / TCC

- `swift build` only produces the dev binary. The **running app is the installed
  bundle** at `/Applications/Quack.app` — run `./Scripts/install.sh` to rebuild
  and relaunch it. UI/behavior changes won't appear otherwise.
- TCC (Accessibility) grants persist across rebuilds via the stable
  "Quack Local Signing" identity, but a fresh rebuild may need the grant
  re-affirmed once. If a tap won't install, `AXIsProcessTrusted()` is false —
  re-toggle Quack in System Settings → Privacy & Security → Accessibility.
- Don't run `install.sh` (which rebuilds) right after the user grants
  Accessibility — rebuilding changes the binary and can drop the grant. Just
  relaunch the existing bundle (`open /Applications/Quack.app`).
