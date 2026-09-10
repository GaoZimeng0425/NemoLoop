import Testing
import Foundation
@testable import NemoLoop

@MainActor
struct ChainStoreTests {
    @Test func persistsUnderDocumentedKeyAndReloads() throws {
        let defaults = makeDefaults()
        let store = ChainStore(defaults: defaults)
        var chain = ChainDefinition(name: "Wrap Up")
        chain.steps = [.pluginOp(pluginID: "system", opID: "lockScreen")]
        chain.repeatCount = 2
        #expect(store.add(chain))

        // Pin the on-disk key contract, not just behavior (spec pins this key).
        let data = try #require(defaults.data(forKey: "nemoloop.plugin.chain.chains"))
        #expect(try JSONDecoder().decode([ChainDefinition].self, from: data) == [chain])

        let reopened = ChainStore(defaults: defaults)
        #expect(reopened.chains == [chain])
    }

    @Test func updateEditsInPlaceAndRemoveDrops() {
        let store = ChainStore(defaults: makeDefaults())
        var chain = ChainDefinition(name: "Draft")
        store.add(chain)

        chain.name = "Shipped"
        store.update(chain)
        #expect(store.chains.map(\.name) == ["Shipped"])

        store.update(ChainDefinition(name: "Unknown"))   // unknown id is a no-op
        #expect(store.chains.count == 1)

        store.remove(id: chain.id)
        #expect(store.chains.isEmpty)
    }

    @Test func addRefusesBeyondMaxChains() {
        let store = ChainStore(defaults: makeDefaults())
        for i in 0..<ChainStore.maxChains {
            #expect(store.add(ChainDefinition(name: "chain \(i)")))
        }
        #expect(!store.add(ChainDefinition(name: "one too many")))
        #expect(store.chains.count == ChainStore.maxChains)
    }

    @Test func updateClampsFieldsToSpecLimits() {
        let store = ChainStore(defaults: makeDefaults())
        var chain = ChainDefinition(name: "clamp")
        chain.steps = (0..<20).map { _ in .app(URL(filePath: "/Applications/Safari.app")) }
        chain.repeatCount = 99
        chain.interStepDelay = 9
        store.add(chain)

        let saved = store.chains[0]
        #expect(saved.steps.count == ChainDefinition.maxSteps)
        #expect(saved.steps.first == .app(URL(filePath: "/Applications/Safari.app")))  // prefix kept
        #expect(saved.repeatCount == ChainDefinition.maxRepeatCount)
        #expect(saved.interStepDelay == ChainDefinition.maxDelaySeconds)

        var under = ChainDefinition(name: "under", repeatCount: 0, interStepDelay: -1)
        under.id = chain.id
        store.update(under)
        #expect(store.chains[0].repeatCount == ChainDefinition.minRepeatCount)
        #expect(store.chains[0].interStepDelay == 0)
    }

    @Test func corruptDataFallsBackToEmpty() {
        let defaults = makeDefaults()
        defaults.set(Data([0xFF, 0xFE]), forKey: ChainStore.storageKey)
        #expect(ChainStore(defaults: defaults).chains.isEmpty)
    }
}
