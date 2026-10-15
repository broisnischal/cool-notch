import SwiftUI
import Combine

/// Polls `docker ps` on a background queue and publishes container state. Handles
/// the daemon being down (very common) as a first-class state rather than an error.
/// Container start/stop between polls fires a notification.
@MainActor
final class DockerService: ObservableObject {
    @Published private(set) var state: DockerState = .notRunning
    var onNotify: ((NotchNotification) -> Void)?

    private var timer: AnyCancellable?
    private var seenNames: Set<String> = []
    private var seeded = false
    private let dockerPath: String?

    init() {
        dockerPath = Self.findDocker()
        refresh()
        timer = Timer.publish(every: 6, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    /// Fetch recent logs for a container (stdout+stderr merged), off the main actor.
    func logs(name: String, tail: Int = 300) async -> String {
        guard let path = dockerPath else { return "docker CLI not found" }
        return await Task.detached(priority: .utility) {
            Self.runLogs(path, name: name, tail: tail)
        }.value
    }

    private nonisolated static func runLogs(_ path: String, name: String, tail: Int) -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = ["logs", "--tail", String(tail), name]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe   // docker often logs to stderr
        do { try proc.run() } catch { return "failed to run docker logs" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        let text = String(data: data, encoding: .utf8) ?? ""
        return text.isEmpty ? "(no output)" : text
    }

    private static func findDocker() -> String? {
        let candidates = ["/opt/homebrew/bin/docker", "/usr/local/bin/docker", "/usr/bin/docker"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func refresh() {
        guard let path = dockerPath else { state = .unavailable; return }
        Task.detached(priority: .utility) {
            let result = Self.runPS(path)
            await MainActor.run { self.apply(result) }
        }
    }

    /// Run a lifecycle action (`stop`, `restart`, `rm -f`) on a container, then refresh.
    func control(_ action: String, container: String) {
        guard let path = dockerPath else { return }
        Task.detached(priority: .userInitiated) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: path)
            proc.arguments = action.split(separator: " ").map(String.init) + [container]
            proc.standardOutput = Pipe(); proc.standardError = Pipe()
            try? proc.run(); proc.waitUntilExit()
            await MainActor.run { self.refresh() }
        }
    }

    private func apply(_ new: DockerState) {
        // Diff running containers for start/stop notifications.
        if case let .running(containers) = new {
            let names = Set(containers.map(\.name))
            if seeded {
                for started in names.subtracting(seenNames) {
                    onNotify?(NotchNotification(icon: "shippingbox.fill",
                                               title: "Container started", subtitle: started,
                                               tint: DS.good))
                }
                for stopped in seenNames.subtracting(names) {
                    onNotify?(NotchNotification(icon: "shippingbox",
                                               title: "Container stopped", subtitle: stopped,
                                               tint: DS.danger))
                }
            }
            seenNames = names
            seeded = true
        } else {
            seenNames = []
        }
        state = new
    }

    /// Runs `docker ps` synchronously (called off the main actor). Returns state.
    private nonisolated static func runPS(_ path: String) -> DockerState {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = ["ps", "--no-trunc", "--format", "{{.Names}}\t{{.Image}}\t{{.Status}}"]
        let out = Pipe(); let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        do {
            try proc.run()
        } catch {
            return .unavailable
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()

        if proc.terminationStatus != 0 {
            let msg = String(data: errData, encoding: .utf8) ?? ""
            // Daemon down is the common non-zero case.
            if msg.contains("Cannot connect") || msg.contains("daemon") {
                return .notRunning
            }
            return .notRunning
        }

        let text = String(data: data, encoding: .utf8) ?? ""
        let containers: [DockerContainer] = text
            .split(separator: "\n")
            .compactMap { line in
                let cols = line.components(separatedBy: "\t")
                guard cols.count >= 3, !cols[0].isEmpty else { return nil }
                return DockerContainer(
                    name: cols[0],
                    image: cols[1],
                    status: cols[2],
                    isUp: cols[2].lowercased().hasPrefix("up")
                )
            }
        return .running(containers)
    }
}
