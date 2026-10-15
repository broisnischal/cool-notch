import Foundation
import Combine
import CoreWLAN
import IOKit
import SystemConfiguration
import Darwin

enum CheckStatus: Equatable { case pending, running, pass, warn, fail }

struct HealthCheck: Identifiable, Equatable {
    let id: String
    let title: String
    let icon: String          // SF Symbol name
    var status: CheckStatus
    var detail: String        // short, e.g. "92% health · 213 cycles"
}

/// One-shot Mac health sweep: network, CPU, memory, storage, battery, thermals,
/// crashes, security. All checks run concurrently off-main; every external
/// process and blocking call is time-boxed so one hung check can't stall the run.
@MainActor
final class HealthService: ObservableObject {
    @Published private(set) var checks: [HealthCheck]
    @Published private(set) var isRunning = false
    @Published private(set) var lastRun: Date?

    var passed: Int { checks.filter { $0.status == .pass }.count }
    var warned: Int { checks.filter { $0.status == .warn }.count }
    var failed: Int { checks.filter { $0.status == .fail }.count }

    private static let catalog: [(id: String, title: String, icon: String)] = [
        ("internet", "Internet", "globe"),
        ("dns", "DNS", "network"),
        ("wifi", "Wi-Fi", "wifi"),
        ("cpu", "CPU load", "cpu"),
        ("memory", "Memory", "memorychip"),
        ("swap", "Swap", "arrow.triangle.swap"),
        ("disk", "Disk space", "internaldrive"),
        ("smart", "Disk health", "stethoscope"),
        ("battery", "Battery", "battery.100"),
        ("thermal", "Thermals", "thermometer.medium"),
        ("uptime", "Uptime", "clock.arrow.circlepath"),
        ("crashes", "Crashes", "exclamationmark.triangle"),
        ("security", "Security", "lock.shield"),
    ]

    init() {
        checks = Self.catalog.map {
            HealthCheck(id: $0.id, title: $0.title, icon: $0.icon, status: .pending, detail: "")
        }
    }

    func runAll() {
        guard !isRunning else { return }
        isRunning = true
        checks = checks.map { var c = $0; c.status = .running; return c }
        let ids = checks.map(\.id)
        Task {
            await withTaskGroup(of: (String, Outcome).self) { group in
                for id in ids {
                    group.addTask { (id, await Self.evaluate(id)) }
                }
                for await (id, outcome) in group {
                    guard let i = checks.firstIndex(where: { $0.id == id }) else { continue }
                    var c = checks[i]
                    c.status = outcome.status
                    c.detail = outcome.detail
                    checks[i] = c
                }
            }
            isRunning = false
            lastRun = Date()
        }
    }

    // MARK: - Dispatch

    private struct Outcome: Sendable {
        var status: CheckStatus
        var detail: String
        init(_ status: CheckStatus, _ detail: String) { self.status = status; self.detail = detail }
    }

    private nonisolated static func evaluate(_ id: String) async -> Outcome {
        switch id {
        case "internet": return await internet()
        case "dns":      return await blocking { dns() }
        case "wifi":     return await blocking { wifi() }
        case "cpu":      return await blocking { cpu() }
        case "memory":   return await blocking { memory() }
        case "swap":     return await blocking { swap() }
        case "disk":     return await blocking { disk() }
        case "smart":    return await blocking { smart() }
        case "battery":  return await blocking { battery() }
        case "thermal":  return thermal()
        case "uptime":   return await blocking { uptime() }
        case "crashes":  return await blocking { crashes() }
        case "security": return await blocking(timeout: 12) { security() }
        default:         return Outcome(.warn, "Unknown check")
        }
    }

    /// Runs blocking work on a GCD thread (not the cooperative pool) with a hard cap.
    private nonisolated static func blocking(timeout: TimeInterval = 8,
                                             _ work: @escaping @Sendable () -> Outcome) async -> Outcome {
        await withCheckedContinuation { cont in
            let once = HealthOnce()
            DispatchQueue.global(qos: .utility).async {
                let r = work()
                if once.claim() { cont.resume(returning: r) }
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                if once.claim() { cont.resume(returning: Outcome(.fail, "Timed out")) }
            }
        }
    }

    // MARK: - Network

