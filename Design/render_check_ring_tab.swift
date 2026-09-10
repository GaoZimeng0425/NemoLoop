// Design/render_check_ring_tab.swift
//
// Task 7 render-check harness: verifies the Ring tab's full page against the
// six-point checklist from the Loop-style Ring tab spec:
//   1. Mini-ring blade count == configured slot count (SliceConfig.wedgeCount),
//      icon band on the OUTER ring (outside the hole, inside the rim).
//   2. Wrap gap empty (nothing renders just counterclockwise of blade 0).
//   3. The disconnected plugin's blade is distinguishable from a healthy
//      neighbor (saturation + brightness patch stats over the icon).
//   4. Sub-wheel open frame exists: the thin outer card band, all 8 subs, and
//      nothing past the dealt span.
//   5. Picker sections complete: APPS / PLUGINS / FOLDERS visible and the
//      whole-plugin rows carry the trailing link glyph.
//   6. Pixel histograms non-empty (nothing rendered blank).
//
// RUN (from the worktree root, exactly as the task brief specifies):
//
//     swift Design/render_check_ring_tab.swift
//
// HOW IT BUILDS: same self-bootstrap as Design/render_check_plugin_subwheel.swift
// (T9): `swift script.swift` cannot compile extra files or `import NemoLoop`, so
// with no `--render-harness` flag the script copies itself to a temp main.swift,
// compiles that copy together with the real app sources below via
// `xcrun swiftc -D RENDER_HARNESS`, runs the binary, and mirrors its exit code.
//
// App sources compiled VERBATIM (19 files — the real Ring tab render path, the
// real store, and the real picker data model):
//     NemoLoop/Settings/RingTabInspector.swift   (the view under test)
//     NemoLoop/Ring/{RingView,RingTheme,RingGeometry,RingViewModel,RingSnapshot}.swift
//     NemoLoop/Model/{SliceStore,SliceConfig,SlotAction,PluginModels}.swift
//     NemoLoop/Services/{PluginRegistry,ActionResolver,AppScanner,ActionPickerModel,ShellRunner}.swift
//     NemoLoop/Plugins/{SystemPlugin,AppearancePlugin}.swift
//     NemoLoop/Helpers/SymbolPlate.swift
//
// MIRRORED SEAMS (why the net is still smaller than the app): compiling
// SliceStore pulls PluginRegistry.shared, whose plugin list contains
// ScreenshotPlugin -> OcrSessionController -> OcrResultPanel, and SystemPlugin
// -> SystemAction.perform -> OcrSessionController — and OcrResultPanel.swift
// imports Luminare, a Swift package no plain swiftc invocation can link. So
// exactly four tiny seams are mirrored here instead (each marked verbatim
// below, each irrelevant to pixels — perform() is never invoked by a render):
//     - SystemAction.perform (SystemActions.swift, with the one .ocr case
//       no-op'd; lock/sleep/Mission-Control paths copied verbatim)
//     - ScreenshotPlugin (ScreenshotPlugin.swift with Op.perform no-op'd;
//       id/displayName/symbolName/op list verbatim)
//     - ringCenter environment key (RingWindowController.swift, verbatim)
//     - ChainPlugin (ChainPlugin.swift with fixture-fixed ops and perform
//       no-op'd; metadata verbatim)
//
// PICKER FALLBACK (per the brief): ActionPickerPopover imports Luminare
// (LuminareTextField), so the popover chrome cannot be compiled by pure swiftc.
// Panel C therefore renders an equivalent pure-SwiftUI list built from the REAL
// `ActionPickerModel.sections(...)` output over the REAL `PluginRegistry.shared`
// — the DATA (section titles, row titles/subtitles/symbols, link-glyph rows,
// connected-only filter, footnote) is the app's own; only the chrome (search
// field style, no ScrollView, natural height so every section is visible at
// once) is approximated, and this limitation is documented here and in the
// report. The row view is ActionPickerPopover.PickerRow verbatim plus one probe
// gate (`showLink`, below).
//
// REGISTRY DETERMINISM: RingSnapshot dims a blade via PluginRegistry.shared,
// which reads UserDefaults.standard (tri-state: key present wins). The
// bootstrap therefore launches the binary with UserDefaults ARGUMENT-domain
// pairs that pin all four plugins explicitly — they override any real persisted
// keys, mutate nothing on disk, and make the dim state deterministic:
//     -nemoloop.plugin.system.enabled YES
//     -nemoloop.plugin.appearance.enabled NO   <- the dim blade (slot 1)
//     -nemoloop.plugin.screenshot.enabled YES
//     -nemoloop.plugin.chain.enabled YES   <- 4th plugin, seam-mirrored, ON
// The store itself lives in a throwaway UUID defaults suite, removed at exit.
//
// PANELS (one output PNG, side by side, each also analyzed on its own pixels):
//     A. The REAL RingTabInspector view, idle: 240x240 frame, the 0.561
//        fit-scale (240/428) ring inside, all 6 blades, slot 1 dim, 2 empty
//        "+" slots. Static render: the inspector's own @State view model is
//        never begun offline (onAppear/.task never fire under ImageRenderer),
//        which is exactly its fresh-idle state.
//     B. The dwell-driven open sub-wheel. The inspector's view model is a
//        private @State, so it cannot be driven offline through the view; this
//        panel replicates RingTabInspector.body's exact composition (verbatim
//        parameters: preAppeared, ringCenter = frame midpoint, 240x240 frame,
//        scaleEffect(240 / RingView.frameRadius*2)) around a view model driven
//        the way the inspector's preview loop drives it for a selected slot:
//        begin (isSettingsPreview, zero-vector input) + sustained
//        updatePointer(bladePoint(0)) past subDwellDuration — same driving as
//        RingSubWheelTests.dwellOpensTheWheel and T9.
//     C. The picker fallback list described above (300pt wide, natural height).
//
// OUTPUT: Design/render_check_ring_tab.png (2x scale; dark scheme over a dark
// wallpaper stand-in, the "very dark background" case the spec says must be
// pixel-verified). One [CHECK]/[STAT]/[VERDICT] line per assertion; non-zero
// exit on any failure. The caller additionally eyeballs the PNG (Read).

