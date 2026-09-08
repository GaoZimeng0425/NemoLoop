import CoreGraphics
import Foundation

/// Angular layout of the blade fan — the single source of truth shared by rendering
/// (`RingView`) and hit testing (`RingGeometry.wedgeIndex`).
///
/// Every blade is a fixed `bladeDegrees` sector. Up to 11 blades sit edge-to-edge
/// (pitch == width), tiling at most `11 × 30° = 330°` so the wrap gap never shrinks
/// below `arcGapDegrees`; beyond 11 the pitch compresses and blades overlap. Blade 0
/// is centered on 12 o'clock and the fan runs clockwise, leaving the wrap gap just
/// counterclockwise of blade 0 (upper-left).
struct BladeLayout: Equatable {
    let count: Int
    /// Blade angular width, degrees (fixed, from `RingTheme.bladeDegrees`).
    let bladeWidth: Double
    /// Angle between neighbouring blade centers, degrees (≤ bladeWidth).
    let pitch: Double

    /// From-up angle of blade 0's leading (counterclockwise) edge; blade 0 is
    /// centered on up (12 o'clock), so the wrap gap sits just counterclockwise of it.
    var start: Double { -bladeWidth / 2 }
    /// Total occupied arc, degrees: leading edge of blade 0 → trailing edge of blade N−1.
    var span: Double { Double(count - 1) * pitch + bladeWidth }

    /// Builds the layout for `count` blades from `RingTheme` tokens: each blade is a
    /// fixed `bladeDegrees` sector; the pitch stays at full blade width while 11
    /// blades or fewer fit inside `360° − arcGapDegrees`, then compresses (overlap).
    static func forCount(_ count: Int) -> BladeLayout {
        let count = max(1, count)
        let width = RingTheme.bladeDegrees
        let maxPitch = count > 1
            ? (360 - RingTheme.arcGapDegrees - width) / Double(count - 1)
            : 0
        return BladeLayout(count: count, bladeWidth: width, pitch: min(width, maxPitch))
    }

    /// Slot-center angle (from-up, clockwise, degrees) of blade `i`.
    func centerAngle(_ i: Int) -> Double {
        start + bladeWidth / 2 + Double(i) * pitch
    }

    /// Maps a pointer angle (from-up, clockwise, degrees in [0, 360)) onto a blade
    /// index. Boundaries fall on blade edges — the same seams the eye sees — and the
    /// later (top-drawn) blade owns an overlap, so hit regions match the render.
    /// Returns nil inside the wrap gap.
    func index(forAngle angle: Double) -> Int? {
        let rel = ((angle - start).truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        guard rel <= span else { return nil }
        guard count > 1 else { return 0 }
        return max(0, min(Int(rel / pitch), count - 1))
    }
}

enum RingGeometry {
    /// Maps the vector from `center` to `point` onto a blade index.
    /// Returns nil when within `deadZoneRadius`, past `outerRadius` (outer-escape:
    /// pointer angle alone stops owning a wedge beyond the blades — pass nil to keep
    /// the angle-only behavior saturated stick vectors need), or in the wrap gap.
    static func wedgeIndex(
        from center: CGPoint,
        to point: CGPoint,
        layout: BladeLayout,
        deadZoneRadius: CGFloat,
        outerRadius: CGFloat? = nil
    ) -> Int? {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distanceSquared = dx * dx + dy * dy
        if distanceSquared < (deadZoneRadius * deadZoneRadius) { return nil }
        if let outerRadius, distanceSquared > (outerRadius * outerRadius) { return nil }

        // atan2(dx, dy): 0 at +Y (up), increasing toward +X (right) = clockwise.
        let angle = atan2(Double(dx), Double(dy)) * 180 / .pi
        let normalized = (angle.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        return layout.index(forAngle: normalized)
    }

    /// Pointer angle (from-up, clockwise, degrees in [0, 360)) from `center` to `point`.
    static func angle(from center: CGPoint, to point: CGPoint) -> Double {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let angle = atan2(Double(dx), Double(dy)) * 180 / .pi
        return (angle.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
    }

    /// Maps the pointer onto a sub-action of `parent`'s dealt-out ring.
    /// Subs sit on their own fixed pitch (`RingTheme.subPitchDegrees`) — sub j
    /// is centered `j * pitch` clockwise of the parent's center angle, seams on
    /// the pitch grid — and occupy the outer band `[innerRadius, outerRadius]`.
    /// Returns nil outside the dealt slots' span or radial band.
    static func subIndex(
        parent: Int,
        angle: Double,
        distance: CGFloat,
        layout: BladeLayout,
        childCount: Int,
        innerRadius: CGFloat,
        outerRadius: CGFloat
    ) -> Int? {
        guard childCount > 0 else { return nil }
        guard distance >= innerRadius, distance <= outerRadius else { return nil }
        // Signed offset from the parent's center angle, wrapping at ±180 so the
        // last blades (near 165°) still measure their own grid, not the wrap.
        let center = layout.centerAngle(parent)
        let delta = ((angle - center + 180).truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360) - 180
        let slot = Int((delta / RingTheme.subPitchDegrees).rounded())
        guard slot >= 0, slot < childCount else { return nil }
        return slot
    }
}
