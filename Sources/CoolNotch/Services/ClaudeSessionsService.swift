import SwiftUI
import Combine

/// Lists recent Claude Code sessions by scanning `~/.claude/projects/<slug>/*.jsonl`
/// and taking each project's most recently modified transcript. Sessions touched
/// within the last few minutes are flagged active; newly-active ones fire a
/// notification. Read-only, no permissions.
@MainActor
final class ClaudeSessionsService: ObservableObject {
    @Published private(set) var sessions: [ClaudeSession] = []
    var onNotify: ((NotchNotification) -> Void)?

    private var timer: AnyCancellable?
    private var seenActive: Set<String> = []
    private var hotIDs: Set<String> = []      // sessions written to very recently
    private var lastFinishNote: [String: Date] = [:]  // finish-chime cooldown
    private var seeded = false

    private let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects")
    private let homeSlug: String

    private static let activeWindow: TimeInterval = 300  // 5 min
    // "Hot" = transcript written within the last minute. Long enough that a session
    // quietly running a slow tool doesn't flap; leaving hot ⇒ it likely finished.
    private static let hotWindow: TimeInterval = 60

    init() {
        homeSlug = FileManager.default.homeDirectoryForCurrentUser.path
            .replacingOccurrences(of: "/", with: "-") + "-"
        refresh()
        timer = Timer.publish(every: 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return }

        let now = Date()
        var result: [ClaudeSession] = []

        for dir in dirs {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  let files = try? fm.contentsOfDirectory(
                    at: dir, includingPropertiesForKeys: [.contentModificationDateKey],
                    options: [.skipsHiddenFiles])
            else { continue }

            let newest = files
                .filter { $0.pathExtension == "jsonl" }
                .compactMap { url -> (URL, Date)? in
                    guard let d = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                        .contentModificationDate else { return nil }
                    return (url, d)
                }
                .max { $0.1 < $1.1 }

            guard let (url, modified) = newest else { continue }
            result.append(ClaudeSession(
                id: dir.path,
                project: displayName(dir.lastPathComponent),
                modified: modified,
                isActive: now.timeIntervalSince(modified) < Self.activeWindow,
                transcriptPath: url.path,
                sessionUUID: url.deletingPathExtension().lastPathComponent
            ))
        }

        result.sort { $0.modified > $1.modified }
        let top = Array(result.prefix(14))

        let active = Set(top.filter(\.isActive).map(\.id))
        let hot = Set(top.filter { now.timeIntervalSince($0.modified) < Self.hotWindow }.map(\.id))
        if seeded {
            for id in active.subtracting(seenActive) {
                if let s = top.first(where: { $0.id == id }) {
                    onNotify?(NotchNotification(icon: "ellipsis.bubble.fill",
                                               title: "Claude active", subtitle: s.project))
                }
            }
            // A session that stopped writing (but is still in its active window)
            // most likely finished its turn — chime so the user can come back.
            // Long turns with sparse writes flap hot↔cold, so cool down per session:
            // at most one finish chime per 15 minutes.
            if AppSettings.shared.agentAlerts {
                for id in hotIDs.subtracting(hot) {
                    guard let s = top.first(where: { $0.id == id }),
                          now.timeIntervalSince(lastFinishNote[id] ?? .distantPast) > 900
                    else { continue }
                    lastFinishNote[id] = now
                    onNotify?(NotchNotification(icon: "checkmark.circle.fill",
                                               title: "Claude finished", subtitle: s.project,
                                               tint: DS.good))
                    NotchSound.agentDone()
                }
            }
        }
        seenActive = active
        hotIDs = hot
        seeded = true
        sessions = top
    }

    // MARK: Session detail (parsed off the main actor)
    struct SessionDetail: Equatable {
        var cwd: String?
        var messages: [ChatMsg]
        var outputTokens: Int = 0
    }

    nonisolated static func loadDetail(path: String, maxMessages: Int = 16) -> SessionDetail {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return SessionDetail(cwd: nil, messages: [])
        }
        var cwd: String?
        var msgs: [ChatMsg] = []
        var outTokens = 0
        for line in content.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            if cwd == nil, let c = obj["cwd"] as? String { cwd = c }
            guard let type = obj["type"] as? String,
                  type == "user" || type == "assistant",
                  let m = obj["message"] as? [String: Any] else { continue }
            // Sum output tokens across completed assistant turns.
            if type == "assistant", m["stop_reason"] is String,
               let usage = m["usage"] as? [String: Any] {
                outTokens += usage["output_tokens"] as? Int ?? 0
            }

            var text = ""
            if let s = m["content"] as? String { text = s }
            else if let arr = m["content"] as? [[String: Any]] {
                for b in arr where b["type"] as? String == "text" {
                    text += (b["text"] as? String ?? "")
                }
            }
            text = clean(text)
            guard !text.isEmpty else { continue }
            msgs.append(ChatMsg(role: m["role"] as? String ?? type, text: text))
        }
        return SessionDetail(cwd: cwd, messages: Array(msgs.suffix(maxMessages)), outputTokens: outTokens)
    }

    /// Drop slash-command noise, caveats, and image placeholders.
    private nonisolated static func clean(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty || t.hasPrefix("<") || t.hasPrefix("[Image") || t.hasPrefix("Caveat:") { return "" }
        if t.contains("local-command") || t.contains("command-name") { return "" }
        return t
    }

    /// `-Users-nees-stroke--claude-worktrees-ui-revamp` → `stroke · ui-revamp`
    private func displayName(_ slug: String) -> String {
        var s = slug
        if s.hasPrefix(homeSlug) { s.removeFirst(homeSlug.count) }
        else if s.hasPrefix("-") { s.removeFirst() }
        s = s.replacingOccurrences(of: "--claude-worktrees-", with: " · ")
        return s.isEmpty ? slug : s
    }
}
