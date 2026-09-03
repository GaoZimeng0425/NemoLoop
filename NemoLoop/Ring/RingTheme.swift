// NemoLoop/Ring/RingTheme.swift
import SwiftUI

enum RingTheme {
    // Fan-blade geometry (Dory-style): every blade is a fixed-width sector, laid out
    // edge-to-edge in a fan centered on up; 11 blades fill 330° and leave the gap.
    static let outerRadius: CGFloat = 96
    static let innerRadius: CGFloat = 40          // band thickness = 56
    static var midRadius: CGFloat { (innerRadius + outerRadius) / 2 }  // logo orbit + 3D tilt anchor
    static let bladeCornerRadius: CGFloat = 10    // fillet on each blade's 4 corners
    static let bladeDegrees: Double = 30          // fixed angular width of every blade
    static let arcGapDegrees: Double = 30         // min wrap gap between the last blade and the first
    static let blade3DTiltDegrees: Double = 20    // per-blade 3D lean about its tangential axis
    static let blade3DPerspective: CGFloat = 0.75 // lower = stronger near-big-far-small
    static let popOffset: CGFloat = 6             // selected blade slides outward
    static let shadowPad: CGFloat = 14            // frame headroom for pop + shadow

    // Per-blade frosted-glass backing: a darkening tint over the blur so blades stay
    // legible on any wallpaper.
    static let glassTint = Color.black.opacity(0.28)

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

    // Hairlines (Loop's quinary)
    static let dividerColor = Color.white.opacity(0.12)
    static let dividerWidth: CGFloat = 1

    // Icon
    static let iconSize: CGFloat = 32
    static let iconTint = Color.white

    // Depth
    static let shadowRadius: CGFloat = 10
    static let shadowColor = Color.black.opacity(0.22)
    static let bladeShadowRadius: CGFloat = 3            // seam shadow between stacked blades
    static let bladeShadowColor = Color.black.opacity(0.3)

    // Motion
    // Pop-in (1.2→1 scale + fade) is driven by RingView's local `appeared` @State on .onAppear,
    // not a transition — the panel hosts the view only after viewModel.isShown is already true,
    // so an AnyTransition would never animate. `appear` is that pop-in curve.
    static let appear    = Animation.smooth(duration: 0.16)
    static let highlight = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.16)
}
