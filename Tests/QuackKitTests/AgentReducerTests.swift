import Testing
import Foundation
@testable import QuackKit

@Suite struct AgentReducerTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func state(_ overrides: [String: Any]) throws -> StateFileRaw {
        var base: [String: Any] = ["session_id": "s1", "status": "working", "event": "PostToolUse",
                                   "cwd": "/r/website", "project": "website", "branch": "main"]
        base.merge(overrides) { _, new in new }
        base = base.filter { !($0.value is NSNull) }
        return try JSONDecoder().decode(StateFileRaw.self, from: JSONSerialization.data(withJSONObject: base))
    }

    func files(_ st: StateFileRaw?, status: StatusFileRaw? = nil, modified: Date? = nil) -> SessionFiles {
        SessionFiles(sessionID: st?.session_id ?? "s?", state: st, status: status,
                     stateModified: modified ?? now, statusModified: modified ?? now)
    }

    @Test func workingUsesToolPhrase() throws {
        let f = files(try state(["last_tool": "Edit", "last_tool_target": "/r/website/settings.json"]))
        let snap = AgentReducer.snapshots(from: [f], now: now, staleAfter: 900)[0]
        #expect(snap.status == .working)
        #expect(snap.statusMessage == "Editing settings.json")
    }

    @Test func needsYouFromStopUsesAssistantLine() throws {
        let f = files(try state(["status": "needs_you", "event": "Stop",
                                 "last_assistant_line": "Landing page shipped."]))
        let snap = AgentReducer.snapshots(from: [f], now: now, staleAfter: 900)[0]
        #expect(snap.status == .needsYou)
        #expect(snap.statusMessage == "Landing page shipped.")
    }

    @Test func needsYouFromNotificationPrefersNotificationMessage() throws {
        let f = files(try state(["status": "needs_you", "event": "Notification",
                                 "notification_message": "Claude needs your permission to use Bash",
                                 "last_assistant_line": "old text"]))
        #expect(AgentReducer.snapshots(from: [f], now: now, staleAfter: 900)[0].statusMessage
                == "Claude needs your permission to use Bash")
    }

    @Test func progressPrefersTodosOverContext() throws {
        let status = try JSONDecoder().decode(StatusFileRaw.self,
            from: Data(#"{"context_window":{"used_percentage":50}}"#.utf8))
        let withTodos = files(try state(["todos_completed": 3, "todos_total": 4]), status: status)
        #expect(AgentReducer.snapshots(from: [withTodos], now: now, staleAfter: 900)[0].progress == 0.75)
        let noTodos = files(try state([:]), status: status)
        #expect(AgentReducer.snapshots(from: [noTodos], now: now, staleAfter: 900)[0].progress == 0.5)
    }

    @Test func staleAndEndedArePruned() throws {
        let stale = SessionFiles(sessionID: "s1", state: try state([:]), status: nil,
                                 stateModified: now.addingTimeInterval(-1000), statusModified: nil)
        let ended = files(try state(["status": "ended", "event": "SessionEnd"]))
        #expect(AgentReducer.snapshots(from: [stale, ended], now: now, staleAfter: 900).isEmpty)
    }

    @Test func tsFieldBeatsFileMtimeForStaleness() throws {
        let fresh = SessionFiles(sessionID: "s1",
            state: try state(["ts": ISO8601DateFormatter().string(from: now.addingTimeInterval(-10))]),
            status: nil, stateModified: now.addingTimeInterval(-5000), statusModified: nil)
        #expect(AgentReducer.snapshots(from: [fresh], now: now, staleAfter: 900).count == 1)
    }

    @Test func sortNeedsYouFirstThenWorking() throws {
        let w = files(try state(["session_id": "w"]))
        let n = files(try state(["session_id": "n", "status": "needs_you", "event": "Stop"]))
        let i = files(try state(["session_id": "i", "status": "idle", "event": "SessionStart"]))
        let out = AgentReducer.snapshots(from: [i, w, n], now: now, staleAfter: 900)
        #expect(out.map(\.sessionID) == ["n", "w", "i"])
    }

    @Test func statusOnlySessionIsNotACard() throws {
        let status = try JSONDecoder().decode(StatusFileRaw.self, from: Data("{}".utf8))
        let f = SessionFiles(sessionID: "x", state: nil, status: status, stateModified: nil, statusModified: now)
        #expect(AgentReducer.snapshots(from: [f], now: now, staleAfter: 900).isEmpty)
    }

    @Test func projectFallsBackToCwdBasename() throws {
        let f = files(try state(["project": NSNull()]))   // project removed
        #expect(AgentReducer.snapshots(from: [f], now: now, staleAfter: 900)[0].project == "website")
    }

    // MARK: - Amendments: model display source

    @Test func modelDisplayNameExamples() {
        #expect(AgentReducer.modelDisplayName(id: "claude-opus-4-8") == "Opus 4.8")
        #expect(AgentReducer.modelDisplayName(id: "claude-fable-5") == "Fable 5")
        #expect(AgentReducer.modelDisplayName(id: "claude-haiku-4-5-20251001") == "Haiku 4.5")
        #expect(AgentReducer.modelDisplayName(id: "claude-opus-4-8[1m]") == "Opus 4.8")
    }

    @Test func modelDisplayNameUnrecognizedShapeReturnsUnchanged() {
        #expect(AgentReducer.modelDisplayName(id: "weird-id") == "weird-id")
    }

    @Test func snapshotModelPrefersStateModelIdOverStatusDisplayName() throws {
        let status = try JSONDecoder().decode(StatusFileRaw.self,
            from: Data(#"{"model":{"display_name":"Opus"}}"#.utf8))
        let f = files(try state(["model_id": "claude-opus-4-8"]), status: status)
        #expect(AgentReducer.snapshots(from: [f], now: now, staleAfter: 900)[0].model == "Opus 4.8")
    }

    @Test func snapshotModelFallsBackToStatusDisplayNameWhenNoModelId() throws {
        let status = try JSONDecoder().decode(StatusFileRaw.self,
            from: Data(#"{"model":{"display_name":"Opus"}}"#.utf8))
        let f = files(try state([:]), status: status)
        #expect(AgentReducer.snapshots(from: [f], now: now, staleAfter: 900)[0].model == "Opus")
    }

    @Test func snapshotModelNilWhenNeitherSourcePresent() throws {
        let f = files(try state([:]))
        #expect(AgentReducer.snapshots(from: [f], now: now, staleAfter: 900)[0].model == nil)
    }

    // MARK: - Amendments: empty strings treated as nil

    @Test func bashWithEmptyTargetProducesRunningACommand() throws {
        let f = files(try state(["last_tool": "Bash", "last_tool_target": ""]))
        #expect(AgentReducer.snapshots(from: [f], now: now, staleAfter: 900)[0].statusMessage == "Running a command")
    }

    @Test func editWithEmptyTargetProducesEditingFiles() throws {
        let f = files(try state(["last_tool": "Edit", "last_tool_target": ""]))
        #expect(AgentReducer.snapshots(from: [f], now: now, staleAfter: 900)[0].statusMessage == "Editing files")
    }

    @Test func emptyBranchBecomesNil() throws {
        let f = files(try state(["branch": ""]))
        #expect(AgentReducer.snapshots(from: [f], now: now, staleAfter: 900)[0].branch == nil)
    }

    // MARK: - Amendments: per-agent stat line (replaces global usage section)

    @Test func statLineAllFields() throws {
        let status = try JSONDecoder().decode(StatusFileRaw.self,
            from: Data(#"{"context_window":{"used_percentage":22.4},"cost":{"total_cost_usd":0.324},"rate_limits":{"five_hour":{"used_percentage":10.2},"seven_day":{"used_percentage":16.8}}}"#.utf8))
        let f = files(try state(["model_id": "claude-sonnet-4-6"]), status: status)
        let snap = AgentReducer.snapshots(from: [f], now: now, staleAfter: 900)[0]
        #expect(snap.contextUsedPercent == 22.4)
        #expect(snap.costUSD == 0.324)
        #expect(snap.fiveHourUsedPercent == 10.2)
        #expect(snap.sevenDayUsedPercent == 16.8)
        #expect(AgentReducer.statLine(for: snap) == "Sonnet 4.6 · ctx 22% · $0.32 · 5h 10% · 7d 17%")
    }

    @Test func statLineModelOnly() throws {
        let f = files(try state(["model_id": "claude-sonnet-4-6"]))
        let snap = AgentReducer.snapshots(from: [f], now: now, staleAfter: 900)[0]
        #expect(AgentReducer.statLine(for: snap) == "Sonnet 4.6")
    }

    @Test func statLineNilWhenNothing() throws {
        let f = files(try state([:]))
        let snap = AgentReducer.snapshots(from: [f], now: now, staleAfter: 900)[0]
        #expect(AgentReducer.statLine(for: snap) == nil)
    }

    // MARK: - Amendments: host pid (click-to-focus)

    @Test func hostPIDPassesThroughWhenPresent() throws {
        let f = files(try state(["host_pid": 4242, "host_app": "Terminal"]))
        let snap = AgentReducer.snapshots(from: [f], now: now, staleAfter: 900)[0]
        #expect(snap.hostPID == 4242)
    }

    @Test func hostPIDNilWhenAbsent() throws {
        let f = files(try state([:]))
        let snap = AgentReducer.snapshots(from: [f], now: now, staleAfter: 900)[0]
        #expect(snap.hostPID == nil)
    }
}
