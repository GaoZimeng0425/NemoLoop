import Testing
import Foundation
@testable import NemoLoop

struct SliceConfigTests {
    @Test func initPadsToSixSlots() {
        let c = SliceConfig(slots: [URL(filePath: "/Applications/Safari.app")])
        #expect(c.slots.count == 6)
        #expect(c.slots[0] == URL(filePath: "/Applications/Safari.app"))
        #expect(c.slots[5] == nil)
    }

    @Test func initTruncatesBeyondSix() {
        let urls = (0..<8).map { URL(filePath: "/A\($0).app") } as [URL?]
        #expect(SliceConfig(slots: urls).slots.count == 6)
    }

    @Test func codableRoundTrip() throws {
        var c = SliceConfig.empty
        c.slots[2] = URL(filePath: "/Applications/Notes.app")
        let data = try JSONEncoder().encode(c)
        let decoded = try JSONDecoder().decode(SliceConfig.self, from: data)
        #expect(decoded == c)
    }
}
