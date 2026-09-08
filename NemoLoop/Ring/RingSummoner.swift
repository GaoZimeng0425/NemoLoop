// NemoLoop/Ring/RingSummoner.swift
import AppKit
import SwiftUI

/// Owns the show → track → commit lifecycle of a ring, independent of what summoned it
/// (global hotkey or game controller). The caller picks how the wedge is tracked via `RingInput`.
@MainActor
final class RingSummoner {
    /// Max wedges (open apps) shown by the running-apps ring.
    static let maxRunningAppWedges = 10

    private let store: SliceStore
    private let runningApps: RunningAppsService
    private let controller: RingWindowController
    private let viewModel: RingViewModel
    private let appearanceStore: AppearanceStore

    /// The action to run for the selection that exists when the current ring commits.
    private var onSelect: ((RingSelection) -> Void)?

    var isShowing: Bool { controller.isVisible }

    init(store: SliceStore,
         runningApps: RunningAppsService,
         controller: RingWindowController,
         viewModel: RingViewModel,
         appearanceStore: AppearanceStore) {
        self.store = store
        self.runningApps = runningApps
        self.controller = controller
        self.viewModel = viewModel
        self.appearanceStore = appearanceStore
    }

    // MARK: - Summon flows

    func summonLauncher(input: RingInput = .pointer) {
        summon(icons: store.icons, subicons: store.childIcons, input: input) { [weak self] selection in
            guard let self, self.store.config.slots.indices.contains(selection.index) else { return }
            let entry = self.store.config.slots[selection.index]
            if let sub = selection.subIndex, entry.children.indices.contains(sub) {
                Launcher.run(entry.children[sub])
            } else if let action = entry.action {
                Launcher.run(action)
            }
        }
    }

    func summonRunningApps(input: RingInput = .pointer) {
        let apps = runningApps.snapshot(limit: Self.maxRunningAppWedges)
        guard !apps.isEmpty else { return }   // nothing to switch to → no ring
        summon(icons: apps.map(\.icon), input: input) { selection in
            guard apps.indices.contains(selection.index) else { return }
            // openApplication on the running instance restores minimized windows
            // (Dock-reopen semantics); bare activate() leaves them in the Dock.
            Launcher.switchTo(app: apps[selection.index].app)
        }
    }

    /// Shared open path: guards against re-entry, records the commit action, shows the ring.
    private func summon(icons: [NSImage?],
                        subicons: [[NSImage?]] = [],
                        input: RingInput,
                        onSelect: @escaping (RingSelection) -> Void) {
        guard !controller.isVisible else { return } // ignore auto-repeat / held input
        self.onSelect = onSelect
        let center = ringCenter(for: input)
        viewModel.begin(centerGlobal: center,
                        wedgeCount: icons.count,
                        childrenCounts: subicons.map(\.count),
                        input: input)
        let content = RingView(icons: icons, viewModel: viewModel, subicons: subicons)
        controller.show(content: content, centeredAtGlobalPoint: center,
                        appearance: appearanceStore.appearance) { [weak self] in
            self?.cancel()
        }
    }

    /// Pointer rings appear under the cursor; controller rings have no cursor to anchor to,
    /// so they sit at the center of the screen the cursor is currently on.
    private func ringCenter(for input: RingInput) -> CGPoint {
        switch input {
        case .pointer:
            return NSEvent.mouseLocation
        case .vector:
            let frame = controller.screenForCursor().frame
            return CGPoint(x: frame.midX, y: frame.midY)
        }
    }

    // MARK: - Dismiss

    /// Runs the selected wedge's action and closes the ring (hotkey release / confirm button).
    func commit() {
        guard controller.isVisible else { return }
        let selection = viewModel.selection
        let action = onSelect
        teardown()
        if let selection { action?(selection) }
    }

    /// Closes the ring without selecting anything.
    func cancel() {
        guard controller.isVisible else { return }
        teardown()
    }

    private func teardown() {
        controller.hide()
        viewModel.end()
        onSelect = nil
    }
}
