// NemoLoopTests/ToastWindowControllerTests.swift
import Testing
import Foundation
import CoreGraphics
@testable import NemoLoop

struct ToastWindowControllerTests {
    @Test func centersHorizontallyAboveBottom() {
        let frame = ToastWindowController.toastFrame(
            contentSize: NSSize(width: 200, height: 44),
            in: CGRect(x: 0, y: 0, width: 1000, height: 800))
        #expect(frame == NSRect(x: 400, y: 72, width: 200, height: 44))
    }

    @Test func respectsNonZeroScreenOrigin() {
        // Secondary screens left of the primary have negative minX.
        let frame = ToastWindowController.toastFrame(
            contentSize: NSSize(width: 200, height: 44),
            in: CGRect(x: -1440, y: 0, width: 1440, height: 900))
        #expect(frame.origin.x == CGFloat(-1440 + (1440 - 200) / 2))
        #expect(frame.origin.y == 72)
    }

    @Test func usesContentHeight() {
        let frame = ToastWindowController.toastFrame(
            contentSize: NSSize(width: 300, height: 50),
            in: CGRect(x: 0, y: 0, width: 1000, height: 800))
        #expect(frame.height == 50)
    }
}
