import Foundation

struct SliceConfig: Codable, Equatable {
    static let wedgeCount = 6
    var slots: [SlotEntry]

    init(slots: [SlotEntry]) {
        var s = Array(slots.prefix(Self.wedgeCount))
        while s.count < Self.wedgeCount { s.append(SlotEntry()) }
        self.slots = s
    }

    static var empty: SliceConfig { SliceConfig(slots: []) }
}
