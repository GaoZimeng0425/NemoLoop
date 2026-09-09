// NemoLoop/Settings/RingTabInspector.swift
import SwiftUI

/// The permanent mini-ring preview in the Ring tab's inspector column.
/// Reuses the real RingView + RingViewModel (`isSettingsPreview`: no global
/// input sampling, no 120 Hz sampler — see begin()'s gating), so highlight,
/// dwell-dealt sub-wheels and the dimmed cancel look behave exactly like the
/// summoned ring. Input arrives exclusively from SwiftUI gestures and the idle
/// carousel below.
///
/// Coordinates: the vm only ever measures point − center, so everything stays
/// in ONE space — this frame's local space, mirrored to y-up. SwiftUI locals
/// are y-down while the ring's angle math (`atan2(dx, dy)`, 0° = up, clockwise)
/// is y-up, so ingested points flip across the frame midline at the boundary;
/// the begin center (the frame midpoint) is its own mirror and needs no flip.
struct RingTabInspector: View {
    @Bindable var store: SliceStore
    /// Selected slot in the left-hand slot list — tapping a configured blade
    /// selects it there (list ↔ ring linkage).
    @Binding var selectedSlot: Int?
    /// Called when an EMPTY blade is clicked — the parent opens the picker
    /// popover anchored here (spec: empty-blade click = configure directly).
    let configureSlot: (Int) -> Void

    @State private var viewModel = RingViewModel()
    /// True while the pointer is inside the frame, with the last seen point.
    /// The point is re-sent on the preview loop's ticks because dwell must
    /// complete under a perfectly still pointer — `onContinuousHover` only
    /// fires on movement, and in preview mode nothing else drives the vm.
    @State private var isHovering = false
    @State private var lastHoverPoint: CGPoint?
    /// When interaction (hover or click) last happened; the idle carousel
    /// resumes 3s after this goes quiet, Loop-style.
    @State private var lastInteractionAt: Date?
    /// Current carousel blade (advanced once per idle second).
    @State private var carouselIndex = 0

    /// Ring frame. The blade fan (outer radius 130) reads at near-full scale.
    private let side: CGFloat = 240

    init(store: SliceStore, selectedSlot: Binding<Int?>, configureSlot: @escaping (Int) -> Void) {
        self._store = Bindable(store)
        self._selectedSlot = selectedSlot
        self.configureSlot = configureSlot
    }

    private var snapshot: RingSnapshot { RingSnapshot.make(store: store) }

    /// Ring center in this frame's local (and, being the midpoint, the
    /// y-up-mirrored) space.
    private var centerLocal: CGPoint { CGPoint(x: side / 2, y: side / 2) }

