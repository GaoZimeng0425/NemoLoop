import Testing
import Foundation
import AppKit
@testable import NemoLoop

@MainActor
struct WindowLayoutTests {
    // AppKit coords: origin bottom-left. Three representative visibleFrames:
    // plain full screen, side-Dock offset (minX>0), bottom-offset variant.
    private let plain = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let sideDock = CGRect(x: 200, y: 0, width: 1240, height: 900)

    @Test func caseCountAndOrderMatchesSpec() {
        #expect(WindowRegion.allCases.count == 12)
        #expect(WindowRegion.allCases.first == .halfLeft)
        #expect(WindowRegion.allCases.last == .maximize)
    }

    @Test func halves() {
        #expect(WindowRegion.halfLeft.targetFrame(in: plain)
                == CGRect(x: 0, y: 0, width: 720, height: 900))
        #expect(WindowRegion.halfRight.targetFrame(in: plain)
                == CGRect(x: 720, y: 0, width: 720, height: 900))
        #expect(WindowRegion.halfTop.targetFrame(in: plain)
                == CGRect(x: 0, y: 450, width: 1440, height: 450))
        #expect(WindowRegion.halfBottom.targetFrame(in: plain)
                == CGRect(x: 0, y: 0, width: 1440, height: 450))
    }

    @Test func thirds() {
        #expect(WindowRegion.thirdLeft.targetFrame(in: plain)
                == CGRect(x: 0, y: 0, width: 480, height: 900))
        #expect(WindowRegion.thirdCenter.targetFrame(in: plain)
                == CGRect(x: 480, y: 0, width: 480, height: 900))
        #expect(WindowRegion.thirdRight.targetFrame(in: plain)
                == CGRect(x: 960, y: 0, width: 480, height: 900))
        // Boundary sanity on the side-Dock offset screen: x-offset shifts thirds,
        // widths still thirds of 1240.
        #expect(WindowRegion.thirdRight.targetFrame(in: sideDock)
                == CGRect(x: 200 + 2 * 1240.0 / 3.0, y: 0, width: 1240.0 / 3.0, height: 900))
    }

    @Test func quadrants() {
        #expect(WindowRegion.quadrantTopLeft.targetFrame(in: plain)
                == CGRect(x: 0, y: 450, width: 720, height: 450))
        #expect(WindowRegion.quadrantTopRight.targetFrame(in: plain)
                == CGRect(x: 720, y: 450, width: 720, height: 450))
        #expect(WindowRegion.quadrantBottomLeft.targetFrame(in: plain)
                == CGRect(x: 0, y: 0, width: 720, height: 450))
        #expect(WindowRegion.quadrantBottomRight.targetFrame(in: plain)
                == CGRect(x: 720, y: 0, width: 720, height: 450))
    }

    @Test func maximizeIsIdentity() {
        #expect(WindowRegion.maximize.targetFrame(in: plain) == plain)
        #expect(WindowRegion.maximize.targetFrame(in: sideDock) == sideDock)
    }

    @Test func sideDockOffsetsShiftHalves() {
        // Snapping is relative to the visibleFrame, not the screen origin.
        #expect(WindowRegion.halfLeft.targetFrame(in: sideDock)
                == CGRect(x: 200, y: 0, width: 620, height: 900))
        #expect(WindowRegion.halfRight.targetFrame(in: sideDock)
                == CGRect(x: 820, y: 0, width: 620, height: 900))
    }

    @Test func metadataCompleteAndSymbolsResolve() {
        // Every region must have a non-empty name and an SF Symbol that
        // actually resolves on this SDK — a typo'd symbol renders blank
        // blades with no other failure signal.
        for region in WindowRegion.allCases {
            #expect(!region.displayName.isEmpty)
            let image = NSImage(systemSymbolName: region.symbolName, accessibilityDescription: nil)
            #expect(image != nil, "SF Symbol missing: \(region.symbolName)")
        }
    }
}
