import SwiftUI
import AppKit

/// Streams system-wide now-playing metadata + artwork via the bundled
/// mediaremote-adapter (perl bridge → private MediaRemote, allowed because the
/// `com.apple.*` perl binary carries the entitlement). Works for any media app.
@MainActor
final class NowPlayingService: ObservableObject {
    @Published private(set) var info: NowPlaying?
    @Published private(set) var artwork: NSImage?

    private var proc: Process?
    private var lastArtworkHash: Int?

    private let plPath: String?
    private let fwPath: String?

    init() {
        let dir = Bundle.main.resourceURL?.appendingPathComponent("mediaremote")
        plPath = dir?.appendingPathComponent("mediaremote-adapter.pl").path
        fwPath = dir?.appendingPathComponent("MediaRemoteAdapter.framework").path
        start()
    }

    var isAvailable: Bool {
        guard let plPath, let fwPath else { return false }
        let fm = FileManager.default
        return fm.fileExists(atPath: plPath) && fm.fileExists(atPath: fwPath)
    }

    func start() {
        guard proc == nil, let plPath, let fwPath, isAvailable else { return }
        // Run the adapter under a tiny watchdog shell: it kills the adapter as soon
        // as this app's PID is gone — so a quit, crash or SIGKILL never leaves an
        // orphaned perl process streaming in the background.
        let watchdog = """
        /usr/bin/perl "$0" "$1" stream --no-diff --debounce=250 & c=$!
        trap 'kill $c 2>/dev/null' EXIT TERM INT
        while kill -0 \(getpid()) 2>/dev/null && kill -0 $c 2>/dev/null; do sleep 2; done
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", watchdog, plPath, fwPath]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()

        let parser = NowPlayingParser()
        pipe.fileHandleForReading.readabilityHandler = { fh in
            let data = fh.availableData
            guard !data.isEmpty else { return }
            for raw in parser.feed(data) {
                Task { @MainActor in self.apply(raw) }
            }
        }
        do { try p.run() } catch { return }
        proc = p
    }

    /// Stop the adapter (its watchdog shell takes the perl child with it).
    func stop() {
        proc?.terminate()
        proc = nil
    }

    private func apply(_ raw: NowPlayingRaw) {
        guard let title = raw.title, !title.isEmpty else {
            info = nil; artwork = nil; lastArtworkHash = nil; return
        }
        info = NowPlaying(
            title: title,
            artist: raw.artist ?? "",
            album: raw.album ?? "",
            bundleID: raw.bundleID ?? "",
            isPlaying: raw.playing ?? false,
            duration: raw.duration ?? 0,
            elapsed: raw.elapsed ?? 0,
            timestamp: raw.timestamp.flatMap { Self.iso.date(from: $0) }
        )
        if let art = raw.artwork {
            let hash = art.count
            if hash != lastArtworkHash {
                lastArtworkHash = hash
                artwork = NSImage(data: art)
            }
        } else if raw.artworkWasPresent {
            artwork = nil; lastArtworkHash = nil
        }
    }

    /// Send a transport command (2 = toggle, 4 = next, 5 = previous).
    func send(_ command: Int) {
        guard let plPath, let fwPath else { return }
        Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            p.arguments = [plPath, fwPath, "send", String(command)]
            p.standardOutput = Pipe(); p.standardError = Pipe()
            try? p.run(); p.waitUntilExit()
        }
    }

    func toggle()   { send(2) }
    func next()     { send(4) }
    func previous() { send(5) }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); return f
    }()
}

/// Sendable snapshot extracted off the main actor.
struct NowPlayingRaw: Sendable {
    var title: String?
    var artist: String?
    var album: String?
    var bundleID: String?
    var playing: Bool?
    var duration: Double?
    var elapsed: Double?
    var timestamp: String?
    var artwork: Data?
    var artworkWasPresent: Bool = false
}

/// Buffers newline-delimited JSON from the adapter stream and extracts snapshots.
final class NowPlayingParser: @unchecked Sendable {
    private var buffer = Data()

    func feed(_ data: Data) -> [NowPlayingRaw] {
        buffer.append(data)
        var out: [NowPlayingRaw] = []
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            if let raw = parse(line) { out.append(raw) }
        }
        return out
    }

    private func parse(_ data: Data) -> NowPlayingRaw? {
        guard !data.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        // stream wraps payload; `get` is flat.
        let payload = (obj["payload"] as? [String: Any]) ?? obj
        if obj["type"] as? String == "data", obj["payload"] is NSNull {
            return NowPlayingRaw()   // nothing playing
        }
        var raw = NowPlayingRaw()
        raw.title = payload["title"] as? String
        raw.artist = payload["artist"] as? String
        raw.album = payload["album"] as? String
        raw.bundleID = payload["bundleIdentifier"] as? String
        raw.playing = payload["playing"] as? Bool
        raw.duration = payload["duration"] as? Double
        raw.elapsed = payload["elapsedTime"] as? Double
        raw.timestamp = payload["timestamp"] as? String
        if let b64 = payload["artworkData"] as? String {
            raw.artworkWasPresent = true
            raw.artwork = Data(base64Encoded: b64)
        }
        return raw
    }
}
