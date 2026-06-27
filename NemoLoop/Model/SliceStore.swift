import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class SliceStore {
    private static let defaultsKey = "nemoloop.sliceConfig"
    private let defaults: UserDefaults

    var config: SliceConfig {
        didSet { persist() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(SliceConfig.self, from: data) {
            self.config = decoded
        } else {
            self.config = .empty
        }
    }

    func setSlot(_ url: URL?, at index: Int) {
        guard config.slots.indices.contains(index) else { return }
        config.slots[index] = url
    }

    func icon(at index: Int) -> NSImage? {
        guard config.slots.indices.contains(index), let url = config.slots[index] else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
