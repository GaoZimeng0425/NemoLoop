// NemoLoopTests/PluginRegistryTests.swift
import Testing
import Foundation
@testable import NemoLoop

@MainActor
struct PluginRegistryTests {
    @Test func enabledPersistsAcrossInstances() async throws {
        let plugin = StubPlugin([StubOp("a")])
        let defaults = makeDefaults()
        let r1 = PluginRegistry(defaults: defaults, plugins: [plugin])
        #expect(!r1.isEnabled("stub"))
        try await r1.setEnabled("stub", true)
        #expect(r1.isEnabled("stub"))
        // Pin the documented on-disk key contract, not just the behavior:
        // the settings UI (Task 6) and `defaults read` debugging depend on it.
        #expect(defaults.bool(forKey: "nemoloop.plugin.stub.enabled"))

        let r2 = PluginRegistry(defaults: defaults, plugins: [StubPlugin([StubOp("a")])])
        #expect(r2.isEnabled("stub"))
    }

    @Test func connectFailureRollsBackAndThrows() async {
        let plugin = StubPlugin([StubOp("a")])
        plugin.connectError = URLError(.notConnectedToInternet)
        let registry = PluginRegistry(defaults: makeDefaults(), plugins: [plugin])
        await #expect(throws: (any Error).self) {
            try await registry.setEnabled("stub", true)
        }
        #expect(!registry.isEnabled("stub"))           // bounces back to off
        #expect(plugin.connectCalls == 1)
    }

    @Test func performRoutesToOpAndToleratesMissing() async throws {
        let op = StubOp("play")
        let registry = PluginRegistry(defaults: makeDefaults(), plugins: [StubPlugin([op])])
        try await registry.setEnabled("stub", true)
        registry.perform(pluginID: "stub", opID: "play")
        #expect(op.performedCount == 1)

        registry.perform(pluginID: "stub", opID: "nope")   // no crash, no count
        registry.perform(pluginID: "ghost", opID: "play")
        #expect(op.performedCount == 1)
    }

    @Test func performIgnoredWhenDisabled() async throws {
        let op = StubOp("play")
        let plugin = StubPlugin([op])
        let registry = PluginRegistry(defaults: makeDefaults(), plugins: [plugin])
        try await registry.setEnabled("stub", true)
        try await registry.setEnabled("stub", false)
        registry.perform(pluginID: "stub", opID: "play")
        #expect(op.performedCount == 0)
        #expect(plugin.disconnectCalls == 1)
    }

    @Test func unknownPluginDefaultsDisabled() {
        let registry = PluginRegistry(defaults: makeDefaults(), plugins: [])
        #expect(!registry.isEnabled("ghost"))
        #expect(registry.plugin(id: "ghost") == nil)
        #expect(registry.op(pluginID: "ghost", opID: "x") == nil)
    }

    @Test func systemPluginEnabledByDefaultAndDisablePersists() async throws {
        // Fresh defaults: the System plugin ships connected (key never written).
        let defaults = makeDefaults()
        let fresh = PluginRegistry(defaults: defaults, plugins: [SystemPlugin()])
        #expect(fresh.isEnabled("system"))

        // An explicit disable persists as false; re-enabling restores it —
        // the user's choice always beats the factory default.
        try await fresh.setEnabled("system", false)
        let afterDisable = PluginRegistry(defaults: defaults, plugins: [SystemPlugin()])
        #expect(!afterDisable.isEnabled("system"))

        try await afterDisable.setEnabled("system", true)
        #expect(PluginRegistry(defaults: defaults, plugins: [SystemPlugin()]).isEnabled("system"))
    }

    @Test func nonDefaultPluginsStayDisabledOnFreshDefaults() {
        let stub = StubPlugin([StubOp("a")])   // isEnabledByDefault = false (protocol default)
        let registry = PluginRegistry(defaults: makeDefaults(), plugins: [stub])
        #expect(!registry.isEnabled("stub"))
    }

    @Test func performReturnsTrueOnlyWhenRouted() async throws {
        // The chain executor (and any future combinator) needs perform to
        // report routing success so it can fail the sequence fast.
        let op = StubOp("play")
        let plugin = StubPlugin([op])
        let registry = PluginRegistry(defaults: makeDefaults(), plugins: [plugin])
        try await registry.setEnabled("stub", true)

        #expect(registry.perform(pluginID: "stub", opID: "play") == true)
        #expect(registry.perform(pluginID: "stub", opID: "nope") == false)   // unknown op
        #expect(registry.perform(pluginID: "ghost", opID: "play") == false)  // unknown plugin

        try await registry.setEnabled("stub", false)
        #expect(registry.perform(pluginID: "stub", opID: "play") == false)   // disabled
    }
}
