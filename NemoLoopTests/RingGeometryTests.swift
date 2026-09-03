import Testing
import CoreGraphics
import Foundation
@testable import NemoLoop

struct RingGeometryTests {
    let center = CGPoint(x: 100, y: 100)
    let dz: CGFloat = 20

    @Test func deadZoneReturnsNil() {
        #expect(RingGeometry.wedgeIndex(from: center, to: center, deadZoneRadius: dz) == nil)
        #expect(RingGeometry.wedgeIndex(from: center, to: CGPoint(x: 110, y: 105), deadZoneRadius: dz) == nil)
    }

    @Test func straightUpIsWedgeZero() {
        // +Y is up in AppKit global coords
        #expect(RingGeometry.wedgeIndex(from: center, to: CGPoint(x: 100, y: 200), deadZoneRadius: dz) == 0)
    }

    @Test func clockwiseSectors() {
        // upper-right (~60° clockwise from up)
        #expect(RingGeometry.wedgeIndex(from: center, to: CGPoint(x: 187, y: 150), deadZoneRadius: dz) == 1)
        // straight down
        #expect(RingGeometry.wedgeIndex(from: center, to: CGPoint(x: 100, y: 0), deadZoneRadius: dz) == 3)
        // upper-left
        #expect(RingGeometry.wedgeIndex(from: center, to: CGPoint(x: 13, y: 150), deadZoneRadius: dz) == 5)
    }

    @Test func boundaryAtThirtyDegreesGoesToWedgeOne() {
        // just clockwise of +30° boundary → wedge 1
        let p = CGPoint(x: 100 + 100 * sin(31 * Double.pi / 180), y: 100 + 100 * cos(31 * Double.pi / 180))
        #expect(RingGeometry.wedgeIndex(from: center, to: p, deadZoneRadius: dz) == 1)
    }

    @Test func dynamicWedgeCountEvenlyDividesCircle() {
        // 3 cards: 0° (up) → 0, 120° → 1, 240° → 2.
        func point(_ deg: Double) -> CGPoint {
            CGPoint(x: 100 + 100 * sin(deg * Double.pi / 180),
                    y: 100 + 100 * cos(deg * Double.pi / 180))
        }
        #expect(RingGeometry.wedgeIndex(from: center, to: point(0), wedgeCount: 3, deadZoneRadius: dz) == 0)
        #expect(RingGeometry.wedgeIndex(from: center, to: point(120), wedgeCount: 3, deadZoneRadius: dz) == 1)
        #expect(RingGeometry.wedgeIndex(from: center, to: point(240), wedgeCount: 3, deadZoneRadius: dz) == 2)
    }
}
