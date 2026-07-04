# Dynamic Notch — Claude Code Agent Progress — Design Spec

- **Date:** 2026-07-04
- **Status:** Approved (design), not yet implemented
- **Branch:** `notch-agents` (off `main`)
- **Builds on:** the shipped notch **media player** (`2026-07-01-dynamic-notch-media-design.md`)
- **Inspiration:** agentnotch.app — glanceable agent status in the notch

## Problem

The notch already reveals a media player on hover. The user also wants to see
**Claude Code agent progress** in the notch: which agents are running, which
need attention, what they're doing, plus account usage limits — all at a glance,
in the same notch surface. Like agentnotch.app.

## Reference UI (target)

A dark expanded notch panel, orange asterisk accent, green usage bars. Top→bottom:

- **Header:** orange asterisk + "N agents" (left); pills "⚡ Xk today" and outlined
  "N needs you" (right).
- **Claude section:** asterisk + "Claude"; two green usage bars — "5h — 84% left ·
  resets 3:20 PM" and "7d — 81% left · resets Jul 2".
- **Per-agent cards:** colored status dot (orange = needs attention, green =
  working), asterisk, project name, `⎇ branch`, a one-line status message, and a
  pill row: status pill (⚠ NEEDS YOU orange / ⚡ WORKING green), model pill
  ("Opus 4.8"), progress-meter pill ("22%").
- **New (not in reference):** the existing media player, shrunk to a compact strip
  **pinned at the bottom** of the same panel (album thumb + title/artist + ⏮ ⏯ ⏭),
  on a darker sub-surface with a hairline divider.

## Decisions (locked in brainstorming)

1. **Coexistence — unified panel.** The notch is one physical spot; one hover
   reveals one panel. Agents occupy the top (primary); the media player is a
   compact strip pinned at the bottom of the same panel.
2. **Always-on peek.** When an agent needs you (or is working), a subtle indicator
   shows at the notch **without** hovering; hover expands the full panel. Pure
   hover-only fallback when there is nothing to report.
