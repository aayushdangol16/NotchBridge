import SwiftUI

/// The island silhouette: concave "ears" where it meets the top of the screen (so it reads as part of
/// the hardware notch) and rounded bottom corners. Both radii animate, so the shape morphs smoothly
/// between the closed notch, the compact peek and the open card.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        let t = max(0, min(topRadius, r.width / 4, r.height / 2))
        let b = max(0, min(bottomRadius, r.height - t, (r.width - 2 * t) / 2))
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        // left ear (concave)
        p.addQuadCurve(to: CGPoint(x: r.minX + t, y: r.minY + t), control: CGPoint(x: r.minX + t, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + t, y: r.maxY - b))
        // bottom-left corner
        p.addArc(tangent1End: CGPoint(x: r.minX + t, y: r.maxY), tangent2End: CGPoint(x: r.minX + t + b, y: r.maxY), radius: b)
        p.addLine(to: CGPoint(x: r.maxX - t - b, y: r.maxY))
        // bottom-right corner
        p.addArc(tangent1End: CGPoint(x: r.maxX - t, y: r.maxY), tangent2End: CGPoint(x: r.maxX - t, y: r.maxY - b), radius: b)
        p.addLine(to: CGPoint(x: r.maxX - t, y: r.minY + t))
        // right ear (concave)
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - t, y: r.minY))
        p.closeSubpath()
        return p
    }
}
