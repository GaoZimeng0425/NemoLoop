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

    @Test func configSectionsExposesTheGrantFlow() {
        let plugin = WindowPlugin(service: RecordingWindowService())
        #expect(plugin.configSections != nil)
    }
}

/// The AX↔AppKit y-flip is the only coordinate math in the real service
/// (the rest is guarded by RecordingWindowService tests) — pinned here
/// against concrete numbers, pure, no screens required.
@MainActor
struct WindowCoordinateFlipTests {
    // The primary screen's top edge in AppKit space (screens.first.frame.maxY
    // in production): a 900pt-tall primary, origin (0,0).
    private let primaryMaxY: CGFloat = 900

    @Test func axTopLeftOriginFlipsToAppKitBottomLeft() {
        // AX y=100 is 100pt BELOW the primary top; the rect's AppKit top
        // edge is 900−100=800, so its bottom-left origin is 750.
        let ax = CGRect(x: 100, y: 100, width: 200, height: 50)
        #expect(AccessibilityWindowService.appKitFrame(fromAX: ax, primaryMaxY: primaryMaxY)
                == CGRect(x: 100, y: 750, width: 200, height: 50))
    }

    @Test func appKitFrameFlipsBackToAX() {
        // Bottom-left origin 750 means the top edge is 800, i.e. 100pt
        // below the primary top in AX's top-down space.
        let appKit = CGRect(x: 100, y: 750, width: 200, height: 50)
        #expect(AccessibilityWindowService.axFrame(fromAppKit: appKit, primaryMaxY: primaryMaxY)
                == CGRect(x: 100, y: 100, width: 200, height: 50))
    }

    @Test func flipIsInvolutionOnRepresentativeFrames() {
        // appKitFrame(axFrame(f)) == f and back, across plain, side-offset,
        // and off-primary-negative frames.
        let frames = [
            CGRect(x: 0, y: 0, width: 1440, height: 900),
            CGRect(x: 200, y: 0, width: 620, height: 900),
            CGRect(x: 820, y: 225.5, width: 620, height: 450),
            CGRect(x: -500, y: 1200, width: 400, height: 300),
        ]
        for frame in frames {
            #expect(AccessibilityWindowService.axFrame(fromAppKit:
                        AccessibilityWindowService.appKitFrame(fromAX: frame, primaryMaxY: primaryMaxY),
                        primaryMaxY: primaryMaxY) == frame)
            #expect(AccessibilityWindowService.appKitFrame(fromAX:
                        AccessibilityWindowService.axFrame(fromAppKit: frame, primaryMaxY: primaryMaxY),
                        primaryMaxY: primaryMaxY) == frame)
        }
    }

    @Test func flipPreservesSize() {
        let ax = CGRect(x: 100, y: 100, width: 200, height: 50)
        let flipped = AccessibilityWindowService.appKitFrame(fromAX: ax, primaryMaxY: primaryMaxY)
        #expect(flipped.width == ax.width)
        #expect(flipped.height == ax.height)
    }
}
