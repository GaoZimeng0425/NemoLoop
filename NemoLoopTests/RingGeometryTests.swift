import Testing
import CoreGraphics
import Foundation
import SwiftUI
@testable import NemoLoop

struct BladeLayoutTests {
    @Test func fixedThirtyDegreeBlades() {
        let layout = BladeLayout.forCount(6)
        #expect(layout.bladeWidth == RingTheme.bladeDegrees)
        #expect(abs(layout.pitch - 30) < 0.001)   // pitch == width: edge-to-edge tiles
        #expect(abs(layout.span - 180) < 0.001)   // 6 × 30°
    }

    @Test func bladeZeroCenteredOnUp() {
        for n in [1, 2, 6, 11] {
            let layout = BladeLayout.forCount(n)
            #expect(abs(layout.centerAngle(0)) < 0.001)   // blade 0 at 12 o'clock
            #expect(abs(layout.start - (-layout.bladeWidth / 2)) < 0.001)
        }
        let six = BladeLayout.forCount(6)
        #expect(abs(six.centerAngle(1) - 30) < 0.001)    // 0, 30, 60, … clockwise
        #expect(abs(six.centerAngle(5) - 150) < 0.001)
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
        // 6 blades occupy −15°…+165° (blade 0 centred on up, clockwise); the 180°
        // wrap gap runs from blade 5's trailing edge around to blade 0's leading edge.
        #expect(layout.index(forAngle: 255) == nil)   // middle of the gap, lower-left
        #expect(layout.index(forAngle: 170) == nil)   // just past blade 5's trailing edge
        #expect(layout.index(forAngle: 340) == nil)   // just before blade 0's leading edge
        // The boundary rays themselves still select their blade.
        #expect(layout.index(forAngle: 165) == 5)
        #expect(layout.index(forAngle: 345) == 0)
        #expect(layout.index(forAngle: 350) == 0)     // "past" up is still blade 0
    }

    @Test func singleBlade() {
        let one = BladeLayout.forCount(1)
        #expect(abs(one.centerAngle(0)) < 0.001)
        #expect(one.index(forAngle: 0) == 0)
        #expect(one.index(forAngle: 10) == 0)
        #expect(one.index(forAngle: 20) == nil)
    }
}

/// Pins CardBladeShape's angle convention (inherited from WedgeShape) so the
/// v4–v5.2 "+90° fan vs icons" bug can never come back: `centerAngle` is a SwiftUI
/// angle (0 = +x, clockwise, y down), while RingView's slot angles are from-up-
/// clockwise and MUST be converted (−π/2).
struct CardBladeShapeTests {
    let rect = CGRect(x: 0, y: 0, width: 100, height: 100)

    private func blade(centerAngle: Double, arcCenter: CGPoint? = nil,
                       cornerRadius: CGFloat = 0) -> CardBladeShape {
        CardBladeShape(innerRadius: 10, outerRadius: 50,
                       cornerRadius: cornerRadius, centerAngle: centerAngle,
                       bladeWidth: 30 * .pi / 180, arcCenter: arcCenter)
    }

    @Test func centerAngleIsSwiftUIConvention() {
        // −π/2 = up: the blade covers points above the arc centre, not right/below.
        let p = blade(centerAngle: -.pi / 2).path(in: rect)
        #expect(p.contains(CGPoint(x: 50, y: 20)))    // up, mid-band
        #expect(!p.contains(CGPoint(x: 80, y: 50)))   // right = 90° away
        #expect(!p.contains(CGPoint(x: 50, y: 80)))   // down = 180° away
    }

    @Test func fromUpClockwiseSlotsNeedMinusHalfPi() {
        // A −75° (from-up, clockwise) slot blade covers its own ray, not straight up.
        let p = blade(centerAngle: -75 * Double.pi / 180 - Double.pi / 2).path(in: rect)
        let onRay = CGPoint(x: 50 + 40 * sin(-75 * Double.pi / 180),
                            y: 50 - 40 * cos(-75 * Double.pi / 180))
        #expect(p.contains(onRay))
        #expect(!p.contains(CGPoint(x: 50, y: 20)))
    }

    @Test func arcCenterOffsetsTheArcCentre() {
        // Local blade view: arc centre away from the rect centre keeps the band
        // where the local geometry says it is.
        let p = blade(centerAngle: -.pi / 2, arcCenter: CGPoint(x: 50, y: 80)).path(in: rect)
        #expect(p.contains(CGPoint(x: 50, y: 50)))    // 30pt above the arc centre
        #expect(!p.contains(CGPoint(x: 50, y: 20)))   // 60pt up: past the outer edge
    }

    @Test func filletsTrimCornersKeepBody() {
        // Own geometry: arcCentre (50,50), radii 40/80, 30° wide, centred up — a
        // band deep enough that the per-corner clamp (the fillet may not eat more
        // than a third of the half-width at the inner arc) leaves a real fillet.
        func card(_ cr: CGFloat) -> Path {
            CardBladeShape(innerRadius: 40, outerRadius: 80, cornerRadius: cr,
                           centerAngle: -.pi / 2, bladeWidth: 30 * .pi / 180,
                           arcCenter: CGPoint(x: 50, y: 50)).path(in: rect)
        }
        // 1.2pt inside the trailing outer corner along its interior bisector: inside
        // the sharp card, inside the region a 12pt-nominal fillet rounds away.
        let a1 = -75 * Double.pi / 180
        let corner = CGPoint(x: 50 + 80 * cos(a1), y: 50 + 80 * sin(a1))
        func unit(towards p: CGPoint) -> CGPoint {
            let d = CGPoint(x: p.x - corner.x, y: p.y - corner.y)
            let l = hypot(d.x, d.y)
            return CGPoint(x: d.x / l, y: d.y / l)
        }
        let alongEdge = unit(towards: CGPoint(x: 50 + 80 * cos(a1 - 30 * Double.pi / 180),
                                              y: 50 + 80 * sin(a1 - 30 * Double.pi / 180)))
        let inward = unit(towards: CGPoint(x: 50 + 40 * cos(a1), y: 50 + 40 * sin(a1)))
        let bis = CGPoint(x: alongEdge.x + inward.x, y: alongEdge.y + inward.y)
        let bisLen = hypot(bis.x, bis.y)
        let cutSample = CGPoint(x: corner.x + bis.x / bisLen * 1.2,
                                y: corner.y + bis.y / bisLen * 1.2)

        #expect(card(0).contains(cutSample))          // sanity: inside the sharp card
        #expect(!card(12).contains(cutSample))        // fillet trims the corner region
        #expect(card(12).contains(CGPoint(x: 50, y: -10)))   // outer band stays
        #expect(card(12).contains(CGPoint(x: 50, y: 2)))     // inner band stays
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
        // Blade 0 is centred on 12 o'clock.
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
