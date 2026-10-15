import SwiftUI

/// The expanded panel: shoulder tabs in the notch strip, then either the selected
/// feed or a pushed detail page (with its own back row) that slides in from the
/// trailing edge. Settings and Keep Open live in the right-click menu, so the
/// surface itself carries nothing but content.
struct PanelContent: View {
    @ObservedObject var state: NotchState
    @ObservedObject var battery: BatteryService
    @ObservedObject var claude: ClaudeSessionsService
    @ObservedObject var docker: DockerService
    @ObservedObject var clipboard: ClipboardService
    @ObservedObject var ai: AIService
    @ObservedObject var nowPlaying: NowPlayingService
    @ObservedObject var dev: DevService
    @ObservedObject var calendar: CalendarService
    // Owned here (PanelContent is always mounted) so results survive tab switches.
    @StateObject private var network = NetworkService()
    @StateObject private var health = HealthService()

    var body: some View {
        VStack(spacing: 0) {
            ShoulderTabs(state: state)
                .revealOnExpand(state.isExpanded, index: 0)

            ZStack(alignment: .top) {
                // The feed stays mounted under a detail page so its scroll/state survive.
                feed
                    .id(state.selectedTab)
                    .transition(.asymmetric(
                        insertion: .offset(x: 18 * state.tabDirection).combined(with: .opacity),
                        removal: .opacity.animation(.easeOut(duration: 0.1))))
                    .opacity(state.route == nil ? 1 : 0)
                    .allowsHitTesting(state.route == nil)

                if let route = state.route {
                    VStack(alignment: .leading, spacing: DS.gap) {
                        BackRow(title: route.title) { state.pop() }
                        detail(route)
                    }
                    .transition(.asymmetric(
                        insertion: .offset(x: 24).combined(with: .opacity),
                        removal: .offset(x: 24).combined(with: .opacity)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 10)
            .revealOnExpand(state.isExpanded, index: 1)
        }
        .padding(.horizontal, DS.panelPadding)
        .padding(.bottom, DS.panelPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .contextMenu {
            Button(state.isPinned ? "Unpin" : "Keep Open") { state.togglePin() }
            Button("Settings…") {
                NotificationCenter.default.post(name: .coolNotchOpenPrefs, object: nil)
            }
        }
        // Fresh data every time the panel opens — no manual refresh needed.
        .onChange(of: state.isExpanded) { _, open in if open { refresh() } }
    }

    @ViewBuilder private var feed: some View {
        switch state.selectedTab {
        case .home:          HomeView(state: state, battery: battery, nowPlaying: nowPlaying, calendar: calendar)
        case .claude:        ClaudeView(state: state, claude: claude)
        case .network:       NetworkView(state: state, net: network)
        case .health:        HealthView(health: health)
        case .dev:           DevView(dev: dev, claude: claude)
        case .docker:        DockerView(state: state, docker: docker)
        case .clipboard:     ClipboardView(clipboard: clipboard)
        case .bookmarks:     BookmarksView()
        case .mirror:        MirrorView()
        case .notifications: NotificationsView()
        }
    }

    @ViewBuilder private func detail(_ route: NotchRoute) -> some View {
        switch route {
        case .dockerLogs(let name):
            DockerLogsView(state: state, docker: docker, name: name)
        case .session(let id, let project):
            SessionDetailView(state: state, ai: ai, sessionID: id, project: project)
        case .ask(let prompt):
            AskView(ai: ai, prompt: prompt)
        }
    }

    private func refresh() {
        claude.refresh()
        docker.refresh()
        state.bumpRefresh()
    }
}

/// Back affordance for a pushed page: chevron + page title in a quiet capsule.
struct BackRow: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Icon("chevron.left", size: 12.3, weight: .bold)
                Text(title).font(.title).lineLimit(1).truncationMode(.middle)
            }
            .foregroundStyle(hovering ? DS.textPrimary : DS.textSecondary)
            .padding(.leading, 8).padding(.trailing, 10)
            .frame(height: 26)
            .outline(Capsule(), hovering: hovering)
            .contentShape(Capsule())
        }
        .buttonStyle(Pressable())
        .accessibilityLabel("Back")
        .onHover { h in withAnimation(DS.hover) { hovering = h } }
    }
}

/// The Home feed: a borderless hero (clock ⟷ battery, mirrored about the centre),
/// then media and the shelf.
struct HomeView: View {
    @ObservedObject var state: NotchState
    @ObservedObject var battery: BatteryService
    @ObservedObject var nowPlaying: NowPlayingService
    @ObservedObject var calendar: CalendarService

    var body: some View {
        VStack(spacing: DS.section) {
            HomeHero(info: battery.info, event: calendar.events.first)
                .padding(.horizontal, 4)
            MediaCard(np: nowPlaying)
            ShelfView(state: state)
        }
    }
}
