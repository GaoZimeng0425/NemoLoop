// NemoLoopTests/PluginRegistryTests.swift
import Testing
import Foundation
import SwiftUI
@testable import NemoLoop

@MainActor
struct PluginRegistryTests {
    /// Test doubles: minimal plugin/op that record how often they fire.
    /// The conformance clauses carry their own @MainActor: this module's
    /// default isolation is nonisolated, so an un-isolated conformance to a
    /// MainActor protocol is a data-race error in Swift 6 mode.
    @MainActor
    private final class StubOp: @MainActor PluginOp {
        let id: String; let displayName: String; let symbolName: String
        private(set) var performed = 0
        init(_ id: String) { self.id = id; displayName = id; symbolName = "circle" }
        func perform() { performed += 1 }
    }

    @MainActor
    private final class StubPlugin: @MainActor NemoPlugin {
        let id = "stub"; let displayName = "Stub"; let symbolName = "puzzlepiece"
        let summary = "test double"
        let ops: [StubOp]
        var connectError: Error?
        private(set) var connectCalls = 0
        private(set) var disconnectCalls = 0
        init(_ ops: [StubOp]) { self.ops = ops }
        var operations: [any PluginOp] { ops }
        var status: PluginStatus { .ready }
        func connect() async throws {
            connectCalls += 1
            if let connectError { throw connectError }
        }
        func disconnect() async { disconnectCalls += 1 }
    }

    /// Isolated defaults suite: UserDefaults persists arbitrary suite names to
    /// disk, so scrub the domain first to keep runs independent.
    private func makeDefaults() -> UserDefaults {
        let name = "plugin-registry-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

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
        #expect(op.performed == 1)

        registry.perform(pluginID: "stub", opID: "nope")   // no crash, no count
        registry.perform(pluginID: "ghost", opID: "play")
        #expect(op.performed == 1)
    }

    @Test func performIgnoredWhenDisabled() async throws {
        let op = StubOp("play")
        let plugin = StubPlugin([op])
        let registry = PluginRegistry(defaults: makeDefaults(), plugins: [plugin])
        try await registry.setEnabled("stub", true)
        try await registry.setEnabled("stub", false)
        registry.perform(pluginID: "stub", opID: "play")
        #expect(op.performed == 0)
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
}