import AppKit
import SwiftUI

// MARK: - Verbatim copy from NemoLoop/Ring/RingWindowController.swift

/// The environment key itself is private there; only the EnvironmentValues
/// extension is visible to RingView/RingTabInspector. Copied so both compile
/// unmodified outside the app module.
private struct RingCenterKey: EnvironmentKey {
    static let defaultValue: CGPoint = .zero
}
extension EnvironmentValues {
    var ringCenter: CGPoint {
        get { self[RingCenterKey.self] }
        set { self[RingCenterKey.self] = newValue }
    }
}

// MARK: - Harness (only in the multi-file program the bootstrap builds)

#if RENDER_HARNESS

/// Verbatim from NemoLoop/Services/SystemActions.swift, EXCEPT the `.ocr` case:
/// it routes to OcrSessionController, whose file graph reaches Luminare (see
/// header). Renders never perform actions; the case logs instead. Everything
/// else — dlopen'd SACLockScreenImmediate, pmset, synthetic Mission Control
/// keystroke — is copied verbatim so this mirror can never drift in spirit.
extension SystemAction {
    func perform() {
        switch self {
        case .lockScreen: Self.lockScreenImmediate()
        case .sleepDisplays: Self.runTool("/usr/bin/pmset", ["displaysleepnow"])
        case .sleep: Self.runTool("/usr/bin/pmset", ["sleepnow"])
        case .missionControl: Self.postControlUpArrow()
        case .ocr: NSLog("NemoLoop render harness: OCR perform skipped (OCR stack not linked)")
        }
    }

    private static func lockScreenImmediate() {
        let frameNames = [
            "/System/Library/PrivateFrameworks/ScreenSaver.framework/ScreenSaver",
            "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices",
        ]
        for path in frameNames {
            guard let handle = dlopen(path, RTLD_LAZY) else { continue }
            if let symbol = dlsym(handle, "SACLockScreenImmediate") {
                typealias LockFn = @convention(c) () -> Void
                unsafeBitCast(symbol, to: LockFn.self)()
                return
            }
        }
        NSLog("NemoLoop: SACLockScreenImmediate unavailable — lock screen action dropped")
    }

    private static func runTool(_ path: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(filePath: path)
        process.arguments = arguments
        try? process.run()
    }

    private static func postControlUpArrow() {
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 126, keyDown: keyDown)
            event?.flags = .maskControl
            event?.post(tap: .cghidEventTap)
        }
    }
}

/// Verbatim from NemoLoop/Plugins/ScreenshotPlugin.swift, EXCEPT Op.perform:
/// it calls OcrSessionController (whose file graph reaches Luminare — see
/// header). Never invoked by a render; metadata and op list are verbatim so
/// the registry, the picker model and the icon resolver see the real plugin.
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
        func perform() { NSLog("NemoLoop render harness: snip perform skipped (OCR stack not linked)") }
    }

    var operations: [any PluginOp] { [Op()] }
    var status: PluginStatus { .ready }
}

/// Verbatim from NemoLoop/Plugins/Chain/ChainPlugin.swift, EXCEPT: ops are
/// fixture-fixed (the real plugin derives them from ChainStore — irrelevant
/// to pixels) and perform is a no-op. Metadata is verbatim so the picker
/// model sees the real plugin shape. Pinned ENABLED since the chain fixture
/// task — the fixture op yields the third whole-plugin picker row.
@MainActor
final class ChainPlugin: @MainActor NemoPlugin {
    static let pluginID = "chain"
    let id = ChainPlugin.pluginID
    let displayName = "Chains"
    let symbolName = "link"
    let summary = "Run several actions in one trigger — with repeat and inter-step delay."

    struct Op: @MainActor PluginOp {
        let id = "demo-chain-op"
        let displayName = "Wrap Up (fixture)"
        let symbolName = "link"
        func perform() { NSLog("NemoLoop render harness: chain perform skipped") }
    }

    var operations: [any PluginOp] { [Op()] }
    var status: PluginStatus { .ready }
}

/// Panel C chrome: ActionPickerPopover's section list rebuilt in pure SwiftUI.
/// Structure (VStack/ForEach/section header style/footnote) mirrors
/// ActionPickerPopover.body verbatim; the ScrollView+LazyVStack becomes a
/// plain VStack at natural height (documented deviation so FOLDERS is pixel-
/// visible in one frame), and LuminareTextField becomes a rounded TextField.
private struct FallbackPickerList: View {
    let sections: [PickerSection]
    let footnote: String
    /// Probe gate: while true, the section-header and link-glyph views render
    /// `.hidden()` — same frames, no ink — so a per-pixel diff against the
    /// normal render isolates exactly that ink (see analyzePickerProbes).
    var hideProbeInk = false

