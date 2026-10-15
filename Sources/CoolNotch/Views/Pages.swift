import SwiftUI

// MARK: - Docker logs page

struct DockerLogsView: View {
    @ObservedObject var state: NotchState
    @ObservedObject var docker: DockerService
    let name: String
    @State private var log = "Loading logs…"

    var body: some View {
        ScrollView([.vertical], showsIndicators: true) {
            Text(log)
                .font(.mono(10, .regular))
                .foregroundStyle(DS.textSecondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(9)
        }
        .outline(RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous))
        .frame(maxHeight: .infinity)
        .task(id: state.refreshTick) { log = await docker.logs(name: name) }
    }
}

// MARK: - Chat pieces (shared by session + ask)

struct MessageBubble: View {
    let msg: ChatMsg
    private var isUser: Bool { msg.role == "user" }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(isUser ? "You" : "Claude")
                .font(.label)
                .foregroundStyle(isUser ? DS.accent : DS.good)
            if isUser {
                Text(msg.text)
                    .font(.body)
                    .foregroundStyle(DS.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            } else {
                MarkdownText(text: msg.text)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.inset)
        .outline(RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous), tint: isUser ? DS.accent.opacity(0.45) : nil)
    }
}

/// Message input row. Enter sends; shows a spinner while awaiting a reply.
struct Composer: View {
    @Binding var text: String
    var sending: Bool
    var placeholder: String
    var onSend: () -> Void
    @FocusState private var focused: Bool

    private var empty: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundStyle(DS.textPrimary)
                .focused($focused)
                .onSubmit(onSend)
            if sending {
                ProgressView().controlSize(.small)
            } else {
                Button(action: onSend) {
                    Icon("arrow.up.circle.fill", size: 22.1)
                        .foregroundStyle(empty ? DS.textTertiary : DS.accent)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(Pressable())
                .disabled(empty)
                .accessibilityLabel("Send")
            }
        }
        .padding(.leading, DS.inset).padding(.trailing, 6)
        .frame(height: 36)
        .outline(RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous), tint: focused ? DS.accent.opacity(0.6) : nil)
        .animation(.easeOut(duration: 0.15), value: focused)
        .onAppear {
            NotificationCenter.default.post(name: .coolNotchNeedsKey, object: nil)
            focused = true
        }
        .onTapGesture {
            NotificationCenter.default.post(name: .coolNotchNeedsKey, object: nil)
            focused = true
        }
    }
}

private struct ChatScroll: View {
    let messages: [ChatMsg]
    let streaming: String?   // in-progress assistant text
    let sending: Bool        // request in flight, before first token

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    if messages.isEmpty && streaming == nil && !sending {
                        FeedStatus(icon: "text.bubble", text: "No messages yet")
                    }
                    ForEach(messages) { MessageBubble(msg: $0) }
                    if let streaming {
                        MessageBubble(msg: ChatMsg(role: "assistant", text: streaming))
                    } else if sending {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Claude is thinking…").font(.caption).foregroundStyle(DS.textSecondary)
                        }.padding(.vertical, 4)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
            }
            .onChange(of: messages.count) { _, _ in scroll(proxy) }
            .onChange(of: streaming) { _, _ in scroll(proxy) }
            .onChange(of: sending) { _, _ in scroll(proxy) }
        }
        .background {
            // Pixel pets (or matrix rain) behind the transcript while Claude works.
            if AppSettings.shared.aiEffect && (streaming != nil || sending) {
                Group {
                    if AppSettings.shared.aiEffectStyle == .pets {
                        PixelPetsField(pets: PixelPet.troupe)
                    } else {
                        MatrixField(opacity: 0.13)
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: streaming != nil || sending)
    }
    private func scroll(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("bottom", anchor: .bottom) }
    }
}

// MARK: - Claude session detail (read transcript + send new messages)

struct SessionDetailView: View {
    @ObservedObject var state: NotchState
    @ObservedObject var ai: AIService
    let sessionID: String
    let project: String

    @State private var loaded: [ChatMsg] = []
    @State private var extra: [ChatMsg] = []
    @State private var streaming: String?
    @State private var cwd: String?
    @State private var tokens = 0
    @State private var input = ""
    @State private var sending = false

    private var uuid: String { SessionRouteStore.uuid(for: sessionID) }
    private var path: String { SessionRouteStore.path(for: sessionID) }

