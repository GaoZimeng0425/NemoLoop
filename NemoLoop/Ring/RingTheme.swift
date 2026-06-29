// NemoLoop/Ring/RingTheme.swift
import SwiftUI

enum RingTheme {
    // Geometry (keep current RingView radii)
    static let outerRadius: CGFloat = 96
    static let innerRadius: CGFloat = 40          // band thickness = 56
    static let canvasPadding: CGFloat = 40        // shadow/pop-in headroom
    static let wedgeGap: CGFloat = 4              // perpendicular gap (points) between wedges
    static let wedgeCornerRadius: CGFloat = 10    // fillet on each wedge's 4 corners

    // Accent gradient (Loop's color1 → color2, diagonal)
    static let accentStart = Color.accentColor
    static let accentEnd   = Color.accentColor.mix(with: .blue, by: 0.45)
    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accentStart, accentEnd],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // Background band behind the wedge fan (shows through the inter-wedge gaps)
    static let backgroundColor = Color.black.opacity(0.35)

    // Surfaces / state fills — kept translucent so the frosted glass shows through
    // (Loop's airiness comes from NOT darkening the ring; only the selected wedge is solid accent).
    static let baseFill        = Color.white.opacity(0.05)   // assigned, idle — faint glass highlight
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
