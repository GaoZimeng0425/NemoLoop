import Testing
import CoreGraphics
import Foundation
@testable import NemoLoop

struct RingGeometryTests {
    let center = CGPoint(x: 100, y: 100)
    let dz: CGFloat = 20

    // from-up convention: 0° = up, clockwise positive, around (100, 100).
    private func point(atDegrees deg: Double, radius: CGFloat = 100) -> CGPoint {
        CGPoint(x: 100 + radius * sin(deg * Double.pi / 180),
                y: 100 + radius * cos(deg * Double.pi / 180))
    }

    @Test func deadZoneReturnsNil() {
        #expect(RingGeometry.wedgeIndex(from: center, to: center, deadZoneRadius: dz) == nil)
        #expect(RingGeometry.wedgeIndex(from: center, to: CGPoint(x: 110, y: 105), deadZoneRadius: dz) == nil)
    }

    @Test func arcLayoutMatchesTheme() {
        // Gap centered at -45° (10:30), 60° wide → arc starts at -15°, spans 300°.
        #expect(abs(RingGeometry.arcStart - RingTheme.arcStartDegrees * .pi / 180) < 0.000001)
        #expect(abs(RingGeometry.arcSpan - RingTheme.arcSpanDegrees * .pi / 180) < 0.000001)
        #expect(abs(RingTheme.arcStartDegrees - (-15)) < 0.001)
        #expect(abs(RingTheme.arcSpanDegrees - 300) < 0.001)
    }

    @Test func straightUpIsWedgeZero() {
        // +Y is up in AppKit global coords
        #expect(RingGeometry.wedgeIndex(from: center, to: CGPoint(x: 100, y: 200), deadZoneRadius: dz) == 0)
    }

    @Test func clockwiseSectors() {
        // 6 wedges over the 300° arc → 50° each; wedge 0 starts at −15°.
        // upper-right (~60° clockwise from up)
        #expect(RingGeometry.wedgeIndex(from: center, to: CGPoint(x: 187, y: 150), deadZoneRadius: dz) == 1)
        // straight down
        #expect(RingGeometry.wedgeIndex(from: center, to: CGPoint(x: 100, y: 0), deadZoneRadius: dz) == 3)
        // just counterclockwise of the gap's lower edge → last wedge
        #expect(RingGeometry.wedgeIndex(from: center, to: point(atDegrees: -76), deadZoneRadius: dz) == 5)
    }

    @Test func gapReturnsNil() {
        // The fixed gap spans [−75°, −15°); any pointer there selects nothing.
        #expect(RingGeometry.wedgeIndex(from: center, to: point(atDegrees: -45), deadZoneRadius: dz) == nil)
        #expect(RingGeometry.wedgeIndex(from: center, to: point(atDegrees: -74), deadZoneRadius: dz) == nil)
        #expect(RingGeometry.wedgeIndex(from: center, to: point(atDegrees: -16), deadZoneRadius: dz) == nil)
        // upper-left (~−60°) used to be wedge 5; it is now inside the gap.
        #expect(RingGeometry.wedgeIndex(from: center, to: CGPoint(x: 13, y: 150), deadZoneRadius: dz) == nil)
    }

    @Test func boundaryBetweenWedgeZeroAndOne() {
        // Wedge 0/1 boundary sits at −15° + 50° = 35°.
        #expect(RingGeometry.wedgeIndex(from: center, to: point(atDegrees: 34), deadZoneRadius: dz) == 0)
        #expect(RingGeometry.wedgeIndex(from: center, to: point(atDegrees: 36), deadZoneRadius: dz) == 1)
    }

    @Test func dynamicWedgeCountSpansArc() {
        // 3 wedges over the 300° arc → 100° each: [−15, 85), [85, 185), [185, 285).
        #expect(RingGeometry.wedgeIndex(from: center, to: point(atDegrees: 0), wedgeCount: 3, deadZoneRadius: dz) == 0)
        #expect(RingGeometry.wedgeIndex(from: center, to: point(atDegrees: 100), wedgeCount: 3, deadZoneRadius: dz) == 1)
        #expect(RingGeometry.wedgeIndex(from: center, to: point(atDegrees: 200), wedgeCount: 3, deadZoneRadius: dz) == 2)
        #expect(RingGeometry.wedgeIndex(from: center, to: point(atDegrees: -45), wedgeCount: 3, deadZoneRadius: dz) == nil)
    }

    @Test func singleWedgeCoversWholeArc() {
        #expect(RingGeometry.wedgeIndex(from: center, to: point(atDegrees: 180), wedgeCount: 1, deadZoneRadius: dz) == 0)
        #expect(RingGeometry.wedgeIndex(from: center, to: point(atDegrees: -45), wedgeCount: 1, deadZoneRadius: dz) == nil)
    }
}
