import AppKit
import SwiftUI
import Combine

/// AppKit "helpfully" constrains borderless windows to sit BELOW the visible menu
/// bar — which shoved strip windows down a bar-height whenever they were created
/// while the bar was showing. Our strips are positioned deliberately; keep the rect.
final class UnconstrainedPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// Pixel pets strolling across the macOS menu bar — one click-through strip window
/// per screen at status-bar level, ordered just below the notch panel so pets
/// disappear behind the notch as they cross it (like walking behind the camera).
/// Modes: always, only while agents are working, or off.
@MainActor
final class MenuBarPetsController {
    var notchWindowNumber: Int?
    private var panels: [NSPanel] = []
    private var subs: Set<AnyCancellable> = []
    private var working = false

    /// Watch the Claude sessions + in-notch streams so "while working" mode can
    /// show/hide the troupe live. Re-call after the services are rebuilt.
    func bind(claude: ClaudeSessionsService, ai: AIService) {
        subs.removeAll()
        claude.$sessions.map { $0.contains(where: \.isActive) }
            .combineLatest(ai.$activeStreams.map { $0 > 0 })
            .map { $0 || $1 }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] on in
                guard let self else { return }
                self.working = on
                if AppSettings.shared.menuBarPets == .working { self.refresh() }
            }
            .store(in: &subs)
    }

    /// Rebuild the strips for the current screens + settings.
    func refresh() {
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        switch AppSettings.shared.menuBarPets {
        case .off: return
        case .working: guard working else { return }
        case .always: break
        }
        for screen in NSScreen.screens {
            var h = screen.frame.maxY - screen.visibleFrame.maxY   // menu-bar height
            if h <= 1 { h = max(24, screen.safeAreaInsets.top) }    // auto-hidden bar
            let rect = NSRect(x: screen.frame.minX, y: screen.frame.maxY - h,
                              width: screen.frame.width, height: h)
            panels.append(makePanel(rect: rect, barHeight: h))
        }
    }

    private func makePanel(rect: NSRect, barHeight: CGFloat) -> NSPanel {
        // Unconstrained: AppKit otherwise pushes the strip below the visible menu bar.
        let panel = UnconstrainedPanel(contentRect: rect,
                                       styleMask: [.borderless, .nonactivatingPanel],
                                       backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true          // pure decoration, clicks fall through
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                    .fullScreenAuxiliary, .ignoresCycle]
        panel.level = .statusBar

        let px: CGFloat = barHeight >= 30 ? 3 : 2   // tall notch bar vs standard bar
        let host = NSHostingView(rootView: MenuBarPetsStrip(px: px))
        host.frame = NSRect(origin: .zero, size: rect.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.setFrame(rect, display: true)
        panel.orderFrontRegardless()
        if let n = notchWindowNumber { panel.order(.below, relativeTo: n) }
        return panel
    }
}

private struct MenuBarPetsStrip: View {
    let px: CGFloat
    var body: some View {
        PixelPetsField(pets: PixelPet.menuTroupe(px: px), baseline: 2, spread: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
