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
            // Each item view: blade shape drawn AROUND its centred logo, the whole
            // view leaning in 3D. Fixed-width blades tile edge-to-edge in ascending
            // index order, blade 0 centered on 12 o'clock and the rest clockwise;
            // the wrap gap (just counterclockwise of blade 0) selects nothing.
            // Above 11 blades the pitch compresses and each blade covers its CCW
            // neighbour.
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
    /// slot point (slot angle θ, mid-band radius); the wedge's arc centre is offset
    /// back toward the ring centre, so the blade is drawn AROUND the centred logo.
    /// The 3D tilt pivots at the view centre — the logo itself — so no transform can
    /// ever separate logo from blade.
    @ViewBuilder
    private func bladeView(for i: Int) -> some View {
        let theta = slotAngle(i)
        // Outward radial unit at θ (canvas coords, y down) and the slot point.
        let radial = (x: sin(theta), y: -cos(theta))
        let slot = (x: RingTheme.midRadius * radial.x, y: RingTheme.midRadius * radial.y)
        let side = RingTheme.bladeViewSide
        // Ring centre expressed in the blade view's local coords.
        let arcCenter = CGPoint(x: side / 2 - slot.x, y: side / 2 - slot.y)
        let shape = WedgeShape(index: 0, count: 1,
                               innerRadius: RingTheme.innerRadius,
                               outerRadius: RingTheme.outerRadius,
                               cornerRadius: RingTheme.bladeCornerRadius,
                               // WedgeShape speaks SwiftUI angles (0 = +x, clockwise,
                               // y down); slot angles are from-up-clockwise. The −π/2
                               // conversion is what keeps each blade under ITS logo —
                               // feeding θ directly rotates the whole fan +90° (the
                               // v4→v5.2 "logo not in blade / hover off" root cause).
                               centerAngle: theta - .pi / 2,
                               bladeWidth: layout.bladeWidth * .pi / 180,
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
            iconView(for: i)   // centred — exactly on the tilt pivot
        }
        .frame(width: side, height: side)
        // Per-blade drop shadow: each blade casts onto the one beneath it, making
        // the seams legible (Dory's look).
        .shadow(color: RingTheme.bladeShadowColor, radius: RingTheme.bladeShadowRadius)
        // 3D lean about the tangential axis through the slot — the view centre, so
        // the logo rides the pivot and the band foreshortens around it.
        .rotation3DEffect(.degrees(RingTheme.blade3DTiltDegrees),
                          axis: (x: cos(theta), y: sin(theta), z: 0),
                          perspective: RingTheme.blade3DPerspective)
        .position(x: frameRadius + slot.x + (isHot ? RingTheme.popOffset * radial.x : 0),
                  y: frameRadius + slot.y + (isHot ? RingTheme.popOffset * radial.y : 0))
    }

    // MARK: - Icon

    @ViewBuilder
    private func iconView(for i: Int) -> some View {
        if let icon = icons[i] {
            Image(nsImage: icon)
                .resizable()
                .frame(width: RingTheme.iconSize, height: RingTheme.iconSize)
        } else {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(RingTheme.iconTint.opacity(0.35))
        }
    }
}

/// A fan blade: an annular sector for index `i` of `count`. Blades are centered on
/// evenly spaced slot angles starting at `startAngle + slice/2`, but each blade's own
/// angular width `bladeWidth` can exceed the slot pitch `span/count`, so neighbouring
/// blades overlap — each one tucks under the previous. An explicit `centerAngle`
/// (radians, SwiftUI convention) overrides the slot placement entirely, and
/// `arcCenter` moves the arc centre away from the rect's centre so the blade can be
/// drawn in a local view centred elsewhere (e.g. on its logo).
/// `cornerRadius` rounds the four corners with circular fillets while keeping the
/// outer/inner arcs and straight radial edges exact.
struct WedgeShape: Shape {
    let index: Int
    let count: Int
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    var cornerRadius: CGFloat = 0
    var startAngle: Double = -.pi / 2
    var span: Double = 2 * .pi
    var centerAngle: Double? = nil  // radians; overrides the slot-derived angle
    var bladeWidth: Double? = nil   // radians; defaults to the slot pitch
    var arcCenter: CGPoint? = nil   // arc centre in local coords; nil = rect centre

