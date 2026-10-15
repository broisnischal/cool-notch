import SwiftUI

/// Central design tokens.
///
/// Colors are reasoned in OKLCH (perceptually uniform) then expressed as sRGB for
/// SwiftUI. Motion is translated from Apple's `Designing Fluid Interfaces`
/// damping/response model into SwiftUI's response/dampingFraction springs.
enum DS {

    // MARK: Motion
    // One spring moves the whole surface (width, height, ears, radius together) so
    // it opens as a single shape — nothing inside moves while it grows. Open has
    // a whisper of settle; close is critically damped.
    static let expand   = Animation.spring(response: 0.36, dampingFraction: 0.88)
    static let collapse = Animation.spring(response: 0.28, dampingFraction: 1.0)
    // Hover peek: a quick, slightly springy swell of the idle notch under the cursor.
    static let peek     = Animation.spring(response: 0.22, dampingFraction: 0.68)
    static let content  = Animation.spring(response: 0.36, dampingFraction: 0.90)
    static let press    = Animation.spring(response: 0.22, dampingFraction: 0.72)
    static let hover    = Animation.easeOut(duration: 0.12)
    static let swap     = Animation.spring(duration: 0.3, bounce: 0)

    // MARK: Color
    // User-selectable accent (persisted); read synchronously so any context can use it.
    static var accent: Color { AccentPreset.current.color }
    // good    oklch(0.80 0.16 152)
    static let good        = Color(red: 0.30, green: 0.85, blue: 0.55)
    // danger  oklch(0.66 0.20 24)
    static let danger      = Color(red: 1.00, green: 0.44, blue: 0.40)
    // amber   oklch(0.82 0.13 78)
    static let amber       = Color(red: 1.00, green: 0.75, blue: 0.36)

    static let surface       = Color.black                   // fuses with the hardware notch

    // Text — slightly below full white. On the mini-LED XDR panel every bright
    // pixel lights its backlight zone and blooms into the surrounding black; less
    // luminance = less halo, so the panel reads as black as the hardware notch.
    static let textPrimary   = Color.white.opacity(0.90)
    static let textSecondary = Color.white.opacity(0.55)
    static let textTertiary  = Color.white.opacity(0.32)

    // Everything sits on PURE black: surfaces have no fill at all; a 1px outline
    // carries the structure and brightens for hover / selection. No gradients,
    // no frost, no shadows, no grey wash.
    static let cardFill      = Color.clear
    static let cardFillHover = Color.clear
    static let stroke        = Color.white.opacity(0.10)
    static let strokeHover   = Color.white.opacity(0.20)
    static let strokeActive  = Color.white.opacity(0.36)
    static let hairline      = Color.white.opacity(0.09)    // rings, dividers, drop zone

    // MARK: Radii (concentric: outer = inner + padding)
    static let panelRadius: CGFloat  = 28    // = cardRadius + panelPadding
    static let cardRadius: CGFloat   = 14    // cards and rows that sit on the panel
    static let chipRadius: CGFloat   = 8     // items inset ~6pt inside a card
    static let notchBottom: CGFloat  = 10    // idle notch bottom corners

    // MARK: Spacing / sizing
    static let panelPadding: CGFloat = 14
    static let inset: CGFloat        = 12    // content inset inside every card and row
    static let gap: CGFloat          = 8     // between peers (rows, tiles)
    static let section: CGFloat      = 16    // between groups (2× gap)
    static let rowHeight: CGFloat    = 42    // two-line list row
    static let control: CGFloat      = 28    // icon buttons
    static let tab: CGFloat          = 26    // shoulder tab button
    static let tabSpacing: CGFloat   = 3
}

extension Font {
    /// Numerals — Geist Mono, so live values keep a steady width and never jitter.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .custom(geist(weight, mono: true), fixedSize: size)
    }
    /// Interface text — Geist (bundled, OFL), registered at launch by `AppFonts`.
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .custom(geist(weight, mono: false), fixedSize: size)
    }
    private static func geist(_ w: Font.Weight, mono: Bool) -> String {
        let face: String
        switch w {
        case .bold, .heavy, .black: face = "Bold"
        case .semibold:             face = "SemiBold"
        case .medium:               face = "Medium"
        default:                    face = "Regular"
        }
        return (mono ? "GeistMono-" : "Geist-") + face
    }

    // Compact type scale used across every feed.
    static let title    = ui(13, .semibold)    // row titles, card headings
    static let body     = ui(12.5, .regular)   // inputs, content
    static let caption  = ui(11, .regular)     // secondary lines
    static let label    = ui(10, .semibold)    // section labels, badges
}
