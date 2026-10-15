import SwiftUI

/// Live network diagnostics, laid out like an instrument rather than a grid of
/// boxes: a big latency readout over a full-width live chart, one row of stats,
/// the speed test, then connection details — grouped by space and hairlines.
/// Monitoring runs only while this tab is on screen and the panel is open.
struct NetworkView: View {
    @ObservedObject var state: NotchState
    @ObservedObject var net: NetworkService

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                PingHero(net: net)
                StatsRow(net: net)
                Hairline(inset: 0)
                SpeedTestRow(net: net)
                Hairline(inset: 0)
                DetailsGrid(net: net)
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 4)
        }
        .onAppear { sync() }
        .onDisappear { net.stopMonitoring() }
        .onChange(of: state.isExpanded) { _, _ in sync() }
    }

    private func sync() {
        state.isExpanded ? net.startMonitoring() : net.stopMonitoring()
    }
}

// MARK: - Formatting

/// Bytes/s → ("1.2", "MB/s").
func rate(_ bps: Double?) -> (String, String) {
    guard let b = bps else { return ("—", "") }
    switch b {
    case ..<1024:          return (String(format: "%.0f", b), "B/s")
    case ..<(1024 * 1024): return (String(format: "%.0f", b / 1024), "KB/s")
    default:               return (String(format: "%.1f", b / 1_048_576), "MB/s")
    }
}

func latencyColor(_ ms: Double?) -> Color {
    guard let ms else { return DS.textPrimary }
    return ms < 60 ? DS.good : (ms < 150 ? DS.amber : DS.danger)
}

private func ms(_ v: Double?) -> String {
    guard let v else { return "—" }
    return v < 10 ? String(format: "%.1f", v) : String(format: "%.0f", v)
}

// MARK: - Ping hero

private struct PingHero: View {
    @ObservedObject var net: NetworkService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(ms(net.lastMs))
                            .font(.mono(30, .semibold)).tracking(-0.8)
                            .foregroundStyle(latencyColor(net.lastMs))
                            .contentTransition(.numericText())
                        Text("ms").font(.mono(12, .medium)).foregroundStyle(DS.textTertiary)
                    }
                    Text(caption).font(.caption).foregroundStyle(DS.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 12)
                Segmented(options: NetworkService.targets.map { ($0, $0 == "gateway" ? "Router" : $0) },
                          selection: Binding(get: { net.target }, set: { net.setTarget($0) }))
            }
            LatencyChart(samples: net.samples)
                .frame(height: 54)
        }
    }

    private var caption: String {
        let host = net.target == "gateway" ? "router" : net.target
        guard net.sent > 0 else { return "Pinging \(host)…" }
        return "Ping to \(host) · avg \(ms(net.avgMs)) · max \(ms(net.maxMs)) ms"
    }
}

/// Rolling latency line over the last 60 probes, filling in from the trailing
/// edge. Flat, low-opacity area under the line (no gradient); a lost probe breaks
/// the line and draws a red tick.
private struct LatencyChart: View {
    let samples: [PingSample]
    private let slots = 60

