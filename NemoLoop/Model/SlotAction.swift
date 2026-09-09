import Foundation

/// System-level actions a slot can run — the things that have no file to open.
/// UI-presentable metadata (label + symbol) lives here too: the System plugin
/// surfaces it as op names/symbols, and the strings are stable.
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
    /// Pre-plugin name for the manual cap; existing tests still read it.
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
/// plugin cases reference the plugin registry by id (names, symbols, and
/// execution resolve through PluginRegistry at use time).
enum SlotAction: Codable, Equatable {
    case app(URL)
    case folder(URL)
    case plugin(String)
    case pluginOp(pluginID: String, opID: String)

    /// Keys the encoder writes — exactly the surviving cases.
    private enum CodingKeys: String, CodingKey {
        case app, folder, plugin, pluginOp
    }
    /// Decode-side superset of CodingKeys: also recognizes the `system`
    /// payload written by pre-plugin builds so legacy data migrates on read.
    /// A separate enum from CodingKeys is what guarantees the encoder can
    /// never emit a `system` key again.
    private enum DecodeKeys: String, CodingKey {
        case app, folder, system, plugin, pluginOp
    }
    private enum SingleValueKeys: String, CodingKey { case _0 }
    /// Nested `_0` shape of the legacy `{"system":{"_0":"…"}}` payload.
    private enum LegacySystemKeys: String, CodingKey { case _0 }
    private enum PluginOpKeys: String, CodingKey { case pluginID, opID }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DecodeKeys.self)
        // Swift's synthesized format wraps every single-associated-value case
        // as {"case":{"_0":value}} — decode app/folder/plugin through the
        // nested _0; flat payloads are rejected.
        if container.contains(.app) {
            let nested = try container.nestedContainer(keyedBy: SingleValueKeys.self, forKey: .app)
            self = .app(try nested.decode(URL.self, forKey: ._0)); return
        }
        if container.contains(.folder) {
            let nested = try container.nestedContainer(keyedBy: SingleValueKeys.self, forKey: .folder)
            self = .folder(try nested.decode(URL.self, forKey: ._0)); return
        }
        // Legacy v3 data: `.system` was its own case, and its raw payload IS
        // the System plugin's op id space, so map one to one. No validation
        // against SystemAction — an unknown value becomes a placeholder op
        // the registry logs-and-ignores, which beats dropping the user's
        // saved slot to a decode error.
        if container.contains(.system) {
            let nested = try container.nestedContainer(keyedBy: LegacySystemKeys.self, forKey: .system)
            let raw = try nested.decode(String.self, forKey: ._0)
            self = .pluginOp(pluginID: "system", opID: raw)
            return
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
        // Report against the value's own path, not any DecodeKeys member:
        // `.system` exists for legacy decoding only, and the failure is "no
        // case matched at all" — blaming a stale key would mislead readers.
        throw DecodingError.dataCorrupted(.init(
            codingPath: container.codingPath,
            debugDescription: "no known SlotAction case (expected app, folder, plugin, or pluginOp)"))
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
        case .plugin(let id):
            var nested = container.nestedContainer(keyedBy: SingleValueKeys.self, forKey: .plugin)
            try nested.encode(id, forKey: ._0)
        case .pluginOp(let pluginID, let opID):
            var nested = container.nestedContainer(keyedBy: PluginOpKeys.self, forKey: .pluginOp)
            try nested.encode(pluginID, forKey: .pluginID)
            try nested.encode(opID, forKey: .opID)
        }
    }

    /// True when the action resolves through the plugin registry at use time:
    /// its name, symbol, enablement and (for whole mounts) op list all live in
    /// possibly-changing plugin config rather than a frozen file URL. Settings
    /// marks such slots with the reference glyph and dims them when the
    /// backing plugin is disconnected.
    var isPluginBacked: Bool {
        switch self {
        case .plugin, .pluginOp: true
        case .app, .folder: false
        }
    }

    /// Stable identity for list rows and diffing (folder row ids must not
    /// collide with app ids that share a basename).
    var identity: String {
        switch self {
        case .app(let url), .folder(let url): return url.path
        case .plugin(let id): return "plugin:\(id)"
        case .pluginOp(let pluginID, let opID): return "pluginOp:\(pluginID):\(opID)"
        }
    }

    var displayName: String {
        switch self {
        case .app(let url): return url.deletingPathExtension().lastPathComponent
        case .folder(let url): return url.lastPathComponent
        // Placeholder until the MainActor resolver's names replace this call
        // site (plugin ops resolve through the registry).
        case .plugin(let id): return id
        case .pluginOp(let pluginID, let opID): return "\(pluginID)/\(opID)"
        }
    }
}
