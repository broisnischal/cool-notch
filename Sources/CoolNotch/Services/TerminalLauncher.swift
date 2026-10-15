import AppKit

/// Runs a command in the user's terminal of choice. Whichever supported terminal is
/// already running wins; otherwise the first one installed; Terminal.app is the
/// always-available fallback. Commands run through `zsh -lic` (or the terminal's own
/// login shell) so `claude` resolves from the user's PATH.
@MainActor
enum TerminalLauncher {
    private struct TermApp {
        let name: String
        let bundleID: String
        let kind: Kind
    }
    private enum Kind { case iterm, appleTerminal, ghostty, wezterm, kitty, alacritty, warp }

    private static let known: [TermApp] = [
        TermApp(name: "Warp",      bundleID: "dev.warp.Warp-Stable",   kind: .warp),
        TermApp(name: "iTerm2",    bundleID: "com.googlecode.iterm2",  kind: .iterm),
        TermApp(name: "Ghostty",   bundleID: "com.mitchellh.ghostty",  kind: .ghostty),
        TermApp(name: "WezTerm",   bundleID: "com.github.wez.wezterm", kind: .wezterm),
        TermApp(name: "kitty",     bundleID: "net.kovidgoyal.kitty",   kind: .kitty),
        TermApp(name: "Alacritty", bundleID: "org.alacritty",          kind: .alacritty),
        TermApp(name: "Terminal",  bundleID: "com.apple.Terminal",     kind: .appleTerminal),
    ]

    /// Display name of the terminal a launch would use right now (for tooltips).
    static var currentName: String { pick().name }

    private static func pick() -> TermApp {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        if let hit = known.first(where: { running.contains($0.bundleID) }) { return hit }
        if let hit = known.first(where: {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil
        }) { return hit }
        return known.last!   // Terminal.app always exists
    }

    /// Resume a Claude Code session in a fresh terminal window, optionally
    /// submitting `message` straight into it (`claude --resume <id> "<msg>"`).
    static func resumeClaude(uuid: String, cwd: String?, message: String? = nil) {
        var cmd = "claude --resume \(shellQuote(uuid))"
        if let m = message, !m.isEmpty { cmd += " \(shellQuote(m))" }
        run(cmd, in: cwd)
    }

    /// Run `command` in a new window/tab of the user's terminal, cd'ing first.
    static func run(_ command: String, in cwd: String?) {
        let cd = cwd.map { "cd \(shellQuote($0)) && " } ?? ""
        let full = cd + command
        let app = pick()
        switch app.kind {
        case .iterm:
            script("""
            tell application "iTerm2"
                activate
                set w to (create window with default profile)
                tell current session of w to write text \(appleQuote(full))
            end tell
            """)
        case .appleTerminal:
            script("""
            tell application "Terminal"
                activate
                do script \(appleQuote(full))
            end tell
            """)
        case .ghostty:
            openArgs(app.bundleID, ["-e", "zsh", "-lic", full])
        case .wezterm:
            openArgs(app.bundleID, ["start", "--", "zsh", "-lic", full])
        case .kitty:
            openArgs(app.bundleID, ["zsh", "-lic", full])
        case .alacritty:
            openArgs(app.bundleID, ["-e", "zsh", "-lic", full])
        case .warp:
            launchWarp(command: command, cwd: cwd)
        }
    }

    /// Warp can't exec a command from plain URIs, but it can run one via a Launch
    /// Configuration: write a one-shot config and open `warp://launch/<path>`.
    private static func launchWarp(command: String, cwd: String?) {
        let dir = cwd ?? FileManager.default.homeDirectoryForCurrentUser.path
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".warp/launch_configurations", isDirectory: true)
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let yaml = """
        ---
        name: Cool Notch
        windows:
          - tabs:
              - title: claude
                layout:
                  cwd: \(yamlQuote(dir))
                  commands:
                    - exec: \(yamlQuote(command))
        """
        let file = configDir.appendingPathComponent("coolnotch.yaml")
        guard (try? yaml.write(to: file, atomically: true, encoding: .utf8)) != nil,
              let encoded = file.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "warp://launch/\(encoded)")
        else { return }
        NSWorkspace.shared.open(url)
    }

    private static func yamlQuote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\")
               .replacingOccurrences(of: "\"", with: "\\\"")
               .replacingOccurrences(of: "\n", with: " ") + "\""
    }

    // MARK: plumbing

    private static func script(_ src: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", src]
        try? p.run()
    }

    private static func openArgs(_ bundleID: String, _ args: [String]) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.arguments = args
        cfg.createsNewApplicationInstance = true
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: cfg)
    }

    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
    private static func appleQuote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\")
               .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