    var body: some View {
        VStack(spacing: DS.gap) {
            if tokens > 0 {
                HStack(spacing: 6) {
                    Icon("chart.bar.fill", size: 11.7, weight: .semibold).foregroundStyle(DS.accent)
                    Text(verbatim: "\(compactTokens(tokens)) output tokens this session")
                        .font(.caption).foregroundStyle(DS.textTertiary)
                    Spacer()
                }
            }
            ChatScroll(messages: loaded + extra, streaming: streaming, sending: sending)
                .frame(maxHeight: .infinity)

            HStack(spacing: 8) {
                Composer(text: $input, sending: sending,
                         placeholder: "Message this Claude session…", onSend: send)
                Button { continueInTerminal() } label: {
                    Icon("terminal", size: 14.3, weight: .semibold)
                        .foregroundStyle(hasDraft ? DS.accent : DS.textSecondary)
                        .frame(width: 36, height: 36)
                        .outline(RoundedRectangle(cornerRadius: DS.cardRadius, style: .continuous), tint: hasDraft ? DS.accent.opacity(0.6) : nil)
                }
                .buttonStyle(Pressable())
                .accessibilityLabel("Resume in \(TerminalLauncher.currentName)")
                .help(hasDraft ? "Send message & resume in \(TerminalLauncher.currentName)"
                               : "Resume in \(TerminalLauncher.currentName)")
            }
        }
        .task(id: state.refreshTick) {
            let p = path
            let detail = await Task.detached { ClaudeSessionsService.loadDetail(path: p) }.value
            loaded = detail.messages
            cwd = detail.cwd
            tokens = detail.outputTokens
        }
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        extra.append(ChatMsg(role: "user", text: text))
        input = ""
        sending = true
        streaming = ""
        Task {
            // Fast/cheap model but resumes the session's context — a quick notch reply.
            for await delta in ai.stream(text, cwd: cwd, resume: uuid, model: "claude-haiku-4-5") {
                streaming = (streaming ?? "") + delta
            }
            if let final = streaming { extra.append(ChatMsg(role: "assistant", text: final)) }
            streaming = nil
            sending = false
        }
    }

    private var hasDraft: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Jump into the real session in the user's terminal. If a message is typed,
    /// it's submitted straight into the resumed session (`claude --resume <id> "…"`).
    private func continueInTerminal() {
        let msg = input.trimmingCharacters(in: .whitespacesAndNewlines)
        TerminalLauncher.resumeClaude(uuid: uuid,
                                      cwd: cwd ?? FileManager.default.homeDirectoryForCurrentUser.path,
                                      message: msg.isEmpty ? nil : msg)
        if !msg.isEmpty {
            extra.append(ChatMsg(role: "user", text: msg))
            input = ""
        }
    }
    private func compactTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return "\(n / 1000)K" }
        return "\(n)"
    }
}

// MARK: - Ask Claude (one-shot, fresh)

struct AskView: View {
    @ObservedObject var ai: AIService
    let prompt: String
    @State private var messages: [ChatMsg] = []
    @State private var streaming: String?
    @State private var input = ""
    @State private var sending = false
    @State private var started = false

    // Fast model for quick questions.
    private let model = "claude-haiku-4-5"

    var body: some View {
        VStack(spacing: DS.gap) {
            ChatScroll(messages: messages, streaming: streaming, sending: sending)
                .frame(maxHeight: .infinity)
            Composer(text: $input, sending: sending, placeholder: "Ask another question…", onSend: { ask(input) })
        }
        .task {
            guard !started else { return }
            started = true
            ask(prompt)
        }
    }

    private func ask(_ q: String) {
        let text = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        messages.append(ChatMsg(role: "user", text: text))
        input = ""
        sending = true
        streaming = ""
        Task {
            for await delta in ai.stream(text, model: model) {
                streaming = (streaming ?? "") + delta
            }
            if let final = streaming { messages.append(ChatMsg(role: "assistant", text: final)) }
            streaming = nil
            sending = false
        }
    }
}

/// Bridges a session route (id + project) to the transcript path and UUID
/// captured by the sessions service, without widening the enum.
@MainActor
enum SessionRouteStore {
    private static var paths: [String: String] = [:]
    private static var uuids: [String: String] = [:]
    static func register(_ s: ClaudeSession) {
        paths[s.id] = s.transcriptPath
        uuids[s.id] = s.sessionUUID
    }
    static func path(for id: String) -> String { paths[id] ?? "" }
    static func uuid(for id: String) -> String { uuids[id] ?? "" }
}
