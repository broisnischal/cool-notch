import SwiftUI

/// One-tap device health check: a borderless summary with a progress/verdict ring,
/// then every check in a two-column list split by hairlines (no box per check).
/// Runs automatically the first time the tab opens; "Run again" re-runs it.
struct HealthView: View {
    @ObservedObject var health: HealthService

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 14) {
                summary
                Hairline(inset: 0)
                grid
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 4)
        }
        .onAppear { if health.lastRun == nil && !health.isRunning { health.runAll() } }
    }

    private var done: Int { health.passed + health.warned + health.failed }

    /// Two columns, a vertical hairline between them, a horizontal one between rows.
    private var grid: some View {
        let rows = stride(from: 0, to: health.checks.count, by: 2).map {
            Array(health.checks[$0..<min($0 + 2, health.checks.count)])
        }
        return VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 0) {
                    CheckCell(check: rows[r][0])
                    Hairline(vertical: true).padding(.vertical, 8)
                    if rows[r].count > 1 { CheckCell(check: rows[r][1]) }
                    else { Color.clear.frame(maxWidth: .infinity) }
                }
                if r < rows.count - 1 { Hairline() }
            }
        }
    }

    private var summary: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().stroke(DS.hairline, lineWidth: 4)
                Circle()
                    .trim(from: 0, to: health.checks.isEmpty ? 0 : CGFloat(done) / CGFloat(health.checks.count))
                    .stroke(verdictColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(DS.content, value: done)
                Icon(verdictSymbol, size: 16, weight: .bold)
                    .foregroundStyle(verdictColor)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(verdict).font(.ui(15, .semibold)).foregroundStyle(DS.textPrimary).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(DS.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            if !health.isRunning {   // while running, the ring itself shows progress
                PillButton(title: health.lastRun == nil ? "Run check" : "Run again",
                           symbol: "arrow.clockwise", prominent: true) { health.runAll() }
            }
        }
    }

    private var verdict: String {
        if health.isRunning { return "Checking your Mac…" }
        if health.lastRun == nil { return "Not checked yet" }
        if health.failed > 0 { return "\(health.failed) \(health.failed == 1 ? "problem" : "problems") found" }
        if health.warned > 0 { return "\(health.warned) \(health.warned == 1 ? "thing" : "things") to look at" }
        return "Everything's running well"
    }

    private var detail: String {
        if health.isRunning { return "\(done) of \(health.checks.count) checks done" }
        guard let last = health.lastRun else { return "\(health.checks.count) checks · network, system, storage" }
        let time = last.formatted(date: .omitted, time: .shortened)
        return "\(health.passed) passed · \(health.warned) warn · \(health.failed) fail · \(time)"
    }

    private var verdictColor: Color {
        if health.isRunning || health.lastRun == nil { return DS.accent }
        if health.failed > 0 { return DS.danger }
        if health.warned > 0 { return DS.amber }
        return DS.good
    }

    private var verdictSymbol: String {
        if health.isRunning || health.lastRun == nil { return "stethoscope" }
        if health.failed > 0 { return "xmark" }
        if health.warned > 0 { return "exclamationmark" }
        return "checkmark"
    }
}

private struct CheckCell: View {
    let check: HealthCheck

    var body: some View {
        HStack(spacing: 8) {
            Icon(check.icon, size: 13, weight: .semibold)
                .foregroundStyle(color)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 0) {
                Text(check.title).font(.ui(11, .semibold)).foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                Text(check.detail.isEmpty ? placeholder : check.detail)
                    .font(.ui(9.5, .regular)).foregroundStyle(DS.textSecondary)
                    .lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 0)
            status
        }
        .rowSurface(height: 42)
        .help(check.detail)
        .animation(DS.content, value: check.status)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(check.title), \(statusText)\(check.detail.isEmpty ? "" : ", " + check.detail)")
    }

    @ViewBuilder private var status: some View {
        switch check.status {
        case .running: StatusDot(color: DS.accent, pulsing: true)
        case .pending: Circle().fill(DS.textTertiary).frame(width: 5, height: 5).frame(width: 12)
        default:
            Icon(symbol, size: 14.3, weight: .semibold).foregroundStyle(color)
                .transition(.iconSwap)
        }
    }

    private var statusText: String {
        switch check.status {
        case .pending: return "not checked"
        case .running: return "checking"
        case .pass:    return "passed"
        case .warn:    return "warning"
        case .fail:    return "failed"
        }
    }

    private var placeholder: String {
        check.status == .running ? "Checking…" : "—"
    }

    private var symbol: String {
        switch check.status {
        case .pass: return "checkmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .fail: return "xmark.octagon.fill"
        default:    return "circle"
        }
    }

    private var color: Color {
        switch check.status {
        case .pass: return DS.good
        case .warn: return DS.amber
        case .fail: return DS.danger
        default:    return DS.textTertiary
        }
    }
}
