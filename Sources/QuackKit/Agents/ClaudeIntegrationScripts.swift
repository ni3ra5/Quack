import Foundation

/// Bash sources Quack installs into ~/.claude/quack/ when the user enables the
/// Claude Code integration. Kept as pure constants so the shape is unit-tested
/// and the installer only does file IO. Fail-soft by design: every path exits 0
/// so a broken script can never block Claude Code itself.
public enum ClaudeIntegrationScripts {
    /// Hook events Quack registers. One shared script, event name as $1.
    public static let hookEvents = ["SessionStart", "UserPromptSubmit", "PostToolUse", "Notification", "Stop", "SessionEnd"]

    public static let hookScript = #"""
    #!/bin/bash
    # Quack Claude Code integration hook. Writes per-session agent state to
    # ~/.claude/quack/sessions/<session_id>.state.json for the notch panel.
    # Installed/removed by Quack.app (Settings -> Windows -> Notch). Fail-soft:
    # every exit path is 0 so this can never block Claude Code.
    EVENT="$1"
    DIR="$HOME/.claude/quack/sessions"
    mkdir -p "$DIR" 2>/dev/null || exit 0
    command -v jq >/dev/null 2>&1 || exit 0
    INPUT=$(cat)
    SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
    [ -n "$SID" ] || exit 0
    FILE="$DIR/$SID.state.json"
    CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
    NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    STATUS=""
    case "$EVENT" in
      SessionStart) STATUS="idle" ;;
      UserPromptSubmit|PostToolUse) STATUS="working" ;;
      Stop|Notification) STATUS="needs_you" ;;
      SessionEnd) STATUS="ended" ;;
    esac

    EXTRA='{}'
    if [ "$EVENT" = "PostToolUse" ]; then
      TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
      TARGET=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.command // .tool_input.pattern // empty' 2>/dev/null | head -1 | cut -c1-200)
      EXTRA=$(jq -n --arg t "$TOOL" --arg g "$TARGET" '{last_tool:$t, last_tool_target:$g}')
      if [ "$TOOL" = "TodoWrite" ]; then
        COUNTS=$(printf '%s' "$INPUT" | jq '{todos_total: ((.tool_input.todos // [])|length), todos_completed: ([(.tool_input.todos // [])[]|select(.status=="completed")]|length)}' 2>/dev/null)
        [ -n "$COUNTS" ] && EXTRA=$(printf '%s' "$EXTRA" | jq --argjson c "$COUNTS" '. + $c')
      fi
    fi
    if [ "$EVENT" = "Notification" ]; then
      MSG=$(printf '%s' "$INPUT" | jq -r '.message // empty' 2>/dev/null | head -1 | cut -c1-200)
      [ -n "$MSG" ] && EXTRA=$(jq -n --arg m "$MSG" '{notification_message:$m}')
    fi
    if [ "$EVENT" = "Stop" ]; then
      TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
      if [ -f "$TRANSCRIPT" ]; then
        LAST=$(tail -300 "$TRANSCRIPT" 2>/dev/null | jq -rs '[.[] | select(.type=="assistant" and .isSidechain != true) | .message.content[]? | select(.type=="text") | .text] | last // empty' 2>/dev/null | head -1 | cut -c1-200)
        [ -n "$LAST" ] && EXTRA=$(jq -n --arg l "$LAST" '{last_assistant_line:$l}')
        # Model id from the transcript: desktop-app sessions never invoke the
        # statusLine command, so this is the only model source there.
        MODEL_ID=$(tail -300 "$TRANSCRIPT" 2>/dev/null | jq -rs '[.[] | select(.type=="assistant" and .isSidechain != true) | .message.model // empty] | last // empty' 2>/dev/null | head -1 | cut -c1-64)
        [ -n "$MODEL_ID" ] && EXTRA=$(printf '%s' "$EXTRA" | jq --arg m "$MODEL_ID" '. + {model_id:$m}')
      fi
    fi

    PROJECT=""; BRANCH=""
    if [ -n "$CWD" ]; then
      PROJECT=$(basename "$CWD")
      BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null)
    fi

    BASE=$(jq -n --arg sid "$SID" --arg st "$STATUS" --arg ev "$EVENT" --arg cwd "$CWD" \
      --arg p "$PROJECT" --arg b "$BRANCH" --arg ts "$NOW" \
      '{session_id:$sid, status:$st, event:$ev, cwd:$cwd, project:$p, branch:$b, ts:$ts} | with_entries(select(.value != ""))')

    OLD='{}'
    if [ -f "$FILE" ]; then
      CANDIDATE=$(cat "$FILE" 2>/dev/null)
      printf '%s' "$CANDIDATE" | jq -e . >/dev/null 2>&1 && OLD="$CANDIDATE"
    fi
    printf '%s' "$OLD" | jq --argjson base "$BASE" --argjson extra "$EXTRA" '. * $base * $extra' > "$FILE.tmp" 2>/dev/null \
      && mv "$FILE.tmp" "$FILE" 2>/dev/null
    exit 0
    """#

    public static let statusLineWrapperTemplate = #"""
    #!/bin/bash
    # Quack statusLine wrapper: captures the status JSON for the notch panel,
    # then delegates to the previous statusLine command so the visible status
    # line is unchanged. Installed/removed by Quack.app.
    DIR="$HOME/.claude/quack/sessions"
    INPUT=$(cat)
    if command -v jq >/dev/null 2>&1; then
      SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
      if [ -n "$SID" ]; then
        mkdir -p "$DIR" 2>/dev/null
        printf '%s' "$INPUT" > "$DIR/$SID.status.json.tmp" 2>/dev/null \
          && mv "$DIR/$SID.status.json.tmp" "$DIR/$SID.status.json" 2>/dev/null
      fi
    fi
    __PREV_STATUSLINE__
    """#

    /// Bakes the delegation line. With a previous command, pipe the same stdin
    /// into it; without one, emit the model name so the status line isn't blank.
    public static func statusLineWrapper(previousCommand: String?) -> String {
        let delegation: String
        if let previousCommand, !previousCommand.isEmpty {
            delegation = #"printf '%s' "$INPUT" | "\#(previousCommand)""#
        } else {
            delegation = #"command -v jq >/dev/null 2>&1 && printf '%s' "$INPUT" | jq -r '.model.display_name // ""'"#
        }
        return statusLineWrapperTemplate.replacingOccurrences(of: "__PREV_STATUSLINE__", with: delegation)
    }
}
