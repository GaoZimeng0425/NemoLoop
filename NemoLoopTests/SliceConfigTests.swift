import Testing
import Foundation
@testable import NemoLoop

struct SliceConfigTests {
    @Test func initPadsToSixSlots() {
        let c = SliceConfig(actions: [.app(URL(filePath: "/Applications/Safari.app"))])
        #expect(c.actions.count == 6)
        #expect(c.actions[0] == .app(URL(filePath: "/Applications/Safari.app")))
        #expect(c.actions[5] == nil)
    }

    @Test func initTruncatesBeyondSix() {
        let actions: [SlotAction?] = (0..<8).map { .app(URL(filePath: "/A\($0).app")) }
        #expect(SliceConfig(actions: actions).actions.count == 6)
    }

    @Test func codableRoundTrip() throws {
        var c = SliceConfig.empty
        c.actions[2] = .app(URL(filePath: "/Applications/Notes.app"))
        let data = try JSONEncoder().encode(c)
        let decoded = try JSONDecoder().decode(SliceConfig.self, from: data)
        #expect(decoded == c)
    }

    @Test func mixedActionTypesRoundTrip() throws {
        var c = SliceConfig.empty
        c.actions[0] = .app(URL(filePath: "/Applications/Safari.app"))
        c.actions[1] = .folder(URL(filePath: "/Users/x/Downloads"))
        c.actions[2] = .system(.lockScreen)
        c.actions[3] = .system(.missionControl)
        let data = try JSONEncoder().encode(c)
        let decoded = try JSONDecoder().decode(SliceConfig.self, from: data)
        #expect(decoded == c)
    }
}

struct SlotActionTests {
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

    @Test func legacyAppURLSlotsMigrateToAppActions() {
        let defaults = freshDefaults("migration")
        let urls: [URL?] = [URL(filePath: "/Applications/Safari.app"), nil]
        defaults.set(try! JSONEncoder().encode(urls), forKey: "nemoloop.sliceConfig")

        let store = SliceStore(defaults: defaults)
        #expect(store.config.actions[0] == .app(URL(filePath: "/Applications/Safari.app")))
        #expect(store.config.actions[1] == nil)
    }

    @Test func newFormatPersistsUnderItsOwnKey() throws {
        let defaults = freshDefaults("persist")
        let store = SliceStore(defaults: defaults)
        store.setAction(.system(.lockScreen), at: 4)

        let reread = SliceStore(defaults: defaults)
        #expect(reread.config.actions[4] == .system(.lockScreen))
        // The stored payload is the new format, decodable as SliceConfig.
        let data = try #require(defaults.data(forKey: "nemoloop.slotActions"))
        #expect(try JSONDecoder().decode(SliceConfig.self, from: data).actions[4] == .system(.lockScreen))
    }

    @Test func noDataGivesEmptyConfig() {
        let store = SliceStore(defaults: freshDefaults("empty"))
        #expect(store.config == .empty)
        #expect(store.icons.count == SliceConfig.wedgeCount)
    }
}
