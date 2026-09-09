// NemoLoop/Services/Launcher.swift
import AppKit

enum Launcher {
    static func launch(url: URL) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if let error { NSLog("NemoLoop launch failed for \(url.path): \(error)") }
        }
    }

    /// Runs any slot action: apps launch, folders open in Finder, system
    /// actions fire.
    static func run(_ action: SlotAction) {
        switch action {
        case .app(let url):
            launch(url: url)
        case .folder(let url):
            NSWorkspace.shared.open(url)
        case .system(let system):
            system.perform()
        case .plugin, .pluginOp:
            // Plugin execution arrives with the registry in a later task; no
            // UI can produce these actions yet.
            break
        }
    }

    /// Brings a running app forward the way a Dock click does. `NSRunningApplication
    /// .activate()` alone leaves minimized windows in the Dock; openApplication on the
    /// running instance re-delivers the reopen event, which restores them.
    static func switchTo(app: NSRunningApplication) {
        guard let url = app.bundleURL else {
            if !app.activate() {
                NSLog("NemoLoop activate failed for \(app.localizedName ?? app.bundleIdentifier ?? "?")")
            }
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if let error {
                NSLog("NemoLoop switch to \(url.lastPathComponent) failed (\(error)); falling back to activate")
                Task { @MainActor in _ = app.activate() }
            }
        }
    }
}
