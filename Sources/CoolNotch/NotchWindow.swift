import AppKit
import SwiftUI

/// Borderless, non-activating panel that floats over the notch. Never takes focus.
final class NotchPanel: NSPanel {
    // Can become key so the terminal text field accepts input, but never main —
    // it stays a floating accessory and doesn't activate the app.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The window's content view (flipped, top-left origin to match SwiftUI).
///
/// Hover is decided **manually** against the cursor's real screen position, not by
/// an NSTrackingArea rect — a rect-limited tracking area proved unreliable on a
/// flipped view (it fired far outside its bounds). We install one whole-view
/// tracking area purely to receive move/enter/exit, then test the cursor against
/// the notch rect (collapsed) or the panel rect (expanded) in screen coordinates.
///
///  • Hit-testing (clicks): pass through everything unless expanded and inside the panel.
///  • Hover (expand/collapse): open only while the cursor is inside the notch.
final class NotchContainerView: NSView {
    private let state: NotchState
    private var collapseWork: DispatchWorkItem?
    private var openWork: DispatchWorkItem?

    init(state: NotchState) {
        self.state = state
        super.init(frame: NSRect(origin: .zero, size: state.geo.windowSize))
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    // MARK: Interactive regions in SCREEN coordinates (bottom-left origin)
    // Both rects run a few points PAST the top of the screen: a cursor pushed
    // against the top edge reports y == screen.maxY, which NSRect.contains treats
    // as outside — so the notch wouldn't open and the shoulder tabs wouldn't take
    // hover/clicks exactly where the cursor naturally lands.
    private static let topSlop: CGFloat = 4

    private func notchScreenRect() -> NSRect {
        let s = state.geo
        let t = s.triggerSize
        return NSRect(x: s.screenFrame.midX - t.width / 2,
                      y: s.screenFrame.maxY - t.height,
                      width: t.width, height: t.height + Self.topSlop)
    }
    private func panelScreenRect() -> NSRect {
        let s = state.geo
        let p = s.panelSize
        return NSRect(x: s.screenFrame.midX - p.width / 2,
                      y: s.screenFrame.maxY - p.height,
                      width: p.width, height: p.height + Self.topSlop)
    }

    // MARK: Clicks — solid only over the expanded panel; otherwise pass through.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard state.isExpanded, let window else { return nil }
        let screenPoint = window.convertPoint(toScreen: point)
        return panelScreenRect().contains(screenPoint) ? super.hitTest(point) : nil
    }

    // MARK: Hover — one whole-view tracking area, manual region test.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways],
            owner: self, userInfo: nil
        ))
    }

    override func mouseMoved(with event: NSEvent)   { evaluate() }
    override func mouseEntered(with event: NSEvent) { evaluate() }
    override func mouseExited(with event: NSEvent)  { unpeek(); scheduleCollapse() }

    /// The single source of truth for open/closed, driven by the real cursor.
    private func evaluate() {
        let p = NSEvent.mouseLocation
        if state.isExpanded {
            if panelScreenRect().contains(p) { collapseWork?.cancel() }
            else { scheduleCollapse() }
        } else if notchScreenRect().contains(p) {
            // Peek first (instant feedback), open after a short dwell — so a cursor
            // just passing through the menu bar gets a swell, not a full panel.
            collapseWork?.cancel()
            guard openWork == nil else { return }
            withAnimation(DS.peek) { state.peeking = true }
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.openWork = nil
                    if self.notchScreenRect().contains(NSEvent.mouseLocation) {
                        self.state.expand()
                    } else {
                        withAnimation(DS.peek) { self.state.peeking = false }
                    }
                }
            }
            openWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.09, execute: work)
        } else {
            unpeek()
        }
    }

    private func unpeek() {
        openWork?.cancel(); openWork = nil
        guard state.peeking else { return }
        withAnimation(DS.peek) { state.peeking = false }
    }

    private func scheduleCollapse() {
        collapseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if !self.panelScreenRect().contains(NSEvent.mouseLocation) {
                    self.state.collapseIfUnpinned()
                }
            }
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }
}

/// Owns the panel lifecycle and pins it to the notch of a screen.
@MainActor
final class NotchWindowController {
    /// Identity of the display geometry this window was built for.
    let screenKey: String

    static func key(for screen: NSScreen) -> String {
        let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 ?? 0
        return "\(id)|\(screen.frame)|\(screen.safeAreaInsets.top)|\(screen.backingScaleFactor)"
    }

    /// Take the window off screen and stop background helpers, so a rebuild never
    /// leaves a second notch panel (or an orphaned now-playing adapter) behind.
    func tearDown() {
        nowPlaying.stop()
        panel.orderOut(nil)
        panel.close()
    }

    let panel: NotchPanel
    let state: NotchState
    // Long-lived services (app lifetime). `claude`/`ai` are read by the menu-bar
    // pets controller to know when agents are working.
    private let battery = BatteryService()
    let claude = ClaudeSessionsService()
    private let docker = DockerService()
    private let clipboard = ClipboardService()
    let ai = AIService()
    private let nowPlaying = NowPlayingService()
    private let claudeNotify = ClaudeNotifyWatcher()
    private let volume = VolumeMonitor()
    private let dev = DevService()
    private let calendar = CalendarService()

    init(screen: NSScreen) {
        let geo = NotchGeometry.detect(for: screen)
        let state = NotchState(geo: geo)
        self.state = state

        // Route service events into the notification pill.
        claude.onNotify = { [weak state] in state?.notify($0) }
        docker.onNotify = { [weak state] in state?.notify($0) }
        claudeNotify.onNotify = { [weak state] in state?.notify($0) }
        battery.onNotify = { [weak state] in state?.notify($0) }
        volume.onChange = { [weak state] level, muted in
            if AppSettings.shared.hideSystemHUD { SystemHUD.killOSD() }
            let icon: String = muted || level == 0 ? "speaker.slash.fill"
                : (level < 0.34 ? "speaker.wave.1.fill"
                : (level < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"))
            state?.showHUD(HUDInfo(icon: icon, level: muted ? 0 : level))
        }
        volume.start()
        calendar.start()

        let panel = NotchPanel(
            contentRect: NSRect(origin: .zero, size: geo.windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        // Above the menu bar and its status items, so the shoulder tabs (which sit
        // in the menu-bar strip) receive the cursor instead of the menu bar.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                    .fullScreenAuxiliary, .ignoresCycle]
        panel.acceptsMouseMovedEvents = true

        let container = NotchContainerView(state: state)
        let host = NSHostingView(rootView: RootView(
            state: state, battery: battery, claude: claude, docker: docker,
            clipboard: clipboard, ai: ai, nowPlaying: nowPlaying, dev: dev, calendar: calendar))
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
        panel.contentView = container

        // Top-centered on the screen.
        let x = screen.frame.midX - geo.windowSize.width / 2
        let y = screen.frame.maxY - geo.windowSize.height
        panel.setFrameOrigin(NSPoint(x: x, y: y))

        self.panel = panel
        self.screenKey = Self.key(for: screen)
        panel.orderFrontRegardless()
    }
}
