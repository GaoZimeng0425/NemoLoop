import Testing
import CoreGraphics
import Foundation
@testable import NemoLoop

/// Sub-wheel hit testing: subs tile the parent sector's full angular width
/// across the outer band ([midRadius, outerRadius]), sub 0 counterclockwise-most
/// — the same mapping subBladeView renders, so hit regions match the draw.
struct RingSubWheelGeometryTests {
    let center = CGPoint(x: 100, y: 100)
    let layout = BladeLayout.forCount(6)
    let inner = RingTheme.subBandInner
    let outer = RingTheme.subBandOuter

    private func subPoint(parent: Int, sub: Int, childCount: Int, radius: CGFloat,
                          angleOffset: Double = 0) -> CGPoint {
        let half = layout.bladeWidth / 2
        let subWidth = 2 * half / Double(childCount)
        let angle = layout.centerAngle(parent) - half + (Double(sub) + 0.5) * subWidth + angleOffset
        let t = angle * Double.pi / 180
        return CGPoint(x: center.x + radius * sin(t), y: center.y + radius * cos(t))
    }

    @Test func subCentersHitTheirOwnSub() {
        // parent 0 (center 0°), 3 children → sub centers at −10°, 0°, +10°.
        for sub in 0..<3 {
            let p = subPoint(parent: 0, sub: sub, childCount: 3, radius: 110)
            #expect(RingGeometry.subIndex(parent: 0,
                                          angle: RingGeometry.angle(from: center, to: p),
                                          distance: 110,
                                          layout: layout, childCount: 3,
                                          innerRadius: inner, outerRadius: outer) == sub)
        }
    }

    @Test func subSeamsSplitEvenly() {
        // Boundary between sub 0 and sub 1 of a 2-child wheel: −7.5° for parent 0.
        let inside = subPoint(parent: 0, sub: 1, childCount: 2, radius: 110, angleOffset: -0.1)
        #expect(RingGeometry.subIndex(parent: 0,
                                      angle: RingGeometry.angle(from: center, to: inside),
                                      distance: 110, layout: layout, childCount: 2,
                                      innerRadius: inner, outerRadius: outer) == 1)
    }

    @Test func radialBounds() {
        let p = subPoint(parent: 0, sub: 0, childCount: 3, radius: 110)
        let angle = RingGeometry.angle(from: center, to: p)
        // Inside the inner radius (the parent's band) and past the outer edge: no sub.
        #expect(RingGeometry.subIndex(parent: 0, angle: angle, distance: inner - 1,
                                      layout: layout, childCount: 3,
                                      innerRadius: inner, outerRadius: outer) == nil)
        #expect(RingGeometry.subIndex(parent: 0, angle: angle, distance: outer + 1,
                                      layout: layout, childCount: 3,
                                      innerRadius: inner, outerRadius: outer) == nil)
    }

    @Test func outsideTheParentSector() {
        // Parent 0 spans −15°…+15°; 30° away (parent 1's center) is no sub of parent 0.
        #expect(RingGeometry.subIndex(parent: 0, angle: 30, distance: 110,
                                      layout: layout, childCount: 3,
                                      innerRadius: inner, outerRadius: outer) == nil)
    }

    @Test func lastParentWrapsCleanly() {
        // Parent 5 centers at 150° — deltas past 180° must measure from 150°, not wrap.
        let p = subPoint(parent: 5, sub: 2, childCount: 4, radius: 110)
        #expect(RingGeometry.subIndex(parent: 5,
                                      angle: RingGeometry.angle(from: center, to: p),
                                      distance: 110, layout: layout, childCount: 4,
                                      innerRadius: inner, outerRadius: outer) == 2)
    }

    @Test func noChildrenMeansNoSub() {
        #expect(RingGeometry.subIndex(parent: 0, angle: 0, distance: 110,
                                      layout: layout, childCount: 0,
                                      innerRadius: inner, outerRadius: outer) == nil)
    }
}

/// Dwell-driven sub-wheel state machine: dwelling `subDwellDuration` on a blade
/// with children deals them out; leaving for another blade (or cancelling)
/// sweeps them away; hover inside the open band selects a sub.
@MainActor
struct RingSubWheelViewModelTests {
    let center = CGPoint(x: 500, y: 500)
    let layout = BladeLayout.forCount(6)

    private func makeViewModel(children: [Int]) -> (RingViewModel, Date) {
        let vm = RingViewModel()
        var clock = Date(timeIntervalSince1970: 1_000)
        vm.now = { clock }
        vm.begin(centerGlobal: center, wedgeCount: 6, childrenCounts: children, input: .pointer)
        return (vm, clock)
    }

    private func point(atDegrees deg: Double, radius: CGFloat) -> CGPoint {
        CGPoint(x: center.x + radius * sin(deg * Double.pi / 180),
                y: center.y + radius * cos(deg * Double.pi / 180))
    }

    private func subAngle(parent: Int, sub: Int, childCount: Int) -> Double {
        let half = layout.bladeWidth / 2
        let subWidth = 2 * half / Double(childCount)
        return layout.centerAngle(parent) - half + (Double(sub) + 0.5) * subWidth
    }

