import Testing
import CoreGraphics
import Foundation
@testable import NemoLoop

struct BladeLayoutTests {
    @Test func fixedThirtyDegreeBlades() {
        let layout = BladeLayout.forCount(6)
        #expect(layout.bladeWidth == RingTheme.bladeDegrees)
        #expect(abs(layout.pitch - 30) < 0.001)   // pitch == width: edge-to-edge tiles
        #expect(abs(layout.span - 180) < 0.001)   // 6 × 30°
    }

    @Test func fanCenteredOnUp() {
        for n in [1, 2, 6, 11] {
            let layout = BladeLayout.forCount(n)
            #expect(abs(layout.start + layout.span / 2) < 0.001)  // start = −span/2
        }
        let six = BladeLayout.forCount(6)
        #expect(abs(six.centerAngle(0) - (-75)) < 0.001)
        #expect(abs(six.centerAngle(5) - 75) < 0.001)
    }

    @Test func elevenBladesFillTheArc() {
        let eleven = BladeLayout.forCount(11)
        #expect(abs(eleven.pitch - 30) < 0.001)
        #expect(abs(eleven.span - 330) < 0.001)   // the 30° wrap gap remains
        // Beyond 11 the pitch compresses (blades overlap) to keep the 30° gap.
        let twelve = BladeLayout.forCount(12)
        #expect(twelve.bladeWidth == 30)
        #expect(twelve.pitch < 30)
        #expect(abs(twelve.span - 330) < 0.001)
    }

    @Test func indexBoundariesOnBladeEdges() {
        let layout = BladeLayout.forCount(6)
        // Hit seams are the visual seams: each blade owns [center−15°, center+15°).
        #expect(layout.index(forAngle: layout.centerAngle(0)) == 0)
        #expect(layout.index(forAngle: layout.centerAngle(0) + 14.9) == 0)
        #expect(layout.index(forAngle: layout.centerAngle(0) + 15) == 1)   // seam 0|1
        #expect(layout.index(forAngle: layout.centerAngle(3)) == 3)
        #expect(layout.index(forAngle: layout.centerAngle(5)) == 5)
        // Overlap (12 blades): the later, top-drawn blade owns the seam region.
        let twelve = BladeLayout.forCount(12)
        let seam = twelve.start + twelve.pitch     // blade 1's leading edge
        #expect(twelve.index(forAngle: seam - 0.1) == 0)
        #expect(twelve.index(forAngle: seam + 0.1) == 1)
    }

    @Test func wrapGapReturnsNil() {
        let layout = BladeLayout.forCount(6)
        // 6 blades occupy −90°…+90°; the 180° wrap gap is centered on down.
        #expect(layout.index(forAngle: 180) == nil)   // bottom, middle of the gap
        #expect(layout.index(forAngle: 95) == nil)    // just past blade 5's trailing edge
        #expect(layout.index(forAngle: 265) == nil)   // just before blade 0's leading edge
        // The boundary rays themselves still select their blade.
        #expect(layout.index(forAngle: 90) == 5)
        #expect(layout.index(forAngle: 270) == 0)
    }

    @Test func singleBlade() {
        let one = BladeLayout.forCount(1)
        #expect(abs(one.centerAngle(0)) < 0.001)
        #expect(one.index(forAngle: 0) == 0)
        #expect(one.index(forAngle: 10) == 0)
        #expect(one.index(forAngle: 20) == nil)
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

    @Test func straightUpIsTheTwoThreeSeam() {
        // 6 blades tile −90°…+90° symmetric on up: straight up is the seam between
        // blades 2 and 3; the leading ray belongs to blade 3.
        #expect(RingGeometry.wedgeIndex(from: center, to: CGPoint(x: 100, y: 200), layout: .forCount(6), deadZoneRadius: dz) == 3)
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
        let gapCenter = (layout.span + 360) / 2 + layout.start   // 180°, middle of the bottom gap
        #expect(RingGeometry.wedgeIndex(from: center, to: point(atDegrees: gapCenter), layout: layout, deadZoneRadius: dz) == nil)
    }

    @Test func dynamicCountMapsAcrossArc() {
        let layout = BladeLayout.forCount(3)
        #expect(RingGeometry.wedgeIndex(from: center, to: point(atDegrees: layout.centerAngle(0)), layout: layout, deadZoneRadius: dz) == 0)
        #expect(RingGeometry.wedgeIndex(from: center, to: point(atDegrees: layout.centerAngle(1)), layout: layout, deadZoneRadius: dz) == 1)
        #expect(RingGeometry.wedgeIndex(from: center, to: point(atDegrees: layout.centerAngle(2)), layout: layout, deadZoneRadius: dz) == 2)
    }
}
