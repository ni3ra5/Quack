import Testing
@testable import QuackKit

@Suite struct ClaudeIntegrationScriptsTests {
    @Test func hookScriptShape() {
        let s = ClaudeIntegrationScripts.hookScript
        #expect(s.hasPrefix("#!/bin/bash"))
        #expect(s.contains(".state.json"))
        #expect(s.contains("session_id"))
        #expect(s.contains("exit 0"))          // fail-soft: never blocks Claude Code
        #expect(!s.contains("tac "))           // BSD userland: tail -r, not tac
        #expect(s.contains("model_id"))        // desktop sessions: model comes from the transcript
    }

    @Test func wrapperTemplateHasPlaceholder() {
        #expect(ClaudeIntegrationScripts.statusLineWrapperTemplate.contains("__PREV_STATUSLINE__"))
        #expect(ClaudeIntegrationScripts.statusLineWrapperTemplate.contains(".status.json"))
    }

    @Test func wrapperBakesPreviousCommand() {
        let s = ClaudeIntegrationScripts.statusLineWrapper(previousCommand: "/Users/x/.claude/statusline.sh")
        #expect(s.contains(#"printf '%s' "$INPUT" | "/Users/x/.claude/statusline.sh""#))
        #expect(!s.contains("__PREV_STATUSLINE__"))
    }

    @Test func wrapperWithoutPreviousEmitsModelName() {
        let s = ClaudeIntegrationScripts.statusLineWrapper(previousCommand: nil)
        #expect(s.contains("display_name"))
        #expect(!s.contains("__PREV_STATUSLINE__"))
    }

    @Test func hookEventsList() {
        #expect(ClaudeIntegrationScripts.hookEvents == ["SessionStart", "UserPromptSubmit", "PostToolUse", "Notification", "Stop", "SessionEnd"])
    }
}
