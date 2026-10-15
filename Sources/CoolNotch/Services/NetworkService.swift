import Foundation
import Combine
import CoreWLAN
import Darwin

/// One ping result. `ms == nil` means the probe timed out / was lost.
struct PingSample: Equatable { let seq: Int; let ms: Double? }

/// Snapshot of the primary (default-route) network link.
struct NetLink: Equatable {
    var interface: String        // "en0"
    var kind: String             // "Wi-Fi" | "Ethernet" | "Other"
    var ssid: String?            // nil without Location permission
    var localIP: String?
    var gateway: String?
    var dns: [String]
    var rssi: Int?               // dBm, Wi-Fi only
    var noise: Int?              // dBm
    var txRate: Double?          // Mbps
}

/// Per-second rates on the primary interface (bytes/s, packets/s) plus
/// cumulative in+out error count.
struct Throughput: Equatable { var rxBps: Double; var txBps: Double; var rxPps: Double; var txPps: Double; var errors: Int }

/// Result of one `networkQuality` run.
struct SpeedResult: Equatable { var downMbps: Double; var upMbps: Double; var rpm: Int?; var baseRTT: Double?; var date: Date }

/// Live network diagnostics: continuous latency (one long-running `ping`),
/// per-second throughput (64-bit `NET_RT_IFLIST2` counters), link details
/// (`route` / getifaddrs / CoreWLAN), public IP, and on-demand
/// `networkQuality` speed tests.
@MainActor
final class NetworkService: ObservableObject {
    static let targets = ["1.1.1.1", "8.8.8.8", "gateway"]   // "gateway" = current default gateway

    @Published private(set) var target: String = "1.1.1.1"
    @Published private(set) var samples: [PingSample] = []   // rolling window, last 60
    @Published private(set) var link: NetLink?
    @Published private(set) var publicIP: String?
    @Published private(set) var throughput: Throughput?
    @Published private(set) var speed: SpeedResult?
    @Published private(set) var speedTesting = false
    @Published private(set) var speedError: String?
    @Published private(set) var isMonitoring = false

    private static let window = 60

    private var pingProcess: Process?
    private var pingGen = 0              // bumped on every start/stop; stale output is dropped
    private var seqBase = 0              // keeps `seq` monotonic across ping restarts / wraps
    private var lastRawSeq = -1
    private var throughputTimer: AnyCancellable?
    private var linkTimer: AnyCancellable?
    private var lastCounters: (iface: String, c: IfCounters, t: TimeInterval)?
    private var linkRefreshing = false
    private var speedBox: NetProcBox?

    // MARK: - Derived ping stats

    var sent: Int { samples.count }
    var received: Int { samples.reduce(0) { $0 + ($1.ms == nil ? 0 : 1) } }
    var lossPct: Double { sent == 0 ? 0 : Double(sent - received) / Double(sent) * 100 }
    /// RTT of the most recent probe (nil if it was lost).
    var lastMs: Double? { samples.last?.ms }
    var minMs: Double? { rtts.min() }
    var avgMs: Double? { let r = rtts; return r.isEmpty ? nil : r.reduce(0, +) / Double(r.count) }
    var maxMs: Double? { rtts.max() }
    /// Mean absolute difference between consecutive successful RTTs.
    var jitterMs: Double? {
        let r = rtts
        guard r.count >= 2 else { return nil }
        var sum = 0.0
        for i in 1..<r.count { sum += abs(r[i] - r[i - 1]) }
        return sum / Double(r.count - 1)
    }
    private var rtts: [Double] { samples.compactMap(\.ms) }

