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
    @State private var tab: SettingsTab = .ring

    init(store: SliceStore, chrome: SettingsChrome) {
        self._store = Bindable(store)
        self._chrome = Bindable(chrome)
    }

    private let wedgeNames = ["Top", "Upper-right", "Lower-right", "Bottom", "Lower-left", "Upper-left"]

    var body: some View {
        HStack(spacing: 0) {
            if chrome.sidebarVisible {
                sidebarCard
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            LuminarePane(tab.title) {
                paneContent
            }
            .luminarePaneLayout(.stacked)
        }
        .padding(.top, 28) // clear the transparent titlebar (fullSizeContentView)
        .animation(.smooth(duration: 0.25), value: chrome.sidebarVisible)
        .luminareTint(overridingWith: .accentColor)
    }

    /// A floating, rounded sidebar card (inset with padding + shadow) rather than a flush edge sidebar.
    private var sidebarCard: some View {
        LuminareSidebar {
            LuminareSidebarSection("Settings", selection: $tab, items: SettingsTab.allCases)
        }
        .frame(width: 200)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.bottom, 12)
        .shadow(color: .black.opacity(0.28), radius: 14, x: 0, y: 4)
    }

    // MARK: - Panes

    @ViewBuilder private var paneContent: some View {
        switch tab {
        case .ring: ringSettings
        case .general: placeholder("General settings coming soon.")
        case .appearance: placeholder("Ring appearance options coming soon.")
        case .about: aboutSettings
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
        }

        LuminareSection("Wedges") {
            ForEach(0..<SliceConfig.wedgeCount, id: \.self) { i in
                LuminareCompose(alignment: .center) {
                    HStack(spacing: 6) {
                        Button("Choose…") { chooseApp(for: i) }
                            .buttonStyle(.luminareCompact)
                        Button("Clear") { store.setSlot(nil, at: i) }
                            .buttonStyle(.luminareCompact)
                            .disabled(store.config.slots[i] == nil)
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

    private func label(for i: Int) -> String {
        if let url = store.config.slots[i] {
            return "\(wedgeNames[i]): \(url.deletingPathExtension().lastPathComponent)"
        }
        return "\(wedgeNames[i]): (empty)"
    }

    private func chooseApp(for index: Int) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.application]
        panel.directoryURL = URL(filePath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            store.setSlot(url, at: index)
        }
    }
}
