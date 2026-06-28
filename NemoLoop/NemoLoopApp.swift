// NemoLoop/NemoLoopApp.swift
import KeyboardShortcuts
import SwiftUI

@main
struct NemoLoopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("NemoLoop", systemImage: "circle.grid.cross") {
            if KeyboardShortcuts.getShortcut(for: .summonRing) == nil {
                Text("Set a summon hotkey in Settings →")
                Divider()
            }
            Button("Settings…") {
                appDelegate.settingsWindowController.show(store: appDelegate.sliceStore)
            }
            Divider()
            Button("Quit NemoLoop") { NSApplication.shared.terminate(nil) }
        }
    }
}
