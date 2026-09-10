// NemoLoop/Plugins/Chain/ChainStore.swift
import Foundation
import Observation

/// Self-managed plugin config (the P0 foundation pattern): the Chains
/// plugin owns its data, derives `operations` from it at read time, and
/// persists it as JSON under its own UserDefaults key — SliceStore and the
/// slot format know nothing about it. Every write is clamped to the spec's
/// limits; the builder UI clamps too (double enforcement).
@MainActor
@Observable
final class ChainStore {
    /// On-disk key contract — pinned by ChainStoreTests and `defaults read`
    /// debugging; same family as nemoloop.plugin.<id>.enabled.
    static let storageKey = "nemoloop.plugin.chain.chains"
    static let maxChains = 32

    private let defaults: UserDefaults

    private(set) var chains: [ChainDefinition] {
        didSet { persist() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([ChainDefinition].self, from: data) {
            chains = decoded
        } else {
            chains = []
        }
    }

    @discardableResult
    func add(_ chain: ChainDefinition) -> Bool {
        guard chains.count < Self.maxChains else {
            NSLog("NemoLoop chain store: full (\(Self.maxChains)) — add ignored")
            return false
        }
        chains.append(Self.clamped(chain))
        return true
    }

    func update(_ chain: ChainDefinition) {
        guard let index = chains.firstIndex(where: { $0.id == chain.id }) else { return }
        chains[index] = Self.clamped(chain)
    }

    func remove(id: UUID) {
        chains.removeAll { $0.id == id }
    }

    private static func clamped(_ chain: ChainDefinition) -> ChainDefinition {
        var clamped = chain
        clamped.steps = Array(clamped.steps.prefix(ChainDefinition.maxSteps))
        clamped.repeatCount = min(max(clamped.repeatCount, ChainDefinition.minRepeatCount),
                                  ChainDefinition.maxRepeatCount)
        clamped.interStepDelay = min(max(clamped.interStepDelay, 0), ChainDefinition.maxDelaySeconds)
        return clamped
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(chains) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
