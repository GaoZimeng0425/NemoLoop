import Foundation

struct SliceConfig: Codable, Equatable {
    static let wedgeCount = 6
    var actions: [SlotAction?]

    init(actions: [SlotAction?]) {
        var a = Array(actions.prefix(Self.wedgeCount))
        while a.count < Self.wedgeCount { a.append(nil) }
        self.actions = a
    }

    static var empty: SliceConfig { SliceConfig(actions: []) }
}
