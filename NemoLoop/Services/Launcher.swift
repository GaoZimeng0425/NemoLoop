// NemoLoop/Services/Launcher.swift
import AppKit

enum Launcher {
    static func launch(url: URL) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if let error { LogService.error("launch failed for \(url.path): \(error)", category: "Launcher") }
        }
    }

    /// Runs any slot action: apps launch, folders open in Finder, plugin ops
    /// fire through the registry. A whole-plugin blade released without dwell
    /// runs its first configured child op. The registry is injectable purely
    /// for tests; production callers ride `.shared`.
    @MainActor
    static func run(_ action: SlotAction,
                    children: [SlotAction] = [],
                    registry: PluginRegistry = .shared) {
        switch action {
        case .app(let url):
            launch(url: url)
        case .folder(let url):
            NSWorkspace.shared.open(url)
        case .plugin:
            guard let first = children.first, case let .pluginOp(pluginID, opID) = first else {
                LogService.info("plugin blade released with no ops — nothing to run", category: "Launcher")
                return
            }
            registry.perform(pluginID: pluginID, opID: opID)
        case .pluginOp(let pluginID, let opID):
            registry.perform(pluginID: pluginID, opID: opID)
        }
    }

    /// Brings a running app forward the way a Dock click does. `NSRunningApplication
    /// .activate()` alone leaves minimized windows in the Dock; openApplication on the
    /// running instance re-delivers the reopen event, which restores them.
    static func switchTo(app: NSRunningApplication) {
        guard let url = app.bundleURL else {
            if !app.activate() {
                LogService.error("activate failed for \(app.localizedName ?? app.bundleIdentifier ?? "?")", category: "Launcher")
            }
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if let error {
                LogService.error("switch to \(url.lastPathComponent) failed (\(error)); falling back to activate", category: "Launcher")
                Task { @MainActor in _ = app.activate() }
            }
        }
    }
}
