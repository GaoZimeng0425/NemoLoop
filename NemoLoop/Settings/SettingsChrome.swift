// NemoLoop/Settings/SettingsChrome.swift
import SwiftUI

/// Shared chrome state for the settings window, observed by both the SwiftUI
/// content (to show/hide the floating sidebar) and the titlebar toggle button.
@MainActor
@Observable
final class SettingsChrome {
    var sidebarVisible = true
}

/// The sidebar collapse/expand button hosted in the window titlebar (leading accessory).
struct SidebarToggle: View {
    @Bindable var chrome: SettingsChrome

    var body: some View {
        Button {
            withAnimation(.smooth(duration: 0.25)) { chrome.sidebarVisible.toggle() }
        } label: {
            Image(systemName: "sidebar.leading")
                .font(.system(size: 13, weight: .medium))
        }
        .buttonStyle(.accessoryBar)
        .help(chrome.sidebarVisible ? "Hide Sidebar" : "Show Sidebar")
        .padding(.horizontal, 6)
        .frame(height: 28)
    }
}
