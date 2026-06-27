import Foundation

struct SliceConfig: Codable, Equatable {
    static let wedgeCount = 6
    var slots: [URL?]

    init(slots: [URL?]) {
        var s = Array(slots.prefix(Self.wedgeCount))
        while s.count < Self.wedgeCount { s.append(nil) }
        self.slots = s
    }

    static var empty: SliceConfig { SliceConfig(slots: []) }
}
