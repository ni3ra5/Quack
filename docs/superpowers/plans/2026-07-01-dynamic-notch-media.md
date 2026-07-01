# Dynamic Notch — Media Player Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hovering the MacBook notch reveals a panel below it showing the current track (art, title, artist) with play/pause and next/previous, driving system-wide media on macOS 26.

**Architecture:** Reuse the hover-proven notch panel shell (cherry-picked from the shelved `Knock-Notch` branch, geometry-corrected to hang below the notch cutout). Read/control media through a **vendored** copy of `ejbills/mediaremote-adapter` (perl + a small ObjC dylib that resolves private MediaRemote symbols), isolated behind a fail-soft service. Pure display logic lives in QuackKit (unit-tested); the adapter, panel, and view are app-target glue verified by `swift build` + on-hardware checks.

**Tech Stack:** Swift 5.9, SwiftPM (no Xcode), AppKit + SwiftUI, a vendored ObjC target compiled `-fno-objc-arc`, `/usr/bin/perl` at runtime, Swift Testing (`import Testing`).

## Global Constraints

- **Deployment target:** macOS 13 (`Package.swift` `platforms: [.macOS(.v13)]`). The vendored adapter is macOS 10.15+, so it composes.
- **Two-target split:** pure, side-effect-free logic → `QuackKit` (unit-tested, no AppKit). Live system calls → the `Quack` executable target (or the vendored adapter targets).
- **Vendored, not remote:** the MediaRemote adapter source is **copied into this repo** (pinned upstream `ejbills/mediaremote-adapter` @ `cf30c4f1af29b5829d859f088f8dbdf12611a046`, BSD-3-Clause). Do **not** add a remote SwiftPM `dependencies:` entry. Preserve the upstream BSD-3 license/attribution alongside the vendored files.
- **No new *remote* dependency; new *local* targets are expected** (`CIMediaRemote`, `MediaRemoteAdapter`).
- **No permissions:** the perl/`com.apple.perl` mechanism needs no TCC grant (no Screen Recording, no Accessibility). Do not add any permission prompt for this feature.
- **No CGEvent tap / run-loop source** anywhere in this feature (CLAUDE.md freeze rules). Media control is `Process`/pipe I/O; hover is SwiftUI `.onHover`.
- **Notch geometry:** content must hang **below** the notch cutout (the shelved code's 24px-at-exact-notch target sat in the invisible camera housing). Panel is top-anchored but extends down into visible screen.
- **Built-in display only** (`NSScreen.isBuiltIn`, existing extension in `BrightnessController.swift`). Nil notch layout → feature inert, not an error.
- **Distribution:** unsandboxed, notarized, direct/DMG only — spawning perl + loading a private-framework resolver is not App-Store/sandbox compatible. Note this in code comments.
- **Environment build quirk:** in some sandboxes `swift build`/`swift test` prints `accessing build database ".build/build.db": disk I/O error` and exits non-zero **even though** it also prints `Build complete!` / tests pass. If the only error is that db line and the build/tests otherwise succeeded, treat it as success and retry once; it is not a code failure.
- **Commit trailer:** end every commit message body with `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- **Verification reality:** QuackKit pure logic = strict TDD via `swift test`. App-target/adapter glue = `swift build` + explicit on-hardware checks (Tasks 2 and 8). Do not fabricate unit tests for the perl/AppKit glue.

---

## File Structure

**Cherry-picked from `Knock-Notch` (reused shell):**
- `Sources/QuackKit/Notch/NotchGeometry.swift` (+ `Tests/QuackKitTests/NotchGeometryTests.swift`) — pure notch-span math, unchanged.
- `Sources/Quack/Notch/NotchScreenReader.swift` — built-in notch geometry + screen-change observer, unchanged.
- `Sources/Quack/Notch/NotchPanel.swift` — borderless nonactivating panel, unchanged.
- `Sources/Quack/Notch/NotchShape.swift` — extracted from the shelved `NotchRevealView.swift` (the `NotchShape` struct only).

**Vendored adapter (copied from pinned upstream):**
- `Sources/CIMediaRemote/` — `MediaRemote.m`, `MediaRemoteAdapter.m`, `MediaRemoteAdapterKeys.m`, `include/*.h` (3 headers), plus `LICENSE`.
- `Sources/MediaRemoteAdapter/` — `MediaController.swift`, `TrackInfo.swift`, `Resources/run.pl`, plus `LICENSE`.

**New (QuackKit, pure):**
- `Sources/QuackKit/NowPlaying/NowPlayingDisplay.swift` — pure elapsed-time interpolation + show/nothing decision. (+ `Tests/QuackKitTests/NowPlayingDisplayTests.swift`.)

**New (Quack app):**
- `Sources/Quack/NowPlaying/NowPlayingService.swift` — protocol + concrete wrapper over `MediaController`; `@Published` track; fail-soft.
- `Sources/Quack/Notch/NotchMediaViewModel.swift` — `@MainActor ObservableObject` panel state.
- `Sources/Quack/Notch/NotchMediaView.swift` — SwiftUI player (art + text + 3 buttons).
- `Sources/Quack/MenuBar/NotchMediaService.swift` — `ManagedService`, owns panel, hover→show, bridges service↔viewmodel.

**Modified:**
- `Package.swift` — add `CIMediaRemote` + `MediaRemoteAdapter` targets; `Quack` depends on `MediaRemoteAdapter`.
- `Scripts/build-app.sh` — bundle the built adapter dylib + `run.pl` resource into `Quack.app` so runtime paths resolve.
- `Sources/QuackKit/Models/QuackSettings.swift` — add `notchMediaEnabled` flag.
- `Sources/QuackKit/Coordinator/ManagedService.swift` — add `.notchMedia` Feature.
- `Sources/Quack/AppEnvironment.swift` — construct + register `NotchMediaService`.
- `Sources/Quack/Settings/SettingsView.swift` — add the toggle.

---

## Task 1: Cherry-pick the reusable notch shell

**Files:**
- Create (from `Knock-Notch`): `Sources/QuackKit/Notch/NotchGeometry.swift`, `Tests/QuackKitTests/NotchGeometryTests.swift`, `Sources/Quack/Notch/NotchScreenReader.swift`, `Sources/Quack/Notch/NotchPanel.swift`
- Create (new): `Sources/Quack/Notch/NotchShape.swift`

**Interfaces:**
- Produces: `QuackKit.NotchGeometry` (`notchSpan(...)`, `NotchSpan`, `StatusItemFrame`); `NotchScreenReader` (`currentLayout() -> NotchLayout?`, `onChange`, `startObserving()`, `stopObserving()`, `NotchLayout{screen,span,cocoaNotchRect}`); `NotchPanel(contentRect:)`; `NotchShape(bottomRadius:)`.

- [ ] **Step 1: Restore the reused files from `Knock-Notch`**

```bash
git checkout Knock-Notch -- \
  Sources/QuackKit/Notch/NotchGeometry.swift \
  Tests/QuackKitTests/NotchGeometryTests.swift \
  Sources/Quack/Notch/NotchScreenReader.swift \
  Sources/Quack/Notch/NotchPanel.swift
```

- [ ] **Step 2: Extract `NotchShape` into its own file**

The shelved `NotchRevealView.swift` bundled `NotchShape` with icon-reveal UI we are not reusing. Create `Sources/Quack/Notch/NotchShape.swift` with only the shape:

```swift
import SwiftUI

/// A rounded-bottom "notch" shape: square top corners (flush with the screen
/// edge), rounded bottom corners, so the expanded panel reads as growing out of
/// the notch.
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
```

- [ ] **Step 3: Verify build + reused tests**

Run: `swift build` then `swift test --filter NotchGeometryTests`
Expected: build clean (modulo the build.db quirk); 7 NotchGeometry tests pass. (`NotchScreenReader`/`NotchPanel`/`NotchShape` are self-contained — they reference nothing icon-reveal-specific.)

- [ ] **Step 4: Commit**

```bash
git add Sources/QuackKit/Notch Tests/QuackKitTests/NotchGeometryTests.swift Sources/Quack/Notch
git commit -m "feat(notch): cherry-pick reusable notch shell for media panel"
```

---

## Task 2: Vendor the MediaRemote adapter + Package/build wiring + HARDWARE CHECKPOINT

> **This is the risk gate.** The whole feature depends on the adapter reading now-playing on macOS 26.5.1. Getting the vendored dylib + `run.pl` to resolve inside Quack's hand-assembled `.app` is the fiddly part and may need iteration. **If the checkpoint (Step 6) cannot read a live track, STOP and report — do not build UI on an unproven adapter.**

**Files:**
- Create: `Sources/CIMediaRemote/*` and `Sources/MediaRemoteAdapter/*` (copied from the pinned clone)
- Modify: `Package.swift`, `Scripts/build-app.sh`

**Interfaces:**
- Produces: `import MediaRemoteAdapter` → `MediaController` (`getTrackInfo(_:)`, `startListening()`, `stopListening()`, `togglePlayPause()`, `nextTrack()`, `previousTrack()`, `onTrackInfoReceived`) and `TrackInfo` (`payload` with `title/artist/album/isPlaying/artwork/…`).

- [ ] **Step 1: Copy the vendored files verbatim from the pinned clone**

Source of truth (pinned): `ejbills/mediaremote-adapter` @ `cf30c4f1af29b5829d859f088f8dbdf12611a046`, available at `/private/tmp/claude-501/-Users-strativ-Repositories-Quack/b28c7e2e-5453-4d1b-bbf5-79b5a17e6ddc/scratchpad/mediaremote-adapter`. Copy verbatim (these are upstream files, not authored here):

```bash
SRC=/private/tmp/claude-501/-Users-strativ-Repositories-Quack/b28c7e2e-5453-4d1b-bbf5-79b5a17e6ddc/scratchpad/mediaremote-adapter
mkdir -p Sources/CIMediaRemote/include Sources/MediaRemoteAdapter/Resources
cp "$SRC"/Sources/CIMediaRemote/*.m               Sources/CIMediaRemote/
cp "$SRC"/Sources/CIMediaRemote/include/*.h        Sources/CIMediaRemote/include/
cp "$SRC"/Sources/MediaRemoteAdapter/MediaController.swift Sources/MediaRemoteAdapter/
cp "$SRC"/Sources/MediaRemoteAdapter/TrackInfo.swift       Sources/MediaRemoteAdapter/
cp "$SRC"/Sources/MediaRemoteAdapter/Resources/run.pl      Sources/MediaRemoteAdapter/Resources/
```

Preserve attribution: create `Sources/MediaRemoteAdapter/LICENSE` (and `Sources/CIMediaRemote/LICENSE`) containing the upstream BSD-3-Clause text (the `run.pl` header credits "Copyright (c) 2025 Jonas van den Berg"); if the clone has no root `LICENSE`, reconstruct the standard BSD-3-Clause text with that copyright line. Add a one-line `Sources/MediaRemoteAdapter/VENDORED.md` noting the repo URL + pinned commit `cf30c4f`.

- [ ] **Step 2: Add the two targets to `Package.swift`**

Add these targets to the `targets:` array, and add `"MediaRemoteAdapter"` to the `Quack` executable target's `dependencies`:

```swift
        // Vendored (ejbills/mediaremote-adapter @ cf30c4f, BSD-3-Clause):
        // ObjC resolver for private MediaRemote symbols. Compiled without ARC.
        .target(
            name: "CIMediaRemote",
            publicHeadersPath: "include",
            cSettings: [.unsafeFlags(["-fno-objc-arc"])],
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedFramework("AppKit"),
            ]
        ),
        // Vendored: Swift controller that spawns /usr/bin/perl + run.pl to load
        // the CIMediaRemote dylib and stream/command now-playing over pipes.
        .target(
            name: "MediaRemoteAdapter",
            dependencies: ["CIMediaRemote"],
            resources: [.copy("Resources/run.pl")]
        ),
```

In the `Quack` executable target, add `"MediaRemoteAdapter"` to `dependencies: ["QuackKit", "CDDC", "CMultitouch", "CSMC"]` → `[..., "MediaRemoteAdapter"]`.

- [ ] **Step 3: Confirm it compiles as a library**

Run: `swift build` (modulo build.db quirk).
Expected: `CIMediaRemote` (ObjC, no-ARC) and `MediaRemoteAdapter` compile; `Quack` links. If the ObjC target errors on missing frameworks, confirm the `.linkedFramework` lines above are present.

- [ ] **Step 4: Bundle the adapter into `Quack.app` in `build-app.sh`**

`MediaController` resolves `run.pl` via `Bundle.module` and the dylib via `Bundle(for: MediaController.self).executablePath`. Because Quack is hand-assembled (not Xcode), `Scripts/build-app.sh` must copy the SwiftPM-built adapter dylib **and** its resource bundle into the app so those lookups resolve at runtime. After the `cp "${BUILD_DIR}/${APP_NAME}" …` line, add:

```bash
# Vendored MediaRemoteAdapter: copy its dynamic lib + resource bundle so the
# perl adapter can locate run.pl (Bundle.module) and the dylib
# (Bundle(for:).executablePath) at runtime.
FW_DIR="${APP_DIR}/Contents/Frameworks"
mkdir -p "${FW_DIR}"
# The SwiftPM build products live in ${BUILD_DIR}; names may be
# libMediaRemoteAdapter.dylib and MediaRemoteAdapter_MediaRemoteAdapter.bundle.
for artifact in "${BUILD_DIR}"/libMediaRemoteAdapter.dylib \
                "${BUILD_DIR}"/MediaRemoteAdapter_MediaRemoteAdapter.bundle \
                "${BUILD_DIR}"/*MediaRemoteAdapter*.bundle; do
    [ -e "$artifact" ] && cp -R "$artifact" "${FW_DIR}/" 2>/dev/null || true
done
echo "▸ Bundled MediaRemoteAdapter artifacts into ${FW_DIR}"
```

> **Note (may need iteration):** exact artifact names/locations from SwiftPM can vary; after Step 5, inspect `.build/release/` and adjust the globs so the dylib and the `run.pl`-containing bundle actually land in the app. This is the expected fiddly part.

- [ ] **Step 5: Build + install the app bundle**

Run: `Scripts/install.sh` (or, if the build.db quirk aborts it, the manual assemble+sign+install sequence — see `.superpowers/sdd/progress.md` "workaround" — then `swift build -c release --product Quack || true` first).
Expected: `/Applications/Quack.app` installed and launched; `Contents/Frameworks/` contains the adapter dylib and the `run.pl` bundle.

- [ ] **Step 6: HARDWARE CHECKPOINT — prove the adapter reads now-playing**

Start playing something (Music/Spotify/a YouTube tab). Then run a one-shot harness that exercises the *vendored* `MediaController` exactly as the app will. Create `Sources/Quack/Diagnostics/nowplaying-probe` is overkill — instead run this throwaway from the repo root using the built module path:

```bash
cat > /tmp/nowplaying_probe.swift <<'SWIFT'
import Foundation
import MediaRemoteAdapter
let mc = MediaController()
let sem = DispatchSemaphore(value: 0)
mc.getTrackInfo { info in
    if let p = info?.payload {
        print("✅ NOW PLAYING: \(p.title ?? "?") — \(p.artist ?? "?") playing=\(String(describing: p.isPlaying)) art=\(p.artwork != nil)")
    } else {
        print("❌ nil — nothing playing OR adapter can't read")
    }
    sem.signal()
}
_ = sem.wait(timeout: .now() + 5)
SWIFT
swift run --package-path . 2>/dev/null || \
  swiftc /tmp/nowplaying_probe.swift -I .build/release/Modules -L .build/release -lMediaRemoteAdapter -o /tmp/nowplaying_probe && DYLD_LIBRARY_PATH=.build/release /tmp/nowplaying_probe
```

> If linking the throwaway is awkward, an acceptable alternative is to temporarily add a hidden `--nowplaying-probe` launch argument to `AppDelegate` that calls `MediaController().getTrackInfo { print(...) ; exit(0) }`, run the installed app with that arg from Terminal, observe stdout, then remove it before committing.

Expected: prints the real current track. **If it prints nil while media is definitely playing, STOP** — the adapter does not work on this OS; report to the controller/human before any further tasks.

- [ ] **Step 7: Commit**

```bash
git add Sources/CIMediaRemote Sources/MediaRemoteAdapter Package.swift Scripts/build-app.sh
git commit -m "feat(media): vendor mediaremote-adapter + bundle wiring (hardware-verified read)"
```

---

## Task 3: Pure now-playing display logic (QuackKit, TDD)

**Files:**
- Create: `Sources/QuackKit/NowPlaying/NowPlayingDisplay.swift`
- Test: `Tests/QuackKitTests/NowPlayingDisplayTests.swift`

**Interfaces:**
- Produces:
  - `public struct NowPlayingSnapshot: Equatable, Sendable { public let title: String?; public let artist: String?; public let isPlaying: Bool; public let elapsedMicros: Double?; public let timestampEpochMicros: Double?; public let playbackRate: Double?; public init(...) }`
  - `public enum NowPlayingDisplay { public static func hasTrack(_ s: NowPlayingSnapshot) -> Bool; public static func elapsedSeconds(_ s: NowPlayingSnapshot, nowEpochSeconds: Double) -> Double? }`

- [ ] **Step 1: Write the failing test**

Create `Tests/QuackKitTests/NowPlayingDisplayTests.swift`:

```swift
import Testing
@testable import QuackKit

@Suite struct NowPlayingDisplayTests {
    private func snap(title: String? = "T", playing: Bool = true,
                      elapsed: Double? = nil, ts: Double? = nil, rate: Double? = nil) -> NowPlayingSnapshot {
        NowPlayingSnapshot(title: title, artist: "A", isPlaying: playing,
                           elapsedMicros: elapsed, timestampEpochMicros: ts, playbackRate: rate)
    }

    @Test func hasTrackWhenTitlePresent() {
        #expect(NowPlayingDisplay.hasTrack(snap(title: "Song")))
        #expect(!NowPlayingDisplay.hasTrack(snap(title: nil)))
        #expect(!NowPlayingDisplay.hasTrack(snap(title: "")))
    }

    @Test func elapsedNilWhenNoTiming() {
        #expect(NowPlayingDisplay.elapsedSeconds(snap(), nowEpochSeconds: 1000) == nil)
    }

    @Test func elapsedIsRawWhenPaused() {
        // paused: elapsed = elapsedMicros/1e6, no interpolation
        let s = snap(playing: false, elapsed: 30_000_000, ts: 900, rate: 1)
        #expect(NowPlayingDisplay.elapsedSeconds(s, nowEpochSeconds: 1000) == 30)
    }

    @Test func elapsedInterpolatesWhenPlaying() {
        // playing: 30s at ts=900, rate 1, now=1000 → 30 + (1000-900)*1 = 130
        let s = snap(playing: true, elapsed: 30_000_000, ts: 900, rate: 1)
        #expect(NowPlayingDisplay.elapsedSeconds(s, nowEpochSeconds: 1000) == 130)
    }

    @Test func elapsedUsesRateWhenPlaying() {
        // rate 0 → no advance
        let s = snap(playing: true, elapsed: 30_000_000, ts: 900, rate: 0)
        #expect(NowPlayingDisplay.elapsedSeconds(s, nowEpochSeconds: 1000) == 30)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter NowPlayingDisplayTests`
Expected: FAIL to build ("cannot find 'NowPlayingSnapshot'/'NowPlayingDisplay'").

- [ ] **Step 3: Write minimal implementation**

Create `Sources/QuackKit/NowPlaying/NowPlayingDisplay.swift`:

```swift
import Foundation

/// A coordinate-free snapshot of now-playing state — the scalar fields the panel
/// needs, decoupled from the vendored adapter's AppKit-bearing `TrackInfo` so the
/// display math stays pure and testable (mirrors ScreenGeometry vs WindowMover).
public struct NowPlayingSnapshot: Equatable, Sendable {
    public let title: String?
    public let artist: String?
    public let isPlaying: Bool
    public let elapsedMicros: Double?
    public let timestampEpochMicros: Double?
    public let playbackRate: Double?

    public init(title: String?, artist: String?, isPlaying: Bool,
                elapsedMicros: Double?, timestampEpochMicros: Double?, playbackRate: Double?) {
        self.title = title; self.artist = artist; self.isPlaying = isPlaying
        self.elapsedMicros = elapsedMicros; self.timestampEpochMicros = timestampEpochMicros
        self.playbackRate = playbackRate
    }
}

public enum NowPlayingDisplay {
    /// Whether there is a real track to show (vs. the "Nothing playing" state).
    public static func hasTrack(_ s: NowPlayingSnapshot) -> Bool {
        !(s.title ?? "").isEmpty
    }

    /// Current elapsed seconds. When playing, interpolates from the last reported
    /// elapsed + rate * (now - reportTimestamp); when paused, the raw elapsed.
    /// Pure: caller supplies `nowEpochSeconds`. Mirrors the adapter's own
    /// `currentElapsedTime`, minus its `Date()` call, so it can be unit-tested.
    public static func elapsedSeconds(_ s: NowPlayingSnapshot, nowEpochSeconds: Double) -> Double? {
        guard let elapsedMicros = s.elapsedMicros else { return nil }
        let elapsed = elapsedMicros / 1_000_000
        guard s.isPlaying, let tsMicros = s.timestampEpochMicros else { return elapsed }
        let ts = tsMicros / 1_000_000
        let rate = s.playbackRate ?? 0
        return elapsed + (nowEpochSeconds - ts) * rate
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter NowPlayingDisplayTests` → PASS (5 tests). Then `swift test` → full suite green.

- [ ] **Step 5: Commit**

```bash
git add Sources/QuackKit/NowPlaying Tests/QuackKitTests/NowPlayingDisplayTests.swift
git commit -m "feat(media): pure now-playing display + elapsed interpolation"
```

---

## Task 4: NowPlayingService (app, fail-soft wrapper)

**Files:**
- Create: `Sources/Quack/NowPlaying/NowPlayingService.swift`

**Interfaces:**
- Consumes: `MediaRemoteAdapter.MediaController`, `TrackInfo`.
- Produces: `@MainActor final class NowPlayingService: ObservableObject` with `@Published private(set) var track: TrackInfo?`, `func start()`, `func stop()`, `func togglePlayPause()`, `func next()`, `func previous()`.

App glue — `swift build` cycle.

- [ ] **Step 1: Write the implementation**

Create `Sources/Quack/NowPlaying/NowPlayingService.swift`:

```swift
import Foundation
import Combine
import MediaRemoteAdapter

/// Wraps the vendored MediaController. Publishes the current track and forwards
/// transport commands. Fail-soft: if the adapter never emits or dies, `track`
/// simply stays nil and the panel shows "Nothing playing" — no crash. Spawns
/// perl via Process/pipes only; installs no event tap (CLAUDE.md freeze rules
/// do not apply). Not App-Store/sandbox compatible (perl + private framework).
@MainActor
final class NowPlayingService: ObservableObject {
    @Published private(set) var track: TrackInfo?

    private let controller = MediaController()
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        controller.onTrackInfoReceived = { [weak self] info in
            // Adapter already hops to main for this callback.
            self?.track = info
        }
        controller.onListenerTerminated = { [weak self] in
            // Listener died; degrade to nothing rather than stale data.
            self?.track = nil
        }
        controller.startListening()
    }

    func stop() {
        guard started else { return }
        started = false
        controller.stopListening()
        controller.onTrackInfoReceived = nil
        controller.onListenerTerminated = nil
        track = nil
    }

    func togglePlayPause() { controller.togglePlayPause() }
    func next() { controller.nextTrack() }
    func previous() { controller.previousTrack() }
}
```

- [ ] **Step 2: Verify build**

Run: `swift build` (modulo build.db quirk). Expected: clean.

- [ ] **Step 3: Commit**

```bash
git add Sources/Quack/NowPlaying/NowPlayingService.swift
git commit -m "feat(media): NowPlayingService fail-soft wrapper over MediaController"
```

---

## Task 5: `notchMediaEnabled` flag + `.notchMedia` feature (QuackKit, TDD)

**Files:**
- Modify: `Sources/QuackKit/Models/QuackSettings.swift`, `Sources/QuackKit/Coordinator/ManagedService.swift`
- Test: `Tests/QuackKitTests/SettingsStoreTests.swift`

**Interfaces:**
- Produces: `QuackSettings.notchMediaEnabled: Bool` (default `false`); `Feature.notchMedia` (enabled iff `settings.notchMediaEnabled`).

- [ ] **Step 1: Write the failing test**

Add to the `SettingsTests` suite in `Tests/QuackKitTests/SettingsStoreTests.swift`:

```swift
    @Test func notchMediaDefaultsOff() {
        #expect(!QuackSettings().notchMediaEnabled)
    }

    @Test func notchMediaDecodesFromOldBlobAsDefault() throws {
        let json = #"{"brightnessEnabled": true}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(QuackSettings.self, from: json)
        #expect(!decoded.notchMediaEnabled)
    }

    @Test func notchMediaFeatureFollowsFlag() {
        var s = QuackSettings()
        s.notchMediaEnabled = true
        #expect(Feature.notchMedia.isEnabled(in: s))
        s.notchMediaEnabled = false
        #expect(!Feature.notchMedia.isEnabled(in: s))
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SettingsTests`
Expected: FAIL to build ("has no member 'notchMediaEnabled'").

- [ ] **Step 3: Write minimal implementation**

In `Sources/QuackKit/Models/QuackSettings.swift`, all four touch-points (after the `notchRevealEnabled` field if present, else after `cpuTemperatureEnabled`):
1. Stored property: `public var notchMediaEnabled: Bool`
2. Init parameter: `notchMediaEnabled: Bool = false,`
3. Init assignment: `self.notchMediaEnabled = notchMediaEnabled`
4. Decoder fallback: `notchMediaEnabled = v(.notchMediaEnabled, d.notchMediaEnabled)`

In `Sources/QuackKit/Coordinator/ManagedService.swift`:
1. `Feature` case: `case notchMedia`
2. `isEnabled(in:)` arm: `case .notchMedia: return settings.notchMediaEnabled`

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SettingsTests` → PASS. Then `swift test` → full suite green (confirms the new `Feature` case didn't break `AppCoordinatorTests`).

- [ ] **Step 5: Commit**

```bash
git add Sources/QuackKit/Models/QuackSettings.swift Sources/QuackKit/Coordinator/ManagedService.swift Tests/QuackKitTests/SettingsStoreTests.swift
git commit -m "feat(media): add notchMedia feature flag + settings field"
```

---

## Task 6: NotchMediaViewModel + NotchMediaView (app UI)

**Files:**
- Create: `Sources/Quack/Notch/NotchMediaViewModel.swift`, `Sources/Quack/Notch/NotchMediaView.swift`

**Interfaces:**
- Consumes: `MediaRemoteAdapter.TrackInfo`, `NotchShape`.
- Produces:
  - `@MainActor final class NotchMediaViewModel: ObservableObject { @Published var isOpen: Bool; @Published var track: TrackInfo?; var onHoverChange: ((Bool)->Void)?; var onToggle: (()->Void)?; var onNext: (()->Void)?; var onPrevious: (()->Void)? }`
  - `struct NotchMediaView: View` (takes `@ObservedObject var model: NotchMediaViewModel`).

App UI glue — `swift build` cycle; behavior verified in Task 8.

- [ ] **Step 1: Write the view model**

Create `Sources/Quack/Notch/NotchMediaViewModel.swift`:

```swift
import AppKit
import Combine
import MediaRemoteAdapter

@MainActor
final class NotchMediaViewModel: ObservableObject {
    @Published var isOpen = false
    @Published var track: TrackInfo?

    var onHoverChange: ((Bool) -> Void)?
    var onToggle: (() -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
}
```

- [ ] **Step 2: Write the view**

Create `Sources/Quack/Notch/NotchMediaView.swift`:

```swift
import SwiftUI
import MediaRemoteAdapter

/// The below-notch media panel: album art + title/artist + transport controls
/// when open and something is playing; a near-invisible hover target otherwise.
struct NotchMediaView: View {
    @ObservedObject var model: NotchMediaViewModel

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { model.onHoverChange?($0) }
    }

    @ViewBuilder
    private var content: some View {
        if model.isOpen {
            HStack(spacing: 12) {
                artwork
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.track?.payload.title ?? "Nothing playing")
                        .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(model.track?.payload.artist ?? "")
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                if model.track != nil {
                    HStack(spacing: 14) {
                        button("backward.fill") { model.onPrevious?() }
                        button((model.track?.payload.isPlaying ?? false) ? "pause.fill" : "play.fill") { model.onToggle?() }
                        button("forward.fill") { model.onNext?() }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(NotchShape().fill(Color.black))
            .foregroundStyle(.white)
        } else {
            Color.black.opacity(0.001)   // hover target only (below the notch)
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let art = model.track?.payload.artwork {
            Image(nsImage: art).resizable().aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28).clipShape(RoundedRectangle(cornerRadius: 5))
        } else {
            RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.12))
                .frame(width: 28, height: 28)
                .overlay(Image(systemName: "music.note").font(.system(size: 12)).foregroundStyle(.secondary))
        }
    }

    private func button(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Image(systemName: symbol).font(.system(size: 13))
            .contentShape(Rectangle()).onTapGesture(perform: action)
    }
}
```

- [ ] **Step 3: Verify build**

Run: `swift build` (modulo build.db quirk). Expected: clean (all SwiftUI APIs used predate macOS 13).

- [ ] **Step 4: Commit**

```bash
git add Sources/Quack/Notch/NotchMediaViewModel.swift Sources/Quack/Notch/NotchMediaView.swift
git commit -m "feat(media): notch media panel view + view model"
```

---

## Task 7: NotchMediaService (ManagedService wiring)

**Files:**
- Create: `Sources/Quack/MenuBar/NotchMediaService.swift`

**Interfaces:**
- Consumes: `NotchScreenReader`, `NotchPanel`, `NotchMediaViewModel`, `NotchMediaView`, `NowPlayingService`; conforms to `QuackKit.ManagedService`.
- Produces: `@MainActor final class NotchMediaService: NSObject, ManagedService` with `init()` and `start()`/`stop()`.

App glue — `swift build`; end-to-end verified in Task 8.

- [ ] **Step 1: Write the implementation**

Create `Sources/Quack/MenuBar/NotchMediaService.swift`:

```swift
import AppKit
import SwiftUI
import Combine
import QuackKit

/// Owns the below-notch media panel and wires it to NowPlayingService. Panel is
/// created once and shown/hidden (mirrors TemperatureStatusItem). Hover expands;
/// the panel hangs BELOW the notch cutout (the shelved icon-reveal's at-cutout
/// geometry was invisible/unhoverable). No event tap / run-loop source.
@MainActor
final class NotchMediaService: NSObject, ManagedService {
    private let reader = NotchScreenReader()
    private let model = NotchMediaViewModel()
    private let nowPlaying = NowPlayingService()
    private var panel: NotchPanel?
    private var cancellable: AnyCancellable?

    private let collapsedHeight: CGFloat = 6      // thin below-notch hover lip
    private let expandedHeight: CGFloat = 56      // room for art + controls, below the cutout
    private let expandedWidth: CGFloat = 320

    func start() {
        guard reader.currentLayout() != nil else {
            reader.onChange = { [weak self] in self?.repositionOrTeardown() }
            reader.startObserving()
            return
        }
        buildPanelIfNeeded()
        model.onHoverChange = { [weak self] h in self?.handleHover(h) }
        model.onToggle = { [weak self] in self?.nowPlaying.togglePlayPause() }
        model.onNext = { [weak self] in self?.nowPlaying.next() }
        model.onPrevious = { [weak self] in self?.nowPlaying.previous() }
        reader.onChange = { [weak self] in self?.repositionOrTeardown() }
        reader.startObserving()
        nowPlaying.start()
        cancellable = nowPlaying.$track.sink { [weak self] t in self?.model.track = t }
        reposition()
    }

    func stop() {
        reader.stopObserving()
        reader.onChange = nil
        cancellable = nil
        nowPlaying.stop()
        panel?.orderOut(nil)
        panel = nil
        model.isOpen = false
        model.track = nil
    }

    private func buildPanelIfNeeded() {
        guard panel == nil else { return }
        let p = NotchPanel(contentRect: NSRect(x: 0, y: 0, width: expandedWidth, height: collapsedHeight))
        let host = NSHostingView(rootView: NotchMediaView(model: model))
        host.frame = p.contentView!.bounds
        host.autoresizingMask = [.width, .height]
        p.contentView?.addSubview(host)
        panel = p
    }

    private func repositionOrTeardown() {
        guard reader.currentLayout() != nil else {
            panel?.orderOut(nil); model.isOpen = false; return
        }
        buildPanelIfNeeded(); reposition()
    }

    /// Positions the panel centered under the notch. Collapsed = a thin lip just
    /// below the cutout (hover target in visible screen). Expanded = the player,
    /// hanging below the notch. Cocoa (Y-up): top-anchored at the screen top.
    private func reposition() {
        guard let layout = reader.currentLayout(), let panel else { return }
        let width = model.isOpen ? expandedWidth : max(layout.span.width, 120)
        let height = model.isOpen ? expandedHeight : collapsedHeight
        let centerX = layout.cocoaNotchRect.midX
        let originX = centerX - width / 2
        let originY = layout.screen.frame.maxY - height   // hangs down from the top
        panel.setFrame(NSRect(x: originX, y: originY, width: width, height: height), display: true)
        panel.orderFrontRegardless()
    }

    private func handleHover(_ hovering: Bool) {
        model.isOpen = hovering
        reposition()
    }
}
```

> **Note (tuning):** `collapsedHeight`/`expandedHeight`/`expandedWidth` and the collapsed hover-lip position are the empirical knobs — the hover spike proved `.onHover` fires on a below-notch panel; exact sizing is tuned on hardware in Task 8.

- [ ] **Step 2: Verify build**

Run: `swift build` (modulo build.db quirk). Expected: clean.

- [ ] **Step 3: Commit**

```bash
git add Sources/Quack/MenuBar/NotchMediaService.swift
git commit -m "feat(media): NotchMediaService owns panel + wires now-playing"
```

---

## Task 8: Wire into AppEnvironment + Settings + HARDWARE VERIFY

**Files:**
- Modify: `Sources/Quack/AppEnvironment.swift`, `Sources/Quack/Settings/SettingsView.swift`

**Interfaces:**
- Consumes: `NotchMediaService`, `Feature.notchMedia`, `QuackSettings.notchMediaEnabled`.

Final integration — `swift build` + full `swift test` + on-hardware verification.

- [ ] **Step 1: Register the service in AppEnvironment**

In `Sources/Quack/AppEnvironment.swift`:
1. Stored property (after `temperatureService`): `private let notchMediaService: NotchMediaService`
2. Construct in `init` (after `temperatureService = …`): `self.notchMediaService = NotchMediaService()`
3. Services map entry (after `.temperature: temperatureService,`): `.notchMedia: notchMediaService,`

- [ ] **Step 2: Add the settings toggle**

In `Sources/Quack/Settings/SettingsView.swift`, add to the `.windows` case in `SettingsPane.body`: `NotchMediaSection()`, then add the section view (after `DockGesturesSection`):

```swift
private struct NotchMediaSection: View {
    @EnvironmentObject var env: AppEnvironment
    var body: some View {
        let s = env.settingsStore
        Section("Notch") {
            Toggle("Show a media player when you hover the notch", isOn: s.binding(\.notchMediaEnabled))
            Text("Move the pointer to the notch to see what's playing and control it. Built-in display only.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}
```

- [ ] **Step 3: Build + full test suite**

Run: `swift build` then `swift test`.
Expected: clean build (modulo build.db quirk); full suite green (QuackKit additions from Tasks 3 & 5 + untouched suites).

- [ ] **Step 4: Install + verify on hardware**

Run: `Scripts/install.sh` (or the manual assemble+install workaround if build.db aborts it).
Then, on the built-in notched display:
1. Settings → Windows → Notch → enable "Show a media player when you hover the notch".
2. Play media in any app.
3. Hover the notch → the player drops down with art/title/artist and controls.
4. Click play/pause, next, previous → the real media reacts; the panel updates.
5. Move away → the panel hides.
6. Pause/stop all media → hover shows "Nothing playing".
7. Toggle the feature off → the panel stops appearing.

Expected: each step behaves as described. Note any sizing/position tuning needed (the `NotchMediaService` height/width knobs).

- [ ] **Step 5: Commit**

```bash
git add Sources/Quack/AppEnvironment.swift Sources/Quack/Settings/SettingsView.swift
git commit -m "feat(media): register notch media service + settings toggle"
```

---

## Self-Review

**Spec coverage:**

| Spec item | Task |
|---|---|
| Hover reveals below-notch player | Tasks 1, 6, 7 |
| Full transport controls (no scrubber) | Tasks 4, 6 |
| System-wide now-playing via vendored perl/MediaRemote adapter | Task 2 |
| Vendored (not remote dep), BSD-3 attribution | Task 2 |
| No permissions | (nothing requests any; Task 4 comment) |
| Pure hover-to-reveal, auto-hide | Tasks 6, 7 |
| Built-in display only / nil layout inert | Task 7 (guards on `currentLayout()`) |
| Fail-soft "Nothing playing" | Tasks 4, 6 |
| Reuse notch shell, geometry-corrected below cutout | Tasks 1, 7 |
| Pure logic unit-tested | Task 3 |
| Hardware checkpoint BEFORE UI | Task 2 Step 6 (hard gate) |
| Feature flag + coordinator lifecycle | Tasks 5, 7, 8 |
| Final hardware verification | Task 8 Step 4 |
| No CGEvent tap | Tasks 4, 7 (comments; Process/onHover only) |
| macOS 13 floor, no remote dep | Global Constraints |

**Placeholder scan:** none — vendored files are copied verbatim from the pinned clone (referenced by path + commit, legitimately not inlined); every authored step has concrete code or an exact command. Task 2 Steps 4/6 explicitly flag where SwiftPM artifact names may need on-machine adjustment — that is honest iteration guidance, not a vague placeholder.

**Type consistency:** `NowPlayingSnapshot`/`NowPlayingDisplay` (Task 3) are self-contained. `TrackInfo`/`MediaController` (Task 2, vendored) are consumed by Tasks 4/6/7 with the exact members read from upstream source (`payload.title/artist/isPlaying/artwork`, `togglePlayPause()/nextTrack()/previousTrack()/startListening()/stopListening()/onTrackInfoReceived`). `NotchMediaViewModel` (Task 6) produced → consumed by Task 7. `NotchScreenReader`/`NotchPanel`/`NotchShape` (Task 1) → consumed by Tasks 6/7. `Feature.notchMedia`/`notchMediaEnabled` (Task 5) → consumed by Tasks 7/8. Consistent.

**Note on risk ordering:** Task 2 is intentionally front-loaded and gated — if the adapter can't read on this hardware, the plan stops there with only vendored files + wiring committed, before any UI investment.
