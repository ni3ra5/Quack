import Foundation
import Testing
@testable import QuackKit

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private func ms(_ d: Date) -> Double { d.timeIntervalSince1970 * 1000 }

private func record(_ id: String, pid: Int32 = 1, status: String?, statusAfter: TimeInterval,
                    entrypoint: String = "claude-desktop") -> ClaudeRegistryRecord {
    ClaudeRegistryRecord(pid: pid, sessionId: id, cwd: "/x/Proj", name: nil, entrypoint: entrypoint,
                         status: status, startedAt: ms(t0), statusUpdatedAt: ms(t0 + statusAfter))
}

private func resolve(_ records: [ClaudeRegistryRecord], events: [String: ClaudeHookEvent] = [:],
                     dismissed: [String: Date] = [:], alive: Set<Int32> = [1, 2]) -> [ClaudeSession] {
    ClaudeSessionResolver.sessions(records: records, events: events, dismissed: dismissed) {
        alive.contains($0) ? t0 : nil
    }
}

@Test func registryStatusMapsToState() {
    let s = resolve([record("opened", status: "idle", statusAfter: 0),
                     record("run", status: "busy", statusAfter: 10),
                     record("done", status: "idle", statusAfter: 60)])
    let byId = Dictionary(uniqueKeysWithValues: s.map { ($0.id, $0.state) })
    #expect(byId == ["run": .running, "done": .done])   // just-opened sessions are hidden
    #expect(s.first?.name == "Proj")   // falls back to the folder name
}

@Test func hookEventMarksBusySessionWaitingUntilNextEvent() {
    let r = record("a", status: "busy", statusAfter: 10)
    let ask = ClaudeHookEvent(sessionId: "a", name: "PreToolUse", toolName: "AskUserQuestion", at: t0 + 20)
    #expect(resolve([r], events: ["a": ask]).first?.state == .waiting)

    let perm = ClaudeHookEvent(sessionId: "a", name: "Notification", notificationType: "permission_prompt", at: t0 + 20)
    #expect(resolve([r], events: ["a": perm]).first?.state == .waiting)

    let resumed = ClaudeHookEvent(sessionId: "a", name: "PostToolUse", toolName: "Bash", at: t0 + 30)
    #expect(resolve([r], events: ["a": resumed]).first?.state == .running)

    // A waiting event from before the current turn is stale.
    let stale = ClaudeHookEvent(sessionId: "a", name: "PermissionRequest", at: t0 + 5)
    #expect(resolve([r], events: ["a": stale]).first?.state == .running)

    // Once the turn ends, "done" wins over a leftover waiting event.
    let idle = record("a", status: "idle", statusAfter: 40)
    #expect(resolve([idle], events: ["a": ask]).first?.state == .done)
}

@Test func deadOrRecycledPidsAreDropped() {
    #expect(resolve([record("a", pid: 9, status: "busy", statusAfter: 1)]).isEmpty)
    let recycled = ClaudeSessionResolver.sessions(
        records: [record("a", status: "busy", statusAfter: 1)], events: [:], dismissed: [:]
    ) { _ in t0 + 3600 }
    #expect(recycled.isEmpty)
}

@Test func dismissedSessionReturnsOnNewActivity() {
    let r = record("a", status: "idle", statusAfter: 60)
    #expect(resolve([r], dismissed: ["a": t0 + 61]).isEmpty)
    let later = record("a", status: "busy", statusAfter: 90)
    #expect(resolve([later], dismissed: ["a": t0 + 61]).count == 1)
}

@Test func hookEventParsesFromStdinJSON() throws {
    let json = #"{"session_id":"s1","hook_event_name":"Notification","notification_type":"permission_prompt","message":"x"}"#
    let e = try #require(ClaudeHookEvent(json: Data(json.utf8), at: t0))
    #expect(e.sessionId == "s1" && e.isWaitingForUser)
    #expect(ClaudeHookEvent(json: Data("nope".utf8), at: t0) == nil)
}

@Test func hookInstallIsIdempotentAndRemovable() {
    let userHook: [String: Any] = ["hooks": [["type": "command", "command": "echo mine"]]]
    let original: [String: Any] = ["model": "opus", "hooks": ["PreToolUse": [userHook]]]
    #expect(!ClaudeHookConfig.isInstalled(in: original))

    let once = ClaudeHookConfig.installing(into: original)
    let twice = ClaudeHookConfig.installing(into: once)
    #expect(ClaudeHookConfig.isInstalled(in: twice))
    let pre = (twice["hooks"] as? [String: Any])?["PreToolUse"] as? [[String: Any]]
    #expect(pre?.count == 2)   // the user's hook + exactly one of ours

    let removed = ClaudeHookConfig.removing(from: twice)
    #expect(!ClaudeHookConfig.isInstalled(in: removed))
    #expect(NSDictionary(dictionary: removed).isEqual(to: original))
}

@Test func sessionsGroupByAppInFixedOrder() {
    let s = resolve([record("t", status: "idle", statusAfter: 60, entrypoint: "cli"),
                     record("v", pid: 2, status: "idle", statusAfter: 60, entrypoint: "claude-vscode"),
                     record("d", status: "idle", statusAfter: 60)])
    #expect(s.groupedBySource.map(\.source) == [.desktop, .vscode, .terminal])
}

@Test func onlySessionsActiveSinceLaunchAreShown() {
    let old = record("old", status: "idle", statusAfter: 60)      // last touched at t0+60
    let fresh = record("new", pid: 2, status: "busy", statusAfter: 200)
    let s = ClaudeSessionResolver.sessions(records: [old, fresh], events: [:], dismissed: [:],
                                           activeSince: t0 + 100, now: t0 + 300) { _ in t0 }
    #expect(s.map(\.id) == ["new"])
}

@Test func untouchedSessionsExpireButRunningOnesStay() {
    let done = record("done", status: "idle", statusAfter: 60)
    let busy = record("busy", pid: 2, status: "busy", statusAfter: 60)
    let later = t0 + 60 + 4 * 3600 + 1
    let s = ClaudeSessionResolver.sessions(records: [done, busy], events: [:], dismissed: [:],
                                           now: later) { _ in t0 }
    #expect(s.map(\.id) == ["busy"])
}

@Test func inProgressSessionsShowEvenIfStartedBeforeLaunch() {
    let busy = record("busy", status: "busy", statusAfter: 60)     // turn began before launch
    let done = record("done", pid: 2, status: "idle", statusAfter: 60)
    let s = ClaudeSessionResolver.sessions(records: [busy, done], events: [:], dismissed: [:],
                                           activeSince: t0 + 100, now: t0 + 300) { _ in t0 }
    #expect(s.map(\.id) == ["busy"])
}
