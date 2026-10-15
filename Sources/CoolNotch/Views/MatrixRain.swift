import SwiftUI

/// Matrix-style falling glyphs, drawn with `Canvas` so it stays cheap and keeps
/// animating even in the non-key notch panel (where `.animation`/display-link work
/// gets throttled — a periodic `TimelineView` does not).
///
/// Motion is fully deterministic: each column's phase and speed come from a cheap
/// hash of its index, so there's no per-frame state to keep. Reduced-motion collapses
/// it to a calm, near-static grid.
struct MatrixRain: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var color: Color = DS.accent
    var glyphSize: CGFloat = 11
    var speed: Double = 7          // rows/second each column's head advances
    var trail: Int = 7             // lit glyphs behind each head
    var pixelated: Bool = false    // block glyphs (pixel-art) instead of katakana

    private static let kata = Array("ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾚﾛﾜﾝ")
    private static let blocks = Array("█▓▒░▚▞▛▜▙▟▄▀◧◨")
    private var chars: [Character] { pixelated ? Self.blocks : Self.kata }

    var body: some View {
        TimelineView(.periodic(from: .now, by: reduceMotion ? 0.5 : 0.055)) { ctx in
            Canvas { gc, size in
                let colW = glyphSize * (pixelated ? 1.0 : 0.92)
                let rowH = glyphSize * (pixelated ? 1.0 : 1.12)
                let cols = max(1, Int(size.width / colW))
                let rows = max(1, Int(size.height / rowH) + 2)
                let span = rows + trail + 4
                let font = Font.system(size: glyphSize, weight: .semibold, design: .monospaced)
                let t = reduceMotion ? 0 : ctx.date.timeIntervalSinceReferenceDate

                for c in 0..<cols {
                    let h = Double((UInt64(bitPattern: Int64(c)) &* 0x9E3779B1) & 0xFFFF) / 65535.0
                    let colSpeed = speed * (0.55 + 0.9 * h)
                    let headF = t * colSpeed + h * Double(span)
                    let head = Int(headF.truncatingRemainder(dividingBy: Double(span))) - trail
                    let flick = Int((t * 9).rounded(.down))

                    for k in 0..<trail {
                        let r = head - k
                        guard r >= 0, r < rows else { continue }
                        let hash = (c &* 73856093) ^ (r &* 19349663) ^ (flick &* (k + 1))
                        let ci = ((hash % chars.count) + chars.count) % chars.count
                        let lit = 1.0 - Double(k) / Double(trail)
                        // Bright white head, accent-tinted fading tail.
                        let paint = k == 0 ? Color.white.opacity(0.92) : color.opacity(lit * 0.72)
                        let text = gc.resolve(Text(String(chars[ci])).font(font).foregroundColor(paint))
                        gc.draw(text, at: CGPoint(x: CGFloat(c) * colW + colW / 2,
                                                  y: CGFloat(r) * rowH + rowH / 2))
                    }
                }
            }
        }
    }
}

/// Full-surface matrix rain behind chat while Claude streams. Clean katakana columns
/// (never the blocky "pixelated" glyphs — those read as noise at low opacity), faded
/// at the bottom so it stays ambient.
struct MatrixField: View {
    var color: Color = Color(red: 0.30, green: 0.85, blue: 0.55)   // classic matrix green
    var opacity: Double = 0.22

    var body: some View {
        MatrixRain(color: color, glyphSize: 13, speed: 9, trail: 9)
            .opacity(opacity)
            .mask(
                LinearGradient(colors: [.black, .black, .clear],
                               startPoint: .top, endPoint: .bottom)
            )
            .allowsHitTesting(false)
    }
}

/// Collapsed-notch "Claude is working" activity — a sparkle on one shoulder and a
/// compact matrix rain on the other, split around the camera. Dynamic-Island style.
struct NotchMatrixActivity: View {
    let notchWidth: CGFloat
    var body: some View {
        HStack(spacing: 0) {
            Icon("sparkles", size: 15.6, weight: .semibold)
                .foregroundStyle(DS.accent)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 11)
            Color.clear.frame(width: notchWidth)   // notch gap
            MatrixRain(glyphSize: 8, speed: 10, trail: 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .mask(LinearGradient(colors: [.clear, .black, .black],
                                     startPoint: .leading, endPoint: .trailing))
                .padding(.leading, 8)
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
    }
}
