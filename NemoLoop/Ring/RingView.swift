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
        .onAppear { appeared = true }
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
        let overlapDeg = min(RingTheme.bladeOverlapDegrees, layout.pitch * 0.45)
        let shape = CardBladeShape(innerRadius: RingTheme.innerRadius,
                                   outerRadius: RingTheme.outerRadius,
                                   cornerRadius: RingTheme.bladeCornerRadius,
                                   outerCornerRadius: RingTheme.bladeOuterCornerRadius,
                                   // CardBladeShape speaks SwiftUI angles (0 = +x,
                                   // clockwise, y down); slot angles are from-up-
                                   // clockwise. The −π/2 conversion is what keeps
                                   // each blade under ITS logo — feeding θ directly
                                   // rotates the whole fan +90° (the v4→v5.2 root
                                   // cause).
                                   centerAngle: theta - .pi / 2,
                                   bladeWidth: (layout.bladeWidth + overlapDeg) * .pi / 180,
                                   arcCenter: arcCenter,
                                   outerBow: RingTheme.bladeOuterBow)
        // Lean pivot: the blade's inner edge, `bladeLeanHingeFraction` of the band
        // inward of the view centre (the logo), expressed in unit coords.
        let hingeDrop = RingTheme.bladeLeanHingeFraction * (RingTheme.outerRadius - RingTheme.innerRadius) / (2 * side)
        let hinge = UnitPoint(x: 0.5 - radial.x * hingeDrop, y: 0.5 - radial.y * hingeDrop)
        let isEmpty = icons[i] == nil
        let isHot = viewModel.highlightedIndex == i

        ZStack {
            // Frosted surface: translucent dark fill. Deliberately NOT a Material /
            // VisualEffectView / glassEffect — platform-backed materials composite
            // above their SwiftUI siblings and swallow them, and NSViews ignore 3D
            // transforms (render-proven; see spec).
            shape.fill(RingTheme.glassTint)
            // Face lighting: bright at the inner (hinge) edge, falling off outward —
            // a flat plate reads as a tilted one. Gradient runs along the radial.
            shape.fill(LinearGradient(colors: [RingTheme.faceLightStart, RingTheme.faceLightEnd],
                                      startPoint: UnitPoint(x: 0.5 - radial.x * 0.5, y: 0.5 - radial.y * 0.5),
                                      endPoint: UnitPoint(x: 0.5 + radial.x * 0.5, y: 0.5 + radial.y * 0.5)))
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
            // Logo and card are ONE PIECE: the logo sits dead centre of the card —
            // its slot angle, mid-band radius, no nudges (every attempt to re-centre
            // it on the *exposed* strip instead reads as the logo coming loose)
            // and carries the card's angle, so a card at 6 o'clock shows its logo
            // turned 180° with it, exactly like the reference. The lean on top of
            // that comes from the parent rotation, which moves both together.
            iconView(for: i, size: iconSize(pitch: layout.pitch + overlapDeg))
                .rotationEffect(.degrees(layout.centerAngle(i)))
        }
        .frame(width: side, height: side)
        // Two shadows per blade: a tight seam shadow (each card onto its clockwise
        // neighbour, so the shingling reads) plus a soft directional cast that lifts
        // the whole card off the wallpaper — the depth cue the reference leans on.
        .shadow(color: RingTheme.bladeShadowColor, radius: RingTheme.bladeShadowRadius)
        .shadow(color: RingTheme.bladeCastColor, radius: RingTheme.bladeCastRadius,
                x: RingTheme.bladeCastOffset.width, y: RingTheme.bladeCastOffset.height)
        // Fan-blade lean: pivot the whole card in plane about its inner edge (the
        // hinge), so its outer end swings clockwise past its neighbour's. The outer
        // silhouette becomes a sawtooth of stepped corners and each card visibly
        // lies over the next — the tilt the reference reads as depth. The logo is
        // counter-rotated above, so it stays upright and undistorted.
        .rotationEffect(.degrees(RingTheme.bladeLeanDegrees), anchor: hinge)
        // Deal-out: before `appeared` each card sits a little inside the ring,
        // smaller and transparent; blade i springs into its slot after i · stagger,
        // so the fan unfolds clockwise from 12 o'clock card by card.
        .scaleEffect(appeared ? 1 : RingTheme.bladeAppearScale)
        .opacity(appeared ? 1 : 0)
        .position(x: frameRadius + slot.x + (isHot ? RingTheme.popOffset * radial.x : 0)
                    - (appeared ? 0 : RingTheme.bladeAppearInset * radial.x),
                  y: frameRadius + slot.y + (isHot ? RingTheme.popOffset * radial.y : 0)
                    - (appeared ? 0 : RingTheme.bladeAppearInset * radial.y))
        .animation(RingTheme.bladeAppear.delay(Double(i) * RingTheme.bladeStagger), value: appeared)
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

