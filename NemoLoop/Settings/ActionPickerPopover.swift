// NemoLoop/Settings/ActionPickerPopover.swift
import AppKit
import Luminare
import SwiftUI
import UniformTypeIdentifiers

/// Click-triggered picker popover (native SwiftUI `.popover` — Luminare 0.2.0's
/// own popover is hover/forceTouch only, which is the wrong trigger for a
/// settings picker) hosting Luminare content: a search field over a sectioned
/// list (Apps → Plugins → Folders) built by `ActionPickerModel`. 300×360 per
/// spec. Picking an item writes the store immediately and dismisses.
struct ActionPickerPopover: View {
    let context: PickerContext
    @Bindable var store: SliceStore
    let slot: Int
    let onDismiss: () -> Void

    /// Optional because LuminareTextField binds String? — always read via
    /// `query ?? ""`.
    @State private var query: String? = ""
    /// nil = not scanned yet (spinner state); filled once per process from
    /// `AppScanner.cachedScan()`.
    @State private var apps: [AppEntry]?

    init(context: PickerContext, store: SliceStore, slot: Int,
         onDismiss: @escaping () -> Void) {
        self.context = context
        self._store = Bindable(store)
        self.slot = slot
        self.onDismiss = onDismiss
    }

    private var model: ActionPickerModel {
        ActionPickerModel(apps: apps ?? [], registry: .shared)
    }

    var body: some View {
        VStack(spacing: 8) {
            LuminareTextField("Search", text: $query)
                .padding(.horizontal, 10)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if apps == nil {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    }
                    // id: \.title (not implicit Identifiable): section titles
                    // are unique by construction (Apps/Plugins/Folders).
                    ForEach(model.sections(context: context, query: query ?? ""), id: \.title) { section in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(section.title.uppercased())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(section.items) { item in
                                PickerRow(item: item) { choose(item) }
                            }
                        }
                    }
                    Text(model.connectedPluginFootnote)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 10)
            }
        }
        .padding(.vertical, 10)
        .frame(width: 300, height: 360)
        .onAppear {
            // Task (not a direct call): lets this body pass finish so the
            // spinner renders before the synchronous scan blocks the main
            // actor; the cache makes every later open instant.
            if apps == nil {
                Task { @MainActor in apps = AppScanner.cachedScan() }
            }
        }
    }

    // MARK: - Choosing

    private func choose(_ item: PickerItem) {
        switch item.kind {
        case .app(let entry):
            // One concrete action, then the context decides the store write:
            // a main pick REPLACES the slot's action, a sub pick APPENDS a
            // child. (Expanded from the brief's ternary.)
            let action = SlotAction.app(entry.url)
            applyByContext(action)
        case .wholePlugin(let id):
            // Main-only by construction: the model never emits whole-plugin
            // items for .subSlot — sub-slots mount single operations.
            store.attachWholePlugin(id, at: slot)
        case .op(let pluginID, let opID):
            applyByContext(.pluginOp(pluginID: pluginID, opID: opID))
        case .browseApps, .browseFolder:
            // ORDERING CONTRACT: close the popover FIRST, then run the modal
            // open panel, then write the store. NSOpenPanel.runModal() spins
            // its own run loop while the popover is still up, and presenting
            // a modal panel over a live popover detaches the popover shell on
            // some macOS versions. Early-return: onDismiss already ran.
            onDismiss()
            runOpenPanel(kind: item.kind == .browseApps ? .appPanel : .folderPanel)
            return
        }
        onDismiss()
    }

    private func applyByContext(_ action: SlotAction) {
        if context == .mainSlot {
            store.setAction(action, at: slot)
        } else {
            store.addChild(action, at: slot)
        }
    }

    // MARK: - Browse fallback

    private enum PanelKind { case appPanel, folderPanel }

    /// Manual browse when the scanned list doesn't carry what the user wants.
    /// Reuses SettingsView's shared panel (one source of truth for the
    /// app/folder panel semantics: apps root at /Applications, .application
    /// type; folders root at the home dir, directories selectable) and routes
    /// the pick through the same context rule as direct picks.
    private func runOpenPanel(kind: PanelKind) {
        let url: URL?
        switch kind {
        case .appPanel:
            url = SettingsView.runOpenPanel(contentTypes: [.application],
                                            directory: URL(filePath: "/Applications"),
                                            canChooseDirectories: false)
        case .folderPanel:
            url = SettingsView.runOpenPanel(contentTypes: [.folder],
                                            directory: FileManager.default.homeDirectoryForCurrentUser,
                                            canChooseDirectories: true)
        }
        guard let url else { return }
        applyByContext(kind == .appPanel ? .app(url) : .folder(url))
    }
}

/// One selectable row: real file icon for apps, SF Symbol otherwise, title
/// over optional subtitle. Whole-plugin rows carry a link glyph — reference
/// semantics: plugin config changes flow into the whole ring.
private struct PickerRow: View {
    let item: PickerItem
    let onChoose: () -> Void

    var body: some View {
        Button(action: onChoose) {
            HStack(spacing: 8) {
                if case .app(let entry) = item.kind {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                        .resizable()
                        .frame(width: 20, height: 20)
                } else if let symbol = item.symbolName {
                    Image(systemName: symbol)
                        .frame(width: 20)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if case .wholePlugin = item.kind {
                    // Reference semantics: the slot mirrors live plugin config.
                    Image(systemName: "link")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