    var body: some View {
        VStack(spacing: 8) {
            TextField("Search", text: .constant(""))
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 10)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(sections, id: \.title) { section in
                    VStack(alignment: .leading, spacing: 4) {
                        header(section.title)
                        ForEach(section.items) { item in
                            FallbackRow(item: item, showLink: !hideProbeInk) {}
                        }
                    }
                }
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
        }
        .padding(.vertical, 10)
        .frame(width: 300)
    }

    @ViewBuilder
    private func header(_ title: String) -> some View {
        if hideProbeInk {
            Text(title.uppercased()).font(.caption).foregroundStyle(.secondary).hidden()
        } else {
            Text(title.uppercased()).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// ActionPickerPopover.PickerRow VERBATIM, plus the `showLink` probe gate (the
/// only delta; with showLink true the pixels are PickerRow's own).
private struct FallbackRow: View {
    let item: PickerItem
    var showLink = true
    let onChoose: () -> Void

    var body: some View {
        Button(action: onChoose) {
            HStack(spacing: 8) {
                if case .app(let entry) = item.kind {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                        .resizable()
                        .frame(width: 20, height: 20)
                } else if let symbol = item.symbolName {
                    Image(systemName: symbol)
                        .frame(width: 20)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if case .wholePlugin = item.kind {
                    if showLink {
                        Image(systemName: "link")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else {
                        Image(systemName: "link")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .hidden()
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Check plumbing (T9 pattern)

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

@MainActor
private func stat(_ message: String) {
    print("[STAT] \(message)")
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

// MARK: - The render check

@MainActor
enum RingTabRenderCheck {
    static var designDir: URL!
    static var pngURL: URL { designDir.appendingPathComponent("render_check_ring_tab.png") }

    /// Panel A/B frame side (RingTabInspector.side) and RingView's canvas side.
    static let side: CGFloat = 240
    static var canvasSide: CGFloat { RingView.frameRadius * 2 }
    /// The fit-scale under test: 240/428 ~ 0.5607.
    static var fitScale: CGFloat { side / canvasSide }

    /// Dark wallpaper stand-in (same as T9: a few levels below the dark
    /// palette's charcoal card stock so cards still clear the ink threshold).
    static let bg = Color(red: 0.063, green: 0.071, blue: 0.078)

    static func run() {
        // ---- Registry determinism (argument domain pinned by the bootstrap) ----
        check(PluginRegistry.shared.isEnabled("system"),
              "system plugin connected (argument-domain pin) — healthy whole-plugin blade")
        check(!PluginRegistry.shared.isEnabled("appearance"),
              "appearance plugin disconnected (argument-domain pin) — the DIM blade")
        check(PluginRegistry.shared.isEnabled("screenshot"),
              "screenshot plugin connected (argument-domain pin) — second whole-plugin picker row")

        // ---- The store: same slot plan the previous harness used ----
        // slot 0 = System whole-plugin widened to 8 children (5 system ops +
        // appearance toggle + screenshot snip + one unknown-op placeholder),
        // slot 1 = Appearance whole-plugin (DISABLED -> dim blade), slots 2/3 =
        // colorful stock apps, slots 4/5 empty ("+").
        let suiteName = "nemo-render-check-ring-tab-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = SliceStore(defaults: defaults, testingSuiteName: suiteName)
        store.attachWholePlugin("system", at: 0)
        store.addChild(.pluginOp(pluginID: "appearance", opID: "toggleDarkMode"), at: 0)
        store.addChild(.pluginOp(pluginID: "screenshot", opID: "snipToClipboard"), at: 0)
        store.addChild(.pluginOp(pluginID: "system", opID: "unknown-op"), at: 0)
        store.attachWholePlugin("appearance", at: 1)
        store.setAction(.app(URL(fileURLWithPath: "/System/Applications/Calendar.app")), at: 2)
        store.setAction(.app(URL(fileURLWithPath: "/System/Applications/Notes.app")), at: 3)

        let snap = RingSnapshot.make(store: store)
        let layout = BladeLayout.forCount(snap.icons.count)
        check(snap.icons.count == SliceConfig.wedgeCount,
              "snapshot blade count \(snap.icons.count) == SliceConfig.wedgeCount \(SliceConfig.wedgeCount)")
        check(snap.childrenCounts == [8, 1, 0, 0, 0, 0], "children counts \(snap.childrenCounts)")
        check(snap.dimmed == [false, true, false, false, false, false],
              "dimmed flags — exactly the disconnected Appearance blade is dim: \(snap.dimmed)")
        check(snap.icons[4] == nil && snap.icons[5] == nil, "slots 4/5 empty (+ placeholders)")

        // ---- Geometry facts (code side; pixels below confirm the render) ----
        let k = fitScale
        let centerLocal = CGPoint(x: side / 2, y: side / 2)   // (120, 120)
        check(layout.pitch == 30 && layout.span == 180,
              "6-blade layout: pitch \(layout.pitch)°, span \(layout.span)°, wrap gap [165°, 345°) = upper-left half")
        check(abs(k - 0.5607) < 0.001,
              "fit-scale 240/\(Int(canvasSide)) = \(String(format: "%.4f", k)) (the ~0.561 the spec froze)")
        check(RingTheme.subBandOuter * k < side / 2,
              "dealt sub-wheel outer band \(Int(RingTheme.subBandOuter))pt · k = \(String(format: "%.1f", RingTheme.subBandOuter * k))pt < \(Int(side / 2))pt half-frame — scaled ring NOT clipped")
        check(RingTheme.midRadius > RingTheme.innerRadius && RingTheme.midRadius < RingTheme.outerRadius,
              "icon orbit (midRadius \(Int(RingTheme.midRadius))) rides the outer band, above the hole (\(Int(RingTheme.innerRadius))) and inside the rim (\(Int(RingTheme.outerRadius)))")

        // ---- Panel A: the REAL RingTabInspector, idle ----
        var configureCalls: [Int] = []
        let inspector = RingTabInspector(store: store, selectedSlot: .constant(nil)) { slot in
            configureCalls.append(slot)
        }
        let panelA = ZStack { Self.bg; inspector }
            .environment(\.colorScheme, .dark)
            .frame(width: side, height: side)

        // ---- Panel B: dwell-driven open sub-wheel ----
        // RingTabInspector.beginPreview + runPreviewLoop's selectedSlot branch,
        // applied to a view model the harness owns (the inspector's own vm is a
        // private @State that no offline render can drive; see header). The
        // composition below is RingTabInspector.body verbatim.
        let vm = RingViewModel()
        vm.isSettingsPreview = true
        vm.begin(centerGlobal: centerLocal,
                 wedgeCount: snap.icons.count,
                 childrenCounts: snap.childrenCounts,
                 input: .vector(deadZone: vm.deadZoneRadius) { .zero })
        // bladePoint(for: 0) — RingTabInspector's formula verbatim: the slot's
        // center angle at 0.7 x outerRadius, in the vm's y-up ring units.
        let blade0Angle = layout.centerAngle(0) * .pi / 180
        let blade0Point = CGPoint(x: centerLocal.x + sin(blade0Angle) * RingTheme.outerRadius * 0.7,
                                  y: centerLocal.y + cos(blade0Angle) * RingTheme.outerRadius * 0.7)
        let clock = Date(timeIntervalSince1970: 1_000)
        vm.now = { clock }
        vm.updatePointer(at: blade0Point)                                    // dwell anchor
        vm.updatePointer(at: blade0Point, now: clock.addingTimeInterval(0.30)) // past subDwellDuration
        check(vm.openSubIndex == 0 && vm.highlightedIndex == 0 && vm.hoveredSubIndex == nil,
              "dwell opened blade 0's sub-wheel (openSubIndex 0, parent highlighted, no sub hovered)")
        let drivenComposition = RingView(icons: snap.icons, viewModel: vm,
                                         subicons: snap.subicons, dimmed: snap.dimmed,
                                         preAppeared: true)
            .environment(\.ringCenter, centerLocal)
            .frame(width: side, height: side)
            .scaleEffect(k)
        let panelB = ZStack { Self.bg; drivenComposition }
            .environment(\.colorScheme, .dark)
            .frame(width: side, height: side)

        // ---- Panel C: picker fallback over the REAL model ----
        let apps = [
            AppEntry(id: "com.apple.Calendar", name: "Calendar",
                     url: URL(fileURLWithPath: "/System/Applications/Calendar.app")),
            AppEntry(id: "apple.notes", name: "Notes",
                     url: URL(fileURLWithPath: "/System/Applications/Notes.app")),
            AppEntry(id: "com.apple.Music", name: "Music",
                     url: URL(fileURLWithPath: "/System/Applications/Music.app")),
        ]
        let model = ActionPickerModel(apps: apps, registry: .shared)
        let sections = model.sections(context: .mainSlot, query: "")
        check(sections.map(\.title) == ["Apps", "Plugins", "Folders"],
              "real model sections: \(sections.map(\.title)) (appearance excluded — disconnected)")
        let pluginItems = sections.first { $0.title == "Plugins" }?.items ?? []
        let wholeRows = pluginItems.filter { item in
            if case .wholePlugin = item.kind { return true } else { return false }
        }
        check(wholeRows.map(\.title) == ["System", "Screenshot", "Chains"],
              "whole-plugin rows (link-glyph rows): \(wholeRows.map(\.title)) with subtitles \(wholeRows.compactMap(\.subtitle)) (appearance excluded — disconnected)")
        check(pluginItems.count == 10 && sections[0].items.count == 4 && sections[2].items.count == 1,
              "row counts Apps \(sections[0].items.count) (3 apps + Browse), Plugins \(pluginItems.count) (3 whole + 7 ops), Folders \(sections[2].items.count)")
        let chainRowListed = wholeRows.map(\.title) == ["System", "Screenshot", "Chains"]
        check(!model.connectedPluginFootnote.isEmpty, "connected-only footnote present: \"\(model.connectedPluginFootnote)\"")

        let panelC = ZStack {
            Self.bg
            FallbackPickerList(sections: sections, footnote: model.connectedPluginFootnote)
        }
        .environment(\.colorScheme, .dark)
        .frame(width: 300)
        // Probe variant: identical frames, section headers + link glyphs hidden.
        let panelCProbe = ZStack {
            Self.bg
            FallbackPickerList(sections: sections, footnote: model.connectedPluginFootnote,
                               hideProbeInk: true)
        }
        .environment(\.colorScheme, .dark)
        .frame(width: 300)

        // ---- Render ----
        func render(_ content: some View, width: CGFloat, height: CGFloat? = nil) -> Data? {
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            renderer.proposedSize = ProposedViewSize(width: width, height: height)
            guard let nsImage = renderer.nsImage,
                  let tiff = nsImage.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff) else { return nil }
            return rep.representation(using: .png, properties: [:])
        }

        guard let pngA1 = render(panelA, width: side, height: side),
              let pngB1 = render(panelB, width: side, height: side),
              let pngC1 = render(panelC, width: 300),
              let pngCProbe1 = render(panelCProbe, width: 300) else {
            fail("ImageRenderer produced no image for one of the panels")
            finish(defaults: defaults, suiteName: suiteName)
            return
        }
        writeComposite(pngA: pngA1, pngB: pngB1, pngC: pngC1)

        // Project convention: let the runloop spin, then re-render and confirm
        // the frames are stable before the pixel analysis reads them. Byte
        // equality proved too strict (antialiasing/shadow rasterization varies
        // a few pixels between ImageRenderer passes), so stability = the count
        // of differing pixels between passes, reported per panel.
        func pixelDiff(_ a: Data, _ b: Data) -> Int {
            guard let ga = PixelGrid(data: a), let gb = PixelGrid(data: b),
                  ga.w == gb.w, ga.h == gb.h else { return -1 }
            var count = 0
            for y in 0..<ga.h {
                for x in 0..<ga.w {
                    let p = ga.rgba(x, y), q = gb.rgba(x, y)
                    if p.r != q.r || p.g != q.g || p.b != q.b || p.a != q.a { count += 1 }
                }
            }
            return count
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            MainActor.assumeIsolated {
                let pngA2 = render(panelA, width: self.side, height: self.side) ?? pngA1
                let pngB2 = render(panelB, width: self.side, height: self.side) ?? pngB1
                let pngC2 = render(panelC, width: 300) ?? pngC1
                let pngCProbe2 = render(panelCProbe, width: 300) ?? pngCProbe1
                stat("frame drift across runloop spins (differing px of \(Int(self.side * 2))²/\(Int(self.side * 2))² per ring panel): A \(pixelDiff(pngA1, pngA2)), B \(pixelDiff(pngB1, pngB2)), C \(pixelDiff(pngC1, pngC2)), C-probe \(pixelDiff(pngCProbe1, pngCProbe2))")
                self.writeComposite(pngA: pngA2, pngB: pngB2, pngC: pngC2)
                self.analyze(pngA: pngA2, pngB: pngB2, pngC: pngC2, pngCProbe: pngCProbe2,
                             layout: layout, k: k, chainRowsPresent: chainRowListed)
                self.finish(defaults: defaults, suiteName: suiteName)
            }
        }
    }

    private static func finish(defaults: UserDefaults, suiteName: String) {
        defaults.removePersistentDomain(forName: suiteName)
        // Exit DIRECTLY with the verdict code: NSApp.terminate(nil) ends the
        // process with status 0, which would silently swallow every failure
        // (the exit() after app.run() in the entry block is unreachable).
        exit(renderCheckExitCode)
    }

    /// Canvas point for an angle (degrees, from-up, clockwise) at `radius` ring
    /// points: fit-scaled to panel points, y-down like the render.
    private static func panelPoint(angle: Double, radiusRingPt: CGFloat, k: CGFloat) -> (x: CGFloat, y: CGFloat) {
        let t = angle * .pi / 180
        let r = radiusRingPt * k * 2   // ring pt -> panel px (2x render scale)
        return (side + r * sin(t), side - r * cos(t))   // center = (240, 240) px
    }

    /// Compose the three panels side by side with labels into the final PNG.
    private static func writeComposite(pngA: Data, pngB: Data, pngC: Data) {
        let panels: [(String, Data)] = [
            ("A  idle: 6 blades, slot 1 dim", pngA),
            ("B  sub-wheel open (8 subs)", pngB),
            ("C  picker fallback (real model)", pngC),
        ]
        let reps = panels.compactMap { NSBitmapImageRep(data: $0.1) }
        guard reps.count == 3 else { stat("composite skipped (panel decode failed)"); return }
        let pad = 28.0, gap = 28.0, labelH = 40.0
        let width = Int(pad * 2 + Double(reps.reduce(0) { $0 + $1.pixelsWide }) + gap * 2)
        let height = Int(pad + labelH + Double(reps.map(\.pixelsHigh).max() ?? 0) + pad)
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor(red: 0.05, green: 0.055, blue: 0.06, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor(white: 0.82, alpha: 1),
        ]
        var x = pad
        for (label, data) in panels {
            guard let panelImage = NSImage(data: data) else { continue }
            let panelTopY = CGFloat(height) - pad - labelH
            (label as NSString).draw(at: NSPoint(x: x, y: panelTopY + 8), withAttributes: attrs)
            panelImage.draw(in: NSRect(x: x, y: panelTopY - panelImage.size.height,
                                       width: panelImage.size.width, height: panelImage.size.height))
            x += panelImage.size.width + gap
        }
        image.unlockFocus()
        if let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: pngURL)
        }
    }

    // ---- Pixel analysis (reads the rendered PNG bytes, not the live views) ----
    private static func analyze(pngA: Data, pngB: Data, pngC: Data, pngCProbe: Data,
                                layout: BladeLayout, k: CGFloat, chainRowsPresent: Bool) {
        guard let gridA = PixelGrid(data: pngA), let gridB = PixelGrid(data: pngB),
              let gridC = PixelGrid(data: pngC), let gridProbe = PixelGrid(data: pngCProbe) else {
            fail("could not decode rendered panels for pixel analysis")
            return
        }

        // Ink helper per grid: any channel > 12 away from that panel's background.
        func makeInk(_ grid: PixelGrid) -> (Int, Int) -> Bool {
            let bg = grid.rgba(4, 4)
            return { x, y in
                let p = grid.rgba(x, y)
                return max(abs(Int(p.r) - Int(bg.r)), abs(Int(p.g) - Int(bg.g)),
                           abs(Int(p.b) - Int(bg.b))) > 12
            }
        }
        let inkA = makeInk(gridA), inkB = makeInk(gridB)
        func inkRatio(_ grid: PixelGrid, _ ink: (Int, Int) -> Bool) -> Double {
            var count = 0
            for y in 0..<grid.h { for x in 0..<grid.w where ink(x, y) { count += 1 } }
            return Double(count) / Double(grid.w * grid.h)
        }

        // Panel-point radii, ring pt -> px: icon orbit 93, hole 56, rim 130, sub band mid 159.
        let rMidPx: CGFloat = RingTheme.midRadius * k * 2
        let rSubMidPx: CGFloat = (RingTheme.subBandInner + RingTheme.subBandOuter) / 2 * k * 2
        let rRimPx: CGFloat = RingTheme.outerRadius * k * 2

        // Fit-scale containment: the outermost 4px border strips must be
        // ink-free on both ring panels. The scaled canvas nominally fills the
        // frame edge-to-edge, but the DRAWN ring (deepest: the dealt sub band,
        // 196pt -> 219.8px of the 240px half-panel, plus ~11px of scaled
        // shadow) ends ~5px inside the border; any ink in the strips would
        // mean the fit-scale clipped visible content.
        func borderInk(_ grid: PixelGrid, _ ink: (Int, Int) -> Bool) -> Int {
            var n = 0
            for y in 0..<grid.h {
                for x in 0..<grid.w
                where (x < 4 || x >= grid.w - 4 || y < 4 || y >= grid.h - 4) && ink(x, y) {
                    n += 1
                }
            }
            return n
        }
        let borderA = borderInk(gridA, inkA)
        let borderB = borderInk(gridB, inkB)
        stat("border strips (outermost 4px): ink A \(borderA)px, B \(borderB)px — zero proves the fit-scaled ring (incl. shadows) is not clipped by the 240pt frame")

        // ----- Item 1 (panel A): blade count == wedgeCount, icons on the outer band -----
        var bladesInked: [Int] = []
        for i in 0..<SliceConfig.wedgeCount {
            let p = panelPoint(angle: layout.centerAngle(i), radiusRingPt: RingTheme.midRadius, k: k)
            let px = Int(p.x), py = Int(p.y)
            let iconInked = (-12...12).contains { dx in
                (-12...12).contains { dy in dx * dx + dy * dy <= 144 && inkA(px + dx, py + dy) }
            }
            if iconInked { bladesInked.append(i) }
        }
        // Hole empty: a disk at the center well inside the inner radius.
        var holeInk = 0
        let holeR = Int(RingTheme.innerRadius * k * 2 * 0.8)
        for dy in -holeR...holeR {
            for dx in -holeR...holeR where dx * dx + dy * dy <= holeR * holeR {
                if inkA(Int(Self.side) + dx, Int(Self.side) + dy) { holeInk += 1 }
            }
        }
        // Corners clean: the fit-scaled canvas keeps everything inside the frame.
        let cornersClean = [ (6, 6), (gridA.w - 7, 6), (6, gridA.h - 7), (gridA.w - 7, gridA.h - 7) ]
            .allSatisfy { !inkA($0.0, $0.1) }
        let ratioA = inkRatio(gridA, inkA)
        stat("panel A \(gridA.w)x\(gridA.h): ink \(String(format: "%.1f%%", ratioA * 100)); icon ink at blade centers \(bladesInked); hole ink \(holeInk)px; corners clean \(cornersClean)")

        // ----- Item 2 (panels A and B): wrap gap empty in the blade band -----
        // Probe placement note: blades RENDER 6° wider than their slot (the
        // shingle overlap: bladeWidth 30 + overlap 6 = 36°), so blade 0's drawn
        // leading edge sits at 342°, not its 345° slot edge, and blade 5's
        // drawn trailing edge at ~168°. The pixel-empty assertion therefore
        // covers the RENDERED gap interior [175°, 335°]; the wider hit-test gap
        // [165°, 345) is asserted on the code side below (wedgeIndex nil).
        var gapClean = true
        for angle in [200.0, 250.0, 300.0, 330.0] {
            for (grid, ink, name) in [(gridA, inkA, "A"), (gridB, inkB, "B")] {
                let p = panelPoint(angle: angle, radiusRingPt: RingTheme.midRadius, k: k)
                let px = Int(p.x), py = Int(p.y)
                let clean = !(-4...4).contains { dx in (-4...4).contains { dy in ink(px + dx, py + dy) } }
                if !clean {
                    gapClean = false
                    stat("blade-band ink found in wrap gap at \(Int(angle))° (panel \(name), \(grid.w)x\(grid.h))")
                }
            }
        }
        // Code side (same probe set as T9): the gap selects nothing. Geometry
        // only measures point − center, so work in y-up ring units at origin.
        var gapUnreachable = true
        for gapAngle in [170.0, 200.0, 250.0, 300.0, 340.0, 344.0] {
            let t = gapAngle * .pi / 180
            let probe = CGPoint(x: RingTheme.midRadius * sin(t), y: RingTheme.midRadius * cos(t))
            gapUnreachable = gapUnreachable
                && RingGeometry.wedgeIndex(from: .zero, to: probe, layout: layout,
                                           deadZoneRadius: 36) == nil
        }
        check(gapUnreachable, "hit-test wrap gap [165°, 345°) selects no blade at 170/200/250/300/340/344°")

        // ----- Item 3 (panel A): dim blade vs healthy neighbor patch stats -----
        func patchStats(_ grid: PixelGrid, angleDeg: Double) -> (sat: Double, bri: Double) {
            let p = panelPoint(angle: angleDeg, radiusRingPt: RingTheme.midRadius, k: k)
            let px = Int(p.x), py = Int(p.y), r = 18
            var s = 0.0, b = 0.0, n = 0
            for dy in -r...r {
                for dx in -r...r where dx * dx + dy * dy <= r * r {
                    let c = grid.rgba(px + dx, py + dy)
                    let rf = Double(c.r) / 255, gf = Double(c.g) / 255, bf = Double(c.b) / 255
                    let mx = max(rf, gf, bf), mn = min(rf, gf, bf)
                    s += mx == 0 ? 0 : (mx - mn) / mx
                    b += mx
                    n += 1
                }
            }
            return (s / Double(n), b / Double(n))
        }
        let dim = patchStats(gridA, angleDeg: layout.centerAngle(1))     // blade 1: disabled Appearance
        let normal = patchStats(gridA, angleDeg: layout.centerAngle(2))  // blade 2: Calendar app icon
        stat("dim blade patch (slot 1, appearance):   meanSat \(String(format: "%.3f", dim.sat)), meanBri \(String(format: "%.3f", dim.bri))")
        stat("normal blade patch (slot 2, Calendar): meanSat \(String(format: "%.3f", normal.sat)), meanBri \(String(format: "%.3f", normal.bri))")

        // ----- Item 4 (panel B): sub-wheel open — outer band inked, nothing past span -----
        var subsInked: [Int] = []
        for j in 0..<SlotEntry.maxPluginChildren {
            let angle = layout.centerAngle(0) + Double(j) * RingTheme.subPitchDegrees
            let p = panelPoint(angle: angle, radiusRingPt: (RingTheme.subBandInner + RingTheme.subBandOuter) / 2, k: k)
            let px = Int(p.x), py = Int(p.y)
            let inked = (-10...10).contains { dx in
                (-10...10).contains { dy in dx * dx + dy * dy <= 100 && inkB(px + dx, py + dy) }
            }
            if inked { subsInked.append(j) }
        }
        var straySubAngles: [Int] = []
        for angle in stride(from: 130.0, to: 345.0, by: 3) {
            let p = panelPoint(angle: angle, radiusRingPt: (RingTheme.subBandInner + RingTheme.subBandOuter) / 2, k: k)
            let px = Int(p.x), py = Int(p.y)
            if (-5...5).contains(where: { dx in (-5...5).contains { dy in inkB(px + dx, py + dy) } }) {
                straySubAngles.append(Int(angle))
            }
        }
        let ratioB = inkRatio(gridB, inkB)
        stat("panel B \(gridB.w)x\(gridB.h): ink \(String(format: "%.1f%%", ratioB * 100)); sub-band ink at centers \(subsInked) (r=\(Int(rSubMidPx))px, blade rim r=\(Int(rRimPx))px — band OUTSIDE the rim); stray ink past dealt span \(straySubAngles)")

        // ----- Items 5 + link glyph (panel C): sections + probe diff -----
        guard gridC.w == gridProbe.w && gridC.h == gridProbe.h else {
            fail("picker probe render size mismatch: \(gridC.w)x\(gridC.h) vs \(gridProbe.w)x\(gridProbe.h)")
            return
        }
        var headerDiffYs: [Int] = []
        var trailingDiffYs: [Int] = []
        var diffPixels = 0
        for y in 0..<gridC.h {
            for x in 0..<gridC.w {
                let a = gridC.rgba(x, y), b = gridProbe.rgba(x, y)
                let delta = max(abs(Int(a.r) - Int(b.r)), abs(Int(a.g) - Int(b.g)),
                                abs(Int(a.b) - Int(b.b)))
                if delta > 8 {
                    diffPixels += 1
                    if x < gridC.w / 2 { headerDiffYs.append(y) } else { trailingDiffYs.append(y) }
                }
            }
        }
        func bands(_ ys: [Int]) -> [(start: Int, end: Int, count: Int)] {
            guard !ys.isEmpty else { return [] }
            let sorted = ys.sorted()
            var out: [(Int, Int, Int)] = []
            var runStart = sorted[0], prev = sorted[0], count = 1
            for y in sorted.dropFirst() {
                if y - prev > 10 { out.append((runStart, prev, count)); runStart = y; count = 0 }
                prev = y; count += 1
            }
            out.append((runStart, prev, count))
            return out
        }
        let headerBands = bands(headerDiffYs).filter { $0.count >= 20 }
        let trailingBands = bands(trailingDiffYs).filter { $0.count >= 8 }
        let trailingPixels = trailingBands.reduce(0) { $0 + $1.count }
        let inkC = { (x: Int, y: Int) -> Bool in
            let bg = gridC.rgba(4, 4)
            let p = gridC.rgba(x, y)
            return max(abs(Int(p.r) - Int(bg.r)), abs(Int(p.g) - Int(bg.g)),
                       abs(Int(p.b) - Int(bg.b))) > 12
        }
        var ratioC = 0.0
        for y in 0..<gridC.h { for x in 0..<gridC.w where inkC(x, y) { ratioC += 1 } }
        ratioC /= Double(gridC.w * gridC.h)
        stat("panel C \(gridC.w)x\(gridC.h): ink \(String(format: "%.1f%%", ratioC * 100)); probe diff \(diffPixels)px -> header bands \(headerBands.count) at y \(headerBands.map { $0.start }), trailing (link-glyph) bands \(trailingBands.count) at y \(trailingBands.map { $0.start }), \(trailingPixels) link-glyph px")

        // ----- Verdicts -----
        verdict(bladesInked.count == SliceConfig.wedgeCount && holeInk == 0 && cornersClean && borderA == 0,
                "1. mini-ring blade count == wedgeCount: ink at all \(SliceConfig.wedgeCount) blade centers \(bladesInked), hole empty (\(holeInk) px), icons on the outer band (orbit \(Int(rMidPx))px vs hole \(Int(RingTheme.innerRadius * k * 2))px vs rim \(Int(rRimPx))px), border strips clean (\(borderA)px)")
        verdict(gapClean && gapUnreachable,
                "2. wrap gap empty: no blade-band ink at 200/250/300/330° (rendered gap interior) in either panel; hit-test gap [165°, 345°) selects nothing")
        verdict(dim.sat < normal.sat * 0.5 && dim.bri < normal.bri,
                "3. dim blade distinguishable from neighbor: sat \(String(format: "%.3f", dim.sat)) vs \(String(format: "%.3f", normal.sat)), bri \(String(format: "%.3f", dim.bri)) vs \(String(format: "%.3f", normal.bri))")
        verdict(subsInked.count == SlotEntry.maxPluginChildren && straySubAngles.isEmpty && borderB == 0,
                "4. sub-wheel open frame: all \(SlotEntry.maxPluginChildren) sub centers inked on the outer band, nothing past the dealt span, border strips clean (\(borderB)px — sub band fits the frame, not clipped)")
        verdict(sectionsComplete(gridC: gridC, headerBands: headerBands.count,
                                 trailingBands: trailingBands.count, trailingPixels: trailingPixels,
                                 chainRowsPresent: chainRowsPresent),
                "5. picker sections complete: APPS/PLUGINS/FOLDERS headers \(headerBands.count) diff bands, whole-plugin link glyphs \(trailingBands.count) bands/\(trailingPixels)px on trailing edge (code side: titles [Apps, Plugins, Folders], 3 whole rows)")
        verdict(ratioA > 0.05 && ratioB > 0.05 && ratioC > 0.01,
                "6. histograms non-empty: A \(String(format: "%.1f%%", ratioA * 100)), B \(String(format: "%.1f", ratioB * 100)), C \(String(format: "%.1f", ratioC * 100)) ink")

        print(renderCheckExitCode == 0 ? "SUMMARY: all pixel checks PASS" : "SUMMARY: FAILURES PRESENT")
    }

    /// Item 5's code+pixel conjunction (kept readable; numbers printed above).
    private static func sectionsComplete(gridC: PixelGrid, headerBands: Int,
                                         trailingBands: Int, trailingPixels: Int,
                                         chainRowsPresent: Bool) -> Bool {
        headerBands == 3 && trailingBands == 3 && trailingPixels >= 36 && gridC.h > 200 && chainRowsPresent
    }
}

// MARK: - App lifecycle (project convention: keep the runloop alive)

private final class RenderCheckDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            RingTabRenderCheck.run()
        }
    }
}

#endif // RENDER_HARNESS

// MARK: - Bootstrap

enum RenderCheckBootstrap {
    /// The app sources compiled verbatim alongside the script's temp main.swift.
    static let appSources = [
        "NemoLoop/Settings/RingTabInspector.swift",
        "NemoLoop/Ring/RingView.swift",
        "NemoLoop/Ring/RingTheme.swift",
        "NemoLoop/Ring/RingGeometry.swift",
        "NemoLoop/Ring/RingViewModel.swift",
        "NemoLoop/Ring/RingSnapshot.swift",
        "NemoLoop/Model/SliceStore.swift",
        "NemoLoop/Model/SliceConfig.swift",
        "NemoLoop/Model/SlotAction.swift",
        "NemoLoop/Model/PluginModels.swift",
        "NemoLoop/Services/PluginRegistry.swift",
        "NemoLoop/Services/ActionResolver.swift",
        "NemoLoop/Services/AppScanner.swift",
        "NemoLoop/Services/ActionPickerModel.swift",
        "NemoLoop/Services/ShellRunner.swift",
        "NemoLoop/Plugins/SystemPlugin.swift",
        "NemoLoop/Plugins/AppearancePlugin.swift",
        "NemoLoop/Helpers/SymbolPlate.swift",
    ]

    /// UserDefaults argument-domain pins: override whatever the host machine
    /// has persisted for plugin enablement, deterministically and without
    /// writing anything (NSArgumentDomain beats every persisted domain).
    static let registryPins = [
        "-nemoloop.plugin.system.enabled", "YES",
        "-nemoloop.plugin.appearance.enabled", "NO",
        "-nemoloop.plugin.screenshot.enabled", "YES",
        "-nemoloop.plugin.chain.enabled", "YES",
    ]

    /// `swift script.swift` invocation: build the multi-file program and run it.
    static func buildAndRun() -> Int32 {
        let scriptPath = #filePath
        let designDir = URL(fileURLWithPath: scriptPath).deletingLastPathComponent()
        let root = designDir.deletingLastPathComponent()
        let buildDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("nemo-render-check-ring-tab-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)
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
        run.arguments = ["--render-harness", designDir.path] + registryPins
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
// We are the binary built by the bootstrap above.
if CommandLine.arguments.contains("--render-harness") {
    guard CommandLine.arguments.count > 2 else {
        print("render-check: missing design dir argument")
        exit(2)
    }
    MainActor.assumeIsolated {
        RingTabRenderCheck.designDir = URL(fileURLWithPath: CommandLine.arguments[2])
        let app = NSApplication.shared
        let delegate = RenderCheckDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.prohibited)
        app.run()
        exit(renderCheckExitCode)
    }
    exit(renderCheckExitCode)   // unreachable; satisfies nonisolated flow
} else {
    exit(RenderCheckBootstrap.buildAndRun())
}
#else
// Interpreted invocation (`swift Design/render_check_ring_tab.swift`):
// bootstrap the compiled harness and mirror its exit code.
exit(RenderCheckBootstrap.buildAndRun())
#endif