/// A fan-blade card, shaped exactly the way the reference gets its "round hole,
/// sawtooth rim" silhouette:
///
/// - the INNER edge is a true arc concentric with the ring, and cards overlap
///   enough that those arcs merge into one continuous circle — the hole reads as a
///   clean circle no matter how the cards lean;
/// - the OUTER edge is a true arc too, but each card LEANS (see RingView), which
///   tips its arc off-centre from the ring's — so neighbouring outer edges cross at
///   stepped corners and the rim reads as a sawtooth of fan blades.
///
/// Both radial edges are rays from `arcCenter`; all four corners are rounded.
/// `centerAngle` (radians, SwiftUI convention: 0 = +x, clockwise, y down) and
/// `arcCenter` (band centre in local coords) keep the original conventions — the
/// −π/2 conversion from slot angles still applies (see the v4–v5.2 "+90° fan vs
/// icons" root cause).
struct CardBladeShape: Shape {
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    var cornerRadius: CGFloat = 0            // inner corners (and outer, unless overridden)
    var outerCornerRadius: CGFloat? = nil    // outer corners, when they should be rounder
    let centerAngle: Double          // radians
    let bladeWidth: Double           // radians
    var arcCenter: CGPoint? = nil   // band centre in local coords; nil = rect centre
    /// How curved the outer edge is, as a multiple of the ring-concentric arc's
    /// bulge: 1 = concentric with the ring, >1 bows further out (a fan blade's
    /// belly), 0 = a straight chord. It is a real circular arc at any value — an
    /// earlier quadratic approximation read as "a flat edge with a bump glued to
    /// the middle", because a parabola piles its curvature into the centre.
    var outerBow: Double = 1

    func path(in rect: CGRect) -> Path {
        let c = arcCenter ?? CGPoint(x: rect.midX, y: rect.midY)
        let half = bladeWidth / 2
        let a0 = centerAngle - half   // leading boundary ray
        let a1 = centerAngle + half   // trailing boundary ray
        let R = Double(outerRadius)
        let r = Double(innerRadius)

        func pt(_ radius: Double, _ angle: Double) -> CGPoint {
            CGPoint(x: c.x + radius * cos(angle), y: c.y + radius * sin(angle))
        }
        func lerp(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }

        // Clamp each pair of corners separately. Inner corners: their angular inset
        // on the (short) inner arc may not eat more than a third of the half-width,
        // or the arc vanishes and the card pinches into a petal. Outer corners: at
        // most 45% of the outer edge, so the two fillets never meet.
        let crI = min(Double(cornerRadius), (R - r) / 2, half * 0.35 * r)
        let crO = min(Double(outerCornerRadius ?? cornerRadius), (R - r) / 2, half * 0.45 * R)

        // Outer edge: the circular arc through both outer corners whose bulge is
        // `outerBow` × the concentric arc's. Chord half-length `aHalf` and sagitta
        // `sag` give its radius; its centre sits on the card's centre ray.
        let cornerLead = pt(R, a0)
        let cornerTrail = pt(R, a1)
        let aHalf = R * sin(half)
        let sag = max(0.001, outerBow * R * (1 - cos(half)))
        let bowRadius = (aHalf * aHalf + sag * sag) / (2 * sag)
        let bowOrigin = pt(R * cos(half) + sag - bowRadius, centerAngle)
        func bowAngle(_ p: CGPoint) -> Double { atan2(p.y - bowOrigin.y, p.x - bowOrigin.x) }
        func bowPoint(_ angle: Double) -> CGPoint {
            CGPoint(x: bowOrigin.x + bowRadius * cos(angle), y: bowOrigin.y + bowRadius * sin(angle))
        }
        let phi0 = bowAngle(cornerLead)
        let phi1 = bowAngle(cornerTrail)

        guard crI > 0 || crO > 0 else {
            var p = Path()
            p.move(to: cornerLead)
            p.addArc(center: bowOrigin, radius: bowRadius,
                     startAngle: .radians(phi0), endAngle: .radians(phi1), clockwise: false)
            p.addLine(to: pt(r, a1))
            p.addArc(center: c, radius: r, startAngle: .radians(a1), endAngle: .radians(a0), clockwise: true)
            p.closeSubpath()
            return p
        }

        let dr = crI / r                 // inner fillet's angular inset along the inner arc
        let dR = crO / bowRadius         // outer fillet's angular inset along the outer arc

        var p = Path()
        p.move(to: bowPoint(phi0 + dR))
        p.addArc(center: bowOrigin, radius: bowRadius,
                 startAngle: .radians(phi0 + dR), endAngle: .radians(phi1 - dR), clockwise: false)
        p.addQuadCurve(to: lerp(cornerTrail, pt(r, a1), crO / (R - r)), control: cornerTrail)
        p.addLine(to: pt(r + crI, a1))
        p.addQuadCurve(to: pt(r, a1 - dr), control: pt(r, a1))
        p.addArc(center: c, radius: r, startAngle: .radians(a1 - dr), endAngle: .radians(a0 + dr), clockwise: true)
        p.addQuadCurve(to: pt(r + crI, a0), control: pt(r, a0))
        p.addLine(to: lerp(cornerLead, pt(r, a0), crO / (R - r)))
        p.addQuadCurve(to: bowPoint(phi0 + dR), control: cornerLead)
        p.closeSubpath()
        return p
    }
}
