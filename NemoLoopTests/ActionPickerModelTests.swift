// NemoLoopTests/ActionPickerModelTests.swift
import Testing
import Foundation
@testable import NemoLoop

@MainActor
struct ActionPickerModelTests {
    /// Fresh UUID suite per call so no test reads another's persisted keys.
    /// Appearance is left disconnected on purpose — the connected-only filter
    /// path needs a plugin that must NOT show up.
    private func makeModel() async throws -> ActionPickerModel {
        let defaults = UserDefaults(suiteName: "picker-tests-\(UUID().uuidString)")!
        let registry = PluginRegistry(defaults: defaults, plugins: [SystemPlugin(), AppearancePlugin()])
        try await registry.setEnabled("system", true)
        let apps = [AppEntry(id: "com.apple.Safari", name: "Safari",
                             url: URL(filePath: "/Applications/Safari.app")),
                    AppEntry(id: "com.apple.Terminal", name: "Terminal",
                             url: URL(filePath: "/Applications/Terminal.app"))]
        return ActionPickerModel(apps: apps, registry: registry)
    }

    @Test func mainSlotSectionsAppsThenConnectedPluginsThenFolders() async throws {
        let model = try await makeModel()
        let sections = model.sections(context: .mainSlot, query: "")
        #expect(sections.map(\.title) == ["Apps", "Plugins", "Folders"])
        let apps = sections[0].items
        // Scanned apps first, then Browse… closing the section (spec: 末尾 Browse…).
        #expect(apps.map(\.title) == ["Safari", "Terminal", "Browse…"])
        #expect(apps.last?.kind == .browseApps)

        let plugins = sections[1].items
        #expect(plugins.first?.kind == .wholePlugin("system"))   // whole-mount leads
        #expect(plugins.first?.subtitle == "5 actions")
        #expect(plugins.contains { $0.kind == .op(pluginID: "system", opID: "lockScreen") })
        // Ops carry the plugin name as subtitle so the flat list stays readable.
        #expect(plugins.first { $0.kind == .op(pluginID: "system", opID: "lockScreen") }?.subtitle == "System")
        #expect(!plugins.contains { $0.kind == .wholePlugin("appearance") }) // disconnected never shows
        #expect(plugins.contains { $0.kind == .op(pluginID: "system", opID: "ocr") })

        #expect(sections[2].items.map(\.kind) == [.browseFolder])
    }

    @Test func subSlotContextDropsWholePluginEntries() async throws {
        let model = try await makeModel()
        let sections = model.sections(context: .subSlot, query: "")
        let plugins = sections.first { $0.title == "Plugins" }!
        #expect(!plugins.items.contains { if case .wholePlugin = $0.kind { return true }; return false })
        #expect(plugins.items.contains { $0.kind == .op(pluginID: "system", opID: "sleep") })
    }

    @Test func disconnectedEverythingDropsPluginsSection() async throws {
        // System ships enabled by default; an explicit off beats it, so with
        // nothing connected the Plugins section must vanish entirely rather
        // than render as an empty header.
        let defaults = UserDefaults(suiteName: "picker-tests-\(UUID().uuidString)")!
        let fresh = PluginRegistry(defaults: defaults, plugins: [SystemPlugin(), AppearancePlugin()])
        try await fresh.setEnabled("system", false)
        let off = ActionPickerModel(apps: [], registry: fresh)
        #expect(off.sections(context: .mainSlot, query: "").map(\.title) == ["Apps", "Folders"])
    }

    @Test func searchFiltersAcrossSectionsByScore() async throws {
        let model = try await makeModel()
        let sections = model.sections(context: .mainSlot, query: "sa")
        let titles = sections.flatMap(\.items).map(\.title)
        // "Safari" hits the prefix tier; "Sleep Displays" only qualifies as a
        // subsequence (s…a in "displays") — sections keep their order, and
        // the prefix match leads across sections.
        #expect(titles == ["Safari", "Sleep Displays"])
        #expect(!titles.contains("Terminal"))
        // Terminal/Browse…/System matched nothing → non-matching rows and the
        // now-empty Folders section all dropped.
        #expect(sections.map(\.title) == ["Apps", "Plugins"])
    }

