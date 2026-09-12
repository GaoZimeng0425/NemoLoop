// Design/render_check_ocr_result.swift
//
// Render-check harness for the OCR result panel (OcrResultView verbatim).
// Same self-bootstrapping xcrun-swiftc pattern as render_check_toast.swift:
// `swift script.swift` cannot compile other files alongside the script, so
// with no --render-harness flag the script copies itself to a temp main.swift,
// compiles that copy together with the real app sources, runs the binary
// with the flag, and mirrors its exit code. With the flag it IS that binary.
//
// RUN (repo root):   swift Design/render_check_ocr_result.swift
// OUTPUT: Design/render_check_ocr_result.png (the panel with mixed
// original/translated rows over a dark stand-in). Prints one [CHECK] line
// per assertion + [VERDICT]; non-zero exit on any failure.
//
// Checks: material background renders (bright, mostly opaque), text renders
// (dark pixels over the light material), selected-row checkmarks render in
// the accent blue. Hover highlight and the panel fade-in live in AppKit
// interaction/NSPanel layers and are not assertable here.

import AppKit
import SwiftUI

// MARK: - Bootstrap (interpreted invocation: build the real harness and run it)

enum RenderCheckBootstrap {
    /// The app sources compiled verbatim alongside the script's temp main.swift copy.
    static let appSources = [
        "NemoLoop/Services/Ocr/OcrResultPanel.swift",
        "NemoLoop/Services/Ocr/OcrTextProcessor.swift",
    ]

    static func buildAndRun() -> Int32 {
        let scriptPath = #filePath
        let designDir = URL(fileURLWithPath: scriptPath).deletingLastPathComponent()
        let root = designDir.deletingLastPathComponent()
        let buildDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocr-result-harness-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)
            // swiftc requires the top-level-code file to be named main.swift.
            try FileManager.default.copyItem(at: URL(fileURLWithPath: scriptPath),
                                     to: buildDir.appendingPathComponent("main.swift"))
        } catch {
            print("render-check bootstrap: \(error)")
            return 1
        }
        let bin = buildDir.appendingPathComponent("ocr-result-harness")
        let compile = Process()
        compile.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compile.arguments = ["swiftc", "-D", "RENDER_HARNESS", "-o", bin.path,
                             buildDir.appendingPathComponent("main.swift").path]
            + appSources.map { root.appendingPathComponent($0).path }
        compile.currentDirectoryURL = root   // CWD = repo root while compiling
        compile.standardOutput = FileHandle.standardOutput
        compile.standardError = FileHandle.standardError
        do { try compile.run() } catch { print("render-check bootstrap: \(error)"); return 1 }
        compile.waitUntilExit()
        guard compile.terminationStatus == 0 else {
            print("render-check bootstrap: swiftc failed (\(compile.terminationStatus))")
            try? FileManager.default.removeItem(at: buildDir)
            return compile.terminationStatus
        }
        let run = Process()
        run.executableURL = bin
        run.arguments = ["--render-harness", designDir.path]
        run.currentDirectoryURL = root
        run.standardOutput = FileHandle.standardOutput
        run.standardError = FileHandle.standardError
        do { try run.run() } catch { print("render-check bootstrap: \(error)"); return 1 }
        run.waitUntilExit()
        try? FileManager.default.removeItem(at: buildDir)
        return run.terminationStatus
    }
}

#if RENDER_HARNESS
// MARK: - Harness (we are the compiled binary; the app types are in scope)

@MainActor
enum Harness {
    static let scale: Int = 2
    static var failures = 0
    static var designDir: URL!

    static var pngURL: URL { designDir.appendingPathComponent("render_check_ocr_result.png") }

    static func check(_ name: String, _ ok: Bool, _ detail: String) {
        print("[CHECK] \(ok ? "ok" : "FAIL")  \(name) — \(detail)")
        if !ok { failures += 1 }
    }

    static let rows: [OcrResultModel.Row] = [
        .init(id: 1, original: "The quick brown fox jumps over", translated: "敏捷的棕色狐狸跳过"),
        .init(id: 2, original: "the lazy dog.", translated: "懒惰的狗。"),
        .init(id: 3, original: "OCR result panel render check", translated: nil),
        .init(id: 4, original: "System preferences → Keyboard", translated: nil),
    ]

