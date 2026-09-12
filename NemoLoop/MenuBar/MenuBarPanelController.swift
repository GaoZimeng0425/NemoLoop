// NemoLoop/MenuBar/MenuBarPanelController.swift
import AppKit
import SwiftUI

/// The menu-bar entry point: a status item plus a custom pop-up panel. This
/// replaces the old `MenuBarExtra(.menu)` two-button scene — the SwiftUI scene
/// couldn't force the Light/Dark theme (three-tier appearance broke), couldn't
/// take real content styling, and couldn't dismiss itself after an action.
/// Panel recipe mirrors the proven `RingPanel`: borderless, `.popUpMenu` level,
/// `nonactivatingPanel` (never steals focus from the frontmost app).
@MainActor
final class MenuBarPanelController {
    private final class Panel: NSPanel {
        var onClose: (() -> Void)?

        init(contentRect: NSRect) {
            super.init(contentRect: contentRect,
                       styleMask: [.borderless, .nonactivatingPanel],
                       backing: .buffered,
                       defer: false)
        }

        override var canBecomeKey: Bool { true }

        override func cancelOperation(_ sender: Any?) {
            onClose?()   // Esc
        }
    }

    private let sliceStore: SliceStore
    private let runningApps: RunningAppsService
    private let appearanceStore: AppearanceStore
    // Owned by AppDelegate; closures keep this class decoupled from them.
    private let isRingVisible: () -> Bool
    private let summonRing: () -> Void
    private let releaseRing: () -> Void
    private let openSettings: () -> Void

    private var statusItem: NSStatusItem?
    private var panel: Panel?
    private var outsideClickMonitor: Any?

    init(sliceStore: SliceStore,
         runningApps: RunningAppsService,
         appearanceStore: AppearanceStore,
         isRingVisible: @escaping () -> Bool,
         summonRing: @escaping () -> Void,
         releaseRing: @escaping () -> Void,
         openSettings: @escaping () -> Void) {
        self.sliceStore = sliceStore
        self.runningApps = runningApps
        self.appearanceStore = appearanceStore
        self.isRingVisible = isRingVisible
        self.summonRing = summonRing
        self.releaseRing = releaseRing
        self.openSettings = openSettings
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(named: "MenubarLogo")
            // The catalog declares template intent; assert it here too so a named
            // lookup that bypasses the catalog still renders as a maskable glyph.
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(statusItemClicked)
        }
        statusItem = item
    }

    var isPanelVisible: Bool { panel != nil }

    @objc private func statusItemClicked() {
        if panel != nil { hidePanel() } else { showPanel() }
    }

    // MARK: - Panel lifecycle

    private func showPanel() {
        hidePanel()

        // Snapshot at open: rows must not reshuffle while the user is reading
        // or mid-drag on the ring button (same contract as the ring's summon).
        let apps = runningApps.snapshot(limit: RingSummoner.maxRunningAppWedges)
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        let view = MenuBarPanelView(
            running: apps,
            frontmostPID: frontmostPID,
            sliceStore: sliceStore,
            isRingVisible: { [weak self] in self?.isRingVisible() ?? false },
            onRingPress: { [weak self] in self?.summonRing() },
            onRingRelease: { [weak self] in self?.releaseRing() },
            onOpenApp: { [weak self] app in
                self?.hidePanel()
                Launcher.switchTo(app: app.app)
            },
            onRunPinned: { [weak self] action, children in
                self?.hidePanel()
                // Children must ride along: a whole-plugin mount releases
                // through Launcher's first-configured-child op, so without
                // them the pinned row would only log and do nothing.
                Launcher.run(action, children: children)
            },
            onOpenSettings: { [weak self] in
                self?.hidePanel()
                self?.openSettings()
            },
            onQuit: { NSApp.terminate(nil) },
            onHeightChange: { [weak self] height in self?.resizePanel(to: height) })

        let host = NSHostingView(rootView: view)
        let size = NSSize(width: MenuBarPanelView.width,
                          height: MenuBarPanelView.contentHeight(rowCount: apps.count))
        host.frame = NSRect(origin: .zero, size: size)

        let panel = Panel(contentRect: NSRect(origin: .zero, size: size))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Theme BEFORE hosting — SwiftUI's colorScheme (and so RingPalette inside
        // the view) derives from the panel's effective appearance.
        panel.appearance = appearanceStore.appearance.nsAppearance
        panel.onClose = { [weak self] in self?.hidePanel() }
        panel.contentView = host
        position(panel: panel)
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel

        // Click-outside close. Global monitor only sees events delivered to
        // OTHER apps (our panel's own clicks never reach it); clicks that land
        // on the status button must pass through so the toggle action decides.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel else { return }
                let location = event.locationInWindow // screen coords on global monitors
                if let button = self.statusItem?.button, let window = button.window,
                   window.convertToScreen(button.bounds).contains(location) {
                    return
                }
                if !panel.frame.contains(location) {
                    self.hidePanel()
                }
            }
        }
    }

    private func hidePanel() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
        outsideClickMonitor = nil
        panel?.orderOut(nil)
        panel = nil
    }

    /// Keeps the top edge pinned (panel hangs from the status item), so a
    /// section switch to more/fewer rows grows downward.
    private func resizePanel(to height: CGFloat) {
        guard let panel else { return }
        var frame = panel.frame
        frame.origin.y += frame.height - height
        frame.size.height = height
        panel.setFrame(frame, display: true)
    }

    private func position(panel: Panel) {
        let width = panel.frame.width
        let height = panel.frame.height

        // Anchor under the icon USING THE WINDOW THAT RECEIVED THE CLICK.
        // statusItemClicked runs while NSApp.currentEvent is the click, and
        // event.window is the status-item window at its true position —
        // button.window can't be trusted here: macOS relocates it to the
        // newly-active screen asynchronously (wrong screen when clicked on a
        // secondary display), and Bartender-style managers park it offscreen.
        var iconRect = NSRect.zero
        if let clickWindow = NSApp.currentEvent?.window {
            iconRect = clickWindow.frame
        } else if let button = statusItem?.button, let buttonWindow = button.window {
            iconRect = buttonWindow.convertToScreen(button.bounds)
        }

        // The icon's own screen is the one clicked. Parked/hidden items sit
        // at a large negative x (bar overflow, Bartender) — no screen will
        // claim them and we fall back to the cursor screen's corner.
        let iconScreen = NSScreen.screens.first {
            $0.frame.contains(NSPoint(x: iconRect.midX, y: iconRect.midY))
        }
        guard iconRect.origin.x >= 0, let iconScreen else {
            let cursor = NSEvent.mouseLocation
            let cursorScreen = NSScreen.screens.first {
                NSMouseInRect(cursor, $0.frame, false)
            } ?? NSScreen.main ?? NSScreen.screens[0]
            let visible = cursorScreen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: visible.maxX - width - 8,
                                         y: visible.maxY - height - 4))
            return
        }

        let visible = iconScreen.visibleFrame
        let x = iconRect.midX - width / 2
        let y = iconRect.minY - height - 6
        panel.setFrameOrigin(NSPoint(
            x: max(visible.minX + 4, min(x, visible.maxX - width - 4)),
            y: y))
    }
}
