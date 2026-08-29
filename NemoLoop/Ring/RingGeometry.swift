import CoreGraphics
import Foundation

enum RingGeometry {
    /// The open arc the wedges share (from-up convention: 0 = +Y, clockwise positive).
    /// `arcStart` is the a0-side ray of wedge 0; the angular range outside
    /// [arcStart, arcStart + arcSpan) is the fixed gap at 10:30.
    static var arcStart: Double { RingTheme.arcStartDegrees * .pi / 180 }
    static var arcSpan: Double { RingTheme.arcSpanDegrees * .pi / 180 }

    /// Maps the vector from `center` to `point` onto a wedge index.
    /// Index 0 starts at `arcStart`; indices increase clockwise along the arc.
    /// Returns nil when within `deadZoneRadius` or when the pointer sits in the gap.
    static func wedgeIndex(
        from center: CGPoint,
        to point: CGPoint,
        wedgeCount: Int = 6,
        deadZoneRadius: CGFloat
    ) -> Int? {
        let dx = point.x - center.x
        let dy = point.y - center.y
        if (dx * dx + dy * dy) < (deadZoneRadius * deadZoneRadius) { return nil }

        // atan2(dx, dy): 0 at +Y (up), increasing toward +X (right) = clockwise.
        let twoPi = 2 * Double.pi
        let angle = atan2(Double(dx), Double(dy))
        let normalized = (angle.truncatingRemainder(dividingBy: twoPi) + twoPi)
            .truncatingRemainder(dividingBy: twoPi)
        let rel = ((normalized - arcStart).truncatingRemainder(dividingBy: twoPi) + twoPi)
            .truncatingRemainder(dividingBy: twoPi)

        guard rel < arcSpan else { return nil }   // pointer in the gap: no selection
        let sliceAngle = arcSpan / Double(wedgeCount)
        return min(Int(rel / sliceAngle), wedgeCount - 1)
    }
}
