// NemoLoop/Ring/RingView.swift
import SwiftUI

struct RingView: View {
    /// One entry per blade; `nil` renders an empty slot (a "+" glyph). `icons.count`
    /// drives the blade count, so the ring is fully dynamic. `subicons` is parallel:
    /// the dealt-out sub-action icons per blade, rendered only while that blade's
    /// sub-wheel is open (`viewModel.openSubIndex`).
    let icons: [NSImage?]
    let subicons: [[NSImage?]]
    @Bindable var viewModel: RingViewModel
    @Environment(\.ringCenter) private var center
    // Follows the hosting panel's effective appearance: RingWindowController forces
    // it from the Appearance setting (light/dark) or leaves it to the system (auto).
    @Environment(\.colorScheme) private var scheme

    @State private var appeared = false

    private var palette: RingPalette { RingPalette.palette(for: scheme) }

    private var bladeCount: Int { icons.count }

    /// Angular layout shared with hit testing — fixed-width blades edge-to-edge,
    /// blade 0 centered on 12 o'clock with the fan running clockwise, wrap gap just
    /// counterclockwise of blade 0 (overlap only above 11 blades).
    private var layout: BladeLayout { BladeLayout.forCount(bladeCount) }

    /// Single designated init. `preAppeared` renders the settled fan (deal-out
    /// already done) — the seam offline render probes use, since `onAppear`
    /// never fires outside a window.
    init(icons: [NSImage?], viewModel: RingViewModel, subicons: [[NSImage?]] = [], preAppeared: Bool = false) {
        self.icons = icons
        self.subicons = subicons
        self._viewModel = Bindable(viewModel)
        self._appeared = State(initialValue: preAppeared)
    }

