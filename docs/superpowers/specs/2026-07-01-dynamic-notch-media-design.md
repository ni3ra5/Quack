# Dynamic Notch — Media Player — Design Spec

- **Date:** 2026-07-01
- **Status:** Approved (design), not yet implemented
- **Branch:** `Notch-Media` (off `main`)
- **Sub-project:** 2 of 2 — media mode (clipboard mode is a later, separate spec)

## Problem

The user wants a "dynamic notch": hovering the MacBook notch reveals useful
controls. This spec covers the first mode — a **now-playing media player** for
whatever app currently owns system media (Music, Spotify, a browser tab, a
podcast app): show the track and control playback without leaving the current
app or hunting for the source app's window.

## Context: what changed before this spec

Sub-project 1 (reveal menu-bar icons hidden behind the notch) was **built,
reviewed, and then shelved** after on-hardware verification (macOS 26.5.1, M4)
proved its mechanism impossible: menu-bar extras are owned by the system
*Control Center* process and macOS drops overflow items from layout entirely, so
there is no under-notch window to scan/screenshot/click. See
`2026-07-01-notch-icon-reveal-design.md` (marked SHELVED) for the full account.

Two durable results carry into this sub-project:

1. **The notch panel shell works.** A standalone probe confirmed the panel
   positions correctly, and a hover spike (`scratchpad/hover-spike.swift`)
   confirmed SwiftUI `.onHover` fires reliably (24 hits) on a borderless
   `.nonactivatingPanel` at level `.mainMenu + 3` sitting at the notch. **No
   hit-test-window workaround is needed.**
2. **Geometry correction.** The shelved code placed its collapsed target 24 pt
   tall *exactly at the notch span* — which is the physical camera-housing
   cutout (no visible pixels, unhoverable). This sub-project's panel must anchor
   its visible/hoverable content **below** the notch cutout (top-anchored, but
   extending down into visible screen).

## Goals (v1)

- Hovering the notch reveals a panel **below** it showing the current track:
  album art, title, artist.
- **Full transport controls**: play/pause, next, previous — driven from the
  panel.
- System-wide now-playing (app-agnostic), via MediaRemote through a **vendored**
  perl/`com.apple.perl` adapter (see Architecture).
- **Pure hover-to-reveal**: nothing shown when not hovering; panel auto-hides on
  mouse-leave.
- Built-in (notched) display only.
- Degrade to a quiet "Nothing playing" state whenever media info is
  unavailable — never crash.

## Non-goals (v1)

- **No scrubber / seek.** Seeking is the exact call that regressed in the
  adapter on macOS 26.2; it is the flakiest piece and is deliberately excluded.
- **No always-on "live activity" peek.** The notch is normal until hover; an
  always-visible album-art sliver is a possible later enhancement, not v1.
- **No clipboard mode.** That is the next sub-project, a separate spec, reusing
  this same shell + a mode switch.
- No volume control, no queue/playlist, no audio visualizer, no lyrics.
- No external-display support.

## User-facing behavior

1. Media is playing in any app. The notch looks normal.
2. User moves the pointer to the notch. A panel animates down from below the
   notch showing album art + title + artist and three controls (⏮ ⏯ ⏭).
3. Controls act on the real media immediately (play/pause toggles; skip changes
   track); the panel updates to the new track.
4. Pointer leaves → panel hides.
5. Nothing playing (or media info unavailable) → the panel, on hover, shows a
   quiet "Nothing playing" state rather than being empty or absent.

## Architecture

### Reused shell (cherry-picked from the shelved `Knock-Notch` branch)

- `Sources/QuackKit/Notch/NotchGeometry.swift` — pure notch-span math (already
  unit-tested). Reused unchanged.
- `Sources/Quack/Notch/NotchScreenReader.swift` — built-in-screen notch geometry
  + screen-change observer. Reused; the panel positioning that consumes it is
  corrected to hang content below the notch.
- `Sources/Quack/Notch/NotchPanel.swift` — borderless nonactivating panel,
  `.mainMenu + 3`, never key/main. Reused unchanged.
- `Sources/Quack/Notch/NotchShape.swift` — animatable rounded-bottom shape.
  Reused.

The shelved icon-reveal-specific files (`StatusItemScanner`, `StatusItemMirror`,
`StatusItemForwarder`, `NotchIconRevealService`, `NotchRevealView`, and the
`notchRevealEnabled` flag / `.notchReveal` feature / Screen-Recording permission)
are **left behind** — not cherry-picked.

### New — pure logic (QuackKit, unit-tested)

- `Sources/QuackKit/NowPlaying/TrackInfo.swift` — value type: `title`, `artist`,
  `album`, `isPlaying`, `artworkData: Data?` (format-agnostic — the adapter
  returns base64 + a mime type; decode to `NSImage` at the app layer), plus
  timing fields. `Equatable`, `Sendable`.
- `Sources/QuackKit/NowPlaying/NowPlayingReducer.swift` — pure functions over
  `TrackInfo`: "should the panel show a track vs. nothing-playing", and
  (later-proofed) elapsed-time interpolation from `playbackRate` + a supplied
  `now` timestamp. No system dependencies; fully testable with fixtures.

### New — vendored adapter (no remote SwiftPM dependency)

