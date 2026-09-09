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
    func connect() async throws
    func disconnect() async
    var configSections: AnyView? { get }
}

extension NemoPlugin {
    func connect() async throws {}
    func disconnect() async {}
    var configSections: AnyView? { nil }
}
