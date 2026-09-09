// NemoLoop/Settings/SettingsWindowController.swift
import AppKit
import Luminare
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var windowController: NSWindowController?
    private let chrome = SettingsChrome()

    /// Content widths of the settings window: without and with the Ring tab's
    /// inspector column. One source shared by the initial content size and
    /// `setInspectorLayout`, so the two can never disagree.
    private static let compactWidth: CGFloat = 680
    private static let inspectorWidth: CGFloat = 960

    func show(store: SliceStore, appearance: AppearanceStore) {
        NSApp.setActivationPolicy(.regular)

        if let existing = windowController {
            existing.window?.makeKeyAndOrderFront(nil)
            forceFrontmost()
            return
        }

        let window = LuminareWindow {
            SettingsView(store: store, chrome: self.chrome, appearance: appearance)
        }
        window.title = "Settings"
        // The pane header (current tab name) IS the title — the system title text
        // would draw a second, centered bar above it (LuminareWindow doesn't hide
        // it; its modal windows do).
        window.titleVisibility = .hidden
        // Size the window for the tab it OPENS on (Ring hosts the inspector
        // column) instead of popping in compact and animating wider on the
        // first appear. Set BEFORE the callback is wired so setup itself
        // notifies no one.
        chrome.inspectorVisible = SettingsView.initialTab == .ring
        window.setContentSize(NSSize(width: chrome.inspectorVisible ? Self.inspectorWidth : Self.compactWidth,
                                     height: 480))
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

        // Tab switches toggle the inspector column; the window follows with an
        // animated resize. Wired here (the chrome's construction site) once the
        // window exists for the callback to act on.
        chrome.inspectorDidChange = { [weak self] visible in
            self?.setInspectorLayout(visible)
        }

        wc.showWindow(nil)
        forceFrontmost()
    }

    /// Animates the window wider/narrower for the Ring tab's inspector column
    /// (0.25 s ease-in-out, matching the SwiftUI column animation). Top-left
    /// anchored so the window grows right, never drifts: AppKit frame origins
    /// sit at the BOTTOM-left, so the top edge is what must be held — origin.y
    /// is derived from `maxY` (equal to the old origin while the height is
    /// unchanged, and still correct if it ever isn't).
    func setInspectorLayout(_ visible: Bool) {
        guard let window = windowController?.window else { return }
        let width = visible ? Self.inspectorWidth : Self.compactWidth
        // Same-value assignments re-fire the chrome callback (didSet fires on
        // every assignment); a frame it already has needs no animation.
        guard window.frame.width != width else { return }
        let target = NSRect(x: window.frame.origin.x,
                            y: window.frame.maxY - window.frame.height,
                            width: width,
                            height: window.frame.height)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(target, display: true)
        }
    }

    /// The no-arg `NSApp.activate()` (macOS 14+) is cooperative: invoked from the
    /// menu bar while another app owns focus, it loses and the window opens behind
    /// that app. This show is always user-initiated, so a forceful raise is correct.
    private func forceFrontmost() {
        NSApp.activate(ignoringOtherApps: true)
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
