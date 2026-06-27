// NemoLoop/NemoLoopApp.swift
import SwiftUI

@main
struct NemoLoopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("NemoLoop", systemImage: "circle.grid.cross") {
            SettingsLink { Text("Settings…") }
            Divider()
            Button("Quit NemoLoop") { NSApplication.shared.terminate(nil) }
        }
        Settings {
            SettingsView(store: appDelegate.sliceStore)
        }
    }
}
