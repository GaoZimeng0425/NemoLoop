// NemoLoop/Services/ActionResolver.swift
import AppKit

/// Shared name/symbol resolution for the ring and settings chips: plugin
/// cases resolve through the registry (disabled plugins still resolve — the
/// dim rule keeps them browsable). SlotAction lives in the nonisolated model
/// layer, so this MainActor lookup sits beside it instead of inside it.
@MainActor
enum ActionResolver {
    static func name(for action: SlotAction) -> String {
        switch action {
        case .app, .folder:
            return action.displayName
        case .plugin(let id):
            return PluginRegistry.shared.plugin(id: id)?.displayName ?? id
        case .pluginOp(let pluginID, let opID):
            return PluginRegistry.shared.op(pluginID: pluginID, opID: opID)?.displayName
                ?? "\(pluginID)/\(opID)"
        }
    }

    static func symbolName(for action: SlotAction) -> String? {
        switch action {
        case .app, .folder:
            return nil
        case .plugin(let id):
            return PluginRegistry.shared.plugin(id: id)?.symbolName
        case .pluginOp(let pluginID, let opID):
            return PluginRegistry.shared.op(pluginID: pluginID, opID: opID)?.symbolName
        }
    }
}
