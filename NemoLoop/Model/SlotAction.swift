import Foundation

/// System-level actions a slot can run — the things that have no file to open.
/// UI-presentable metadata (label + symbol) lives here too: both the settings
/// pane and the pinned-row naming rules need it, and the strings are stable.
enum SystemAction: String, Codable, CaseIterable, Identifiable {
    case lockScreen
    case sleepDisplays
    case sleep
    case missionControl
    case ocr

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lockScreen: "Lock Screen"
        case .sleepDisplays: "Sleep Displays"
        case .sleep: "Sleep"
        case .missionControl: "Mission Control"
        case .ocr: "OCR"
        }
    }

    var symbolName: String {
        switch self {
        case .lockScreen: "lock.fill"
        case .sleepDisplays: "display"
        case .sleep: "moon.zzz"
        case .missionControl: "square.grid.3x3"
        case .ocr: "doc.text.viewfinder"
        }
    }
}

/// One ring slot: its primary action plus up to `childLimit(for:)` sub-actions
/// that the blade deals out on dwell — the cascading sub-wheel.
struct SlotEntry: Codable, Equatable {
    static let maxManualChildren = 4
    static let maxPluginChildren = 8
    /// Pre-plugin name for the manual cap; the settings UI and existing tests
    /// still read it (the plugin-aware UI lands in a later task).
    static let maxChildren = maxManualChildren

    var action: SlotAction?
    var children: [SlotAction] = []

    init(action: SlotAction? = nil, children: [SlotAction] = []) {
        self.action = action
        self.children = Array(children.prefix(Self.childLimit(for: action)))
    }

    /// Child fan-out capacity: a slot mounting a whole plugin widens to 8;
    /// everything else (including empty slots) stays at 4.
    static func childLimit(for action: SlotAction?) -> Int {
        if case .plugin = action { return maxPluginChildren }
        return maxManualChildren
    }
}

/// What a slot runs when triggered. Apps and folders carry their file URL;
/// system actions are named enum cases; plugin cases reference the plugin
/// registry by id (resolved in a later task).
enum SlotAction: Codable, Equatable {
    case app(URL)
    case folder(URL)
    case system(SystemAction)                       // removed in Task 4
    case plugin(String)
    case pluginOp(pluginID: String, opID: String)

    private enum CodingKeys: String, CodingKey {
        case app, folder, system, plugin, pluginOp
    }
    private enum SingleValueKeys: String, CodingKey { case _0 }
    private enum PluginOpKeys: String, CodingKey { case pluginID, opID }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Swift's synthesized format wraps every single-associated-value case
        // as {"case":{"_0":value}} — decode app/folder/system/plugin through
        // the nested _0; flat payloads are rejected.
        if container.contains(.app) {
            let nested = try container.nestedContainer(keyedBy: SingleValueKeys.self, forKey: .app)
            self = .app(try nested.decode(URL.self, forKey: ._0)); return
        }
        if container.contains(.folder) {
            let nested = try container.nestedContainer(keyedBy: SingleValueKeys.self, forKey: .folder)
            self = .folder(try nested.decode(URL.self, forKey: ._0)); return
        }
        if container.contains(.system) {
            let nested = try container.nestedContainer(keyedBy: SingleValueKeys.self, forKey: .system)
            let raw = try nested.decode(String.self, forKey: ._0)
            guard let system = SystemAction(rawValue: raw) else {
                throw DecodingError.dataCorruptedError(forKey: .system, in: container,
                                                       debugDescription: "unknown system action \(raw)")
            }
            self = .system(system); return
        }
        if container.contains(.plugin) {
            let nested = try container.nestedContainer(keyedBy: SingleValueKeys.self, forKey: .plugin)
            self = .plugin(try nested.decode(String.self, forKey: ._0)); return
        }
        if container.contains(.pluginOp) {
            let nested = try container.nestedContainer(keyedBy: PluginOpKeys.self, forKey: .pluginOp)
            self = .pluginOp(pluginID: try nested.decode(String.self, forKey: .pluginID),
                             opID: try nested.decode(String.self, forKey: .opID))
            return
        }
        throw DecodingError.dataCorruptedError(forKey: .system, in: container,
                                               debugDescription: "no known SlotAction case")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .app(let url):
            var nested = container.nestedContainer(keyedBy: SingleValueKeys.self, forKey: .app)
            try nested.encode(url, forKey: ._0)
        case .folder(let url):
            var nested = container.nestedContainer(keyedBy: SingleValueKeys.self, forKey: .folder)
            try nested.encode(url, forKey: ._0)
        case .system(let system):
            var nested = container.nestedContainer(keyedBy: SingleValueKeys.self, forKey: .system)
            try nested.encode(system.rawValue, forKey: ._0)
        case .plugin(let id):
            var nested = container.nestedContainer(keyedBy: SingleValueKeys.self, forKey: .plugin)
            try nested.encode(id, forKey: ._0)
        case .pluginOp(let pluginID, let opID):
            var nested = container.nestedContainer(keyedBy: PluginOpKeys.self, forKey: .pluginOp)
            try nested.encode(pluginID, forKey: .pluginID)
            try nested.encode(opID, forKey: .opID)
        }
    }

    /// Stable identity for list rows and diffing (folder row ids must not
    /// collide with app ids that share a basename).
    var identity: String {
        switch self {
        case .app(let url), .folder(let url): return url.path
        case .system(let system): return "system:\(system.rawValue)"
        case .plugin(let id): return "plugin:\(id)"
        case .pluginOp(let pluginID, let opID): return "pluginOp:\(pluginID):\(opID)"
        }
    }

    var displayName: String {
        switch self {
        case .app(let url): return url.deletingPathExtension().lastPathComponent
        case .folder(let url): return url.lastPathComponent
        case .system(let system): return system.displayName
        // Placeholder until Task 3's MainActor resolver supplies real names.
        case .plugin(let id): return id
        case .pluginOp(let pluginID, let opID): return "\(pluginID)/\(opID)"
        }
    }
}
