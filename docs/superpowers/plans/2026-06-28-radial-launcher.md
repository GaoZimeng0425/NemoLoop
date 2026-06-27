# Radial Launcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build NemoLoop — a macOS menu-bar utility where holding a global hotkey pops a 6-wedge donut ring at the mouse cursor; moving the mouse in a direction highlights a wedge, and releasing the hotkey launches that wedge's app.

**Architecture:** A `.accessory` SwiftUI app (no Dock icon, `MenuBarExtra` for settings/quit). A borderless non-activating transparent `NSPanel` covers the cursor's screen and hosts a SwiftUI donut. A `KeyboardShortcuts` hotkey drives show (onKeyDown) / launch (onKeyUp). While shown, a timer polls `NSEvent.mouseLocation`; the pure `RingGeometry` function maps the cursor vector to a wedge index. The selected wedge's app launches via `NSWorkspace`. Config (6 app slots) persists in UserDefaults and is edited in a settings window.

**Tech Stack:** Swift 5 / SwiftUI / AppKit, Swift Testing, `sindresorhus/KeyboardShortcuts` (SPM), `NSWorkspace`, `NSPanel`.

## Global Constraints

- macOS deployment target: **26.5**. Swift language version: **5.0**.
- Tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`) — never XCTest.
- Source files live under `NemoLoop/`; tests under `NemoLoopTests/`. The Xcode project uses **file-system-synchronized groups**, so new files are auto-included — **no `.pbxproj` edits needed** for `.swift` files.
- App activation policy is **`.accessory`** (no Dock icon, absent from Cmd-Tab). UI entry is a `MenuBarExtra`.
- Git: **never commit on `main`.** Work on `develop`. Commit after every task.
- Wedge convention: **index 0 is top (12 o'clock)**, indices increase **clockwise** (0=top, 1=upper-right, 2=lower-right, 3=bottom, 4=lower-left, 5=upper-left). 6 wedges × 60°, wedge 0 centered on "up" spanning [-30°, +30°].
- Ring center is the global mouse location at summon time; cancel = release while cursor is within `deadZoneRadius` of center, or press ESC.

---

## File Structure

- `NemoLoop/Ring/RingGeometry.swift` — pure angle→wedge mapping (no UIKit/AppKit state).
- `NemoLoop/Model/SliceConfig.swift` — Codable 6-slot config + UserDefaults persistence.
- `NemoLoop/Model/SliceStore.swift` — `@Observable @MainActor` store wrapping `SliceConfig` + icon lookup.
- `NemoLoop/App/AppDelegate.swift` — lifecycle, activation policy, service assembly.
- `NemoLoop/NemoLoopApp.swift` — entry point + `MenuBarExtra` (replaces SwiftData template).
- `NemoLoop/Ring/RingPanel.swift` — borderless non-activating transparent `NSPanel` + ESC handling.
- `NemoLoop/Ring/RingWindowController.swift` — positions/shows/hides the panel on the cursor's screen.
- `NemoLoop/Ring/RingViewModel.swift` — `@Observable` display state + mouse-poll loop driving highlight.
- `NemoLoop/Ring/RingView.swift` — SwiftUI donut: 6 wedges + app icons + highlight.
- `NemoLoop/Services/Launcher.swift` — launches/activates an app by URL.
- `NemoLoop/Services/HotkeyService.swift` — `KeyboardShortcuts` wiring (down=show, up=launch).
- `NemoLoop/Settings/SettingsView.swift` — 6 slot pickers + hotkey recorder.
- `NemoLoopTests/RingGeometryTests.swift`, `NemoLoopTests/SliceConfigTests.swift` — unit tests.
- Delete: `NemoLoop/Item.swift`. Rewrite: `NemoLoop/ContentView.swift` (remove SwiftData template) — folded into Task 3.

---

### Task 1: RingGeometry — pure angle→wedge mapping

**Files:**
- Create: `NemoLoop/Ring/RingGeometry.swift`
- Test: `NemoLoopTests/RingGeometryTests.swift`

**Interfaces:**
- Produces: `enum RingGeometry { static func wedgeIndex(from center: CGPoint, to point: CGPoint, wedgeCount: Int = 6, deadZoneRadius: CGFloat) -> Int? }` — returns `nil` if `point` is within `deadZoneRadius` of `center`, else `0..<wedgeCount` with index 0 centered on +Y (up), increasing clockwise. Coordinates are AppKit global (bottom-left origin, +Y up).

- [ ] **Step 1: Write the failing test**

```swift
// NemoLoopTests/RingGeometryTests.swift
import Testing
import CoreGraphics
@testable import NemoLoop

