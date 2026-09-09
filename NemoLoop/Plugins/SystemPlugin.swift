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

    /// Ships connected: system actions predate the plugin system, so upgraders
    /// with saved `.system` slots (now System plugin ops) keep working the
    /// moment they update, without a settings visit.
    var isEnabledByDefault: Bool { true }

    let operations: [any PluginOp] = SystemAction.allCases.map(Op.init(action:))
    var status: PluginStatus { .ready }
}
