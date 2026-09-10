import Testing
import Foundation
@testable import NemoLoop

@MainActor
struct ChainPluginTests {
    /// Executor double: records runs synchronously at entry.
    @MainActor
    final class RecordingExecutor: ChainExecuting {
        var runs: [ChainDefinition] = []
        func run(_ chain: ChainDefinition) async { runs.append(chain) }
    }

    @Test func operationsDeriveFromStoreByIdentity() {
        let store = ChainStore(defaults: makeDefaults())
        var first = ChainDefinition(name: "Wrap Up")
        first.steps = [.pluginOp(pluginID: "system", opID: "lockScreen")]
        var second = ChainDefinition(name: "Morning")
        second.symbolName = "clock"
        second.steps = [.app(URL(filePath: "/Applications/Safari.app"))]   // non-empty → mountable
        store.add(first)
        store.add(second)

        let plugin = ChainPlugin(store: store, executor: RecordingExecutor())
        #expect(plugin.id == "chain")
        #expect(plugin.operations.map(\.id) == [first.id.uuidString, second.id.uuidString])
        #expect(plugin.operations.map(\.displayName) == ["Wrap Up", "Morning"])
        #expect(plugin.operations.map(\.symbolName) == ["link", "clock"])
    }

    @Test func editingAChainFollowsThroughTheOpIdentity() {
        let store = ChainStore(defaults: makeDefaults())
        var chain = ChainDefinition(name: "Draft")
        chain.steps = [.pluginOp(pluginID: "system", opID: "lockScreen")]   // mountable (empty chains yield no op)
        store.add(chain)

        let plugin = ChainPlugin(store: store, executor: RecordingExecutor())
        chain.name = "Shipped"          // same UUID, new name
        chain.symbolName = "bolt"
        store.update(chain)

        let op = plugin.operations[0]
        #expect(op.id == chain.id.uuidString)   // slot references survive edits
        #expect(op.displayName == "Shipped")
        #expect(op.symbolName == "bolt")
    }

    @Test func removingAChainDropsItsOp() {
        let store = ChainStore(defaults: makeDefaults())
        var chain = ChainDefinition(name: "Gone")
        chain.steps = [.pluginOp(pluginID: "system", opID: "lockScreen")]   // mountable (empty chains yield no op)
        store.add(chain)
        let plugin = ChainPlugin(store: store, executor: RecordingExecutor())
        #expect(plugin.operations.count == 1)

        store.remove(id: chain.id)
        #expect(plugin.operations.isEmpty)
        // Mounted slots keep .pluginOp("chain", <uuid>) — the registry's
        // existing unknown-op tolerance covers the dangling reference.
    }

    @Test func shipsEnabledByDefault() {
        let registry = PluginRegistry(defaults: makeDefaults(),
                                      plugins: [ChainPlugin(store: ChainStore(defaults: makeDefaults()),
                                                            executor: RecordingExecutor())])
        #expect(registry.isEnabled("chain"))
    }

    @Test func opPerformDelegatesToTheExecutor() async throws {
        let store = ChainStore(defaults: makeDefaults())
        var chain = ChainDefinition(name: "Run me")
        chain.steps = [.pluginOp(pluginID: "stub", opID: "a")]
        chain.interStepDelay = 0
        store.add(chain)

        let executor = RecordingExecutor()
        let plugin = ChainPlugin(store: store, executor: executor)
        plugin.operations[0].perform()   // fire-and-forget Task inside

        // The perform() spawns a Task; give the main actor a beat to drain it.
        try await Task.sleep(for: .milliseconds(100))
        #expect(executor.runs.map(\.id) == [chain.id])
    }

    @Test func emptyStoreYieldsNoOperations() {
        let plugin = ChainPlugin(store: ChainStore(defaults: makeDefaults()),
                                 executor: RecordingExecutor())
        #expect(plugin.operations.isEmpty)
        #expect(plugin.status == .ready)
    }

    @Test func emptyChainYieldsNoOpUntilItHasAStep() {
        // Spec: an empty chain must not be mountable — the builder creates
        // chains with zero steps, and the op only appears once a step lands.
        let store = ChainStore(defaults: makeDefaults())
        var empty = ChainDefinition(name: "Nothing yet")
        store.add(empty)
        var filled = ChainDefinition(name: "Has a step")
        filled.steps = [.pluginOp(pluginID: "system", opID: "lockScreen")]
        store.add(filled)

        let plugin = ChainPlugin(store: store, executor: RecordingExecutor())
        #expect(plugin.operations.map(\.displayName) == ["Has a step"])

        empty.steps = [.pluginOp(pluginID: "system", opID: "sleep")]
        store.update(empty)
        #expect(plugin.operations.count == 2)   // becomes mountable immediately
    }
}
