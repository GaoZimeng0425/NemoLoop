// NemoLoop/Settings/SettingsView.swift
import AppKit
import KeyboardShortcuts
import Luminare
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var store: SliceStore

    init(store: SliceStore) { self._store = Bindable(store) }

    private let wedgeNames = ["Top", "Upper-right", "Lower-right", "Bottom", "Lower-left", "Upper-left"]

    var body: some View {
        LuminarePane("NemoLoop") {
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
        .luminarePaneLayout(.stacked)
        .luminareTint(overridingWith: .accentColor)
    }

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
