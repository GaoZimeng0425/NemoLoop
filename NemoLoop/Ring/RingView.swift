// NemoLoop/Ring/RingView.swift
import SwiftUI

struct RingView: View {
    let store: SliceStore
    @Bindable var viewModel: RingViewModel
    @Environment(\.ringCenter) private var center

    @State private var appeared = false

    private let wedgeCount = SliceConfig.wedgeCount

    init(store: SliceStore, viewModel: RingViewModel) {
        self.store = store
        self._viewModel = Bindable(viewModel)
    }

    var body: some View {
        ZStack {
            ForEach(0..<wedgeCount, id: \.self) { i in
                wedgeFill(for: i)
                    .overlay(
                        WedgeShape(index: i, count: wedgeCount,
                                   innerRadius: RingTheme.innerRadius,
                                   outerRadius: RingTheme.outerRadius,
                                   cornerRadius: RingTheme.wedgeCornerRadius,
                                   gap: RingTheme.wedgeGap)
                            .stroke(RingTheme.dividerColor, lineWidth: RingTheme.dividerWidth)
                    )
                iconView(for: i)
            }
        }
        .frame(width: RingTheme.outerRadius * 2, height: RingTheme.outerRadius * 2)
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

    // MARK: - Per-wedge fills

    @ViewBuilder
    private func wedgeFill(for i: Int) -> some View {
        let shape = WedgeShape(index: i, count: wedgeCount,
                               innerRadius: RingTheme.innerRadius,
                               outerRadius: RingTheme.outerRadius,
                               cornerRadius: RingTheme.wedgeCornerRadius,
                               gap: RingTheme.wedgeGap)
        let isEmpty = store.config.slots[i] == nil
        let isHot = viewModel.highlightedIndex == i

        ZStack {
            shape.fill(RingTheme.backgroundColor)   // per-wedge background

            if isHot && !isEmpty {
                shape.fill(RingTheme.accentGradient)
            } else if isHot {
                shape.fill(RingTheme.highlightEmpty)
            } else if !isEmpty {
                shape.fill(RingTheme.backgroundColor)
            }
        }
    }

    // MARK: - Icons

    @ViewBuilder
    private func iconView(for i: Int) -> some View {
        let midRadius = (RingTheme.innerRadius + RingTheme.outerRadius) / 2
        let angle = (Double(i) / Double(wedgeCount)) * 2 * .pi
        let dx = midRadius * sin(angle)
        let dy = -midRadius * cos(angle)
        let x = RingTheme.outerRadius + dx
        let y = RingTheme.outerRadius + dy

        if let icon = store.icon(at: i) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: RingTheme.iconSize, height: RingTheme.iconSize)
                .position(x: x, y: y)
        } else {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(RingTheme.iconTint.opacity(0.35))
                .position(x: x, y: y)
        }
    }
}

/// A donut wedge (annular sector) for index `i` of `count`, centered on up, clockwise.
/// `cornerRadius` rounds the four corners with circular fillets while keeping the
/// outer/inner arcs and straight radial edges exact. `gap` (points) is the total
/// perpendicular separation left between neighbouring wedges — each radial edge is
/// offset inward by `gap/2`, so adjacent edges stay parallel and aligned (a constant-
/// width gap), instead of the wedge-shaped gap an angular shave would produce.
struct WedgeShape: Shape {
    let index: Int
    let count: Int
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    var cornerRadius: CGFloat = 0
    var gap: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let slice = 2 * Double.pi / Double(count)
        // SwiftUI angles: 0° = +x (right), increasing clockwise (y down).
        // Wedge 0 centered on up (= -90° / 270°).
        let centerAngle = -Double.pi / 2 + Double(index) * slice
        let theta0 = centerAngle - slice / 2   // a0-side boundary ray
        let theta1 = centerAngle + slice / 2   // a1-side boundary ray
        let R = Double(outerRadius)
        let r = Double(innerRadius)
        let g = max(0, Double(gap) / 2)         // perpendicular inset of each radial edge

