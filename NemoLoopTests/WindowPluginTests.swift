import Testing
import Foundation
import AppKit
@testable import NemoLoop

@MainActor
struct WindowPluginTests {
    @MainActor
    final class RecordingWindowService: WindowServicing {
        var trusted = true
        var windowFrame: CGRect?
        var setFrameCalls: [CGRect] = []
        var minimizeCalls = 0
        var fullscreenToggles = 0
        var promptCalls = 0
        func isTrusted() -> Bool { trusted }
        func promptForTrust() { promptCalls += 1 }
        func focusedWindowFrame() -> CGRect? { windowFrame }
        func setFrame(_ frame: CGRect) -> Bool { setFrameCalls.append(frame); return true }
        func setMinimized() -> Bool { minimizeCalls += 1; return true }
        func toggleFullscreen() -> Bool { fullscreenToggles += 1; return true }
    }

    /// A window centered on the test host's main screen — the region op must
    /// compute against that same screen's live visibleFrame, so both sides of
    /// the assertion derive from one source.
    private func centeredWindowFrame() -> CGRect {
        let visible = NSScreen.main!.visibleFrame
        return CGRect(x: visible.midX - 200, y: visible.midY - 150, width: 400, height: 300)
    }

    @Test func offersFourteenOpsWithRegionIdSpace() {
        let plugin = WindowPlugin(service: RecordingWindowService())
        #expect(plugin.id == "windows")
        #expect(plugin.operations.count == 14)
        #expect(plugin.operations.map(\.id).contains("halfLeft"))
        #expect(plugin.operations.map(\.id).contains("maximize"))
        #expect(plugin.operations.map(\.id).contains("minimize"))
        #expect(plugin.operations.map(\.id).contains("toggleFullscreen"))
        // Every op symbol resolves on this SDK (blank-blade guard, same as regions).
        for op in plugin.operations {
            #expect(NSImage(systemSymbolName: op.symbolName, accessibilityDescription: nil) != nil,
                    "SF Symbol missing: \(op.symbolName)")
        }
    }

    @Test func regionOpSnapsToWindowScreenVisibleFrame() throws {
        let service = RecordingWindowService()
        service.windowFrame = centeredWindowFrame()
        let plugin = WindowPlugin(service: service)

        let op = plugin.operations.first { $0.id == "halfLeft" }!
        op.perform()

        let expected = WindowRegion.halfLeft.targetFrame(in: NSScreen.main!.visibleFrame)
        #expect(service.setFrameCalls == [expected])
    }

    @Test func allRegionsRouteThroughSetFrame() throws {
        let service = RecordingWindowService()
        service.windowFrame = centeredWindowFrame()
        let plugin = WindowPlugin(service: service)
        let visible = NSScreen.main!.visibleFrame

        for region in WindowRegion.allCases {
            let op = plugin.operations.first { $0.id == region.rawValue }!
            op.perform()
        }
        #expect(service.setFrameCalls.count == 12)
        #expect(service.setFrameCalls == WindowRegion.allCases.map { $0.targetFrame(in: visible) })
    }

    @Test func untrustedTriggerIsSilentNoOp() {
        let service = RecordingWindowService()
        service.trusted = false
        service.windowFrame = centeredWindowFrame()
        let plugin = WindowPlugin(service: service)

        for op in plugin.operations { op.perform() }
        #expect(service.setFrameCalls.isEmpty)
        #expect(service.minimizeCalls == 0)
        #expect(service.fullscreenToggles == 0)
    }

    @Test func missingFocusedWindowIsSilentNoOp() {
        let service = RecordingWindowService()
        service.windowFrame = nil
        let plugin = WindowPlugin(service: service)

        plugin.operations.first { $0.id == "halfLeft" }!.perform()
        #expect(service.setFrameCalls.isEmpty)
    }

    @Test func minimizeAndFullscreenRouteToAttributes() {
        let service = RecordingWindowService()
        service.windowFrame = centeredWindowFrame()
        let plugin = WindowPlugin(service: service)

        plugin.operations.first { $0.id == "minimize" }!.perform()
        plugin.operations.first { $0.id == "toggleFullscreen" }!.perform()
        #expect(service.minimizeCalls == 1)
        #expect(service.fullscreenToggles == 1)
        #expect(service.setFrameCalls.isEmpty)
    }

    @Test func statusReflectsTrust() {
        let service = RecordingWindowService()
        let plugin = WindowPlugin(service: service)
        #expect(plugin.status == .ready)
        service.trusted = false
        #expect(plugin.status == .needsAuth)
    }

    @Test func disabledByDefault() {
        let registry = PluginRegistry(defaults: makeDefaults(),
                                      plugins: [WindowPlugin(service: RecordingWindowService())])
        #expect(!registry.isEnabled("windows"))
    }
}
