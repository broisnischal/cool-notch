import SwiftUI

/// Which feed the expanded panel is showing.
enum NotchTab: String, CaseIterable, Identifiable {
    case home, claude, network, health, dev, docker, clipboard, bookmarks, mirror, notifications
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .home:          return "house"
        case .claude:        return "ellipsis.bubble"
        case .network:       return "wifi"
        case .health:        return "stethoscope"
        case .dev:           return "hammer"
        case .docker:        return "shippingbox"
        case .clipboard:     return "doc.on.clipboard"
        case .bookmarks:     return "bookmark"
        case .mirror:        return "camera"
        case .notifications: return "bell"
        }
    }
    var title: String {
        switch self {
        case .home:          return "Home"
        case .claude:        return "Claude"
        case .network:       return "Network"
        case .health:        return "Health"
        case .dev:           return "Dev"
        case .docker:        return "Docker"
        case .clipboard:     return "Clipboard"
        case .bookmarks:     return "Links"
        case .mirror:        return "Mirror"
        case .notifications: return "Notifications"
        }
    }
    /// Tabs that existed before `knownTabs` was tracked — anything newer gets
    /// enabled automatically for people with a saved tab list.
    static let legacyRaw = ["home", "claude", "docker", "terminal", "clipboard",
                            "dev", "mirror", "bookmarks", "notifications"]
}

/// A saved website bookmark.
struct Bookmark: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var url: String
}

/// A notification recorded in the in-app notification center.
struct RecordedNotification: Identifiable, Equatable {
    let id = UUID()
    let notification: NotchNotification
    let date: Date
}

/// A calendar event (mapped from EKEvent for display).
struct CalEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
}

/// Git status for a working directory.
struct GitStatus: Equatable {
    var branch: String
    var ahead: Int
    var behind: Int
    var dirty: Int          // changed files
    var prTitle: String?
    var prState: String?    // OPEN / MERGED / CLOSED
    var checks: String?     // pass/fail summary
}

/// A listening TCP port.
struct PortInfo: Identifiable, Equatable {
    var id: String { "\(port)-\(pid)" }
    let port: Int
    let process: String
    let pid: Int
}

/// A detail page pushed on top of a tab's root (iOS-style navigation).
enum NotchRoute: Equatable {
    case dockerLogs(name: String)
    case session(id: String, project: String)
    case ask(prompt: String)

    var title: String {
        switch self {
        case .dockerLogs(let name): return name
        case .session(_, let project): return project
        case .ask: return "Ask Claude"
        }
    }
}

/// Now-playing metadata from any media app.
struct NowPlaying: Equatable {
    var title: String
    var artist: String
    var album: String
    var bundleID: String
    var isPlaying: Bool
    var duration: Double      // seconds
    var elapsed: Double       // seconds at `timestamp`
    var timestamp: Date?

    var progress: Double { duration > 0 ? min(1, max(0, elapsed / duration)) : 0 }

    /// Elapsed time projected to `now` (so the scrubber advances smoothly).
    func elapsed(at now: Date) -> Double {
        guard isPlaying, let ts = timestamp else { return elapsed }
        return min(duration, elapsed + now.timeIntervalSince(ts))
    }
    func progress(at now: Date) -> Double {
        duration > 0 ? min(1, max(0, elapsed(at: now) / duration)) : 0
    }
}

/// A captured clipboard entry.
struct ClipItem: Identifiable, Equatable, Codable {
    var id = UUID()
    let text: String
    let date: Date
    var preview: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
    }
}

/// One message from a Claude transcript, cleaned for display.
struct ChatMsg: Identifiable, Equatable {
    let id = UUID()
    let role: String    // "user" | "assistant"
    let text: String
}

/// A recent Claude Code session (one project's most recent transcript).
struct ClaudeSession: Identifiable, Equatable {
    let id: String            // project dir path
    let project: String       // display name
    let modified: Date
    var isActive: Bool         // touched within the last few minutes
    let transcriptPath: String // newest .jsonl
    let sessionUUID: String    // its filename stem, for `claude --resume`
}

/// A Docker container from `docker ps`.
struct DockerContainer: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let image: String
    let status: String
    var isUp: Bool
}

enum DockerState: Equatable {
    case unavailable          // docker CLI not found
    case notRunning           // daemon down
    case running([DockerContainer])
}

/// A transient level HUD (volume/brightness) shown from the notch.
struct HUDInfo: Equatable {
    var icon: String
    var level: Double   // 0…1
}

/// A transient Dynamic-Island-style notification shown from the notch.
struct NotchNotification: Identifiable, Equatable {
    let id = UUID()
    var icon: String
    var title: String
    var subtitle: String?
    var tint: Color = DS.accent
}
