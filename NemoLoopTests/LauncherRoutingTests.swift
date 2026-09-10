import Testing
import Foundation
@testable import NemoLoop

/// The ring's single trigger choke point: whole-plugin blades run their first
/// configured child op, single ops route through the registry (which gates on
/// enabled). Routing is the part worth pinning — the ops themselves are covered
/// by their own suites.
@MainActor
struct LauncherRoutingTests {
    @Test func pluginBladeRunsFirstChildOpOnly() async throws {
        let a = StubOp("a"), b = StubOp("b")
        let registry = PluginRegistry(defaults: makeDefaults(), plugins: [StubPlugin([a, b])])
        try await registry.setEnabled("stub", true)

        Launcher.run(.plugin("stub"),
                     children: [.pluginOp(pluginID: "stub", opID: "a"),
                                .pluginOp(pluginID: "stub", opID: "b")],
                     registry: registry)
        #expect(a.performedCount == 1)
        #expect(b.performedCount == 0)
    }

    @Test func pluginBladeWithoutChildrenRunsNothing() async throws {
        let a = StubOp("a")
        let registry = PluginRegistry(defaults: makeDefaults(), plugins: [StubPlugin([a])])
        try await registry.setEnabled("stub", true)

        Launcher.run(.plugin("stub"), children: [], registry: registry)
        #expect(a.performedCount == 0)
    }

    @Test func pluginBladeWithNonOpFirstChildRunsNothing() async throws {
        let a = StubOp("a")
        let registry = PluginRegistry(defaults: makeDefaults(), plugins: [StubPlugin([a])])
        try await registry.setEnabled("stub", true)

        Launcher.run(.plugin("stub"),
                     children: [.app(URL(filePath: "/Applications/Safari.app"))],
                     registry: registry)
        #expect(a.performedCount == 0)
    }

    @Test func pluginOpRoutesThroughRegistry() async throws {
        let a = StubOp("a")
        let registry = PluginRegistry(defaults: makeDefaults(), plugins: [StubPlugin([a])])
        try await registry.setEnabled("stub", true)

        Launcher.run(.pluginOp(pluginID: "stub", opID: "a"), registry: registry)
        #expect(a.performedCount == 1)
    }

    @Test func disabledPluginOpIsInert() {
        let a = StubOp("a")
        let registry = PluginRegistry(defaults: makeDefaults(), plugins: [StubPlugin([a])])
        // Left disabled: the registry's gate (not the launcher) must stop it.

        Launcher.run(.pluginOp(pluginID: "stub", opID: "a"), registry: registry)
        #expect(a.performedCount == 0)
    }

    /// Spec test-table row: a chain op trigger routes through the registry to
    /// the executor. This is the composite id-space handshake — picker output,
    /// slot persistence, and registry lookup all agree that a chain's opID is
    /// the ChainDefinition UUID's uuidString, resolved through the REAL
    /// ChainPlugin.operations into the injected executor (a real ChainExecutor
    /// would just recurse into this same registry.perform seam).
    @Test func chainOpRoutesThroughRegistryToExecutor() async throws {
        let store = ChainStore(defaults: makeDefaults())
        var chain = ChainDefinition(name: "Routing")
        chain.steps = [.pluginOp(pluginID: "stub", opID: "a")]
        chain.interStepDelay = 0
        store.add(chain)

        let executor = RecordingChainExecutor()
        let registry = PluginRegistry(defaults: makeDefaults(),
                                      plugins: [ChainPlugin(store: store, executor: executor)])
        try await registry.setEnabled("chain", true)

        let routed = registry.perform(pluginID: "chain", opID: chain.id.uuidString)
        #expect(routed == true)
        try await Task.sleep(for: .milliseconds(100))   // Op.perform is fire-and-forget
        #expect(executor.runs.map(\.id) == [chain.id])

        // Cheap negative: uuidString is uppercase and the registry lookup is
        // exact match, so the lowercased spelling of the same id must not route.
        #expect(registry.perform(pluginID: "chain", opID: chain.id.uuidString.lowercased()) == false)
        #expect(executor.runs.map(\.id) == [chain.id])   // no extra run
    }

    /// Executor double for the chain-routing test: records runs synchronously
    /// at entry.
    @MainActor
    final class RecordingChainExecutor: ChainExecuting {
        private(set) var runs: [ChainDefinition] = []
        func run(_ chain: ChainDefinition) async { runs.append(chain) }
    }
}
