// NemoLoopTests/ScreenshotPluginTests.swift
import Testing
import Foundation
@testable import NemoLoop

@MainActor
struct ScreenshotPluginTests {
    @Test func singleOpMetadata() {
        let plugin = ScreenshotPlugin()
        #expect(plugin.id == "screenshot")
        #expect(plugin.operations.count == 1)
        let op = plugin.operations.first!
        #expect(op.id == "snipToClipboard")
        #expect(op.symbolName == "camera.viewfinder")
        #expect(plugin.status == .ready)   // screen-capture auth is only known at runtime; card badge renders ready
    }

    @Test func ocrEntryStillRoutesToOcrMode() {
        // SystemPlugin's ocr op semantics unchanged: handleOcrRequested is .ocr mode.
        #expect(OcrSessionController.CaptureMode.ocr.isOcrFlow)
        #expect(!OcrSessionController.CaptureMode.snip.isOcrFlow)
    }
}
