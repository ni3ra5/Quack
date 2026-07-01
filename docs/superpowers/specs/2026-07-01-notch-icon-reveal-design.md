# Notch Icon Reveal — Design Spec

- **Date:** 2026-07-01
- **Status:** ⚠️ SHELVED (2026-07-01) after on-hardware verification — see note below.
- **Sub-project:** 1 of 2 (see [Relationship to sub-project 2](#relationship-to-sub-project-2))

> **SHELVED — why.** The implementation was built and reviewed (branch `Knock-Notch`),
> but on-hardware verification (macOS 26.5.1, M4) proved the core mechanism cannot
> work. A standalone probe (`scratchpad/notch-probe.swift`) confirmed: (1) menu-bar
> extras are owned by the system *Control Center* process, not their apps; and
> (2) macOS drops overflow items from layout entirely — a notch-hidden item has NO
> on-screen window to scan, screenshot, or forward a click to. So
> `StatusItemScanner`/`StatusItemMirror`/`StatusItemForwarder` return/target nothing
> by construction. Source-level research into Ice/Thaw confirmed the only working
> technique is to *take over* the whole menu bar (own-spacer + private SkyLight/CGS
> APIs + a two-hop CGEvent "scromble" + — on macOS 26 — an XPC Accessibility-tree
> service to recover source PIDs), which is product-scale, private-API-dependent, and
> breaks per macOS release (Ice has open unresolved Tahoe bugs). Decision: shelve the
> Quack-native icon manager (recommend users run Thaw), and reuse the **working notch
> panel shell** (`NotchGeometry`/`NotchScreenReader`/`NotchPanel`/`NotchViewModel`/
> `NotchShape`) for sub-project 2 (dynamic notch: media + clipboard), which does not
> fight the OS. Panel positioning is verified working (probe saw it at layer 27,
> exactly under the notch); whether SwiftUI `.onHover` fires there is still unproven
> and is the first thing sub-project 2 must de-risk.

## Problem

On notched MacBook Pros (M-series, including the target M4 machine), third-party
menu bar icons that grow past the available width get crushed by the notch —
`NSStatusItem.isVisible` still reports `true`, so there is no API signal that an
icon has become invisible. The user wants to see and interact with whatever is
currently hidden.

## Prior art (research summary)

Surveyed 14 open-source projects (full brief: repos + technique citations kept
in the session that produced this spec, not duplicated here). Key takeaways
that shape this design:

- **Ice / Thaw** (jordanbaird/Ice, stonerl/Thaw) solve this with a fence status
  item + `CGEvent`-synthesized drag to physically reorder other apps' icons,
  plus a second floating panel ("Ice Bar"/"Thaw Bar") that mirrors hidden
  icons. Ice's own source has retry/fallback machinery (`wakeUpItem`, dual-hop
  event posting) — synthetic event delivery to other apps' status items is
  inherently unreliable per-app.
- **Hidden Bar**'s own architecture doc documents that pure geometry tricks
  (inflating a spacer item) *cannot* reach icons already under the notch —
  confirms a mirror-panel approach is necessary, not optional.
- Notch geometry detection converges on the same public `NSScreen` APIs
  everywhere (`safeAreaInsets`, `auxiliaryTopLeftArea`/`auxiliaryTopRightArea`,
  stable since macOS 12).
- No project found reads another app's status item pixels without Screen
  Recording permission — this is a real, new permission surface for Quack.

## Scope decomposition

The original ask bundled four sub-problems: notch icon reveal, a hover-driven
notch panel, now-playing media, and clipboard history. These split into two
independent sub-projects because they touch different subsystems and carry
different risk:

1. **This spec** — icon reveal behind the notch (MenuBar overflow detection +
   a notch-anchored panel shell).
2. **Future spec** — now-playing media + clipboard history as additional
   content modes inside the same panel shell. Deferred; see
   [Relationship to sub-project 2](#relationship-to-sub-project-2).

## Goals (v1)

- Detect which menu bar icons are currently crushed by the notch, automatically
  — no manual zone configuration required from the user.
- Reveal them in a panel anchored at the notch, opened by hovering the cursor
  there.
- Show each hidden icon as a **live pixel mirror** of its real rendered state
  (not a generic app-icon substitute) — confirmed with the user, who accepted
  the Screen Recording permission this requires.
- Clicking a mirrored icon **forwards the click** to the real item so its
  actual menu opens (Wi-Fi list, battery detail, etc.) — full interactivity,
  not read-only.
- Built-in display only.

## Non-goals (v1)

- No manual fence/drag-to-reorganize UI (Ice/Thaw/Bartender-style zone
  management). Detection is automatic and geometry-driven.
- No support for external, non-notched displays. If `NotchGeometry` finds no
  notch, the feature is simply inert on that screen.
- No notifications or proactive alerts when a new icon becomes hidden.
- No now-playing media or clipboard content in the panel — that is
  sub-project 2, built as additional modes on top of the same shell.

## User-facing behavior

1. User moves the cursor to the notch. A small panel that already lives there
   (present but visually minimal when closed) expands.
2. The panel shows, as live mirrored icons, whichever real status items are
   currently crushed by the notch at that moment (computed fresh each time the
   panel opens — not continuously polled in the background).
3. Clicking a mirrored icon forwards a synthetic activation to the real item.
   If that item supports it, its native menu/detail view opens as normal.
4. Moving the cursor away closes the panel.

## Architecture

```
Sources/Quack/Notch/
  NotchGeometry.swift       — safeAreaInsets / auxiliaryTop{Left,Right}Area
                               wrapper. Live-updates on
                               NSApplication.didChangeScreenParametersNotification.
                               Returns nil on non-notched screens; callers treat
                               nil as "feature inactive here," not an error.
  NotchPanel.swift           — NSPanel subclass: isFloatingPanel = true,
                               isOpaque = false, backgroundColor = .clear,
                               hasShadow = false, isMovable = false,
                               canBecomeKey/canBecomeMain = false,
                               level = .mainMenu + 3,
                               collectionBehavior = [.canJoinAllSpaces, .stationary,
                               .fullScreenAuxiliary, .ignoresCycle].
                               Always present at the notch's frame; sized to the
                               closed (minimal) state until hover expands it.
  NotchViewModel.swift        — @Published state: .closed / .open. Driven by
                               SwiftUI .onHover on the panel's own content —
                               no CGEvent mouse-moved tap needed, since the
                               panel already sits at the notch and the cursor
                               must physically enter its bounds.
  NotchShape.swift             — animatable custom Shape for the closed↔open
                               morph (corner radii as animatableData).

Sources/Quack/MenuBar/Overflow/
  StatusItemScanner.swift      — Enumerates status-bar-level windows via
                               CGWindowListCopyWindowInfo, cross-references each
                               frame against NotchGeometry's safe-area rects to
                               classify "crushed" vs "visible." Excludes windows
                               owned by Quack's own process (see
                               AXHelpers.isOwnWindow for the existing precedent).
                               Runs on-demand when the panel opens, not on a
                               background timer.
  StatusItemMirror.swift       — For each crushed window, calls
                               CGWindowListCreateImage scoped to that window's ID
                               to get a snapshot for display. Requires Screen
                               Recording permission (new TCC grant, see
                               Permissions below).
  StatusItemForwarder.swift    — Click forwarding, layered:
                               1. AXUIElementPerformAction(kAXPressAction) on the
                                  AX element at the item's real position — same
                                  idiom as the existing AXHelpers.close/minimize.
                               2. Only if the AX press did NOT succeed, fall back
                                  to a CGEvent leftMouseDown/leftMouseUp pair
                                  posted via postToPid at the item's real frame
                                  (Ice's proven technique).
                               A successful AXPress returns immediately WITHOUT
                               also firing the synthetic click — firing a click
                               after AX already opened the menu would risk
                               dismissing it or mis-triggering a menu item
                               (decided during final review, 2026-07-01; this
                               supersedes an earlier draft that fired the
                               fallback unconditionally). The residual risk is an
                               AX "success" on a wrong element short-circuiting
                               the fallback — accepted, to watch during hardware
                               testing.
```

### Data flow

```
cursor enters NotchPanel bounds
  → SwiftUI .onHover fires → NotchViewModel.state = .open
  → StatusItemScanner.scan() (fresh, on-demand)
      → NotchGeometry gives the current safe-area rects
      → classify each enumerated status-bar window as crushed / not
  → for each crushed window: StatusItemMirror.snapshot(windowID)
  → NotchPanel renders one button per crushed item, image = snapshot
  → user clicks a button
      → StatusItemForwarder.forward(to: item.frame)
          → AXUIElementPerformAction(kAXPressAction); if it succeeds, return
          → else CGEvent leftMouseDown/Up via postToPid (fallback only)
  → cursor leaves panel bounds → NotchViewModel.state = .closed
```

## Permissions

- **Accessibility** — already required by Quack for existing features. Reused
  here for `AXUIElementCopyElementAtPosition` / `AXUIElementPerformAction`
  (via the existing `AXHelpers` module) and as a prerequisite for the
  `CGEvent.postToPid` fallback.
- **Screen Recording** — **new** for Quack. Required by
  `CGWindowListCreateImage` to read another app's status-item pixels. Surface
  this through the existing `PermissionsManager`, following the same
  "explain, then send the user to System Settings" pattern already used for
  Accessibility. This is a distinct TCC category from Accessibility and needs
  its own explanatory copy — users will see a second, separate system prompt.

### Relationship to Quack's CGEvent tap safety rules

CLAUDE.md's hard-won tap rules (dedicated background thread, stop/recreate
lifecycle on Accessibility toggle) apply to **active `CGEventTap` input taps**
that gate the main run loop. This feature does not install one:

- Hover detection is SwiftUI `.onHover` / `NSTrackingArea` on an
  always-present panel, not a global input tap.
- The `CGEvent.postToPid` fallback is a one-shot **outgoing** synthetic event,
  not a persistent listening tap — it does not gate other input and cannot
  freeze the Mac the way a stalled tap on the main run loop can.

The one real dependency to carry over: this feature requires Accessibility,
so if the user revokes it mid-session, `StatusItemScanner`/`StatusItemForwarder`
must degrade to "feature inactive" (panel just shows nothing / clicks no-op)
rather than crashing or spinning — reuse `PermissionsManager`'s existing
Accessibility-state observation for this, do not add a second AX observer.

## Error handling / degradation

| Condition | Behavior |
|---|---|
| No notch on this screen | `NotchGeometry` returns nil; panel never activates on that screen. Not an error. |
| Scan finds zero crushed items | Panel opens with nothing to show. Not an error. |
| AX press + CGEvent fallback both fail to trigger a menu | No detectable failure signal exists; click is a silent no-op. Matches the reality every surveyed project ships with. |
| Accessibility revoked mid-session | Feature goes inactive via `PermissionsManager`'s existing observation; no crash. |
| Screen Recording not granted | `StatusItemMirror` returns no image; item is simply omitted from the panel rather than shown broken. |

## Testing / verification

- This class of behavior (real notch geometry, real crushed icons) only
  reproduces on real hardware — verify manually on the target M4 MacBook Pro,
  not in CI.
- Unit-testable in isolation, with fixture data (no real screen/AX needed):
  - `NotchGeometry` math against fixture `NSScreen`-shaped inputs.
  - `StatusItemScanner`'s crushed/not-crushed classification given fixture
    window-info arrays and fixture safe-area rects.

## Open risks carried into implementation

- Per-app click-forward reliability will vary — some apps' status items may
  not respond to either `AXPress` or the synthetic `CGEvent`. Accepted per
  Error handling above; the exact crushed/not-crushed pixel threshold will
  also need empirical tuning against real hardware during implementation.
- Screen Recording adds a second permission the user must grant before the
  feature does anything useful.
- Enumerating other apps' status-bar windows via `CGWindowListCopyWindowInfo`
  relies on window-layer conventions that are stable but undocumented; a
  future macOS release could shift them. Lower risk than Ice's live-reordering
  approach specifically because this design never moves another app's window,
  it only reads position/pixels and posts a click.

## Relationship to sub-project 2

The `Notch/` shell built here (`NotchPanel`, `NotchViewModel`, `NotchGeometry`,
`NotchShape`) is deliberately generic — sub-project 2 (now-playing media +
clipboard history) will add further `NotchViewModel` states/content modes to
the same panel rather than building a second overlay window. Not specified
further here; will get its own design doc when brainstormed.
