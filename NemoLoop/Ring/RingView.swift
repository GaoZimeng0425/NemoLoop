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
            backing()

            ForEach(0..<wedgeCount, id: \.self) { i in
                wedgeFill(for: i)
                    .overlay(
                        WedgeShape(index: i, count: wedgeCount,
                                   innerRadius: RingTheme.innerRadius,
                                   outerRadius: RingTheme.outerRadius)
                            .stroke(RingTheme.dividerColor, lineWidth: RingTheme.dividerWidth)
                    )
                iconView(for: i)
            }

            borders()
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

    // MARK: - Backing material (frosted glass)

    @ViewBuilder
    private func backing() -> some View {
        let band = Circle().strokeBorder(lineWidth: RingTheme.outerRadius - RingTheme.innerRadius)
        if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(.regular.tint(RingTheme.accentStart.opacity(0.025)),
                             in: .circle)
                .mask(band)
        } else {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow, state: .active)
                .mask(band)
        }
    }

    // MARK: - Per-wedge fills

    @ViewBuilder
    private func wedgeFill(for i: Int) -> some View {
        let shape = WedgeShape(index: i, count: wedgeCount,
                               innerRadius: RingTheme.innerRadius,
                               outerRadius: RingTheme.outerRadius)
        let isEmpty = store.config.slots[i] == nil
        let isHot = viewModel.highlightedIndex == i

        if isHot && !isEmpty {
            shape.fill(RingTheme.accentGradient)
        } else if isHot {
            shape.fill(RingTheme.highlightEmpty)
        } else {
            shape.fill(isEmpty ? RingTheme.emptyFill : RingTheme.baseFill)
        }
    }

    // MARK: - Dual hairline border rims

    @ViewBuilder
    private func borders() -> some View {
        ZStack {
            Circle()
                .stroke(RingTheme.borderColor, lineWidth: RingTheme.borderWidth)
                .frame(width: RingTheme.outerRadius * 2,
                       height: RingTheme.outerRadius * 2)
            Circle()
                .stroke(RingTheme.borderColor, lineWidth: RingTheme.borderWidth)
                .frame(width: RingTheme.innerRadius * 2,
                       height: RingTheme.innerRadius * 2)
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
struct WedgeShape: Shape {
    let index: Int
    let count: Int
    let innerRadius: CGFloat
    let outerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let slice = 2 * Double.pi / Double(count)
        // SwiftUI angles: 0° = +x (right), increasing clockwise (y down).
        // Wedge 0 centered on up (= -90° / 270°), spanning ±half slice.
        let centerAngle = -Double.pi / 2 + Double(index) * slice
        let start = Angle(radians: centerAngle - slice / 2)
        let end = Angle(radians: centerAngle + slice / 2)

        var p = Path()
        p.addArc(center: c, radius: outerRadius, startAngle: start, endAngle: end, clockwise: false)
        p.addArc(center: c, radius: innerRadius, startAngle: end, endAngle: start, clockwise: true)
        p.closeSubpath()
        return p
    }
}
