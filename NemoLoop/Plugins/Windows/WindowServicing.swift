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

    /// This SDK's HIServices exports no kAXFullscreenAttribute constant
    /// (only the FullScreenButton variants); the wire name is "AXFullscreen".
    private static let fullscreenAttribute = "AXFullscreen"

    func isTrusted() -> Bool { AXIsProcessTrusted() }

    func promptForTrust() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func focusedWindowFrame() -> CGRect? {
        guard let window = focusedWindow() else { return nil }
        guard let position = value(window, kAXPositionAttribute) as? CGPoint,
              let size = value(window, kAXSizeAttribute) as? CGSize else { return nil }
        return CGRect(origin: position, size: size)
    }

    func setFrame(_ frame: CGRect) -> Bool {
        guard let window = focusedWindow() else { return false }
        var origin = frame.origin
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
        guard let current = attribute(window, Self.fullscreenAttribute) as? Bool else { return false }
        let next: CFTypeRef = !current ? kCFBooleanTrue : kCFBooleanFalse
        return setAttribute(window, Self.fullscreenAttribute, next)
    }

    // MARK: - AX plumbing

    private func focusedWindow() -> AXUIElement? {
        guard let app = element(systemWide, kAXFocusedApplicationAttribute) else { return nil }
        return element(app, kAXFocusedWindowAttribute)
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
