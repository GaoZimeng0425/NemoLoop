// NemoLoop/Plugins/Windows/WindowConfigSection.swift
import Luminare
import SwiftUI

/// Plugins-tab config area for Windows: one trust row. Ungranted shows a
/// Grant Access button (system prompt); granted shows a green confirmation.
/// AX trust has no change notification, so the button polls briefly after
/// the prompt; outside that window the row refreshes when the card reopens.
struct WindowConfigSection: View {
    let service: any WindowServicing
    @State private var granted = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.raised.circle")
                .foregroundStyle(granted ? Color.green : Color.yellow)
            if granted {
                Text("Accessibility granted")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Window snapping needs Accessibility access.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Grant Access") { grant() }
                    .buttonStyle(.luminareCompact)
            }
        }
        .onAppear { granted = service.isTrusted() }
    }

    private func grant() {
        service.promptForTrust()
        // Light poll: the system prompt grants out-of-band; ~5s of checks
        // catches the common path without a permanent timer.
        Task { @MainActor in
            for _ in 0..<10 {
                try? await Task.sleep(for: .milliseconds(500))
                if service.isTrusted() { break }
            }
            withAnimation(.smooth(duration: 0.2)) { granted = service.isTrusted() }
        }
    }
}
