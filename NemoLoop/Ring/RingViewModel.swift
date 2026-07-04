import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class RingViewModel {
    var isShown = false
    var highlightedIndex: Int?
    let deadZoneRadius: CGFloat = 36

    @ObservationIgnored private var centerGlobal: CGPoint = .zero
    @ObservationIgnored private var wedgeCount: Int = SliceConfig.wedgeCount
    @ObservationIgnored private var timer: Timer?

    var selectedIndex: Int? { highlightedIndex }

    func begin(centerGlobal: CGPoint, wedgeCount: Int) {
        self.centerGlobal = centerGlobal
        self.wedgeCount = wedgeCount
        self.highlightedIndex = nil
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
    }

    private func sample() {
        highlightedIndex = RingGeometry.wedgeIndex(
            from: centerGlobal,
            to: NSEvent.mouseLocation,
            wedgeCount: wedgeCount,
            deadZoneRadius: deadZoneRadius
        )
    }
}
