import SwiftUI

/// The morphing silhouette: flush square top with concave "ears" where it meets
/// the menu bar, and rounded bottom corners — the same anatomy as the hardware
/// notch. Both the bottom radius and the ear size animate, so as the surface
/// grows the ears widen with it and it reads as the notch itself stretching.
struct NotchShape: Shape, InsettableShape {
    var bottom: CGFloat
    var topFlare: CGFloat = 6
    var inset: CGFloat = 0

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(bottom, topFlare) }
        set { bottom = newValue.first; topFlare = newValue.second }
    }

    func inset(by amount: CGFloat) -> NotchShape {
        var s = self
        s.inset += amount
        return s
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        var p = Path()
        let f = topFlare
        let b = min(bottom, r.height, r.width / 2)

        // Ear: flare inward from just outside the top-left corner.
        p.move(to: CGPoint(x: r.minX - f, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.minY + f),
                       control: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - b))
        p.addQuadCurve(to: CGPoint(x: r.minX + b, y: r.maxY),
                       control: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - b, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.maxY - b),
                       control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + f))
        p.addQuadCurve(to: CGPoint(x: r.maxX + f, y: r.minY),
                       control: CGPoint(x: r.maxX, y: r.minY))
        p.closeSubpath()
        return p
    }
}
