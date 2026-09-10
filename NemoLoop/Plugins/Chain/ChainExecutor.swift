// NemoLoop/Plugins/Chain/ChainExecutor.swift
import AppKit
import Foundation

/// Testability seam for .app/.folder chain steps (the ShellRunning pattern,
/// but MainActor-confined: NSWorkspace.open is main-thread API and the
/// executor is MainActor, so the seam stays actor-confined and race-free).
@MainActor
protocol AppOpening: AnyObject {
    @discardableResult func open(_ url: URL) -> Bool
}

@MainActor
final class WorkspaceAppOpener: AppOpening {
    /// Nonisolated so `ChainExecutor.init` can default-construct this seam —
    /// default-argument generators are nonisolated in Swift 5 mode; the empty
    /// allocation touches no isolated state.
    nonisolated init() {}

    @discardableResult func open(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }
}

/// Testability seam for the inter-step delay — Task.sleep itself cannot be
/// observed from tests. Suspending on the main actor is fine: suspension
/// never blocks the run loop.
@MainActor
protocol ChainSleeping: AnyObject {
    func sleep(seconds: TimeInterval) async throws
}

@MainActor
final class TaskChainSleeper: ChainSleeping {
    /// Nonisolated for default-argument construction (see WorkspaceAppOpener).
    nonisolated init() {}

    func sleep(seconds: TimeInterval) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }
}

@MainActor
protocol ChainExecuting: AnyObject {
    func run(_ chain: ChainDefinition) async
}

/// Sequential chain runner, semantics pinned by the spec:
///   - steps run in order; the whole run repeats `repeatCount` times;
///   - every step except the run's very first waits `interStepDelay`;
///   - a failed step ABORTS the chain (order-dependent sequences must not
///     limp on half-executed) — already-run steps are not rolled back;
///   - a reentrant trigger of an already-running chain is ignored.
@MainActor
final class ChainExecutor: ChainExecuting {
    private let registry: () -> PluginRegistry
    private let appOpener: any AppOpening
    private let sleeper: any ChainSleeping
    private var runningIDs: Set<UUID> = []

    /// The registry is resolved lazily (factory, default `.shared`) because
    /// PluginRegistry.shared constructs the plugin that owns this executor —
    /// an eager reference would be an initialization cycle.
    init(registry: @escaping () -> PluginRegistry = { .shared },
         appOpener: any AppOpening = WorkspaceAppOpener(),
         sleeper: any ChainSleeping = TaskChainSleeper()) {
        self.registry = registry
        self.appOpener = appOpener
        self.sleeper = sleeper
    }

    func run(_ chain: ChainDefinition) async {
        guard !runningIDs.contains(chain.id) else {
            NSLog("NemoLoop chain: '\(chain.name)' already running — retrigger ignored")
            return
        }
        runningIDs.insert(chain.id)
        defer { runningIDs.remove(chain.id) }

        for iteration in 0..<max(chain.repeatCount, 1) {
            for (index, step) in chain.steps.enumerated() {
                if !(iteration == 0 && index == 0), chain.interStepDelay > 0 {
                    try? await sleeper.sleep(seconds: chain.interStepDelay)
                }
                guard performStep(step) else {
                    NSLog("NemoLoop chain: step \(index + 1) failed — chain '\(chain.name)' aborted")
                    ToastService.shared.show(.error,
                        "Chain '\(chain.name)' failed at step \(index + 1) — aborted")
                    return
                }
            }
        }
    }

    private func performStep(_ step: SlotAction) -> Bool {
        switch step {
        case .pluginOp(let pluginID, let opID):
            return registry().perform(pluginID: pluginID, opID: opID)
        case .app(let url), .folder(let url):
            if appOpener.open(url) { return true }
            NSLog("NemoLoop chain: open failed for \(url.path)")
            return false
        case .plugin:
            NSLog("NemoLoop chain: whole-plugin mount cannot be a chain step (the builder filters it)")
            return false
        }
    }
}
