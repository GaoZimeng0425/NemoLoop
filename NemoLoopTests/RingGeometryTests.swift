import Testing
import CoreGraphics
import Foundation
@testable import NemoLoop

struct BladeLayoutTests {
    @Test func sixBladeLayoutMath() {
        let layout = BladeLayout.forCount(6)
        // Occupied arc = 360 − 30 gap = 330°; blade width = 1.35 × 55 = 74.25°.
        #expect(abs(layout.bladeWidth - 74.25) < 0.001)
        #expect(abs(layout.pitch - (330 - 74.25) / 5) < 0.001)
        // Total span from blade 0's leading edge to blade 5's trailing edge = 330°.
        #expect(abs(layout.span - 330) < 0.001)
        // All blades share one fixed size; neighbours overlap, the wrap does not.
        #expect(layout.pitch < layout.bladeWidth)
    }

    @Test func bladeZeroCenteredOnUp() {
        let layout = BladeLayout.forCount(6)
        #expect(abs(layout.centerAngle(0)) < 0.001)
        #expect(abs(layout.start - (-layout.bladeWidth / 2)) < 0.001)
    }

    @Test func indexNearestSlotCenter() {
        let layout = BladeLayout.forCount(6)
        #expect(layout.index(forAngle: 0) == 0)                 // blade 0 center
        #expect(layout.index(forAngle: layout.centerAngle(3)) == 3)
        // Halfway between blade 0 and 1 flips to the nearer center.
        #expect(layout.index(forAngle: layout.centerAngle(0) + layout.pitch / 2 - 1) == 0)
        #expect(layout.index(forAngle: layout.centerAngle(0) + layout.pitch / 2 + 1) == 1)
        // Overlap region still resolves to the nearest blade.
        #expect(layout.index(forAngle: layout.centerAngle(5) - layout.pitch / 2 - 2) == 4)
    }

    @Test func wrapGapReturnsNil() {
        let layout = BladeLayout.forCount(6)
        // Gap spans from blade 5's trailing edge (~292.9°) around to blade 0's
        // leading edge (~322.9°) — 30° total, sitting just clockwise-of-up's left.
        let gapCenter = (layout.span + 360) / 2 + layout.start   // ~307.9°, middle of the gap
        #expect(layout.index(forAngle: gapCenter) == nil)
        #expect(layout.index(forAngle: 300) == nil)              // just CW of blade 5's edge
        #expect(layout.index(forAngle: 320) == nil)              // just CCW of blade 0's edge
        // 350° looks "past" up but is inside blade 0 (leading edge ~322.9°).
        #expect(layout.index(forAngle: 350) == 0)
        // Edges of the occupied arc still select the boundary blades.
        #expect(layout.index(forAngle: 335) == 0)
        #expect(layout.index(forAngle: 292) == 5)
    }

    @Test func singleAndManyBlades() {
        let one = BladeLayout.forCount(1)
        #expect(one.index(forAngle: 0) == 0)
        #expect(one.index(forAngle: 180) == nil)

        let ten = BladeLayout.forCount(10)
        #expect(ten.index(forAngle: ten.centerAngle(7)) == 7)
        #expect(ten.index(forAngle: (ten.span + 360) / 2 + ten.start) == nil)
        // Cap keeps tiny counts sane.
        let three = BladeLayout.forCount(3)
        #expect(three.bladeWidth <= RingTheme.maxBladeDegrees)
    }
}

struct RingGeometryTests {
    let center = CGPoint(x: 100, y: 100)
    let dz: CGFloat = 20

    // from-up convention: 0° = up, clockwise positive, around (100, 100).
    private func point(atDegrees deg: Double, radius: CGFloat = 100) -> CGPoint {
        CGPoint(x: 100 + radius * sin(deg * Double.pi / 180),
                y: 100 + radius * cos(deg * Double.pi / 180))
    }

    @Test func deadZoneReturnsNil() {
        #expect(RingGeometry.wedgeIndex(from: center, to: center, layout: .forCount(6), deadZoneRadius: dz) == nil)
        #expect(RingGeometry.wedgeIndex(from: center, to: CGPoint(x: 110, y: 105), layout: .forCount(6), deadZoneRadius: dz) == nil)
    }

    @Test func straightUpIsBladeZero() {
        #expect(RingGeometry.wedgeIndex(from: center, to: CGPoint(x: 100, y: 200), layout: .forCount(6), deadZoneRadius: dz) == 0)
    }

    @Test func clockwiseBlades() {
        let layout = BladeLayout.forCount(6)
        for i in 0..<6 {
            let expected = RingGeometry.wedgeIndex(
                from: center,
                to: point(atDegrees: layout.centerAngle(i)),
                layout: layout,
                deadZoneRadius: dz)
            #expect(expected == i)
        }
    }

    @Test func gapPointReturnsNil() {
        let layout = BladeLayout.forCount(6)
        let gapCenter = (layout.span + 360) / 2 + layout.start
        #expect(RingGeometry.wedgeIndex(from: center, to: point(atDegrees: gapCenter), layout: layout, deadZoneRadius: dz) == nil)
    }

    @Test func dynamicCountMapsAcrossArc() {
        let layout = BladeLayout.forCount(3)
        #expect(RingGeometry.wedgeIndex(from: center, to: point(atDegrees: layout.centerAngle(0)), layout: layout, deadZoneRadius: dz) == 0)
        #expect(RingGeometry.wedgeIndex(from: center, to: point(atDegrees: layout.centerAngle(1)), layout: layout, deadZoneRadius: dz) == 1)
        #expect(RingGeometry.wedgeIndex(from: center, to: point(atDegrees: layout.centerAngle(2)), layout: layout, deadZoneRadius: dz) == 2)
    }
}
