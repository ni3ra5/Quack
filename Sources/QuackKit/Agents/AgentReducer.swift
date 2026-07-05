import Foundation

/// One session's on-disk pair (state from hooks, status from the statusLine
/// wrapper) plus file mtimes, as read by the app-layer watcher.
public struct SessionFiles: Sendable {
    public let sessionID: String
    public let state: StateFileRaw?
    public let status: StatusFileRaw?
    public let stateModified: Date?
    public let statusModified: Date?

    public init(sessionID: String, state: StateFileRaw?, status: StatusFileRaw?,
                stateModified: Date?, statusModified: Date?) {
        self.sessionID = sessionID
        self.state = state
        self.status = status
        self.stateModified = stateModified
        self.statusModified = statusModified
    }
}

/// Pure reduction of session files to display state. No system dependencies;
/// `now` is always injected so staleness is testable.
public enum AgentReducer {
    public static let defaultStaleAfter: TimeInterval = 15 * 60

    /// Live agent cards, sorted needs-you → working → idle, newest first within
    /// a group. Sessions that ended, went stale, or never emitted hook state
    /// (status-only) produce no card.
    public static func snapshots(from files: [SessionFiles], now: Date,
                                 staleAfter: TimeInterval = defaultStaleAfter) -> [AgentSnapshot] {
        files.compactMap { snapshot(from: $0, now: now, staleAfter: staleAfter) }
            .sorted { a, b in
                if rank(a.status) != rank(b.status) { return rank(a.status) < rank(b.status) }
                return a.lastUpdate > b.lastUpdate
            }
    }

    /// Plain single-line per-agent stat, built from this session's OWN status
    /// file (rate limits are per-account, so a global aggregate would mix
    /// accounts for multi-profile users). Parts are omitted when absent —
    /// desktop sessions with no status file may yield just the model, or nil.
    public static func statLine(for snapshot: AgentSnapshot) -> String? {
        var parts: [String] = []
        if let model = snapshot.model { parts.append(model) }
        if let pct = snapshot.contextUsedPercent { parts.append("ctx \(Int(pct.rounded()))%") }
        if let cost = snapshot.costUSD { parts.append(String(format: "$%.2f", cost)) }
        if let p = snapshot.fiveHourUsedPercent { parts.append("5h \(Int(p.rounded()))%") }
        if let p = snapshot.sevenDayUsedPercent { parts.append("7d \(Int(p.rounded()))%") }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    /// Turns a raw model id into a short versioned display name.
    ///
    /// Strips a leading "claude-" prefix, a trailing "[...]" bracket suffix,
    /// and a trailing date-like numeric token (6+ digits, e.g. "-20251001").
    /// The first remaining token is the family (capitalized); any remaining
    /// numeric tokens are joined with "." as the version.
    ///
    /// Examples: "claude-opus-4-8" -> "Opus 4.8"; "claude-fable-5" -> "Fable 5";
    /// "claude-haiku-4-5-20251001" -> "Haiku 4.5"; "claude-opus-4-8[1m]" -> "Opus 4.8".
    /// Unrecognized shapes (no "claude-" prefix) are returned unchanged.
    public static func modelDisplayName(id: String) -> String {
        guard id.hasPrefix("claude-") else { return id }
        var rest = String(id.dropFirst("claude-".count))

        if let bracketRange = rest.range(of: "[", options: .backwards) {
            rest = String(rest[rest.startIndex..<bracketRange.lowerBound])
        }

        var tokens = rest.split(separator: "-").map(String.init)
        if let last = tokens.last, last.count >= 6, last.allSatisfy(\.isNumber) {
            tokens.removeLast()
        }

        guard let family = tokens.first else { return id }
        let versionTokens = tokens.dropFirst()
        var display = family.prefix(1).uppercased() + family.dropFirst()
        if !versionTokens.isEmpty {
            display += " " + versionTokens.joined(separator: ".")
        }
        return display
    }

    // MARK: - Internals (internal for @testable reach if needed)

    static func snapshot(from f: SessionFiles, now: Date, staleAfter: TimeInterval) -> AgentSnapshot? {
        guard let state = f.state else { return nil }
        if state.status == "ended" { return nil }
        let last = state.ts.flatMap(ISO8601Parse.date(from:))
            ?? f.stateModified ?? f.statusModified ?? .distantPast
        guard now.timeIntervalSince(last) <= staleAfter else { return nil }
        let status = agentStatus(state.status)
        let project = nonEmpty(state.project)
            ?? nonEmpty(state.cwd).map { ($0 as NSString).lastPathComponent }
            ?? "unknown"
        let model = nonEmpty(state.model_id).map(modelDisplayName(id:)) ?? f.status?.model?.display_name
        return AgentSnapshot(
            sessionID: f.sessionID,
            project: project,
            branch: nonEmpty(state.branch),
            model: model,
            status: status,
            statusMessage: statusMessage(state: state, status: status),
            progress: progress(state: state, status: f.status),
            contextUsedPercent: f.status?.context_window?.used_percentage,
            costUSD: f.status?.cost?.total_cost_usd,
            fiveHourUsedPercent: f.status?.rate_limits?.five_hour?.used_percentage,
            sevenDayUsedPercent: f.status?.rate_limits?.seven_day?.used_percentage,
            lastUpdate: last,
            hostPID: state.host_pid
        )
    }

    static func agentStatus(_ raw: String?) -> AgentStatus {
        AgentStatus(rawValue: raw ?? "") ?? .idle
    }

    static func statusMessage(state: StateFileRaw, status: AgentStatus) -> String? {
        switch status {
        case .working:
            return toolPhrase(tool: nonEmpty(state.last_tool), target: nonEmpty(state.last_tool_target)) ?? "Working…"
        case .needsYou:
            if state.event == "Notification", let m = nonEmpty(state.notification_message) { return m }
            return nonEmpty(state.last_assistant_line) ?? "Waiting for you"
        case .idle:
            return nonEmpty(state.last_assistant_line)
        }
    }

    /// "Editing settings.json" style phrases from the last tool call.
    static func toolPhrase(tool: String?, target: String?) -> String? {
        guard let tool, !tool.isEmpty else { return nil }
        let base = target.map { ($0 as NSString).lastPathComponent }
        switch tool {
        case "Edit", "Write", "NotebookEdit": return base.map { "Editing \($0)" } ?? "Editing files"
        case "Read": return base.map { "Reading \($0)" } ?? "Reading files"
        case "Bash":
            guard let t = target, !t.isEmpty else { return "Running a command" }
            return "Running \(String(t.prefix(32)))"
        case "Grep", "Glob": return "Searching the codebase"
        case "Task", "Agent": return "Delegating to a subagent"
        case "WebFetch", "WebSearch": return "Browsing the web"
        case "TodoWrite": return "Updating the plan"
        default: return tool
        }
    }

    static func progress(state: StateFileRaw, status: StatusFileRaw?) -> Double? {
        if let total = state.todos_total, total > 0, let done = state.todos_completed {
            return min(max(Double(done) / Double(total), 0), 1)
        }
        if let pct = status?.context_window?.used_percentage {
            return min(max(pct / 100, 0), 1)
        }
        return nil
    }

    /// Treats empty strings (present in real state files, e.g.
    /// `"last_tool_target": ""`) as absent.
    static func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return s
    }

    private static func rank(_ s: AgentStatus) -> Int {
        switch s {
        case .needsYou: return 0
        case .working: return 1
        case .idle: return 2
        }
    }
}
