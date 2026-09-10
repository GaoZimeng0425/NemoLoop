// Design/render_check_toast.swift
//
// Render-check harness for the global toast capsule (spec 2026-09-11).
// Compiles the REAL ToastService.swift + ToastView.swift verbatim via the
// self-bootstrapping xcrun-swiftc pattern (rationale in
// render_check_plugin_subwheel.swift's header): `swift script.swift` cannot
// compile other files alongside the script, and a plain script cannot import
// the app module — so with no `--render-harness` flag the script copies
// itself to a temp main.swift, compiles that copy together with the real app
// sources via `xcrun swiftc`, runs the binary with the flag, and mirrors its
// exit code. With the flag it IS that binary and does the render.
//
// RUN (repo root):   swift Design/render_check_toast.swift
// OUTPUT: Design/render_check_toast.png (success/error/info rows over a dark
// stand-in). Prints one [CHECK] line per assertion + [VERDICT]; non-zero
// exit on any failure.
//
// Checks per kind: capsule pixels present (alpha), fill is black-dominant,
// icon region saturated (green/red), text region bright. Plus: a fresh
// service renders fully transparent (blank case).
//
// Deviations from the task brief's literal listing (all minimal, documented
// in the task-3 report):
//   * The harness body sits behind `#if RENDER_HARNESS` (reference-harness
//     pattern): the interpreted `swift script.swift` pass type-checks this
//     file WITHOUT the app sources, so references to app types
//     (ToastKind/ToastService/ToastView) must be compiled out of that pass.
//   * `render`'s redundant NSRect double-assignment is simplified away (the
//     rect was never consumed by the caller).
//   * The entry boots via MainActor.assumeIsolated (top-level code is
//     nonisolated; NSApplication.shared is MainActor-isolated), and
//     Harness.run exits the process DIRECTLY with the verdict code —
//     NSApp.terminate would end with status 0 and swallow failures.

import AppKit
import SwiftUI

// MARK: - Bootstrap (interpreted invocation: build the real harness and run it)

enum RenderCheckBootstrap {
    /// The app sources compiled verbatim alongside the script's temp main.swift copy.
    static let appSources = [
        "NemoLoop/Services/Toast/ToastService.swift",
        "NemoLoop/Services/Toast/ToastView.swift",
    ]

    static func buildAndRun() -> Int32 {
        let scriptPath = #filePath
        let designDir = URL(fileURLWithPath: scriptPath).deletingLastPathComponent()
        let root = designDir.deletingLastPathComponent()
        let buildDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("toast-harness-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)
            // swiftc requires the top-level-code file to be named main.swift.
            try FileManager.default.copyItem(at: URL(fileURLWithPath: scriptPath),
                                             to: buildDir.appendingPathComponent("main.swift"))
        } catch {
            print("render-check bootstrap: \(error)")
            return 1
        }
        let bin = buildDir.appendingPathComponent("toast-harness")
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

    static var pngURL: URL { designDir.appendingPathComponent("render_check_toast.png") }

    static func check(_ name: String, _ ok: Bool, _ detail: String) {
        print("[CHECK] \(ok ? "ok" : "FAIL")  \(name) — \(detail)")
        if !ok { failures += 1 }
    }

    /// Renders one shown toast over a transparent canvas; 60s durations so no
    /// dismiss can fire mid-render.
    static func render(_ kind: ToastKind, _ text: String) -> NSBitmapImageRep {
        let service = ToastService(toastDuration: 60, errorDuration: 60, fadeDuration: 60)
        service.show(kind, text)
        let view = ToastView(service: service)
            .frame(width: 480, height: 60)
        let renderer = ImageRenderer(content: view)
        renderer.scale = Double(scale)
        let image = renderer.nsImage!
        return NSBitmapImageRep(data: image.tiffRepresentation!)!
    }

    /// RGBA pixel stats over the whole bitmap.
    static func stats(_ rep: NSBitmapImageRep) -> (alphaOn: Int, black: Int, saturated: Int, bright: Int) {
        var alphaOn = 0, black = 0, saturated = 0, bright = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let c = rep.colorAt(x: x, y: y) else { continue }
                let a = c.alphaComponent, r = c.redComponent, g = c.greenComponent, b = c.blueComponent
                let mx = max(r, g, b), mn = min(r, g, b)
                let lum = 0.299 * r + 0.587 * g + 0.114 * b
                if a > 0.8 { alphaOn += 1 }
                if a > 0.8 && lum < 0.30 { black += 1 }
                if a > 0.8 && (mx - mn) > 0.35 && mx > 0.3 { saturated += 1 }
                if a > 0.8 && lum > 0.80 { bright += 1 }
            }
        }
        return (alphaOn, black, saturated, bright)
    }

    static func run() {
        // Blank: a fresh service must render nothing at all.
        let blankService = ToastService(toastDuration: 60, errorDuration: 60, fadeDuration: 60)
        let blankRenderer = ImageRenderer(content: ToastView(service: blankService)
                                            .frame(width: 480, height: 60))
        blankRenderer.scale = Double(scale)
        let blankRep = NSBitmapImageRep(data: blankRenderer.nsImage!.tiffRepresentation!)!
        let (bA, _, _, _) = stats(blankRep)
        check("blank-transparent", bA == 0, "alphaOn=\(bA)")

        let kinds: [(ToastKind, String, String)] = [
            (.success, "Snipped to clipboard", "success"),
            (.error, "OCR failed: timeout", "error"),
            (.info, "No text recognized", "info"),
        ]
        var rows: [NSImage] = []
        for (kind, text, label) in kinds {
            let rep = render(kind, text)
            let (a, k, s, br) = stats(rep)
            check("\(label)-capsule-present", a > 2000, "alphaOn=\(a)")
            check("\(label)-fill-black", k > a * 7 / 10, "black=\(k)/\(a)")
            if kind != .info {
                check("\(label)-icon-colored", s > 30, "saturated=\(s)")
            }
            check("\(label)-text-bright", br > 200, "bright=\(br)")
            rows.append(NSImage(cgImage: rep.cgImage!, size: rep.size))
        }

        // Compose the PNG artifact (the three rows on a dark stand-in).
        let compose = VStack(spacing: 12) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                Image(nsImage: row).resizable().frame(width: 480, height: 60)
            }
        }
        .padding(20)
        .background(Color(white: 0.10))
        let cr = ImageRenderer(content: compose)
        cr.scale = Double(scale)
        let data = cr.nsImage!.tiffRepresentation!
        let out = NSBitmapImageRep(data: data)!
        if let png = out.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) {
            try? png.write(to: pngURL)
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
        print("toast render-check: bad invocation (expected --render-harness <designDir>)")
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
// Interpreted invocation (`swift Design/render_check_toast.swift`):
// bootstrap the compiled harness and mirror its exit code.
exit(RenderCheckBootstrap.buildAndRun())
#endif
