import Testing
import Foundation
@testable import QuackKit

@Suite struct AgentModelTests {
    static let stateJSON = #"""
    {"session_id":"abc-123","status":"working","event":"PostToolUse","cwd":"/Users/x/Repositories/website",
     "project":"website","branch":"main","ts":"2026-07-04T12:00:00Z",
     "last_tool":"Edit","last_tool_target":"/Users/x/Repositories/website/settings.json",
     "todos_completed":2,"todos_total":9}
    """#

    // Real captured state.json from the Task 2 hardware checkpoint (own session,
    // hooks live end-to-end) — verbatim from docs/superpowers/specs/fixtures-notch-agents.md.
    // Exercises: model_id field, empty-string last_tool_target, no todos fields.
    static let realCapturedStateJSON = #"""
    {
      "session_id": "0a2b9045-11e1-41c5-800a-fe2870544ccb",
      "status": "working",
      "event": "UserPromptSubmit",
      "cwd": "/Users/strativ/Repositories/Quack",
      "project": "Quack",
      "branch": "notch-agents",
      "ts": "2026-07-04T18:35:15Z",
      "last_tool": "ScheduleWakeup",
      "last_tool_target": "",
      "last_assistant_line": "jq bug in plan's command (`(...)[]` on comma-stream). settings.json untouched (mv never ran). Fixed:",
      "model_id": "claude-fable-5"
    }
    """#

    static let statusJSON = #"""
    {"session_id":"abc-123","model":{"id":"claude-opus-4-8","display_name":"Opus 4.8"},
     "context_window":{"used_percentage":22.4},
     "rate_limits":{"five_hour":{"used_percentage":16.0,"resets_at":"2026-07-04T15:20:00Z"},
                    "seven_day":{"used_percentage":19.0,"resets_at":1783036800}}}
    """#

    @Test func decodesStateFile() throws {
        let s = try JSONDecoder().decode(StateFileRaw.self, from: Data(Self.stateJSON.utf8))
        #expect(s.session_id == "abc-123")
        #expect(s.status == "working")
        #expect(s.branch == "main")
        #expect(s.todos_total == 9)
    }

    @Test func decodesRealCapturedStateFile() throws {
        let s = try JSONDecoder().decode(StateFileRaw.self, from: Data(Self.realCapturedStateJSON.utf8))
        #expect(s.session_id == "0a2b9045-11e1-41c5-800a-fe2870544ccb")
        #expect(s.status == "working")
        #expect(s.event == "UserPromptSubmit")
        #expect(s.branch == "notch-agents")
        #expect(s.project == "Quack")
        #expect(s.model_id == "claude-fable-5")
        // Empty string must decode as "" — not nil, no crash.
        #expect(s.last_tool_target == "")
        #expect(s.todos_completed == nil)
        #expect(s.todos_total == nil)
    }

    @Test func decodesStatusFileWithBothResetFormats() throws {
        let s = try JSONDecoder().decode(StatusFileRaw.self, from: Data(Self.statusJSON.utf8))
        #expect(s.model?.display_name == "Opus 4.8")
        #expect(s.context_window?.used_percentage == 22.4)
        #expect(s.rate_limits?.five_hour?.used_percentage == 16.0)
        #expect(s.rate_limits?.five_hour?.resetsAtDate != nil)   // ISO string
        #expect(s.rate_limits?.seven_day?.resetsAtDate != nil)   // epoch number
    }

    @Test func missingFieldsDecodeToNil() throws {
        let s = try JSONDecoder().decode(StatusFileRaw.self, from: Data("{}".utf8))
        #expect(s.rate_limits == nil && s.model == nil)
        let t = try JSONDecoder().decode(StateFileRaw.self, from: Data("{}".utf8))
        #expect(t.session_id == nil)
        #expect(t.model_id == nil)
    }

    @Test func agentStatusRawValues() {
        #expect(AgentStatus(rawValue: "needs_you") == .needsYou)
        #expect(AgentStatus.working.rawValue == "working")
    }
}
