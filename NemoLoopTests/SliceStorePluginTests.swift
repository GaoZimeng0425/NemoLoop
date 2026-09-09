// NemoLoopTests/SliceStorePluginTests.swift
import Testing
import Foundation
@testable import NemoLoop

@MainActor
struct SliceStorePluginTests {
    private func makeStore() -> SliceStore {
        // Own UUID suite per store: the reload assertion reopens the same
        // on-disk suite by name (UserDefaults can't be asked for it back),
        // and parallel tests must not share one.
        let name = "slice-store-plugin-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return SliceStore(defaults: d, testingSuiteName: name)
    }

    @Test func attachWholePluginFillsChildrenWithAllOps() {
        let store = makeStore()
        store.attachWholePlugin("system", at: 0)
        let entry = store.config.slots[0]
        guard case .plugin("system") = entry.action else {
            Issue.record("expected whole-plugin action"); return
        }
        #expect(entry.children.count == 5)      // System plugin has 5 ops, under the 8 cap
        #expect(entry.children.first == .pluginOp(pluginID: "system", opID: "lockScreen"))

        store.persistNowForTesting()            // test-support flush hook
        let store2 = SliceStore(defaults: UserDefaults(suiteName: store.testingSuiteName!)!)
        #expect(store2.config.slots[0] == entry)
    }

    @Test func attachTruncatesOpsBeyondLimit() {
        let store = makeStore()
        // 9-op stub injected through a private registry — attachWholePlugin's
        // registry parameter exists for this (the shared registry has no stub9).
        let registry = PluginRegistry(defaults: makeDefaults(),
                                      plugins: [StubPlugin(id: "stub9", opCount: 9)])
        store.attachWholePlugin("stub9", at: 1, registry: registry)
        #expect(store.config.slots[1].children.count == SlotEntry.maxPluginChildren)
        // Truncation keeps plugin order (op0…op7), not an arbitrary subset.
        #expect(store.config.slots[1].children
            == (0..<SlotEntry.maxPluginChildren).map { .pluginOp(pluginID: "stub9", opID: "op\($0)") })
    }

    @Test func disabledPluginActionReportsDisabled() async throws {
        let store = makeStore()
        try await PluginRegistry.shared.setEnabled("system", true)
        #expect(store.isEnabled(.pluginOp(pluginID: "system", opID: "lockScreen")))
        try await PluginRegistry.shared.setEnabled("system", false)
        #expect(!store.isEnabled(.pluginOp(pluginID: "system", opID: "lockScreen")))
        #expect(!store.isEnabled(.plugin("system")))
        #expect(store.isEnabled(.app(URL(filePath: "/A.app"))))
        // Restore the shared registry: swift-testing suites may run in
        // parallel, so the System plugin must be back to enabled before
        // this test exits.
        try await PluginRegistry.shared.setEnabled("system", true)
    }

    @Test func replacingPluginSlotTrimsChildrenToNewLimit() {
        let store = makeStore()
        store.setAction(.plugin("stub9"), at: 2)      // whole-plugin slot: 8-child capacity
        for i in 0..<5 {
            store.addChild(.pluginOp(pluginID: "stub9", opID: "op\(i)"), at: 2)
        }
        #expect(store.config.slots[2].children.count == 5)   // 5 fit under the plugin limit
        store.setAction(.pluginOp(pluginID: "system", opID: "ocr"), at: 2)  // back to a manual slot
        #expect(store.config.slots[2].children.count == SlotEntry.maxManualChildren)
        // The earliest children survive the trim.
        #expect(store.config.slots[2].children.first == .pluginOp(pluginID: "stub9", opID: "op0"))
    }
}
