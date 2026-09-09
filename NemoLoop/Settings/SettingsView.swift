// NemoLoop/Settings/SettingsView.swift
import AppKit
import KeyboardShortcuts
import Luminare
import SwiftUI
import UniformTypeIdentifiers

/// Sidebar tabs for the settings window (Loop-style left-right layout).
enum SettingsTab: LuminareTabItem, CaseIterable, Identifiable {
    case general, ring, plugins, appearance, about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .ring: "Ring"
        case .plugins: "Plugins"
        case .appearance: "Appearance"
        case .about: "About"
        }
    }

    var image: Image {
        switch self {
        case .general: Image(systemName: "gearshape")
        case .ring: Image(systemName: "circle.grid.cross")
        case .plugins: Image(systemName: "puzzlepiece.extension")
        case .appearance: Image(systemName: "paintpalette")
        case .about: Image(systemName: "info.circle")
        }
    }
}

struct SettingsView: View {
    @Bindable var store: SliceStore
    @Bindable var chrome: SettingsChrome
    @Bindable var appearance: AppearanceStore
    @State private var tab: SettingsTab = .ring
    /// Which slot groups have their sub-action rows unfolded.
    @State private var expandedSlots: Set<Int> = []

    init(store: SliceStore, chrome: SettingsChrome, appearance: AppearanceStore) {
        self._store = Bindable(store)
        self._chrome = Bindable(chrome)
        self._appearance = Bindable(appearance)
    }

