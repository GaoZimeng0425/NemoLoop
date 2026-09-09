// NemoLoop/Ring/RingSnapshot.swift
import AppKit

/// The value-type payload a ring render needs, captured from the store at
/// summon (or settings-preview render) time. Icon identity stability is the
/// store's job (see `SliceStore.icons` — cached so re-renders don't animate
/// icon swaps); this only packages. Both ring hosts — the real summoner and
/// the Ring tab inspector — compose their four arrays here so the two can
/// never drift apart.
struct RingSnapshot: Equatable {
    /// One entry per blade; `nil` renders the empty "+" slot. `.count` drives
    /// the blade count.
    let icons: [NSImage?]
    /// Sub-action icons per blade, parallel to `icons` — dealt out by dwell.
    let subicons: [[NSImage?]]
    /// Dark-state flags per blade (captured at the same moment as the icons,
    /// so blades don't shift mid-interaction).
    let dimmed: [Bool]
    /// Sub-action counts per blade — only blades with children can dwell open
    /// their sub-wheel.
    let childrenCounts: [Int]

    /// Captures the launcher ring's payload from the store: icons and child
    /// icons from the caches, dark-state flags and children counts from the
    /// config. Only CONFIGURED slots dim — an empty "+" slot has nothing
    /// disconnected to explain, so the placeholder keeps its usual rendering.
    @MainActor
    static func make(store: SliceStore) -> RingSnapshot {
        let dimmed = store.config.slots.map { slot in
            slot.action.map { !store.isEnabled($0) } ?? false
        }
        return RingSnapshot(icons: store.icons,
                            subicons: store.childIcons,
                            dimmed: dimmed,
                            childrenCounts: store.config.slots.map(\.children.count))
    }

    /// `NSImage` isn't Equatable, so equality can't compare icon payloads.
    /// Everything that affects LAYOUT is compared instead: nil-patterns (which
    /// blades render the "+" placeholder), per-blade subicon counts, dimmed
    /// flags, and children counts. Two snapshots with different-but-present
    /// icon instances are equal.
    static func == (lhs: RingSnapshot, rhs: RingSnapshot) -> Bool {
        lhs.icons.count == rhs.icons.count
            && lhs.icons.map { $0 == nil } == rhs.icons.map { $0 == nil }
            && lhs.dimmed == rhs.dimmed
            && lhs.childrenCounts == rhs.childrenCounts
            && lhs.subicons.count == rhs.subicons.count
            && zip(lhs.subicons, rhs.subicons).allSatisfy { $0.count == $1.count }
    }
}
