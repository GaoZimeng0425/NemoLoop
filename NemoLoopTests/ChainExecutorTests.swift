import Testing
import Foundation
@testable import NemoLoop

@MainActor
struct ChainExecutorTests {
    // Doubles: everything records into one ordered log so sequence semantics
    // (order, repeat, abort point) assert on a single timeline.
    @MainActor
    private final class Log {
        var entries: [String] = []
        func record(_ entry: String) { entries.append(entry) }
    }

    @MainActor
    private final class RecordingOpener: AppOpening {
        let log: Log
        var nextResult = true
        init(log: Log) { self.log = log }
        @discardableResult func open(_ url: URL) -> Bool {
            log.record("open:\(url.lastPathComponent)")
            return nextResult
        }
    }

    @MainActor
    private final class RecordingSleeper: ChainSleeping {
        var slept: [TimeInterval] = []
        func sleep(seconds: TimeInterval) async throws { slept.append(seconds) }
    }

    /// Parks each sleep on a continuation so a run can be frozen mid-delay
    /// (the reentrancy test needs a run demonstrably still in flight).
    @MainActor
    private final class BlockingSleeper: ChainSleeping {
        private var parked: [CheckedContinuation<Void, Never>] = []
        private(set) var sleptCount = 0
        func sleep(seconds: TimeInterval) async throws {
            sleptCount += 1
            await withCheckedContinuation { parked.append($0) }
        }
        func releaseAll() {
            parked.forEach { $0.resume() }
            parked.removeAll()
        }
    }

    @Test func runsStepsInOrderAcrossRepeats() async throws {
        let log = Log()
        let opener = RecordingOpener(log: log)
        let a = ClosureOp("a") { log.record("a") }
        let registry = PluginRegistry(defaults: makeDefaults(), plugins: [StubPlugin(id: "stub", [a])])
        try await registry.setEnabled("stub", true)

        var chain = ChainDefinition(name: "seq")
        chain.steps = [.pluginOp(pluginID: "stub", opID: "a"),
                       .app(URL(filePath: "/Applications/Safari.app"))]
        chain.repeatCount = 2
        chain.interStepDelay = 0    // determinism: no sleeps in this test

        let executor = ChainExecutor(registry: { registry }, appOpener: opener,
                                      sleeper: RecordingSleeper())
        await executor.run(chain)
        #expect(log.entries == ["a", "open:Safari.app", "a", "open:Safari.app"])
    }

    @Test func delayBeforeEveryStepExceptTheVeryFirst() async throws {
        let log = Log()
        let a = ClosureOp("a") { log.record("a") }
        let b = ClosureOp("b") { log.record("b") }
        let registry = PluginRegistry(defaults: makeDefaults(), plugins: [StubPlugin(id: "stub", [a, b])])
        try await registry.setEnabled("stub", true)

        var chain = ChainDefinition(name: "delay")
        chain.steps = [.pluginOp(pluginID: "stub", opID: "a"),
                       .pluginOp(pluginID: "stub", opID: "b")]
        chain.repeatCount = 2
        chain.interStepDelay = 0.25

        let sleeper = RecordingSleeper()
        let executor = ChainExecutor(registry: { registry }, appOpener: RecordingOpener(log: log),
                                     sleeper: sleeper)
        await executor.run(chain)
        // 4 executions → 3 waits (everything except the run's very first
        // step; the iteration boundary counts as a step boundary).
        #expect(sleeper.slept == [0.25, 0.25, 0.25])
        #expect(log.entries == ["a", "b", "a", "b"])
    }

    @Test func zeroDelayNeverSleeps() async throws {
        let a = ClosureOp("a")
        let registry = PluginRegistry(defaults: makeDefaults(), plugins: [StubPlugin(id: "stub", [a])])
        try await registry.setEnabled("stub", true)

        var chain = ChainDefinition(name: "fast")
        chain.steps = [.pluginOp(pluginID: "stub", opID: "a"),
                       .pluginOp(pluginID: "stub", opID: "a"),
                       .pluginOp(pluginID: "stub", opID: "a")]
        chain.interStepDelay = 0    // the zero under test (default is 0.2)
        let sleeper = RecordingSleeper()
        await ChainExecutor(registry: { registry }, appOpener: RecordingOpener(log: Log()),
                            sleeper: sleeper).run(chain)
        #expect(sleeper.slept.isEmpty)
    }

