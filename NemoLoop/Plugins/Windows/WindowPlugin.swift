// NemoLoop/Plugins/Windows/WindowPlugin.swift
import AppKit
import SwiftUI

/// Window-management plugin: 14 static ops over the focused window —
/// snap regions (pure geometry from WindowRegion), minimize, and a
/// fullscreen toggle. Opt-in (no legacy slots to serve); needsAuth until
/// the user grants Accessibility (the settings card carries the Grant
/// button — triggering ungranted ops stays silent per the spec).
@MainActor
final class WindowPlugin: NemoPlugin {
    static let pluginID = "windows"

    private let service: any WindowServicing

    init(service: (any WindowServicing)? = nil) {
        // nil-default + ?? : MainActor-isolated default args don't compile
        // (same constraint documented in ChainPlugin).
        self.service = service ?? AccessibilityWindowService()
    }

    let id = WindowPlugin.pluginID
    let displayName = "Windows"
    let symbolName = "rectangle.split.2x2"
    let summary = "Snap the focused window to halves, thirds, and quarters — plus maximize, minimize, and fullscreen."
    var status: PluginStatus { service.isTrusted() ? .ready : .needsAuth }
    let isEnabledByDefault = false

    var configSections: AnyView? { AnyView(WindowConfigSection(service: service)) }

    var operations: [any PluginOp] {
        WindowRegion.allCases.map { RegionOp(region: $0, service: service) }
            + [MinimizeOp(service: service), FullscreenOp(service: service)]
    }

    // MARK: - Ops

    struct RegionOp: @MainActor PluginOp {
        let region: WindowRegion
        let service: any WindowServicing
        var id: String { region.rawValue }
        var displayName: String { region.displayName }
        var symbolName: String { region.symbolName }

        func perform() {
            guard service.isTrusted() else {
                NSLog("NemoLoop windows: \(region.rawValue) skipped — Accessibility not granted")
                return
            }
            guard let windowFrame = service.focusedWindowFrame() else {
                NSLog("NemoLoop windows: \(region.rawValue) skipped — no focused window")
                return
            }
            guard let screen = Self.screen(containing: windowFrame) else {
                NSLog("NemoLoop windows: \(region.rawValue) skipped — no screen for window")
                return
            }
            _ = service.setFrame(region.targetFrame(in: screen.visibleFrame))
        }

        /// The window's center picks the screen (a straddling window snaps
        /// against the screen holding its center). nil only in a session
        /// with no screens at all.
        static func screen(containing frame: CGRect) -> NSScreen? {
            let center = CGPoint(x: frame.midX, y: frame.midY)
            return NSScreen.screens.first { NSPointInRect(center, $0.frame) }
                ?? NSScreen.main
                ?? NSScreen.screens.first
        }
    }

    struct MinimizeOp: @MainActor PluginOp {
        let id = "minimize"
        let displayName = "Minimize"
        let symbolName = "minus"
        let service: any WindowServicing
        func perform() {
            guard service.isTrusted() else {
                NSLog("NemoLoop windows: minimize skipped — Accessibility not granted")
                return
            }
            _ = service.setMinimized()
        }
    }

    struct FullscreenOp: @MainActor PluginOp {
        let id = "toggleFullscreen"
        let displayName = "Toggle Fullscreen"
        let symbolName = "arrow.up.backward.and.arrow.down.forward"
        let service: any WindowServicing
        func perform() {
            guard service.isTrusted() else {
                NSLog("NemoLoop windows: fullscreen skipped — Accessibility not granted")
                return
            }
            _ = service.toggleFullscreen()
        }
    }
}
