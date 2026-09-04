// NemoLoop/Ring/RingTheme.swift
import SwiftUI

enum RingTheme {
    // Fan-blade geometry (Dory-style): every blade is a fixed-width sector, laid out
    // edge-to-edge in a fan centered on up; 11 blades fill 330° and leave the gap.
    static let outerRadius: CGFloat = 104
    static let innerRadius: CGFloat = 30          // band thickness = 74 — deep, plump cards (Dory)
    static var midRadius: CGFloat { (innerRadius + outerRadius) / 2 }  // logo orbit = blade view centre
    static let bladeCornerRadius: CGFloat = 18    // fillet on each blade's 4 corners
    static let bladeDegrees: Double = 30          // slot pitch of every blade
    static let bladeOverlapDegrees: Double = 8    // render width = pitch + this (capped at 30% of pitch in RingView)
    static let arcGapDegrees: Double = 30         // min wrap gap between the last blade and the first
    static let bladeViewSide: CGFloat = 88        // local blade view: logo centred, blade within ±37pt
    static let blade3DTiltDegrees: Double = 32    // v5.5: lean hinged at the inner edge — the deep band is what reads the tilt
    static let blade3DPerspective: CGFloat = 0.6 // lower = stronger near-big-far-small
    static let blade3DHingeFraction: CGFloat = 1  // tilt anchor along the band: 0 = logo centre, 1 = inner edge
    static let popOffset: CGFloat = 6             // selected blade slides outward
    static let shadowPad: CGFloat = 14            // frame headroom for pop + shadow

    // Per-blade frosted-glass backing: a LIGHT frosted card (Dory's look) over the
    // wallpaper; icon tiles sit on it with the white overlays below.
    static let glassTint = Color.white.opacity(0.30)

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
    static let iconSize: CGFloat = 32
    static let iconTint = Color.white

    // Depth
    static let shadowRadius: CGFloat = 10
    static let shadowColor = Color.black.opacity(0.22)
    static let bladeShadowRadius: CGFloat = 4            // seam shadow between stacked blades
    static let bladeShadowColor = Color.black.opacity(0.32)

    // Motion
    // Pop-in (1.2→1 scale + fade) is driven by RingView's local `appeared` @State on .onAppear,
    // not a transition — the panel hosts the view only after viewModel.isShown is already true,
    // so an AnyTransition would never animate. `appear` is that pop-in curve.
    static let appear    = Animation.smooth(duration: 0.16)
    static let highlight = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.16)
}
