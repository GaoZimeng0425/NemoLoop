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
        SystemPlugin(),
        AppearancePlugin(),
        ScreenshotPlugin(),
        ChainPlugin(),
        WindowPlugin(),
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
        self.enabledIDs = Set(plugins.filter { Self.initialEnabled($0, defaults: defaults) }.map(\.id))
    }

    /// Tri-state enablement: key absent → the plugin's factory default;
    /// key present (even false) → the user's explicit choice always wins.
    /// Static because it runs while `self` is still initializing.
    private static func initialEnabled(_ plugin: any NemoPlugin, defaults: UserDefaults) -> Bool {
        let key = Self.enabledKey(plugin.id)
        if defaults.object(forKey: key) != nil { return defaults.bool(forKey: key) }
        return plugin.isEnabledByDefault
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

    /// Single funnel for every trigger. Returns false when the plugin is
    /// disabled or the op is unknown (both still just NSLog — a stale slot
    /// must never crash the ring); true when the op actually ran. The chain
    /// executor uses the result to abort a failing sequence.
    @discardableResult
    func perform(pluginID: String, opID: String) -> Bool {
        guard isEnabled(pluginID) else {
            NSLog("NemoLoop plugin: op \(pluginID).\(opID) skipped — plugin disabled")
            return false
        }
        guard let op = op(pluginID: pluginID, opID: opID) else {
            NSLog("NemoLoop plugin: unknown op \(pluginID).\(opID)")
            return false
        }
        op.perform()
        return true
    }
}