3. **Data source — push (hooks + statusLine).** Quack installs Claude Code hooks +
   a statusLine wrapper (chaining the user's existing `statusline.sh`) that write
   per-session state into `~/.claude/quack/`; Quack watches that directory. This
   is the only path that yields the 5h/7d rate-limit data and a reliable
   "needs you" signal. Reversible; gated behind explicit consent.
4. **Scope — full parity** with the reference, including the Claude 5h/7d
   usage-limits section, in v1.
5. **A. Progress %** = TodoWrite completed/total ratio when the session has an
   active todo list; fallback to `context_window.used_percentage`.
6. **B. Status message** = the current tool action while working
   (e.g. "Editing settings.json"); the first line of the last assistant text when
   idle / needs-you (e.g. "Landing page shipped. One notch, one glance.").
7. **C. "Agents"** = all Claude Code sessions with recent activity, auto-discovered
   across projects, pruned by staleness.

## Goals (v1)

- Hovering the notch reveals a panel showing all active Claude Code agents: status
  dot, project, branch, one-line status, status/model/progress pills.
- Header shows agent count, tokens-today, and needs-you count.
- Claude usage section shows 5h and 7d rate-limit bars with reset times.
- Always-on **peek**: an ambient dot/count at the notch when an agent needs you or
  is working; nothing when idle/none.
- The media player is retained as a compact strip pinned at the panel bottom.
- Degrade quietly whenever data is unavailable — never crash.
- Built-in (notched) display only.

## Non-goals (v1)

- No agent control (can't approve/deny/stop a Claude session from the notch —
  read-only view). A "click a card to focus that terminal/session" affordance is a
  possible later enhancement, not v1.
- No historical charts / analytics beyond the header's tokens-today.
- No external-display support.
- No dependency on the third-party `usage.db` aggregator (optional enrichment only;
  never required).
- Not App-Store / sandbox compatible (consistent with Quack shipping outside the
  App Store, and with the media player already spawning perl).

## Baseline precondition (blocker — task 0)

`main` and `show-notch-hidden-icons` are the **same commit** (`6852496`) and the
tree **does not currently compile**:

- `AppEnvironment` uses `notchMediaService` uninitialized, and assigns
  `self.notchRevealService` to a property that is not declared.
- `Feature.isEnabled(in:)` is missing its `.notchReveal` case → non-exhaustive
  switch.

This is a half-merged Knock-Notch (icon-reveal) reintroduction. **Task 0 of the
implementation is to restore a green build off `main`** — either finish or stub the
`.notchReveal` wiring and initialize `notchMediaService` — and verify on hardware
that the media player still reveals. All agent work builds on that green baseline.

## Architecture

### Reused notch shell (unchanged)

- `Sources/QuackKit/Notch/NotchGeometry.swift` — pure notch-span math.
- `Sources/Quack/Notch/NotchScreenReader.swift` — built-in-screen notch geometry +
  screen-change observer (`NotchLayout.cocoaNotchRect`).
- `Sources/Quack/Notch/NotchPanel.swift` — borderless nonactivating panel,
  `.mainMenu + 3`, never key/main.
- `Sources/Quack/Notch/NotchShape.swift` — animatable rounded-bottom shape.

Geometry rule is unchanged from the media spec: anchor the panel top at
`cocoaNotchRect.minY` and hang content **downward**, never behind the physical
cutout.

### Single panel owner (refactor)

Today `NotchMediaService` owns the one notch panel. For the unified panel, one
service owns the single panel and hosts a unified view containing both zones.

- Rename/replace `NotchMediaService` → **`NotchService`** (`ManagedService`). It
  owns the `NotchPanel`, the `NotchScreenReader`, and a `NotchContentViewModel`
  that aggregates media state (from `NowPlayingService`) **and** agent state (from
  `ClaudeAgentsService`). It computes the panel's three visual states and its
  frame.
- This avoids two services fighting over one panel and keeps a single source of
  truth for hover / open / geometry.

### Panel states (one view model)

Driven by `NotchContentViewModel`:

- **Peek** (not hovering, something to report): a small pill just below the notch —
  colored dot + count (orange if any needs-you, else green if any working).
- **Collapsed** (not hovering, nothing to report): an invisible hover strip (as the
  media player is today).
- **Expanded** (hover): the full panel — header row → Claude usage section → agent
  cards (scroll if many) → media strip pinned at bottom. Width ~360; height dynamic
  with a cap, scrolling the agents zone beyond the cap. Media strip stays pinned.

### New — pure logic (QuackKit, unit-tested)

- `Sources/QuackKit/Models/AgentModel.swift` — value types, all
  `Codable`/`Equatable`/`Sendable`:
  - `AgentSnapshot`: `sessionID`, `project`, `branch?`, `model?`, `status`
    (`AgentStatus`), `statusMessage?`, `progress: Double?` (0…1), `lastUpdate:
    Date`.
  - `AgentStatus`: `.working`, `.needsYou`, `.idle`.
  - `UsageLimits`: `fiveHourUsedPercent?`, `sevenDayUsedPercent?`,
    `fiveHourResetsAt?`, `sevenDayResetsAt?`, `tokensToday?`.
  - Raw decode types for the two on-disk file shapes: the statusLine JSON blob and
    the hook state JSON.
- `Sources/QuackKit/Agents/AgentReducer.swift` — pure functions:
  - **Merge:** given a set of `(statusFile, stateFile)` per `sessionID` + a `now`
    timestamp, produce `[AgentSnapshot]` + a single account-global `UsageLimits`
    (rate limits are account-global → take the most recently updated session's).
  - **Status/color:** map hook events to `AgentStatus`; derive dot color.
  - **Progress:** TodoWrite ratio when present, else `context_window.used_percentage`.
  - **Status message:** tool action (`"<Tool> <file/arg>"`) while working; first
    line of last assistant text when idle/needs-you.
  - **Staleness prune:** drop sessions whose `lastUpdate` is older than a threshold
    (constant, e.g. 15 min) or that emitted `SessionEnd`.
  - **Counts:** agents total, needs-you count.
  - No system dependencies; fully testable with on-disk-shape fixtures.

### New — Claude Code integration (app layer)

- `Sources/Quack/Agents/ClaudeConfigInstaller.swift` — idempotent install/uninstall
  of Quack's hooks + statusLine wrapper into `~/.claude/settings.json`:
  - Writes bundled script templates to `~/.claude/quack/` (a statusLine wrapper and
    per-event hook scripts).
  - **statusLine wrapper:** reads the statusLine JSON on stdin, writes the raw JSON
    to `~/.claude/quack/sessions/<session_id>.status.json`, then execs the user's
    **previous** statusLine command (captured at install time) so their existing
    status line is untouched.
  - **hooks:** `SessionStart`, `UserPromptSubmit`, `PostToolUse`, `Notification`,
    `Stop`, `SessionEnd` — each a one-liner that writes/updates
    `~/.claude/quack/sessions/<session_id>.state.json` (`status`, `lastTool`,
    `lastFile`, `branch`, `project`, `cwd`, `ts`) using `session_id` +
    `transcript_path` from the hook's stdin JSON.
  - Marks its own entries (e.g. a `# quack` sentinel / a dedicated block) so
    uninstall removes **only** Quack's additions and restores the prior statusLine
    command. Idempotent: re-install detects and updates its own block rather than
    duplicating.
- `Sources/Quack/Agents/ClaudeStateWatcher.swift` — watches
  `~/.claude/quack/sessions/` (a `DispatchSource` file-system watch, or FSEvents),
  debounced; decodes the `.status.json` + `.state.json` files into the raw types.
  No event tap, no run-loop source (CLAUDE.md freeze rules do not apply).
- `Sources/Quack/Agents/ClaudeAgentsService.swift` — `ManagedService` that owns the
  watcher, runs `AgentReducer` on change (with `Date()` as `now`), and publishes
  `@Published [AgentSnapshot]` + `@Published UsageLimits?`. Fail-soft: missing dir
  / unreadable files → empty agents + nil usage, never a crash.

### New — SwiftUI views

- `Sources/Quack/Notch/NotchContentViewModel.swift` — `@MainActor ObservableObject`:
  `isOpen`, `peekState`, `agents`, `usage`, media `track`, `contentTopInset`,
  hover + media callbacks.
- `Sources/Quack/Notch/NotchContentView.swift` — the unified panel: header +
  usage section + agent cards + media strip, plus the peek/collapsed states.
- `Sources/Quack/Notch/AgentCardView.swift` — one agent card.
- `Sources/Quack/Notch/NotchHeaderView.swift` — header row (count + pills).
- `Sources/Quack/Notch/UsageLimitsView.swift` — the Claude 5h/7d section.
- `Sources/Quack/Notch/NotchTheme.swift` — shared design tokens (colors, pill
  styles, the orange accent, green bar color) used by agent + media views.
- The existing `NotchMediaView` is reused (shrunk) as the pinned media strip.

### Wiring

- `notchAgentsEnabled` flag in `QuackSettings` (default false; additive decode).
- Agents are served by the same single-panel `.notchMedia` feature (one panel), or
  a dedicated `.notchAgents` `Feature` case that shares the panel — plan-level
  detail; the constraint is **one panel**. If a new `Feature` case is added, add
  its `isEnabled` mapping (avoid the `.notchReveal` non-exhaustive-switch mistake).
- Register `ClaudeAgentsService` + the renamed `NotchService` in `AppEnvironment`'s
  services map; same coordinator-driven lifecycle.
- Settings UI: a toggle plus an **"Enable Claude integration"** button that runs
  `ClaudeConfigInstaller` (writes `~/.claude` config) and an **"Disable"** that
  uninstalls. Show install state (installed / not installed).

### Data flow

```
Claude Code session runs (any project)
  → statusLine wrapper writes <id>.status.json (model, ctx%, 5h/7d limits, cost, cwd)
  → hooks write <id>.state.json (status working|needs_you|idle, lastTool, lastFile, branch, project, ts)
Quack:
  ClaudeStateWatcher (FS watch) → decode raw files
  → AgentReducer.merge(files, now) → [AgentSnapshot] + UsageLimits
  → ClaudeAgentsService publishes → NotchContentViewModel
  → peek indicator updates live; hover expands the full panel
NowPlayingService.$track → NotchContentViewModel.track → media strip
```

## Field → source map

| Mockup field        | Source |
|---------------------|--------|
| "N agents"          | count of live (non-stale) sessions |
| ⚡ "Xk today"        | today's output tokens (statusLine usage; `usage.db` optional enrich) |
| "N needs you"       | count of sessions in `needs_you` |
| Claude 5h / 7d bars | statusLine `rate_limits.five_hour` / `seven_day` `used_percentage` + reset (account-global → most-recent session) |
| status dot          | needs_you = orange · working = green · idle = gray |
| project name        | cwd basename / workspace from hook state |
| ⎇ branch            | git branch from hook state |
| status message      | working → "`<Tool> <file>`"; idle/needs_you → first line of last assistant text |
| status pill         | NEEDS YOU / WORKING (from `AgentStatus`) |
| model pill          | statusLine `model.display_name` |
| progress %          | TodoWrite completed/total; fallback `context_window.used_percentage` |

## Permissions / consent

- **No TCC.** No Accessibility, no Screen Recording. No event tap.
- **The one consent item:** writing `~/.claude/settings.json` (hooks + statusLine)
  changes the user's Claude Code configuration. Gated behind an explicit
  "Enable Claude integration" button in settings; chains the existing statusLine so
  nothing breaks; a matching uninstall restores the prior state. Nothing is written
  to `~/.claude` unless the user opts in.
- Reading `~/.claude/quack/` is plain file IO.

## Distribution

Consistent with Quack's model (unsandboxed, notarized, direct/DMG). Reading/writing
`~/.claude` + spawning shell hooks is not sandbox-compatible; note this in code
comments so a future sandboxed build variant isn't attempted.

## Error handling / degradation

| Condition | Behavior |
|---|---|
| Integration not installed | Agents section shows an "Enable Claude integration" CTA; media strip still works. |
| No active sessions | Agents section shows a quiet "No active agents" state; peek shows nothing. |
| Session state stale (> threshold) or `SessionEnd` | Session pruned (card disappears). |
| statusLine JSON lacks `rate_limits` (older Claude Code) | Hide the Claude usage section; keep cards. |
| Unreadable / malformed state file | Skip that session; log once, not repeatedly. |
| No built-in notch (external only / clamshell) | Feature inactive on that screen. Not an error. |
| `usage.db` absent or unreadable | Tokens-today falls back to statusLine-derived total or hides; never fails. |

## Testing / verification

- **Hardware checkpoint (early plan task):** after installing hooks + statusLine,
  confirm that running a real Claude Code session writes `<id>.status.json` +
  `<id>.state.json` with the expected fields (model, 5h/7d limits, status, branch)
  on this Mac (macOS 26.5.x) **before** building UI on the pipeline. If the
  statusLine JSON lacks `rate_limits`/`context_window` here, adjust the usage
  section's degradation and reassess.
- **Pure unit tests (QuackKit):** `AgentReducer` merge (statusLine + hook fixtures),
  staleness prune, progress calc (TodoWrite ratio vs context fallback), status
  message derivation, needs-you counting, `UsageLimits` parse; `AgentModel`
  decode/round-trip. No system deps.
- **Installer test:** idempotent install → re-install (no duplication) → uninstall
  round-trip against a temp `settings.json`, asserting the prior statusLine command
  is preserved and restored.
- **Hardware manual verification (final task):** run two real Claude sessions in
  two projects → both cards appear with correct project/branch/model; a card flips
  to NEEDS YOU on `Stop`/`Notification` and back to WORKING on the next prompt; the
  peek dot shows without hovering; hover expands the full panel; the media strip
  plays and controls work — on the built-in notched display.
- App-target glue (service, watcher, views, installer wiring) is `swift build` +
  manual verify (consistent with the codebase).

## Phasing (for the implementation plan)

1. **Task 0 — green baseline** off `main` (fix the non-compiling icon-reveal
   wiring; verify media reveals).
2. **Data pipeline** — installer + hook/statusLine templates + watcher; prove it
   emits correct files on hardware (debug dump, no UI yet).
3. **QuackKit models + reducer** with unit tests.
4. **`ClaudeAgentsService`** publishing snapshots + usage.
5. **Unified panel refactor** — `NotchService` + `NotchContentViewModel`; move media
   into the strip; keep media working.
6. **Agent UI** — header, usage section, cards, theme; expanded state.
7. **Peek state** + always-on indicator.
8. **Settings** — toggle + install/uninstall button + state display.
9. **Hardware manual verification.**

## Risks / open questions for the plan

- **statusLine cadence:** statusLine only re-emits when a session renders its status
  line (active/foreground redraw). A backgrounded session's `.status.json` goes
  stale; the hook `.state.json` still updates on events. The reducer must treat
  status (model/ctx/limits) and state (working/needs-you) with independent
  freshness, and rate limits as account-global (any recent session's value).
- **Status message fidelity:** deriving the "last assistant line" requires reading
  the transcript tail in the `Stop` hook (it receives `transcript_path`). Keep it
  best-effort; fall back to a generic "Waiting for you".
- **Hook JSON schema drift:** hook/statusLine stdin fields can change across Claude
  Code versions. Decode defensively; missing fields degrade, never crash.
- **Multiple Quack installs / re-install:** installer must own a clearly-marked
  block and be safe to re-run.

## Branch strategy

Branch `notch-agents` off `main`. Task 0 restores a green build. The notch shell
(`NotchPanel`, `NotchScreenReader`, `NotchGeometry`, `NotchShape`) and the media
player are reused, not forked. `NotchMediaService` is refactored into `NotchService`
(single panel owner). No changes to the media adapter.