struct RingGeometryTests {
    let center = CGPoint(x: 100, y: 100)
    let dz: CGFloat = 20

    @Test func deadZoneReturnsNil() {
        #expect(RingGeometry.wedgeIndex(from: center, to: center, deadZoneRadius: dz) == nil)
        #expect(RingGeometry.wedgeIndex(from: center, to: CGPoint(x: 110, y: 105), deadZoneRadius: dz) == nil)
    }

    @Test func straightUpIsWedgeZero() {
        // +Y is up in AppKit global coords
        #expect(RingGeometry.wedgeIndex(from: center, to: CGPoint(x: 100, y: 200), deadZoneRadius: dz) == 0)
    }

    @Test func clockwiseSectors() {
        // upper-right (~60° clockwise from up)
        #expect(RingGeometry.wedgeIndex(from: center, to: CGPoint(x: 187, y: 150), deadZoneRadius: dz) == 1)
        // straight down
        #expect(RingGeometry.wedgeIndex(from: center, to: CGPoint(x: 100, y: 0), deadZoneRadius: dz) == 3)
        // upper-left
        #expect(RingGeometry.wedgeIndex(from: center, to: CGPoint(x: 13, y: 150), deadZoneRadius: dz) == 5)
    }

    @Test func boundaryAtThirtyDegreesGoesToWedgeOne() {
        // just clockwise of +30° boundary → wedge 1
        let p = CGPoint(x: 100 + 100 * sin(31 * .pi / 180), y: 100 + 100 * cos(31 * .pi / 180))
        #expect(RingGeometry.wedgeIndex(from: center, to: p, deadZoneRadius: dz) == 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project NemoLoop.xcodeproj -scheme NemoLoop -destination 'platform=macOS' -only-testing:NemoLoopTests/RingGeometryTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'RingGeometry' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
// NemoLoop/Ring/RingGeometry.swift
import CoreGraphics
import Foundation

enum RingGeometry {
    /// Maps the vector from `center` to `point` onto a wedge index.
    /// Index 0 is centered on +Y (up); indices increase clockwise.
    /// Returns nil when within `deadZoneRadius` (treated as "no selection").
    static func wedgeIndex(
        from center: CGPoint,
        to point: CGPoint,
        wedgeCount: Int = 6,
        deadZoneRadius: CGFloat
    ) -> Int? {
        let dx = point.x - center.x
        let dy = point.y - center.y
        if (dx * dx + dy * dy) < (deadZoneRadius * deadZoneRadius) { return nil }

        // atan2(dx, dy): 0 at +Y (up), increasing toward +X (right) = clockwise.
        let twoPi = 2 * Double.pi
        let sliceAngle = twoPi / Double(wedgeCount)
        let angle = atan2(Double(dx), Double(dy))
        let normalized = (angle.truncatingRemainder(dividingBy: twoPi) + twoPi)
            .truncatingRemainder(dividingBy: twoPi)
        // Shift by half a slice so wedge 0 is centered on up.
        let shifted = (normalized + sliceAngle / 2).truncatingRemainder(dividingBy: twoPi)
        return Int(shifted / sliceAngle) % wedgeCount
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project NemoLoop.xcodeproj -scheme NemoLoop -destination 'platform=macOS' -only-testing:NemoLoopTests/RingGeometryTests 2>&1 | tail -20`
Expected: PASS (and delete the template `example()` test in `NemoLoopTests.swift` if it interferes — leave it otherwise).

- [ ] **Step 5: Commit**

```bash
git add NemoLoop/Ring/RingGeometry.swift NemoLoopTests/RingGeometryTests.swift
git commit -m "feat: add RingGeometry wedge mapping with tests"
```

---

### Task 2: SliceConfig + SliceStore — model & persistence

**Files:**
- Create: `NemoLoop/Model/SliceConfig.swift`
- Create: `NemoLoop/Model/SliceStore.swift`
- Test: `NemoLoopTests/SliceConfigTests.swift`

**Interfaces:**
- Produces: `struct SliceConfig: Codable, Equatable { var slots: [URL?]; static let wedgeCount = 6; static var empty: SliceConfig; init(slots: [URL?]) /* pads/truncates to 6 */ }`
- Produces: `@Observable @MainActor final class SliceStore { var config: SliceConfig; init(defaults: UserDefaults = .standard); func setSlot(_ url: URL?, at index: Int); func icon(at index: Int) -> NSImage? }`
- Consumes (later tasks): `SliceStore.config.slots[i]` for the app URL at wedge `i`; `icon(at:)` for rendering.

- [ ] **Step 1: Write the failing test**

```swift
// NemoLoopTests/SliceConfigTests.swift
import Testing
import Foundation
@testable import NemoLoop

struct SliceConfigTests {
    @Test func initPadsToSixSlots() {
        let c = SliceConfig(slots: [URL(filePath: "/Applications/Safari.app")])
        #expect(c.slots.count == 6)
        #expect(c.slots[0] == URL(filePath: "/Applications/Safari.app"))
        #expect(c.slots[5] == nil)
    }

    @Test func initTruncatesBeyondSix() {
        let urls = (0..<8).map { URL(filePath: "/A\($0).app") } as [URL?]
        #expect(SliceConfig(slots: urls).slots.count == 6)
    }

    @Test func codableRoundTrip() throws {
        var c = SliceConfig.empty
        c.slots[2] = URL(filePath: "/Applications/Notes.app")
        let data = try JSONEncoder().encode(c)
        let decoded = try JSONDecoder().decode(SliceConfig.self, from: data)
        #expect(decoded == c)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project NemoLoop.xcodeproj -scheme NemoLoop -destination 'platform=macOS' -only-testing:NemoLoopTests/SliceConfigTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'SliceConfig' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
// NemoLoop/Model/SliceConfig.swift
import Foundation

struct SliceConfig: Codable, Equatable {
    static let wedgeCount = 6
    var slots: [URL?]

    init(slots: [URL?]) {
        var s = Array(slots.prefix(Self.wedgeCount))
        while s.count < Self.wedgeCount { s.append(nil) }
        self.slots = s
    }

    static var empty: SliceConfig { SliceConfig(slots: []) }
}
```

```swift
// NemoLoop/Model/SliceStore.swift
import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class SliceStore {
    private static let defaultsKey = "nemoloop.sliceConfig"
    private let defaults: UserDefaults

    var config: SliceConfig {
        didSet { persist() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(SliceConfig.self, from: data) {
            self.config = decoded
        } else {
            self.config = .empty
        }
    }

    func setSlot(_ url: URL?, at index: Int) {
        guard config.slots.indices.contains(index) else { return }
        config.slots[index] = url
    }

    func icon(at index: Int) -> NSImage? {
        guard config.slots.indices.contains(index), let url = config.slots[index] else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project NemoLoop.xcodeproj -scheme NemoLoop -destination 'platform=macOS' -only-testing:NemoLoopTests/SliceConfigTests 2>&1 | tail -20`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add NemoLoop/Model/SliceConfig.swift NemoLoop/Model/SliceStore.swift NemoLoopTests/SliceConfigTests.swift
git commit -m "feat: add SliceConfig model and persistent SliceStore"
```

---

### Task 3: App bootstrap — remove SwiftData, add KeyboardShortcuts, `.accessory` + MenuBarExtra

**Files:**
- Delete: `NemoLoop/Item.swift`
- Rewrite: `NemoLoop/NemoLoopApp.swift`, `NemoLoop/ContentView.swift`
- Create: `NemoLoop/App/AppDelegate.swift`
- Modify (manual, Xcode GUI): add SPM package `https://github.com/sindresorhus/KeyboardShortcuts` to the `NemoLoop` target.

**Interfaces:**
- Produces: `final class AppDelegate: NSObject, NSApplicationDelegate` exposing `let sliceStore: SliceStore`, and (filled in later tasks) `ringController`, `hotkeyService`. For now it sets `.accessory` policy and owns `sliceStore`.

> **This task has no unit test** — its deliverable is "app builds and runs as a menu-bar-only app." Verify by build + launch.

- [ ] **Step 1: Add the KeyboardShortcuts SPM dependency (manual)**

In Xcode: File → Add Package Dependencies → enter `https://github.com/sindresorhus/KeyboardShortcuts` → Add Package → attach the `KeyboardShortcuts` library product to the **NemoLoop** app target (not the test targets).

Verify it resolved:
Run: `grep -c "KeyboardShortcuts" NemoLoop.xcodeproj/project.pbxproj`
Expected: ≥ 1.

- [ ] **Step 2: Delete the SwiftData template model**

```bash
git rm NemoLoop/Item.swift
```

- [ ] **Step 3: Write AppDelegate**

```swift
// NemoLoop/App/AppDelegate.swift
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let sliceStore = SliceStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
```

- [ ] **Step 4: Rewrite the entry point with MenuBarExtra**

```swift
// NemoLoop/NemoLoopApp.swift
import SwiftUI

@main
struct NemoLoopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("NemoLoop", systemImage: "circle.grid.cross") {
            Button("Settings…") { /* opened in Task 8 */ }
            Divider()
            Button("Quit NemoLoop") { NSApplication.shared.terminate(nil) }
        }
    }
}
```

- [ ] **Step 5: Replace ContentView placeholder (still referenced by tests target build)**

```swift
// NemoLoop/ContentView.swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        EmptyView()
    }
}
```

- [ ] **Step 6: Build and run**

Run: `xcodebuild build -project NemoLoop.xcodeproj -scheme NemoLoop -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`. Launching the app shows a menu-bar icon with Settings/Quit and **no Dock icon**.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: bootstrap menu-bar app, add KeyboardShortcuts, remove SwiftData template"
```

---

### Task 4: RingPanel + RingWindowController — transparent overlay on cursor's screen

**Files:**
- Create: `NemoLoop/Ring/RingPanel.swift`
- Create: `NemoLoop/Ring/RingWindowController.swift`

**Interfaces:**
- Produces: `final class RingPanel: NSPanel { var onCancel: (() -> Void)? }` — non-activating, transparent, can become key, calls `onCancel` on ESC.
- Produces: `@MainActor final class RingWindowController { func show(content: some View, centeredAtGlobalPoint: CGPoint, onCancel: @escaping () -> Void); func hide(); var isVisible: Bool; func screenForCursor() -> NSScreen }`
- Consumes: a SwiftUI view (the `RingView` from Task 6) passed to `show`.

> **No unit test** (NSWindow/screen integration is excluded per the spec's test strategy). Verify by temporary manual show.

- [ ] **Step 1: Write RingPanel**

```swift
// NemoLoop/Ring/RingPanel.swift
import AppKit

final class RingPanel: NSPanel {
    var onCancel: (() -> Void)?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .popUpMenu
        isFloatingPanel = true
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
```

- [ ] **Step 2: Write RingWindowController**

```swift
// NemoLoop/Ring/RingWindowController.swift
import AppKit
import SwiftUI

@MainActor
final class RingWindowController {
    private var panel: RingPanel?

    var isVisible: Bool { panel != nil }

    /// Screen that currently contains the mouse cursor (falls back to main).
    func screenForCursor() -> NSScreen {
        let loc = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(loc, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    func show(content: some View, centeredAtGlobalPoint center: CGPoint, onCancel: @escaping () -> Void) {
        hide()
        let screen = screenForCursor()
        let panel = RingPanel(contentRect: screen.frame)
        panel.onCancel = onCancel

        // Convert global (bottom-left) center to the hosting view's top-left coords.
        let local = CGPoint(x: center.x - screen.frame.minX,
                            y: screen.frame.maxY - center.y)

        let host = NSHostingView(
            rootView: AnyView(content.environment(\.ringCenter, local))
        )
        host.frame = NSRect(origin: .zero, size: screen.frame.size)
        panel.contentView = host
        panel.setFrame(screen.frame, display: true)
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

// Passes the ring's center (top-left view coords) down to RingView.
private struct RingCenterKey: EnvironmentKey {
    static let defaultValue: CGPoint = .zero
}
extension EnvironmentValues {
    var ringCenter: CGPoint {
        get { self[RingCenterKey.self] }
        set { self[RingCenterKey.self] = newValue }
    }
}
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild build -project NemoLoop.xcodeproj -scheme NemoLoop -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add NemoLoop/Ring/RingPanel.swift NemoLoop/Ring/RingWindowController.swift
git commit -m "feat: add transparent non-activating ring panel and window controller"
```

---

### Task 5: RingViewModel — display state + mouse-poll loop

**Files:**
- Create: `NemoLoop/Ring/RingViewModel.swift`

**Interfaces:**
- Produces: `@Observable @MainActor final class RingViewModel { var isShown: Bool; var highlightedIndex: Int?; let deadZoneRadius: CGFloat; func begin(centerGlobal: CGPoint); func end(); var selectedIndex: Int? }`
- `begin` records the global center and starts a ~120 Hz timer that reads `NSEvent.mouseLocation` and updates `highlightedIndex` via `RingGeometry.wedgeIndex`. `end` stops the timer. `selectedIndex` returns the current `highlightedIndex` (nil if in dead zone).
- Consumes: `RingGeometry.wedgeIndex` (Task 1).

> **No unit test** — it polls live mouse state and timers. The pure mapping it delegates to is already tested in Task 1.

- [ ] **Step 1: Write RingViewModel**

```swift
// NemoLoop/Ring/RingViewModel.swift
import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class RingViewModel {
    var isShown = false
    var highlightedIndex: Int?
    let deadZoneRadius: CGFloat = 36

    @ObservationIgnored private var centerGlobal: CGPoint = .zero
    @ObservationIgnored private var timer: Timer?

    var selectedIndex: Int? { highlightedIndex }

    func begin(centerGlobal: CGPoint) {
        self.centerGlobal = centerGlobal
        self.highlightedIndex = nil
        self.isShown = true
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func end() {
        timer?.invalidate()
        timer = nil
        isShown = false
        highlightedIndex = nil
    }

    private func sample() {
        highlightedIndex = RingGeometry.wedgeIndex(
            from: centerGlobal,
            to: NSEvent.mouseLocation,
            deadZoneRadius: deadZoneRadius
        )
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild build -project NemoLoop.xcodeproj -scheme NemoLoop -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add NemoLoop/Ring/RingViewModel.swift
git commit -m "feat: add RingViewModel with mouse-poll highlight loop"
```

---

### Task 6: RingView — SwiftUI donut with wedges, icons, highlight

**Files:**
- Create: `NemoLoop/Ring/RingView.swift`

**Interfaces:**
- Produces: `struct RingView: View { init(store: SliceStore, viewModel: RingViewModel) }` — draws a donut centered at `@Environment(\.ringCenter)`, 6 wedges, each wedge's app icon, and highlights `viewModel.highlightedIndex`.
- Consumes: `SliceStore.icon(at:)` (Task 2), `RingViewModel.highlightedIndex` (Task 5), `\.ringCenter` environment (Task 4).

> **No unit test** (SwiftUI rendering). Verify visually in Task 7's end-to-end run.

- [ ] **Step 1: Write RingView**

```swift
// NemoLoop/Ring/RingView.swift
import SwiftUI

struct RingView: View {
    let store: SliceStore
    @Bindable var viewModel: RingViewModel
    @Environment(\.ringCenter) private var center

    private let outerRadius: CGFloat = 96
    private let innerRadius: CGFloat = 40
    private let wedgeCount = SliceConfig.wedgeCount

    init(store: SliceStore, viewModel: RingViewModel) {
        self.store = store
        self._viewModel = Bindable(viewModel)
    }

    var body: some View {
        ZStack {
            ForEach(0..<wedgeCount, id: \.self) { i in
                WedgeShape(index: i, count: wedgeCount,
                           innerRadius: innerRadius, outerRadius: outerRadius)
                    .fill(fillColor(for: i))
                    .overlay(
                        WedgeShape(index: i, count: wedgeCount,
                                   innerRadius: innerRadius, outerRadius: outerRadius)
                            .stroke(.white.opacity(0.15), lineWidth: 1)
                    )
                iconView(for: i)
            }
        }
        .frame(width: outerRadius * 2, height: outerRadius * 2)
        .position(center)
        .animation(.easeOut(duration: 0.12), value: viewModel.highlightedIndex)
    }

    private func fillColor(for i: Int) -> Color {
        let isEmpty = store.config.slots[i] == nil
        if viewModel.highlightedIndex == i {
            return isEmpty ? Color.white.opacity(0.18) : Color.accentColor.opacity(0.85)
        }
        return Color.black.opacity(isEmpty ? 0.35 : 0.6)
    }

    @ViewBuilder
    private func iconView(for i: Int) -> some View {
        let midRadius = (innerRadius + outerRadius) / 2
        // wedge i center angle: 0 = up, clockwise. Convert to view coords (y down).
        let angle = (Double(i) / Double(wedgeCount)) * 2 * .pi
        let dx = midRadius * sin(angle)
        let dy = -midRadius * cos(angle) // up = negative y in view space
        if let icon = store.icon(at: i) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 28, height: 28)
                .position(x: outerRadius + dx, y: outerRadius + dy)
        } else {
            Image(systemName: "plus")
                .foregroundStyle(.white.opacity(0.3))
                .position(x: outerRadius + dx, y: outerRadius + dy)
        }
    }
}

/// A donut wedge (annular sector) for index `i` of `count`, centered on up, clockwise.
struct WedgeShape: Shape {
    let index: Int
    let count: Int
    let innerRadius: CGFloat
    let outerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let slice = 2 * Double.pi / Double(count)
        // SwiftUI angles: 0° = +x (right), increasing clockwise (y down).
        // Wedge 0 centered on up (= -90° / 270°), spanning ±half slice.
        let centerAngle = -Double.pi / 2 + Double(index) * slice
        let start = Angle(radians: centerAngle - slice / 2)
        let end = Angle(radians: centerAngle + slice / 2)

        var p = Path()
        p.addArc(center: c, radius: outerRadius, startAngle: start, endAngle: end, clockwise: false)
        p.addArc(center: c, radius: innerRadius, startAngle: end, endAngle: start, clockwise: true)
        p.closeSubpath()
        return p
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild build -project NemoLoop.xcodeproj -scheme NemoLoop -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add NemoLoop/Ring/RingView.swift
git commit -m "feat: add RingView donut with wedges, icons, and highlight"
```

---

### Task 7: Launcher + HotkeyService — wire hold→show, release→launch, ESC→cancel

**Files:**
- Create: `NemoLoop/Services/Launcher.swift`
- Create: `NemoLoop/Services/HotkeyService.swift`
- Modify: `NemoLoop/App/AppDelegate.swift` (assemble services), `NemoLoop/NemoLoopApp.swift` (no change needed if MenuBarExtra already present)

**Interfaces:**
- Produces: `enum Launcher { static func launch(url: URL) }` — opens/activates the app at `url`.
- Produces: `extension KeyboardShortcuts.Name { static let summonRing }` (no default binding).
- Produces: `@MainActor final class HotkeyService { init(store: SliceStore, controller: RingWindowController, viewModel: RingViewModel); func register() }` — on key down: records mouse center, calls `viewModel.begin`, shows the panel with `RingView`; on key up: reads `viewModel.selectedIndex`, launches the slot's app if non-nil, then tears down; ESC (`onCancel`) tears down without launching.
- Consumes: `RingWindowController.show/hide` (Task 4), `RingViewModel` (Task 5), `RingView` (Task 6), `SliceStore.config` (Task 2).

> **No unit test** — it's the integration seam (global hotkey + window + workspace launch). Verify end-to-end manually.

- [ ] **Step 1: Write Launcher**

```swift
// NemoLoop/Services/Launcher.swift
import AppKit

enum Launcher {
    static func launch(url: URL) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if let error { NSLog("NemoLoop launch failed for \(url.path): \(error)") }
        }
    }
}
```

- [ ] **Step 2: Write HotkeyService**

```swift
// NemoLoop/Services/HotkeyService.swift
import AppKit
import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let summonRing = Self("summonRing") // no default binding — user sets it
}

@MainActor
final class HotkeyService {
    private let store: SliceStore
    private let controller: RingWindowController
    private let viewModel: RingViewModel

    init(store: SliceStore, controller: RingWindowController, viewModel: RingViewModel) {
        self.store = store
        self.controller = controller
        self.viewModel = viewModel
    }

    func register() {
        KeyboardShortcuts.onKeyDown(for: .summonRing) { [weak self] in
            self?.summon()
        }
        KeyboardShortcuts.onKeyUp(for: .summonRing) { [weak self] in
            self?.release()
        }
    }

    private func summon() {
        guard !controller.isVisible else { return } // ignore auto-repeat
        let center = NSEvent.mouseLocation
        viewModel.begin(centerGlobal: center)
        let content = RingView(store: store, viewModel: viewModel)
        controller.show(content: content, centeredAtGlobalPoint: center) { [weak self] in
            self?.cancel()
        }
    }

    private func release() {
        guard controller.isVisible else { return }
        let index = viewModel.selectedIndex
        teardown()
        if let index, let url = store.config.slots[index] {
            Launcher.launch(url: url)
        }
    }

    private func cancel() {
        guard controller.isVisible else { return }
        teardown()
    }

    private func teardown() {
        controller.hide()
        viewModel.end()
    }
}
```

- [ ] **Step 3: Assemble services in AppDelegate**

```swift
// NemoLoop/App/AppDelegate.swift
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let sliceStore = SliceStore()
    let ringController = RingWindowController()
    let ringViewModel = RingViewModel()
    private var hotkeyService: HotkeyService?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let service = HotkeyService(store: sliceStore, controller: ringController, viewModel: ringViewModel)
        service.register()
        self.hotkeyService = service
    }
}
```

- [ ] **Step 4: Build, then manual end-to-end check**

Run: `xcodebuild build -project NemoLoop.xcodeproj -scheme NemoLoop -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

Manual (after Task 8 sets a binding + apps, or temporarily set a binding in Settings first): hold the hotkey → ring appears at cursor; move in a direction → wedge highlights; release → app launches; release in center or press ESC → no launch. (If no binding is set yet, do this check at the end of Task 8.)

- [ ] **Step 5: Commit**

```bash
git add NemoLoop/Services/Launcher.swift NemoLoop/Services/HotkeyService.swift NemoLoop/App/AppDelegate.swift
git commit -m "feat: wire hotkey hold/release to ring show and app launch"
```

---

### Task 8: SettingsView — 6 slot pickers + hotkey recorder

**Files:**
- Create: `NemoLoop/Settings/SettingsView.swift`
- Modify: `NemoLoop/NemoLoopApp.swift` (add `Settings` scene + open it from MenuBarExtra)

**Interfaces:**
- Produces: `struct SettingsView: View { init(store: SliceStore) }` — 6 rows (wedge 0..5), each showing the assigned app's icon+name with "Choose…" (NSOpenPanel filtered to `.application`) and "Clear"; plus a `KeyboardShortcuts.Recorder` for `.summonRing`.
- Consumes: `SliceStore.setSlot` / `config` (Task 2), `KeyboardShortcuts.Name.summonRing` (Task 7).

> **No unit test** (SwiftUI + NSOpenPanel). Verify manually.

- [ ] **Step 1: Write SettingsView**

```swift
// NemoLoop/Settings/SettingsView.swift
import AppKit
import KeyboardShortcuts
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var store: SliceStore

    init(store: SliceStore) { self._store = Bindable(store) }

    private let wedgeNames = ["Top", "Upper-right", "Lower-right", "Bottom", "Lower-left", "Upper-left"]

    var body: some View {
        Form {
            Section("Hotkey") {
                KeyboardShortcuts.Recorder("Summon ring (hold):", name: .summonRing)
            }
            Section("Wedges") {
                ForEach(0..<SliceConfig.wedgeCount, id: \.self) { i in
                    HStack {
                        if let icon = store.icon(at: i) {
                            Image(nsImage: icon).resizable().frame(width: 22, height: 22)
                        } else {
                            Image(systemName: "app.dashed").frame(width: 22, height: 22)
                        }
                        Text(label(for: i)).frame(maxWidth: .infinity, alignment: .leading)
                        Button("Choose…") { chooseApp(for: i) }
                        Button("Clear") { store.setSlot(nil, at: i) }
                            .disabled(store.config.slots[i] == nil)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 380)
    }

    private func label(for i: Int) -> String {
        if let url = store.config.slots[i] {
            return "\(wedgeNames[i]): \(url.deletingPathExtension().lastPathComponent)"
        }
        return "\(wedgeNames[i]): (empty)"
    }

    private func chooseApp(for index: Int) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.application]
        panel.directoryURL = URL(filePath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            store.setSlot(url, at: index)
        }
    }
}
```

- [ ] **Step 2: Wire the Settings scene and MenuBarExtra action**

```swift
// NemoLoop/NemoLoopApp.swift
import SwiftUI

@main
struct NemoLoopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openSettings) private var openSettings

    var body: some Scene {
        MenuBarExtra("NemoLoop", systemImage: "circle.grid.cross") {
            SettingsLink { Text("Settings…") }
            Divider()
            Button("Quit NemoLoop") { NSApplication.shared.terminate(nil) }
        }
        Settings {
            SettingsView(store: appDelegate.sliceStore)
        }
    }
}
```

- [ ] **Step 3: Build**

Run: `xcodebuild build -project NemoLoop.xcodeproj -scheme NemoLoop -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Full manual acceptance**

Launch the app. Open Settings → set the summon hotkey via the recorder → assign apps to a few wedges. Then: hold the hotkey anywhere → ring appears at cursor; move toward an assigned wedge → it highlights in accent color; release → that app launches and comes to front; repeat releasing in the center (dead zone) or pressing ESC → nothing launches; empty wedges show a dim "+" and never launch.

- [ ] **Step 5: Commit**

```bash
git add NemoLoop/Settings/SettingsView.swift NemoLoop/NemoLoopApp.swift
git commit -m "feat: add settings window with wedge app pickers and hotkey recorder"
```

---

## Self-Review

**Spec coverage:**
- Hold→show / release→launch / direction selection → Tasks 5, 7 (+ geometry in 1). ✓
- Ring at cursor on cursor's screen → Task 4 (`screenForCursor`, coord conversion). ✓
- 6-wedge donut, icons, highlight, dim empty slots → Task 6. ✓
- Dead-zone cancel + ESC cancel → Task 1 (dead zone), Task 4 (ESC via `cancelOperation`), Task 7 (cancel teardown). ✓
- Apps only, by bundle URL, icon via `NSWorkspace.icon(forFile:)` → Tasks 2, 8. ✓
- Settings: 6 slots via NSOpenPanel, hotkey with no default binding via Recorder → Task 8. ✓
- `.accessory` + MenuBarExtra, no focus stealing (non-activating panel) → Tasks 3, 4. ✓
- Persistence in UserDefaults → Task 2. ✓
- Tests: geometry mapping, dead zone, SliceConfig codable round-trip → Tasks 1, 2. ✓ (empty-slot no-launch is enforced by Task 7's `store.config.slots[index]` guard and the dim render in Task 6.)

**Placeholder scan:** No TBD/TODO; every code step shows full code. The two `/* … */` comments in Task 3 reference work completed in later tasks and are replaced there. ✓

**Type consistency:** `SliceConfig.wedgeCount`, `SliceStore.config.slots`/`setSlot`/`icon(at:)`, `RingGeometry.wedgeIndex`, `RingViewModel.begin/end/selectedIndex/highlightedIndex`, `RingWindowController.show/hide/isVisible`, `\.ringCenter`, `KeyboardShortcuts.Name.summonRing` — names used in Tasks 4–8 match their definitions in Tasks 1–7. ✓

**Note for implementer:** `addGlobalMonitorForEvents` is intentionally avoided for mouse tracking — Task 5 uses a `Timer` polling `NSEvent.mouseLocation`, which needs no Accessibility permission and works regardless of app-active state. ESC works because the panel is `.nonactivatingPanel` + `canBecomeKey`, receiving `cancelOperation(_:)` without activating the app.
