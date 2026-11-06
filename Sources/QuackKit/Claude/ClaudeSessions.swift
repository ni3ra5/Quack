import Foundation

/// One entry of Claude Code's live session registry, `~/.claude/sessions/<pid>.json`.
/// Claude Code (CLI, VS Code extension, desktop app) writes one per running
/// process. The format is internal and undocumented, so every field but the
/// identity is optional and unknown fields are ignored.
public struct ClaudeRegistryRecord: Decodable, Equatable, Sendable {
    public var pid: Int32
    public var sessionId: String
    public var cwd: String?
    public var name: String?
    public var entrypoint: String?
    public var kind: String?
    /// "busy" / "idle" / "waiting" / "shell".
    public var status: String?
    /// Epoch milliseconds.
    public var startedAt: Double?
    public var statusUpdatedAt: Double?
    /// The desktop app's own id ("local_…"), used for its deep link.
    public var hostSessionId: String?

    public init(pid: Int32, sessionId: String, cwd: String? = nil, name: String? = nil,
                entrypoint: String? = nil, kind: String? = "interactive", status: String? = nil,
                startedAt: Double? = nil, statusUpdatedAt: Double? = nil, hostSessionId: String? = nil) {
        self.pid = pid; self.sessionId = sessionId; self.cwd = cwd; self.name = name
        self.hostSessionId = hostSessionId
        self.entrypoint = entrypoint; self.kind = kind; self.status = status
        self.startedAt = startedAt; self.statusUpdatedAt = statusUpdatedAt
    }
}

/// The latest hook event Quack's Claude Code hook recorded for a session.
public struct ClaudeHookEvent: Equatable, Sendable {
    public var sessionId: String
    public var name: String              // hook_event_name
    public var toolName: String?
    public var notificationType: String?
    public var at: Date                  // when the hook wrote it

    public init(sessionId: String, name: String, toolName: String? = nil,
                notificationType: String? = nil, at: Date) {
        self.sessionId = sessionId; self.name = name; self.toolName = toolName
        self.notificationType = notificationType; self.at = at
    }

    /// Parses the hook's stdin JSON (as saved to disk by the hook command).
    public init?(json: Data, at: Date) {
        guard let obj = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let sid = obj["session_id"] as? String,
              let name = obj["hook_event_name"] as? String else { return nil }
        self.init(sessionId: sid, name: name, toolName: obj["tool_name"] as? String,
                  notificationType: obj["notification_type"] as? String, at: at)
    }

    /// Whether this event means the session is blocked on the user.
    public var isWaitingForUser: Bool {
        switch name {
        case "PermissionRequest", "Elicitation":
            return true
        case "Notification":
            return notificationType == "permission_prompt" || notificationType == "elicitation_dialog"
        case "PreToolUse":
            return toolName == "AskUserQuestion" || toolName == "ExitPlanMode"
        default:
            return false
        }
    }
}

public enum ClaudeSessionState: Int, Comparable, Sendable {
    case idle      // started, nothing run yet
    case running
    case done      // finished a turn, waiting for your next message
    case waiting   // blocked on you (permission, question, plan approval)

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

public enum ClaudeSessionSource: String, CaseIterable, Sendable {
    case desktop, vscode, terminal

    init(entrypoint: String?) {
        switch entrypoint {
        case "claude-desktop", "claude-desktop-3p", "local-agent": self = .desktop
        case "claude-vscode": self = .vscode
        default: self = .terminal
        }
    }