- `Sources/CMediaRemoteAdapter/` (or a `Resources/` bundle) — the vendored
  pieces of `ejbills/mediaremote-adapter`: the `run.pl` perl script, the small
  Objective-C framework that resolves MediaRemote symbols via
  `CFBundleGetFunctionPointerForName`, and its headers. Committed into the repo
  (pinned; no supply-chain surprise). Exact packaging (SPM C target vs. copied
  resource bundle) is a plan-level detail; the constraint is: **vendored, not a
  remote dependency**, and Quack stays otherwise zero-remote-dep.

### New — app integration

- `Sources/Quack/NowPlaying/NowPlayingService.swift` — spawns the vendored
  adapter (`Process` → `/usr/bin/perl` → `run.pl`), decodes its line-delimited
  JSON into `TrackInfo`, and publishes it (Combine `@Published` /
  `ObservableObject`). Sends transport commands (play/pause/next/previous) back
  through the adapter. **Isolated behind a protocol** so a future adapter/OS
  break degrades to "no info", never propagates. No event tap, no run-loop
  source (CLAUDE.md freeze rules do not apply).
- `Sources/Quack/Notch/NotchMediaViewModel.swift` — `@MainActor ObservableObject`:
  `isOpen`, current `TrackInfo?`, hover + tap callbacks. (Parallels the shell's
  view-model pattern.)
- `Sources/Quack/Notch/NotchMediaView.swift` — SwiftUI: album art + title/artist
  + three transport buttons; `.onHover` drives open/close; buttons call the
  service. "Nothing playing" state when `TrackInfo` is nil.
- `Sources/Quack/Notch/NotchMediaService.swift` — the `ManagedService` that owns
  the panel (created once, `orderFront`/`orderOut`), positions it below the
  notch, wires hover → show, and bridges `NowPlayingService` ↔ view model.
- Wiring: `notchMediaEnabled` flag in `QuackSettings`; `.notchMedia` `Feature`
  case + `isEnabled`; registration in `AppEnvironment`'s services map; a
  settings toggle (Windows or a new "Notch" tab). Same coordinator-driven
  lifecycle as `TemperatureStatusItem`.

### Data flow

```
media plays (any app)
  → NowPlayingService: perl+adapter stream → line-delimited JSON → TrackInfo (@Published)
  → NotchMediaService bridges TrackInfo → NotchMediaViewModel
cursor enters notch panel
  → SwiftUI .onHover → viewModel.isOpen = true → panel animates down, shows current TrackInfo
  → user taps ⏯ / ⏭ / ⏮ → NowPlayingService sends MediaRemote command via adapter
  → adapter stream reports the new state → TrackInfo updates → panel re-renders
cursor leaves → viewModel.isOpen = false → panel hides
```

## Permissions

**None.** The perl/`com.apple.perl` adapter borrows Perl's implicit
Apple-internal entitlement, so no Screen Recording and no Accessibility grant is
required. This is strictly simpler than the shelved icon-reveal (which needed
both). No new TCC surface.

## Distribution

Compatible with Quack's model (unsandboxed, notarized, direct/DMG). Spawning
`/usr/bin/perl` + loading a private-framework resolver is **not** App-Store /
sandbox compatible — consistent with Quack already shipping outside the App
Store. Note this in code comments so a future sandboxed build variant isn't
attempted.

## Error handling / degradation

| Condition | Behavior |
|---|---|
| No built-in notch (external only / clamshell) | Panel inactive on that screen. Not an error. |
| Nothing playing | Panel on hover shows a quiet "Nothing playing" state. |
| Adapter spawn fails / returns no data | `NowPlayingService` publishes nil; panel shows "Nothing playing". Logged once, not repeatedly. |
| Adapter breaks on a future macOS | Same soft-fail path (isolated behind the protocol). Feature goes quiet; rest of Quack unaffected. |
| A transport command fails | No-op; the stream's next update reconciles the displayed state. |

## Testing / verification

- **First plan task is a hardware checkpoint:** vendor the adapter and prove it
  returns a live track (and that a play/pause command lands) on this Mac
  (macOS 26.5.1) **before** any UI is built on it. If it cannot read
  now-playing here, stop and reassess — do not build UI on an unproven adapter.
- **Pure unit tests (QuackKit):** `TrackInfo` decode/round-trip;
  `NowPlayingReducer` show-vs-nothing logic and elapsed-time interpolation with
  fixtures. No system deps.
- **Hardware manual verification (final task):** hover reveals the player,
  controls act on real media, panel hides on leave, "Nothing playing" shows when
  idle — on the built-in notched display.
- App-target glue (service, panel, view) is `swift build` + manual verify, not
  unit-tested (consistent with the codebase).

## Branch strategy

Build on `Notch-Media` (off `main`). Implementation's first step cherry-picks the
four reusable shell files from `Knock-Notch`; everything else is new. The shelved
icon-reveal code is never brought over. `Knock-Notch` is retained (not merged,
not deleted) as the record of the shelved sub-project 1.

## Relationship to the next sub-project (clipboard)

The clipboard-history mode will reuse this exact shell (`NotchPanel`,
`NotchScreenReader`, `NotchGeometry`, `NotchShape`, and the below-notch
positioning) plus a mode switch in the panel. It is out of scope here and gets
its own spec once the media mode is verified on hardware.
