// Design/render_check_plugin_subwheel.swift
//
// Task 9 render-check harness: verifies the plugin sub-wheel rendering against
// the four-point checklist from the plugin architecture spec:
//   1. Second-tier blades on the 15-degree grid, all 8 visible, band OUTSIDE
//      (below/outboard of) the icon ring.
//   2. Wrap gap empty (nothing inhabits the gap just counterclockwise of blade 0).
//   3. The disconnected plugin's blade is desaturated/dimmed; the others normal.
//   4. Pixel histogram non-blank + the dim blade's region distinguishable from a
//      healthy neighbor's region (saturation + brightness numbers).
//
// RUN (from the worktree root, exactly as the task brief specifies):
//
//     swift Design/render_check_plugin_subwheel.swift
//
// HOW IT BUILDS: `swift script.swift extra.swift` does NOT compile the extra
// files together with the script (they arrive as CommandLine.arguments), and a
// plain script cannot `import NemoLoop` (an executable module, no framework is
// produced). So the script bootstraps itself: with no `--render-harness` flag
// it copies itself to a temp `main.swift`, compiles that copy together with the
// real app sources below via `xcrun swiftc`, runs the binary with the flag, and
// mirrors its exit code. With the flag it IS that binary and does the render.
//
// App sources compiled verbatim (the render path under test — geometry, theme,
// view model state machine, and the model constants they read):
//     NemoLoop/Ring/RingView.swift        (RingView + CardBladeShape)
//     NemoLoop/Ring/RingTheme.swift       (RingTheme + RingPalette)
//     NemoLoop/Ring/RingGeometry.swift    (BladeLayout + RingGeometry)
//     NemoLoop/Ring/RingViewModel.swift   (dwell/openSubIndex state machine)
//     NemoLoop/Model/SliceConfig.swift    (SliceConfig.wedgeCount)
//     NemoLoop/Model/SlotAction.swift     (SlotEntry.maxPluginChildren)
//
// WHY THE STORE LAYER IS MIRROD, NOT COMPILED: SliceStore/PluginRegistry pull
// in SystemActions/ScreenshotPlugin -> OcrSessionController and the whole OCR
// stack, which is far outside this render probe. What the render needs from
// them is only (a) the per-slot icon/subicon NSImages (produced here with the
// same SymbolPlate recipe, verbatim below) and (b) the summon-time `dimmed`
// snapshot (RingSummoner computes it from PluginRegistry enablement; the
// "appearance" plugin is opt-in — isEnabledByDefault false — so in a fresh
// defaults suite its blade is dim, while "system" ships connected and is not).
// That store/registry behavior is covered by the task 1-8 unit tests; this
// harness verifies the RENDER. The two blocks copied verbatim from the app are
// marked with their provenance below.
//
// STATE DRIVING: the sub-wheel only exists while `viewModel.openSubIndex` is
// set, which only the dwell path sets (it is `private(set)`). We drive the REAL
// state machine exactly like RingSubWheelTests.dwellOpensTheWheel: begin()
// followed by two updatePointer(at:now:) calls with the injected clock past
// subDwellDuration. begin() uses `.vector` input with a zero-vector provider so
// its 120 Hz timer (which samples the REAL mouse on `.pointer`) can never
// disturb the offline render; updatePointer is the same core either way.
// Blades are pre-dealt via RingView's `preAppeared: true` (its designated
// offline path — onAppear never fires without a window), and the sub-blades'
// deal-in is bound directly to openSubIndex, so they render deterministically
// at full scale offline. Per project convention the runloop is kept alive
// (NSApp.run()) and a second snapshot is taken 0.7 s later, compared for
// stability, and written back over the first.
//
// OUTPUT: Design/render_check_subwheel.png (2x scale, 856x856 px, dark scheme
// over a dark wallpaper stand-in — the "very dark background" case the spec
// says must be pixel-verified, not just exported). The script prints one
// [CHECK]/[STAT]/[VERDICT] line per assertion and exits non-zero on any fail.

import AppKit
import SwiftUI

