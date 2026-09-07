import AppKit
import Foundation
import Observation

/// Where the highlighted wedge is sampled from.
enum RingInput {
    /// Angle of the cursor relative to the ring center (hotkey rings).
    case pointer
    /// A direction vector in y-up unit space, e.g. a thumbstick (game controller rings).
    /// The ring center is irrelevant — the vector already *is* the direction.
    case vector(deadZone: CGFloat, provider: () -> CGPoint)
}

/// What a release will run: the highlighted blade, or one of its sub-actions
/// while that blade's sub-wheel is open and a sub-blade is hovered.
struct RingSelection: Equatable {
    let index: Int
    let subIndex: Int?
}

@MainActor
@Observable
final class RingViewModel {
    var isShown = false
    var highlightedIndex: Int?
    /// True while the pointer sits beyond `RingTheme.cancelRadius` (outer-escape
    /// cancel): RingView dims into the "safe cancel" look and `commit()` — which
    /// already no-ops on a nil selection — runs nothing. Vector input never sets it.
    var isCancelling = false
    /// Blade whose sub-actions are dealt out (dwell opened it).
    private(set) var openSubIndex: Int?
    /// Hovered sub-action inside the open sub-wheel.
    private(set) var hoveredSubIndex: Int?
    let deadZoneRadius: CGFloat = 36

    @ObservationIgnored private var centerGlobal: CGPoint = .zero
    @ObservationIgnored private var layout: BladeLayout = BladeLayout.forCount(SliceConfig.wedgeCount)
    @ObservationIgnored private var input: RingInput = .pointer
    @ObservationIgnored private var timer: Timer?
    /// Sub-action counts per blade (from the summoner) — only blades with
    /// children can dwell open their sub-wheel.
    @ObservationIgnored private var childrenCounts: [Int] = []
    @ObservationIgnored private var dwellAnchor: Int?
    @ObservationIgnored private var dwellDeadline: Date?
    /// Injectable clock so the dwell rules are testable.
    @ObservationIgnored var now: () -> Date = Date.init

    var selection: RingSelection? {
        guard let index = highlightedIndex else { return nil }
        if index == openSubIndex, let sub = hoveredSubIndex {
            return RingSelection(index: index, subIndex: sub)
        }
        return RingSelection(index: index, subIndex: nil)
    }

    func begin(centerGlobal: CGPoint, wedgeCount: Int, childrenCounts: [Int] = [], input: RingInput = .pointer) {
        self.centerGlobal = centerGlobal
        self.layout = BladeLayout.forCount(wedgeCount)
        self.childrenCounts = childrenCounts
        self.input = input
        self.highlightedIndex = nil
        self.isCancelling = false
        self.openSubIndex = nil
        self.hoveredSubIndex = nil
        self.dwellAnchor = nil
        self.dwellDeadline = nil
        self.isShown = true
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func end() {
        timer?.invalidate()
        timer = nil
        isShown = false
        highlightedIndex = nil
        isCancelling = false
        openSubIndex = nil
        hoveredSubIndex = nil
        dwellAnchor = nil
        dwellDeadline = nil
        input = .pointer
    }

    func sample() {
        switch input {
        case .pointer:
            updatePointer(at: NSEvent.mouseLocation, now: now())
        case let .vector(deadZone, provider):
            // A stick vector is already relative to "center", so measure it from the origin.
            // Releasing the stick IS the commit gesture, so the aim must survive the trip back
            // through the dead zone — keep the last selection instead of clearing it, and
            // never cancel (a saturated stick sits past any radius by definition). Sticks
            // get no sub-wheels: there is no cursor to dwell with.
            if let index = RingGeometry.wedgeIndex(
                from: .zero,
                to: provider(),
                layout: layout,
                deadZoneRadius: deadZone
            ) {
                highlightedIndex = index
            }
        }
    }

    /// Pointer-sample core: selection with both radial bounds, the cancel state
    /// past the cancel radius, and the dwell-driven sub-wheel. Split out of
    /// `sample()` so the rules stay testable without live mouse locations.
    func updatePointer(at point: CGPoint, now moment: Date? = nil) {
        let moment = moment ?? now()
        let dx = point.x - centerGlobal.x
        let dy = point.y - centerGlobal.y
        let distance = hypot(dx, dy)
        // With a wheel open the outer world is the sub ring, so the escape
        // boundary moves past it — otherwise reaching a sub would cancel.
        let cancelBoundary = openSubIndex != nil ? RingTheme.subCancelRadius : RingTheme.cancelRadius
        if distance > cancelBoundary {
            isCancelling = true
            highlightedIndex = nil
            closeSubs()
            return
        }
        isCancelling = false

        // Sub hover wins inside the open wheel's band; the parent stays the
        // highlighted blade while its wheel is open.
        hoveredSubIndex = nil
        if let open = openSubIndex, childrenCounts.indices.contains(open) {
            hoveredSubIndex = RingGeometry.subIndex(
                parent: open,
                angle: RingGeometry.angle(from: centerGlobal, to: point),
                distance: distance,
                layout: layout,
                childCount: childrenCounts[open],
                innerRadius: RingTheme.subBandInner,
                outerRadius: RingTheme.subBandOuter
            )
        }
        highlightedIndex = RingGeometry.wedgeIndex(
            from: centerGlobal,
            to: point,
            layout: layout,
            deadZoneRadius: deadZoneRadius,
            outerRadius: RingTheme.outerRadius
        )
        // While a sub is under the pointer the parent stays the highlighted
        // blade: the sub ring now lives OUTSIDE the blade band, where the wedge
        // mapping has nothing — leaving it nil would dim the parent and make
        // `selection` (which keys off the highlighted blade) drop the sub.
        if hoveredSubIndex != nil, let open = openSubIndex {
            highlightedIndex = open
        }
        // Landing on a DIFFERENT blade sweeps the wheel away; crossing the outer
        // bands (sub ring / grace) on the way to a sub — or back — keeps it open.
        if let open = openSubIndex, hoveredSubIndex == nil,
           let landed = highlightedIndex, landed != open {
            closeSubs()
        }
        updateDwell(for: highlightedIndex, at: moment)
    }

    private func updateDwell(for index: Int?, at moment: Date) {
        guard let index, childrenCounts.indices.contains(index), childrenCounts[index] > 0 else {
            dwellAnchor = nil
            dwellDeadline = nil
            return
        }
        if dwellAnchor != index {
            dwellAnchor = index
            dwellDeadline = moment.addingTimeInterval(RingTheme.subDwellDuration)
        } else if openSubIndex != index, let deadline = dwellDeadline, moment >= deadline {
            openSubIndex = index
        }
    }

    private func closeSubs() {
        openSubIndex = nil
        hoveredSubIndex = nil
        dwellAnchor = nil
        dwellDeadline = nil
    }
}
