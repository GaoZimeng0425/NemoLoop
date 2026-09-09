// NemoLoopTests/SliceStorePluginTests.swift
import Testing
import Foundation
@testable import NemoLoop

@MainActor
struct SliceStorePluginTests {
    /// Test doubles: a plugin with a configurable op count, so the
    /// beyond-the-limit path can run against 9 ops without touching the
    /// shared registry (attachWholePlugin takes a registry for exactly this).
    /// The conformance clauses carry their own @MainActor: this module's
    /// default isolation is nonisolated, so an un-isolated conformance to a
    /// MainActor protocol is a data-race error in Swift 6 mode.
    @MainActor
    private final class StubOp: @MainActor PluginOp {
        let id: String; let displayName: String; let symbolName: String
        init(_ id: String) { self.id = id; displayName = id; symbolName = "circle" }
        func perform() {}
    }

    @MainActor
    private final class StubPlugin: @MainActor NemoPlugin {
        let id: String; let displayName: String; let symbolName: String
        let summary = "test double"
        let operations: [any PluginOp]
        var status: PluginStatus { .ready }
        init(id: String, opCount: Int) {
            self.id = id
            self.displayName = id
            self.symbolName = "puzzlepiece"
            self.operations = (0..<opCount).map { StubOp("op\($0)") }
        }
    }

    /// Isolated defaults suite: UserDefaults persists arbitrary suite names to
    /// disk, so scrub the domain first to keep runs independent.
    private func makeDefaults() -> UserDefaults {
        let name = "slice-store-plugin-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    private func makeStore() -> SliceStore {
        let name = "slice-store-plugin-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        // Suite name passed in (UserDefaults can't be asked for it back) so
        // the reload assertion below can reopen the same on-disk suite.
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
