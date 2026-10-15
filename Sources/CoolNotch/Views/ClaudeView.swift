import SwiftUI

/// Recent Claude Code sessions, most-recent first. Active sessions get a pulsing
/// green dot and a "live" badge.
struct ClaudeView: View {
    @ObservedObject var state: NotchState
    @ObservedObject var claude: ClaudeSessionsService
    @State private var ask = ""

    var body: some View {
        VStack(spacing: DS.gap) {
            Composer(text: $ask, sending: false, placeholder: "Ask Claude anything…") {
                let q = ask.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !q.isEmpty else { return }
                state.push(.ask(prompt: q))
                ask = ""
            }

            if claude.sessions.isEmpty {
                FeedStatus(icon: "ellipsis.bubble", text: "No recent Claude sessions")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    SeparatedList(items: claude.sessions) { session in
                        SessionRow(session: session) {
                            SessionRouteStore.register(session)
                            state.push(.session(id: session.id, project: session.project))
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

struct SessionRow: View {
    let session: ClaudeSession
    let onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onTap) { rowContent }
            .buttonStyle(Pressable())
            .onHover { h in withAnimation(DS.hover) { hovering = h } }
    }

    private var rowContent: some View {
        HStack(spacing: 8) {
            StatusDot(color: session.isActive ? DS.good : DS.textTertiary, pulsing: session.isActive)

            VStack(alignment: .leading, spacing: 1) {
                Text(session.project)
                    .font(.title)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1).truncationMode(.middle)
                Text(session.modified, format: .relative(presentation: .numeric))
                    .font(.caption)
                    .foregroundStyle(DS.textSecondary)
            }
            Spacer(minLength: 6)
            if hovering {
                IconButton(symbol: "terminal",
                           help: "Resume in \(TerminalLauncher.currentName)", action: openInTerminal)
                    .transition(.iconSwap)
            }
            if session.isActive {
                Text("LIVE")
                    .font(.label).tracking(0.4)
                    .foregroundStyle(DS.good)
                    .padding(.horizontal, 6).frame(height: 16)
                    .outline(Capsule(), tint: DS.good.opacity(0.5))
            }
            Icon("chevron.right", size: 11.7, weight: .semibold)
                .foregroundStyle(DS.textTertiary)
        }
        .rowSurface(hovering: hovering)
    }

    /// Jump this session into the user's terminal (`claude --resume`), cd'd to the
    /// project. The cwd lives inside the transcript, so read it off-main first.
    private func openInTerminal() {
        let path = session.transcriptPath
        let uuid = session.sessionUUID
        Task {
            let detail = await Task.detached { ClaudeSessionsService.loadDetail(path: path, maxMessages: 1) }.value
            TerminalLauncher.resumeClaude(uuid: uuid, cwd: detail.cwd)
        }
    }
}