    @Test func unknownOpStepAbortsTheChain() async throws {
        let log = Log()
        let opener = RecordingOpener(log: log)
        let registry = PluginRegistry(defaults: makeDefaults(), plugins: [StubPlugin(id: "stub", [ClosureOp("a")])])
        try await registry.setEnabled("stub", true)

        var chain = ChainDefinition(name: "abort")
        chain.steps = [.pluginOp(pluginID: "stub", opID: "ghost"),   // unknown → false
                       .app(URL(filePath: "/Applications/Safari.app"))]
        chain.interStepDelay = 0
        await ChainExecutor(registry: { registry }, appOpener: opener,
                            sleeper: RecordingSleeper()).run(chain)
        #expect(log.entries.isEmpty)   // step 2 never ran
    }

    @Test func disabledPluginStepAbortsTheChain() async throws {
        let log = Log()
        let plugin = StubPlugin(id: "stub", [ClosureOp("a")])
        let registry = PluginRegistry(defaults: makeDefaults(), plugins: [plugin])
        try await registry.setEnabled("stub", true)
        try await registry.setEnabled("stub", false)   // enabled then disabled

        var chain = ChainDefinition(name: "disabled")
        chain.steps = [.pluginOp(pluginID: "stub", opID: "a"),
                       .app(URL(filePath: "/Applications/Safari.app"))]
        chain.interStepDelay = 0
        await ChainExecutor(registry: { registry }, appOpener: RecordingOpener(log: log),
                            sleeper: RecordingSleeper()).run(chain)
        #expect(log.entries.isEmpty)
    }

    @Test func openFailureAbortsTheChain() async throws {
        let log = Log()
        let opener = RecordingOpener(log: log)
        opener.nextResult = false
        let a = ClosureOp("a") { log.record("a") }
        let registry = PluginRegistry(defaults: makeDefaults(), plugins: [StubPlugin(id: "stub", [a])])
        try await registry.setEnabled("stub", true)

        var chain = ChainDefinition(name: "openfail")
        chain.steps = [.app(URL(filePath: "/Applications/Safari.app")),
                       .pluginOp(pluginID: "stub", opID: "a")]
        chain.interStepDelay = 0
        await ChainExecutor(registry: { registry }, appOpener: opener,
                            sleeper: RecordingSleeper()).run(chain)
        #expect(log.entries == ["open:Safari.app"])   // abort before the op step
    }

    @Test func wholePluginStepFailsDefensively() async throws {
        let log = Log()
        let registry = PluginRegistry(defaults: makeDefaults(), plugins: [StubPlugin(id: "stub", [ClosureOp("a")])])
        try await registry.setEnabled("stub", true)

        var chain = ChainDefinition(name: "defensive")
        chain.steps = [.plugin("stub"),
                       .pluginOp(pluginID: "stub", opID: "a")]
        chain.interStepDelay = 0
        await ChainExecutor(registry: { registry }, appOpener: RecordingOpener(log: log),
                            sleeper: RecordingSleeper()).run(chain)
        #expect(log.entries.isEmpty)   // .plugin as a step is filtered by the builder; treated as failure here
    }

    @Test func folderStepsOpenThroughTheSeam() async throws {
        let log = Log()
        let opener = RecordingOpener(log: log)
        let executor = ChainExecutor(registry: { PluginRegistry(defaults: makeDefaults(), plugins: []) },
                                     appOpener: opener, sleeper: RecordingSleeper())
        var chain = ChainDefinition(name: "folders")
        chain.steps = [.folder(URL(filePath: "/Users/dev/Work"))]
        await executor.run(chain)
        #expect(log.entries == ["open:Work"])
    }

    @Test func reentrantRunIsIgnoredWhileRunning() async throws {
        let log = Log()
        let a = ClosureOp("a") { log.record("a") }
        let registry = PluginRegistry(defaults: makeDefaults(), plugins: [StubPlugin(id: "stub", [a])])
        try await registry.setEnabled("stub", true)

        var chain = ChainDefinition(name: "double")
        chain.steps = [.pluginOp(pluginID: "stub", opID: "a"),
                       .pluginOp(pluginID: "stub", opID: "a")]
        chain.interStepDelay = 0.1   // parks run #1 between its two steps

        let sleeper = BlockingSleeper()
        let executor = ChainExecutor(registry: { registry }, appOpener: RecordingOpener(log: Log()),
                                     sleeper: sleeper)
        let first = Task { await executor.run(chain) }
        // Single-actor determinism: yield until run #1 has parked in the sleeper
        // (its first step has executed exactly once by then).
        while sleeper.sleptCount < 1 { await Task.yield() }

        await executor.run(chain)          // reentrant trigger — must be a no-op
        #expect(log.entries == ["a"])      // run #1's first step only

        sleeper.releaseAll()
        await first.value
        #expect(log.entries == ["a", "a"]) // run #1 finished; run #2 added nothing
    }
}
