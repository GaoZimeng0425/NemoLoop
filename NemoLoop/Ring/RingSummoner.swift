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

    /// The action to run for the wedge that is selected when the current ring commits.
    private var onSelect: ((Int) -> Void)?

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
        summon(icons: store.icons, input: input) { [weak self] index in
            if let action = self?.store.config.actions[index] {
                Launcher.run(action)
            }
        }
    }

    func summonRunningApps(input: RingInput = .pointer) {
        let apps = runningApps.snapshot(limit: Self.maxRunningAppWedges)
        guard !apps.isEmpty else { return }   // nothing to switch to → no ring
        summon(icons: apps.map(\.icon), input: input) { index in
            guard apps.indices.contains(index) else { return }
            // openApplication on the running instance restores minimized windows
            // (Dock-reopen semantics); bare activate() leaves them in the Dock.
            Launcher.switchTo(app: apps[index].app)
        }
    }

    /// Shared open path: guards against re-entry, records the commit action, shows the ring.
    private func summon(icons: [NSImage?], input: RingInput, onSelect: @escaping (Int) -> Void) {
        guard !controller.isVisible else { return } // ignore auto-repeat / held input
        self.onSelect = onSelect
        let center = ringCenter(for: input)
        viewModel.begin(centerGlobal: center, wedgeCount: icons.count, input: input)
        let content = RingView(icons: icons, viewModel: viewModel)
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
        let index = viewModel.selectedIndex
        let action = onSelect
        teardown()
        if let index { action?(index) }
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
