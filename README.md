# Quack 🦆

A native macOS menu-bar utility. Lives in the menu bar (no Dock icon), shows
your next meeting with a live countdown, fires click-to-join reminders, and
bundles two display utilities — cursor-based external-monitor brightness and a
title-bar swipe to fling a window to another monitor.

Every feature is individually toggleable. Services start **only** when their
toggle is on, so if you only want the brightness feature you never see a
Calendar or Notifications prompt.

## Features

| Feature | What it does | Permission |
|---|---|---|
| **Menu-bar countdown** | Next/in-progress meeting + live `· 5m` countdown | — |
| **Calendar** | Reads events via EventKit. Manage which calendars/accounts sync (toggle individually or whole accounts) | Calendar |
| **Reminders** | Local notifications at configurable lead times, with a **Join** button that opens Zoom/Meet/Teams links | Notifications |
| **External brightness** | The Mac brightness keys (F1/F2) control whichever external display the cursor is on, over DDC/CI | Accessibility¹ (Apple Silicon) |
| **Window swipe** | Two-finger trackpad swipe over a window's title bar flings it to the next monitor (either direction) | Accessibility |

¹ The brightness slider and "dim inactive display" work without Accessibility;
only intercepting the F1/F2 keys needs it (to consume the key so the built-in
display doesn't also change).

## Requirements

- macOS 13 Ventura or later
- Apple Silicon for the brightness feature (DDC/CI via `IOAVService`). Intel
  Macs run everything else; brightness reports "unavailable on this Mac".
- An external display that supports **DDC/CI** for brightness control. Many do;
  some monitors and most USB-C hubs do not. The settings panel shows
  "DDC supported / not supported" per display.

## Install

Builds with **Swift Package Manager** — no full Xcode required, just Command
Line Tools (`xcode-select --install`).

```bash
# Build AND install to /Applications (recommended — see note below)
Scripts/install.sh
```

`install.sh` quits any running copy, builds a release bundle, installs it to
`/Applications/Quack.app`, and resets stale permission grants so the new copy
prompts cleanly. The menu-bar duck appears at the top-right; open **Settings…**
to enable features one at a time.

> **Why install to /Applications matters.** macOS ties Accessibility/Calendar
> permissions to an app's bundle id *and* signature at a fixed path. Running
> from the build folder, or re-signing on every rebuild, makes grants silently
> stop working (macOS may still show Quack as "allowed" while it does nothing).
> Always run via `install.sh` and grant permissions to the installed copy. Each
> reinstall resets the grants, so you re-approve once per install.

Other scripts:

```bash
swift test                 # run the logic tests (no hardware needed)
Scripts/build-app.sh       # just build build/Quack.app (debug; CONFIG=release for release)
Scripts/package-dmg.sh     # wrap build/Quack.app in a drag-to-Applications DMG
Scripts/make-icon.sh       # regenerate Resources/AppIcon.icns from Resources/AppIcon-source.png
```

### Verify it's working

Stream Quack's own logs while you use it:

```bash
log stream --predicate 'subsystem == "com.quack.menubar"' --level debug
```

You'll see lines like `Brightness key tap installed`, `Scroll gesture tap
installed`, `refreshDisplays: 1 external screen(s), 1 DDC service(s)`, and
`swipe right -> move ok`. If a tap fails to install, the log says so (almost
always means Accessibility isn't effective yet).

### Brightness with F1 / F2

With the brightness feature on and Accessibility granted, moving the cursor onto
an external display and pressing the Mac brightness keys adjusts **that monitor**
over DDC; the built-in display is left alone. On the built-in display the keys
behave normally. Step size is configurable in Settings.

### Managing calendar accounts

In Settings → Calendar, turn off "Sync all calendars" to choose exactly which
accounts and calendars feed the menu bar and reminders — toggle a whole account
or individual calendars. **Add or remove accounts…** opens System Settings →
Internet Accounts (macOS owns account creation; Quack reads whatever is there).

## Permissions

- **Calendar / Notifications** — requested automatically the first time you
  enable the matching feature.
- **Accessibility** (window swipe + F1/F2 brightness routing) — cannot be
  granted programmatically. Click **Grant** in Settings; macOS opens System
  Settings → Privacy & Security → Accessibility, where you flip Quack on. Quack
  detects the change by polling.

If you ever deny a permission, each Settings section has an **Open Settings**
button that deep-links to the right pane.

## Signing & distribution (Developer ID + notarization)

`Scripts/build-app.sh` ad-hoc signs by default (fine for local use). To produce
a distributable DMG:

```bash
# 1. Sign with hardened runtime using your Developer ID
SIGN_ID="Developer ID Application: Your Name (TEAMID)" \
  CONFIG=release Scripts/build-app.sh

# 2. Package as a DMG
hdiutil create -volname Quack -srcfolder build/Quack.app -ov -format UDZO build/Quack.dmg

# 3. Notarize and staple
xcrun notarytool submit build/Quack.dmg \
  --apple-id you@example.com --team-id TEAMID --password "app-specific-pw" --wait
xcrun stapler staple build/Quack.dmg
```

**No App Sandbox** — the entitlements (`Resources/Quack.entitlements`)
deliberately omit it, because the sandbox blocks DDC over IOKit and cross-app
Accessibility window moving. That is why Quack ships as a direct notarized DMG
rather than through the Mac App Store.

## Architecture

```
QuackKit (library, fully unit-tested — no system/UI deps)
  Models/        MeetingEvent, QuackSettings
  Settings/      SettingsStore (+ injectable KeyValueStore)
  Calendar/      CalendarProvider, MeetingSelection, MeetingStore, MeetingURLParser
  Reminders/     ReminderPlan (pure scheduling + diff)
  MenuBar/       CountdownFormatter
  Display/       ScreenGeometry (cursor→screen, swipe targeting),
                 TrackpadSwipe (finger-delta normalization), BrightnessMath
  Permissions/   PermissionStatusMapper
  Coordinator/   AppCoordinator, ManagedService, Feature

Quack (executable — SwiftUI + AppKit + system frameworks)
  QuackApp / AppEnvironment      composition root, MenuBarExtra, Settings scene
  Calendar/  EventKitProvider, CalendarRefreshService
  Reminders/ ReminderScheduler (UNUserNotificationCenter), NotificationDelegate
  Display/   CursorBrightnessService, BrightnessController, DDCControl
  Windows/   GestureMonitor (CGEventTap), WindowMover, AXHelpers
  Permissions/ PermissionsManager
  MenuBar/   MenuBarLabelView, MenuContentView
  Settings/  SettingsView (one section per feature)

CDDC (C target)  DDC/CI brightness over the private IOAVService API (m1ddc-style)
```

The design keeps all decision logic in `QuackKit` behind protocols and pure
functions, so it is unit-testable without hardware or permissions. The app
target wires that logic to the live system frameworks. An `AppCoordinator`
observes `SettingsStore` and starts/stops each service as flags flip —
guaranteeing a disabled feature never triggers its permission prompt.

### What can't be unit-tested

DDC brightness (`DDCControl`/`CDDC`) and window moving (`AXHelpers`,
`GestureMonitor`) require real hardware and granted permissions. The
*geometry and selection math* behind them lives in `QuackKit.ScreenGeometry`
and **is** covered by tests; only the IOKit/Accessibility I/O is manual.

## Status / roadmap

Implemented: menu-bar shell, settings, EventKit calendar, reminders + join
toast, countdown, cursor-based brightness, window swipe, permissions, app
bundling & signing.

Not yet implemented (staged): **Google Calendar API** (Step 7) — EventKit
already surfaces Google calendars added to macOS, so this is only needed for
accounts not in the system. The `CalendarProvider` protocol is the extension
point; add a `GoogleCalendarProvider` (OAuth 2.0 + PKCE, tokens in Keychain).
