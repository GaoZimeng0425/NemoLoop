import Testing
import CoreGraphics
@testable import NemoLoop

/// The outer-escape cancel state: past `RingTheme.cancelRadius` the pointer is
/// in "safe cancel" — no blade highlights and release commits nothing. Between
/// the blades' outer edge and the cancel radius sits a grace band where nothing
/// selects either, but the ring does not dim (avoids accidental flicks).
@MainActor
struct RingViewModelCancelTests {
    let center = CGPoint(x: 500, y: 500)

    private func makeViewModel() -> RingViewModel {
        let vm = RingViewModel()
        vm.begin(centerGlobal: center, wedgeCount: 6, input: .pointer)
        return vm
    }

    private func point(atDegrees deg: Double, radius: CGFloat) -> CGPoint {
        // Same math space as RingGeometry: 0° = +Y, clockwise toward +X.
        CGPoint(x: center.x + radius * sin(deg * Double.pi / 180),
                y: center.y + radius * cos(deg * Double.pi / 180))
    }

    @Test func insideTheBandSelectsAndIsNotCancelling() {
        let vm = makeViewModel()
        defer { vm.end() }
        vm.updatePointer(at: point(atDegrees: 0, radius: RingTheme.midRadius))
        #expect(vm.highlightedIndex == 0)
        #expect(!vm.isCancelling)
    }

    @Test func beyondOuterEdgeClearsSelectionWithoutCancelling() {
        let vm = makeViewModel()
        defer { vm.end() }
        // Grace band: just past the blades, before the cancel radius.
        let midGrace = (RingTheme.outerRadius + RingTheme.cancelRadius) / 2
        vm.updatePointer(at: point(atDegrees: 0, radius: midGrace))
        #expect(vm.highlightedIndex == nil)
        #expect(!vm.isCancelling)
    }

    @Test func beyondCancelRadiusEntersCancelState() {
        let vm = makeViewModel()
        defer { vm.end() }
        vm.updatePointer(at: point(atDegrees: 0, radius: RingTheme.cancelRadius + 40))
        #expect(vm.highlightedIndex == nil)
        #expect(vm.isCancelling)
    }

    @Test func escapingBackInsideRestoresSelection() {
        let vm = makeViewModel()
        defer { vm.end() }
        vm.updatePointer(at: point(atDegrees: 30, radius: RingTheme.cancelRadius + 40))
        #expect(vm.isCancelling)
        vm.updatePointer(at: point(atDegrees: 30, radius: RingTheme.midRadius))
        #expect(!vm.isCancelling)
        #expect(vm.highlightedIndex == 1)
    }

    @Test func beginResetsCancelState() {
        let vm = makeViewModel()
        defer { vm.end() }
        vm.updatePointer(at: point(atDegrees: 0, radius: RingTheme.cancelRadius + 40))
        #expect(vm.isCancelling)
        vm.begin(centerGlobal: center, wedgeCount: 6, input: .pointer)
        #expect(!vm.isCancelling)
        #expect(vm.highlightedIndex == nil)
    }

    @Test func vectorInputNeverCancels() {
        // A thumbstick saturates at full deflection — there is no "past the ring".
        // sample() keeps the last selection and never enters the cancel state.
        let vm = RingViewModel()
        var stick = CGPoint(x: 0, y: 500)   // far past any radius, straight up
        vm.begin(centerGlobal: .zero, wedgeCount: 6,
                 input: .vector(deadZone: 10, provider: { stick }))
        defer { vm.end() }
        vm.sample()
        #expect(vm.highlightedIndex == 0)
        #expect(!vm.isCancelling)
        stick = CGPoint(x: 0, y: 1)
        vm.sample()
        #expect(vm.highlightedIndex == 0)   // aim survives the trip back through the dead zone
    }
}
