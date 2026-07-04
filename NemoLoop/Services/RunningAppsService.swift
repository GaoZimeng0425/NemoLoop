// NemoLoop/Services/RunningAppsService.swift
import AppKit
import Foundation
import Observation

/// A snapshot entry for one running application.
struct RunningApp: Identifiable {
    let app: NSRunningApplication
    let name: String
    let icon: NSImage?

    var id: pid_t { app.processIdentifier }
}

/// Tracks running applications in most-recently-used order by observing activations.
/// Long-lived (owned by AppDelegate); the running-apps ring reads a `snapshot` on summon.
@MainActor
@Observable
final class RunningAppsService {
    /// pids in most-recently-used order (front = most recent). @ObservationIgnored:
    /// consumers pull a `snapshot` on demand, they don't observe the raw order.
    @ObservationIgnored private var mru: [pid_t] = []
    @ObservationIgnored private var observer: NSObjectProtocol?

    init() {
        // Seed with the current frontmost app so the first summon has a sensible order.
        if let front = NSWorkspace.shared.frontmostApplication {
            mru = [front.processIdentifier]
        }
        let center = NSWorkspace.shared.notificationCenter
        observer = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated { self?.handleActivation(note) }
        }
    }

    deinit {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    private func handleActivation(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        else { return }
        let pid = app.processIdentifier
        mru.removeAll { $0 == pid }
        mru.insert(pid, at: 0)
    }

    /// Regular, non-terminated apps (excluding NemoLoop itself), MRU-first, capped to `limit`.
    func snapshot(limit: Int) -> [RunningApp] {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier != selfPID }
            .map { RunningApp(app: $0, name: $0.localizedName ?? "", icon: $0.icon) }
        return Self.order(apps, mru: mru, limit: limit, id: \.id)
    }

    /// Pure ordering: items whose id is present in `mru` come first in MRU order; the rest
    /// keep their incoming (system) order, appended after. Result is truncated to `limit`.
    /// Generic over id so it can be tested without constructing `NSRunningApplication`.
    nonisolated static func order<T>(_ items: [T], mru: [pid_t], limit: Int, id: (T) -> pid_t) -> [T] {
        let rank = Dictionary(uniqueKeysWithValues: mru.enumerated().map { ($1, $0) })
        let known = items.filter { rank[id($0)] != nil }.sorted { rank[id($0)]! < rank[id($1)]! }
        let unknown = items.filter { rank[id($0)] == nil }
        return Array((known + unknown).prefix(limit))
    }
}
