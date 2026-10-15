import SwiftUI

/// The developer surface: a focus timer, git/PR status for the active Claude
/// project, and listening ports.
struct DevView: View {
    @ObservedObject var dev: DevService
    @ObservedObject var claude: ClaudeSessionsService
    @StateObject private var pomodoro = PomodoroTimer.shared
    @State private var git: GitStatus?
    @State private var gitProject: String?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 14) {
                pomodoroCard
                Hairline(inset: 0)
                gitCard
                Hairline(inset: 0)
                portsCard
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
        .task(id: claude.sessions.first?.id) { await loadGit() }
    }

    private func loadGit() async {
        guard let top = claude.sessions.first else { git = nil; return }
        let detail = await Task.detached { ClaudeSessionsService.loadDetail(path: top.transcriptPath) }.value
        guard let cwd = detail.cwd else { git = nil; return }
        gitProject = top.project
        git = await dev.gitStatus(cwd: cwd)
    }

    // MARK: Pomodoro
    private var pomodoroCard: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().stroke(DS.hairline, lineWidth: 3)
                Circle().trim(from: 0, to: pomodoro.progress)
                    .stroke(pomodoro.isBreak ? DS.good : DS.accent,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.3), value: pomodoro.progress)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(pomodoro.label).font(.mono(15, .semibold)).foregroundStyle(DS.textPrimary)
                Text("\(pomodoro.isBreak ? "Break" : "Focus") · \(pomodoro.running ? "running" : "paused")")
                    .font(.caption).foregroundStyle(DS.textSecondary)
            }
            Spacer()
            HStack(spacing: 6) {
                MediaButton(symbol: "arrow.counterclockwise", size: 10, label: "Reset timer") { pomodoro.reset() }
                MediaButton(symbol: pomodoro.running ? "pause.fill" : "play.fill",
                            size: 11, prominent: true,
                            label: pomodoro.running ? "Pause timer" : "Start timer") { pomodoro.toggle() }
            }
        }
    }

    // MARK: Git
    @ViewBuilder private var gitCard: some View {
        if let git {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Icon("arrow.triangle.branch", size: 13, weight: .semibold).foregroundStyle(DS.accent)
                    Text(git.branch).font(.title).foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    if let project = gitProject {
                        Text(project).font(.caption).foregroundStyle(DS.textTertiary)
                            .lineLimit(1)
                    }
                }
                HStack(spacing: 6) {
                    stat("\(git.dirty)", "changed", git.dirty > 0 ? DS.amber : DS.textSecondary)
                    if git.ahead > 0 { stat("↑\(git.ahead)", "ahead", DS.good) }
                    if git.behind > 0 { stat("↓\(git.behind)", "behind", DS.danger) }
                }
                if let title = git.prTitle {
                    HStack(spacing: 6) {
                        Icon("arrow.triangle.pull", size: 11.7, weight: .semibold)
                            .foregroundStyle(prColor(git.prState))
                        Text(title).font(.caption).foregroundStyle(DS.textSecondary)
                            .lineLimit(1)
                        if let checks = git.checks {
                            Text(checks).font(.label)
                                .foregroundStyle(checks.contains("fail") ? DS.danger : DS.good)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 6) {
                Icon("arrow.triangle.branch", size: 13, weight: .regular)
                Text("No git repo in the active session").font(.caption)
                Spacer()
            }
            .foregroundStyle(DS.textTertiary)
        }
    }

    private func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Text(value).font(.mono(10.5, .semibold)).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(DS.textTertiary)
        }
        .padding(.horizontal, 8).frame(height: 20)
        .outline(Capsule())
    }

    private func prColor(_ state: String?) -> Color {
        switch state {
        case "OPEN": return DS.good
        case "MERGED": return DS.accent
        default: return DS.textSecondary
        }
    }

    // MARK: Ports
    private var portsCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: "Listening ports") {
                Text("\(dev.ports.count)").font(.mono(10, .semibold)).foregroundStyle(DS.textTertiary)
            }
            if dev.ports.isEmpty {
                Text("Nothing listening").font(.caption).foregroundStyle(DS.textTertiary)
            } else {
                ForEach(dev.ports.prefix(8)) { port in
                    HStack(spacing: 8) {
                        Text(verbatim: ":\(port.port)").font(.mono(11, .semibold)).foregroundStyle(DS.accent)
                            .frame(width: 52, alignment: .leading)
                        Text(port.process).font(.body).foregroundStyle(DS.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Text(verbatim: "pid \(port.pid)").font(.mono(9.5, .regular)).foregroundStyle(DS.textTertiary)
                    }
                    .frame(height: 20)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
