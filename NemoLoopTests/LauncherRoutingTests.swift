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
}
