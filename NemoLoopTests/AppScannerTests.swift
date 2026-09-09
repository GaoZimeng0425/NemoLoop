import Testing
import Foundation
@testable import NemoLoop

// @MainActor because AppScanner.scan and its NSWorkspace.shared default
// argument are MainActor-isolated.
@MainActor
struct AppScannerTests {
    /// FileManager-driven fake: lists .app bundles under fixture dirs.
    /// UUID-based roots keep every test independent — no shared fixtures.
    private func makeFixture(_ names: [String]) -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("app-scanner-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for name in names {
            let appDir = root.appendingPathComponent("\(name).app")
            try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        }
        return root
    }

    private final class FakeWorkspace: WorkspaceDescribing {
        // Keyed by bundle filename, not full path: FileManager canonicalizes
        // temp-dir listings (/var/folders → /private/var/folders), so exact
        // full-path keys would silently miss.
        var displayNames: [String: String] = [:]
        func displayName(forFile path: String) -> String? {
            displayNames[(path as NSString).lastPathComponent]
        }
    }

    @Test func scansAppBundlesWithLocalizedNamesSorted() {
        let dir = makeFixture(["Zeplin", "Safari", "Notes"])
        let ws = FakeWorkspace()
        ws.displayNames["Safari.app"] = "Safari"
        ws.displayNames["Notes.app"] = "备忘录"
        ws.displayNames["Zeplin.app"] = "Zeplin"

        let entries = AppScanner.scan(dirs: [dir], workspace: ws)
        let names = entries.map(\.name)

        // Ordering: sort uses localizedCaseInsensitiveCompare, which follows
        // the user locale — where 备忘录 lands relative to the Latin names is
        // locale-dependent (before "Safari" under zh_CN pinyin collation,
        // after "Zeplin" elsewhere). Only the relative order of the ASCII
        // names is stable across locales, so that's all we assert.
        #expect(names.contains("Safari"))
        #expect(names.contains("Zeplin"))
        if let safari = names.firstIndex(of: "Safari"),
           let zeplin = names.firstIndex(of: "Zeplin") {
            #expect(safari < zeplin, "Safari must sort before Zeplin, got \(names)")
        }

        // Localized-name mapping, asserted independently of collation:
        // Notes.app surfaces under its Finder display name 备忘录.
        let notes = entries.first { $0.url.lastPathComponent == "Notes.app" }
        #expect(notes?.name == "备忘录")

        #expect(entries.allSatisfy { $0.url.pathExtension == "app" })
        #expect(entries.allSatisfy { $0.id.contains(".app") }) // no bundle id → path is the id
    }

    @Test func dedupesAcrossDirsByPath() {
        let a = makeFixture(["Safari"])
        let b = makeFixture(["Safari"])   // same name, different dir → both kept (different paths)
        let entries = AppScanner.scan(dirs: [a, b])
        #expect(entries.filter { $0.name == "Safari" }.count == 2)
    }

    @Test func skipsNonAppBundles() {
        let dir = makeFixture(["Good"])
        try? FileManager.default.createDirectory(
            at: dir.appendingPathComponent("README.txt"), withIntermediateDirectories: true)
        let entries = AppScanner.scan(dirs: [dir])
        #expect(entries.count == 1)
    }

    @Test func defaultDirsCoverBothApplicationRoots() {
        let dirs = AppScanner.defaultDirs()
        #expect(dirs.contains(URL(filePath: "/Applications")))
        #expect(dirs.contains(URL(filePath: "\(NSHomeDirectory())/Applications")))
    }
}
