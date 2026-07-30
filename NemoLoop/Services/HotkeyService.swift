// NemoLoop/Services/HotkeyService.swift
import AppKit
import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let summonRing = Self("summonRing")               // launcher ring — no default binding
    static let summonRunningApps = Self("summonRunningApps") // running-apps ring — no default binding
}

/// Binds the global hotkeys to ring summons: hold to open, release to select.
@MainActor
final class HotkeyService {
    private let summoner: RingSummoner

    init(summoner: RingSummoner) {
        self.summoner = summoner
    }

    func register() {
        KeyboardShortcuts.onKeyDown(for: .summonRing) { [weak self] in
            self?.summoner.summonLauncher()
        }
        KeyboardShortcuts.onKeyDown(for: .summonRunningApps) { [weak self] in
            self?.summoner.summonRunningApps()
        }
        KeyboardShortcuts.onKeyUp(for: .summonRing) { [weak self] in
            self?.summoner.commit()
        }
        KeyboardShortcuts.onKeyUp(for: .summonRunningApps) { [weak self] in
            self?.summoner.commit()
        }
    }
}
