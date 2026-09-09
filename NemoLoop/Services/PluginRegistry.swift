// NemoLoop/Services/PluginRegistry.swift
import Foundation
import Observation

/// Registry and enable-state source of truth for built-in plugins. Toggles
/// drive connect/disconnect; triggering funnels through
/// perform(pluginID:opID:), where missing/disabled targets just NSLog and
/// return — a stale slot action must never crash the ring.
@MainActor
@Observable
final class PluginRegistry {
    static let shared = PluginRegistry(plugins: [
        // Built-in plugins get registered here one by one from Task 3 on;
        // empty list for now.
    ])

    private static let enabledKeyPrefix = "nemoloop.plugin."

    /// On-disk key contract from the plugin architecture spec — later tasks
    /// (and hand debugging via `defaults read`) rely on the exact shape.
    private static func enabledKey(_ pluginID: String) -> String {
        enabledKeyPrefix + pluginID + ".enabled"
    }

    private let defaults: UserDefaults
    private(set) var plugins: [any NemoPlugin]
    private var enabledIDs: Set<String>

    init(defaults: UserDefaults = .standard, plugins: [any NemoPlugin] = []) {
        self.defaults = defaults
        self.plugins = plugins
        self.enabledIDs = Set(plugins.compactMap { plugin in
            defaults.bool(forKey: Self.enabledKey(plugin.id)) ? plugin.id : nil
        })
    }

    func isEnabled(_ pluginID: String) -> Bool { enabledIDs.contains(pluginID) }

    func plugin(id: String) -> (any NemoPlugin)? {
        plugins.first { $0.id == id }
    }

    func op(pluginID: String, opID: String) -> (any PluginOp)? {
        plugin(id: pluginID)?.operations.first { $0.id == opID }
    }

    /// On = connect (roll back and rethrow so the UI can surface the error);
    /// off = disconnect. Both persist.
    func setEnabled(_ pluginID: String, _ enabled: Bool) async throws {
        guard let plugin = plugin(id: pluginID) else {
            NSLog("NemoLoop plugin: toggle for unknown plugin \(pluginID)")
            return
        }
        if enabled {
            try await plugin.connect()
            enabledIDs.insert(pluginID)
        } else {
            await plugin.disconnect()
            enabledIDs.remove(pluginID)
        }
        defaults.set(enabled, forKey: Self.enabledKey(pluginID))
    }

    func perform(pluginID: String, opID: String) {
        guard isEnabled(pluginID) else {
            NSLog("NemoLoop plugin: op \(pluginID).\(opID) skipped — plugin disabled")
            return
        }
        guard let op = op(pluginID: pluginID, opID: opID) else {
            NSLog("NemoLoop plugin: unknown op \(pluginID).\(opID)")
            return
        }
        op.perform()
    }
}
