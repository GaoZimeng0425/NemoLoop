// NemoLoop/Services/HotkeyService.swift
import AppKit
import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let summonRing = Self("summonRing")               // launcher ring — no default binding
    static let summonRunningApps = Self("summonRunningApps") // running-apps ring — no default binding
}

@MainActor
final class HotkeyService {
    /// Max wedges (open apps) shown by the running-apps ring.
    static let maxRunningAppWedges = 10

    private let store: SliceStore
    private let runningApps: RunningAppsService
    private let controller: RingWindowController
    private let viewModel: RingViewModel
    private let appearanceStore: AppearanceStore

    /// The action to run for the wedge the pointer is over when the current ring is released.
    private var onSelect: ((Int) -> Void)?

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

    func register() {
        KeyboardShortcuts.onKeyDown(for: .summonRing) { [weak self] in
            self?.summonLauncher()
        }
        KeyboardShortcuts.onKeyDown(for: .summonRunningApps) { [weak self] in
            self?.summonRunningApps()
        }
        KeyboardShortcuts.onKeyUp(for: .summonRing) { [weak self] in
            self?.release()
        }
        KeyboardShortcuts.onKeyUp(for: .summonRunningApps) { [weak self] in
            self?.release()
        }
    }

    /// For the menu-bar panel's ring button: the drag ends with the pointer over
    /// a blade, so the same release path that closes the hotkey flow picks it.
    func releaseRing() {
        release()
    }

    var isRingVisible: Bool { controller.isVisible }

    // MARK: - Summon flows

    /// Also the menu-bar panel's ring button: press pops the ring, release picks
    /// the wedge — the button replays the hotkey's down/up choreography.
    func summonLauncher() {
        summon(icons: store.icons) { [weak self] index in
            if let url = self?.store.config.slots[index] ?? nil {
                Launcher.launch(url: url)
            }
        }
    }

    private func summonRunningApps() {
        let apps = runningApps.snapshot(limit: Self.maxRunningAppWedges)
        guard !apps.isEmpty else { return }   // nothing to switch to → no ring
        summon(icons: apps.map(\.icon)) { index in
            guard apps.indices.contains(index) else { return }
            Launcher.switchTo(app: apps[index].app)
        }
    }

    /// Shared open path: guards against auto-repeat, records the release action, shows the ring.
    private func summon(icons: [NSImage?], onSelect: @escaping (Int) -> Void) {
        guard !controller.isVisible else { return } // ignore auto-repeat
        self.onSelect = onSelect
        let center = NSEvent.mouseLocation
        viewModel.begin(centerGlobal: center, wedgeCount: icons.count)
        let content = RingView(icons: icons, viewModel: viewModel)
        controller.show(content: content, centeredAtGlobalPoint: center,
                        appearance: appearanceStore.appearance) { [weak self] in
            self?.cancel()
        }
    }

    // MARK: - Dismiss

    private func release() {
        guard controller.isVisible else { return }
        let index = viewModel.selectedIndex
        let action = onSelect
        teardown()
        if let index { action?(index) }
    }

    private func cancel() {
        guard controller.isVisible else { return }
        teardown()
    }

    private func teardown() {
        controller.hide()
        viewModel.end()
        onSelect = nil
    }
}