    var body: some View {
        HStack(spacing: 0) {
            if chrome.sidebarVisible {
                // Flush left sidebar, the way LuminareSidebar is meant to sit
                // (see its own preview: sidebar | Divider | pane) — no floating
                // card, no shadow, no inset.
                sidebar
                    .transition(.move(edge: .leading).combined(with: .opacity))
                Divider()
            }
            LuminarePane {
                paneContent
            } header: {
                // Leading-aligned tab title: the pane's plain-Text header gets
                // centered by the button wrapper, which reads as a toolbar title.
                Text(tab.title)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .luminarePaneLayout(.stacked)
        }
        .animation(.smooth(duration: 0.25), value: chrome.sidebarVisible)
        .luminareTint(overridingWith: .accentColor)
        // Rise into the titlebar strip: the pane header (tab name) then occupies
        // the full-size-content titlebar as the single top bar, instead of
        // stacking under the system title.
        .ignoresSafeArea(.container, edges: .top)
    }

    /// Edge-to-edge sidebar column: full window height, square to the window
    /// edges; the hairline Divider in `body` separates it from the pane. The
    /// extra top margin keeps the first tab clear of the traffic lights and the
    /// titlebar toggle, which now share the strip the sidebar rises into.
    private var sidebar: some View {
        LuminareSidebar {
            LuminareSidebarSection(selection: $tab, items: SettingsTab.allCases)
                .padding(.vertical, 12)
        }
        .environment(\.luminareContentMarginsTop, 16)
        .frame(width: 200)
    }

    // MARK: - Panes

    @ViewBuilder private var paneContent: some View {
        switch tab {
        case .ring: ringSettings
        case .plugins: PluginsTab(registry: PluginRegistry.shared)
        case .general: placeholder("General settings coming soon.")
        case .appearance: appearanceSettings
        case .about: aboutSettings
        }
    }

    @ViewBuilder private var appearanceSettings: some View {
        LuminareSection(
            "Theme",
            "Ring card colours. Auto follows your system appearance; the next summon picks it up."
        ) {
            LuminarePicker(compactElements: RingAppearance.allCases, selection: $appearance.appearance) { option in
                VStack(spacing: 6) {
                    Image(systemName: option.iconName)
                        .font(.system(size: 16))
                    Text(option.label)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder private var ringSettings: some View {
        LuminareSection(
            "Hotkey",
            "Hold this hotkey anywhere to summon the ring; release over a wedge to launch."
        ) {
            LuminareCompose("Summon ring (hold):") {
                KeyboardShortcuts.Recorder("", name: .summonRing)
            }
            LuminareCompose("Open apps (hold):") {
                KeyboardShortcuts.Recorder("", name: .summonRunningApps)
            }
        }

        LuminareSection("Wedges") {
            ForEach(0..<SliceConfig.wedgeCount, id: \.self) { i in
                wedgeRow(i)
            }
        }
    }

    @ViewBuilder
    private func wedgeRow(_ i: Int) -> some View {
        let entry = store.config.slots[i]
        // One collapsible group: the slot row, and when expanded its sub-slot
        // rows beneath (indented), ending with the add row.
        VStack(spacing: 0) {
            LuminareCompose(alignment: .center) {
                HStack(spacing: 6) {
                    Menu {
                        Button("Choose App…") { chooseApp(for: i) }
                        Button("Choose Folder…") { chooseFolder(for: i) }
                        // Connected plugins only: a disconnected plugin has
                        // nothing runnable to offer the ring.
                        Menu("Plugins") {
                            ForEach(connectedPlugins, id: \.id) { plugin in
                                Button("Whole: \(plugin.displayName)") {
                                    store.attachWholePlugin(plugin.id, at: i)
                                }
                                Menu(plugin.displayName) {
                                    ForEach(plugin.operations, id: \.id) { op in
                                        Button(op.displayName) {
                                            store.setAction(.pluginOp(pluginID: plugin.id, opID: op.id), at: i)
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        Text("Configure")
                    }
                    .buttonStyle(.luminareCompact)
                    Button("Clear") {
                        withAnimation(.smooth(duration: 0.2)) {
                            store.setAction(nil, at: i)
                            expandedSlots.remove(i)
                        }
                    }
                    .buttonStyle(.luminareCompact)
                    .disabled(entry.action == nil && entry.children.isEmpty)
                }
            } label: {
                HStack(spacing: 8) {
                    // Only configured slots unfold — sub-slots hang off a
                    // configured slot, so an empty slot has nothing to expand.
                    // (Legacy children without an action stay manageable.)
                    if entry.action != nil || !entry.children.isEmpty {
                        Button {
                            withAnimation(.smooth(duration: 0.2)) {
                                if expandedSlots.contains(i) {
                                    expandedSlots.remove(i)
                                } else {
                                    expandedSlots.insert(i)
                                }
                            }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .rotationEffect(.degrees(expandedSlots.contains(i) ? 90 : 0))
                                .foregroundStyle(.secondary)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    Group {
                        if let icon = store.icon(at: i) {
                            Image(nsImage: icon)
                                .resizable()
                                .interpolation(.high)
                        } else {
                            Image(systemName: "app.dashed")
                                .resizable()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 22, height: 22)
                    Text(label(for: i))
                }
            }

            if expandedSlots.contains(i) {
                subRows(i, entry: entry)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// The sub-slot controls of one slot, indented under it: a right-aligned
    /// strip of rounded icon buttons — one per sub-action (click removes, hover
    /// shows the minus badge) — with the add button at the end. Adding stays
    /// gated on a configured slot; an empty expanded slot explains why.
    @ViewBuilder
    private func subRows(_ i: Int, entry: SlotEntry) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            // childLimit (not the manual cap): a whole-plugin slot widens to
            // 8 sub-actions, and the add affordance must reflect that headroom.
            if !entry.children.isEmpty
                || (entry.action != nil
                    && entry.children.count < SlotEntry.childLimit(for: entry.action)) {
                HStack(spacing: 8) {
                    ForEach(entry.children.indices, id: \.self) { j in
                        // ActionResolver, not SlotAction.displayName: the model
                        // layer's plugin fallback is the raw "pluginID/opID",
                        // which must never reach the remove tooltip.
                        SubSlotChip(icon: SliceStore.icon(for: entry.children[j]),
                                    name: ActionResolver.name(for: entry.children[j])) {
                            withAnimation(.smooth(duration: 0.2)) {
                                store.removeChild(at: i, offset: j)
                            }
                        }
                    }

                    if entry.action != nil,
                       entry.children.count < SlotEntry.childLimit(for: entry.action) {
                        Menu {
                            Button("App…") { chooseChildApp(for: i) }
                            Button("Folder…") { chooseChildFolder(for: i) }
                            // Same connected-plugins source as the main slot
                            // menu above, ops only — a sub-slot mounts single
                            // operations, never a whole plugin.
                            Menu("Plugins") {
                                ForEach(connectedPlugins, id: \.id) { plugin in
                                    Menu(plugin.displayName) {
                                        ForEach(plugin.operations, id: \.id) { op in
                                            Button(op.displayName) {
                                                store.addChild(.pluginOp(pluginID: plugin.id, opID: op.id), at: i)
                                            }
                                        }
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 36, height: 36)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        // The chip card wraps the MENU, not the label — a
                        // borderless menu restyles its label and drops fills.
                        .frame(width: 36, height: 36)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.quinary.opacity(0.6)))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                        .help("Add Sub-action")
                    }
                }
                .padding(.vertical, 4)
            }

        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 12)
        .padding(.bottom, 4)
    }

    @ViewBuilder private func placeholder(_ text: String) -> some View {
        LuminareSection {
            Text(text)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
        }
    }

    @ViewBuilder private var aboutSettings: some View {
        LuminareSection("About") {
            LuminareCompose("Name") {
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "NemoLoop")
                    .foregroundStyle(.secondary)
            }
            LuminareCompose("Version") {
                Text(appVersion)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(short) (\(build))"
    }

    // MARK: - Helpers

    /// Connected plugins for both slot menus. Read during body evaluation so
    /// toggling a plugin in the Plugins tab re-renders the menus in place.
    private var connectedPlugins: [any NemoPlugin] {
        PluginRegistry.shared.plugins.filter { PluginRegistry.shared.isEnabled($0.id) }
    }

    /// Slots are numbered by ring order — blade 0 at 12 o'clock running
    /// clockwise — not by compass position: the fan's wrap gap means half the
    /// old "Upper-left"-style names pointed at nonexistent geometry.
    private func slotName(_ i: Int) -> String { "Slot \(i + 1)" }

    private func label(for i: Int) -> String {
        let entry = store.config.slots[i]
        // Resolve through the registry so plugin actions read their display
        // names ("Lock Screen"), never raw ids ("system/lockScreen").
        let base = entry.action.map { "\(slotName(i)): \(ActionResolver.name(for: $0))" }
            ?? "\(slotName(i)): (empty)"
        return entry.children.isEmpty ? base : "\(base) · \(entry.children.count) subs"
    }

    private func chooseApp(for index: Int) {
        if let url = runOpenPanel(contentTypes: [.application],
                                  directory: URL(filePath: "/Applications"),
                                  canChooseDirectories: false) {
            store.setAction(.app(url), at: index)
        }
    }

    private func chooseFolder(for index: Int) {
        if let url = runOpenPanel(contentTypes: [.folder],
                                  directory: FileManager.default.homeDirectoryForCurrentUser,
                                  canChooseDirectories: true) {
            store.setAction(.folder(url), at: index)
        }
    }

    private func chooseChildApp(for index: Int) {
        if let url = runOpenPanel(contentTypes: [.application],
                                  directory: URL(filePath: "/Applications"),
                                  canChooseDirectories: false) {
            store.addChild(.app(url), at: index)
        }
    }

    private func chooseChildFolder(for index: Int) {
        if let url = runOpenPanel(contentTypes: [.folder],
                                  directory: FileManager.default.homeDirectoryForCurrentUser,
                                  canChooseDirectories: true) {
            store.addChild(.folder(url), at: index)
        }
    }

    private func runOpenPanel(contentTypes: [UTType],
                              directory: URL,
                              canChooseDirectories: Bool) -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = contentTypes
        panel.directoryURL = directory
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = canChooseDirectories
        panel.canChooseFiles = !canChooseDirectories
        return panel.runModal() == .OK ? panel.url : nil
    }
}

/// Theme picker presentation (UI strings live here, not on the model).
extension RingAppearance {
    var label: String {
        switch self {
        case .auto: "Auto"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var iconName: String {
        switch self {
        case .auto: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }
}

/// The 36pt rounded card frame shared by the sub-slot chip buttons.
private struct SubSlotChipFrame: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: 8).fill(.quinary.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// One sub-slot chip: the action's icon; hovering reveals the minus badge and
/// clicking removes it (settings only configures — the ring runs these).
private struct SubSlotChip: View {
    let icon: NSImage
    let name: String
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onRemove) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 22, height: 22)
                .frame(width: 36, height: 36)
                .modifier(SubSlotChipFrame())
                .overlay(alignment: .topTrailing) {
                    if hovering {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                            .offset(x: 4, y: -4)
                    }
                }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Remove \(name)")
    }
}