    private nonisolated static func internet() async -> Outcome {
        guard let url = URL(string: "http://captive.apple.com/hotspot-detect.html") else {
            return Outcome(.fail, "Bad URL")
        }
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 5
        cfg.timeoutIntervalForResource = 5
        cfg.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let session = URLSession(configuration: cfg)
        defer { session.finishTasksAndInvalidate() }
        let t0 = nowMs()
        do {
            let (data, _) = try await session.data(from: url)
            return captive(String(decoding: data, as: UTF8.self), ms: nowMs() - t0)
        } catch let e as URLError {
            switch e.code {
            case .appTransportSecurityRequiresSecureConnection:
                // ATS blocks plain HTTP in the app bundle; curl isn't subject to it.
                return await blocking { internetViaCurl() }
            case .timedOut: return Outcome(.fail, "Timed out (5 s)")
            case .notConnectedToInternet, .networkConnectionLost: return Outcome(.fail, "Offline")
            case .cannotFindHost, .dnsLookupFailed: return Outcome(.fail, "Can't resolve host")
            default: return Outcome(.fail, "No connection")
            }
        } catch {
            return Outcome(.fail, "No connection")
        }
    }

    private nonisolated static func internetViaCurl() -> Outcome {
        guard let out = run("/usr/bin/curl", ["-s", "-m", "5", "-w", "\n%{time_total}",
                                              "http://captive.apple.com/hotspot-detect.html"], timeout: 6),
              let last = out.split(separator: "\n").last,
              let secs = Double(last), out.count > last.count
        else { return Outcome(.fail, "No connection") }
        return captive(String(out.dropLast(last.count)), ms: secs * 1000)
    }

    private nonisolated static func captive(_ body: String, ms: Double) -> Outcome {
        body.contains("Success") ? Outcome(.pass, "Online · \(Int(ms.rounded())) ms")
                                 : Outcome(.warn, "Captive portal")
    }

    private nonisolated static func dns() -> Outcome {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var res: UnsafeMutablePointer<addrinfo>?
        let t0 = nowMs()
        let rc = getaddrinfo("www.apple.com", nil, &hints, &res)
        let ms = Int((nowMs() - t0).rounded())
        if let res { freeaddrinfo(res) }
        guard rc == 0 else { return Outcome(.fail, "Lookup failed") }
        if ms < 150 { return Outcome(.pass, "Resolved in \(ms) ms") }
        if ms < 1000 { return Outcome(.warn, "Slow · \(ms) ms") }
        return Outcome(.fail, "Very slow · \(ms) ms")
    }

    private nonisolated static func wifi() -> Outcome {
        guard let primary = primaryInterface() else { return Outcome(.warn, "Not connected") }
        let client = CWWiFiClient.shared()
        let wifiNames = client.interfaceNames() ?? []

        func grade(_ wi: CWInterface) -> Outcome {
            let rssi = wi.rssiValue()
            guard rssi != 0 else { return Outcome(.warn, "Not associated") }
            let tx = Int(wi.transmitRate().rounded())
            let detail = tx > 0 ? "\(rssi) dBm · \(tx) Mbps" : "\(rssi) dBm"
            if rssi > -67 { return Outcome(.pass, detail) }
            if rssi > -75 { return Outcome(.warn, detail) }
            return Outcome(.fail, detail)
        }

        if wifiNames.contains(primary), let wi = client.interface(withName: primary) { return grade(wi) }
        if primary.hasPrefix("en") { return Outcome(.pass, "Ethernet") }
        // Primary is a tunnel/bridge (VPN etc.): grade Wi-Fi underneath if associated.
        if let wi = client.interface(), wi.rssiValue() != 0 { return grade(wi) }
        return Outcome(.pass, "Via \(primary)")
    }

