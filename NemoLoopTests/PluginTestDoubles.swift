import Foundation
@testable import NemoLoop

/// Shared plugin doubles for registry/routing tests: counting ops, a stub
/// plugin that can fail connect on demand, and a scrubbed throwaway defaults
/// suite. Tests assert through `performedCount` / `connectCalls` /
/// `disconnectCalls`, never through mocks-of-mocks.
@MainActor
final class StubOp: PluginOp {
    let id: String
    let displayName: String
    let symbolName: String
    private(set) var performedCount = 0

    init(_ id: String) {
        self.id = id
        displayName = id
        symbolName = "circle"
    }

    func perform() { performedCount += 1 }
}

@MainActor
final class StubPlugin: NemoPlugin {
    let id: String
    let displayName: String
    let symbolName: String
    let summary = "test double"
    let ops: [any PluginOp]
    var connectError: Error?
    private(set) var connectCalls = 0
    private(set) var disconnectCalls = 0

    init(id: String = "stub", _ ops: [any PluginOp]) {
        self.id = id
        displayName = id
        symbolName = "puzzlepiece"
        self.ops = ops
    }

    /// Convenience for capacity tests: ops named `op0…op(n−1)`.
    convenience init(id: String = "stub", opCount: Int) {
        self.init(id: id, (0..<opCount).map { StubOp("op\($0)") })
    }

    var operations: [any PluginOp] { ops }
    var status: PluginStatus { .ready }

    func connect() async throws {
        connectCalls += 1
        if let connectError { throw connectError }
    }

    func disconnect() async { disconnectCalls += 1 }
}

/// A fresh, scrubbed UserDefaults suite — each call returns an isolated one.
@MainActor
func makeDefaults() -> UserDefaults {
    let name = "plugin-test-doubles-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

/// Op whose perform() runs an injected closure — for tests that need custom
/// observation (ordering logs, gates) beyond StubOp's counter.
@MainActor
final class ClosureOp: PluginOp {
    let id: String
    let displayName: String
    let symbolName: String
    let onPerform: () -> Void

    init(_ id: String, onPerform: @escaping () -> Void = {}) {
        self.id = id
        displayName = id
        symbolName = "circle"
        self.onPerform = onPerform
    }

    func perform() { onPerform() }
}
