import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class SliceStore {
    private static let entriesKey = "nemoloop.slotEntries"
    /// v2 stored bare `SlotAction?`s under this key; migrated to entries.
    private static let actionsKey = "nemoloop.slotActions"
    /// v1 stored bare app URLs under this key; migrated to `.app` actions.
    private static let legacySlotsKey = "nemoloop.sliceConfig"
    private let defaults: UserDefaults

    /// v2 payload shape: a SliceConfig whose only field was `actions`.
    private struct V2Config: Codable { var actions: [SlotAction?] }

    var config: SliceConfig {
        didSet { persist(); rebuildIcons() }
    }

    /// Cached file icons, rebuilt only when `config` changes. `NSWorkspace.icon(forFile:)`
    /// returns a new `NSImage` on every call, so resolving icons inside `RingView.body`
    /// gave every render a fresh image identity — turning each hover-driven re-evaluation
    /// into an animated icon swap (the visible "all icons flicker" on wedge crossings).
    /// Caching keeps icon identity stable across re-renders so only the highlighted wedge animates.
    private(set) var icons: [NSImage?] = []
    /// Sub-action icons per slot, parallel to `icons` — feeds the dealt-out sub-wheel.
    private(set) var childIcons: [[NSImage?]] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.entriesKey),
           let decoded = try? JSONDecoder().decode(SliceConfig.self, from: data) {
            self.config = decoded
        } else if let data = defaults.data(forKey: Self.actionsKey),
                  let v2 = try? JSONDecoder().decode(V2Config.self, from: data) {
            self.config = SliceConfig(slots: v2.actions.map { SlotEntry(action: $0) })
        } else if let data = defaults.data(forKey: Self.legacySlotsKey),
                  let urls = try? JSONDecoder().decode([URL?].self, from: data) {
            self.config = SliceConfig(slots: urls.map { SlotEntry(action: $0.map(SlotAction.app)) })
        } else {
            self.config = .empty
        }
        rebuildIcons()
    }

    func setAction(_ action: SlotAction?, at index: Int) {
        guard config.slots.indices.contains(index) else { return }
        config.slots[index].action = action
    }

    func addChild(_ child: SlotAction, at index: Int) {
        guard config.slots.indices.contains(index),
              config.slots[index].children.count < SlotEntry.maxChildren else { return }
        config.slots[index].children.append(child)
    }

    func removeChild(at index: Int, offset: Int) {
        guard config.slots.indices.contains(index),
              config.slots[index].children.indices.contains(offset) else { return }
        config.slots[index].children.remove(at: offset)
    }

    func icon(at index: Int) -> NSImage? {
        icons.indices.contains(index) ? icons[index] : nil
    }

    /// The cached icon for one action: file icons for apps and folders, a
    /// symbol-drawn plate for system actions.
    static func icon(for action: SlotAction) -> NSImage {
        switch action {
        case .app(let url), .folder(let url):
            return NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
        case .system(let system):
            return system.symbolImage
        }
    }

    private func rebuildIcons() {
        icons = config.slots.map { $0.action.map(Self.icon(for:)) }
        childIcons = config.slots.map { $0.children.map(Self.icon(for:)) }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: Self.entriesKey)
    }
}

extension SystemAction {
    /// Monochrome symbol drawn at app-icon size, tinted systemGray so it reads
    /// on both the near-white card stock and the dark charcoal one.
    var symbolImage: NSImage {
        let size = NSSize(width: 32, height: 32)
        let img = NSImage(size: size)
        img.lockFocus()
        defer { img.unlockFocus() }
        guard let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: displayName) else {
            return img
        }
        var configured = base.withSymbolConfiguration(.init(pointSize: 22, weight: .medium))
        configured = configured?.withSymbolConfiguration(.init(paletteColors: [.systemGray]))
        configured?.draw(in: NSRect(origin: .zero, size: size),
                         from: .zero, operation: .sourceOver, fraction: 1,
                         respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
        return img
    }
}
