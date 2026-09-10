// NemoLoop/Services/Toast/ToastService.swift
import SwiftUI

enum ToastKind { case success, error, info }

/// Testability seam for the dismiss timeline (the ChainSleeping pattern):
/// Task.sleep itself cannot be observed from tests.
@MainActor
protocol ToastSleeping: AnyObject {
    func sleep(seconds: TimeInterval) async throws
}

@MainActor
final class TaskToastSleeper: ToastSleeping {
    /// Nonisolated for default-argument construction (WorkspaceAppOpener idiom).
    nonisolated init() {}

    func sleep(seconds: TimeInterval) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }
}

/// Global toast channel: any module calls `ToastService.shared.show(...)` and
/// a black capsule appears bottom-center on the mouse's screen. Pure state
/// machine — windows are owned by ToastWindowController, so this is fully
/// testable headless.
///
/// Timeline (NemoNotch CompletionFlashService's validated pattern):
/// show() → current/visible/panelWanted immediately true → after
/// `toastDuration` (error: `errorDuration`) visible animates false → one
/// `fadeDuration` later panelWanted drops and current clears. panelWanted
/// deliberately falls LAST: the fading animation still needs the window.
@MainActor
@Observable
final class ToastService {
    static let shared = ToastService()

    struct Toast: Equatable {
        let kind: ToastKind
        let text: String
    }

    private(set) var current: Toast?
    private(set) var visible = false
    private(set) var panelWanted = false

    private let sleeper: any ToastSleeping
    private let toastDuration: TimeInterval
    private let errorDuration: TimeInterval
    private let fadeDuration: TimeInterval
    private var dismissTask: Task<Void, Never>?

    init(sleeper: any ToastSleeping = TaskToastSleeper(),
         toastDuration: TimeInterval = 2.0,
         errorDuration: TimeInterval = 3.5,
         fadeDuration: TimeInterval = 0.25) {
        self.sleeper = sleeper
        self.toastDuration = toastDuration
        self.errorDuration = errorDuration
        self.fadeDuration = fadeDuration
    }

    /// Later toast wins: replaces immediately and restarts the dismiss
    /// timeline (no queueing — only one capsule is ever on screen).
    func show(_ kind: ToastKind, _ text: String) {
        current = Toast(kind: kind, text: text)
        visible = true
        panelWanted = true
        restartDismiss(for: kind)
    }

    private func duration(for kind: ToastKind) -> TimeInterval {
        kind == .error ? errorDuration : toastDuration
    }

    private func restartDismiss(for kind: ToastKind) {
        dismissTask?.cancel()
        let wait = duration(for: kind)
        let fade = fadeDuration
        dismissTask = Task { @MainActor [weak self] in
            try? await self?.sleeper.sleep(seconds: wait)
            guard let self, !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: fade)) {
                self.visible = false
            }
            try? await self.sleeper.sleep(seconds: fade)
            guard !Task.isCancelled else { return }
            self.panelWanted = false
            self.current = nil
        }
    }
}
