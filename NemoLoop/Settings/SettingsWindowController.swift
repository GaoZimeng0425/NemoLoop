// NemoLoop/Settings/SettingsWindowController.swift
import AppKit
import Luminare
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var windowController: NSWindowController?

    func show(store: SliceStore) {
        if let existing = windowController {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = LuminareWindow {
            SettingsView(store: store)
        }
        window.title = "NemoLoop Settings"
        window.setContentSize(NSSize(width: 480, height: 460))
        window.delegate = self
        window.center()

        let wc = NSWindowController(window: window)
        self.windowController = wc

        NSApp.setActivationPolicy(.regular)
        wc.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        windowController = nil
        NSApp.setActivationPolicy(.accessory)
    }
}
