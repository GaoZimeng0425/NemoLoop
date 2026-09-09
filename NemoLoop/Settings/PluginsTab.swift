// NemoLoop/Settings/PluginsTab.swift
import Luminare
import SwiftUI

/// One card per built-in plugin: status badge + connect toggle + an
/// expandable config area (only when the plugin has one). A failed connect
/// shows inline red text and the toggle bounces back off — never silent.
struct PluginsTab: View {
    // Bindable (not a plain let) so enable-state reads inside the cards
    // subscribe the view to registry changes — toggles must re-render cards.
    @Bindable var registry: PluginRegistry

    var body: some View {
        LuminareSection("Plugins",
                        "Connect feature packs. Slots already on the ring keep their data — a disconnected plugin just dims.") {
            // id: \.id (not implicit Identifiable): `any NemoPlugin` doesn't
            // satisfy the existential Identifiable conformance ForEach needs.
            ForEach(registry.plugins, id: \.id) { plugin in
                PluginCard(plugin: plugin, registry: registry)
            }
        }
    }
}

private struct PluginCard: View {
    let plugin: any NemoPlugin
    @Bindable var registry: PluginRegistry
    @State private var expanded = false
    @State private var errorText: String?
    @State private var busy = false

    var body: some View {
        LuminareCompose(alignment: .center) {
            HStack(spacing: 6) {
                if busy { ProgressView().controlSize(.small) }
                // Custom binding: enablement is registry state, and connect
                // can fail — a thrown error must revert the knob, which a
                // get-backed binding gives us for free (the get still reads
                // the un-mutated registry state).
                Toggle("", isOn: Binding(
                    get: { registry.isEnabled(plugin.id) },
                    set: { on in Task { await toggle(on) } }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: plugin.symbolName)
                    .font(.system(size: 16))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(plugin.displayName)
                    Text(plugin.summary).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                statusBadge
                if plugin.configSections != nil {
                    Button { withAnimation(.smooth(duration: 0.2)) { expanded.toggle() } } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        if expanded, let sections = plugin.configSections { sections }
        if let errorText {
            Text(errorText).font(.caption).foregroundStyle(.red)
        }
    }

    private var statusBadge: some View {
        Circle().fill(color).frame(width: 8, height: 8)
            .help(helpText)
    }
    private var color: Color {
        plugin.status == .ready ? .green : (plugin.status == .needsAuth ? .yellow : .gray)
    }
    private var helpText: String {
        switch plugin.status {
        case .ready: "Ready"; case .needsAuth: "Needs authorization"; case .notInstalled: "Not installed"
        }
    }

    private func toggle(_ on: Bool) async {
        busy = true; errorText = nil
        defer { busy = false }
        do { try await registry.setEnabled(plugin.id, on) }
        catch { errorText = "Connect failed: \(error.localizedDescription)" }
    }
}
