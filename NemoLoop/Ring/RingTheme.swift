// NemoLoop/Ring/RingTheme.swift
import SwiftUI

/// The scheme-dependent half of the ring's look: everything tuned to the blade
/// card's own stock (fills, hairlines, face lighting, lift-off shadow). Geometry
/// and motion don't change with appearance and stay in `RingTheme`. `light` is the
/// verified v6.1 look, frozen; `dark` is its opaque warm-charcoal twin — no
/// translucency, same as light: the card is paper, not glass.
struct RingPalette: Equatable {
    let glassTint: Color              // opaque card stock — no wallpaper showing through
    let faceLightStart: Color         // inner-edge sheen of the face-lighting gradient
    let faceLightEnd: Color           // outer-edge falloff
    let baseFill: Color               // assigned, idle — visible tint over glass
    let emptyFill: Color              // empty slot, idle
    let highlightEmpty: Color         // empty slot, highlighted
    let highlightFill: Color          // filled slot, highlighted — the card lights up
    let dividerColor: Color           // hairline between stacked blades
    let bladeCastColor: Color         // directional lift-off shadow

    // Highlight is a WHITE brighten, not an accent fill: the accent gradient mixed
    // the system accent with blue (orange + blue = mud on the light stock), and a
    // saturated colour slab broke the frosted-card language. White needs scheme-
    // specific opacity to read at all — over near-white stock a white 40% overlay
    // moves luminance ~2%; over charcoal the same 40% would flip the card light.
    static let light = RingPalette(
        glassTint: Color(red: 0.95, green: 0.94, blue: 0.92),
        faceLightStart: Color.white.opacity(0.18),
        faceLightEnd: Color.black.opacity(0.06),
        baseFill: Color.white.opacity(0.05),
        emptyFill: Color.white.opacity(0.07),
        highlightEmpty: Color.white.opacity(0.45),
        highlightFill: Color.white.opacity(0.95),
        dividerColor: Color.black.opacity(0.12),
        bladeCastColor: Color.black.opacity(0.16))

    static let dark = RingPalette(
        // Warm charcoal stock; the white overlays become sheens and the hairline
        // flips to a light one so it still reads on the dark card.
        glassTint: Color(red: 0.13, green: 0.125, blue: 0.115),
        faceLightStart: Color.white.opacity(0.10),
        faceLightEnd: Color.black.opacity(0.22),
        baseFill: Color.white.opacity(0.06),
        emptyFill: Color.white.opacity(0.08),
        highlightEmpty: Color.white.opacity(0.18),
        highlightFill: Color.white.opacity(0.32),
        dividerColor: Color.white.opacity(0.14),
        // Dark wallpapers swallow shadows — the cast pushes harder to still lift.
        bladeCastColor: Color.black.opacity(0.28))

    static func palette(for scheme: ColorScheme) -> RingPalette {
        scheme == .dark ? .dark : .light
    }
}