// MARK: - Verbatim copies from the app (do not let these drift)

/// Verbatim from NemoLoop/Ring/RingWindowController.swift (the key itself is
/// private there; only the EnvironmentValues extension is visible to RingView).
/// Copied so RingView compiles unmodified outside the app module.
private struct RingCenterKey: EnvironmentKey {
    static let defaultValue: CGPoint = .zero
}
extension EnvironmentValues {
    var ringCenter: CGPoint {
        get { self[RingCenterKey.self] }
        set { self[RingCenterKey.self] = newValue }
    }
}

/// Verbatim from NemoLoop/Helpers/SymbolPlate.swift — the exact icon recipe the
/// app uses for plugin references (monochrome systemGray symbol on a plate).
enum SymbolPlate {
    static func image(symbolName: String, label: String) -> NSImage {
        let size = NSSize(width: 32, height: 32)
        let img = NSImage(size: size)
        img.lockFocus()
        defer { img.unlockFocus() }
        guard let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: label) else {
            return img
        }
        var configured = base.withSymbolConfiguration(.init(pointSize: 22, weight: .medium))
        configured = configured?.withSymbolConfiguration(.init(paletteColors: [.systemGray]))
        configured?.draw(in: NSRect(origin: .zero, size: size),
                         from: .zero, operation: .sourceOver, fraction: 1,
                         respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
        return img
    }
}

// MARK: - Harness
//
// The harness section only compiles in the multi-file program the bootstrap
// builds (`swiftc -D RENDER_HARNESS main.swift <app sources>`); the interpreted
// invocation type-checks this file WITHOUT the app sources, so every reference
// to app types sits behind this condition.

#if RENDER_HARNESS

var renderCheckExitCode: Int32 = 0

@MainActor
private func fail(_ message: String) {
    print("[CHECK] FAIL: \(message)")
    renderCheckExitCode = 1
}

@MainActor
private func check(_ condition: Bool, _ message: String) {
    print("[CHECK] \(condition ? "PASS" : "FAIL"): \(message)")
    if !condition { renderCheckExitCode = 1 }
}

@MainActor
private func verdict(_ condition: Bool, _ message: String) {
    print("[VERDICT] \(condition ? "PASS" : "FAIL"): \(message)")
    if !condition { renderCheckExitCode = 1 }
}

/// Raw RGBA pixel access over a decoded PNG (fast pointer path, colorAt fallback).
private struct PixelGrid {
    let rep: NSBitmapImageRep
    let w: Int
    let h: Int

    init?(data: Data) {
        guard let rep = NSBitmapImageRep(data: data) else { return nil }
        self.rep = rep
        self.w = rep.pixelsWide
        self.h = rep.pixelsHigh
    }

    func rgba(_ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        if x < 0 || y < 0 || x >= w || y >= h { return (0, 0, 0, 0) }
        if rep.bitsPerSample == 8, rep.bitsPerPixel == 32, let base = rep.bitmapData {
            let row = base + y * rep.bytesPerRow
            let px = row + x * 4
            // PNG-decoded reps are RGBA in memory on macOS; fall through to
            // colorAt below if this ever disagrees (verified against colorAt
            // in a spot check during development).
            let order = rep.bitmapFormat
            let alphaFirst = order.contains(.alphaFirst)
            let r = alphaFirst ? px[3] : px[0]
            let g = alphaFirst ? px[2] : px[1]
            let b = alphaFirst ? px[1] : px[2]
            let a = alphaFirst ? px[0] : px[3]
            return (r, g, b, a)
        }
        guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return (0, 0, 0, 0) }
        return (UInt8(c.redComponent * 255), UInt8(c.greenComponent * 255),
                UInt8(c.blueComponent * 255), UInt8(c.alphaComponent * 255))
    }
}

@MainActor
enum SubWheelRenderCheck {
    static var designDir: URL!

    static var pngURL: URL { designDir.appendingPathComponent("render_check_subwheel.png") }

