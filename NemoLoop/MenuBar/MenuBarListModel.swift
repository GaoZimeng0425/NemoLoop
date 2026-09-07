// NemoLoop/MenuBar/MenuBarListModel.swift
import Foundation

/// Pure row-building for the menu-bar panel's two sections. Kept free of AppKit
/// UI types so the filtering/naming rules are unit-testable; the view layers
/// icons on top. The two sections are rendered separately, so `Row.iconIndex`
/// means "index into the icon array of the section being rendered":
/// position in the running snapshot, or original slot index into `SliceStore.icons`.
enum MenuBarListModel {
    /// Lightweight running-app input the tests can construct freely
    /// (unlike `NSRunningApplication`).
    struct AppEntry: Equatable {
        let id: pid_t
        let name: String
    }

    struct Row: Equatable {
        /// Stable SwiftUI identity: pid string for running, file path for pinned.
        let id: String
        let name: String
        /// True only for the currently frontmost running app (the accent dot).
        let isFrontmost: Bool
        let iconIndex: Int
    }

    /// `apps` arrives MRU-first (the `RunningAppsService.snapshot` contract) and
    /// keeps that order — the panel is a launcher, MRU is the sorting users expect.
    static func runningRows(_ apps: [AppEntry], frontmostPID: pid_t?) -> [Row] {
        apps.enumerated().map { index, app in
            Row(id: String(app.id),
                name: app.name,
                isFrontmost: app.id == frontmostPID,
                iconIndex: index)
        }
    }

    /// Empty slots vanish; survivors keep slot order and remember their original
    /// slot so icon lookups hit `SliceStore`'s cache.
    static func pinnedRows(_ actions: [SlotAction?]) -> [Row] {
        actions.enumerated().compactMap { slotIndex, action in
            guard let action else { return nil }
            return Row(id: action.identity,
                       name: action.displayName,
                       isFrontmost: false,
                       iconIndex: slotIndex)
        }
    }
}
