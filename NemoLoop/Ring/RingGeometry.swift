import CoreGraphics
import Foundation

/// Angular layout of the blade fan — the single source of truth shared by rendering
/// (`RingView`) and hit testing (`RingGeometry.wedgeIndex`).
///
/// Every blade is a fixed `bladeDegrees` sector. Up to 11 blades sit edge-to-edge
/// (pitch == width), tiling at most `11 × 30° = 330°` so the wrap gap never shrinks
/// below `arcGapDegrees`; beyond 11 the pitch compresses and blades overlap. The fan
/// is centered on up, so the wrap gap sits centered on down.
struct BladeLayout: Equatable {
    let count: Int
    /// Blade angular width, degrees (fixed, from `RingTheme.bladeDegrees`).
    let bladeWidth: Double
    /// Angle between neighbouring blade centers, degrees (≤ bladeWidth).
    let pitch: Double

    /// From-up angle of blade 0's leading (counterclockwise) edge; the fan is
    /// centered on up, so the wrap gap is centered on down.
    var start: Double { -span / 2 }
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
