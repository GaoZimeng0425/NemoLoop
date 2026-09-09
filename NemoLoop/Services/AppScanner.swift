// NemoLoop/Services/AppScanner.swift
import AppKit
import Foundation

/// One launchable app found on disk. Icons are NOT captured here — the view
/// layer resolves them via NSWorkspace so the model stays testable.
struct AppEntry: Identifiable, Equatable {
    let id: String          // bundleIdentifier when available, else path
    let name: String        // localized display name, falls back to filename
    let url: URL
}

/// NSWorkspace seam — the scanner only needs the localized display name.
protocol WorkspaceDescribing {
    func displayName(forFile path: String) -> String?
}

extension NSWorkspace: WorkspaceDescribing {
    /// NSWorkspace has no display-name API of its own; Finder's localized
    /// name comes from FileManager. Optional keeps the seam fake-friendly.
    func displayName(forFile path: String) -> String? {
        FileManager.default.displayName(atPath: path)
    }
}

@MainActor
enum AppScanner {
    /// Scans the given directories one level deep for .app bundles, dedupes
    /// by id (bundle id or path), sorts by localized name. Called once when
    /// the picker first opens; the caller caches.
    static func scan(dirs: [URL], workspace: WorkspaceDescribing = NSWorkspace.shared) -> [AppEntry] {
        var seen = Set<String>()
        var entries: [AppEntry] = []
        let fm = FileManager.default
        for dir in dirs {
            guard let children = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for url in children where url.pathExtension == "app" {
                // Strip ".app" so names read like Finder ("Safari", not
                // "Safari.app"); fallback mirrors it for the filename path.
                let rawName = workspace.displayName(forFile: url.path)
                    ?? url.deletingPathExtension().lastPathComponent
                let name = rawName.hasSuffix(".app") ? String(rawName.dropLast(4)) : rawName
                // Fixture bundles have no Info.plist, so the path doubles as
                // the id there — same rule as a real bundle missing one.
                let id = Bundle(url: url)?.bundleIdentifier ?? url.path
                guard seen.insert(id).inserted else { continue }
                entries.append(AppEntry(id: id, name: name, url: url))
            }
        }
        return entries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func defaultDirs() -> [URL] {
        [URL(filePath: "/Applications"), URL(filePath: "\(NSHomeDirectory())/Applications")]
    }
}
