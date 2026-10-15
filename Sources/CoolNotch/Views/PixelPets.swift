import SwiftUI

/// A pixel-art critter with a 2-frame walk cycle. Sprites are plain strings — each
/// character maps to a palette color; space/`.` is transparent. Drawn with `Canvas`
/// (filled rects per pixel) so it's cheap and keeps ticking in the non-key panel.
struct PixelPet {
    let frames: [[String]]              // walk frames, each a list of equal-width rows
    let palette: [Character: Color]
    var px: CGFloat = 3                 // pixel size
    var speed: Double = 26              // points/second
    var facingLeft: Bool = false
    var bob: Bool = false               // little vertical hop while walking
}

extension PixelPet {
    private static let outline = Color(white: 0.08)

    /// Orange tabby.
    static let cat = PixelPet(
        frames: [[
            "  k      k  ",
            " kOk    kOk ",
            " kOOOOOOOOk ",
            "kOwOOOOOOwOk",
            "kOOOOOOOOOOk",
            "kOOOOOOOOOOk",
            " kOOOOOOOOk ",
            " k k    k k ",
        ], [
            "  k      k  ",
            " kOk    kOk ",
            " kOOOOOOOOk ",
            "kOwOOOOOOwOk",
            "kOOOOOOOOOOk",
            "kOOOOOOOOOOk",
            " kOOOOOOOOk ",
            "  kk    kk  ",
        ]],
        palette: ["k": outline, "O": Color(red: 1.0, green: 0.58, blue: 0.23),
                  "w": Color(white: 0.98)])

    /// Claude — a friendly rust-orange blob with a smile.
    static let claude = PixelPet(
        frames: [[
            "   kkkkkk   ",
            "  kRRRRRRk  ",
            " kRRRRRRRRk ",
            "kRRwRRRRwRRk",
            "kRRRRRRRRRRk",
            "kRRRkkkkRRRk",
            "kRRRRRRRRRRk",
            "  kk    kk  ",
        ], [
            "   kkkkkk   ",
            "  kRRRRRRk  ",
            " kRRRRRRRRk ",
            "kRRwRRRRwRRk",
            "kRRRRRRRRRRk",
            "kRRRkkkkRRRk",
            "kRRRRRRRRRRk",
            " k k    k k ",
        ]],
        palette: ["k": outline, "R": Color(red: 0.85, green: 0.46, blue: 0.34),
                  "w": Color(white: 0.98)],
        bob: true)

    /// A little agent robot.
    static let robot = PixelPet(
        frames: [[
            "  k      k  ",
            "  kGGGGGGk  ",
            " kGGGGGGGGk ",
            "kGcGGGGGGcGk",
            "kGGGGGGGGGGk",
            "kGGGkkkkGGGk",
            "kGGGGGGGGGGk",
            " k k    k k ",
        ], [
            "  k      k  ",
            "  kGGGGGGk  ",
            " kGGGGGGGGk ",
            "kGcGGGGGGcGk",
            "kGGGGGGGGGGk",
            "kGGGkkkkGGGk",
            "kGGGGGGGGGGk",
            "  kk    kk  ",
        ]],
        palette: ["k": outline, "G": Color(red: 0.62, green: 0.64, blue: 0.70),
                  "c": Color(red: 0.30, green: 0.85, blue: 0.90)])

    /// A mixed troupe walking in both directions at varied speeds — sized for the panel.
    static var troupe: [PixelPet] {
        var claudeL = claude; claudeL.facingLeft = true; claudeL.speed = 22; claudeL.px = 4
        var robotR = robot;   robotR.speed = 32;   robotR.px = 4
        var catR = cat;       catR.speed = 27;     catR.px = 4
        return [catR, claudeL, robotR]
    }

    /// The troupe sized for the macOS menu bar — slower, ambient, tiny.
    static func menuTroupe(px: CGFloat) -> [PixelPet] {
        var catR = cat;       catR.px = px;    catR.speed = 21
        var claudeL = claude; claudeL.px = px; claudeL.speed = 13; claudeL.facingLeft = true
        var robotR = robot;   robotR.px = px;  robotR.speed = 29
        return [catR, claudeL, robotR]
    }
}