    public var label: String {
        switch self {
        case .desktop: return "Claude"
        case .vscode: return "VS Code"
        case .terminal: return "Terminal"
        }
    }
}

public struct ClaudeSession: Identifiable, Equatable, Sendable {
    public var id: String          // sessionId
    public var pid: Int32
    public var hostSessionId: String?
    public var name: String
    public var cwd: String
    public var source: ClaudeSessionSource
    public var state: ClaudeSessionState
    /// Last time anything about this session changed (used for dismissal).
    public var updatedAt: Date
    public var startedAt: Date
}

public enum ClaudeSessionResolver {
    /// Builds the visible session list.
    /// - `processStart` returns a live pid's start time, or nil if the pid is
    ///   dead. Registry files of exited processes linger, and pids get reused, so
    ///   a record only counts when its pid is alive AND started when it claims.
    /// - `dismissed` maps sessionId → when the user removed it; it stays hidden
    ///   until something newer happens in that session.
    /// - Sessions in progress (running/waiting) always show. Others only show
    ///   after activity since `activeSince` (Quack's launch), so old idle or
    ///   finished sessions don't flood the notch at startup.
    /// - A finished/idle session drops off after `staleAfter` without
    ///   activity. Running or waiting sessions never expire.
    public static func sessions(
        records: [ClaudeRegistryRecord],
        events: [String: ClaudeHookEvent],
        dismissed: [String: Date],
        activeSince: Date = .distantPast,
        now: Date = Date(),
        staleAfter: TimeInterval = 4 * 3600,
        processStart: (Int32) -> Date?
    ) -> [ClaudeSession] {
        var byId: [String: ClaudeSession] = [:]
        for r in records where (r.kind ?? "interactive") == "interactive" {
            guard let started = processStart(r.pid) else { continue }
            let startedAt = r.startedAt.map(date) ?? started
            // The registry is written a moment after the process starts.
            guard abs(startedAt.timeIntervalSince(started)) < 120 else { continue }

            let statusAt = r.statusUpdatedAt.map(date) ?? startedAt
            let event = events[r.sessionId]
            let state = state(status: r.status, statusAt: statusAt, startedAt: startedAt, event: event)
            // Just opened (a new session, or an old one clicked to read it):
            // no dot until it actually works on something.
            if state == .idle { continue }
            let updatedAt = max(statusAt, event?.at ?? .distantPast)
            let inProgress = state == .running || state == .waiting
            let hiddenUntil = max(dismissed[r.sessionId] ?? .distantPast,
                                  inProgress ? .distantPast : activeSince)
            if updatedAt <= hiddenUntil { continue }
            if state == .idle || state == .done,
               now.timeIntervalSince(updatedAt) > staleAfter { continue }

            let cwd = r.cwd ?? ""
            let name = r.name.flatMap { $0.isEmpty ? nil : $0 }
                ?? (cwd as NSString).lastPathComponent
            let s = ClaudeSession(id: r.sessionId, pid: r.pid, hostSessionId: r.hostSessionId,
                                  name: name, cwd: cwd,
                                  source: ClaudeSessionSource(entrypoint: r.entrypoint),
                                  state: state, updatedAt: updatedAt, startedAt: startedAt)
            // One session can briefly have two processes (resume/handoff): keep the newest.
            if let existing = byId[s.id], existing.updatedAt >= s.updatedAt { continue }
            byId[s.id] = s
        }
        return byId.values.sorted { $0.startedAt < $1.startedAt }
    }

    static func state(status: String?, statusAt: Date, startedAt: Date,
                      event: ClaudeHookEvent?) -> ClaudeSessionState {
        switch status {
        case "waiting":
            return .waiting
        case "busy", "shell":
            // The registry says "busy" for the whole turn, including while a
            // permission prompt or question waits; only the hook can tell.
            if let event, event.at >= statusAt, event.isWaitingForUser { return .waiting }
            return .running
        default:
            // Idle right after launch = new session; idle after a turn = done.
            return statusAt.timeIntervalSince(startedAt) > 3 ? .done : .idle
        }
    }

    private static func date(_ ms: Double) -> Date { Date(timeIntervalSince1970: ms / 1000) }
}

extension Array where Element == ClaudeSession {
    /// Sessions grouped by where they run, in a fixed app order, empty groups dropped.
    public var groupedBySource: [(source: ClaudeSessionSource, sessions: [ClaudeSession])] {
        ClaudeSessionSource.allCases.compactMap { src in
            let group = filter { $0.source == src }
            return group.isEmpty ? nil : (src, group)
        }
    }
}

/// Adds/removes Quack's hook in Claude Code's user settings
/// (`~/.claude/settings.json`). The hook saves each event's stdin JSON as
/// `<eventsDir>/<session>.json` (latest event per session wins); Quack reads
/// that folder. Pure dictionary transforms so they can be unit-tested.
public enum ClaudeHookConfig {
    /// Only the events needed to tell "blocked on you" from "working".
    public static let events = ["PreToolUse", "PostToolUse", "PostToolUseFailure",
                                "PermissionRequest", "Notification"]
    /// Marker used to recognise our entries.
    public static let marker = "Quack/claude-events"

    public static func command() -> String {
        // Write to a temp name, then rename, so Quack never reads a half file.
        #"d="$HOME/Library/Application Support/\#(marker)"; mkdir -p "$d" && f="$d/${CLAUDE_CODE_SESSION_ID:-$PPID}" && cat > "$f.$$.tmp" && mv -f "$f.$$.tmp" "$f.json""#
    }

    public static func isInstalled(in settings: [String: Any]) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        return events.allSatisfy { ev in
            ((hooks[ev] as? [[String: Any]]) ?? []).contains(where: isOurs)
        }
    }

    public static func installing(into settings: [String: Any]) -> [String: Any] {
        var out = removing(from: settings)
        var hooks = out["hooks"] as? [String: Any] ?? [:]
        for ev in events {
            var groups = hooks[ev] as? [[String: Any]] ?? []
            groups.append(["hooks": [["type": "command", "command": command(), "timeout": 5]]])
            hooks[ev] = groups
        }
        out["hooks"] = hooks
        return out
    }

    public static func removing(from settings: [String: Any]) -> [String: Any] {
        var out = settings
        guard var hooks = out["hooks"] as? [String: Any] else { return out }
        for (ev, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let kept = groups.filter { !isOurs($0) }
            if kept.isEmpty { hooks[ev] = nil } else { hooks[ev] = kept }
        }
        if hooks.isEmpty { out["hooks"] = nil } else { out["hooks"] = hooks }
        return out
    }

    private static func isOurs(_ group: [String: Any]) -> Bool {
        ((group["hooks"] as? [[String: Any]]) ?? []).contains {
            ($0["command"] as? String)?.contains(marker) == true
        }
    }
}
