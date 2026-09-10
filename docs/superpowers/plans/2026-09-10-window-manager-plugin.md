# Windows Plugin Implementation Plan (Flick Port P1)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the Windows plugin — 14 static ops (snap halves/thirds/quadrants, maximize, minimize, toggle fullscreen) over a pure-function geometry layer and an AX service seam, with a settings-card Accessibility grant flow.

**Architecture:** `WindowRegion`/`WindowLayout` computes target frames from a screen's `visibleFrame` (pure, fully unit-tested). `WindowServicing` is the testability seam behind `AccessibilityWindowService` (real AXUIElement calls: focused app → focused window, position/size/minimized/fullscreen attributes). `WindowPlugin` (id `windows`, opt-in, needsAuth until AX trusted) derives 14 ops; region ops pick the screen by window-center and write via the seam. Ring/SlotAction/Launcher untouched.

**Tech Stack:** Swift 6 (strict concurrency, `@MainActor`), SwiftUI + Luminare 0.2.0 (settings chrome), Swift Testing, Xcode 16 file-system-synchronized project.

**Spec:** `docs/superpowers/specs/2026-09-10-window-manager-plugin-design.md` — the plan argues from the spec; executors read both.

## Global Constraints

- Repository: `/Users/gaozimeng/Learn/macOS/NemoLoop`, branch **`feature/window-manager`** (stacked on feature/plugin-config-chains @ ef6ead2). Run everything from the repo root; verify branch with `git branch --show-current`.
- Unit tests MUST use the ad-hoc signing override (dev certificate invalid):
  `xcodebuild test -project NemoLoop.xcodeproj -scheme NemoLoop -destination 'platform=macOS' -only-testing:NemoLoopTests CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual -quiet`
  Single suite: swap the flag for `-only-testing:NemoLoopTests/<SuiteName>`. Suite count before this plan: **164 tests / 32 suites**.
- New files auto-join the target via Xcode 16 synchronized groups — **never edit `project.pbxproj`**.
- Test conventions: Swift Testing (`import Testing`, `@Test`, `#expect`, `@MainActor struct <Subject>Tests`); shared doubles in `NemoLoopTests/PluginTestDoubles.swift` (`StubOp`/`StubPlugin`/`ClosureOp`/`makeDefaults()`).
- Code identifiers/comments in English; commits use `git add <explicit paths>` + conventional messages exactly as each task specifies.
- MUST NOT touch: `SlotAction`, `NemoLoop/Ring/*`, `NemoLoop/Services/Launcher.swift`, any P0 file except `PluginRegistry.swift` (plugin-list line only) and `Design/render_check_ring_tab.swift` (5th seam + assertions). Do NOT touch `NemoLoop/Settings/PluginsTab.swift` (the card already renders `configSections` generically).
- Working tree is CLEAN (the old staged OCR line now lives in `stash@{0}` — leave the stash alone; never `git stash pop`).
- Spec-pinned values (verbatim): plugin id `windows`, displayName `Windows`, plugin symbol `rectangle.split.2x2`, default **disabled** (opt-in); op ids = `WindowRegion` rawValues + `minimize` + `toggleFullscreen`; untrusted trigger = silent + NSLog; icons per spec table; harness: pin `windows YES`, whole rows 3→4, `pluginItems` 10→25.
- TDD: failing test → verify red (compile error counts) → minimal implementation → green → commit. Full suite once before each task's final commit.
- App launch for inspection (T3/T4): `pkill -x NemoLoop` first, ad-hoc build, `open` the Debug product. AX authorization (TCC) is human-only — never attempt to auto-grant.

---

### Task 1: `WindowLayout` — pure geometry

