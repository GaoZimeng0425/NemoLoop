// NemoLoop/Plugins/SystemPlugin.swift
import Foundation

/// The factory-fit family of system actions, adopted into the plugin system:
/// op ids reuse SystemAction.rawValue and perform still routes to the
/// existing SystemActions.swift implementations — zero behavior change.
@MainActor
final class SystemPlugin: @MainActor NemoPlugin {
    struct Op: @MainActor PluginOp {
        let action: SystemAction
        var id: String { action.rawValue }
        var displayName: String { action.displayName }
        var symbolName: String { action.symbolName }
        func perform() { action.perform() }
    }

    let id = "system"
    let displayName = "System"
    let symbolName = "gearshape.2"
    let summary = "Built-in system actions: lock, sleep, Mission Control, OCR."

    let operations: [any PluginOp] = SystemAction.allCases.map(Op.init(action:))
    var status: PluginStatus { .ready }
}
