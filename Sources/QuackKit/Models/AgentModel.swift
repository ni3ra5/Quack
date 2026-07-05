import Foundation

/// Status of one Claude Code agent session as shown in the notch panel.
public enum AgentStatus: String, Codable, Sendable {
    case working
    case needsYou = "needs_you"
    case idle
}

/// One agent card: the reduced, display-ready view of a Claude Code session.
public struct AgentSnapshot: Equatable, Sendable, Identifiable {
    public var id: String { sessionID }
    public let sessionID: String
    public let project: String
    public let branch: String?
    public let model: String?
    public let status: AgentStatus
    public let statusMessage: String?
    /// 0...1 (TodoWrite ratio, else context-window fraction), nil = hide meter.
    public let progress: Double?
    /// This session's own context-window usage, 0...100 (from statusLine JSON).
    public let contextUsedPercent: Double?
    /// This session's own cumulative cost in USD (from statusLine JSON).
    public let costUSD: Double?
    /// This session's own 5h rate-limit window usage, 0...100.
    public let fiveHourUsedPercent: Double?
    /// This session's own 7d rate-limit window usage, 0...100.
    public let sevenDayUsedPercent: Double?
    public let lastUpdate: Date
    /// pid of the GUI app hosting this session (Terminal, iTerm2, VS Code,
    /// Claude desktop, ...), captured by the SessionStart hook's parent-chain
    /// walk. nil when unknown or the hook predates this field.
    public let hostPID: Int?

    public init(sessionID: String, project: String, branch: String?, model: String?,
                status: AgentStatus, statusMessage: String?, progress: Double?,
                contextUsedPercent: Double?, costUSD: Double?, fiveHourUsedPercent: Double?,
                sevenDayUsedPercent: Double?, lastUpdate: Date, hostPID: Int?) {
        self.sessionID = sessionID
        self.project = project
        self.branch = branch
        self.model = model
        self.status = status
        self.statusMessage = statusMessage
        self.progress = progress
        self.contextUsedPercent = contextUsedPercent
        self.costUSD = costUSD
        self.fiveHourUsedPercent = fiveHourUsedPercent
        self.sevenDayUsedPercent = sevenDayUsedPercent
        self.lastUpdate = lastUpdate
        self.hostPID = hostPID
    }
}

/// On-disk shape of ~/.claude/quack/sessions/<id>.state.json (written by
/// hook.sh). Every field optional — hooks are fail-soft and versions drift.
public struct StateFileRaw: Decodable, Equatable, Sendable {
    public let session_id: String?
    public let status: String?
    public let event: String?
    public let cwd: String?
    public let project: String?
    public let branch: String?
    public let ts: String?
    public let last_tool: String?
    public let last_tool_target: String?
    public let last_assistant_line: String?
    public let notification_message: String?
    public let todos_completed: Int?
    public let todos_total: Int?
    /// Model id captured from the transcript by the Stop hook (e.g. "claude-fable-5").
    public let model_id: String?
    /// pid of the GUI app hosting this session, captured at SessionStart.
    public let host_pid: Int?
    /// Name of the GUI app hosting this session (e.g. "Terminal"), captured at SessionStart.
    public let host_app: String?
}

/// On-disk shape of <id>.status.json — the raw Claude Code statusLine JSON.
/// Decoded defensively: only the fields the panel needs, all optional.
public struct StatusFileRaw: Decodable, Sendable {
    public struct Model: Decodable, Sendable { public let display_name: String? }
    public struct ContextWindow: Decodable, Sendable { public let used_percentage: Double? }

    /// One rate-limit window. `resets_at` arrives as an epoch-seconds number
    /// (the real path, per Claude Code's statusline docs) or, defensively, an
    /// ISO-8601 string — accept both.
    public struct RateWindow: Decodable, Sendable {
        public let used_percentage: Double?
        public let resetsAtDate: Date?

        enum CodingKeys: String, CodingKey { case used_percentage, resets_at }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            used_percentage = try? c.decodeIfPresent(Double.self, forKey: .used_percentage)
            if let epoch = try? c.decodeIfPresent(Double.self, forKey: .resets_at) {
                resetsAtDate = Date(timeIntervalSince1970: epoch)
            } else if let iso = try? c.decodeIfPresent(String.self, forKey: .resets_at) {
                resetsAtDate = ISO8601Parse.date(from: iso)
            } else {
                resetsAtDate = nil
            }
        }
    }

    public struct RateLimits: Decodable, Sendable {
        public let five_hour: RateWindow?
        public let seven_day: RateWindow?
    }

    public struct Cost: Decodable, Sendable { public let total_cost_usd: Double? }

    public let session_id: String?
    public let model: Model?
    public let context_window: ContextWindow?
    public let rate_limits: RateLimits?
    public let cost: Cost?
}

/// Shared defensive ISO-8601 parsing (with and without fractional seconds).
public enum ISO8601Parse {
    public static func date(from string: String) -> Date? {
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: string) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: string)
    }
}