**Files:**
- Create: `NemoLoop/Plugins/Windows/WindowLayout.swift`
- Test: `NemoLoopTests/WindowLayoutTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces (Task 2 builds on these):

```swift
enum WindowRegion: String, CaseIterable, Identifiable {
    case halfLeft, halfRight, halfTop, halfBottom
    case thirdLeft, thirdCenter, thirdRight
    case quadrantTopLeft, quadrantTopRight, quadrantBottomLeft, quadrantBottomRight
    case maximize
    var id: String { rawValue }            // op id space
    var displayName: String                // "Left Half" … "Maximize"
    var symbolName: String                 // SF Symbol per spec table
    func targetFrame(in visibleFrame: CGRect) -> CGRect   // AppKit coords, origin bottom-left
}
```

- [ ] **Step 1: Write the failing tests**

Create `NemoLoopTests/WindowLayoutTests.swift`:

```swift
import Testing
import Foundation
@testable import NemoLoop

@MainActor
struct WindowLayoutTests {
    // AppKit coords: origin bottom-left. Three representative visibleFrames:
    // plain full screen, side-Dock offset (minX>0), bottom-offset variant.
    private let plain = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let sideDock = CGRect(x: 200, y: 0, width: 1240, height: 900)

    @Test func caseCountAndOrderMatchesSpec() {
        #expect(WindowRegion.allCases.count == 12)
        #expect(WindowRegion.allCases.first == .halfLeft)
        #expect(WindowRegion.allCases.last == .maximize)
    }

    @Test func halves() {
        #expect(WindowRegion.halfLeft.targetFrame(in: plain)
                == CGRect(x: 0, y: 0, width: 720, height: 900))
        #expect(WindowRegion.halfRight.targetFrame(in: plain)
                == CGRect(x: 720, y: 0, width: 720, height: 900))
        #expect(WindowRegion.halfTop.targetFrame(in: plain)
                == CGRect(x: 0, y: 450, width: 1440, height: 450))
        #expect(WindowRegion.halfBottom.targetFrame(in: plain)
                == CGRect(x: 0, y: 0, width: 1440, height: 450))
    }

    @Test func thirds() {
        #expect(WindowRegion.thirdLeft.targetFrame(in: plain)
                == CGRect(x: 0, y: 0, width: 480, height: 900))
        #expect(WindowRegion.thirdCenter.targetFrame(in: plain)
                == CGRect(x: 480, y: 0, width: 480, height: 900))
        #expect(WindowRegion.thirdRight.targetFrame(in: plain)
                == CGRect(x: 960, y: 0, width: 480, height: 900))
        // Boundary sanity on the side-Dock offset screen: x-offset shifts thirds,
        // widths still thirds of 1240.
        #expect(WindowRegion.thirdRight.targetFrame(in: sideDock)
                == CGRect(x: 200 + 2 * 1240.0 / 3.0, y: 0, width: 1240.0 / 3.0, height: 900))
    }

    @Test func quadrants() {
        #expect(WindowRegion.quadrantTopLeft.targetFrame(in: plain)
                == CGRect(x: 0, y: 450, width: 720, height: 450))
        #expect(WindowRegion.quadrantTopRight.targetFrame(in: plain)
                == CGRect(x: 720, y: 450, width: 720, height: 450))
        #expect(WindowRegion.quadrantBottomLeft.targetFrame(in: plain)
                == CGRect(x: 0, y: 0, width: 720, height: 450))
        #expect(WindowRegion.quadrantBottomRight.targetFrame(in: plain)
                == CGRect(x: 720, y: 0, width: 720, height: 450))
    }

    @Test func maximizeIsIdentity() {
        #expect(WindowRegion.maximize.targetFrame(in: plain) == plain)
        #expect(WindowRegion.maximize.targetFrame(in: sideDock) == sideDock)
    }

    @Test func sideDockOffsetsShiftHalves() {
        // Snapping is relative to the visibleFrame, not the screen origin.
        #expect(WindowRegion.halfLeft.targetFrame(in: sideDock)
                == CGRect(x: 200, y: 0, width: 620, height: 900))
        #expect(WindowRegion.halfRight.targetFrame(in: sideDock)
                == CGRect(x: 820, y: 0, width: 620, height: 900))
    }

    @Test func metadataCompleteAndSymbolsResolve() {
        // Every region must have a non-empty name and an SF Symbol that
        // actually resolves on this SDK — a typo'd symbol renders blank
        // blades with no other failure signal.
        for region in WindowRegion.allCases {
            #expect(!region.displayName.isEmpty)
            let image = NSImage(systemSymbolName: region.symbolName, accessibilityDescription: nil)
            #expect(image != nil, "SF Symbol missing: \(region.symbolName)")
        }
    }
}
```

(`NSImage` needs `import AppKit` — add it alongside Foundation.)

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild test -project NemoLoop.xcodeproj -scheme NemoLoop -destination 'platform=macOS' -only-testing:NemoLoopTests/WindowLayoutTests CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual -quiet`
Expected: compile failure — `cannot find 'WindowRegion' in scope`.

