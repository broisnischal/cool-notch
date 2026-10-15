import AppKit

/// Everything about where the notch is and how big our surfaces are.
/// Window coordinates are top-left origin (the container view is flipped).
struct NotchGeometry: Equatable {
    var screenFrame: CGRect
    var hasNotch: Bool
    var notchWidth: CGFloat      // width of the physical notch (0 if none)
    var notchHeight: CGFloat     // menu-bar strip height at the notch

    var collapsedSize: CGSize    // the idle black surface (fuses with the notch)
    var triggerSize: CGSize      // hover target — the physical notch
    var pillSize: CGSize         // Dynamic-Island notification pill
    var mediaSize: CGSize        // now-playing / working live activity (compact)
    var hudSize: CGSize          // volume HUD (room for a level bar)
    var panelSize: CGSize        // the expanded surface
    var windowSize: CGSize       // the borderless window (panel + shadow room)

    /// Centered inset of a surface of `width` inside the window.
    func centeredX(_ width: CGFloat, windowWidth: CGFloat) -> CGFloat {
        (windowWidth - width) / 2
    }

    static func detect(for screen: NSScreen) -> NotchGeometry {
        let frame = screen.frame
        let insetTop = screen.safeAreaInsets.top
        let left  = screen.auxiliaryTopLeftArea?.width ?? 0
        let right = screen.auxiliaryTopRightArea?.width ?? 0
        let physicalNotch = (left > 0 && right > 0) ? max(0, frame.width - left - right) : 0
        let hasNotch = insetTop > 0 && physicalNotch > 0

        let notchH = hasNotch ? insetTop : 34
        let notchW = hasNotch ? physicalNotch : 0

        // Idle surface = exactly the notch, so it's invisible against the hardware.
        let collapsed = hasNotch ? CGSize(width: notchW, height: notchH)
                                 : CGSize(width: 180, height: 32)
        // Hover target = exactly the physical notch, so it opens only when the cursor
        // is genuinely over the notch — not a wider strip of the menu bar.
        let trigger = hasNotch ? CGSize(width: notchW, height: notchH)
                               : CGSize(width: 160, height: 28)

        let base = notchW == 0 ? 150 : notchW
        // EVERY collapsed state stays exactly menu-bar height — activities widen the
        // notch, never deepen it (a height bounce reads as the notch "breaking").
        let pill = CGSize(width: min(620, base + 300), height: notchH)
        // Compact: one 20pt glyph centred in each 40pt shoulder — no empty wings.
        let media = CGSize(width: base + 80, height: notchH)
        let hud = CGSize(width: base + 150, height: notchH)
        // Tabs live in the notch shoulders: five per side, plus outer padding and
        // camera clearance. Height then goes entirely to content.
        let shoulder = 5 * 26 + 4 * 3 + 14 + 12          // tabs + gaps + edge + clearance
        let panel = CGSize(width: max(520, notchW + 2 * CGFloat(shoulder)), height: 344)
        // Room for the top ears (NotchShape.topFlare, max 10pt per side).
        let window = CGSize(width: panel.width + 24, height: panel.height + 8)

        return NotchGeometry(
            screenFrame: frame,
            hasNotch: hasNotch,
            notchWidth: notchW,
            notchHeight: notchH,
            collapsedSize: collapsed,
            triggerSize: trigger,
            pillSize: pill,
            mediaSize: media,
            hudSize: hud,
            panelSize: panel,
            windowSize: window
        )
    }
}
