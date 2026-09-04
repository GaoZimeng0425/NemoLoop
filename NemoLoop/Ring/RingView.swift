// NemoLoop/Ring/RingView.swift
import SwiftUI

struct RingView: View {
    /// One entry per blade; `nil` renders an empty slot (a "+" glyph). `icons.count`
    /// drives the blade count, so the ring is fully dynamic.
    let icons: [NSImage?]
    @Bindable var viewModel: RingViewModel
    @Environment(\.ringCenter) private var center

    @State private var appeared = false

    private var bladeCount: Int { icons.count }

    /// Angular layout shared with hit testing — fixed-width blades edge-to-edge,
    /// blade 0 centered on 12 o'clock with the fan running clockwise, wrap gap just
    /// counterclockwise of blade 0 (overlap only above 11 blades).
    private var layout: BladeLayout { BladeLayout.forCount(bladeCount) }

    init(icons: [NSImage?], viewModel: RingViewModel) {
        self.icons = icons
        self._viewModel = Bindable(viewModel)
    }

    private var frameRadius: CGFloat {
        RingTheme.outerRadius + RingTheme.popOffset + RingTheme.shadowPad
    }

    var body: some View {
        ZStack {
            // Each item view: card-shaped blade drawn AROUND its centred logo, the
            // whole view leaning back in 3D. Fixed-pitch blades tile in ascending
            // index order, blade 0 centered on 12 o'clock and the rest clockwise;
            // the wrap gap (just counterclockwise of blade 0) selects nothing.
            // Every blade renders wider than the pitch and zIndex runs REVERSED
            // (blade 0 topmost), so each blade shingles over its clockwise
            // neighbour — the previous card presses on the next, Dory-style.
            ForEach(0..<bladeCount, id: \.self) { i in
                bladeView(for: i)
            }
        }
        .frame(width: frameRadius * 2, height: frameRadius * 2)
        .compositingGroup()
        .shadow(color: RingTheme.shadowColor, radius: RingTheme.shadowRadius)
        .position(center)
        .animation(RingTheme.highlight, value: viewModel.highlightedIndex)
        .scaleEffect(appeared ? 1 : 1.2)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(RingTheme.appear) { appeared = true }
        }
    }

    /// Slot-center angle (from-up convention, clockwise, radians) of blade `i`.
    private func slotAngle(_ i: Int) -> Double {
        layout.centerAngle(i) * .pi / 180
    }

    // MARK: - Blades

    /// One blade = one local view centred on the logo. The view sits at the blade's
    /// slot point (slot angle θ, mid-band radius); the card's band is offset back
    /// toward the ring centre, so the blade is drawn AROUND the centred logo. The
    /// 3D lean hinges at the blade's inner edge (`blade3DHingeFraction` = 1) — the
    /// card tips backward like a trapdoor, outer edge receding — while logo and
    /// card stay one rigid view, so no transform can ever separate them.
    @ViewBuilder
    private func bladeView(for i: Int) -> some View {
        let theta = slotAngle(i)
        // Outward radial unit at θ (canvas coords, y down) and the slot point.
        let radial = (x: sin(theta), y: -cos(theta))
        let slot = (x: RingTheme.midRadius * radial.x, y: RingTheme.midRadius * radial.y)
        let side = RingTheme.bladeViewSide
        // Ring centre expressed in the blade view's local coords.
        let arcCenter = CGPoint(x: side / 2 - slot.x, y: side / 2 - slot.y)
        // Shingle overlap shrinks with the pitch: above 11 blades the pitch
        // compresses, so cap the overlap at 30% of it or the fan piles up.
        let overlapDeg = min(RingTheme.bladeOverlapDegrees, layout.pitch * 0.3)
        let shape = CardBladeShape(innerRadius: RingTheme.innerRadius,
                                   outerRadius: RingTheme.outerRadius,
                                   cornerRadius: RingTheme.bladeCornerRadius,
                                   // CardBladeShape speaks SwiftUI angles (0 = +x,
                                   // clockwise, y down); slot angles are from-up-
                                   // clockwise. The −π/2 conversion is what keeps
                                   // each blade under ITS logo — feeding θ directly
                                   // rotates the whole fan +90° (the v4→v5.2 root
                                   // cause).
                                   centerAngle: theta - .pi / 2,
                                   bladeWidth: (layout.bladeWidth + overlapDeg) * .pi / 180,
                                   arcCenter: arcCenter)
        let isEmpty = icons[i] == nil
        let isHot = viewModel.highlightedIndex == i

        ZStack {
            // Frosted surface: translucent dark fill. Deliberately NOT a Material /
            // VisualEffectView / glassEffect — platform-backed materials composite
            // above their SwiftUI siblings and swallow them, and NSViews ignore 3D
            // transforms (render-proven; see spec).
            shape.fill(RingTheme.glassTint)
            if isHot && !isEmpty {
                shape.fill(RingTheme.accentGradient)
            } else if isHot {
                shape.fill(RingTheme.highlightEmpty)
            } else if !isEmpty {
                shape.fill(RingTheme.baseFill)
            } else {
                shape.fill(RingTheme.emptyFill)
            }
            shape.stroke(RingTheme.dividerColor, lineWidth: RingTheme.dividerWidth)
            iconView(for: i, size: iconSize(pitch: layout.pitch + overlapDeg))   // rides the tilt with the card
        }
        .frame(width: side, height: side)
        // Per-blade drop shadow: each blade casts onto the one beneath it (its CW
        // neighbour), making the shingle seams legible (Dory's look).
        .shadow(color: RingTheme.bladeShadowColor, radius: RingTheme.bladeShadowRadius)
        // 3D lean about the tangential axis through the hinge point — fraction
        // `blade3DHingeFraction` of the band inward of the logo (1.0 = the inner
        // edge): the card plants on its inner edge and tips back, outer edge far.
        .rotation3DEffect(.degrees(RingTheme.blade3DTiltDegrees),
                          axis: (x: cos(theta), y: sin(theta), z: 0),
                          anchor: UnitPoint(x: 0.5 - radial.x * RingTheme.blade3DHingeFraction * (RingTheme.outerRadius - RingTheme.innerRadius) / (2 * side),
                                            y: 0.5 - radial.y * RingTheme.blade3DHingeFraction * (RingTheme.outerRadius - RingTheme.innerRadius) / (2 * side)),
                          perspective: RingTheme.blade3DPerspective)
        .position(x: frameRadius + slot.x + (isHot ? RingTheme.popOffset * radial.x : 0),
                  y: frameRadius + slot.y + (isHot ? RingTheme.popOffset * radial.y : 0))
        // Previous card over next: descending zIndex with index, so blade i shingles
        // over blade i+1; the highlighted blade jumps above all of them so its pop
        // reads on top of both neighbours.
        .zIndex(Double(bladeCount - i) + (isHot ? Double(bladeCount) : 0))
    }

    // MARK: - Icon

    /// Icon size shrinks with the slot width so dense fans (12+ blades, compressed
    /// pitch) keep a visible card margin around each icon instead of beading over.
    private func iconSize(pitch: Double) -> CGFloat {
        let widthAtMid = 2 * RingTheme.midRadius * sin(pitch * .pi / 360)
        return min(RingTheme.iconSize, widthAtMid * 0.7)
    }

    @ViewBuilder
    private func iconView(for i: Int, size: CGFloat) -> some View {
        if let icon = icons[i] {
            Image(nsImage: icon)
                .resizable()
                .frame(width: size, height: size)
        } else {
            Image(systemName: "plus")
                .font(.system(size: size * 0.56, weight: .bold))
                .foregroundStyle(RingTheme.iconTint.opacity(0.35))
        }
    }
}

