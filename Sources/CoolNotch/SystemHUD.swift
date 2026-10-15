import Foundation

/// Best-effort suppression of the macOS volume/brightness OSD so only the notch
/// HUD shows. `OSDUIHelper` is the agent that draws the system popup; we boot it
/// out when suppression is enabled and kill it on each change as a backstop
/// (it's demand-launched and can respawn). No sudo required.
enum SystemHUD {
    static func setSuppressed(_ on: Bool) {
        let uid = String(getuid())
        if on {
            launchctl(["bootout", "gui/\(uid)/com.apple.OSDUIHelper"])
            killOSD()
        } else {
            launchctl(["bootstrap", "gui/\(uid)",
                       "/System/Library/LaunchAgents/com.apple.OSDUIHelper.plist"])
        }
    }

    /// Kill the popup helper (it respawns; called right when a change fires).
    static func killOSD() { run("/usr/bin/killall", ["-9", "OSDUIHelper"]) }

    private static func launchctl(_ args: [String]) { run("/bin/launchctl", args) }

    private static func run(_ path: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try? p.run()
    }
}