enum RingTheme {
    // Fan-blade geometry (Dory-style): every blade is a fixed-width sector, laid out
    // edge-to-edge in a fan centered on up; 11 blades fill 330° and leave the gap.
    static let outerRadius: CGFloat = 130
    static let innerRadius: CGFloat = 56          // band 60; inner/outer ≈ 0.42 matches the reference's round hole
    static var midRadius: CGFloat { (innerRadius + outerRadius) / 2 }  // logo orbit = blade view centre
    static let bladeCornerRadius: CGFloat = 10   // inner corners
    /// Outer corners — a touch rounder than the inner ones. Much past ~20pt the two
    /// fillets eat the whole outer edge and the card stops reading as a sector.
    static let bladeOuterCornerRadius: CGFloat = 10
    /// Curvature of the outer edge as a multiple of the ring-concentric arc's bulge:
    /// 0 = straight chord, 1 = follows the ring's own circle, >1 bows out into a
    /// fan-blade belly. It is a real circular arc at every value. The rim reads as a
    /// sawtooth regardless, because each card leans and its arc tips off-centre from
    /// the ring's, so neighbouring outer edges meet at stepped corners.
    static let bladeOuterBow: Double = 1.2
    static let bladeDegrees: Double = 30          // slot pitch of every blade
    static let bladeOverlapDegrees: Double = 6    // render width = pitch + this (capped at 45% of pitch in RingView).
                                                  // Must exceed the lean's tangential swing at the inner radius, or the
                                                  // inner arcs stop overlapping and the hole loses its clean circle.
    static let arcGapDegrees: Double = 30         // min wrap gap between the last blade and the first
    static let bladeViewSide: CGFloat = 124        // local blade view: logo centred, blade within ±37pt
    // Fan-blade lean: each card pivots IN PLANE about its inner edge, like a fan
    // blade, so the outer corners step past one another and the ring's outer edge
    // reads as a sawtooth instead of a perfect circle — that jagged silhouette is
    // what makes the fan look tilted. (rotation3DEffect was tried instead: at any
    // angle that stayed legible it barely bent the silhouette while visibly
    // stretching the logos — see spec v6.)
    static let bladeLeanDegrees: Double = -5
    /// Per-card depth tilt (degrees) about the diagonal between the card's radial and
    /// tangential axes: the leading-outer corner sinks, the trailing-inner corner
    /// comes forward. This is the near-big-far-small cue; the logo rides it, so past
    /// ~50° its perspective stretch starts to show.
    static let bladeDepthTiltDegrees: Double = 15
    static let bladeDepthPerspective: CGFloat = 0.4   // lower = stronger perspective
    static let bladeLeanHingeFraction: CGFloat = 0  // pivot along the band: 0 = logo centre, 1 = inner edge
    // Pivoting at the logo (0) is deliberate: with an inner-edge hinge every card
    // sweeps clockwise over its neighbour's leading edge, so the logo — centred on
    // its own card — reads as pushed off-centre. Pivoting at the logo makes the
    // overlap antisymmetric (outer edge one way, inner edge the other) and leaves
    // the logo's own radius unshifted, so it stays visually centred in its wedge.
    static let popOffset: CGFloat = 6             // selected blade slides outward
    static let shadowPad: CGFloat = 14            // frame headroom for pop + shadow

    // Outer-escape cancel: past the blades there is a short grace band where nothing
    // selects (so brushing the rim doesn't drop a selection), and past the cancel
    // radius the ring dims into the translucent "safe cancel" state — releasing
    // there commits nothing.
    static var cancelRadius: CGFloat { outerRadius + 16 }
    static let cancelDimOpacity: Double = 0.35

    // Hairlines (Loop's quinary) — see RingPalette.dividerColor
    static let dividerWidth: CGFloat = 1

    // Icon
    static let iconSize: CGFloat = 38
    static let iconTint = Color.white

    // Depth
    static let shadowRadius: CGFloat = 10
    static let shadowColor = Color.black.opacity(0.10)
    static let bladeShadowRadius: CGFloat = 3            // tight seam shadow between stacked blades
    static let bladeShadowColor = Color.black.opacity(0.20)
    // Directional cast shadow (light from above): what makes each card look lifted
    // off the wallpaper rather than painted on it.
    static let bladeCastRadius: CGFloat = 10
    static let bladeCastOffset = CGSize(width: 0, height: 5)

    // Cascading sub-wheel: dwell this long on a blade that has sub-actions and
    // they deal out as a second ring outside the fan — slim 10° cards on their
    // own fixed pitch (sub j sits j pitches clockwise of its parent). The band
    // tucks 8pt UNDER the blades so the first ring presses on the second and
    // hides its seams (blades zIndex above subs). While the wheel is open the
    // cancel boundary moves out past the subs, or hovering a sub would read as
    // outer-escape.
    static let subDwellDuration: Double = 0.25
    static let subPitchDegrees: Double = 10
    static let subBandInner: CGFloat = 122
    static let subBandOuter: CGFloat = subBandInner + (outerRadius - innerRadius)
    static var subCancelRadius: CGFloat { subBandOuter + 16 }
    static let subPopOffset: CGFloat = 4

    // Motion
    // Pop-in is driven by RingView's local `appeared` @State on .onAppear, not a
    // transition — the panel hosts the view only after viewModel.isShown is already
    // true, so an AnyTransition would never animate.
    // Deal-out: each blade springs into its slot from slightly inside the ring, in
    // index order (clockwise from 12 o'clock) — the fan unfolds card by card
    // instead of the whole ring sliding in as one piece.
    static let bladeAppear = Animation.spring(response: 0.24, dampingFraction: 0.74)
    static let bladeStagger: Double = 0.026       // delay per blade
    static let bladeAppearInset: CGFloat = 22     // starts this far toward the ring centre
    static let bladeAppearScale: CGFloat = 0.78   // and this much smaller
    static let highlight = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.16)
}
