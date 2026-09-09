// NemoLoop/Plugins/ScreenshotPlugin.swift
import Foundation

/// Single-operation plugin: a command-shift-4 style region snip whose pixels
/// go straight to the clipboard — reuses the OCR selection and permission flow.
@MainActor
final class ScreenshotPlugin: @MainActor NemoPlugin {
    let id = "screenshot"
    let displayName = "Screenshot"
    let symbolName = "camera.viewfinder"
    let summary = "Drag a region; the pixels go straight to your clipboard."

    struct Op: @MainActor PluginOp {
        let id = "snipToClipboard"
        let displayName = "Snip to Clipboard"
        let symbolName = "camera.viewfinder"
        func perform() { OcrSessionController.shared.handleRequested(mode: .snip) }
    }

    var operations: [any PluginOp] { [Op()] }
    var status: PluginStatus { .ready }
}
