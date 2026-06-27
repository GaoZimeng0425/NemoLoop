// NemoLoop/Settings/SettingsView.swift
import AppKit
import KeyboardShortcuts
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var store: SliceStore

    init(store: SliceStore) { self._store = Bindable(store) }

    private let wedgeNames = ["Top", "Upper-right", "Lower-right", "Bottom", "Lower-left", "Upper-left"]

    var body: some View {
        Form {
            Section("Hotkey") {
                KeyboardShortcuts.Recorder("Summon ring (hold):", name: .summonRing)
            }
            Section("Wedges") {
                ForEach(0..<SliceConfig.wedgeCount, id: \.self) { i in
                    HStack {
                        if let icon = store.icon(at: i) {
                            Image(nsImage: icon).resizable().frame(width: 22, height: 22)
                        } else {
                            Image(systemName: "app.dashed").frame(width: 22, height: 22)
                        }
                        Text(label(for: i)).frame(maxWidth: .infinity, alignment: .leading)
                        Button("Choose…") { chooseApp(for: i) }
                        Button("Clear") { store.setSlot(nil, at: i) }
                            .disabled(store.config.slots[i] == nil)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 380)
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
