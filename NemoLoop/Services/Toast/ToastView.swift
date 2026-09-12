// NemoLoop/Services/Toast/ToastView.swift
import SwiftUI

/// Black-capsule toast: SF Symbol icon (semantic color by kind) + single-line
/// text. Fixed styling by design decision — deliberately NOT following the
/// RingPalette themes (system-HUD convention, strong contrast in both modes).
/// No Material anywhere: plain shape fill only.
struct ToastView: View {
    let service: ToastService

    var body: some View {
        ZStack {
            if service.visible, let toast = service.current {
                capsule(for: toast)
                    .transition(.opacity.combined(with: .offset(y: 6)))
            }
        }
        // The animation itself is driven by ToastService's withAnimation so
        // the fade duration stays a service-level (injectable) constant.
    }

    private func capsule(for toast: ToastService.Toast) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon(toast.kind))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(iconColor(toast.kind))
                .symbolEffect(.bounce, value: toast)
            Text(toast.text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 18)
        .frame(height: 44)
        .fixedSize()
        .background(.black.opacity(0.85))
        .clipShape(Capsule())
        // Light catches the top edge: a brighter upper stroke over a near-
        // invisible lower one reads as a lit capsule, not a flat outline.
        .overlay(Capsule().strokeBorder(
            LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.06)],
                           startPoint: .top, endPoint: .bottom),
            lineWidth: 0.5))
        .shadow(color: .black.opacity(0.4), radius: 14, y: 7)
    }

    private func icon(_ kind: ToastKind) -> String {
        switch kind {
        case .success: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        }
    }

    private func iconColor(_ kind: ToastKind) -> Color {
        switch kind {
        case .success: .green
        // System red sits too dark on the black fill (r1.0 g0.23 b0.19);
        // this lift keeps the error glyph readable at HUD contrast.
        case .error: Color(red: 1.0, green: 0.42, blue: 0.40)
        case .info: .white.opacity(0.7)
        }
    }
}