    // MARK: - Monitoring

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        lastCounters = nil
        refreshLink()
        startPing()
        throughputTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.sampleThroughput() }
        linkTimer = Timer.publish(every: 10, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refreshLink() }
        if publicIP == nil { fetchPublicIP() }
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        stopPing()
        throughputTimer = nil
        linkTimer = nil
        lastCounters = nil
    }

    func setTarget(_ host: String) {
        guard host != target else { return }
        target = host
        samples = []
        seqBase = 0
        guard isMonitoring else { return }
        if host == "gateway" && link?.gateway == nil {
            stopPing()
            refreshLink()        // applyLink starts the ping once the gateway is known
        } else {
            startPing()
        }
    }

    // MARK: - Ping (single long-running process)

    private func startPing() {
        stopPing()
        guard isMonitoring else { return }
        let host: String
        if target == "gateway" {
            guard let gw = link?.gateway else { return }
            host = gw
        } else {
            host = target
        }

        let gen = pingGen
        seqBase = (samples.last?.seq ?? -1) + 1
        lastRawSeq = -1

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/sbin/ping")
        p.arguments = ["-n", "-i", "1", host]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice

        let buffer = NetLineBuffer()
        out.fileHandleForReading.readabilityHandler = { [weak self] fh in
            let data = fh.availableData
            if data.isEmpty { fh.readabilityHandler = nil; return }   // EOF
            let parsed = buffer.feed(data).compactMap(NetworkService.parsePing)
            guard !parsed.isEmpty else { return }
            Task { @MainActor [weak self] in self?.ingest(parsed, gen: gen) }
        }
        p.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in self?.pingExited(gen: gen) }
        }
        do {
            try p.run()
            pingProcess = p
        } catch {
            out.fileHandleForReading.readabilityHandler = nil
        }
    }

    private func stopPing() {
        pingGen &+= 1
        guard let p = pingProcess else { return }
        pingProcess = nil
        (p.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        if p.isRunning { p.terminate() }
    }

    /// ping exited on its own (e.g. network vanished): retry in 3 s.
    private func pingExited(gen: Int) {
        guard gen == pingGen, isMonitoring else { return }
        pingProcess = nil
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, gen == self.pingGen, self.isMonitoring, self.pingProcess == nil else { return }
            self.startPing()
        }
    }

    private func ingest(_ batch: [PingSample], gen: Int) {
        guard gen == pingGen else { return }   // late output from a replaced process
        var s = samples
        for raw in batch {
            if lastRawSeq >= 0 && raw.seq < lastRawSeq - 30_000 { seqBase += 65_536 }   // icmp_seq wrapped
            lastRawSeq = max(lastRawSeq, raw.seq)
            let seq = seqBase + raw.seq
            if let i = s.lastIndex(where: { $0.seq == seq }) {
                // Late reply after a "Request timeout" line; ignore DUPs.
                if s[i].ms == nil, raw.ms != nil { s[i] = PingSample(seq: seq, ms: raw.ms) }
            } else {
                s.append(PingSample(seq: seq, ms: raw.ms))
            }
        }
        if s.count > Self.window { s.removeFirst(s.count - Self.window) }
        samples = s
    }

    /// Parses one ping output line into a raw (process-relative) sample.
    private nonisolated static func parsePing(_ line: String) -> PingSample? {
        if let r = line.range(of: "Request timeout for icmp_seq ") {
            guard let seq = Int(line[r.upperBound...].prefix(while: \.isNumber)) else { return nil }
            return PingSample(seq: seq, ms: nil)
        }
        guard !line.contains("DUP!"),
              let s = line.range(of: "icmp_seq="),
              let t = line.range(of: "time="),
              let seq = Int(line[s.upperBound...].prefix(while: \.isNumber)),
              let ms = Double(line[t.upperBound...].prefix(while: { $0.isNumber || $0 == "." }))
        else { return nil }
        return PingSample(seq: seq, ms: ms)
    }

    // MARK: - Throughput

    private func sampleThroughput() {
        guard let iface = link?.interface, let now = Self.counters(for: iface) else { return }
        let t = ProcessInfo.processInfo.systemUptime
        defer { lastCounters = (iface, now, t) }
        guard let prev = lastCounters, prev.iface == iface else { return }
        let dt = t - prev.t
        guard dt > 0.2 else { return }
        let p = prev.c
        // Counter reset (interface bounced): just re-baseline.
        guard now.ibytes >= p.ibytes, now.obytes >= p.obytes,
              now.ipackets >= p.ipackets, now.opackets >= p.opackets else { return }
        let errs = now.ierrors &+ now.oerrors
        throughput = Throughput(rxBps: Double(now.ibytes - p.ibytes) / dt,
                                txBps: Double(now.obytes - p.obytes) / dt,
                                rxPps: Double(now.ipackets - p.ipackets) / dt,
                                txPps: Double(now.opackets - p.opackets) / dt,
                                errors: Int(clamping: errs))
    }

    /// 64-bit interface counters via sysctl NET_RT_IFLIST2 (if_msghdr2/if_data64).
    private nonisolated static func counters(for iface: String) -> IfCounters? {
        let index = if_nametoindex(iface)
        guard index != 0 else { return nil }
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, Int32(index)]
        var len = 0
        guard sysctl(&mib, u_int(mib.count), nil, &len, nil, 0) == 0, len > 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: len)
        guard sysctl(&mib, u_int(mib.count), &buf, &len, nil, 0) == 0 else { return nil }
        return buf.withUnsafeBytes { raw -> IfCounters? in
            var off = 0
            while off + MemoryLayout<if_msghdr>.size <= len {
                let hdr = raw.loadUnaligned(fromByteOffset: off, as: if_msghdr.self)
                let msglen = Int(hdr.ifm_msglen)
                guard msglen > 0 else { break }
                if Int32(hdr.ifm_type) == RTM_IFINFO2, off + MemoryLayout<if_msghdr2>.size <= len {
                    let m = raw.loadUnaligned(fromByteOffset: off, as: if_msghdr2.self)
                    if UInt32(m.ifm_index) == index {
                        let d = m.ifm_data
                        return IfCounters(ibytes: d.ifi_ibytes, obytes: d.ifi_obytes,
                                          ipackets: d.ifi_ipackets, opackets: d.ifi_opackets,
                                          ierrors: d.ifi_ierrors, oerrors: d.ifi_oerrors)
                    }
                }
                off += msglen
            }
            return nil
        }
    }

    private struct IfCounters: Sendable {
        var ibytes, obytes, ipackets, opackets, ierrors, oerrors: UInt64
    }

    // MARK: - Link

    private func refreshLink() {
        guard !linkRefreshing else { return }
        linkRefreshing = true
        Task.detached(priority: .utility) {
            let l = Self.readLink()
            await MainActor.run { self.applyLink(l) }
        }
    }

    private func applyLink(_ l: NetLink?) {
        linkRefreshing = false
        let old = link
        if l != old { link = l }
        if l?.interface != old?.interface { lastCounters = nil }
        // Network switched: the public IP likely changed too.
        if isMonitoring, old != nil, l?.gateway != old?.gateway { fetchPublicIP() }
        if isMonitoring, target == "gateway", let gw = l?.gateway,
           pingProcess == nil || gw != old?.gateway {
            startPing()
        }
    }

    private nonisolated static func readLink() -> NetLink? {
        guard let route = run("/sbin/route", ["-n", "get", "default"]) else { return nil }
        var gateway: String?, iface: String?
        for line in route.split(separator: "\n") {
            let kv = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard kv.count == 2 else { continue }
            if kv[0] == "gateway" { gateway = kv[1] }
            if kv[0] == "interface" { iface = kv[1] }
        }
        guard let iface, !iface.isEmpty else { return nil }
        if let g = gateway, g.contains("#") || g.isEmpty { gateway = nil }   // "link#N" on p2p links

        var link = NetLink(interface: iface, kind: "Other", ssid: nil, localIP: localIPv4(iface),
                           gateway: gateway, dns: dnsServers(), rssi: nil, noise: nil, txRate: nil)
        let client = CWWiFiClient.shared()
        if (client.interfaceNames() ?? []).contains(iface) {
            link.kind = "Wi-Fi"
            if let wi = client.interface(withName: iface) {
                let rssi = wi.rssiValue(), noise = wi.noiseMeasurement(), tx = wi.transmitRate()
                link.rssi = rssi != 0 ? rssi : nil
                link.noise = noise != 0 ? noise : nil
                link.txRate = tx > 0 ? tx : nil
                link.ssid = wi.ssid()
            }
        } else if iface.hasPrefix("en") {
            link.kind = "Ethernet"
        }
        return link
    }

    private nonisolated static func localIPv4(_ iface: String) -> String? {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return nil }
        defer { freeifaddrs(ifap) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET),
                  String(cString: ifa.ifa_name) == iface else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count),
                           nil, 0, NI_NUMERICHOST) == 0 {
                return String(decoding: host.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) },
                              as: UTF8.self)
            }
        }
        return nil
    }

    private nonisolated static func dnsServers() -> [String] {
        func unique(_ xs: [String]) -> [String] {
            var seen = Set<String>()
            return xs.filter { seen.insert($0).inserted }
        }
        let conf = (try? String(contentsOfFile: "/etc/resolv.conf", encoding: .utf8)) ?? ""
        let fromConf = conf.split(separator: "\n").compactMap { line -> String? in
            let cols = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            return cols.count >= 2 && cols[0] == "nameserver" ? String(cols[1]) : nil
        }
        if !fromConf.isEmpty { return unique(fromConf) }
        // e.g. "  nameserver[0] : 192.168.1.1"
        let scutil = run("/usr/sbin/scutil", ["--dns"]) ?? ""
        return unique(scutil.split(separator: "\n").compactMap { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("nameserver["), let c = t.firstIndex(of: ":") else { return nil }
            let v = t[t.index(after: c)...].trimmingCharacters(in: .whitespaces)
            return v.isEmpty ? nil : v
        })
    }

    // MARK: - Public IP

    private func fetchPublicIP() {
        Task { [weak self] in
            guard let url = URL(string: "https://1.1.1.1/cdn-cgi/trace") else { return }
            let req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
            guard let (data, _) = try? await URLSession.shared.data(for: req) else { return }
            let ip = String(decoding: data, as: UTF8.self)
                .split(separator: "\n")
                .first { $0.hasPrefix("ip=") }
                .map { String($0.dropFirst(3)) }
            if let ip { self?.publicIP = ip }
        }
    }

    // MARK: - Speed test

    func runSpeedTest() {
        guard !speedTesting else { return }
        speedError = nil
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/networkQuality")
        p.arguments = ["-c"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch {
            speedError = "networkQuality unavailable"
            return
        }
        let box = NetProcBox(p, out.fileHandleForReading)
        speedBox = box
        speedTesting = true

        Task.detached(priority: .utility) {
            let watchdog = DispatchWorkItem { if box.process.isRunning { box.process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 90, execute: watchdog)
            let data = box.output.readDataToEndOfFile()
            box.process.waitUntilExit()
            watchdog.cancel()
            let outcome = Self.parseSpeed(data, status: box.process.terminationStatus,
                                          signaled: box.process.terminationReason == .uncaughtSignal)
            await MainActor.run { self.finishSpeed(box, outcome) }
        }
    }

    func cancelSpeedTest() {
        guard let box = speedBox else { return }
        speedBox = nil
        if box.process.isRunning { box.process.terminate() }
        speedTesting = false
    }

    private func finishSpeed(_ box: NetProcBox, _ outcome: SpeedOutcome) {
        guard speedBox === box else { return }   // cancelled / superseded
        speedBox = nil
        speedTesting = false
        switch outcome {
        case .ok(let r): speed = r
        case .failed(let msg): speedError = msg
        }
    }

    private enum SpeedOutcome: Sendable { case ok(SpeedResult), failed(String) }

    private nonisolated static func parseSpeed(_ data: Data, status: Int32, signaled: Bool) -> SpeedOutcome {
        if signaled { return .failed("Speed test timed out") }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failed(status == 0 ? "Unreadable speed test result" : "Speed test failed — offline?")
        }
        func num(_ k: String) -> Double? { (obj[k] as? NSNumber)?.doubleValue }
        guard let dl = num("dl_throughput"), let ul = num("ul_throughput") else {
            return .failed("Speed test failed — offline?")
        }
        var rpm = num("responsiveness")
        if rpm == nil {
            let parts = [num("dl_responsiveness"), num("ul_responsiveness")].compactMap { $0 }
            if !parts.isEmpty { rpm = parts.reduce(0, +) / Double(parts.count) }
        }
        return .ok(SpeedResult(downMbps: dl / 1_000_000, upMbps: ul / 1_000_000,
                               rpm: rpm.map { Int($0.rounded()) }, baseRTT: num("base_rtt"),
                               date: Date()))
    }

    // MARK: - Off-main helpers

    /// Runs a CLI with a hard timeout (SIGTERM, then SIGKILL 1 s later).
    private nonisolated static func run(_ launch: String, _ args: [String], timeout: TimeInterval = 5) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launch)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let box = NetProcBox(p, pipe.fileHandleForReading)
        let pid = p.processIdentifier
        let term = DispatchWorkItem { if box.process.isRunning { box.process.terminate() } }
        let kill9 = DispatchWorkItem { if box.process.isRunning { kill(pid, SIGKILL) } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: term)
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout + 1, execute: kill9)
        let data = box.output.readDataToEndOfFile()
        p.waitUntilExit()
        term.cancel(); kill9.cancel()
        guard p.terminationReason == .exit else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - Sendable wrappers

/// Lets a Process + its stdout cross into detached tasks / watchdog blocks.
/// Process is thread-safe for isRunning/terminate/wait.
private final class NetProcBox: @unchecked Sendable {
    let process: Process
    let output: FileHandle
    init(_ process: Process, _ output: FileHandle) { self.process = process; self.output = output }
}

/// Accumulates ping stdout chunks and yields complete lines.
private final class NetLineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = Data()

    func feed(_ data: Data) -> [String] {
        lock.lock(); defer { lock.unlock() }
        pending.append(data)
        var lines: [String] = []
        while let nl = pending.firstIndex(of: 0x0A) {
            lines.append(String(decoding: pending[pending.startIndex..<nl], as: UTF8.self))
            pending.removeSubrange(pending.startIndex...nl)
        }
        if pending.count > 65_536 { pending.removeAll() }
        return lines
    }
}
