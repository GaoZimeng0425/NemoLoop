import AppKit
import Foundation
import Testing
@testable import NemoLoop

struct AppearanceStoreTests {
    /// Isolated per-test defaults suite, so persistence tests never touch real user state.
    private func makeDefaults() -> UserDefaults {
        let name = "AppearanceStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func nsAppearanceMapping() {
        #expect(RingAppearance.auto.nsAppearance == nil)
        #expect(RingAppearance.light.nsAppearance?.name == .aqua)
        #expect(RingAppearance.dark.nsAppearance?.name == .darkAqua)
    }

    @Test @MainActor func defaultsToAuto() {
        let store = AppearanceStore(defaults: makeDefaults())
        #expect(store.appearance == .auto)
    }

    @Test @MainActor func setPersistsAcrossStoreInstances() {
        let defaults = makeDefaults()
        let store = AppearanceStore(defaults: defaults)
        store.appearance = .dark
        #expect(AppearanceStore(defaults: defaults).appearance == .dark)
    }

    @Test @MainActor func invalidStoredValueFallsBackToAuto() {
        let defaults = makeDefaults()
        defaults.set("not-a-theme", forKey: AppearanceStore.defaultsKey)
        #expect(AppearanceStore(defaults: defaults).appearance == .auto)
    }
}
