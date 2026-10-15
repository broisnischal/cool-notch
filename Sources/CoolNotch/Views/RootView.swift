import SwiftUI

/// The fluid surface. One pure-black shape that morphs between the idle notch,
/// the collapsed live activities (media, working, notification, HUD) and the
/// full panel. No border, no glow, no shadow: it reads as the notch itself.
///
/// Motion: one spring drives the whole shape — width, height, ears and radius
/// together — so it opens as a single surface. Content is laid out at its final
/// position the whole time and just fades in as the shape uncovers it: nothing
/// inside scales, slides or reflows while it opens.
struct RootView: View {
    @ObservedObject var state: NotchState
    @ObservedObject var battery: BatteryService
    @ObservedObject var claude: ClaudeSessionsService
    @ObservedObject var docker: DockerService
    @ObservedObject var clipboard: ClipboardService
    @ObservedObject var ai: AIService
    @ObservedObject var nowPlaying: NowPlayingService
    @ObservedObject var dev: DevService
    @ObservedObject var calendar: CalendarService
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shake: CGFloat = 0

    var body: some View {
        let g = state.geo
        let expanded = state.isExpanded
        // Pets in the open panel: any Claude session touched in the last few minutes.
        let aiWorking = ai.activeStreams > 0 || claude.sessions.contains(where: \.isActive)
        // The collapsed "working" activity is stricter — only while a reply is being
        // written right now — so the idle notch stays a plain notch the rest of the time.
        let writingNow = ai.activeStreams > 0
            || claude.sessions.contains { Date().timeIntervalSince($0.modified) < 20 }
        let showHUD = !expanded && state.hud != nil
        let showPill = !expanded && !showHUD && state.notification != nil
        let showTyping = !expanded && !showHUD && !showPill && writingNow && settings.aiEffect
        let showMedia = !expanded && !showHUD && !showPill && !showTyping
            && settings.mediaLiveActivity && (nowPlaying.info?.isPlaying ?? false)

        let lifted = expanded || showPill || showMedia || showHUD || showTyping
        // 0 = notch, 1 = media, 2 = typing, 3 = pill, 4 = hud, 5 = panel
        let mode = expanded ? 5 : (showHUD ? 4 : (showPill ? 3 : (showTyping ? 2 : (showMedia ? 1 : 0))))
        let base: CGSize = expanded ? g.panelSize
            : (showHUD ? g.hudSize : (showPill ? g.pillSize
            : ((showTyping || showMedia) ? g.mediaSize : g.collapsedSize)))
        // Hover peek: the idle surface swells evenly under the cursor before opening.
        let peek = !expanded && state.peeking
        let size = peek ? CGSize(width: base.width + 24, height: base.height + 5) : base
        let radius: CGFloat = expanded ? DS.panelRadius : (lifted ? 13 : DS.notchBottom)
        let shape = NotchShape(bottom: radius, topFlare: expanded ? 10 : 6)

        let shapeAnim: Animation = reduceMotion ? .easeOut(duration: 0.2)
            : (lifted ? DS.expand : DS.collapse)

        // Layout is FIXED to the window: content sits at its final, centred position
        // from the first frame; only the black surface and the mask (both centred,
        // top-anchored) animate. So the panel grows evenly out of the camera and
        // nothing inside ever slides sideways.
        ZStack(alignment: .top) {
            shape.fill(DS.surface)
                .frame(width: size.width, height: size.height)

            // ALWAYS mounted (even collapsed) so Claude streams keep running in the
            // background; re-expanding shows the continued state. Fades in after the
            // surface has started to open, and out immediately when it closes.
            PanelContent(state: state, battery: battery, claude: claude,
                         docker: docker, clipboard: clipboard, ai: ai,
                         nowPlaying: nowPlaying, dev: dev, calendar: calendar)
                .frame(width: g.panelSize.width, height: g.panelSize.height, alignment: .top)
                .allowsHitTesting(expanded)

            // Pixel pets stroll along the floor of the panel while Claude works.
            if expanded && settings.aiEffect && settings.aiEffectStyle == .pets {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    // Small enough to stroll inside the bottom padding of the panel.
                    PixelPetsField(pets: PixelPet.menuTroupe(px: 1.5), baseline: 1)
                        .frame(height: 16)
                }
                .frame(width: g.panelSize.width, height: g.panelSize.height, alignment: .top)
                .opacity(aiWorking ? 1 : 0)
                .animation(.easeInOut(duration: 0.5), value: aiWorking)
                .allowsHitTesting(false)
            }

            if !expanded {
                Group {
                    if let hud = state.hud {
                        HUDView(hud: hud, notchWidth: g.notchWidth)
                            .frame(width: g.hudSize.width, height: g.hudSize.height, alignment: .top)
                    } else if let n = state.notification {
                        NotificationHUD(notification: n, notchWidth: g.notchWidth)
                            .frame(width: g.pillSize.width, height: g.pillSize.height, alignment: .top)
                    } else if showTyping {
                        Group {
                            if settings.aiEffectStyle == .pets {
                                NotchPetsActivity(notchWidth: g.notchWidth)
                            } else {
                                NotchMatrixActivity(notchWidth: g.notchWidth)
                            }
                        }
                        .frame(width: g.mediaSize.width, height: g.mediaSize.height, alignment: .top)
                    } else if showMedia, let info = nowPlaying.info {
                        MediaLiveActivity(info: info, artwork: nowPlaying.artwork, notchWidth: g.notchWidth)
                            .frame(width: g.mediaSize.width, height: g.mediaSize.height, alignment: .top)
                    }
                }
                // Gone instantly when the panel opens (so it never overlaps the
                // shoulder tabs); fades back in only once the panel has closed.
                .transition(.asymmetric(
                    insertion: .opacity.animation(.easeOut(duration: 0.18).delay(0.16)),
                    removal: .identity))
            }
        }
        .frame(width: g.windowSize.width, height: g.windowSize.height, alignment: .top)
        .mask(alignment: .top) { shape.frame(width: size.width, height: size.height) }
        .animation(shapeAnim, value: mode)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : DS.peek, value: peek)
        .modifier(ShakeEffect(animatableData: shake))
        .onChange(of: state.notification?.id) { _, newValue in
            guard newValue != nil, !reduceMotion else { return }
            withAnimation(.linear(duration: 0.35)) { shake += 1 }
        }
        .frame(width: g.windowSize.width, height: g.windowSize.height, alignment: .top)
        .environment(\.colorScheme, .dark)
        .focusEffectDisabled()   // no blue focus ring on the toolbar buttons
        .environmentObject(state)
    }
}
