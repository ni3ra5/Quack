import AppKit
import Darwin
import QuackKit

/// Tracks every running Claude Code session (desktop app, VS Code, terminal)
/// and drives the notch indicator.
///
/// Sources: Claude Code's own registry `~/.claude/sessions/<pid>.json` (which
/// sessions exist, busy/idle, name) plus the latest event per session written
/// by Quack's optional hook (whether a session is blocked on a permission
/// prompt or a question). No Accessibility permission or event taps involved.
@MainActor
final class ClaudeSessionMonitor: ObservableObject, ManagedService {
    @Published private(set) var sessions: [ClaudeSession] = []
    @Published private(set) var hooksInstalled = false
    @Published var hookError: String?

    private let home = FileManager.default.homeDirectoryForCurrentUser
    private var registryDir: URL { home.appendingPathComponent(".claude/sessions") }
    private var eventsDir: URL { home.appendingPathComponent("Library/Application Support/\(ClaudeHookConfig.marker)") }
    private var settingsFile: URL { home.appendingPathComponent(".claude/settings.json") }

    private var timer: Timer?
    private var dismissed: [String: Date] = [:]
    private var appByPid: [Int32: NSRunningApplication] = [:]
    /// Sessions only show once they do something after Quack starts.
    private let launchedAt = Date()
    private lazy var notch = NotchPanelController(
        onOpen: { [weak self] in self?.open($0) },
        onDismiss: { [weak self] in self?.dismiss($0) })

    init() { hooksInstalled = Self.readSettings(settingsFile).map(ClaudeHookConfig.isInstalled) ?? false }

    func start() {
        refresh()
        // ponytail: 1 s poll of a handful of tiny files; registry files are
        // rewritten in place, so a directory watcher would miss status changes.
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate(); timer = nil
        sessions = []
        notch.update(sessions: [])
    }

    func dismiss(_ id: String) {
        dismissed[id] = Date()
        refresh()
    }

    private func refresh() {
        let fm = FileManager.default
        let decoder = JSONDecoder()
        let records = ((try? fm.contentsOfDirectory(at: registryDir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(ClaudeRegistryRecord.self, from: Data(contentsOf: $0)) }

        var events: [String: ClaudeHookEvent] = [:]
        let liveIds = Set(records.map(\.sessionId))
        for url in (try? fm.contentsOfDirectory(at: eventsDir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        where url.pathExtension == "json" {
            let at = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            guard let data = try? Data(contentsOf: url), let e = ClaudeHookEvent(json: data, at: at) else { continue }
            if !liveIds.contains(e.sessionId), Date().timeIntervalSince(at) > 3600 {
                try? fm.removeItem(at: url)   // session is long gone
                continue
            }
            if (events[e.sessionId]?.at ?? .distantPast) < at { events[e.sessionId] = e }
        }

        let next = ClaudeSessionResolver.sessions(records: records, events: events,
                                                  dismissed: dismissed, activeSince: launchedAt,
                                                  processStart: Self.processStart)
        if next != sessions { sessions = next }
        // The app a session runs in never changes, so look each pid up once.
        let pids = Set(next.map(\.pid))
        appByPid = appByPid.filter { pids.contains($0.key) && !$0.value.isTerminated }
        for pid in pids where appByPid[pid] == nil {
            if let app = Self.owningApp(of: pid) { appByPid[pid] = app }
        }
        notch.update(sessions: next, apps: appByPid)
    }

    /// Brings the session's window to the front.
    func open(_ session: ClaudeSession) {
        let app = Self.owningApp(of: session.pid)
        switch session.source {
        case .desktop:
            // The desktop app's own "open this Code session" link.
            if let host = session.hostSessionId,
               let url = URL(string: "claude://code/continue?session=\(host)") {
                NSWorkspace.shared.open(url)
            } else {
                Self.bringToFront(app)
            }
        case .vscode:
            // VS Code (or a fork like Cursor): focus the window for this folder,
            // then ask the Claude extension, in that window, to show the session.
            guard let app, let appURL = app.bundleURL else { return }
            let scheme = Self.urlScheme(of: appURL)
            NSWorkspace.shared.open([URL(fileURLWithPath: session.cwd)], withApplicationAt: appURL,
                                    configuration: NSWorkspace.OpenConfiguration()) { _, _ in
                guard let scheme,
                      let url = URL(string: "\(scheme)://anthropic.claude-code/open?session=\(session.id)")
                else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSWorkspace.shared.open(url) }
            }
        case .terminal:
            Self.bringToFront(app)
        }
    }

    /// `NSRunningApplication.activate()` is ignored when called from a
    /// background app like Quack (macOS 14 cooperative activation); asking
    /// Launch Services to "open" the running app does bring it forward.
    private static func bringToFront(_ app: NSRunningApplication?) {
        guard let url = app?.bundleURL else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    /// The GUI app a process runs under (Claude, VS Code, Terminal, iTerm…),
    /// found by walking up its parent processes.
    private static func owningApp(of pid: Int32) -> NSRunningApplication? {
        var p = pid
        for _ in 0..<16 {
            if let app = NSRunningApplication(processIdentifier: p), app.activationPolicy == .regular { return app }
            guard let parent = kinfo(p)?.kp_eproc.e_ppid, parent > 1 else { return nil }
            p = parent
        }
        return nil
    }

    private static func urlScheme(of appURL: URL) -> String? {
        let types = Bundle(url: appURL)?.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]]
        return types?.lazy.compactMap { ($0["CFBundleURLSchemes"] as? [String])?.first }.first
    }

    /// Start time of a live process, or nil if no such pid.
    private nonisolated static func processStart(_ pid: Int32) -> Date? {
        guard let tv = kinfo(pid)?.kp_proc.p_starttime else { return nil }
        return Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000)
    }

    private nonisolated static func kinfo(_ pid: Int32) -> kinfo_proc? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info
    }

    // MARK: Hook install (edits ~/.claude/settings.json, backup kept alongside)

    func setHooksInstalled(_ install: Bool) {
        hookError = nil
        let fm = FileManager.default
        let exists = fm.fileExists(atPath: settingsFile.path)
        guard let current = exists ? Self.readSettings(settingsFile) : [:] else {
            hookError = "Couldn't read ~/.claude/settings.json (invalid JSON?). Nothing was changed."
            return
        }
        let updated = install ? ClaudeHookConfig.installing(into: current)
                              : ClaudeHookConfig.removing(from: current)
        do {
            if exists {
                let backup = settingsFile.appendingPathExtension("quack-backup")
                try? fm.removeItem(at: backup)
                try fm.copyItem(at: settingsFile, to: backup)
            } else {
                try fm.createDirectory(at: settingsFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            }
            let data = try JSONSerialization.data(withJSONObject: updated, options: [.prettyPrinted, .withoutEscapingSlashes])
            try data.write(to: settingsFile, options: .atomic)
            hooksInstalled = install
        } catch {
            hookError = "Couldn't update ~/.claude/settings.json: \(error.localizedDescription)"
        }
    }

    private static func readSettings(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
