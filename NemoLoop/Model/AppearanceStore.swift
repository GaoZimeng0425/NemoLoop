import AppKit
import Foundation
import Observation

/// Ring theme choice. `.auto` follows the system appearance; the other two force
/// one look regardless of system setting. Raw values are what lands in UserDefaults.
enum RingAppearance: String, CaseIterable, Identifiable {
    case auto, light, dark

    var id: Self { self }

    /// What `NSPanel.appearance` should be for this choice — `nil` (follow system)
    /// for `.auto`, a concrete appearance otherwise.
    var nsAppearance: NSAppearance? {
        switch self {
        case .auto: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

@MainActor
@Observable
final class AppearanceStore {
    static let defaultsKey = "nemoloop.ringAppearance"

    private let defaults: UserDefaults

    var appearance: RingAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: Self.defaultsKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Unknown raw values (hand-edited defaults, older formats) fall back to auto.
        self.appearance = RingAppearance(rawValue: defaults.string(forKey: Self.defaultsKey) ?? "") ?? .auto
    }
}