- [ ] **Step 3: Implement**

Create `NemoLoop/Plugins/Windows/WindowLayout.swift`:

```swift
// NemoLoop/Plugins/Windows/WindowLayout.swift
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
        case .thirdCenter: "rectangle.centerthird.inset.filled"
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
```

NOTE: if `metadataCompleteAndSymbolsResolve` fails on the three `…third.inset.filled` symbols (SDK availability), substitute the nearest existing `rectangle.*` variant (e.g. `rectangle.split.3x1` family) and update the spec's icon table in the same commit — the spec explicitly authorizes this.

- [ ] **Step 4: Run to verify pass**

Run the Step 2 command. Expected: PASS — 7 tests.

- [ ] **Step 5: Commit**

```bash
git add NemoLoop/Plugins/Windows/WindowLayout.swift NemoLoopTests/WindowLayoutTests.swift
git commit -m "feat(windows): pure snap-region geometry with symbol validation"
```

---

### Task 2: `WindowServicing` seam + real AX service + `WindowPlugin` with 14 ops

**Files:**
- Create: `NemoLoop/Plugins/Windows/WindowServicing.swift` (protocol + `AccessibilityWindowService`)
- Create: `NemoLoop/Plugins/Windows/WindowPlugin.swift` (plugin + ops)
- Test: `NemoLoopTests/WindowPluginTests.swift`

**Interfaces:**
- Consumes: `WindowRegion` (Task 1), `NemoPlugin`/`PluginOp` protocols, `PluginRegistry.perform` (not needed here — ops call the service directly).
- Produces:

```swift
@MainActor protocol WindowServicing: AnyObject {
    func isTrusted() -> Bool
    func promptForTrust()
    func focusedWindowFrame() -> CGRect?
    func setFrame(_ frame: CGRect) -> Bool
    func setMinimized() -> Bool
    func toggleFullscreen() -> Bool
}
@MainActor final class AccessibilityWindowService: WindowServicing   // real AX; not directly unit-tested

@MainActor final class WindowPlugin: NemoPlugin {
    static let pluginID: String          // "windows"
    init(service: (any WindowServicing)? = nil)   // nil-default + body ?? (MainActor default-arg constraint, see ChainPlugin)
    var operations: [any PluginOp]       // 14: 12 RegionOp + minimize + toggleFullscreen
    var status: PluginStatus             // isTrusted() ? .ready : .needsAuth
    let isEnabledByDefault: Bool         // false — opt-in
    var configSections: AnyView?         // nil in this task; Task 3 wires WindowConfigSection
}
```

- [ ] **Step 1: Write the failing tests**

Create `NemoLoopTests/WindowPluginTests.swift`:

