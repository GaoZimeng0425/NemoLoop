// NemoLoop/Ring/RingTheme.swift
import SwiftUI

enum RingTheme {
    // Geometry (keep current RingView radii)
    static let outerRadius: CGFloat = 96
    static let innerRadius: CGFloat = 40          // band thickness = 56
    static let canvasPadding: CGFloat = 40        // shadow/pop-in headroom
    static let wedgeGap: CGFloat = 4              // perpendicular gap (points) between wedges
    static let wedgeCornerRadius: CGFloat = 10    // fillet on each wedge's 4 corners

    // Open-arc geometry (Dory-style C-shape): wedges share an arc with a fixed gap at
    // 10:30. Angles use the from-up convention (0° = up, clockwise positive).
    static let arcGapCenterDegrees: Double = -45               // 10:30 direction
    static let arcGapSpanDegrees: Double = 60
    static var arcSpanDegrees: Double { 360 - arcGapSpanDegrees }                       // 300°
    static var arcStartDegrees: Double { arcGapCenterDegrees + arcGapSpanDegrees / 2 }  // -15°

    // The continuous frosted-glass ring extends past the wedge band on both edges, so a
    // margin of glass shows inside the inner hole and outside the outer rim — the wedges
    // float within the ring instead of filling it edge-to-edge.
    static let ringBackingGap: CGFloat = 8        // radial margin between wedges and ring edges
    static var ringBackingInner: CGFloat { innerRadius - ringBackingGap }
    static var ringBackingOuter: CGFloat { outerRadius + ringBackingGap }

    // Accent gradient (Loop's color1 → color2, diagonal)
    static let accentStart = Color.accentColor
    static let accentEnd   = Color.accentColor.mix(with: .blue, by: 0.45)
    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accentStart, accentEnd],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // Per-wedge frosted-glass backing: a darkening tint over the blur so wedges
    // stay legible on any wallpaper (each wedge is masked to its own shape).
    static let glassTint = Color.black.opacity(0.28)

    // Surfaces / state fills — translucent so the frosted glass shows through.
    static let baseFill        = Color.white.opacity(0.05)   // assigned, idle — visible tint over glass
    static let highlightEmpty  = Color.white.opacity(0.16)   // empty slot, highlighted

    // Borders (Loop's dual quinary hairlines)
    static let borderColor = Color.white.opacity(0.18)       // ≈ .quinary on dark
    static let borderWidth: CGFloat = 1
    static let dividerColor = Color.white.opacity(0.12)
    static let dividerWidth: CGFloat = 1

    // Icon
    static let iconSize: CGFloat = 28
    static let iconTint = Color.white

    // Depth
    static let shadowRadius: CGFloat = 10
    static let shadowColor = Color.black.opacity(0.22)

    // Motion
    // Pop-in (1.2→1 scale + fade) is driven by RingView's local `appeared` @State on .onAppear,
    // not a transition — the panel hosts the view only after viewModel.isShown is already true,
    // so an AnyTransition would never animate. `appear` is that pop-in curve.
    static let appear    = Animation.smooth(duration: 0.16)
    static let highlight = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.16)
}
