import Foundation
import AppKit
import os

/// Launch-at-login via a LaunchAgent plist. `SMAppService.mainApp` is flaky for
/// self-signed / non-notarized apps; a LaunchAgent in ~/Library/LaunchAgents is
/// rock-solid and launchd loads it automatically at login.
enum LaunchAtLogin {
    private static let label = "com.quack.menubar.login"

    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func set(_ enabled: Bool) {
        enabled ? enable() : disable()
    }

    private static func enable() {
        // Launch the installed bundle via `open` so LaunchServices handles it.
        let appPath = Bundle.main.bundlePath
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": ["/usr/bin/open", appPath],
            "RunAtLoad": true,
        ]
        do {
            try FileManager.default.createDirectory(
                at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: plistURL)
            // Register now too (so it's known to launchd this session).
            run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", plistURL.path])
        } catch {
            Log.permissions.error("Launch-at-login enable failed: \(error.localizedDescription)")
        }
    }

    private static func disable() {
        run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(label)"])
        try? FileManager.default.removeItem(at: plistURL)
    }

    private static func run(_ tool: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = nil
        p.standardError = nil
        try? p.run()
        p.waitUntilExit()
    }
}