/// A troupe of pixel pets strolling along the bottom of whatever it fills. Used as an
/// ambient background while Claude is working. Deterministic motion (no stored state).
struct PixelPetsField: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var pets: [PixelPet]
    var baseline: CGFloat = 6           // gap from the bottom edge
    var spread: Bool = false            // space pets evenly across the width (menu bar)

    var body: some View {
        TimelineView(.periodic(from: .now, by: reduceMotion ? 0.5 : 0.08)) { ctx in
            Canvas { gc, size in
                let t = reduceMotion ? 0 : ctx.date.timeIntervalSinceReferenceDate
                for (i, pet) in pets.enumerated() {
                    let frameIdx = reduceMotion ? 0 : Int(t * 7 + Double(i)) % pet.frames.count
                    let rows = pet.frames[frameIdx]
                    let cols = rows.first?.count ?? 0
                    let spriteW = CGFloat(cols) * pet.px
                    let spriteH = CGFloat(rows.count) * pet.px
                    let period = Double(size.width + spriteW)
                    let offset = spread ? Double(i) * period / Double(max(1, pets.count))
                                        : Double(i) * 97
                    let travel = (t * pet.speed + offset).truncatingRemainder(dividingBy: period)
                    let x = pet.facingLeft ? size.width - travel : travel - spriteW
                    let hop = (pet.bob && !reduceMotion) ? abs(sin(t * 6 + Double(i))) * pet.px : 0
                    let y = size.height - spriteH - baseline - hop
                    draw(rows, palette: pet.palette, px: pet.px, flip: pet.facingLeft,
                         cols: cols, origin: CGPoint(x: x, y: y), gc: gc)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func draw(_ rows: [String], palette: [Character: Color], px: CGFloat,
                      flip: Bool, cols: Int, origin: CGPoint, gc: GraphicsContext) {
        for (ry, row) in rows.enumerated() {
            for (cx, ch) in row.enumerated() {
                guard let color = palette[ch] else { continue }   // space = transparent
                let col = flip ? cols - 1 - cx : cx
                let rect = CGRect(x: origin.x + CGFloat(col) * px,
                                  y: origin.y + CGFloat(ry) * px,
                                  width: px, height: px)
                gc.fill(Path(rect), with: .color(color))
            }
        }
    }
}

/// Collapsed-notch "working" activity — pixel pets padding across each shoulder,
/// split around the camera. No sparkle icon; the pet art is the indicator.
struct NotchPetsActivity: View {
    let notchWidth: CGFloat
    var body: some View {
        HStack(spacing: 0) {
            PixelPetsField(pets: [robot], baseline: 3)
                .frame(maxWidth: .infinity)
                .padding(.trailing, 6)
            Color.clear.frame(width: notchWidth)   // notch gap
            PixelPetsField(pets: [cat], baseline: 3)
                .frame(maxWidth: .infinity)
                .padding(.leading, 6)
        }
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity)
    }
    // Sized to fit the short menu-bar strip.
    private var robot: PixelPet { var p = PixelPet.robot; p.px = 3; p.speed = 22; return p }
    private var cat: PixelPet { var p = PixelPet.cat; p.px = 3; p.speed = 26; return p }
}

/// A single still pixel sprite (first frame), sized exactly to its pixels — used as
/// an inline glyph (composer, collapsed activity) instead of a generic SF Symbol.
struct PixelSprite: View {
    let pet: PixelPet
    var px: CGFloat = 2

    var body: some View {
        let rows = pet.frames.first ?? []
        let cols = rows.first?.count ?? 0
        Canvas { gc, _ in
            for (ry, row) in rows.enumerated() {
                for (cx, ch) in row.enumerated() {
                    guard let color = pet.palette[ch] else { continue }
                    gc.fill(Path(CGRect(x: CGFloat(cx) * px, y: CGFloat(ry) * px, width: px, height: px)),
                            with: .color(color))
                }
            }
        }
        .frame(width: CGFloat(cols) * px, height: CGFloat(rows.count) * px)
        .accessibilityHidden(true)
    }
}
