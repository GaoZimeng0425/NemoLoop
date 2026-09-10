// NemoLoop/Plugins/Chain/ChainDefinition.swift
import Foundation

/// One user-defined action chain: steps run sequentially, the whole run
/// repeats `repeatCount` times, and every step except the first of the run
/// waits `interStepDelay` seconds. Steps are any NON-chain `SlotAction`
/// (v1 has no nesting). The id doubles as the Chains plugin's op id.
struct ChainDefinition: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var symbolName = "link"
    var steps: [SlotAction] = []
    var repeatCount = 1
    var interStepDelay: TimeInterval = 0.2

    static let maxSteps = 16
    static let minRepeatCount = 1
    static let maxRepeatCount = 20
    static let maxDelaySeconds: TimeInterval = 5

    /// Icon chips offered by the builder — a full SF Symbol browser is out
    /// of scope for v1 (spec).
    static let presetSymbols = [
        "link", "bolt", "clock", "arrow.triangle.2.circlepath", "square.stack.3d.up",
        "globe", "doc.text", "keyboard", "paintbrush", "terminal",
    ]
}