    // The slot plan mirrors what RingSummoner.summonLauncher would feed the view
    // for a machine configured as: slot 0 = System whole-plugin widened to 8
    // children (5 real System ops + appearance toggle + screenshot snip + one
    // unknown-op placeholder — a stale slot action the app renders as
    // "circle.dashed"), slot 1 = Appearance whole-plugin (DISABLED plugin: the
    // dim blade under checklist item 3), slot 2/3 = colorful stock apps (healthy
    // saturated neighbors), slots 4/5 empty ("+" glyphs).
    static let bladeSymbols: [(symbol: String, label: String)] = [
        ("lock.fill", "Lock Screen"),              // SystemAction.lockScreen
        ("display", "Sleep Displays"),             // SystemAction.sleepDisplays
        ("moon.zzz", "Sleep"),                     // SystemAction.sleep
        ("square.grid.3x3", "Mission Control"),    // SystemAction.missionControl
        ("doc.text.viewfinder", "OCR"),            // SystemAction.ocr
        ("circle.lefthalf.filled", "Toggle Appearance"), // AppearancePlugin op
        ("camera.viewfinder", "Snip to Clipboard"),      // ScreenshotPlugin op
        ("circle.dashed", "system/unknown-op"),    // missing-op placeholder
    ]

    static func run() {
        let canvas = (max(RingTheme.outerRadius, RingTheme.subBandOuter)
            + RingTheme.subPopOffset + RingTheme.shadowPad) * 2   // 428 pt
        let scale: CGFloat = 2
        let center = CGPoint(x: canvas / 2, y: canvas / 2)

        // ---- Inputs (icon arrays + dim snapshot), mirroring the summoner ----
        let icons: [NSImage?] = [
            SymbolPlate.image(symbolName: "gearshape.2", label: "System"),   // blade 0: System plugin
            SymbolPlate.image(symbolName: "circle.lefthalf.filled", label: "Appearance"), // blade 1: dimmed
            NSWorkspace.shared.icon(forFile: "/System/Applications/Calendar.app"),
            NSWorkspace.shared.icon(forFile: "/System/Applications/Notes.app"),
            nil, nil,
        ]
        let subicons: [[NSImage?]] = [
            bladeSymbols.map { SymbolPlate.image(symbolName: $0.symbol, label: $0.label) },
            [SymbolPlate.image(symbolName: "circle.lefthalf.filled", label: "Toggle Appearance")],
            [], [], [], [],
        ]
        // RingSummoner.summonLauncher's snapshot rule over a FRESH defaults
        // suite: system isEnabledByDefault = true, appearance = false (opt-in).
        let dimmed = [false, true, false, false, false, false]

        // ---- Drive the real dwell state machine to the open sub-wheel ----
        let vm = RingViewModel()
        let clock = Date(timeIntervalSince1970: 1_000)
        vm.now = { clock }
        vm.begin(centerGlobal: CGPoint(x: 1000, y: 1000),
                 wedgeCount: SliceConfig.wedgeCount,
                 childrenCounts: subicons.map(\.count),
                 input: .vector(deadZone: 36) { .zero })  // timer can't touch the offline render
        // Pointer 70 pt above the (fabricated) ring center: blade 0's wedge.
        let dwellPoint = CGPoint(x: 1000, y: 1070)
        vm.updatePointer(at: dwellPoint, now: clock)                              // dwell anchor
        vm.updatePointer(at: dwellPoint, now: clock.addingTimeInterval(0.26))     // past subDwellDuration
        check(vm.openSubIndex == 0, "dwell opened the sub-wheel (openSubIndex == 0)")
        check(vm.highlightedIndex == 0, "parent blade stays highlighted while its wheel is open")
        check(vm.isCancelling == false && vm.hoveredSubIndex == nil, "steady state: not cancelling, no sub hovered")

        // ---- Code-level geometry facts (constants + hit/render agreement) ----
        let layout = BladeLayout.forCount(SliceConfig.wedgeCount)
        let gapStart = layout.start + layout.span          // first free angle clockwise
        let gapEnd = layout.start + 360                    // blade 0's leading edge
        check(RingTheme.subPitchDegrees == 15, "RingTheme.subPitchDegrees == 15")
        check(SlotEntry.maxPluginChildren == 8, "SlotEntry.maxPluginChildren == 8")
        check(layout.pitch == 30 && layout.span == 180,
              "6-blade layout: pitch \(layout.pitch)°, span \(layout.span)°, wrap gap [\(Int(gapStart))°, \(Int(gapEnd))°) i.e. upper-left half")
        check(abs(layout.centerAngle(0)) < 0.0001, "blade 0 centered on 12 o'clock (sub grid starts at 0°)")
        var centersOnGrid = true
        var hitMatchesRender = true
        var gapUnreachable = true
        let midSub = (RingTheme.subBandInner + RingTheme.subBandOuter) / 2
        for j in 0..<SlotEntry.maxPluginChildren {
            // RingView.subBladeView's own formula: parent slot angle + j * sub pitch.
            let expected = layout.centerAngle(0) + Double(j) * RingTheme.subPitchDegrees
            let theta = expected * .pi / 180
            // Every sub center must sit on the 15° grid inside the occupied fan.
            centersOnGrid = centersOnGrid
                && abs(expected.truncatingRemainder(dividingBy: RingTheme.subPitchDegrees)) < 0.0001
                && expected < gapStart
            // The sub-blade's own slot hit through RingGeometry. Note the
            // convention: RingGeometry works in y-UP points (atan2(dx, dy)),
            // while the render canvas is y-down — so hit-test probes use +cos,
            // pixel probes use −cos (same angle, same radius).
            let p = CGPoint(x: center.x + midSub * sin(theta), y: center.y + midSub * cos(theta))
            let angle = RingGeometry.angle(from: center, to: p)
            hitMatchesRender = hitMatchesRender
                && RingGeometry.subIndex(parent: 0, angle: angle, distance: midSub,
                                         layout: layout, childCount: 8,
                                         innerRadius: RingTheme.outerRadius,
                                         outerRadius: RingTheme.subBandOuter) == j
        }
        for gapAngle in [200.0, 250.0, 300.0, 340.0] {
            let p = point(angle: gapAngle, radius: RingTheme.midRadius, center: center)
            let yUp = CGPoint(x: p.x, y: 2 * center.y - p.y)   // canvas y-down → geometry y-up
            gapUnreachable = gapUnreachable
                && RingGeometry.subIndex(parent: 0, angle: gapAngle, distance: midSub,
                                         layout: layout, childCount: 8,
                                         innerRadius: RingTheme.outerRadius,
                                         outerRadius: RingTheme.subBandOuter) == nil
                && RingGeometry.wedgeIndex(from: center, to: yUp,
                                           layout: layout, deadZoneRadius: 36) == nil
        }
        check(centersOnGrid, "all 8 sub centers sit on the 15° grid clockwise of the parent")
        check(hitMatchesRender, "RingGeometry.subIndex maps each rendered sub center back to its own slot")
        check(gapUnreachable, "wrap-gap angles select nothing (no sub, no blade)")
        let subHalf = (RingTheme.subPitchDegrees + min(RingTheme.bladeOverlapDegrees, RingTheme.subPitchDegrees * 0.45)) / 2
        let lastTrailing = 7.0 * RingTheme.subPitchDegrees + subHalf
        check(lastTrailing < gapStart - 30,
              "8th sub trailing edge \(String(format: "%.1f", lastTrailing))° clears the wrap gap start \(Int(gapStart))° by > 30° (lean headroom)")
        check(midSub > RingTheme.outerRadius && RingTheme.subBandInner < RingTheme.outerRadius,
              "sub band [\(Int(RingTheme.subBandInner)), \(Int(RingTheme.subBandOuter))] rides outside the blade rim (\(Int(RingTheme.outerRadius))), tucked 8 pt under it")

        // ---- The view: pre-dealt blades + open sub-wheel, dark scheme ----
        let ringView = RingView(icons: icons, viewModel: vm, subicons: subicons,
                                dimmed: dimmed, preAppeared: true)
        let content = ZStack {
            // Dark wallpaper stand-in, chosen a few levels BELOW the dark
            // palette's charcoal card stock so the cards still clear the ink
            // threshold in the pixel analysis (the very-dark-background case
            // the spec says must be histogram-verified, not eyeballed).
            Color(red: 0.063, green: 0.071, blue: 0.078)
            ringView
        }
        .environment(\.ringCenter, center)
        .environment(\.colorScheme, .dark)
        .frame(width: canvas, height: canvas)

        func snapshotPNG() -> Data? {
            let renderer = ImageRenderer(content: content)
            renderer.scale = scale
            renderer.proposedSize = ProposedViewSize(width: canvas, height: canvas)
            guard let nsImage = renderer.nsImage,
                  let tiff = nsImage.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff) else { return nil }
            return rep.representation(using: .png, properties: [:])
        }

