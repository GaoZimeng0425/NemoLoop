// NemoLoopTests/RingSnapshotTests.swift
import Testing
import AppKit
import Foundation
@testable import NemoLoop

/// `RingSnapshot`: the value-type render payload captured from the store at
/// summon (or settings-preview) time — shared by the real summoner and the
/// Ring tab inspector so both compose the four arrays identically.
@MainActor
struct RingSnapshotTests {
    private func makeStore() -> SliceStore {
        let name = "ring-snapshot-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return SliceStore(defaults: d)
    }

    @Test func snapshotMirrorsStoreArrays() {
        let store = makeStore()
        store.setAction(.app(URL(filePath: "/Applications/Safari.app")), at: 0)
        store.addChild(.pluginOp(pluginID: "system", opID: "lockScreen"), at: 0)
        store.setAction(.plugin("system"), at: 1)

        let snap = RingSnapshot.make(store: store)
        #expect(snap.icons.count == 6)
        #expect(snap.icons[0] != nil && snap.icons[1] != nil && snap.icons[2] == nil)
        #expect(snap.childrenCounts[0] == 1)
        #expect(snap.dimmed[0] == false)   // app slots are always enabled
        #expect(snap.dimmed[1] == false)   // system plugin connected (factory default)
        #expect(snap.subicons[0].count == 1)
    }

    @Test func emptySlotsAreNeverDimmed() {
        // An empty "+" slot has nothing disconnected to explain — the dimmed
        // flag only describes a CONFIGURED slot whose plugin went away.
        let store = makeStore()
        let snap = RingSnapshot.make(store: store)
        #expect(snap.dimmed == Array(repeating: false, count: 6))
        #expect(snap.icons.allSatisfy { $0 == nil })
        #expect(snap.childrenCounts == Array(repeating: 0, count: 6))
    }

    // MARK: - Hand-rolled equality

    /// `NSImage` isn't Equatable, so `==` can't compare icon payloads. It must
    /// compare everything that affects LAYOUT: nil-patterns (which blades render
    //  the "+" placeholder), subicon counts per blade (sub-wheel fan-out), the
    /// dimmed flags, and the children counts.
    @Test func equalityIgnoresIconIdentity() {
        let a = RingSnapshot(icons: [NSImage(), nil, NSImage()],
                             subicons: [[NSImage()], [], []],
                             dimmed: [false, false, true],
                             childrenCounts: [1, 0, 0])
        // Different NSImage instances, identical structure → equal.
        let b = RingSnapshot(icons: [NSImage(), nil, NSImage()],
                             subicons: [[NSImage()], [], []],
                             dimmed: [false, false, true],
                             childrenCounts: [1, 0, 0])
        #expect(a == b)
    }

    @Test func equalityDetectsStructuralDifferences() {
        let base = RingSnapshot(icons: [NSImage(), nil],
                                subicons: [[NSImage(), NSImage()], []],
                                dimmed: [false, false],
                                childrenCounts: [2, 0])

        #expect(base != RingSnapshot(icons: [nil, nil],            // nil-pattern changed
                                     subicons: [[NSImage(), NSImage()], []],
                                     dimmed: [false, false],
                                     childrenCounts: [2, 0]))
        #expect(base != RingSnapshot(icons: [NSImage(), nil],
                                     subicons: [[NSImage()], []],  // subicon count changed
                                     dimmed: [false, false],
                                     childrenCounts: [2, 0]))
        #expect(base != RingSnapshot(icons: [NSImage(), nil],
                                     subicons: [[NSImage(), NSImage()], []],
                                     dimmed: [true, false],         // dimmed changed
                                     childrenCounts: [2, 0]))
        #expect(base != RingSnapshot(icons: [NSImage(), nil],
                                     subicons: [[NSImage(), NSImage()], []],
                                     dimmed: [false, false],
                                     childrenCounts: [3, 0]))       // children count changed
        #expect(base != RingSnapshot(icons: [NSImage()],            // blade count changed
                                     subicons: [[NSImage(), NSImage()]],
                                     dimmed: [false],
                                     childrenCounts: [2]))
    }
}
