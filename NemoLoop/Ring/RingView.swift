// NemoLoop/Ring/RingView.swift
import SwiftUI

struct RingView: View {
    let store: SliceStore
    @Bindable var viewModel: RingViewModel
    @Environment(\.ringCenter) private var center

    private let outerRadius: CGFloat = 96
    private let innerRadius: CGFloat = 40
    private let wedgeCount = SliceConfig.wedgeCount

    init(store: SliceStore, viewModel: RingViewModel) {
        self.store = store
        self._viewModel = Bindable(viewModel)
    }

    var body: some View {
        ZStack {
            ForEach(0..<wedgeCount, id: \.self) { i in
                WedgeShape(index: i, count: wedgeCount,
                           innerRadius: innerRadius, outerRadius: outerRadius)
                    .fill(fillColor(for: i))
                    .overlay(
                        WedgeShape(index: i, count: wedgeCount,
                                   innerRadius: innerRadius, outerRadius: outerRadius)
                            .stroke(.white.opacity(0.15), lineWidth: 1)
                    )
                iconView(for: i)
            }
        }
        .frame(width: outerRadius * 2, height: outerRadius * 2)
        .position(center)
        .animation(.easeOut(duration: 0.12), value: viewModel.highlightedIndex)
    }

    private func fillColor(for i: Int) -> Color {
        let isEmpty = store.config.slots[i] == nil
        if viewModel.highlightedIndex == i {
            return isEmpty ? Color.white.opacity(0.18) : Color.accentColor.opacity(0.85)
        }
        return Color.black.opacity(isEmpty ? 0.35 : 0.6)
    }

    @ViewBuilder
    private func iconView(for i: Int) -> some View {
        let midRadius = (innerRadius + outerRadius) / 2
        // wedge i center angle: 0 = up, clockwise. Convert to view coords (y down).
        let angle = (Double(i) / Double(wedgeCount)) * 2 * .pi
        let dx = midRadius * sin(angle)
        let dy = -midRadius * cos(angle) // up = negative y in view space
        if let icon = store.icon(at: i) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 28, height: 28)
                .position(x: outerRadius + dx, y: outerRadius + dy)
        } else {
            Image(systemName: "plus")
                .foregroundStyle(.white.opacity(0.3))
                .position(x: outerRadius + dx, y: outerRadius + dy)
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
