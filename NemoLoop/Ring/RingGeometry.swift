import CoreGraphics
import Foundation

enum RingGeometry {
    /// Maps the vector from `center` to `point` onto a card index.
    /// Index 0 is centered on +Y (up); indices increase clockwise.
    /// Returns nil when within `deadZoneRadius` (treated as "no selection").
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
        let sliceAngle = twoPi / Double(wedgeCount)
        let angle = atan2(Double(dx), Double(dy))
        let normalized = (angle.truncatingRemainder(dividingBy: twoPi) + twoPi)
            .truncatingRemainder(dividingBy: twoPi)
        // Shift by half a slice so card 0 is centered on up.
        let shifted = (normalized + sliceAngle / 2).truncatingRemainder(dividingBy: twoPi)
        return Int(shifted / sliceAngle) % wedgeCount
    }
}
