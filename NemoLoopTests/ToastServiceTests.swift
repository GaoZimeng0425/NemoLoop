// NemoLoopTests/ToastServiceTests.swift
import Testing
import Foundation
@testable import NemoLoop

@MainActor
struct ToastServiceTests {
    // Deterministic double: parks each sleep on a continuation (the
    // ChainExecutorTests.BlockingSleeper idiom — Task.sleep can't be observed
    // from tests). Cancellation resumes every parked continuation.
    @MainActor
    private final class ParkingSleeper: ToastSleeping {
        private(set) var slept: [TimeInterval] = []
        private(set) var cancelledCount = 0
        private var parked: [CheckedContinuation<Void, Error>] = []

        func sleep(seconds: TimeInterval) async throws {
            slept.append(seconds)
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { parked.append($0) }
            } onCancel: {
                Task { @MainActor in self.cancelAll() }
            }
        }

        private func cancelAll() {
            cancelledCount += parked.count
            parked.forEach { $0.resume(throwing: CancellationError()) }
            parked.removeAll()
        }

        var parkedCount: Int { parked.count }
        func resumeNext() {
            guard !parked.isEmpty else { return }
            parked.removeFirst().resume(returning: ())
        }
    }

    /// Dismiss transitions land on a fire-and-forget task; poll until the
    /// condition holds (or fail loud on timeout) instead of sleeping blind.
    private func eventually(_ condition: @autoclosure @escaping () -> Bool,
                            timeout: TimeInterval = 2.0) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }

    @Test func showSetsStateAndStartsVisibleTimer() async {
        let sleeper = ParkingSleeper()
        let service = ToastService(sleeper: sleeper)
        service.show(.success, "Snipped to clipboard")
        #expect(service.current == .init(kind: .success, text: "Snipped to clipboard"))
        #expect(service.visible)
        #expect(service.panelWanted)
        await eventually(sleeper.parkedCount == 1)
        #expect(sleeper.slept == [2.0])
    }

    @Test func errorToastWaitsLonger() async {
        let sleeper = ParkingSleeper()
        let service = ToastService(sleeper: sleeper)
        service.show(.error, "boom")
        await eventually(sleeper.slept == [3.5])
    }

    @Test func fadesThenClearsInTwoStages() async {
        let sleeper = ParkingSleeper()
        let service = ToastService(sleeper: sleeper)
        service.show(.info, "No text recognized")
        await eventually(sleeper.parkedCount == 1)

        sleeper.resumeNext()
        // Stage 1: view fading out, but the window must stay (animation is
        // still playing) and the message must survive until fully hidden.
        await eventually(!service.visible)
        #expect(service.panelWanted)
        #expect(service.current != nil)
        await eventually(sleeper.parkedCount == 1)
        #expect(sleeper.slept == [2.0, 0.25])

        sleeper.resumeNext()
        await eventually(!service.panelWanted)
        #expect(service.current == nil)
        #expect(!service.visible)
    }

    @Test func laterToastReplacesAndCancelsTheOldSequence() async {
        let sleeper = ParkingSleeper()
        let service = ToastService(sleeper: sleeper)
        service.show(.success, "first")
        await eventually(sleeper.parkedCount == 1)
        service.show(.error, "second")
        #expect(service.current?.text == "second")
        #expect(service.visible)
        #expect(service.panelWanted)
        // Old sequence's visible-sleep (2.0) + new sequence's (3.5); the old
        // task never reaches its fade sleep.
        await eventually(sleeper.slept == [2.0, 3.5])
        #expect(sleeper.cancelledCount >= 1)
    }

    /// Regression: the @Observable macro's equality-checked setter does not
    /// notify on a same-value write, so a second show() while a toast is
    /// still visible (panelWanted true→true) must advance showID to carry
    /// the re-present signal — including when nothing else changes.
    @Test func everyShowAdvancesShowIDEvenWhenPanelAlreadyWanted() {
        let service = ToastService(sleeper: ParkingSleeper())
        service.show(.success, "first")
        #expect(service.showID == 1)

        // Replace-while-visible with different text: panelWanted stays true,
        // so only the showID bump distinguishes this show from the last.
        service.show(.error, "second, a longer replacement")
        #expect(service.showID == 2)

        // Identical kind+text re-show: every Equatable-visible value is
        // unchanged — showID must still advance or present() never re-fires.
        service.show(.error, "second, a longer replacement")
        #expect(service.showID == 3)
    }
}