    /// Canvas radius: the blades, or the dealt-out sub ring when that extends
    /// farther (it sits outside the fan), plus pop and shadow headroom.
    private var frameRadius: CGFloat {
        max(RingTheme.outerRadius, RingTheme.subBandOuter)
            + RingTheme.subPopOffset + RingTheme.shadowPad
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
            // Safe-cancel (outer escape): while the pointer is beyond the cancel
            // radius the whole fan dims to one translucent plate (composited first,
            // so overlapping shingles don't double-brighten through each other) —
            // release there commits nothing.
            Group {
                ForEach(0..<bladeCount, id: \.self) { i in
                    bladeView(for: i)
                        // The open wheel's parent blade recedes so the dealt-out
                        // sub-cards read as a second, brighter tier.
                        .opacity(viewModel.openSubIndex == i ? RingTheme.subOpenParentDimOpacity : 1)
                }
            }
            .compositingGroup()
            .opacity(viewModel.isCancelling ? RingTheme.cancelDimOpacity : 1)
            // Dealt-out sub-cards: a smaller tier of blades tiling the parent
            // sector's outer band, above the parent fan. Their zIndex must beat
            // every blade's — blade zIndexes (reversed, for the shingle) leak
            // through the Group and would bury the subs under the fan otherwise.
            if let open = viewModel.openSubIndex, subicons.indices.contains(open) {
                ForEach(subicons[open].indices, id: \.self) { j in
                    subBladeView(parent: open, sub: j)
                        .zIndex(Double(2 * bladeCount + j))
                }
            }
        }
        .frame(width: frameRadius * 2, height: frameRadius * 2)
        .compositingGroup()
        .shadow(color: RingTheme.shadowColor, radius: RingTheme.shadowRadius)
        .position(center)
        .animation(RingTheme.highlight, value: viewModel.highlightedIndex)
        .animation(.easeOut(duration: 0.14), value: viewModel.isCancelling)
        .animation(RingTheme.bladeAppear, value: viewModel.openSubIndex)
        .animation(RingTheme.highlight, value: viewModel.hoveredSubIndex)
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
            shape.fill(palette.glassTint)
            // Face lighting: bright at the inner (hinge) edge, falling off outward —
            // a flat plate reads as a tilted one. Gradient runs along the radial.
            shape.fill(LinearGradient(colors: [palette.faceLightStart, palette.faceLightEnd],
                                      startPoint: UnitPoint(x: 0.5 - radial.x * 0.5, y: 0.5 - radial.y * 0.5),
                                      endPoint: UnitPoint(x: 0.5 + radial.x * 0.5, y: 0.5 + radial.y * 0.5)))
            if isHot && !isEmpty {
                shape.fill(palette.highlightFill)
            } else if isHot {
                shape.fill(palette.highlightEmpty)
            } else if !isEmpty {
                shape.fill(palette.baseFill)
            } else {
                shape.fill(palette.emptyFill)
            }
            shape.stroke(palette.dividerColor, lineWidth: RingTheme.dividerWidth)
            // Logo and card are ONE PIECE: the logo sits dead centre of the card —
            // its slot angle, mid-band radius, no nudges (every attempt to re-centre
            // it on the *exposed* strip instead reads as the logo coming loose)
            // and carries the card's angle, so a card at 6 o'clock shows its logo
            // turned 180° with it, exactly like the reference. The lean on top of
            // that comes from the parent rotation, which moves both together.
            iconView(icons[i], size: iconSize(pitch: layout.pitch + overlapDeg))
                .rotationEffect(.degrees(layout.centerAngle(i)))
        }
        .frame(width: side, height: side)
        // Two shadows per blade: a tight seam shadow (each card onto its clockwise
        // neighbour, so the shingling reads) plus a soft directional cast that lifts
        // the whole card off the wallpaper — the depth cue the reference leans on.
        .shadow(color: RingTheme.bladeShadowColor, radius: RingTheme.bladeShadowRadius)
        .shadow(color: palette.bladeCastColor, radius: RingTheme.bladeCastRadius,
                x: RingTheme.bladeCastOffset.width, y: RingTheme.bladeCastOffset.height)
        // Fan-blade lean: pivot the whole card in plane about its inner edge (the
        // hinge), so its outer end swings clockwise past its neighbour's. The outer
        // silhouette becomes a sawtooth of stepped corners and each card visibly
        // lies over the next — the tilt the reference reads as depth. The logo is
        // counter-rotated above, so it stays upright and undistorted.
        .rotationEffect(.degrees(RingTheme.bladeLeanDegrees), anchor: hinge)
        // Depth tilt: each card tips back about the DIAGONAL between its radial and
        // tangential axes, so its leading-outer corner is the far one and its
        // trailing-inner corner the near one — near-big-far-small per card, the way
        // a hand of fanned cards reads. (A tangential axis alone tips the outer edge
        // back and barely bends the silhouette; a radial axis alone just narrows the
        // card sideways.)
        .rotation3DEffect(.degrees(RingTheme.bladeDepthTiltDegrees),
                          axis: (x: (radial.x + cos(theta)) / 2.squareRoot(),
                                 y: (radial.y + sin(theta)) / 2.squareRoot(), z: 0),
                          perspective: RingTheme.bladeDepthPerspective)
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
        // over blade i+1. The order holds on hover too: the hot blade pops outward
        // and tints in place, staying tucked under its counterclockwise neighbour.
        .zIndex(Double(bladeCount - i))
    }

    // MARK: - Sub-blades

    /// One dealt-out sub-action card: a smaller blade tiling the parent sector's
    /// full angular width across the raised sub band (`[subBandInner, subBandOuter]`),
    /// sub 0 counterclockwise-most — the same mapping as `RingGeometry.subIndex`, so
    /// hit regions match the render. Hovered sub pops outward and tints like a blade;
    /// the cast shadow lifts each card off the dimmed parent.
    @ViewBuilder
    private func subBladeView(parent: Int, sub: Int) -> some View {
        let childCount = subicons[parent].count
        // Parent half-width in radians, split evenly across the children.
        let parentHalf = layout.bladeWidth * .pi / 360
        let subWidth = 2 * parentHalf / Double(childCount)
        let theta = slotAngle(parent) - parentHalf + (Double(sub) + 0.5) * subWidth
        let radial = (x: sin(theta), y: -cos(theta))
        let midSub = (RingTheme.subBandInner + RingTheme.subBandOuter) / 2
        let slot = (x: midSub * radial.x, y: midSub * radial.y)
        let side = RingTheme.bladeViewSide * 0.6
        let arcCenter = CGPoint(x: side / 2 - slot.x, y: side / 2 - slot.y)
        let isHot = viewModel.hoveredSubIndex == sub
        let icon = subicons[parent][sub]

        let shape = CardBladeShape(innerRadius: RingTheme.subBandInner,
                                   outerRadius: RingTheme.subBandOuter,
                                   cornerRadius: RingTheme.subCornerRadius,
                                   outerCornerRadius: RingTheme.subCornerRadius,
                                   // Same −π/2 conversion as the parent blades — feed it
                                   // θ raw and every card rotates +90° (the v4 bug).
                                   centerAngle: theta - .pi / 2,
                                   bladeWidth: subWidth + RingTheme.subBladeOverlapDegrees * .pi / 180,
                                   arcCenter: arcCenter,
                                   outerBow: 1)

        ZStack {
            shape.fill(palette.glassTint)
            shape.fill(LinearGradient(colors: [palette.faceLightStart, palette.faceLightEnd],
                                      startPoint: UnitPoint(x: 0.5 - radial.x * 0.5, y: 0.5 - radial.y * 0.5),
                                      endPoint: UnitPoint(x: 0.5 + radial.x * 0.5, y: 0.5 + radial.y * 0.5)))
            // Idle subs sit one tone BELOW the hot parent (the parent is always
            // highlighted while its wheel is open), so the dealt-out tier reads as
            // gray paper cards on a lit one instead of white-on-white. Hovering
            // stays the white brighten — the sub is then the brightest card there,
            // same language as blade highlight.
            if isHot {
                shape.fill(palette.highlightFill)
            } else {
                shape.fill(palette.faceLightEnd)
            }
            shape.stroke(palette.dividerColor, lineWidth: RingTheme.dividerWidth)
            iconView(icon, size: subIconSize(width: subWidth))
        }
        .frame(width: side, height: side)
        .shadow(color: RingTheme.bladeShadowColor, radius: RingTheme.bladeShadowRadius)
        .shadow(color: palette.bladeCastColor, radius: 5, x: 0, y: 3)
        // Deal-in bound to state (not a transition): renders deterministically at
        // the final state offline, springs open in the live ring.
        .scaleEffect(viewModel.openSubIndex == parent ? 1 : 0.6)
        .opacity(viewModel.openSubIndex == parent ? 1 : 0)
        .position(x: frameRadius + slot.x + (isHot ? RingTheme.subPopOffset * radial.x : 0),
                  y: frameRadius + slot.y + (isHot ? RingTheme.subPopOffset * radial.y : 0))
    }

    /// Sub icons shrink to the (much narrower) sub-blade width at the sub band's
    /// mid radius.
    private func subIconSize(width subWidthRadians: Double) -> CGFloat {
        let widthAtMid = 2 * midSubRadius * sin(subWidthRadians / 2)
        return min(RingTheme.iconSize * 0.6, widthAtMid * 0.78)
    }

    private var midSubRadius: CGFloat {
        (RingTheme.subBandInner + RingTheme.subBandOuter) / 2
    }

    // MARK: - Icon

    /// Icon size shrinks with the slot width so dense fans (12+ blades, compressed
    /// pitch) keep a visible card margin around each icon instead of beading over.
    private func iconSize(pitch: Double) -> CGFloat {
        let widthAtMid = 2 * RingTheme.midRadius * sin(pitch * .pi / 360)
        return min(RingTheme.iconSize, widthAtMid * 0.7)
    }

    @ViewBuilder
    private func iconView(_ image: NSImage?, size: CGFloat) -> some View {
        if let image {
            Image(nsImage: image)
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