    var body: some View {
        Canvas { gc, size in
            let W = size.width, H = size.height
            // Baseline + a faint mid guide.
            gc.fill(Path(CGRect(x: 0, y: H - 1, width: W, height: 1)), with: .color(DS.hairline))
            gc.fill(Path(CGRect(x: 0, y: H / 2, width: W, height: 1)), with: .color(DS.hairline.opacity(0.4)))

            guard samples.count > 1 else { return }
            let ceiling = max(40, (samples.compactMap(\.ms).max() ?? 40) * 1.15)
            let step = W / CGFloat(slots - 1)
            let start = slots - samples.count
            func point(_ j: Int, _ v: Double) -> CGPoint {
                CGPoint(x: CGFloat(start + j) * step, y: H - 2 - (H - 6) * CGFloat(min(1, v / ceiling)))
            }
            let tint = latencyColor(samples.last(where: { $0.ms != nil })?.ms)

            // Split into runs of consecutive successful probes.
            var runs: [[CGPoint]] = [[]]
            for (j, s) in samples.enumerated() {
                if let v = s.ms { runs[runs.count - 1].append(point(j, v)) }
                else {
                    let x = CGFloat(start + j) * step
                    gc.fill(Path(roundedRect: CGRect(x: x - 1, y: 0, width: 2, height: H), cornerRadius: 1),
                            with: .color(DS.danger.opacity(0.7)))
                    runs.append([])
                }
            }
            for run in runs where run.count > 1 {
                var area = Path()
                area.move(to: CGPoint(x: run[0].x, y: H))
                run.forEach { area.addLine(to: $0) }
                area.addLine(to: CGPoint(x: run[run.count - 1].x, y: H))
                area.closeSubpath()
                gc.fill(area, with: .color(tint.opacity(0.10)))

                var line = Path()
                line.addLines(run)
                gc.stroke(line, with: .color(tint), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
            if let last = runs.last?.last {
                gc.fill(Path(ellipseIn: CGRect(x: last.x - 3, y: last.y - 3, width: 6, height: 6)), with: .color(tint))
            }
        }
        .overlay {
            if samples.count < 2 {
                Text("Measuring…").font(.caption).foregroundStyle(DS.textTertiary)
            }
        }
        .accessibilityLabel("Latency history")
    }
}

// MARK: - Stats

private struct StatsRow: View {
    @ObservedObject var net: NetworkService

    var body: some View {
        let rx = rate(net.throughput?.rxBps), tx = rate(net.throughput?.txBps)
        HStack(spacing: 0) {
            StatTile(label: "Jitter", value: ms(net.jitterMs), unit: "ms", tint: jitterTint)
            Hairline(vertical: true).padding(.trailing, 14)
            StatTile(label: "Loss", value: net.sent == 0 ? "—" : String(format: "%.0f", net.lossPct),
                     unit: "%", tint: lossTint)
            Hairline(vertical: true).padding(.trailing, 14)
            StatTile(label: "Receiving", value: rx.0, unit: rx.1)
            Hairline(vertical: true).padding(.trailing, 14)
            StatTile(label: "Sending", value: tx.0, unit: tx.1)
        }
        .frame(height: 38)
    }

    private var jitterTint: Color {
        guard let j = net.jitterMs else { return DS.textPrimary }
        return j < 10 ? DS.textPrimary : (j < 30 ? DS.amber : DS.danger)
    }
    private var lossTint: Color {
        guard net.sent > 0 else { return DS.textPrimary }
        return net.lossPct == 0 ? DS.textPrimary : (net.lossPct < 3 ? DS.amber : DS.danger)
    }
}

// MARK: - Speed test

private struct SpeedTestRow: View {
    @ObservedObject var net: NetworkService
    @State private var startedAt = Date()

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Speed test").font(.title).foregroundStyle(DS.textPrimary)
                result
            }
            Spacer(minLength: 8)
            if net.speedTesting {
                PillButton(title: "Stop") { net.cancelSpeedTest() }
            } else {
                PillButton(title: net.speed == nil ? "Run test" : "Run again", symbol: "speedometer",
                           prominent: true) {
                    startedAt = Date()
                    net.runSpeedTest()
                }
            }
        }
    }

    @ViewBuilder private var result: some View {
        if net.speedTesting {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                HStack(spacing: 8) {
                    ScanBar().frame(width: 120, height: 3)
                    Text("Testing · \(Int(ctx.date.timeIntervalSince(startedAt)))s")
                        .font(.mono(10.5, .medium)).foregroundStyle(DS.textSecondary)
                }
            }
        } else if let err = net.speedError {
            Text(err).font(.caption).foregroundStyle(DS.danger).lineLimit(1)
        } else if let s = net.speed {
            HStack(spacing: 14) {
                value("↓", mbps(s.downMbps), "Mbps")
                value("↑", mbps(s.upMbps), "Mbps")
                if let rpm = s.rpm { value("", "\(rpm)", "RPM") }
                Text(s.date, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                    .font(.caption).foregroundStyle(DS.textTertiary)
            }
        } else {
            Text("Download, upload and responsiveness via macOS networkQuality")
                .font(.caption).foregroundStyle(DS.textTertiary).lineLimit(1)
        }
    }

    private func value(_ arrow: String, _ v: String, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            if !arrow.isEmpty { Text(arrow).font(.mono(11, .semibold)).foregroundStyle(DS.accent) }
            Text(v).font(.mono(14, .semibold)).foregroundStyle(DS.textPrimary)
            Text(unit).font(.mono(10, .medium)).foregroundStyle(DS.textTertiary)
        }
    }

    private func mbps(_ v: Double) -> String {
        v < 10 ? String(format: "%.1f", v) : String(format: "%.0f", v)
    }
}

/// Indeterminate progress: a short accent segment gliding along a hairline track.
private struct ScanBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { ctx in
            GeometryReader { g in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let p = reduceMotion ? 0.35 : (sin(t * 2.2) + 1) / 2
                let seg = g.size.width * 0.3
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.hairline)
                    Capsule().fill(DS.accent).frame(width: seg)
                        .offset(x: (g.size.width - seg) * p)
                }
            }
        }
        .accessibilityLabel("Speed test running")
    }
}

// MARK: - Details

/// Key/value pairs in a 4-column grid (key, value, key, value): both key columns
/// size to their content and every value starts on a shared edge.
private struct DetailsGrid: View {
    @ObservedObject var net: NetworkService

    var body: some View {
        let l = net.link
        let t = net.throughput
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 7) {
            row("Network", l.map { "\($0.ssid ?? $0.kind) · \($0.interface)" },
                "Signal", l?.rssi.map { sig in "\(sig) dBm" + (l?.noise.map { " · SNR \(sig - $0)" } ?? "") })
            row("Local IP", l?.localIP, "Public IP", net.publicIP)
            row("Gateway", l?.gateway,
                "DNS", l.flatMap { $0.dns.isEmpty ? nil : $0.dns.prefix(2).joined(separator: ", ") })
            row("Link rate", l?.txRate.map { String(format: "%.0f Mbps", $0) },
                "Packets", t.map { String(format: "%.0f in · %.0f out /s", $0.rxPps, $0.txPps) })
        }
    }

    private func row(_ k1: String, _ v1: String?, _ k2: String, _ v2: String?) -> some View {
        GridRow {
            key(k1); value(v1)
            key(k2).padding(.leading, 10); value(v2)
        }
    }
    private func key(_ k: String) -> some View {
        Text(k).font(.caption).foregroundStyle(DS.textTertiary).lineLimit(1)
    }
    private func value(_ v: String?) -> some View {
        Text(v ?? "—").font(.mono(11, .medium)).foregroundStyle(DS.textPrimary)
            .lineLimit(1).truncationMode(.middle)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
