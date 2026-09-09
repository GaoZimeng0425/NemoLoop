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
    /// Test-support: the defaults suite name this store was built over, so
    /// tests can reopen the same on-disk suite in a second store and verify
    /// persistence. `UserDefaults` can't be asked for its suite name back,
    /// hence the init parameter. nil on the standard-defaults production path.
    private(set) var testingSuiteName: String?

    init(defaults: UserDefaults = .standard, testingSuiteName: String? = nil) {
        self.defaults = defaults
        self.testingSuiteName = testingSuiteName
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
        // Changing the slot's action type changes its child fan-out capacity —
        // a slot stepping down from a whole-plugin mount (8) to a manual slot
        // (4, or an empty slot) must shed the extras, keeping the earliest
        // children since those were added first.
        let limit = SlotEntry.childLimit(for: action)
        if config.slots[index].children.count > limit {
            config.slots[index].children = Array(config.slots[index].children.prefix(limit))
        }
    }

    /// Whole-plugin mount: the blade takes the plugin itself as its action
    /// and its children become the plugin's full op list, in plugin order,
    /// truncated to the whole-plugin child limit. Registry-injectable so
    /// tests can mount stub plugins without touching the shared registry.
    func attachWholePlugin(_ pluginID: String, at index: Int, registry: PluginRegistry = .shared) {
        guard config.slots.indices.contains(index), let plugin = registry.plugin(id: pluginID) else { return }
        let ops = plugin.operations.prefix(SlotEntry.childLimit(for: .plugin(pluginID)))
        config.slots[index].action = .plugin(pluginID)
        config.slots[index].children = ops.map { .pluginOp(pluginID: pluginID, opID: $0.id) }
    }

    /// Sub-actions hang off a CONFIGURED slot — the parent must have an action
    /// before it can take children, so a sub-wheel never appears on an empty blade.
    func addChild(_ child: SlotAction, at index: Int) {
        guard config.slots.indices.contains(index),
              config.slots[index].action != nil,
              config.slots[index].children.count < SlotEntry.childLimit(for: config.slots[index].action) else { return }
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
    /// symbol-drawn plate for plugin references.
    static func icon(for action: SlotAction) -> NSImage {
        switch action {
        case .app(let url), .folder(let url):
            return NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
        case .plugin(let id):
            let plugin = PluginRegistry.shared.plugin(id: id)
            return SymbolPlate.image(symbolName: plugin?.symbolName ?? "puzzlepiece",
                                     label: plugin?.displayName ?? id)
        case .pluginOp:
            let symbol = ActionResolver.symbolName(for: action) ?? "circle.dashed"
            return SymbolPlate.image(symbolName: symbol,
                                     label: ActionResolver.name(for: action))
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

    /// Test-support: `config` mutations already persist via `didSet`; this
    /// hook lets a test pin the flush explicitly before reopening the same
    /// defaults suite in a second store.
    @inline(__always) func persistNowForTesting() { persist() }
}