        // First snapshot right away (an early crash still leaves the PNG on disk).
        guard let png1 = snapshotPNG() else {
            fail("ImageRenderer produced no image")
            finish()
            return
        }
        try? png1.write(to: pngURL)

        // Project convention: let the runloop spin, then re-render and confirm
        // the frame is stable (animations settled, layout complete) before the
        // pixel analysis reads the file back.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            MainActor.assumeIsolated {
                let png2 = snapshotPNG() ?? png1
                print("[STAT] frame stable across runloop spins: \(png1 == png2)")
                try? png2.write(to: self.pngURL)   // final artifact on disk
                self.analyze(pngData: png2, canvas: canvas, scale: scale, center: center,
                             layout: layout, midSub: midSub, gapStart: gapStart)
                self.finish()
            }
        }
    }

    private static func finish() {
        NSApp.terminate(nil)
    }

    private static func point(angle: Double, radius: CGFloat, center: CGPoint) -> CGPoint {
        let t = angle * .pi / 180
        return CGPoint(x: center.x + radius * sin(t), y: center.y - radius * cos(t))
    }

    // ---- Pixel analysis: reads the WRITTEN PNG back, not the in-memory view ----
    private static func analyze(pngData: Data, canvas: CGFloat, scale: CGFloat,
                                center: CGPoint, layout: BladeLayout, midSub: CGFloat, gapStart: Double) {
        guard let grid = PixelGrid(data: pngData) else {
            fail("could not decode the written PNG for pixel analysis")
            return
        }
        let bg = grid.rgba(4, 4)
        func ink(_ x: Int, _ y: Int) -> Bool {
            let p = grid.rgba(x, y)
            return max(abs(Int(p.r) - Int(bg.r)), abs(Int(p.g) - Int(bg.g)),
                       abs(Int(p.b) - Int(bg.b))) > 12
        }

        // Item 4a — histogram: the image is not blank.
        var inkCount = 0
        for y in 0..<grid.h {
            for x in 0..<grid.w where ink(x, y) { inkCount += 1 }
        }
        let total = grid.w * grid.h
        let inkRatio = Double(inkCount) / Double(total)
        print("[STAT] png \(grid.w)x\(grid.h), ink pixels \(inkCount)/\(total) (\(String(format: "%.1f%%", inkRatio * 100))) vs background \(bg)")

        // Item 1 — ink at every sub center on the band, band only where subs are.
        // The icon probe is a DISK (r=28 px): sub 7's icon is the "circle.dashed"
        // missing-op placeholder — a hollow dashed ring whose center is empty, so
        // a tiny center-window probe would land in the hole. The disk still
        // proves the icon itself is drawn; the wedge probe below proves the card.
        var subCentersInked: [Int] = []
        var subCardsInked: [Int] = []
        for j in 0..<SlotEntry.maxPluginChildren {
            let angle = layout.centerAngle(0) + Double(j) * RingTheme.subPitchDegrees
            let p = point(angle: angle, radius: midSub, center: center)
            let px = Int(p.x * scale), py = Int(p.y * scale)
            let iconInked = (-28...28).contains { dx in
                (-28...28).contains { dy in
                    dx * dx + dy * dy <= 28 * 28 && ink(px + dx, py + dy)
                }
            }
            if iconInked { subCentersInked.append(j) }
            // Card presence: any ink anywhere in sub j's 15° slot across the band.
            var cardInked = false
            scan: for a in stride(from: angle - 6.5, through: angle + 6.5, by: 1.5) {
                for r in stride(from: CGFloat(RingTheme.subBandInner + 4), through: RingTheme.subBandOuter - 4, by: 6) {
                    let q = point(angle: a, radius: r, center: center)
                    if ink(Int(q.x * scale), Int(q.y * scale)) { cardInked = true; break scan }
                }
            }
            if cardInked { subCardsInked.append(j) }
        }
        var strayInkAngles: [Int] = []
        // Probe from just past the dealt span's trailing edge (~121° with lean
        // swing) around through the wrap gap to blade 0's leading edge (345°).
        for angle in stride(from: 130, to: 345, by: 3) {
            let p = point(angle: Double(angle), radius: midSub, center: center)
            let px = Int(p.x * scale), py = Int(p.y * scale)
            if (-4...4).contains(where: { dx in (-4...4).contains { dy in ink(px + dx, py + dy) } }) {
                strayInkAngles.append(angle)
            }
        }
        print("[STAT] sub band @r=\(Int(midSub))pt: icon ink at sub centers \(subCentersInked); card ink in slots \(subCardsInked); stray ink angles past dealt span \(strayInkAngles)")

        // Item 2 — the wrap gap is empty in the BLADE band too.
        var bladeGapClean = true
        for angle in [200, 270, 340] {
            let p = point(angle: Double(angle), radius: RingTheme.midRadius, center: center)
            let px = Int(p.x * scale), py = Int(p.y * scale)
            let clean = !(-6...6).contains { dx in (-6...6).contains { dy in ink(px + dx, py + dy) } }
            bladeGapClean = bladeGapClean && clean
            if !clean { print("[STAT] blade-band ink found in wrap gap at \(angle)°") }
        }

        // Item 3/4b — dim blade vs healthy neighbor patch stats (saturation/brightness).
        func patchStats(angleDeg: Double) -> (sat: Double, bri: Double, inkRatio: Double) {
            let p = point(angle: angleDeg, radius: RingTheme.midRadius, center: center)
            let px = Int(p.x * scale), py = Int(p.y * scale), r = Int(24 * scale)
            var s = 0.0, b = 0.0, n = 0, inked = 0
            for dy in -r...r {
                for dx in -r...r where dx * dx + dy * dy <= r * r {
                    let c = grid.rgba(px + dx, py + dy)
                    let rf = Double(c.r) / 255, gf = Double(c.g) / 255, bf = Double(c.b) / 255
                    let mx = max(rf, gf, bf), mn = min(rf, gf, bf)
                    s += mx == 0 ? 0 : (mx - mn) / mx
                    b += mx
                    n += 1
                    if ink(px + dx, py + dy) { inked += 1 }
                }
            }
            return (s / Double(n), b / Double(n), Double(inked) / Double(n))
        }
        let dim = patchStats(angleDeg: layout.centerAngle(1))     // blade 1: disabled Appearance plugin
        let normal = patchStats(angleDeg: layout.centerAngle(2))  // blade 2: Calendar app icon
        print("[STAT] dim blade patch:   meanSat \(String(format: "%.3f", dim.sat)), meanBri \(String(format: "%.3f", dim.bri)), ink \(String(format: "%.0f%%", dim.inkRatio * 100))")
        print("[STAT] normal blade patch: meanSat \(String(format: "%.3f", normal.sat)), meanBri \(String(format: "%.3f", normal.bri)), ink \(String(format: "%.0f%%", normal.inkRatio * 100))")

        // ---- Checklist verdicts (pixel side; the script's caller adds the eyeball pass) ----
        verdict(subCentersInked.count == 8 && subCardsInked.count == 8 && strayInkAngles.isEmpty,
                "1. sub-wheel: icon+card ink at all 8 sub slots on the 15° grid, nothing past the dealt span")
        verdict(bladeGapClean && strayInkAngles.isEmpty,
                "2. wrap gap empty: no ink at gap angles in blade band or sub band")
        verdict(dim.sat < normal.sat * 0.5 && dim.bri < normal.bri,
                "3. dim blade desaturated/darker than healthy neighbor (sat \(String(format: "%.3f", dim.sat)) vs \(String(format: "%.3f", normal.sat)), bri \(String(format: "%.3f", dim.bri)) vs \(String(format: "%.3f", normal.bri)))")
        verdict(inkRatio > 0.10 && (dim.sat != normal.sat || dim.bri != normal.bri),
                "4. histogram non-blank (\(String(format: "%.1f%%", inkRatio * 100)) ink) and dim region distinguishable from neighbor")

        print(renderCheckExitCode == 0 ? "SUMMARY: all pixel checks PASS" : "SUMMARY: FAILURES PRESENT")
    }
}

