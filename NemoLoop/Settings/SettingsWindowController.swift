// NemoLoop/Settings/SettingsWindowController.swift
import AppKit
import Luminare
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var windowController: NSWindowController?
    private let chrome = SettingsChrome()

    func show(store: SliceStore) {
        NSApp.setActivationPolicy(.regular)

        if let existing = windowController {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        let window = LuminareWindow {
            SettingsView(store: store, chrome: self.chrome)
        }
        window.title = "NemoLoop Settings"
        window.setContentSize(NSSize(width: 680, height: 480))
        window.delegate = self
        window.center()

        // Sidebar collapse/expand button in the titlebar (leading, next to traffic lights).
        let toggle = NSTitlebarAccessoryViewController()
        toggle.layoutAttribute = .leading
        let host = NSHostingView(rootView: SidebarToggle(chrome: chrome))
        host.frame = NSRect(x: 0, y: 0, width: 40, height: 28)
        toggle.view = host
        window.addTitlebarAccessoryViewController(toggle)

        let wc = NSWindowController(window: window)
        self.windowController = wc

        wc.showWindow(nil)
        NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) {
        windowController = nil
        DispatchQueue.main.async { [weak self] in
            if self?.windowController == nil {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
