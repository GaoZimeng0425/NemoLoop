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
}
