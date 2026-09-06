import SwiftUI
import Testing
@testable import NemoLoop

struct RingPaletteTests {
    @Test func palettePicksByScheme() {
        #expect(RingPalette.palette(for: .light) == RingPalette.light)
        #expect(RingPalette.palette(for: .dark) == RingPalette.dark)
    }

    @Test func lightAndDarkCardsDiffer() {
        #expect(RingPalette.light.glassTint != RingPalette.dark.glassTint)
        #expect(RingPalette.light.dividerColor != RingPalette.dark.dividerColor)
    }

    @Test func lightPaletteKeepsVerifiedValues() {
        // Regression guard: light = the accepted v6.1 card stock, byte for byte.
        #expect(RingPalette.light.glassTint == Color(red: 0.95, green: 0.94, blue: 0.92))
        #expect(RingPalette.light.dividerColor == Color.black.opacity(0.12))
    }

    @Test func highlightIsWhiteBrightenPerScheme() {
        // Hover = white brighten (the accent gradient mixed the system accent with
        // blue — orange + blue = mud on the light stock). Opacity is per scheme:
        // near-opaque on near-white stock, a sheen on charcoal.
        #expect(RingPalette.light.highlightFill == Color.white.opacity(0.95))
        #expect(RingPalette.dark.highlightFill == Color.white.opacity(0.32))
    }
}
