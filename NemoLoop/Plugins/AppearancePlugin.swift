// NemoLoop/Plugins/AppearancePlugin.swift
import Foundation

/// Single-operation plugin: one-tap Light/Dark toggle. Goes through System
/// Events AppleScript — the first trigger raises a one-time "Automation"
/// authorization prompt (TCC); the ring's own three-way theme is unaffected.
@MainActor
final class AppearancePlugin: @MainActor NemoPlugin {
    private static let script =
        "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"

    private let runner: any ShellRunning

    init(runner: any ShellRunning = ProcessShellRunner()) { self.runner = runner }

    let id = "appearance"
    let displayName = "Appearance"
    let symbolName = "circle.lefthalf.filled"
    let summary = "One-tap Light/Dark system appearance toggle."

    struct Op: @MainActor PluginOp {
        let id = "toggleDarkMode"
        let displayName = "Toggle Appearance"
        let symbolName = "circle.lefthalf.filled"
        let runner: any ShellRunning
        func perform() {
            do { try runner.run(executable: "/usr/bin/osascript", arguments: ["-e", AppearancePlugin.script]) }
            catch { LogService.error("appearance toggle failed: \(error)", category: "Appearance") }
        }
    }

    var operations: [any PluginOp] { [Op(runner: runner)] }
    var status: PluginStatus { .ready }
}
