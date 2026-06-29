import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class SliceStore {
    private static let defaultsKey = "nemoloop.sliceConfig"
    private let defaults: UserDefaults

    var config: SliceConfig {
        didSet { persist(); rebuildIcons() }
    }

    /// Cached file icons, rebuilt only when `config` changes. `NSWorkspace.icon(forFile:)`
    /// returns a new `NSImage` on every call, so resolving icons inside `RingView.body`
    /// gave every render a fresh image identity — turning each hover-driven re-evaluation
    /// into an animated icon swap (the visible "all icons flicker" on wedge crossings).
    /// Caching keeps icon identity stable across re-renders so only the highlighted wedge animates.
    private(set) var icons: [NSImage?] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(SliceConfig.self, from: data) {
            self.config = decoded
        } else {
            self.config = .empty
        }
        rebuildIcons()
    }

    func setSlot(_ url: URL?, at index: Int) {
        guard config.slots.indices.contains(index) else { return }
        config.slots[index] = url
    }

    func icon(at index: Int) -> NSImage? {
        icons.indices.contains(index) ? icons[index] : nil
    }

    private func rebuildIcons() {
        icons = config.slots.map { url in
            url.map { NSWorkspace.shared.icon(forFile: $0.path(percentEncoded: false)) }
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