    var body: some View {
        let snap = snapshot
        RingView(icons: snap.icons, viewModel: viewModel,
                 subicons: snap.subicons, dimmed: snap.dimmed, preAppeared: true)
            .environment(\.ringCenter, centerLocal)
            .frame(width: side, height: side)
            // The whole square is interactive — cards, gaps and hole included —
            // so hover/click never drop out between blades.
            .contentShape(Rectangle())
            .onAppear { beginPreview(with: snapshot) }
            .onContinuousHover { phase in handleHover(phase) }
            // DragGesture(minimumDistance: 0) is the macOS way to get a CLICK
            // WITH location — onTapGesture doesn't carry coordinates.
            .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                handleTap(at: value.location, snapshot: snap)
            })
            .task { await runPreviewLoop() }
            // Config edits (picker commits) change wedge content: re-begin the
            // vm so layouts/children counts track the store. The vm is a
            // reference held by @State — re-begin resets state in place.
            .onChange(of: store.config) { _, _ in beginPreview(with: snapshot) }
    }

    // MARK: - Preview lifecycle

    /// (Re)starts the preview vm. `isSettingsPreview` goes up BEFORE begin so
    /// the 120 Hz sampler is never scheduled; the neutral zero vector is a
    /// belt in case the flag ever lags a begin — a zero vector samples nothing.
    private func beginPreview(with snap: RingSnapshot) {
        viewModel.isSettingsPreview = true
        viewModel.begin(centerGlobal: centerLocal,
                        wedgeCount: snap.icons.count,
                        childrenCounts: snap.childrenCounts,
                        input: .vector(deadZone: viewModel.deadZoneRadius) { .zero })
    }

    private func handleHover(_ phase: HoverPhase) {
        lastInteractionAt = Date()
        switch phase {
        case .active(let point):
            isHovering = true
            lastHoverPoint = point
            viewModel.updatePointer(at: toRingSpace(point))
        case .ended:
            // Pointer left the frame: stop feeding the vm — the last highlight
            // freezes here and the carousel picks back up 3s later.
            isHovering = false
        @unknown default:
            break
        }
    }

    private func handleTap(at point: CGPoint, snapshot snap: RingSnapshot) {
        lastInteractionAt = Date()
        // A click implies the pointer sits here — keep the hover feed alive so
        // the highlighted blade doesn't drop before the popover opens.
        isHovering = true
        lastHoverPoint = point
        guard !snap.icons.isEmpty else { return }
        // Same hit math as the real ring's wedge mapping: the vm's dead zone
        // (36pt — the hole's core) as the inner bound, and the ring composite's
        // full interactive radius as the outer — subCancelRadius covers the
        // blade band AND the dealt sub ring, so tapping a sub resolves to its
        // parent blade; the wrap gap still maps to nil.
        guard let index = RingGeometry.wedgeIndex(
            from: centerLocal,
            to: toRingSpace(point),
            layout: BladeLayout.forCount(snap.icons.count),
            deadZoneRadius: viewModel.deadZoneRadius,
            outerRadius: RingTheme.subCancelRadius) else { return }
        if snap.icons[index] == nil {
            configureSlot(index)     // empty blade → picker (parent anchors it)
        } else {
            selectedSlot = index     // configured blade → select + list linkage
        }
    }

    // MARK: - Idle carousel

    /// Single driver for everything the real ring's sampler would do, ticked at
    /// 50 ms (fine enough that the 0.25 s dwell reads exactly like the live ring):
    /// - hovering → re-send the last hover point (dwell completes under a still
    ///   pointer; see `lastHoverPoint`);
    /// - idle for 3 s → carousel: advance to the next blade every 1 s and
    ///   re-point at its center each tick, so the REAL dwell state machine
    ///   highlights it and — on a blade with children — deals the sub-wheel
    ///   mid-slot, Loop-style;
    /// - cooldown (pointer just left) → send nothing; the highlight freezes
    ///   until the carousel resumes.
    @MainActor
    private func runPreviewLoop() async {
        var lastAdvance = Date.distantPast
        while !Task.isCancelled {
            let moment = Date()
            if isHovering, let point = lastHoverPoint {
                viewModel.updatePointer(at: toRingSpace(point))
            } else if moment.timeIntervalSince(lastInteractionAt ?? .distantPast) >= 3 {
                let snap = snapshot   // fresh every tick — config edits track live
                if moment.timeIntervalSince(lastAdvance) >= 1 {
                    carouselIndex = (carouselIndex + 1) % max(snap.icons.count, 1)
                    lastAdvance = moment
                }
                viewModel.updatePointer(at: carouselPoint(for: carouselIndex, snapshot: snap))
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// The synthetic pointer for carousel blade `i`: its slot-center angle at
    /// 0.7 × the outer radius — just inside the blade band. Built directly in
    /// the vm's y-up convention (up = +Y), so no flip is needed.
    private func carouselPoint(for index: Int, snapshot snap: RingSnapshot) -> CGPoint {
        let layout = BladeLayout.forCount(snap.icons.count)
        let angle = layout.centerAngle(index) * .pi / 180
        let radius = RingTheme.outerRadius * 0.7
        return CGPoint(x: centerLocal.x + sin(angle) * radius,
                       y: centerLocal.y + cos(angle) * radius)
    }

    /// Mirrors a local (y-down) point into the ring's y-up math space.
    private func toRingSpace(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x, y: side - p.y)
    }
}
