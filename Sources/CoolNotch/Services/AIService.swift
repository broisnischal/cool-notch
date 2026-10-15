import Foundation

/// Talks to Claude headlessly via `claude -p`. Streams text deltas as they arrive
/// (`--output-format stream-json --include-partial-messages`) so replies render
/// live. With a session UUID it resumes that session; the Ask flow uses a fast
/// model for snappy answers.
@MainActor
final class AIService: ObservableObject {
    @Published private(set) var activeStreams = 0
    private let claudePath: String?

    init() {
        let candidates = [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/bin/claude").path,
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]
        claudePath = candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    var isAvailable: Bool { claudePath != nil }

    /// Streamed reply. Each yielded element is a text delta; concatenate to build
    /// the message. Finishes when the process exits.
    func stream(_ prompt: String, cwd: String? = nil,
                resume: String? = nil, model: String? = nil) -> AsyncStream<String> {
        let path = claudePath
        let dir = cwd ?? FileManager.default.homeDirectoryForCurrentUser.path
        activeStreams += 1
        return AsyncStream<String> { cont in
            guard let path else {
                cont.yield("Claude CLI not found (~/.local/bin/claude).")
                cont.finish()
                Task { @MainActor in self.activeStreams -= 1 }
                return
            }
            Task.detached(priority: .userInitiated) {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: path)
                var args: [String] = []
                // --fork-session branches a copy, so it works even when the session is
                // live in a terminal or running as a background agent.
                if let resume, !resume.isEmpty { args += ["--resume", resume, "--fork-session"] }
                if let model { args += ["--model", model] }
                args += ["-p", prompt,
                         "--output-format", "stream-json",
                         "--include-partial-messages", "--verbose"]
                proc.arguments = args
                proc.currentDirectoryURL = URL(fileURLWithPath: dir)
                // GUI apps launch with a minimal env; give claude a real PATH/HOME
                // so it finds credentials and helpers (otherwise: "Not logged in").
                var env = ProcessInfo.processInfo.environment
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                env["HOME"] = home
                env["PATH"] = (env["PATH"].map { $0 + ":" } ?? "")
                    + "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
                proc.environment = env

                let outPipe = Pipe()
                let errPipe = Pipe()
                proc.standardOutput = outPipe
                proc.standardError = errPipe

                let parser = StreamParser()
                let handle = outPipe.fileHandleForReading
                handle.readabilityHandler = { fh in
                    let data = fh.availableData
                    guard !data.isEmpty else { return }
                    for delta in parser.feed(data) { cont.yield(delta) }
                }
                // Drain stderr concurrently — otherwise a full 64KB stderr buffer
                // blocks claude's writes and the process hangs forever.
                let errBox = DataBox()
                let errHandle = errPipe.fileHandleForReading
                errHandle.readabilityHandler = { fh in
                    let data = fh.availableData
                    if !data.isEmpty { errBox.append(data) }
                }

                do { try proc.run() } catch {
                    cont.yield("Failed to launch Claude.")
                    cont.finish(); await MainActor.run { self.activeStreams -= 1 }; return
                }
                // Backstop timeout so it never spins forever.
                let timeout = DispatchWorkItem { if proc.isRunning { proc.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + 120, execute: timeout)

                proc.waitUntilExit()
                timeout.cancel()
                handle.readabilityHandler = nil
                errHandle.readabilityHandler = nil
                let rest = handle.readDataToEndOfFile()
                if !rest.isEmpty { for delta in parser.feed(rest) { cont.yield(delta) } }
                if parser.emittedNothing {
                    let stderr = errBox.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    let msg = !parser.fallbackText.isEmpty ? parser.fallbackText
                        : (!stderr.isEmpty ? "⚠️ \(stderr)" : "No reply (the session may be too large to fork quickly).")
                    cont.yield(msg)
                }
                cont.finish()
                await MainActor.run { self.activeStreams -= 1 }
            }
        }
    }
}

/// Thread-safe accumulator for draining a pipe off the main actor.
final class DataBox: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()
    func append(_ d: Data) { lock.lock(); data.append(d); lock.unlock() }
    var string: String { lock.lock(); defer { lock.unlock() }; return String(data: data, encoding: .utf8) ?? "" }
}

/// Parses the `stream-json` line protocol incrementally, emitting only assistant
/// text deltas (ignores thinking blocks, tool calls, system events).
final class StreamParser: @unchecked Sendable {
    private var buffer = Data()
    private(set) var emittedNothing = true
    private var assistantText = ""
    private var resultText = ""
    /// Best non-streamed text (final assistant message, else the result field).
    var fallbackText: String { assistantText.isEmpty ? resultText : assistantText }

    func feed(_ data: Data) -> [String] {
        buffer.append(data)
        var out: [String] = []
        while let nl = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            if let text = parseLine(lineData) {
                out.append(text)
                emittedNothing = false
            }
        }
        return out
    }

    private func parseLine(_ data: Data) -> String? {
        guard !data.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let type = obj["type"] as? String
        // Live token deltas (primary path).
        if type == "stream_event",
           let event = obj["event"] as? [String: Any],
           event["type"] as? String == "content_block_delta",
           let delta = event["delta"] as? [String: Any],
           delta["type"] as? String == "text_delta",
           let text = delta["text"] as? String {
            return text
        }
        // Fallbacks so an error/short reply is never shown as "(no response)".
        if type == "assistant", let m = obj["message"] as? [String: Any],
           let content = m["content"] as? [[String: Any]] {
            let text = content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
                .joined()
            if !text.isEmpty { assistantText = text }
        }
        if type == "result", let result = obj["result"] as? String, !result.isEmpty {
            resultText = result
        }
        return nil
    }
}
