import Foundation

/// Thrown by `ClaudeSettingsEditor` when the input settings blob can't be
/// safely mutated without risking silent data loss.
public enum ClaudeSettingsEditorError: Error, Equatable {
    /// The associated String is a short description of what was malformed,
    /// intended for logs (e.g. "top-level JSON is not an object").
    case malformedSettings(String)
}

/// Pure add/remove of Quack's Claude Code integration inside a settings.json
/// blob. All file IO lives in the app-layer installer; this is Data -> Data so
/// the exact mutation is unit-tested. Quack's entries are identified by the
/// hook-script path marker — nothing else is ever touched.
public enum ClaudeSettingsEditor {
    public static let hookMarker = "/.claude/quack/hook.sh"

    /// Non-throwing and fully defensive: any unexpected shape (non-dict hooks,
    /// non-array event value, non-dict array elements) is tolerated and simply
    /// scanned around, yielding `false` rather than propagating an error.
    public static func integrationPresent(in json: Data) -> Bool {
        guard let root = decode(json), let hooks = root["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { value in
            guard let entries = value as? [Any] else { return false }
            return entries.contains { ($0 as? [String: Any]).map(isOurs) ?? false }
        }
    }

    /// Throws `.malformedSettings` rather than silently discarding user data
    /// when the input can't be safely merged into: non-empty input that isn't
    /// parseable JSON, a top-level value that isn't an object, a `hooks` value
    /// that isn't an object, or an event value that isn't an array. Empty (or
    /// whitespace-only) input is treated as `{}` — that's the legitimate
    /// missing-file case, not malformed input.
    public static func addingIntegration(to json: Data, hookCommand: String,
                                         statusLineCommand: String) throws -> (updated: Data, previousStatusLineCommand: String?) {
        var root = try decodeOrThrow(json)
        var hooks: [String: Any] = [:]
        if let rawHooks = root["hooks"] {
            guard let dict = rawHooks as? [String: Any] else {
                throw ClaudeSettingsEditorError.malformedSettings("hooks is not an object")
            }
            hooks = dict
        }
        for event in ClaudeIntegrationScripts.hookEvents {
            var entries: [Any] = []
            if let rawEntries = hooks[event] {
                guard let array = rawEntries as? [Any] else {
                    throw ClaudeSettingsEditorError.malformedSettings("hooks.\(event) is not an array")
                }
                entries = array
            }
            let alreadyOurs = entries.contains { ($0 as? [String: Any]).map(isOurs) ?? false }
            if !alreadyOurs {
                entries.append(["hooks": [["type": "command", "command": "\(hookCommand) \(event)"]]])
            }
            hooks[event] = entries
        }
        root["hooks"] = hooks

        var previous: String?
        if let sl = root["statusLine"] as? [String: Any],
           let cmd = sl["command"] as? String, cmd != statusLineCommand {
            previous = cmd
        }
        // Deliberate: a non-dict/malformed statusLine value is not inspected
        // for a "previous command" (there isn't one to restore) and is simply
        // overwritten below. It was never a restorable command, so this is
        // not data loss in the same sense as the hooks cases above.
        root["statusLine"] = ["type": "command", "command": statusLineCommand]
        return (try encode(root), previous)
    }

    /// Removal always makes progress: unlike `addingIntegration`, this does
    /// NOT throw on a malformed `hooks` shape (non-dict hooks, non-array event
    /// value) — it tolerates and skips those rather than blocking removal. It
    /// DOES throw `.malformedSettings` when the top-level input itself is
    /// unparseable/non-object, since there's nothing sane to write back in
    /// that case.
    public static func removingIntegration(from json: Data,
                                           restoringStatusLineCommand previous: String?) throws -> Data {
        var root = try decodeOrThrow(json)
        if var hooks = root["hooks"] as? [String: Any] {
            for (event, value) in hooks {
                guard let entries = value as? [Any] else { continue }
                let remaining = entries.filter { !(($0 as? [String: Any]).map(isOurs) ?? false) }
                if remaining.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = remaining }
            }
            if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
        }
        if let previous, !previous.isEmpty {
            root["statusLine"] = ["type": "command", "command": previous]
        } else {
            root.removeValue(forKey: "statusLine")
        }
        return try encode(root)
    }

    // MARK: - Internals

    private static func isOurs(_ entry: [String: Any]) -> Bool {
        ((entry["hooks"] as? [[String: Any]]) ?? [])
            .contains { (($0["command"] as? String) ?? "").contains(hookMarker) }
    }

    private static func decode(_ json: Data) -> [String: Any]? {
        guard !json.isEmpty else { return nil }
        return (try? JSONSerialization.jsonObject(with: json)) as? [String: Any]
    }

    /// Empty or whitespace-only input decodes to `{}` (legitimate
    /// missing-file case). Any other non-empty input that fails to parse as
    /// JSON, or that parses to a non-object top level, throws rather than
    /// silently replacing the caller's file contents.
    private static func decodeOrThrow(_ json: Data) throws -> [String: Any] {
        let text = String(decoding: json, as: UTF8.self)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [:] }
        guard let parsed = try? JSONSerialization.jsonObject(with: json) else {
            throw ClaudeSettingsEditorError.malformedSettings("input is not valid JSON")
        }
        guard let root = parsed as? [String: Any] else {
            throw ClaudeSettingsEditorError.malformedSettings("top-level JSON is not an object")
        }
        return root
    }

    private static func encode(_ root: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }
}