    @Test func searchSortsByScoreThenTitle() async throws {
        // "sl": "Sleep" and "Sleep Displays" hit the prefix tier, while
        // "Mission Control" only qualifies as a subsequence — tier first,
        // then localized title order inside a tier.
        let model = try await makeModel()
        let sections = model.sections(context: .mainSlot, query: "sl")
        let plugins = sections.first { $0.title == "Plugins" }!
        #expect(plugins.items.map(\.title) == ["Sleep", "Sleep Displays", "Mission Control"])
    }

    @Test func noMatchYieldsNoSections() async throws {
        let model = try await makeModel()
        #expect(model.sections(context: .mainSlot, query: "zzz").isEmpty)
    }

    @Test func emptyQueryShowsEverythingUnfiltered() async throws {
        let model = try await makeModel()
        let all = model.sections(context: .mainSlot, query: "").flatMap(\.items)
        #expect(all.count >= 2 + 1 + 6 + 1)   // 2 apps + browse + 1 whole + 5 ops + folder
    }

    @Test func footnotePointsDisconnectedPluginsAtPluginsTab() async throws {
        let model = try await makeModel()
        #expect(model.connectedPluginFootnote ==
                "Plugins not listed are disconnected — connect them in the Plugins tab.")
    }

    // MARK: - Chain-step context + zero-op filter

    private func makeChainModel() async throws -> ActionPickerModel {
        let defaults = UserDefaults(suiteName: "picker-tests-\(UUID().uuidString)")!
        let chainStore = ChainStore(defaults: defaults)
        var chain = ChainDefinition(name: "Wrap Up")
        chain.steps = [.pluginOp(pluginID: "system", opID: "lockScreen")]
        chainStore.add(chain)
        let registry = PluginRegistry(defaults: defaults,
                                      plugins: [SystemPlugin(), ChainPlugin(store: chainStore)])
        try await registry.setEnabled("system", true)
        try await registry.setEnabled("chain", true)
        return ActionPickerModel(apps: [], registry: registry)
    }

    @Test func chainStepListsSingleActionsOnly() async throws {
        let model = try await makeChainModel()
        let sections = model.sections(context: .chainStep, query: "")
        let plugins = sections.first { $0.title == "Plugins" }!

        // Single ops from other plugins stay pickable…
        #expect(plugins.items.contains { $0.kind == .op(pluginID: "system", opID: "lockScreen") })
        // …whole-plugin mounts are absent (like subSlot)…
        #expect(!plugins.items.contains { if case .wholePlugin = $0.kind { return true }; return false })
        // …and the Chains plugin itself never appears (no chain-in-chain).
        // Wildcard on the opID — chain op ids are UUIDs, so an exact-id
        // comparison could never match; the fixture HAS a populated chain,
        // so without the hide a `.op("chain", <uuid>)` row WOULD appear.
        #expect(!plugins.items.contains { if case .op("chain", _) = $0.kind { return true }; return false })
        // Apps and Folders sections unaffected.
        #expect(sections.map(\.title) == ["Apps", "Plugins", "Folders"])
    }

    @Test func zeroOpConnectedPluginRendersNothingInMainSlot() async throws {
        // A connected plugin with no operations (e.g. Chains before the user
        // creates any) must not render at all — its whole-plugin row would
        // mount an empty blade that can never run anything.
        let defaults = UserDefaults(suiteName: "picker-tests-\(UUID().uuidString)")!
        let registry = PluginRegistry(defaults: defaults,
                                      plugins: [SystemPlugin(), ChainPlugin(store: ChainStore(defaults: defaults))])
        try await registry.setEnabled("system", true)
        try await registry.setEnabled("chain", true)
        let model = ActionPickerModel(apps: [], registry: registry)

        let items = model.sections(context: .mainSlot, query: "").flatMap(\.items)
        #expect(!items.contains { $0.kind == .wholePlugin("chain") })
        #expect(!items.contains { if case .op("chain", _) = $0.kind { return true }; return false })
    }

    // MARK: - PickerCursor (picker keyboard navigation, pinned independently of the view)

    /// Minimal rows for cursor tests — only title matters for movement.
    private func cursorItems(_ titles: [String]) -> [PickerItem] {
        titles.enumerated().map { i, title in
            PickerItem(id: "cursor:\(i):\(title)", kind: .browseFolder,
                       title: title, subtitle: nil, symbolName: nil)
        }
    }

    @Test func cursorWrapsDownPastEnd() {
        let cursor = PickerCursor(items: cursorItems(["A", "B", "C"]), index: 2).moved(1)
        #expect(cursor.index == 0)
        #expect(cursor.current?.title == "A")
    }

    @Test func cursorWrapsUpPastStart() {
        let cursor = PickerCursor(items: cursorItems(["A", "B", "C"]), index: 0).moved(-1)
        #expect(cursor.index == 2)
        #expect(cursor.current?.title == "C")
    }

    @Test func cursorOnEmptyListIsInert() {
        let cursor = PickerCursor(items: [])
        #expect(cursor.current == nil)
        // Any move on an empty list must stay nil, not trap or invent an index
        // (e.g. "no results" mid-typing).
        #expect(cursor.moved(1).index == nil)
        #expect(cursor.moved(-1).current == nil)
    }

    @Test func cursorNilIndexSelectsFirstOnDownLastOnUp() {
        let items = cursorItems(["A", "B", "C"])
        // Fresh open (nil): first ↓ highlights the top row, first ↑ wraps to
        // the bottom — the same wrap semantics as an explicit move.
        #expect(PickerCursor(items: items).moved(1).index == 0)
        #expect(PickerCursor(items: items).moved(-1).index == 2)
    }

    @Test func cursorCurrentNilWhenIndexOutOfRange() {
        // Possible transiently if the list shrank before a rebound — reading
        // `current` must yield nil, not crash.
        let stale = PickerCursor(items: cursorItems(["A", "B", "C"]), index: 9)
        #expect(stale.current == nil)
    }

    @Test func cursorReboundKeepsIndexWhileInRange() {
        let rebound = PickerCursor(items: cursorItems(["A", "B", "C"]), index: 1)
            .rebound(to: cursorItems(["A", "B", "C", "D"]))
        #expect(rebound.index == 1)
        #expect(rebound.current?.title == "B")
    }

    @Test func cursorReboundClampsWhenListShrinks() {
        let rebound = PickerCursor(items: cursorItems(["A", "B", "C", "D"]), index: 3)
            .rebound(to: cursorItems(["A", "B"]))
        // Clamp to the last row instead of dropping the highlight mid-typing.
        #expect(rebound.index == 1)
        #expect(rebound.current?.title == "B")
    }

    @Test func cursorReboundToEmptyClearsIndex() {
        let rebound = PickerCursor(items: cursorItems(["A", "B"]), index: 1)
            .rebound(to: [])
        #expect(rebound.index == nil)
        #expect(rebound.current == nil)
    }

    // MARK: - PickerSearch tiers (Loop's scoring, pinned independently of the model)

    @Test func scoreTiersPrefixContainsSubsequence() {
        #expect(PickerSearch.score(query: "sa", name: "Safari") == 0)          // prefix
        #expect(PickerSearch.score(query: "fa", name: "Safari") == 1)          // contains
        #expect(PickerSearch.score(query: "sf", name: "Safari") == 2)          // subsequence
        #expect(PickerSearch.score(query: "xyz", name: "Safari") == nil)       // no match
        #expect(PickerSearch.score(query: "", name: "Safari") == 0)            // empty shows all
        // Case-insensitive on both sides, like Loop's picker.
        #expect(PickerSearch.score(query: "SA", name: "safari") == 0)
    }
}