// MARK: - App lifecycle (project convention: keep the runloop alive)

private final class RenderCheckDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            SubWheelRenderCheck.run()
        }
    }
}

#endif // RENDER_HARNESS

// MARK: - Bootstrap

enum RenderCheckBootstrap {
    /// The app sources compiled verbatim alongside the script's temp main.swift copy.
    static let appSources = [
        "NemoLoop/Ring/RingView.swift",
        "NemoLoop/Ring/RingTheme.swift",
        "NemoLoop/Ring/RingGeometry.swift",
        "NemoLoop/Ring/RingViewModel.swift",
        "NemoLoop/Model/SliceConfig.swift",
        "NemoLoop/Model/SlotAction.swift",
    ]

    /// `swift script.swift` invocation: build the multi-file program and run it.
    static func buildAndRun() -> Int32 {
        let scriptPath = #filePath
        let designDir = URL(fileURLWithPath: scriptPath).deletingLastPathComponent()
        let root = designDir.deletingLastPathComponent()
        let buildDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nemo-render-check-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)
            // swiftc requires the top-level-code file to be named main.swift.
            try FileManager.default.copyItem(at: URL(fileURLWithPath: scriptPath),
                                             to: buildDir.appendingPathComponent("main.swift"))
        } catch {
            print("render-check bootstrap: \(error)")
            return 1
        }
        let bin = buildDir.appendingPathComponent("render_check_harness")
        let compile = Process()
        compile.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compile.arguments = ["swiftc", "-D", "RENDER_HARNESS", "-o", bin.path,
                             buildDir.appendingPathComponent("main.swift").path]
            + appSources.map { root.appendingPathComponent($0).path }
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
        run.standardOutput = FileHandle.standardOutput
        run.standardError = FileHandle.standardError
        do { try run.run() } catch { print("render-check bootstrap: \(error)"); return 1 }
        run.waitUntilExit()
        try? FileManager.default.removeItem(at: buildDir)
        return run.terminationStatus
    }
}

// MARK: - Entry

#if RENDER_HARNESS
// We are the compiled binary built by the bootstrap above.
if CommandLine.arguments.contains("--render-harness") {
    guard CommandLine.arguments.count > 2 else {
        print("render-check: missing design dir argument")
        exit(2)
    }
    MainActor.assumeIsolated {
        SubWheelRenderCheck.designDir = URL(fileURLWithPath: CommandLine.arguments[2])
        let app = NSApplication.shared
        let delegate = RenderCheckDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.prohibited)
        app.run()
        exit(renderCheckExitCode)
    }
    exit(renderCheckExitCode)   // unreachable; satisfies nonisolated flow
} else {
    // Defensive: the binary should always be launched with the flag.
    exit(RenderCheckBootstrap.buildAndRun())
}
#else
// Interpreted invocation (`swift Design/render_check_plugin_subwheel.swift`):
// bootstrap the compiled harness and mirror its exit code.
exit(RenderCheckBootstrap.buildAndRun())
#endif
