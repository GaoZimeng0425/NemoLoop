// NemoLoop/Services/ActionPickerModel.swift
import Foundation

/// Where the picker is being used — sub-slots have no whole-plugin mounting,
/// so the Plugins section there lists ops only.
enum PickerContext {
    case mainSlot
    case subSlot
}

/// One selectable row in the picker. Kind carries everything the caller needs
/// to build a SlotAction; title/subtitle/symbol drive the row UI.
struct PickerItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case browseApps
        case browseFolder
        case wholePlugin(String)
        case op(pluginID: String, opID: String)
        case app(AppEntry)
    }
    let id: String
    let kind: Kind
    let title: String
    let subtitle: String?
    let symbolName: String?
}

struct PickerSection: Equatable {
    let title: String
    let items: [PickerItem]
}

/// Loop's three-tier match scoring: prefix (0) beats contains (1) beats
/// subsequence (2); nil means no match. Empty query matches everything at 0.
enum PickerSearch {
    static func score(query: String, name: String) -> Int? {
        let q = query.lowercased(), n = name.lowercased()
        guard !q.isEmpty else { return 0 }
        if n.hasPrefix(q) { return 0 }
        if n.contains(q) { return 1 }
        // Subsequence: every query char appears in order, gaps allowed.
        var qi = q.startIndex
        for char in n where qi < q.endIndex && char == q[qi] { qi = q.index(after: qi) }
        return qi == q.endIndex ? 2 : nil
    }
}

/// Pure data model behind the action picker: builds Apps → Plugins → Folders
/// sections from scanned apps plus the connected plugins, filters/sorts by
/// tiered search score. No UI, no side effects — the popover just renders it.
@MainActor
struct ActionPickerModel {
    let apps: [AppEntry]
    let registry: PluginRegistry

    /// Explicit init (not memberwise) so callers may omit the registry and
    /// get the app's shared one; tests inject one on throwaway defaults.
    init(apps: [AppEntry], registry: PluginRegistry = .shared) {
        self.apps = apps
        self.registry = registry
    }

    /// Shown under the Plugins section: tells the user why a plugin they own
    /// is missing from the list (connected-only) and where to fix it.
    var connectedPluginFootnote: String {
        "Plugins not listed are disconnected — connect them in the Plugins tab."
    }

    func sections(context: PickerContext, query: String) -> [PickerSection] {
        var sections: [PickerSection] = []

        var appItems = apps.map { entry in
            PickerItem(id: "app:\(entry.id)", kind: .app(entry), title: entry.name, subtitle: nil, symbolName: nil)
        }
        appItems.append(PickerItem(id: "browse:apps", kind: .browseApps, title: "Browse…",
                                   subtitle: nil, symbolName: "folder.badge.plus"))
        sections.append(PickerSection(title: "Apps", items: filtered(appItems, query: query)))

        var pluginItems: [PickerItem] = []
        for plugin in registry.plugins where registry.isEnabled(plugin.id) {
            if context == .mainSlot {
                pluginItems.append(PickerItem(
                    id: "whole:\(plugin.id)", kind: .wholePlugin(plugin.id),
                    title: plugin.displayName,
                    subtitle: "\(plugin.operations.count) action\(plugin.operations.count == 1 ? "" : "s")",
                    symbolName: plugin.symbolName))
            }
            for op in plugin.operations {
                pluginItems.append(PickerItem(
                    id: "op:\(plugin.id):\(op.id)", kind: .op(pluginID: plugin.id, opID: op.id),
                    title: op.displayName, subtitle: plugin.displayName, symbolName: op.symbolName))
            }
        }
        // Guard on the unfiltered list: with nothing connected the section
        // must not exist at all (empty-after-search is handled below).
        if !pluginItems.isEmpty {
            sections.append(PickerSection(title: "Plugins", items: filtered(pluginItems, query: query)))
        }

        let folders = [PickerItem(id: "browse:folder", kind: .browseFolder, title: "Browse Folder…",
                                  subtitle: nil, symbolName: "folder")]
        sections.append(PickerSection(title: "Folders", items: filtered(folders, query: query)))

        return sections.filter { !$0.items.isEmpty }
    }

    /// Keeps section order, drops non-matching rows, sorts within by
    /// (score, then localized title) — Loop's picker behavior.
    private func filtered(_ items: [PickerItem], query: String) -> [PickerItem] {
        guard !query.isEmpty else { return items }
        return items.compactMap { item -> (PickerItem, Int)? in
            guard let score = PickerSearch.score(query: query, name: item.title) else { return nil }
            return (item, score)
        }
        .sorted { lhs, rhs in
            lhs.1 != rhs.1 ? lhs.1 < rhs.1 : lhs.0.title.localizedCaseInsensitiveCompare(rhs.0.title) == .orderedAscending
        }
        .map(\.0)
    }
}
