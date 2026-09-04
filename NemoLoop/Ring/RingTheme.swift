// NemoLoop/Ring/RingTheme.swift
import SwiftUI

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
    static let bladeLeanDegrees: Double = 5
    static let bladeLeanHingeFraction: CGFloat = 0  // pivot along the band: 0 = logo centre, 1 = inner edge
    // Pivoting at the logo (0) is deliberate: with an inner-edge hinge every card
    // sweeps clockwise over its neighbour's leading edge, so the logo — centred on
    // its own card — reads as pushed off-centre. Pivoting at the logo makes the
    // overlap antisymmetric (outer edge one way, inner edge the other) and leaves
    // the logo's own radius unshifted, so it stays visually centred in its wedge.
    static let popOffset: CGFloat = 6             // selected blade slides outward
    static let shadowPad: CGFloat = 14            // frame headroom for pop + shadow

    // Per-blade frosted-glass backing: a LIGHT frosted card (Dory's look) over the
    // wallpaper; icon tiles sit on it with the white overlays below.
    static let glassTint = Color(red: 0.95, green: 0.94, blue: 0.92)   // opaque card stock — no wallpaper showing through

    /// Face lighting: each card is brighter at its inner edge and falls off toward the
    /// outer edge, so a flat plate reads as a tilted one (the reference's depth cue).
    static let faceLightStart = Color.white.opacity(0.18)   // inner edge
    static let faceLightEnd   = Color.black.opacity(0.06)   // outer edge

    // Accent gradient (Loop's color1 → color2, diagonal)
    static let accentStart = Color.accentColor
    static let accentEnd   = Color.accentColor.mix(with: .blue, by: 0.45)
    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accentStart, accentEnd],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // Surfaces / state fills — translucent so the frosted glass shows through.
    static let baseFill        = Color.white.opacity(0.05)   // assigned, idle — visible tint over glass
    static let emptyFill       = Color.white.opacity(0.07)   // empty slot, idle
    static let highlightEmpty  = Color.white.opacity(0.16)   // empty slot, highlighted

    // Hairlines (Loop's quinary) — dark enough to read on the light frosted card
    static let dividerColor = Color.black.opacity(0.12)
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
    static let bladeCastColor = Color.black.opacity(0.16)
    static let bladeCastOffset = CGSize(width: 0, height: 5)

    // Motion
    // Pop-in is driven by RingView's local `appeared` @State on .onAppear, not a
    // transition — the panel hosts the view only after viewModel.isShown is already
    // true, so an AnyTransition would never animate.
    // Deal-out: each blade springs into its slot from slightly inside the ring, in
    // index order (clockwise from 12 o'clock) — the fan unfolds card by card
    // instead of the whole ring sliding in as one piece.
    static let bladeAppear = Animation.spring(response: 0.30, dampingFraction: 0.74)
    static let bladeStagger: Double = 0.032       // delay per blade
    static let bladeAppearInset: CGFloat = 22     // starts this far toward the ring centre
    static let bladeAppearScale: CGFloat = 0.78   // and this much smaller
    static let highlight = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.16)
}