```swift
import Testing
import Foundation
import AppKit
@testable import NemoLoop

@MainActor
struct WindowPluginTests {
    @MainActor
    final class RecordingWindowService: WindowServicing {
        var trusted = true
        var windowFrame: CGRect?
        var setFrameCalls: [CGRect] = []
        var minimizeCalls = 0
        var fullscreenToggles = 0
        var promptCalls = 0
        func isTrusted() -> Bool { trusted }
        func promptForTrust() { promptCalls += 1 }
        func focusedWindowFrame() -> CGRect? { windowFrame }
        func setFrame(_ frame: CGRect) -> Bool { setFrameCalls.append(frame); return true }
        func setMinimized() -> Bool { minimizeCalls += 1; return true }
        func toggleFullscreen() -> Bool { fullscreenToggles += 1; return true }
    }

    /// A window centered on the test host's main screen — the region op must
    /// compute against that same screen's live visibleFrame, so both sides of
    /// the assertion derive from one source.
    private func centeredWindowFrame() -> CGRect {
        let visible = NSScreen.main!.visibleFrame
        return CGRect(x: visible.midX - 200, y: visible.midY - 150, width: 400, height: 300)
    }

    @Test func offersFourteenOpsWithRegionIdSpace() {
        let plugin = WindowPlugin(service: RecordingWindowService())
        #expect(plugin.id == "windows")
        #expect(plugin.operations.count == 14)
        #expect(plugin.operations.map(\.id).contains("halfLeft"))
        #expect(plugin.operations.map(\.id).contains("maximize"))
        #expect(plugin.operations.map(\.id).contains("minimize"))
        #expect(plugin.operations.map(\.id).contains("toggleFullscreen"))
        // Every op symbol resolves on this SDK (blank-blade guard, same as regions).
        for op in plugin.operations {
            #expect(NSImage(systemSymbolName: op.symbolName, accessibilityDescription: nil) != nil,
                    "SF Symbol missing: \(op.symbolName)")
        }
    }

    @Test func regionOpSnapsToWindowScreenVisibleFrame() throws {
        let service = RecordingWindowService()
        service.windowFrame = centeredWindowFrame()
        let plugin = WindowPlugin(service: service)

        let op = plugin.operations.first { $0.id == "halfLeft" }!
        op.perform()

        let expected = WindowRegion.halfLeft.targetFrame(in: NSScreen.main!.visibleFrame)
        #expect(service.setFrameCalls == [expected])
    }

    @Test func allRegionsRouteThroughSetFrame() throws {
        let service = RecordingWindowService()
        service.windowFrame = centeredWindowFrame()
        let plugin = WindowPlugin(service: service)
        let visible = NSScreen.main!.visibleFrame

        for region in WindowRegion.allCases {
            let op = plugin.operations.first { $0.id == region.rawValue }!
            op.perform()
        }
        #expect(service.setFrameCalls.count == 12)
        #expect(service.setFrameCalls == WindowRegion.allCases.map { $0.targetFrame(in: visible) })
    }

    @Test func untrustedTriggerIsSilentNoOp() {
        let service = RecordingWindowService()
        service.trusted = false
        service.windowFrame = centeredWindowFrame()
        let plugin = WindowPlugin(service: service)

        for op in plugin.operations { op.perform() }
        #expect(service.setFrameCalls.isEmpty)
        #expect(service.minimizeCalls == 0)
        #expect(service.fullscreenToggles == 0)
    }

    @Test func missingFocusedWindowIsSilentNoOp() {
        let service = RecordingWindowService()
        service.windowFrame = nil
        let plugin = WindowPlugin(service: service)

        plugin.operations.first { $0.id == "halfLeft" }!.perform()
        #expect(service.setFrameCalls.isEmpty)
    }

    @Test func minimizeAndFullscreenRouteToAttributes() {
        let service = RecordingWindowService()
        service.windowFrame = centeredWindowFrame()
        let plugin = WindowPlugin(service: service)

        plugin.operations.first { $0.id == "minimize" }!.perform()
        plugin.operations.first { $0.id == "toggleFullscreen" }!.perform()
        #expect(service.minimizeCalls == 1)
        #expect(service.fullscreenToggles == 1)
        #expect(service.setFrameCalls.isEmpty)
    }

    @Test func statusReflectsTrust() {
        let service = RecordingWindowService()
        let plugin = WindowPlugin(service: service)
        #expect(plugin.status == .ready)
        service.trusted = false
        #expect(plugin.status == .needsAuth)
    }

    @Test func disabledByDefault() {
        let registry = PluginRegistry(defaults: makeDefaults(),
                                      plugins: [WindowPlugin(service: RecordingWindowService())])
        #expect(!registry.isEnabled("windows"))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild test -project NemoLoop.xcodeproj -scheme NemoLoop -destination 'platform=macOS' -only-testing:NemoLoopTests/WindowPluginTests CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual -quiet`