        func pt(_ radius: Double, _ angle: Double) -> CGPoint {
            CGPoint(x: c.x + radius * cos(angle), y: c.y + radius * sin(angle))
        }

        // The radial edge offset inward by `g` meets a circle of radius ρ at the boundary
        // angle ∓ asin(g/ρ) — a larger angular inset near the hub, smaller at the rim, so
        // the two edges of the gap stay parallel.
        let a0o = theta0 + asin(min(1, g / R))   // a0 side, outer
        let a1o = theta1 - asin(min(1, g / R))   // a1 side, outer
        let a0i = theta0 + asin(min(1, g / r))   // a0 side, inner
        let a1i = theta1 - asin(min(1, g / r))   // a1 side, inner

        // Sharp wedge when rounding is off.
        guard cornerRadius > 0 else {
            var p = Path()
            p.move(to: pt(R, a0o))
            p.addArc(center: c, radius: outerRadius, startAngle: .radians(a0o), endAngle: .radians(a1o), clockwise: false)
            p.addLine(to: pt(r, a1i))
            p.addArc(center: c, radius: innerRadius, startAngle: .radians(a1i), endAngle: .radians(a0i), clockwise: true)
            p.closeSubpath()   // straight radial edge back to (R, a0o)
            return p
        }

        // Clamp so fillets never overlap on an arc, invert the radial edge, or exceed the band.
        // Each fillet centre sits a perpendicular distance (g + cr) from its boundary ray, so
        // its angular inset is asin((g+cr)/ρ); requiring that < slice/2 bounds cr.
        let s = sin(slice / 2)
        let maxOuter = (s * R - g) / (1 + s)
        let maxInner = s < 1 ? (s * r - g) / (1 - s) : .infinity
        let maxBand = (R - r) / 2 - 1
        let cr = max(0, min(Double(cornerRadius), maxOuter, maxInner, maxBand))

        guard cr > 0 else {
            var p = Path()
            p.move(to: pt(R, a0o))
            p.addArc(center: c, radius: outerRadius, startAngle: .radians(a0o), endAngle: .radians(a1o), clockwise: false)
            p.addLine(to: pt(r, a1i))
            p.addArc(center: c, radius: innerRadius, startAngle: .radians(a1i), endAngle: .radians(a0i), clockwise: true)
            p.closeSubpath()
            return p
        }

        let bo = asin((g + cr) / (R - cr))   // angular inset of outer fillet tangent point
        let bi = asin((g + cr) / (r + cr))   // angular inset of inner fillet tangent point
        let alphaO = (R - cr) * cos(bo)      // along-edge distance of outer fillet centre
        let alphaI = (r + cr) * cos(bi)      // along-edge distance of inner fillet centre

        // Unit basis for each boundary ray: u along the ray, n toward increasing angle.
        let u1 = CGPoint(x: cos(theta1), y: sin(theta1))
        let n1 = CGPoint(x: -sin(theta1), y: cos(theta1))
        let u0 = CGPoint(x: cos(theta0), y: sin(theta0))
        let n0 = CGPoint(x: -sin(theta0), y: cos(theta0))
        func frame(_ alpha: Double, _ beta: Double, _ u: CGPoint, _ n: CGPoint) -> CGPoint {
            CGPoint(x: c.x + alpha * u.x + beta * n.x, y: c.y + alpha * u.y + beta * n.y)
        }

        // Foot of each fillet on its radial edge (perpendicular offset g from the boundary ray;
        // interior is -n on the a1 side, +n on the a0 side).
        let e1Outer = frame(alphaO, -g, u1, n1)
        let e1Inner = frame(alphaI, -g, u1, n1)
        let e0Inner = frame(alphaI, g, u0, n0)
        let e0Outer = frame(alphaO, g, u0, n0)
        // Fillet centres (a further cr into the interior).
        let coEnd   = frame(alphaO, -(g + cr), u1, n1)
        let ciEnd   = frame(alphaI, -(g + cr), u1, n1)
        let ciStart = frame(alphaI, g + cr, u0, n0)
        let coStart = frame(alphaO, g + cr, u0, n0)

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