    private nonisolated static func primaryInterface() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "CoolNotch.health" as CFString, nil, nil),
              let dict = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        else { return nil }
        return dict["PrimaryInterface"] as? String
    }

    // MARK: - CPU / memory

    private nonisolated static func cpu() -> Outcome {
        var loads = [Double](repeating: 0, count: 3)
        guard getloadavg(&loads, 3) >= 1 else { return Outcome(.warn, "Load unavailable") }
        let cores = max(ProcessInfo.processInfo.activeProcessorCount, 1)
        let ratio = loads[0] / Double(cores)
        var detail = String(format: "Load %.1f", loads[0])
        if let ps = run("/bin/ps", ["-Aceo", "pcpu,comm", "-r"]) {
            let lines = ps.split(separator: "\n")
            if lines.count > 1 {
                let row = lines[1].trimmingCharacters(in: .whitespaces)
                if let sp = row.firstIndex(of: " "), let pct = Double(row[..<sp]) {
                    let name = clip(row[sp...].trimmingCharacters(in: .whitespaces), 14)
                    detail += " · \(name) \(Int(pct.rounded()))%"
                }
            }
        }
        if ratio < 0.7 { return Outcome(.pass, detail) }
        if ratio < 1.0 { return Outcome(.warn, detail) }
        return Outcome(.fail, detail)
    }

    private nonisolated static func memory() -> Outcome {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let haveLevel = sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0

        let gib = 1024.0 * 1024 * 1024
        let total = Double(ProcessInfo.processInfo.physicalMemory) / gib
        var detail = String(format: "%.0f GB total", total)
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        if kr == KERN_SUCCESS {
            let pages = UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
            let used = Double(pages * UInt64(getpagesize())) / gib
            detail = String(format: "%.1f / %.0f GB used", used, total)
        }
        guard haveLevel else { return Outcome(.warn, detail) }
        switch level {
        case 1:  return Outcome(.pass, detail)
        case 2:  return Outcome(.warn, detail)
        case 4:  return Outcome(.fail, detail)
        default: return Outcome(.warn, detail)
        }
    }

    private nonisolated static func swap() -> Outcome {
        var xsw = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &xsw, &size, nil, 0) == 0 else {
            return Outcome(.warn, "Unavailable")
        }
        let gb = Double(xsw.xsu_used) / (1024 * 1024 * 1024)
        let detail: String
        if xsw.xsu_used == 0 { detail = "No swap in use" }
        else if gb < 1 { detail = "\(Int((gb * 1024).rounded())) MB swap used" }
        else { detail = String(format: "%.1f GB swap used", gb) }
        if gb < 1 { return Outcome(.pass, detail) }
        if gb < 4 { return Outcome(.warn, detail) }
        return Outcome(.fail, detail)
    }

    // MARK: - Storage

    private nonisolated static func disk() -> Outcome {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        guard let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let free = v.volumeAvailableCapacityForImportantUsage, let total = v.volumeTotalCapacity,
              total > 0
        else { return Outcome(.warn, "Unavailable") }
        let pct = Double(free) / Double(total) * 100
        let detail = "\(Int((Double(free) / 1e9).rounded())) GB free of \(Int((Double(total) / 1e9).rounded()))"
        if pct > 15 { return Outcome(.pass, detail) }
        if pct > 5 { return Outcome(.warn, detail) }
        return Outcome(.fail, detail)
    }

    private nonisolated static func smart() -> Outcome {
        guard let out = run("/usr/sbin/diskutil", ["info", "disk0"]) else {
            return Outcome(.warn, "Unavailable")
        }
        guard let line = out.split(separator: "\n").first(where: { $0.contains("SMART Status:") }),
              let colon = line.firstIndex(of: ":")
        else { return Outcome(.pass, "Not reported") }
        let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        if value == "Verified" { return Outcome(.pass, "SMART verified") }
        if value.hasPrefix("Not Supported") { return Outcome(.pass, "Not reported") }
        return Outcome(.fail, clip("SMART: \(value)", 32))
    }

    // MARK: - Power / thermals

    private nonisolated static func battery() -> Outcome {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return Outcome(.pass, "AC power") }
        defer { IOObjectRelease(service) }
        func int(_ key: String) -> Int? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Int
        }
        if let installed = IORegistryEntryCreateCFProperty(service, "BatteryInstalled" as CFString,
                                                           kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool,
           !installed { return Outcome(.pass, "AC power") }
        guard let design = int("DesignCapacity"), design > 0 else { return Outcome(.pass, "AC power") }

        var health: Double?
        if let raw = int("AppleRawMaxCapacity"), raw > 0 {
            health = Double(raw) / Double(design) * 100
        } else if let max = int("MaxCapacity"), max > 0 {
            // On Apple silicon MaxCapacity is already a percentage.
            health = max <= 100 && design > 100 ? Double(max) : Double(max) / Double(design) * 100
        }
        guard let h = health else { return Outcome(.warn, "Capacity unknown") }
        let pct = Int(min(h, 100).rounded())
        let detail = int("CycleCount").map { "\(pct)% health · \($0) cycles" } ?? "\(pct)% health"
        if h >= 80 { return Outcome(.pass, detail) }
        if h >= 70 { return Outcome(.warn, detail) }
        return Outcome(.fail, detail)
    }

    private nonisolated static func thermal() -> Outcome {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:  return Outcome(.pass, "Nominal")
        case .fair:     return Outcome(.pass, "Fair")
        case .serious:  return Outcome(.warn, "Serious · throttling")
        case .critical: return Outcome(.fail, "Critical · throttling")
        @unknown default: return Outcome(.pass, "Unknown")
        }
    }

    // MARK: - System

    private nonisolated static func uptime() -> Outcome {
        var tv = timeval()
        var size = MemoryLayout<timeval>.size
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &tv, &size, nil, 0) == 0, tv.tv_sec > 0 else {
            return Outcome(.warn, "Unavailable")
        }
        let secs = Date().timeIntervalSince1970 - (Double(tv.tv_sec) + Double(tv.tv_usec) / 1e6)
        let days = Int(secs / 86_400), hours = Int(secs / 3600) % 24, mins = Int(secs / 60) % 60
        if days >= 14 { return Outcome(.warn, "Up \(days)d · Restart recommended") }
        let up = days > 0 ? "Up \(days)d \(hours)h" : "Up \(hours)h \(mins)m"
        return Outcome(.pass, up)
    }

    private nonisolated static func crashes() -> Outcome {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
        else { return Outcome(.pass, "No crash reports") }

        let cutoff = Date().addingTimeInterval(-86_400)
        var counts: [String: Int] = [:]
        var total = 0
        for f in files where f.pathExtension == "ips" || f.pathExtension == "crash" {
            guard let mod = try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  mod > cutoff else { continue }
            let name = appName(f.deletingPathExtension().lastPathComponent)
            if name == "JetsamEvent" { continue }   // memory-pressure log, not a crash
            counts[name, default: 0] += 1
            total += 1
        }
        if total == 0 { return Outcome(.pass, "None in 24 h") }
        let names = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(2).map(\.key)
        let prefix = "\(total) · "
        let budget = max((32 - prefix.count - 2 * (names.count - 1)) / names.count, 4)
        let detail = prefix + names.map { clip($0, budget) }.joined(separator: ", ")
        return Outcome(total <= 5 ? .warn : .fail, detail)
    }

    /// "Mission Control-2026-10-15-104757" → "Mission Control".
    private nonisolated static func appName(_ stem: String) -> String {
        var s = stem
        if s.hasPrefix("ExcUserFault_") { s.removeFirst("ExcUserFault_".count) }
        if let r = s.range(of: #"-\d{4}-\d{2}-\d{2}-\d{6}"#, options: .regularExpression) {
            return String(s[..<r.lowerBound])
        }
        return s.split(separator: "-").first.map(String.init) ?? s
    }

    private nonisolated static func security() -> Outcome {
        let sip = run("/usr/bin/csrutil", ["status"])?.contains("status: enabled") ?? false
        let fv = run("/usr/bin/fdesetup", ["status"])?.contains("FileVault is On") ?? false
        let detail = "SIP \(sip ? "on" : "off") · FileVault \(fv ? "on" : "off")"
        return Outcome(sip && fv ? .pass : .warn, detail)
    }

    // MARK: - Off-main helpers

    private nonisolated static func nowMs() -> Double {
        Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1_000_000
    }

    private nonisolated static func clip(_ s: String, _ n: Int) -> String {
        s.count <= n ? s : String(s.prefix(n - 1)) + "…"
    }

    /// Runs a CLI with a hard timeout (SIGTERM, then SIGKILL 1 s later).
    /// Returns nil if it couldn't launch or was killed.
    private nonisolated static func run(_ launch: String, _ args: [String], timeout: TimeInterval = 5) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launch)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let box = HealthProcBox(p)
        let pid = p.processIdentifier
        let term = DispatchWorkItem { if box.process.isRunning { box.process.terminate() } }
        let kill9 = DispatchWorkItem { if box.process.isRunning { kill(pid, SIGKILL) } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: term)
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout + 1, execute: kill9)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        term.cancel(); kill9.cancel()
        guard p.terminationReason == .exit else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - Sendable helpers

/// Lets a Process cross into watchdog blocks (isRunning/terminate are thread-safe).
private final class HealthProcBox: @unchecked Sendable {
    let process: Process
    init(_ process: Process) { self.process = process }
}

/// First caller wins; used to resume a continuation exactly once.
private final class HealthOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
