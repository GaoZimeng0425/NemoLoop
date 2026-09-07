import Testing
import Foundation
@testable import NemoLoop

struct SliceConfigTests {
    @Test func initPadsToSixSlots() {
        let c = SliceConfig(slots: [SlotEntry(action: .app(URL(filePath: "/Applications/Safari.app")))])
        #expect(c.slots.count == 6)
        #expect(c.slots[0].action == .app(URL(filePath: "/Applications/Safari.app")))
        #expect(c.slots[5].action == nil)
        #expect(c.slots[5].children.isEmpty)
    }

    @Test func initTruncatesBeyondSix() {
        let slots = (0..<8).map { SlotEntry(action: .app(URL(filePath: "/A\($0).app"))) }
        #expect(SliceConfig(slots: slots).slots.count == 6)
    }

    @Test func codableRoundTrip() throws {
        var c = SliceConfig.empty
        c.slots[2] = SlotEntry(action: .app(URL(filePath: "/Applications/Notes.app")))
        let data = try JSONEncoder().encode(c)
        let decoded = try JSONDecoder().decode(SliceConfig.self, from: data)
        #expect(decoded == c)
    }

    @Test func mixedActionTypesAndChildrenRoundTrip() throws {
        var c = SliceConfig.empty
        c.slots[0] = SlotEntry(action: .app(URL(filePath: "/Applications/Safari.app")),
                               children: [.folder(URL(filePath: "/Users/x/Downloads")),
                                          .system(.lockScreen)])
        c.slots[1] = SlotEntry(action: .folder(URL(filePath: "/Users/x/Downloads")))
        c.slots[2] = SlotEntry(action: .system(.missionControl))
        c.slots[3] = SlotEntry(children: [.system(.sleep)])   // subs without a parent action
        let data = try JSONEncoder().encode(c)
        let decoded = try JSONDecoder().decode(SliceConfig.self, from: data)
        #expect(decoded == c)
    }
}

struct SlotEntryTests {
    @Test func childrenAreCappedAtMax() {
        let many: [SlotAction] = (0..<6).map { .system(SystemAction.allCases[$0 % SystemAction.allCases.count]) }
        let entry = SlotEntry(action: .system(.lockScreen), children: many)
        #expect(entry.children.count == SlotEntry.maxChildren)
    }

    @Test func identityIsStablePerKind() {
        let app = SlotAction.app(URL(fileURLWithPath: "/Applications/Safari.app"))
        let folder = SlotAction.folder(URL(fileURLWithPath: "/Applications"))
        // An app and a folder sharing a basename must not collide.
        #expect(app.identity == "/Applications/Safari.app")
        #expect(folder.identity == "/Applications")
        #expect(SlotAction.system(.lockScreen).identity == "system:lockScreen")
    }

    @Test func displayNames() {
        #expect(SlotAction.app(URL(fileURLWithPath: "/Applications/Safari.app")).displayName == "Safari")
        #expect(SlotAction.folder(URL(fileURLWithPath: "/Users/x/My Files")).displayName == "My Files")
        #expect(SlotAction.system(.sleepDisplays).displayName == "Sleep Displays")
    }

    @Test func systemActionsAreComplete() {
        // Each system action must be presentable (label + symbol) — the ring
        // icon cache and the settings menu both iterate allCases.
        for system in SystemAction.allCases {
            #expect(!system.displayName.isEmpty)
            #expect(!system.symbolName.isEmpty)
        }
    }
}

@MainActor
struct SliceStoreMigrationTests {
    private func freshDefaults(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: "nemoloop.tests.\(name)")!
        defaults.removePersistentDomain(forName: "nemoloop.tests.\(name)")
        return defaults
    }

    @Test func legacyAppURLSlotsMigrateToAppEntries() {
        let defaults = freshDefaults("migration")
        let urls: [URL?] = [URL(filePath: "/Applications/Safari.app"), nil]
        defaults.set(try! JSONEncoder().encode(urls), forKey: "nemoloop.sliceConfig")

        let store = SliceStore(defaults: defaults)
        #expect(store.config.slots[0].action == .app(URL(filePath: "/Applications/Safari.app")))
        #expect(store.config.slots[1].action == nil)
        // Icons rebuilt for the migrated entries (Safari + five empties).
        #expect(store.icons.count == SliceConfig.wedgeCount)
    }

    @Test func v2ActionArraysMigrateToEntries() throws {
        let defaults = freshDefaults("migration-v2")
        // The v2 payload shape: {"actions": [SlotAction?]}
        struct V2: Codable { var actions: [SlotAction?] }
        defaults.set(try JSONEncoder().encode(V2(actions: [nil, .app(URL(filePath: "/Applications/Notes.app"))])),
                     forKey: "nemoloop.slotActions")

        let store = SliceStore(defaults: defaults)
        #expect(store.config.slots[0].action == nil)
        #expect(store.config.slots[1].action == .app(URL(filePath: "/Applications/Notes.app")))
    }

    @Test func newFormatPersistsUnderItsOwnKey() throws {
        let defaults = freshDefaults("persist")
        let store = SliceStore(defaults: defaults)
        store.setAction(.system(.lockScreen), at: 4)
        store.addChild(.folder(URL(filePath: "/Users/x/Downloads")), at: 4)

        let reread = SliceStore(defaults: defaults)
        #expect(reread.config.slots[4].action == .system(.lockScreen))
        #expect(reread.config.slots[4].children == [.folder(URL(filePath: "/Users/x/Downloads"))])
        // The stored payload is the new format, decodable as SliceConfig.
        let data = try #require(defaults.data(forKey: "nemoloop.slotEntries"))
        #expect(try JSONDecoder().decode(SliceConfig.self, from: data).slots[4].action == .system(.lockScreen))
    }

    @Test func childMutationsRespectTheCap() {
        let store = SliceStore(defaults: freshDefaults("cap"))
        for i in 0..<6 {
            store.addChild(.system(SystemAction.allCases[i % SystemAction.allCases.count]), at: 0)
        }
        #expect(store.config.slots[0].children.count == SlotEntry.maxChildren)
        store.removeChild(at: 0, offset: 1)
        #expect(store.config.slots[0].children.count == SlotEntry.maxChildren - 1)
    }

    @Test func noDataGivesEmptyConfig() {
        let store = SliceStore(defaults: freshDefaults("empty"))
        #expect(store.config == .empty)
        #expect(store.icons.count == SliceConfig.wedgeCount)
    }
}