/// A fan-blade card: a rounded trapezoid. Two straight radial edges (rays from
/// `arcCenter` at the blade's boundary angles) capped by straight chords at
/// `outerRadius` and `innerRadius` — the Dory-card look, vs the old WedgeShape's
/// arcs — with all four corners filleted (radius clamped per corner so fillets
/// never overlap). `centerAngle` (radians, SwiftUI convention: 0 = +x, clockwise,
/// y down) and `arcCenter` (band centre in local coords) keep WedgeShape's
/// conventions — the −π/2 conversion from slot angles still applies (see the
/// v4–v5.2 "+90° fan vs icons" root cause).
struct CardBladeShape: Shape {
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    var cornerRadius: CGFloat = 0
    let centerAngle: Double          // radians; overrides nothing — required
    let bladeWidth: Double           // radians
    var arcCenter: CGPoint? = nil   // band centre in local coords; nil = rect centre

    func path(in rect: CGRect) -> Path {
        let c = arcCenter ?? CGPoint(x: rect.midX, y: rect.midY)
        let half = bladeWidth / 2
        let theta0 = centerAngle - half   // a0-side boundary ray
        let theta1 = centerAngle + half   // a1-side boundary ray
        let R = Double(outerRadius)
        let r = Double(innerRadius)

        func pt(_ radius: Double, _ angle: Double) -> CGPoint {
            CGPoint(x: c.x + radius * cos(angle), y: c.y + radius * sin(angle))
        }

        // Clockwise convex quad: outer-lead → outer-trail → inner-trail → inner-lead.
        let corners = [pt(R, theta0), pt(R, theta1), pt(r, theta1), pt(r, theta0)]

        guard cornerRadius > 0 else {
            var p = Path()
            p.move(to: corners[0])
            for v in corners.dropFirst() { p.addLine(to: v) }
            p.closeSubpath()
            return p
        }

        // Per-corner circular fillet. For a corner of interior angle φ the tangent
        // inset along each edge is cr / tan(φ/2); clamp cr so insets never cross an
        // edge midpoint, then drop the fillet centre cr / sin(φ/2) down the
        // interior bisector.
        var fillets: [(inTan: CGPoint, outTan: CGPoint, center: CGPoint, radius: CGFloat)] = []
        for i in 0..<4 {
            let v = corners[i]
            let prev = corners[(i + 3) % 4]
            let next = corners[(i + 1) % 4]
            let dIn = CGPoint(x: prev.x - v.x, y: prev.y - v.y)
            let dOut = CGPoint(x: next.x - v.x, y: next.y - v.y)
            let lenIn = hypot(dIn.x, dIn.y)
            let lenOut = hypot(dOut.x, dOut.y)
            let cosPhi = max(-1.0, min(1.0, (dIn.x * dOut.x + dIn.y * dOut.y) / (lenIn * lenOut)))
            let halfPhi = acos(cosPhi) / 2
            let cr = min(Double(cornerRadius),
                         Double(lenIn) / 2 * tan(halfPhi),
                         Double(lenOut) / 2 * tan(halfPhi))
            let t = CGFloat(cr / tan(halfPhi))
            let uIn = CGPoint(x: dIn.x / lenIn, y: dIn.y / lenIn)
            let uOut = CGPoint(x: dOut.x / lenOut, y: dOut.y / lenOut)
            let bis = CGPoint(x: uIn.x + uOut.x, y: uIn.y + uOut.y)
            let bisLen = hypot(bis.x, bis.y)
            let drop = CGFloat(cr / sin(halfPhi))
            let center = CGPoint(x: v.x + bis.x / bisLen * drop,
                                 y: v.y + bis.y / bisLen * drop)
            fillets.append((CGPoint(x: v.x + uIn.x * t, y: v.y + uIn.y * t),
                            CGPoint(x: v.x + uOut.x * t, y: v.y + uOut.y * t),
                            center,
                            CGFloat(cr)))
        }

        // Walk the quad, filleting each corner with the shortest arc between its
        // tangents (always the fillet — a convex corner's tangent pair spans < π).
        var p = Path()
        p.move(to: fillets[0].inTan)
        for i in 0..<4 {
            let f = fillets[i]
            let aF = atan2(f.inTan.y - f.center.y, f.inTan.x - f.center.x)
            let aT = atan2(f.outTan.y - f.center.y, f.outTan.x - f.center.x)
            var d = aT - aF
            while d <= -.pi { d += 2 * .pi }
            while d > .pi { d -= 2 * .pi }
            p.addArc(center: f.center, radius: f.radius,
                     startAngle: .radians(aF), endAngle: .radians(aT), clockwise: d < 0)
            p.addLine(to: fillets[(i + 1) % 4].inTan)
        }
        p.closeSubpath()
        return p
    }
}
