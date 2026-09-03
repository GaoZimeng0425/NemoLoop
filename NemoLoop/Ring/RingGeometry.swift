import CoreGraphics
import Foundation

/// Angular layout of the blade fan — the single source of truth shared by rendering
/// (`RingView`) and hit testing (`RingGeometry.wedgeIndex`).
///
/// All blades have the same fixed angular width and overlap their clockwise neighbour
/// by `bladeWidth − pitch`. The fan spans less than a full circle: `span` is the arc
/// from blade 0's leading edge to blade N−1's trailing edge, and the remainder of the
/// circle is the wrap gap between the last blade and the first.
struct BladeLayout: Equatable {
    let count: Int
    /// Blade angular width, degrees.
    let bladeWidth: Double
    /// Angle between neighbouring blade centers, degrees.
    let pitch: Double

    /// From-up angle of blade 0's leading (counterclockwise) edge; blade 0 is centered
    /// on up, so the wrap gap sits just counterclockwise of it (upper-left).
    var start: Double { -bladeWidth / 2 }
    /// Total occupied arc, degrees: leading edge of blade 0 → trailing edge of blade N−1.
    var span: Double { Double(count - 1) * pitch + bladeWidth }

    /// Builds the layout for `count` blades from `RingTheme` tokens: the fan fills
    /// `360° − arcGapDegrees`, each blade is `bladeOverlapFactor` wider than its share,
    /// capped at `maxBladeDegrees`.
    static func forCount(_ count: Int) -> BladeLayout {
        let count = max(1, count)
        let occupied = 360 - RingTheme.arcGapDegrees
        let width = min(RingTheme.bladeOverlapFactor * occupied / Double(count),
                        RingTheme.maxBladeDegrees)
        let pitch = count > 1 ? (occupied - width) / Double(count - 1) : 0
        return BladeLayout(count: count, bladeWidth: width, pitch: pitch)
    }

    /// Slot-center angle (from-up, clockwise, degrees) of blade `i`.
    func centerAngle(_ i: Int) -> Double {
        start + bladeWidth / 2 + Double(i) * pitch
    }

    /// Maps a pointer angle (from-up, clockwise, degrees in [0, 360)) onto a blade
    /// index by nearest slot center; nil inside the wrap gap.
    func index(forAngle angle: Double) -> Int? {
        let rel = ((angle - start).truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        guard rel <= span else { return nil }
        guard count > 1 else { return 0 }
        let i = ((rel - bladeWidth / 2) / pitch).rounded()
        return min(max(Int(i), 0), count - 1)
    }
}

enum RingGeometry {
    /// Maps the vector from `center` to `point` onto a blade index.
    /// Returns nil when within `deadZoneRadius` or when the pointer sits in the wrap gap.
    static func wedgeIndex(
        from center: CGPoint,
        to point: CGPoint,
        layout: BladeLayout,
        deadZoneRadius: CGFloat
    ) -> Int? {
        let dx = point.x - center.x
        let dy = point.y - center.y
        if (dx * dx + dy * dy) < (deadZoneRadius * deadZoneRadius) { return nil }

        // atan2(dx, dy): 0 at +Y (up), increasing toward +X (right) = clockwise.
        let angle = atan2(Double(dx), Double(dy)) * 180 / .pi
        let normalized = (angle.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        return layout.index(forAngle: normalized)
    }
}
