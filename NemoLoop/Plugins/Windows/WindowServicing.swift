// NemoLoop/Plugins/Windows/WindowServicing.swift
import AppKit
import ApplicationServices
import Foundation

/// Testability seam between the plugin ops and the Accessibility API —
/// the one untestable dependency in the plugin, isolated here (the
/// ShellRunning pattern). Real AX behavior is pinned indirectly: geometry
/// by WindowLayoutTests, routing by WindowPluginTests over a fake.
@MainActor
protocol WindowServicing: AnyObject {
    /// AXIsProcessTrusted() — the Accessibility TCC grant.
    func isTrusted() -> Bool
    /// System authorization prompt (AXIsProcessTrustedWithOptions with the
    /// prompt option — opens System Settings with this app pre-selected).
    func promptForTrust()
    /// Frame of the focused window, nil when there is none (desktop).
    func focusedWindowFrame() -> CGRect?
    /// Writes position + size to the focused window.
    @discardableResult func setFrame(_ frame: CGRect) -> Bool
    /// kAXMinimized = true on the focused window.
    @discardableResult func setMinimized() -> Bool
    /// kAXFullScreen toggled on the focused window.
    @discardableResult func toggleFullscreen() -> Bool
}

@MainActor
final class AccessibilityWindowService: WindowServicing {
    // nonisolated init: default-argument construction runs in a nonisolated
    // context (see ChainPlugin/ChainExecutor for the same constraint).
    nonisolated init() {}

    private var systemWide: AXUIElement { AXUIElementCreateSystemWide() }

    /// This SDK's HIServices exports no fullscreen-state constant (only the
    /// FullScreenButton variants); the window attribute's wire name is
    /// "AXFullScreen" — capital S, matching the AXFullScreenButton family.
    private static let fullscreenAttribute = "AXFullScreen"

    func isTrusted() -> Bool { AXIsProcessTrusted() }

    func promptForTrust() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func focusedWindowFrame() -> CGRect? {
        guard let window = focusedWindow() else { return nil }
        guard let position = value(window, kAXPositionAttribute) as? CGPoint,
              let size = value(window, kAXSizeAttribute) as? CGSize else { return nil }
        guard let primaryMaxY = NSScreen.screens.first?.frame.maxY else { return nil }
        return Self.appKitFrame(fromAX: CGRect(origin: position, size: size), primaryMaxY: primaryMaxY)
    }

    func setFrame(_ frame: CGRect) -> Bool {
        guard let window = focusedWindow() else { return false }
        guard let primaryMaxY = NSScreen.screens.first?.frame.maxY else { return false }
        let converted = Self.axFrame(fromAppKit: frame, primaryMaxY: primaryMaxY)
        var origin = converted.origin
        var size = frame.size
        guard let position = AXValueCreate(.cgPoint, &origin),
              let axSize = AXValueCreate(.cgSize, &size) else { return false }
        return setAttribute(window, kAXPositionAttribute, position)
            && setAttribute(window, kAXSizeAttribute, axSize)
    }

    func setMinimized() -> Bool {
        guard let window = focusedWindow() else { return false }
        // AX booleans are plain CFBoolean — AXValue has no bool wrapper on
        // this SDK (point/size/rect/range/error only).
        return setAttribute(window, kAXMinimizedAttribute, kCFBooleanTrue)
    }

    func toggleFullscreen() -> Bool {
        guard let window = focusedWindow() else { return false }
        guard let current = attribute(window, Self.fullscreenAttribute) as? Bool else {
            NSLog("NemoLoop windows: AX read \(Self.fullscreenAttribute) failed")
            return false
        }
        let next: CFTypeRef = !current ? kCFBooleanTrue : kCFBooleanFalse
        return setAttribute(window, Self.fullscreenAttribute, next)
    }

    // MARK: - AX plumbing

    private func focusedWindow() -> AXUIElement? {
        guard let app = element(systemWide, kAXFocusedApplicationAttribute),
              let window = element(app, kAXFocusedWindowAttribute) else {
            NSLog("NemoLoop windows: no focused window")
            return nil
        }
        return window
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        guard error == .success else { return nil }
        return value
    }

    /// CFTypeRef → AXUIElement: CF-to-CF casts are unchecked reinterpretations,
    /// so Swift rejects the conditional form ("always succeeds") — rebit instead.
    private func element(_ parent: AXUIElement, _ name: String) -> AXUIElement? {
        attribute(parent, name).map { unsafeBitCast($0, to: AXUIElement.self) }
    }

    private func setAttribute(_ element: AXUIElement, _ name: String, _ value: CFTypeRef) -> Bool {
        let error = AXUIElementSetAttributeValue(element, name as CFString, value)
        guard error == .success else {
            NSLog("NemoLoop windows: AX set \(name) failed (\(error.rawValue))")
            return false
        }
        return true
    }

    /// Unwraps an AXValue of the expected type.
    private func value(_ element: AXUIElement, _ name: String) -> Any? {
        guard let raw = attribute(element, name) else { return nil }
        var point = CGPoint.zero
        if AXValueGetValue(raw as! AXValue, .cgPoint, &point) { return point }
        var size = CGSize.zero
        if AXValueGetValue(raw as! AXValue, .cgSize, &size) { return size }
        return nil
    }
}

/// AX global coordinates are top-left origin; AppKit is bottom-left. The
/// flip is one global linear transform against the primary screen's top
/// (NSScreen.screens.first.frame.maxY — the screen at origin (0,0)).
extension AccessibilityWindowService {
    static func appKitFrame(fromAX frame: CGRect, primaryMaxY: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryMaxY - frame.maxY, width: frame.width, height: frame.height)
    }

    static func axFrame(fromAppKit frame: CGRect, primaryMaxY: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryMaxY - frame.maxY, width: frame.width, height: frame.height)
    }
}
