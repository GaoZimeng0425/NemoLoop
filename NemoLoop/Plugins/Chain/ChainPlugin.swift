// NemoLoop/Plugins/Chain/ChainPlugin.swift
import SwiftUI

/// The plugin over user-defined chains: every saved ChainDefinition becomes
/// exactly one op whose id is the chain's UUID — slots mount
/// `.pluginOp("chain", <uuid>)`, and edits flow into mounted blades because
/// ops derive from the store at read time. The first consumer of the P0
/// self-managed-config pattern (spec: 2026-09-10-plugin-config-chains).
@MainActor
final class ChainPlugin: @MainActor NemoPlugin {
    static let pluginID = "chain"

    private let store: ChainStore
    private let executor: any ChainExecuting

    /// Optional-with-nil-default (not `ChainStore()` as a default argument):
    /// default-argument generators are nonisolated under Swift 5 mode, and
    /// ChainStore.init is MainActor-isolated — the same reason the executor
    /// param below is optional. Coalescing in the body keeps construction on
    /// the actor and one store/executor per plugin instance.
    init(store: ChainStore? = nil, executor: (any ChainExecuting)? = nil) {
        self.store = store ?? ChainStore()
        self.executor = executor ?? ChainExecutor()
    }

    let id = ChainPlugin.pluginID
    let displayName = "Chains"
    let symbolName = "link"
    let summary = "Run several actions in one trigger — with repeat and inter-step delay."
    var status: PluginStatus { .ready }
    /// Ships connected like System: chains only exist once the user creates
    /// them, so an empty plugin costs nothing (spec decision).
    let isEnabledByDefault = true

    var operations: [any PluginOp] {
        // Empty chains stay unmountable (spec): they exist only in the
        // builder until their first step lands.
        store.chains
            .filter { !$0.steps.isEmpty }
            .map { Op(definition: $0, executor: executor) }
    }

    /// nil until the chain-builder task wires ChainConfigSection in.
    var configSections: AnyView? { nil }

    struct Op: @MainActor PluginOp {
        let definition: ChainDefinition
        let executor: any ChainExecuting
        var id: String { definition.id.uuidString }
        var displayName: String { definition.name }
        var symbolName: String { definition.symbolName }
        func perform() {
            // Fire-and-forget: the ring dismisses immediately; multi-second
            // chains must not hold the panel open.
            Task { await executor.run(definition) }
        }
    }
}
