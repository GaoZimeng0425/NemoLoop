// NemoLoop/Settings/SettingsView.swift
import AppKit
import KeyboardShortcuts
import Luminare
import SwiftUI
import UniformTypeIdentifiers

/// Sidebar tabs for the settings window (Loop-style left-right layout).
enum SettingsTab: LuminareTabItem, CaseIterable, Identifiable {
    case general, ring, appearance, about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .ring: "Ring"
        case .appearance: "Appearance"
        case .about: "About"
        }
    }

    var image: Image {
        switch self {
        case .general: Image(systemName: "gearshape")
        case .ring: Image(systemName: "circle.grid.cross")
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
        LuminareCompose(alignment: .center) {
            HStack(spacing: 6) {
                Menu {
                    Button("Choose App…") { chooseApp(for: i) }
                    Button("Choose Folder…") { chooseFolder(for: i) }
                    Menu("System Action") {
                        ForEach(SystemAction.allCases) { system in
                            Button(system.displayName) {
                                store.setAction(.system(system), at: i)
                            }
                        }
                    }
                    Divider()
                    Section("Sub-actions (\(entry.children.count)/\(SlotEntry.maxChildren))") {
                        if entry.children.count < SlotEntry.maxChildren {
                            Menu("Add Sub-action…") {
                                Button("App…") { chooseChildApp(for: i) }
                                Button("Folder…") { chooseChildFolder(for: i) }
                                Menu("System") {
                                    ForEach(SystemAction.allCases) { system in
                                        Button(system.displayName) {
                                            store.addChild(.system(system), at: i)
                                        }
                                    }
                                }
                            }
                        }
                        ForEach(entry.children.indices, id: \.self) { j in
                            Button("Remove “\(entry.children[j].displayName)”") {
                                store.removeChild(at: i, offset: j)
                            }
                        }
                    }
                } label: {
                    Text("Configure")
                }
                .buttonStyle(.luminareCompact)
                Button("Clear") { store.setAction(nil, at: i) }
                    .buttonStyle(.luminareCompact)
                    .disabled(entry.action == nil && entry.children.isEmpty)
            }
        } label: {
            HStack(spacing: 8) {
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

    /// Slots are numbered by ring order — blade 0 at 12 o'clock running
    /// clockwise — not by compass position: the fan's wrap gap means half the
    /// old "Upper-left"-style names pointed at nonexistent geometry.
    private func slotName(_ i: Int) -> String { "Slot \(i + 1)" }

    private func label(for i: Int) -> String {
        let entry = store.config.slots[i]
        let base = entry.action.map { "\(slotName(i)): \($0.displayName)" }
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
