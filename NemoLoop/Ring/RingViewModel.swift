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

@MainActor
@Observable
final class RingViewModel {
    var isShown = false
    var highlightedIndex: Int?
    /// True while the pointer sits beyond `RingTheme.cancelRadius` (outer-escape
    /// cancel): RingView dims into the "safe cancel" look and `commit()` — which
    /// already no-ops on a nil selection — runs nothing. Vector input never sets it.
    var isCancelling = false
    let deadZoneRadius: CGFloat = 36

    @ObservationIgnored private var centerGlobal: CGPoint = .zero
    @ObservationIgnored private var layout: BladeLayout = BladeLayout.forCount(SliceConfig.wedgeCount)
    @ObservationIgnored private var input: RingInput = .pointer
    @ObservationIgnored private var timer: Timer?

    var selectedIndex: Int? { highlightedIndex }

    func begin(centerGlobal: CGPoint, wedgeCount: Int, input: RingInput = .pointer) {
        self.centerGlobal = centerGlobal
        self.layout = BladeLayout.forCount(wedgeCount)
        self.input = input
        self.highlightedIndex = nil
        self.isCancelling = false
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
        input = .pointer
    }

    func sample() {
        switch input {
        case .pointer:
            updatePointer(at: NSEvent.mouseLocation)
        case let .vector(deadZone, provider):
            // A stick vector is already relative to "center", so measure it from the origin.
            // Releasing the stick IS the commit gesture, so the aim must survive the trip back
            // through the dead zone — keep the last selection instead of clearing it, and
            // never cancel (a saturated stick sits past any radius by definition).
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

    /// Pointer-sample core: selection with both radial bounds, plus the cancel state
    /// past the cancel radius. Split out of `sample()` so the rules stay testable
    /// without live mouse locations.
    func updatePointer(at point: CGPoint) {
        let dx = point.x - centerGlobal.x
        let dy = point.y - centerGlobal.y
        if hypot(dx, dy) > RingTheme.cancelRadius {
            isCancelling = true
            highlightedIndex = nil
            return
        }
        isCancelling = false
        highlightedIndex = RingGeometry.wedgeIndex(
            from: centerGlobal,
            to: point,
            layout: layout,
            deadZoneRadius: deadZoneRadius,
            outerRadius: RingTheme.outerRadius
        )
    }
}