    func path(in rect: CGRect) -> Path {
        let c = arcCenter ?? CGPoint(x: rect.midX, y: rect.midY)
        let slice = span / Double(count)
        // SwiftUI angles: 0 = +x (right), increasing clockwise (y down); -π/2 = up.
        let slotCenter = startAngle + slice / 2 + Double(index) * slice
        let centerAngle = centerAngle ?? slotCenter
        let half = (bladeWidth ?? slice) / 2
        let theta0 = centerAngle - half   // a0-side boundary ray
        let theta1 = centerAngle + half   // a1-side boundary ray
        let R = Double(outerRadius)
        let r = Double(innerRadius)

        func pt(_ radius: Double, _ angle: Double) -> CGPoint {
            CGPoint(x: c.x + radius * cos(angle), y: c.y + radius * sin(angle))
        }

        // Sharp blade when rounding is off.
        guard cornerRadius > 0 else {
            var p = Path()
            p.move(to: pt(R, theta0))
            p.addArc(center: c, radius: outerRadius, startAngle: .radians(theta0), endAngle: .radians(theta1), clockwise: false)
            p.addLine(to: pt(r, theta1))
            p.addArc(center: c, radius: innerRadius, startAngle: .radians(theta1), endAngle: .radians(theta0), clockwise: true)
            p.closeSubpath()
            return p
        }

        // Clamp so fillets never overlap on an arc, invert a radial edge, or exceed
        // the band. Bounds use the blade's own half-width.
        let s = sin(half)
        let maxOuter = (s * R) / (1 + s)
        let maxInner = s < 1 ? (s * r) / (1 - s) : .infinity
        let maxBand = (R - r) / 2 - 1
        let cr = max(0, min(Double(cornerRadius), maxOuter, maxInner, maxBand))

        guard cr > 0 else {
            var p = Path()
            p.move(to: pt(R, theta0))
            p.addArc(center: c, radius: outerRadius, startAngle: .radians(theta0), endAngle: .radians(theta1), clockwise: false)
            p.addLine(to: pt(r, theta1))
            p.addArc(center: c, radius: innerRadius, startAngle: .radians(theta1), endAngle: .radians(theta0), clockwise: true)
            p.closeSubpath()
            return p
        }

        let bo = asin(cr / (R - cr))   // angular inset of outer fillet tangent point
        let bi = asin(cr / (r + cr))   // angular inset of inner fillet tangent point
        let alphaO = (R - cr) * cos(bo)   // along-edge distance of outer fillet centre
        let alphaI = (r + cr) * cos(bi)   // along-edge distance of inner fillet centre

        // Unit basis for each boundary ray: u along the ray, n toward increasing angle.
        let u1 = CGPoint(x: cos(theta1), y: sin(theta1))
        let n1 = CGPoint(x: -sin(theta1), y: cos(theta1))
        let u0 = CGPoint(x: cos(theta0), y: sin(theta0))
        let n0 = CGPoint(x: -sin(theta0), y: cos(theta0))
        func frame(_ alpha: Double, _ beta: Double, _ u: CGPoint, _ n: CGPoint) -> CGPoint {
            CGPoint(x: c.x + alpha * u.x + beta * n.x, y: c.y + alpha * u.y + beta * n.y)
        }

        // Fillet feet on the radial edges; interior is -n on the a1 side, +n on a0.
        let e1Outer = frame(alphaO, 0, u1, n1)
        let e1Inner = frame(alphaI, 0, u1, n1)
        let e0Inner = frame(alphaI, 0, u0, n0)
        let e0Outer = frame(alphaO, 0, u0, n0)
        // Fillet centres (a further cr into the interior).
        let coEnd   = frame(alphaO, -cr, u1, n1)
        let ciEnd   = frame(alphaI, -cr, u1, n1)
        let ciStart = frame(alphaI, cr, u0, n0)
        let coStart = frame(alphaO, cr, u0, n0)

        // Adds the minor-arc fillet of radius cr around `center`, from `from` to `to`.
        func fillet(_ p: inout Path, _ center: CGPoint, from: CGPoint, to: CGPoint) {
            let aF = atan2(from.y - center.y, from.x - center.x)
            let aT = atan2(to.y - center.y, to.x - center.x)
            var d = aT - aF
            while d <= -.pi { d += 2 * .pi }
            while d > .pi { d -= 2 * .pi }
            p.addArc(center: center, radius: cr, startAngle: .radians(aF), endAngle: .radians(aT), clockwise: d < 0)
        }

        var p = Path()
        p.move(to: pt(R, theta0 + bo))
        p.addArc(center: c, radius: outerRadius, startAngle: .radians(theta0 + bo), endAngle: .radians(theta1 - bo), clockwise: false)
        fillet(&p, coEnd, from: pt(R, theta1 - bo), to: e1Outer)
        p.addLine(to: e1Inner)
        fillet(&p, ciEnd, from: e1Inner, to: pt(r, theta1 - bi))
        p.addArc(center: c, radius: innerRadius, startAngle: .radians(theta1 - bi), endAngle: .radians(theta0 + bi), clockwise: true)
        fillet(&p, ciStart, from: pt(r, theta0 + bi), to: e0Inner)
        p.addLine(to: e0Outer)
        fillet(&p, coStart, from: e0Outer, to: pt(R, theta0 + bo))
        p.closeSubpath()
        return p
    }
}
