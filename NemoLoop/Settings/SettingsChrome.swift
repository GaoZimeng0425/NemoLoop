// NemoLoop/Settings/SettingsChrome.swift
import SwiftUI

/// Shared chrome state for the settings window, observed by both the SwiftUI
/// content (to show/hide the floating sidebar) and the titlebar toggle button.
@MainActor
@Observable
final class SettingsChrome {
    var sidebarVisible = true

    /// Ring-tab inspector column. Toggled by the tab switch, observed by the
    /// window controller to animate the frame wider/narrower.
    var inspectorVisible = false {
        didSet { inspectorDidChange?(inspectorVisible) }
    }

    /// Notified on every assignment — including same-value ones (Swift's
    /// didSet fires regardless); the window controller filters no-op resizes.
    var inspectorDidChange: ((Bool) -> Void)?
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