    @Test func dwellOpensTheWheel() {
        let (vm, start) = makeViewModel(children: [3, 0, 0, 0, 0, 0])
        defer { vm.end() }
        let mid = RingTheme.midRadius
        vm.updatePointer(at: point(atDegrees: 0, radius: 70), now: start)
        #expect(vm.openSubIndex == nil)   // dwelling, not yet open
        vm.updatePointer(at: point(atDegrees: 0, radius: 70), now: start.addingTimeInterval(0.1))
        #expect(vm.openSubIndex == nil)
        vm.updatePointer(at: point(atDegrees: 0, radius: 70), now: start.addingTimeInterval(0.26))
        #expect(vm.openSubIndex == 0)
    }

    @Test func bladesWithoutChildrenNeverOpen() {
        let (vm, start) = makeViewModel(children: [0, 0, 0, 0, 0, 0])
        defer { vm.end() }
        vm.updatePointer(at: point(atDegrees: 0, radius: 70), now: start)
        vm.updatePointer(at: point(atDegrees: 0, radius: 70), now: start.addingTimeInterval(2))
        #expect(vm.openSubIndex == nil)
    }

    @Test func dwellRestartsAfterSwitchingBlades() {
        let (vm, start) = makeViewModel(children: [0, 3, 0, 0, 0, 0])
        defer { vm.end() }
        vm.updatePointer(at: point(atDegrees: 0, radius: 70), now: start)
        vm.updatePointer(at: point(atDegrees: 30, radius: 70), now: start.addingTimeInterval(0.2))
        // Fresh anchor on blade 1: 0.1s later the wheel is still closed.
        vm.updatePointer(at: point(atDegrees: 30, radius: 70), now: start.addingTimeInterval(0.3))
        #expect(vm.openSubIndex == nil)
        vm.updatePointer(at: point(atDegrees: 30, radius: 70), now: start.addingTimeInterval(0.51))
        #expect(vm.openSubIndex == 1)
    }

    @Test func subHoverSelectsInTheOuterBand() {
        let (vm, start) = makeViewModel(children: [3, 0, 0, 0, 0, 0])
        defer { vm.end() }
        vm.updatePointer(at: point(atDegrees: 0, radius: 70), now: start)
        vm.updatePointer(at: point(atDegrees: 0, radius: 70), now: start.addingTimeInterval(0.3))
        #expect(vm.openSubIndex == 0)
        // Sub 2 of 3: +10° from the parent's center, at the sub band's mid radius.
        let angle = subAngle(parent: 0, sub: 2, childCount: 3)
        vm.updatePointer(at: point(atDegrees: angle, radius: 110),
                         now: start.addingTimeInterval(0.4))
        #expect(vm.highlightedIndex == 0)   // parent stays highlighted
        #expect(vm.hoveredSubIndex == 2)
        #expect(vm.selection == RingSelection(index: 0, subIndex: 2))
    }

    @Test func innerBandKeepsParentSelection() {
        let (vm, start) = makeViewModel(children: [2, 0, 0, 0, 0, 0])
        defer { vm.end() }
        vm.updatePointer(at: point(atDegrees: 0, radius: 70), now: start)
        vm.updatePointer(at: point(atDegrees: 0, radius: 70), now: start.addingTimeInterval(0.3))
        // Drop back into the parent's own band (radius < midRadius): parent selected.
        vm.updatePointer(at: point(atDegrees: 0, radius: 70), now: start.addingTimeInterval(0.4))
        #expect(vm.openSubIndex == 0)     // wheel stays open
        #expect(vm.hoveredSubIndex == nil)
        #expect(vm.selection == RingSelection(index: 0, subIndex: nil))
    }

    @Test func leavingForAnotherBladeClosesTheWheel() {
        let (vm, start) = makeViewModel(children: [3, 0, 0, 0, 0, 0])
        defer { vm.end() }
        vm.updatePointer(at: point(atDegrees: 0, radius: 70), now: start)
        vm.updatePointer(at: point(atDegrees: 0, radius: 70), now: start.addingTimeInterval(0.3))
        #expect(vm.openSubIndex == 0)
        vm.updatePointer(at: point(atDegrees: 90, radius: 70), now: start.addingTimeInterval(0.4))
        #expect(vm.openSubIndex == nil)
        #expect(vm.hoveredSubIndex == nil)
    }

    @Test func cancelSweepsTheWheelAway() {
        let (vm, start) = makeViewModel(children: [3, 0, 0, 0, 0, 0])
        defer { vm.end() }
        vm.updatePointer(at: point(atDegrees: 0, radius: 70), now: start)
        vm.updatePointer(at: point(atDegrees: 0, radius: 70), now: start.addingTimeInterval(0.3))
        #expect(vm.openSubIndex == 0)
        vm.updatePointer(at: point(atDegrees: 0, radius: RingTheme.cancelRadius + 40),
                         now: start.addingTimeInterval(0.4))
        #expect(vm.isCancelling)
        #expect(vm.openSubIndex == nil)
        #expect(vm.selection == nil)
    }

    @Test func beginResetsTheWheel() {
        let (vm, start) = makeViewModel(children: [3, 0, 0, 0, 0, 0])
        defer { vm.end() }
        vm.updatePointer(at: point(atDegrees: 0, radius: 70), now: start)
        vm.updatePointer(at: point(atDegrees: 0, radius: 70), now: start.addingTimeInterval(0.3))
        #expect(vm.openSubIndex == 0)
        vm.begin(centerGlobal: center, wedgeCount: 6, childrenCounts: [3, 0, 0, 0, 0, 0], input: .pointer)
        #expect(vm.openSubIndex == nil)
        #expect(vm.hoveredSubIndex == nil)
    }
}