Expected: compile failure — `cannot find 'WindowServicing' in scope`.

- [ ] **Step 3: Implement the seam + real service**

Create `NemoLoop/Plugins/Windows/WindowServicing.swift`:

```swift
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
    /// kAXFullscreen toggled on the focused window.
    @discardableResult func toggleFullscreen() -> Bool
}

@MainActor
final class AccessibilityWindowService: WindowServicing {
    // nonisolated init: default-argument construction runs in a nonisolated
    // context (see ChainPlugin/ChainExecutor for the same constraint).
    nonisolated init() {}

    private var systemWide: AXUIElement { AXUIElementCreateSystemWide() }

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
        guard let position = AXValue(.cgPoint, &origin),
              let axSize = AXValue(.cgSize, &size) else { return false }
        return setAttribute(window, kAXPositionAttribute, position)
            && setAttribute(window, kAXSizeAttribute, axSize)
    }

    func setMinimized() -> Bool {
        guard let window = focusedWindow() else { return false }
        var one = true
        let value = AXValue(.cgBool, &one)
        return setAttribute(window, kAXMinimizedAttribute, value)
    }

    func toggleFullscreen() -> Bool {
        guard let window = focusedWindow() else { return false }
        guard let current = attribute(window, kAXFullScreenAttribute) as? Bool else { return false }
        var next = !current
        let value = AXValue(.cgBool, &next)
        return setAttribute(window, kAXFullScreenAttribute, value)
    }

    // MARK: - AX plumbing

    private func focusedWindow() -> AXUIElement? {
        guard let app = attribute(systemWide, kAXFocusedApplicationAttribute) as? AXUIElement else {
            return nil
        }
        return attribute(app, kAXFocusedWindowAttribute) as? AXUIElement
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        guard error == .success else { return nil }
        return value
    }

    private func setAttribute(_ element: AXUIElement, _ name: String, _ value: AXTypeRef) -> Bool {
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
```

NOTE for the implementer: `setFrame` needs `var` copies of `frame.origin`/`frame.size` before `AXValue(... &...)` — Swift won't take `&frame.origin` on a let parameter binding cleanly; adjust with explicit locals (`var origin = frame.origin; let axPoint = AXValue(.cgPoint, &origin)`). Also `kAXFullScreenAttribute` is the modern spelling of `kAXFullscreenAttribute` — use whichever compiles on this SDK and keep one spelling. Compile-clean beats verbatim.

- [ ] **Step 4: Implement the plugin**

Create `NemoLoop/Plugins/Windows/WindowPlugin.swift`:

