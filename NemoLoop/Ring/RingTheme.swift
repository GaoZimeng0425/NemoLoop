// NemoLoop/Ring/RingTheme.swift
import SwiftUI

enum RingTheme {
    // Geometry (keep current RingView radii)
    static let outerRadius: CGFloat = 96
    static let innerRadius: CGFloat = 40          // band thickness = 56
    static let canvasPadding: CGFloat = 40        // shadow/pop-in headroom
    static let wedgeGap: Angle = .degrees(1.5)    // hairline gap between wedges

    // Accent gradient (Loop's color1 → color2, diagonal)
    static let accentStart = Color.accentColor
    static let accentEnd   = Color.accentColor.mix(with: .blue, by: 0.45)
    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accentStart, accentEnd],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // Surfaces / state fills
    static let baseFill        = Color.black.opacity(0.55)   // assigned, idle
    static let emptyFill       = Color.black.opacity(0.32)   // empty slot, idle
    static let highlightEmpty  = Color.white.opacity(0.18)   // empty slot, highlighted

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
    static let appear    = Animation.smooth(duration: 0.16)
    static let highlight = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.16)
    static let popIn     = AnyTransition.scale(scale: 1.2).combined(with: .opacity)
}
