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
            if let toast = service.current {
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
        .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
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
        case .error: .red
        case .info: .white.opacity(0.7)
        }
    }
}
