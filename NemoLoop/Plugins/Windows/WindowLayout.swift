// NemoLoop/Plugins/Windows/WindowLayout.swift
import CoreGraphics
import Foundation

/// Snap regions the Windows plugin offers. All frame math is pure and
/// relative to a screen's visibleFrame (AppKit coordinates, origin
/// bottom-left; menu bar and Dock already excluded by the caller) — the
/// multi-screen/notch/Dock cases collapse into one input rectangle.
enum WindowRegion: String, CaseIterable, Identifiable {
    case halfLeft, halfRight, halfTop, halfBottom
    case thirdLeft, thirdCenter, thirdRight
    case quadrantTopLeft, quadrantTopRight, quadrantBottomLeft, quadrantBottomRight
    case maximize

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .halfLeft: "Left Half"
        case .halfRight: "Right Half"
        case .halfTop: "Top Half"
        case .halfBottom: "Bottom Half"
        case .thirdLeft: "Left Third"
        case .thirdCenter: "Center Third"
        case .thirdRight: "Right Third"
        case .quadrantTopLeft: "Top Left Quarter"
        case .quadrantTopRight: "Top Right Quarter"
        case .quadrantBottomLeft: "Bottom Left Quarter"
        case .quadrantBottomRight: "Bottom Right Quarter"
        case .maximize: "Maximize"
        }
    }

    var symbolName: String {
        switch self {
        case .halfLeft: "rectangle.lefthalf.filled"
        case .halfRight: "rectangle.righthalf.filled"
        case .halfTop: "rectangle.tophalf.filled"
        case .halfBottom: "rectangle.bottomhalf.filled"
        case .thirdLeft: "rectangle.leadingthird.inset.filled"
        case .thirdCenter: "rectangle.inset.filled"
        case .thirdRight: "rectangle.trailingthird.inset.filled"
        case .quadrantTopLeft: "arrow.up.left.square"
        case .quadrantTopRight: "arrow.up.right.square"
        case .quadrantBottomLeft: "arrow.down.left.square"
        case .quadrantBottomRight: "arrow.down.right.square"
        case .maximize: "arrow.up.left.and.arrow.down.right"
        }
    }

    /// Target frame in screen points for the given visible area.
    func targetFrame(in v: CGRect) -> CGRect {
        switch self {
        case .halfLeft: CGRect(x: v.minX, y: v.minY, width: v.width / 2, height: v.height)
        case .halfRight: CGRect(x: v.midX, y: v.minY, width: v.width / 2, height: v.height)
        case .halfTop: CGRect(x: v.minX, y: v.midY, width: v.width, height: v.height / 2)
        case .halfBottom: CGRect(x: v.minX, y: v.minY, width: v.width, height: v.height / 2)
        case .thirdLeft: CGRect(x: v.minX, y: v.minY, width: v.width / 3, height: v.height)
        case .thirdCenter: CGRect(x: v.minX + v.width / 3, y: v.minY, width: v.width / 3, height: v.height)
        case .thirdRight: CGRect(x: v.minX + 2 * v.width / 3, y: v.minY, width: v.width / 3, height: v.height)
        case .quadrantTopLeft: CGRect(x: v.minX, y: v.midY, width: v.width / 2, height: v.height / 2)
        case .quadrantTopRight: CGRect(x: v.midX, y: v.midY, width: v.width / 2, height: v.height / 2)
        case .quadrantBottomLeft: CGRect(x: v.minX, y: v.minY, width: v.width / 2, height: v.height / 2)
        case .quadrantBottomRight: CGRect(x: v.midX, y: v.minY, width: v.width / 2, height: v.height / 2)
        case .maximize: v
        }
    }
}
