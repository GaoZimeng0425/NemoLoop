// NemoLoop/Services/HotkeyService.swift
import AppKit
import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let summonRing = Self("summonRing") // no default binding — user sets it
}

@MainActor
final class HotkeyService {
    private let store: SliceStore
    private let controller: RingWindowController
    private let viewModel: RingViewModel

    init(store: SliceStore, controller: RingWindowController, viewModel: RingViewModel) {
        self.store = store
        self.controller = controller
        self.viewModel = viewModel
    }

    func register() {
        KeyboardShortcuts.onKeyDown(for: .summonRing) { [weak self] in
            self?.summon()
        }
        KeyboardShortcuts.onKeyUp(for: .summonRing) { [weak self] in
            self?.release()
        }
    }

    private func summon() {
        guard !controller.isVisible else { return } // ignore auto-repeat
        let center = NSEvent.mouseLocation
        viewModel.begin(centerGlobal: center)
        let content = RingView(store: store, viewModel: viewModel)
        controller.show(content: content, centeredAtGlobalPoint: center) { [weak self] in
            self?.cancel()
        }
    }

    private func release() {
        guard controller.isVisible else { return }
        let index = viewModel.selectedIndex
        teardown()
        if let index, let url = store.config.slots[index] {
            Launcher.launch(url: url)
        }
    }

    private func cancel() {
        guard controller.isVisible else { return }
        teardown()
    }

    private func teardown() {
        controller.hide()
        viewModel.end()
    }
}
