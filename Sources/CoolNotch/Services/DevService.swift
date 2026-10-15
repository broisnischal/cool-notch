import SwiftUI
import Combine

/// Developer signals: listening TCP ports (polled) and on-demand git/PR status
/// for a working directory. Uses the `git`, `lsof`, and `gh` CLIs.
@MainActor
final class DevService: ObservableObject {
    @Published private(set) var ports: [PortInfo] = []
    private var timer: AnyCancellable?

    init() {
        refreshPorts()
        timer = Timer.publish(every: 6, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refreshPorts() }
    }

    func refreshPorts() {
        Task.detached(priority: .utility) {
            let list = Self.listeningPorts()
            await MainActor.run { self.ports = list }
        }
    }

    func gitStatus(cwd: String) async -> GitStatus? {
        await Task.detached(priority: .utility) { Self.git(cwd) }.value
    }

    // MARK: - Off-main helpers

    private nonisolated static func run(_ launch: String, _ args: [String], cwd: String? = nil) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launch)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        // Inherit a PATH that includes Homebrew (gh/git live there).
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (env["PATH"] ?? "") + ":/opt/homebrew/bin:/usr/local/bin:/usr/bin"
        p.environment = env
        do { try p.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private nonisolated static func listeningPorts() -> [PortInfo] {
        let out = run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN"])
        var seen = Set<String>()
        var result: [PortInfo] = []
        for line in out.split(separator: "\n").dropFirst() {
            let cols = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard cols.count >= 10 else { continue }
            let proc = cols[0]
            let pid = Int(cols[1]) ?? 0
            // NAME column (e.g. "*:3000", "127.0.0.1:5432", "[::1]:5432") precedes "(LISTEN)".
            let addr = cols[cols.count - 2]
            guard let colon = addr.lastIndex(of: ":"),
                  let port = Int(addr[addr.index(after: colon)...]) else { continue }
            let key = "\(port)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(PortInfo(port: port, process: proc, pid: pid))
        }
        return result.sorted { $0.port < $1.port }
    }

    private nonisolated static func git(_ cwd: String) -> GitStatus? {
        let inside = run("/usr/bin/git", ["rev-parse", "--is-inside-work-tree"], cwd: cwd)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard inside == "true" else { return nil }

        let branch = run("/usr/bin/git", ["rev-parse", "--abbrev-ref", "HEAD"], cwd: cwd)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let dirty = run("/usr/bin/git", ["status", "--porcelain"], cwd: cwd)
            .split(separator: "\n").count

        var ahead = 0, behind = 0
        let counts = run("/usr/bin/git", ["rev-list", "--left-right", "--count", "@{upstream}...HEAD"], cwd: cwd)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0 == "\t" || $0 == " " })
        if counts.count == 2 { behind = Int(counts[0]) ?? 0; ahead = Int(counts[1]) ?? 0 }

        var status = GitStatus(branch: branch.isEmpty ? "detached" : branch,
                               ahead: ahead, behind: behind, dirty: dirty)

        // Best-effort PR info via gh (may be absent / unauthenticated).
        let pr = run("/opt/homebrew/bin/gh",
                     ["pr", "view", "--json", "title,state,statusCheckRollup"], cwd: cwd)
        if let d = pr.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            status.prTitle = obj["title"] as? String
            status.prState = obj["state"] as? String
            if let rollup = obj["statusCheckRollup"] as? [[String: Any]], !rollup.isEmpty {
                let fail = rollup.filter { ($0["conclusion"] as? String) == "FAILURE" }.count
                let pass = rollup.filter { ($0["conclusion"] as? String) == "SUCCESS" }.count
                status.checks = fail > 0 ? "\(fail) failing" : "\(pass) passing"
            }
        }
        return status
    }
}
