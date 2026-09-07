import Foundation

/// System-level actions a slot can run — the things that have no file to open.
/// UI-presentable metadata (label + symbol) lives here too: both the settings
/// pane and the pinned-row naming rules need it, and the strings are stable.
enum SystemAction: String, Codable, CaseIterable, Identifiable {
    case lockScreen
    case sleepDisplays
    case sleep
    case missionControl

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lockScreen: "Lock Screen"
        case .sleepDisplays: "Sleep Displays"
        case .sleep: "Sleep"
        case .missionControl: "Mission Control"
        }
    }

    var symbolName: String {
        switch self {
        case .lockScreen: "lock.fill"
        case .sleepDisplays: "display"
        case .sleep: "moon.zzz"
        case .missionControl: "square.grid.3x3"
        }
    }
}

/// One ring slot: its primary action plus up to `maxChildren` sub-actions that
/// the blade deals out on dwell — the cascading sub-wheel.
struct SlotEntry: Codable, Equatable {
    static let maxChildren = 4

    var action: SlotAction?
    var children: [SlotAction] = []

    init(action: SlotAction? = nil, children: [SlotAction] = []) {
        self.action = action
        self.children = Array(children.prefix(Self.maxChildren))
    }
}

/// What a slot runs when triggered. Apps and folders carry their file URL;
/// system actions are named enum cases.
enum SlotAction: Codable, Equatable {
    case app(URL)
    case folder(URL)
    case system(SystemAction)

    /// Stable identity for list rows and diffing (folder row ids must not
    /// collide with app ids that share a basename).
    var identity: String {
        switch self {
        case .app(let url), .folder(let url): return url.path
        case .system(let system): return "system:\(system.rawValue)"
        }
    }

    var displayName: String {
        switch self {
        case .app(let url): return url.deletingPathExtension().lastPathComponent
        case .folder(let url): return url.lastPathComponent
        case .system(let system): return system.displayName
        }
    }
}