```swift
// NemoLoop/Plugins/Windows/WindowPlugin.swift
import AppKit
import SwiftUI

/// Window-management plugin: 14 static ops over the focused window —
/// snap regions (pure geometry from WindowRegion), minimize, and a
/// fullscreen toggle. Opt-in (no legacy slots to serve); needsAuth until
/// the user grants Accessibility (the settings card carries the Grant
/// button — triggering ungranted ops stays silent per the spec).
@MainActor
final class WindowPlugin: NemoPlugin {
    static let pluginID = "windows"

    private let service: any WindowServicing

    init(service: (any WindowServicing)? = nil) {
        // nil-default + ?? : MainActor-isolated default args don't compile
        // (same constraint documented in ChainPlugin).
        self.service = service ?? AccessibilityWindowService()
    }

    let id = WindowPlugin.pluginID
    let displayName = "Windows"
    let symbolName = "rectangle.split.2x2"
    let summary = "Snap the focused window to halves, thirds, and quarters — plus maximize, minimize, and fullscreen."
    var status: PluginStatus { service.isTrusted() ? .ready : .needsAuth }
    let isEnabledByDefault = false

    /// nil until the grant-flow task wires WindowConfigSection in.
    var configSections: AnyView? { nil }

    var operations: [any PluginOp] {
        WindowRegion.allCases.map { RegionOp(region: $0, service: service) }
            + [MinimizeOp(service: service), FullscreenOp(service: service)]
    }

    // MARK: - Ops

    struct RegionOp: @MainActor PluginOp {
        let region: WindowRegion
        let service: any WindowServicing
        var id: String { region.rawValue }
        var displayName: String { region.displayName }
        var symbolName: String { region.symbolName }

        func perform() {
            guard service.isTrusted() else {
                NSLog("NemoLoop windows: \(region.rawValue) skipped — Accessibility not granted")
                return
            }
            guard let windowFrame = service.focusedWindowFrame() else {
                NSLog("NemoLoop windows: \(region.rawValue) skipped — no focused window")
                return
            }
            guard let screen = Self.screen(containing: windowFrame) else {
                NSLog("NemoLoop windows: \(region.rawValue) skipped — no screen for window")
                return
            }
            _ = service.setFrame(region.targetFrame(in: screen.visibleFrame))
        }

        /// The window's center picks the screen (a straddling window snaps
        /// against the screen holding its center). nil only in a session
        /// with no screens at all.
        static func screen(containing frame: CGRect) -> NSScreen? {
            let center = CGPoint(x: frame.midX, y: frame.midY)
            return NSScreen.screens.first { NSPointInRect(center, $0.frame) }
                ?? NSScreen.main
                ?? NSScreen.screens.first
        }
    }

    struct MinimizeOp: @MainActor PluginOp {
        let id = "minimize"
        let displayName = "Minimize"
        let symbolName = "minus"
        let service: any WindowServicing
        func perform() {
            guard service.isTrusted() else {
                NSLog("NemoLoop windows: minimize skipped — Accessibility not granted")
                return
            }
            _ = service.setMinimized()
        }
    }

    struct FullscreenOp: @MainActor PluginOp {
        let id = "toggleFullscreen"
        let displayName = "Toggle Fullscreen"
        let symbolName = "arrow.up.backward.and.arrow.down.forward"
        let service: any WindowServicing
        func perform() {
            guard service.isTrusted() else {
                NSLog("NemoLoop windows: fullscreen skipped — Accessibility not granted")
                return
            }
            _ = service.toggleFullscreen()
        }
    }
}
```

