import SwiftUI
import Combine

/// Surfaces Claude Code's own notifications in the notch. Watches
/// `~/.claude/coolnotch/notifications.jsonl` — each appended line
/// `{"title":"…","message":"…"}` becomes a pill. Wire it from a Claude Code
/// Notification/Stop hook (see README). Only new lines fire (pre-existing history
/// is ignored on launch).
@MainActor
final class ClaudeNotifyWatcher: ObservableObject {
    var onNotify: ((NotchNotification) -> Void)?

    private var timer: AnyCancellable?
    private var offset: UInt64 = 0
    private var seeded = false
    private let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/coolnotch/notifications.jsonl")

    init() {
        timer = Timer.publish(every: 1.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.poll() }
    }

    private func poll() {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        if !seeded { offset = size; seeded = true; return }   // ignore pre-existing lines
        if size < offset { offset = 0 }                        // file was truncated/rotated
        guard size > offset else { return }

        try? handle.seek(toOffset: offset)
        let data = handle.readDataToEndOfFile()
        offset = size
        guard let text = String(data: data, encoding: .utf8) else { return }

        for line in text.split(separator: "\n") {
            guard let d = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
            else { continue }
            let title = obj["title"] as? String ?? "Claude"
            let message = (obj["message"] as? String) ?? (obj["body"] as? String)
            let (icon, tint) = style(for: obj["kind"] as? String, custom: obj["icon"] as? String)
            onNotify?(NotchNotification(icon: icon, title: title, subtitle: message, tint: tint))
        }
    }

    /// Map an optional "kind" to an icon + tint, or use a custom SF Symbol.
    private func style(for kind: String?, custom: String?) -> (String, Color) {
        if let custom { return (custom, DS.accent) }
        switch kind {
        case "done", "finished":     return ("checkmark.circle.fill", DS.good)
        case "input", "waiting":     return ("hand.raised.fill", DS.amber)
        case "error", "failed":      return ("exclamationmark.triangle.fill", DS.danger)
        default:                     return ("sparkles", DS.accent)
        }
    }
}