    /// Renders the real view through an offscreen window + cacheDisplay, NOT
    /// ImageRenderer: on this OS ImageRenderer leaves ScrollView content
    /// blank (verified with a minimal probe — plain VStack renders, any
    /// ScrollView doesn't), and the row list lives inside a ScrollView.
    static func renderPanel() -> NSBitmapImageRep {
        let size = NSSize(width: 320, height: OcrResultView.height(for: rows.count) + 64)
        let content = OcrResultView(model: OcrResultModel(rows: rows)) {}
            .frame(width: size.width, height: size.height)
            // The harness binary has no bundle, where app-tinted styles fall
            // back flat; pin the same system blue the real app renders with.
            .tint(Color.blue)
        let host = NSHostingView(rootView: content)
        // Pin a light appearance: the harness binary has no bundle/Info.plist,
        // so the system resolves dark for it and every material renders dark.
        host.appearance = NSAppearance(named: .aqua)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        window.orderOut(nil)
        return rep
    }

    static func run() {
        let rep = renderPanel()

        // Pixel stats over the panel bitmap. The content-row assertion is
        // scoped to the ScrollView band (below header, above footer) so it
        // cannot pass on header/footer text alone.
        var materialBright = 0, textDark = 0, accentBlue = 0, contentDark = 0, total = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let c = rep.colorAt(x: x, y: y) else { continue }
                total += 1
                let a = c.alphaComponent, r = c.redComponent, g = c.greenComponent, b = c.blueComponent
                let mx = max(r, g, b), mn = min(r, g, b)
                let lum = 0.299 * r + 0.587 * g + 0.114 * b
                if a > 0.5 && lum > 0.80 { materialBright += 1 }
                if a > 0.5 && lum < 0.30 {
                    textDark += 1
                    if y > 40 && y < rep.pixelsHigh - 30 { contentDark += 1 }
                }
                if a > 0.5 && (mx - mn) > 0.30 && b > r + 0.15 && b > g + 0.15 && b > 0.5 { accentBlue += 1 }
            }
        }

        check("material-renders", materialBright > total * 3 / 10,
              "bright=\(materialBright)/\(total)")
        check("content-rows-render", contentDark > 120, "contentDark=\(contentDark)")
        check("checkmark-accent-blue", accentBlue > 10, "blue=\(accentBlue)")

        // Compose the PNG artifact over a dark stand-in so the translucent
        // material is visible in review.
        let compose = Image(nsImage: NSImage(cgImage: rep.cgImage!, size: rep.size))
            .resizable()
            .frame(width: rep.size.width, height: rep.size.height)
            .padding(24)
            .background(Color(white: 0.10))
        let cr = ImageRenderer(content: compose)
        cr.scale = Double(scale)
        let data = cr.nsImage!.tiffRepresentation!
        let out = NSBitmapImageRep(data: data)!
        if let png = out.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) {
            do {
                try png.write(to: pngURL)
            } catch {
                print("[VERDICT] FAILED to write png artifact — \(pngURL.path): \(error)")
                failures += 1
            }
        } else {
            print("[VERDICT] FAILED to encode png artifact — \(pngURL.path)")
            failures += 1
        }

        print(failures == 0 ? "[VERDICT] all checks passed" : "[VERDICT] \(failures) FAILED")
        // Exit DIRECTLY with the verdict code: NSApp.terminate(nil) would end
        // the process with status 0 and silently swallow every failure.
        exit(failures == 0 ? 0 : 1)
    }
}

// MARK: - Entry (project convention: keep the runloop alive with NSApp.run())

MainActor.assumeIsolated {
    guard CommandLine.arguments.contains("--render-harness"), CommandLine.arguments.count > 2 else {
        print("ocr-result render-check: bad invocation (expected --render-harness <designDir>)")
        exit(2)
    }
    Harness.designDir = URL(fileURLWithPath: CommandLine.arguments[2])
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    DispatchQueue.main.async { Task { @MainActor in Harness.run() } }
    app.run()
    exit(Harness.failures == 0 ? 0 : 1)   // unreachable: run() exits first
}
#else
// Interpreted invocation (`swift Design/render_check_ocr_result.swift`):
// bootstrap the compiled harness and mirror its exit code.
exit(RenderCheckBootstrap.buildAndRun())
#endif
