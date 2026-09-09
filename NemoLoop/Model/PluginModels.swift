// NemoLoop/Model/PluginModels.swift
import SwiftUI

/// One plugin operation: an atomic action a ring blade can trigger.
@MainActor
protocol PluginOp: Identifiable {
    var id: String { get }
    var displayName: String { get }
    var symbolName: String { get }
    func perform()
}

enum PluginStatus: Equatable {
    case notInstalled   // dependency missing (e.g. the media plugin's perl bridge)
    case needsAuth      // TCC/login-style authorization still required
    case ready
}

/// One built-in plugin: a family of related operations plus its own connection
/// lifecycle and settings section.
@MainActor
protocol NemoPlugin: Identifiable {
    var id: String { get }
    var displayName: String { get }
    var symbolName: String { get }
    var summary: String { get }
    var operations: [any PluginOp] { get }
    var status: PluginStatus { get }
    /// Factory enablement: with no persisted key, the registry uses this.
    /// Declared as a requirement (not just an extension member) so overrides
    /// dispatch dynamically through `any NemoPlugin` existentials.
    var isEnabledByDefault: Bool { get }
    func connect() async throws
    func disconnect() async
    var configSections: AnyView? { get }
}

extension NemoPlugin {
    func connect() async throws {}
    func disconnect() async {}
    var configSections: AnyView? { nil }
    /// Opt-in model: nothing runs until the user connects it, except plugins
    /// that ship pre-connected by overriding this (the System plugin).
    var isEnabledByDefault: Bool { false }
}
