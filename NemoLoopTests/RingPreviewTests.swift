import Testing
import CoreGraphics
import Foundation
@testable import NemoLoop

/// Settings-inspector preview mode: `isSettingsPreview` turns the ring into a
/// purely driven puppet — global input sampling (`sample()`, and with it
/// `NSEvent.mouseLocation` / stick polling) is inert, while explicit
/// `updatePointer` calls remain the sole input path. The real ring (default
/// false) must keep sampling with zero behavior change.
@MainActor
struct RingPreviewTests {
    /// Straight-up stick vector: angle 0° = blade 0, far past the dead zone.
    /// Sampling it MUST highlight blade 0 — exactly what preview mode suppresses.
    private static let selectingStick = CGPoint(x: 0, y: 500)

    @Test func previewSampleIsInertWhileRealRingStillSamples() {
        // Preview mode: sampling is disabled — with no explicit feed nothing is
        // selected, even though the input would highlight blade 0 if sampled.
        let vm = RingViewModel()
        vm.isSettingsPreview = true
        vm.begin(centerGlobal: .zero, wedgeCount: 6,
                 input: .vector(deadZone: 36, provider: { Self.selectingStick }))
        defer { vm.end() }
        vm.sample()
        #expect(vm.selection == nil)

        // Explicit updatePointer still drives selection in preview mode (the
        // settings inspector's only input path). y:80 sits between the dead zone
        // (36) and the blade rim (130) at 12 o'clock, so it lands on blade 0.
        vm.updatePointer(at: CGPoint(x: 0, y: 80), now: Date())
        #expect(vm.selection == RingSelection(index: 0, subIndex: nil))

        // The real ring (default false) samples the same input unchanged —
        // proves the flag, not the input, is what silenced sampling.
        let real = RingViewModel()
        real.begin(centerGlobal: .zero, wedgeCount: 6,
                   input: .vector(deadZone: 36, provider: { Self.selectingStick }))
        defer { real.end() }
        real.sample()
        #expect(real.selection == RingSelection(index: 0, subIndex: nil))
    }
}