(`NSScreen()` is intentionally not used — `screen(containing:)` returns `NSScreen?` and `perform` skips silently on nil; the tests don't exercise the nil case since a test host always has a main screen, so they stay valid as written.)

- [ ] **Step 5: Run to verify pass**

Run the Step 2 command. Expected: PASS — 8 tests.

- [ ] **Step 6: Commit**

```bash
git add NemoLoop/Plugins/Windows/WindowServicing.swift NemoLoop/Plugins/Windows/WindowPlugin.swift NemoLoopTests/WindowPluginTests.swift
git commit -m "feat(windows): plugin with 14 ops over AX service seam"
```

---

### Task 3: Grant flow UI — `WindowConfigSection`

**Files:**
- Create: `NemoLoop/Plugins/Windows/WindowConfigSection.swift`
- Modify: `NemoLoop/Plugins/Windows/WindowPlugin.swift` (`configSections` nil → section)
- Test: `NemoLoopTests/WindowPluginTests.swift` (append)

**Interfaces:**
- Consumes: `WindowServicing` (Task 2).
- Produces: `struct WindowConfigSection: View` with `let service: any WindowServicing`; `WindowPlugin.configSections` returns `AnyView(WindowConfigSection(service: service))`.

- [ ] **Step 1: Write the failing test**

Append to `WindowPluginTests.swift` (inside the struct):

```swift
    @Test func configSectionsExposesTheGrantFlow() {
        let plugin = WindowPlugin(service: RecordingWindowService())
        #expect(plugin.configSections != nil)
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild test -project NemoLoop.xcodeproj -scheme NemoLoop -destination 'platform=macOS' -only-testing:NemoLoopTests/WindowPluginTests CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual -quiet`
Expected: FAIL — `configSections` is nil.

- [ ] **Step 3: Implement**

Create `NemoLoop/Plugins/Windows/WindowConfigSection.swift`:

```swift
// NemoLoop/Plugins/Windows/WindowConfigSection.swift
import Luminare
import SwiftUI

/// Plugins-tab config area for Windows: one trust row. Ungranted shows a
/// Grant Access button (system prompt); granted shows a green confirmation.
/// AX trust has no change notification, so the button polls briefly after
/// the prompt; outside that window the row refreshes when the card reopens.
struct WindowConfigSection: View {
    let service: any WindowServicing
    @State private var granted = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.raised.circle")
                .foregroundStyle(granted ? Color.green : Color.yellow)
            if granted {
                Text("Accessibility granted")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Window snapping needs Accessibility access.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Grant Access") { grant() }
                    .buttonStyle(.luminareCompact)
            }
        }
        .onAppear { granted = service.isTrusted() }
    }

    private func grant() {
        service.promptForTrust()
        // Light poll: the system prompt grants out-of-band; ~5s of checks
        // catches the common path without a permanent timer.
        Task { @MainActor in
            for _ in 0..<10 {
                try? await Task.sleep(for: .milliseconds(500))
                if service.isTrusted() { break }
            }
            withAnimation(.smooth(duration: 0.2)) { granted = service.isTrusted() }
        }
    }
}
```

Then in `WindowPlugin.swift` replace:

```swift
    /// nil until the grant-flow task wires WindowConfigSection in.
    var configSections: AnyView? { nil }
```

with:

```swift
    var configSections: AnyView? { AnyView(WindowConfigSection(service: service)) }
```

- [ ] **Step 4: Run to verify pass + full suite**

Focused: the Step 2 command (9 tests green). Then full suite once:
`xcodebuild test -project NemoLoop.xcodeproj -scheme NemoLoop -destination 'platform=macOS' -only-testing:NemoLoopTests CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual -quiet` — everything green before committing.

- [ ] **Step 5: Launch for human inspection (AX grant is human-only)**

```bash
pkill -x NemoLoop
xcodebuild build -project NemoLoop.xcodeproj -scheme NemoLoop -destination 'platform=macOS' CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual -quiet
open ~/Library/Developer/Xcode/DerivedData/NemoLoop-*/Build/Products/Debug/NemoLoop.app --args --settings
```

Report the manual checklist to the user (they do the clicking): Plugins → Windows card → enable toggle → expand → Grant Access → system prompt → grant → card shows green; connect the plugin; a snap op from the ring moves the frontmost window. Do NOT interact with the GUI or TCC prompt yourself.

- [ ] **Step 6: Commit**

```bash
git add NemoLoop/Plugins/Windows/WindowConfigSection.swift NemoLoop/Plugins/Windows/WindowPlugin.swift NemoLoopTests/WindowPluginTests.swift
git commit -m "feat(windows): accessibility grant flow in the plugins card"
```

---

### Task 4: Registry wiring + render-harness 5th seam + final verification

**Files:**
- Modify: `NemoLoop/Services/PluginRegistry.swift` (shared plugin list only)
- Modify: `Design/render_check_ring_tab.swift` (5th seam, pin, assertions, header counts)

**Interfaces:**
- Consumes: `WindowPlugin`/`WindowRegion` (Tasks 1-2); the harness's existing mirrored-plugin seam pattern (ScreenshotPlugin/ChainPlugin mirrors).
- Produces: `PluginRegistry.shared` 5th plugin; harness picker data shows 4 whole rows / 25 plugin items.

- [ ] **Step 1: Register the plugin**

In `PluginRegistry.swift`, the `shared` list currently reads (post-P0):

```swift
    static let shared = PluginRegistry(plugins: [
        SystemPlugin(),
        AppearancePlugin(),
        ScreenshotPlugin(),
        ChainPlugin(),
    ])
```

Append `WindowPlugin(),` as the 5th entry.

- [ ] **Step 2: Harness — compile real geometry, mirror the plugin shell**

In `Design/render_check_ring_tab.swift`:

Edit A — `RenderCheckBootstrap.appSources` (the list containing `"NemoLoop/Plugins/SystemPlugin.swift"` etc.): append after the ChainPlugin-era entries or in file order:

```swift
        "NemoLoop/Plugins/Windows/WindowLayout.swift",
```

(`WindowServicing.swift`/`WindowPlugin.swift`/`WindowConfigSection.swift` stay OUT — the real plugin links Luminare through configSections; the shell below keeps the registry compiling.)

Edit B — after the mirrored `ChainPlugin` seam class, add:

```swift
/// Verbatim from NemoLoop/Plugins/Windows/WindowPlugin.swift, EXCEPT: ops
/// carry the real WindowRegion metadata (compiled verbatim from the real
/// geometry file — ids guaranteed identical to the app's) with perform
/// no-op'd, and configSections is dropped (Luminare link). Status is
/// .ready — the harness never triggers ops, and the pixel assertion only
/// reads rows.
@MainActor
final class WindowPlugin: @MainActor NemoPlugin {
    static let pluginID = "windows"
    let id = WindowPlugin.pluginID
    let displayName = "Windows"
    let symbolName = "rectangle.split.2x2"
    let summary = "Snap the focused window to halves, thirds, and quarters — plus maximize, minimize, and fullscreen."

    struct Op: @MainActor PluginOp {
        let id: String
        let displayName: String
        let symbolName: String
        func perform() { NSLog("NemoLoop render harness: windows op skipped") }
    }

    var operations: [any PluginOp] {
        WindowRegion.allCases.map { Op(id: $0.rawValue, displayName: $0.displayName, symbolName: $0.symbolName) }
            + [Op(id: "minimize", displayName: "Minimize", symbolName: "minus"),
               Op(id: "toggleFullscreen", displayName: "Toggle Fullscreen",
                  symbolName: "arrow.up.backward.and.arrow.down.forward")]
    }
    var status: PluginStatus { .ready }
}
```

Edit C — `RenderCheckBootstrap.registryPins`: append `"-nemoloop.plugin.windows.enabled", "YES",`.

- [ ] **Step 3: Harness — widen assertions + header counts**

Same file:

1. The code-side whole-rows check (near the `ActionPickerModel(apps:registry: .shared)` build, currently asserting `wholeRows.map(\.title) == ["System", "Screenshot", "Chains"]`): becomes `["System", "Screenshot", "Chains", "Windows"]` (registry order; appearance pinned off). Update its message text.
2. The row-count check `pluginItems.count == 10` → `== 25` (4 whole + 5+1+1+14 ops); update the message parenthetical.
3. `sectionsComplete(...)`: `trailingBands == 3` → `== 4` and `trailingPixels >= 36` → `>= 48`.
4. The verdict-5 message's "3 whole rows" → "4 whole rows".
5. Header comment: "exactly four tiny seams" → "exactly five tiny seams", appending the Windows seam to the enumerated list in matching style; pin-list comment "pin all four plugins explicitly" → "all five".

- [ ] **Step 4: Run harness + full suite**

`swift Design/render_check_ring_tab.swift` → exit 0, `SUMMARY: all pixel checks PASS` (verdict 5 reports 4 trailing bands; panel C lists a "Windows" row with "14 actions").
Full unit suite → **180 expected at plan time; actual 184 after the review-fix y-flip suite (4 tests, commit 1788fac)**; report the actual total.

- [ ] **Step 5: Final app launch for acceptance**

```bash
pkill -x NemoLoop
xcodebuild build -project NemoLoop.xcodeproj -scheme NemoLoop -destination 'platform=macOS' CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual -quiet
open ~/Library/Developer/Xcode/DerivedData/NemoLoop-*/Build/Products/Debug/NemoLoop.app
```

Report to the user: suite + harness results, app launched — human acceptance path: enable Windows plugin, grant Accessibility, mount "Left Half" on a blade, summon the ring over any window, release.

- [ ] **Step 6: Commit**

```bash
git add NemoLoop/Services/PluginRegistry.swift Design/render_check_ring_tab.swift
git commit -m "feat(windows): register 5th plugin; harness covers the Windows picker row"
```

---

## Deferred (explicitly out of P1)

Stage Manager (P5 evaluation), restore-original-frame, tiling animations, window memory, multi-window pickers. The stash `stash@{0}` (OCR NSLog) stays untouched.
