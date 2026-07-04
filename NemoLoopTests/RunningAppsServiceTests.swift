import Testing
import Foundation
@testable import NemoLoop

struct RunningAppsServiceTests {
    // Items are their own pid for these tests.
    let id: (pid_t) -> pid_t = { $0 }

    @Test func mruAppsComeFirstInMRUOrder() {
        let result = RunningAppsService.order([1, 2, 3, 4], mru: [3, 1], limit: 10, id: id)
        // 3,1 known (MRU order) then 2,4 unknown (system order)
        #expect(result == [3, 1, 2, 4])
    }

    @Test func allUnknownKeepsSystemOrder() {
        let result = RunningAppsService.order([5, 6, 7], mru: [], limit: 10, id: id)
        #expect(result == [5, 6, 7])
    }

    @Test func limitTruncatesAfterOrdering() {
        let result = RunningAppsService.order([1, 2, 3, 4, 5], mru: [5, 4], limit: 3, id: id)
        #expect(result == [5, 4, 1])
    }

    @Test func staleMRUEntriesForGoneAppsAreIgnored() {
        // pid 9 is in MRU but no longer running → must not appear.
        let result = RunningAppsService.order([1, 2], mru: [9, 2], limit: 10, id: id)
        #expect(result == [2, 1])
    }
}
