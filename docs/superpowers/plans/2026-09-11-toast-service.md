# 全局 ToastService 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 NemoLoop 建一个全局 toast 通道:任何模块一行 `ToastService.shared.show(kind, text)` 即可在鼠标所在屏下方弹一条自动消失的黑胶囊。

**Architecture:** 纯状态机 ToastService(@Observable,不碰窗口,无头可测)+ 共享小面板 ToastWindowController(懒创建、每次 show 重定位、淡出动画播完才 orderOut)+ 固定样式 ToastView。三个消费方:PluginRegistry.perform 失败、ChainExecutor 中断、OCR 迁移。

**Tech Stack:** Swift 6 / AppKit(NSPanel + NSHostingView)/ SwiftUI(@Observable + withObservationTracking)/ swift-testing。

**Spec:** `docs/superpowers/specs/2026-09-11-toast-service-design.md`(计划以 spec 为准;文案已勘误为英文)。

## Global Constraints

- 分支:`feature/toast-service`(已存在,spec 已在其上)。**每次 commit 前先 `git branch --show-current` 确认仍是它**(develop 会脚下移动,项目惯例)。
- 单测命令(证书问题,必须 ad-hoc 覆盖;不用此命令会因签名中断):
  `xcodebuild test -project NemoLoop.xcodeproj -scheme NemoLoop -destination 'platform=macOS' -only-testing:NemoLoopTests CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual`
- 测试风格:swift-testing(`import Testing` / `@Test` / `#expect` / `@MainActor struct`),共享 doubles 在 `NemoLoopTests/PluginTestDoubles.swift`(`StubPlugin` / `ClosureOp` / `makeDefaults()`)。
- UI 文案一律英文,逐字用 spec 接入点表的字符串,不得改写。
- ToastView 禁用一切 Material/VisualEffectView/glassEffect(macOS 26 吞图层前科),纯形状填充。
- 新文件放 `NemoLoop/Services/Toast/`,工程是同步文件夹(pbxproj 自动纳入,**不要**手动编辑 pbxproj)。
- 仓库无 README(不存在的东西不要更新)。
- 提交信息:`feat(toast): …` / `test(toast): …` 风格,与近期历史一致。

---

### Task 1: ToastService 状态机(TDD)

**Files:**
- Create: `NemoLoop/Services/Toast/ToastService.swift`
- Test: `NemoLoopTests/ToastServiceTests.swift`

**Interfaces:**
- Consumes: 无(第一块地基)。
- Produces(后续任务依赖的精确签名):
  - `enum ToastKind { case success, error, info }`(顶层)
  - `@MainActor @Observable final class ToastService`,内嵌 `struct Toast: Equatable { let kind: ToastKind; let text: String }`
  - `static let shared: ToastService`
  - `init(sleeper: any ToastSleeping = TaskToastSleeper(), toastDuration: TimeInterval = 2.0, errorDuration: TimeInterval = 3.5, fadeDuration: TimeInterval = 0.25)`
  - `private(set) var current: Toast?`、`private(set) var visible: Bool`、`private(set) var panelWanted: Bool`
  - `func show(_ kind: ToastKind, _ text: String)`
  - seam:`@MainActor protocol ToastSleeping: AnyObject { func sleep(seconds: TimeInterval) async throws }` + 默认实现 `TaskToastSleeper`

- [ ] **Step 1: 写失败测试**

```swift
// NemoLoopTests/ToastServiceTests.swift
import Testing
import Foundation
@testable import NemoLoop

@MainActor
struct ToastServiceTests {
    // Deterministic double: parks each sleep on a continuation (the
    // ChainExecutorTests.BlockingSleeper idiom — Task.sleep can't be observed
    // from tests). Cancellation resumes every parked continuation.
    @MainActor
    private final class ParkingSleeper: ToastSleeping {
        private(set) var slept: [TimeInterval] = []
        private(set) var cancelledCount = 0
        private var parked: [CheckedContinuation<Void, Error>] = []

        func sleep(seconds: TimeInterval) async throws {
            slept.append(seconds)
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { parked.append($0) }
            } onCancel: {
                Task { @MainActor in self.cancelAll() }
            }
        }

        private func cancelAll() {
            cancelledCount += parked.count
            parked.forEach { $0.resume(throwing: CancellationError()) }
            parked.removeAll()
        }

        var parkedCount: Int { parked.count }
        func resumeNext() {
            guard !parked.isEmpty else { return }
            parked.removeFirst().resume(returning: ())
        }
    }

    /// Dismiss transitions land on a fire-and-forget task; poll until the
    /// condition holds (or fail loud on timeout) instead of sleeping blind.
    private func eventually(_ condition: @autoclosure @escaping () -> Bool,
                            timeout: TimeInterval = 2.0) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }

    @Test func showSetsStateAndStartsVisibleTimer() async {
        let sleeper = ParkingSleeper()
        let service = ToastService(sleeper: sleeper)
        service.show(.success, "Snipped to clipboard")
        #expect(service.current == .init(kind: .success, text: "Snipped to clipboard"))
        #expect(service.visible)
        #expect(service.panelWanted)
        await eventually(sleeper.parkedCount == 1)
        #expect(sleeper.slept == [2.0])
    }

    @Test func errorToastWaitsLonger() async {
        let sleeper = ParkingSleeper()
        let service = ToastService(sleeper: sleeper)
        service.show(.error, "boom")
        await eventually(sleeper.slept == [3.5])
    }

    @Test func fadesThenClearsInTwoStages() async {
        let sleeper = ParkingSleeper()
        let service = ToastService(sleeper: sleeper)
        service.show(.info, "No text recognized")
        await eventually(sleeper.parkedCount == 1)

        sleeper.resumeNext()
        // Stage 1: view fading out, but the window must stay (animation is
        // still playing) and the message must survive until fully hidden.
        await eventually(!service.visible)
        #expect(service.panelWanted)
        #expect(service.current != nil)
        await eventually(sleeper.parkedCount == 1)
        #expect(sleeper.slept == [2.0, 0.25])

        sleeper.resumeNext()
        await eventually(!service.panelWanted)
        #expect(service.current == nil)
        #expect(!service.visible)
    }

    @Test func laterToastReplacesAndCancelsTheOldSequence() async {
        let sleeper = ParkingSleeper()
        let service = ToastService(sleeper: sleeper)
        service.show(.success, "first")
        await eventually(sleeper.parkedCount == 1)
        service.show(.error, "second")
        #expect(service.current?.text == "second")
        #expect(service.visible)
        #expect(service.panelWanted)
        // Old sequence's visible-sleep (2.0) + new sequence's (3.5); the old
        // task never reaches its fade sleep.
        await eventually(sleeper.slept == [2.0, 3.5])
        #expect(sleeper.cancelledCount >= 1)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -project NemoLoop.xcodeproj -scheme NemoLoop -destination 'platform=macOS' -only-testing:NemoLoopTests/ToastServiceTests CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual 2>&1 | tail -5`
Expected: FAIL,编译错误 `cannot find 'ToastService' in scope`。

- [ ] **Step 3: 写最小实现**

```swift
// NemoLoop/Services/Toast/ToastService.swift
import SwiftUI

enum ToastKind { case success, error, info }

/// Testability seam for the dismiss timeline (the ChainSleeping pattern):
/// Task.sleep itself cannot be observed from tests.
@MainActor
protocol ToastSleeping: AnyObject {
    func sleep(seconds: TimeInterval) async throws
}

@MainActor
final class TaskToastSleeper: ToastSleeping {
    /// Nonisolated for default-argument construction (WorkspaceAppOpener idiom).
    nonisolated init() {}

    func sleep(seconds: TimeInterval) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }
}

/// Global toast channel: any module calls `ToastService.shared.show(...)` and
/// a black capsule appears bottom-center on the mouse's screen. Pure state
/// machine — windows are owned by ToastWindowController, so this is fully
/// testable headless.
///
/// Timeline (NemoNotch CompletionFlashService's validated pattern):
/// show() → current/visible/panelWanted immediately true → after
/// `toastDuration` (error: `errorDuration`) visible animates false → one
/// `fadeDuration` later panelWanted drops and current clears. panelWanted
/// deliberately falls LAST: the fading animation still needs the window.
@MainActor
@Observable
final class ToastService {
    static let shared = ToastService()

    struct Toast: Equatable {
        let kind: ToastKind
        let text: String
    }

    private(set) var current: Toast?
    private(set) var visible = false
    private(set) var panelWanted = false

    private let sleeper: any ToastSleeping
    private let toastDuration: TimeInterval
    private let errorDuration: TimeInterval
    private let fadeDuration: TimeInterval
    private var dismissTask: Task<Void, Never>?

    init(sleeper: any ToastSleeping = TaskToastSleeper(),
         toastDuration: TimeInterval = 2.0,
         errorDuration: TimeInterval = 3.5,
         fadeDuration: TimeInterval = 0.25) {
        self.sleeper = sleeper
        self.toastDuration = toastDuration
        self.errorDuration = errorDuration
        self.fadeDuration = fadeDuration
    }

    /// Later toast wins: replaces immediately and restarts the dismiss
    /// timeline (no queueing — only one capsule is ever on screen).
    func show(_ kind: ToastKind, _ text: String) {
        current = Toast(kind: kind, text: text)
        visible = true
        panelWanted = true
        restartDismiss(for: kind)
    }

    private func duration(for kind: ToastKind) -> TimeInterval {
        kind == .error ? errorDuration : toastDuration
    }

    private func restartDismiss(for kind: ToastKind) {
        dismissTask?.cancel()
        let wait = duration(for: kind)
        let fade = fadeDuration
        dismissTask = Task { @MainActor [weak self] in
            try? await self?.sleeper.sleep(seconds: wait)
            guard let self, !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: fade)) {
                self.visible = false
            }
            try? await self?.sleeper.sleep(seconds: fade)
            guard let self, !Task.isCancelled else { return }
            self.panelWanted = false
            self.current = nil
        }
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: 同 Step 2 命令。
Expected: PASS,4 条用例全绿。

- [ ] **Step 5: 提交**

```bash
git branch --show-current   # 必须是 feature/toast-service
git add NemoLoop/Services/Toast/ToastService.swift NemoLoopTests/ToastServiceTests.swift
git commit -m "feat(toast): ToastService 状态机(后到胜出+两段式消失,seam 可测)"
```

---

### Task 2: ToastView + ToastWindowController(定位数学 TDD)

**Files:**
- Create: `NemoLoop/Services/Toast/ToastView.swift`
- Create: `NemoLoop/Services/Toast/ToastWindowController.swift`
- Test: `NemoLoopTests/ToastWindowControllerTests.swift`

**Interfaces:**
- Consumes: Task 1 的 `ToastService`(current/visible/panelWanted、ToastKind)。
- Produces:
  - `struct ToastView: View`,`init(service: ToastService)`(Task 3 harness 直接用)
  - `@MainActor final class ToastWindowController`,`init(service: ToastService)`
  - `static func toastFrame(contentSize: NSSize, in visibleFrame: CGRect) -> NSRect`(纯函数,测试入口)

- [ ] **Step 1: 写失败的定位数学测试**

```swift
// NemoLoopTests/ToastWindowControllerTests.swift
import Testing
import Foundation
@testable import NemoLoop

struct ToastWindowControllerTests {
    @Test func centersHorizontallyAboveBottom() {
        let frame = ToastWindowController.toastFrame(
            contentSize: NSSize(width: 200, height: 44),
            in: CGRect(x: 0, y: 0, width: 1000, height: 800))
        #expect(frame == NSRect(x: 400, y: 72, width: 200, height: 44))
    }

    @Test func respectsNonZeroScreenOrigin() {
        // Secondary screens left of the primary have negative minX.
        let frame = ToastWindowController.toastFrame(
            contentSize: NSSize(width: 200, height: 44),
            in: CGRect(x: -1440, y: 0, width: 1440, height: 900))
        #expect(frame.origin.x == -1440 + (1440 - 200) / 2)
        #expect(frame.origin.y == 72)
    }

    @Test func usesContentHeight() {
        let frame = ToastWindowController.toastFrame(
            contentSize: NSSize(width: 300, height: 50),
            in: CGRect(x: 0, y: 0, width: 1000, height: 800))
        #expect(frame.height == 50)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -project NemoLoop.xcodeproj -scheme NemoLoop -destination 'platform=macOS' -only-testing:NemoLoopTests/ToastWindowControllerTests CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual 2>&1 | tail -5`
Expected: FAIL,`cannot find 'ToastWindowController' in scope`。

- [ ] **Step 3: 写 ToastView(完整代码)**

```swift
// NemoLoop/Services/Toast/ToastView.swift
import SwiftUI

/// Black-capsule toast: SF Symbol icon (semantic color by kind) + single-line
/// text. Fixed styling by design decision — deliberately NOT following the
/// RingPalette themes (system-HUD convention, strong contrast in both modes).
/// No Material anywhere: plain shape fill only.
struct ToastView: View {
    let service: ToastService

    var body: some View {
        ZStack {
            if let toast = service.current {
                capsule(for: toast)
                    .transition(.opacity.combined(with: .offset(y: 6)))
            }
        }
        // The animation itself is driven by ToastService's withAnimation so
        // the fade duration stays a service-level (injectable) constant.
    }

    private func capsule(for toast: ToastService.Toast) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon(toast.kind))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(iconColor(toast.kind))
            Text(toast.text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 18)
        .frame(height: 44)
        .fixedSize()
        .background(.black.opacity(0.85))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
    }

    private func icon(_ kind: ToastKind) -> String {
        switch kind {
        case .success: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        }
    }

    private func iconColor(_ kind: ToastKind) -> Color {
        switch kind {
        case .success: .green
        case .error: .red
        case .info: .white.opacity(0.7)
        }
    }
}
```

- [ ] **Step 4: 写 ToastWindowController(完整代码)**

```swift
// NemoLoop/Services/Toast/ToastWindowController.swift
import AppKit
import SwiftUI

/// Owns the single shared toast panel. Created once at app launch; observes
/// `service.panelWanted` (NOT `visible`): the window must stay on screen one
/// fade-duration longer than the view state, or the dismiss animation gets
/// cut off when the panel orders out.
@MainActor
final class ToastWindowController {
    private let service: ToastService
    private var panel: NSPanel?
    private var host: NSHostingView<ToastView>?

    init(service: ToastService) {
        self.service = service
        observe()
    }

    /// Pure positioning math (unit-tested): horizontal center of the screen's
    /// visible area, 72pt above its bottom edge — clears the Dock on any
    /// screen configuration.
    static func toastFrame(contentSize: NSSize, in visibleFrame: CGRect) -> NSRect {
        NSRect(x: visibleFrame.midX - contentSize.width / 2,
               y: visibleFrame.minY + 72,
               width: contentSize.width,
               height: contentSize.height)
    }

    private func observe() {
        withObservationTracking {
            _ = service.panelWanted
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                observe() // re-arm before applying so no change is missed
                apply()
            }
        }
    }

    private func apply() {
        if service.panelWanted {
            present()
        } else {
            panel?.orderOut(nil)
        }
    }

    private func present() {
        let screen = screenUnderMouse()
        if panel == nil {
            let panel = NSPanel(contentRect: .zero,
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false            // shadow drawn by ToastView
            panel.level = .screenSaver         // above the ring's .popUpMenu
            panel.ignoresMouseEvents = true    // pure notification, click-through
            panel.isMovable = false
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                        .ignoresCycle, .fullScreenAuxiliary]
            let host = NSHostingView(rootView: ToastView(service: service))
            host.wantsLayer = true
            host.layer?.backgroundColor = .clear
            panel.contentView = host
            self.panel = panel
            self.host = host
        }
        // Re-measure on every show: the capsule sizes to its content.
        guard let host, let panel else { return }
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        host.frame = NSRect(origin: .zero, size: size)
        panel.setFrame(Self.toastFrame(contentSize: size, in: screen.visibleFrame),
                       display: false)
        panel.orderFrontRegardless()
    }

    private func screenUnderMouse() -> NSScreen {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }
}
```

- [ ] **Step 5: 跑测试确认通过**

Run: 同 Step 2 命令(ToastWindowControllerTests),再全量跑一次 Task 1 的 ToastServiceTests。
Expected: 全 PASS(3 + 4 条)。

- [ ] **Step 6: 提交**

```bash
git branch --show-current   # 必须是 feature/toast-service
git add NemoLoop/Services/Toast/ToastView.swift NemoLoop/Services/Toast/ToastWindowController.swift NemoLoopTests/ToastWindowControllerTests.swift
git commit -m "feat(toast): 黑胶囊视图 + 共享面板控制器(panelWanted 晚一档撤窗)"
```

---

### Task 3: 渲染自查 harness

**Files:**
- Create: `Design/render_check_toast.swift`

**Interfaces:**
- Consumes: Task 1/2 的 `ToastService.swift` + `ToastView.swift`(真实源码逐字编译)。
- Produces: `Design/render_check_toast.png`;进程退出码 0=全过(后续 CI/回归可直接判定)。

- [ ] **Step 1: 写 harness(完整代码)**

自举模式照抄 `Design/render_check_plugin_subwheel.swift` 的头注释理由:`swift script.swift` 无法附带编译别的文件,脚本也不能 import app module,所以无 flag 时先把自己拷去临时 main.swift、连同真实源码一起 `xcrun swiftc` 编译再运行。

```swift
// Design/render_check_toast.swift
//
// Render-check harness for the global toast capsule (spec 2026-09-11).
// Compiles the REAL ToastService.swift + ToastView.swift verbatim via the
// self-bootstrapping xcrun-swiftc pattern (rationale in
// render_check_plugin_subwheel.swift's header).
//
// RUN (repo root):   swift Design/render_check_toast.swift
// OUTPUT: Design/render_check_toast.png (success/error/info rows over a dark
// stand-in). Prints one [CHECK] line per assertion + [VERDICT]; non-zero
// exit on any failure.
//
// Checks per kind: capsule pixels present (alpha), fill is black-dominant,
// icon region saturated (green/red), text region bright. Plus: a fresh
// service renders fully transparent (blank case).

import AppKit
import SwiftUI

// MARK: - Self-bootstrap (no-op when already the compiled harness binary)

func bootstrapIfNeeded() -> Int32? {
    guard !CommandLine.arguments.contains("--render-harness") else { return nil }
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("toast-harness-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    let main = tmp.appendingPathComponent("main.swift")
    try? FileManager.default.contents(atPath: CommandLine.arguments[0])?
        .write(to: main)
    let binary = tmp.appendingPathComponent("toast-harness")
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    proc.arguments = ["swiftc", "-o", binary.path, main.path,
                      "NemoLoop/Services/Toast/ToastService.swift",
                      "NemoLoop/Services/Toast/ToastView.swift"]
    proc.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    // CWD must be the repo root both when compiling and when the binary runs.
    try? proc.run(); proc.waitUntilExit()
    guard proc.terminationStatus == 0 else { return proc.terminationStatus }
    let run = Process()
    run.executableURL = binary
    run.arguments = ["--render-harness"]
    run.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    try? run.run(); run.waitUntilExit()
    return run.terminationStatus
}

if let code = bootstrapIfNeeded() { exit(code) }

// MARK: - Render (we are the compiled binary now)

@MainActor
enum Harness {
    static let scale: Int = 2
    static var failures = 0

    static func check(_ name: String, _ ok: Bool, _ detail: String) {
        print("[CHECK] \(ok ? "ok" : "FAIL")  \(name) — \(detail)")
        if !ok { failures += 1 }
    }

    /// Renders one toast over a transparent canvas; 60s durations so no
    /// dismiss can fire mid-render.
    static func render(_ kind: ToastKind, _ text: String) -> (NSBitmapImageRep, NSRect) {
        let service = ToastService(toastDuration: 60, errorDuration: 60, fadeDuration: 60)
        service.show(kind, text)
        let view = ToastView(service: service)
            .frame(width: 480, height: 60)
        let renderer = ImageRenderer(content: view)
        renderer.scale = Double(scale)
        let image = renderer.nsImage!
        var rect = NSRect(x: 0, y: 0, width: image.size.width, height: image.size.height)
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        _ = rect; rect = NSRect(origin: .zero, size: NSSize(width: rep.pixelsWide, height: rep.pixelsHigh))
        return (rep, rect)
    }

    /// RGBA8 pixel stats over the whole bitmap.
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
            let (rep, _) = render(kind, text)
            let (a, k, s, br) = stats(rep)
            check("\(label)-capsule-present", a > 2000, "alphaOn=\(a)")
            check("\(label)-fill-black", k > a * 7 / 10, "black=\(k)/\(a)")
            if kind != .info {
                check("\(label)-icon-colored", s > 30, "saturated=\(s)")
            }
            check("\(label)-text-bright", br > 200, "bright=\(br)")
            rows.append(NSImage(cgImage: rep.cgImage!, size: rep.size))
        }

        // Compose the PNG artifact (labels + the three rows).
        let compose = VStack(spacing: 12) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                row.resizable().frame(width: 480, height: 60)
            }
        }
        .padding(20)
        .background(Color(white: 0.10))
        let cr = ImageRenderer(content: compose)
        cr.scale = Double(scale)
        let data = cr.nsImage!.tiffRepresentation!
        let out = NSBitmapImageRep(data: data)!
        try? out.representation(using: .png, properties: [:])?
            .write(to: URL(fileURLWithPath: "Design/render_check_toast.png"))

        print(failures == 0 ? "[VERDICT] all checks passed" : "[VERDICT] \(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}

// The AppKit render path needs a live runloop (project convention: NSApp.run()).
let app = NSApplication.shared
DispatchQueue.main.async { Task { @MainActor in Harness.run(); NSApp.terminate(nil) } }
app.run()
```

注意:编写时若 `render` 里 `NSRect`/`rect` 的两行兜底显得多余可化简;像素阈值是初判值,**断言失败时先看打印的实测数再定**:视图确实渲染错→修 ToastView;只是阈值压线→微调阈值并在 commit message 里写明依据。[CHECK] 名称保持不变(spec 验收就这五类)。

- [ ] **Step 2: 跑 harness**

Run(仓库根目录):`swift Design/render_check_toast.swift`
Expected: 9 条 `[CHECK] ... ok`(blank 1 + 每种 kind 3~4 条)+ `[VERDICT] all checks passed`,退出码 0;生成 `Design/render_check_toast.png`。任何 FAIL 先修 ToastView 再继续。

- [ ] **Step 3: 目视 PNG**

用 Read 工具打开 `Design/render_check_toast.png`:三种胶囊齐全、图标绿/红/灰白、文字清晰、深底上对比度足够。用户视觉验收以这张图为准。

- [ ] **Step 4: 提交**

```bash
git branch --show-current   # 必须是 feature/toast-service
git add Design/render_check_toast.swift Design/render_check_toast.png
git commit -m "test(toast): 渲染自查 harness(五类像素断言+PNG 产物)"
```

---

### Task 4: 三个接入点(PluginRegistry / ChainExecutor / OCR 迁移)

**Files:**
- Modify: `NemoLoop/Services/PluginRegistry.swift`(perform 的两个失败分支)
- Modify: `NemoLoop/Plugins/Chain/ChainExecutor.swift`(run 的步骤失败分支)
- Modify: `NemoLoop/Services/Ocr/OcrSessionController.swift`(删私有 toast,三处调用换 ToastService)

**Interfaces:**
- Consumes: Task 1 的 `ToastService.shared.show(_:_:)`。
- Produces: 无新接口(行为变更:失败路径现在有用户可见反馈)。现有 184 个测试只断言返回值/日志行为,不回归。

- [ ] **Step 1: PluginRegistry.perform 两个失败分支加 toast**

在 `perform(pluginID:opID:)` 中,两个 `guard ... else { NSLog(...); return false }` 改为 NSLog 后、return 前各加一行(两分支同文案,spec 勘误后的英文):

```swift
        guard isEnabled(pluginID) else {
            NSLog("NemoLoop plugin: op \(pluginID).\(opID) skipped — plugin disabled")
            ToastService.shared.show(.error, "Action unavailable: plugin disabled or removed")
            return false
        }
        guard let op = op(pluginID: pluginID, opID: opID) else {
            NSLog("NemoLoop plugin: unknown op \(pluginID).\(opID)")
            ToastService.shared.show(.error, "Action unavailable: plugin disabled or removed")
            return false
        }
```

- [ ] **Step 2: ChainExecutor.run 步骤失败加 toast**

`run(_:)` 的失败分支(该文件的 `guard performStep(step) else { ... }`)改为:

```swift
                guard performStep(step) else {
                    NSLog("NemoLoop chain: step \(index + 1) failed — chain '\(chain.name)' aborted")
                    ToastService.shared.show(.error,
                        "Chain '\(chain.name)' failed at step \(index + 1) — aborted")
                    return
                }
```

「重复触发忽略」分支**不动**(spec:刻意不吵)。`performStep` 内部的 open 失败 NSLog 保留——run 层的 toast 已覆盖该场景。

- [ ] **Step 3: OCR 迁移(删私有实现,三处调用改服务)**

`OcrSessionController.swift`:
1. 删除属性:`private var toastPanel: NSPanel?` 与 `private var toastTimer: Timer?`
2. 删除整个 `// MARK: - Toast` 段(`showToast(_:)` 函数体)
3. 三处调用点替换(kind 映射按 spec):

```swift
ToastService.shared.show(.success, "Snipped to clipboard")     // 原 showToast("Snipped to clipboard")
ToastService.shared.show(.info, "No text recognized")          // 原 showToast("No text recognized")
ToastService.shared.show(.error, "OCR failed: \(detail)")      // 原 showToast("OCR failed: \(detail)")
```

4. `screenUnderMouse()` **保留**(权限面板仍在用)。

- [ ] **Step 4: 全量测试回归**

Run: Global Constraints 里的完整单测命令。
Expected: 全 PASS(原 184 条 + Task 1/2 新增 7 条;toast 是 fire-and-forget 副作用,不影响任何现有断言)。

- [ ] **Step 5: 提交**

```bash
git branch --show-current   # 必须是 feature/toast-service
git add NemoLoop/Services/PluginRegistry.swift NemoLoop/Plugins/Chain/ChainExecutor.swift NemoLoop/Services/Ocr/OcrSessionController.swift
git commit -m "feat(toast): 接入插件失败/链中断,OCR 私有 toast 迁入统一服务"
```

---

### Task 5: AppDelegate 挂载 + --toast-test 验证口 + 构建启动验看

**Files:**
- Modify: `NemoLoop/App/AppDelegate.swift`

**Interfaces:**
- Consumes: Task 2 的 `ToastWindowController(service:)`、Task 1 的 `ToastService.shared`。
- Produces: `--toast-test` 启动参数(启动 2s 后弹 error toast),沿用 `--settings` / `--ocr-test` 的验证口惯例。

- [ ] **Step 1: 挂载控制器 + 验证口**

`AppDelegate` 加属性(与 `menuBarController` 同组):

```swift
    private var toastWindowController: ToastWindowController?
```

`applicationDidFinishLaunching` 中,`gamepad` 段之后、`MenuBarPanelController` 段之前插入:

```swift
        let toast = ToastWindowController(service: .shared)
        self.toastWindowController = toast
```

文件末尾(与 `--ocr-test` 段并列)加:

```swift
        // Verification affordance: pop one error toast 2s after launch.
        if CommandLine.arguments.contains("--toast-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                ToastService.shared.show(.error, "Toast test: mouse screen, bottom center")
            }
        }
```

- [ ] **Step 2: 全量测试回归(确认无破坏)**

Run: Global Constraints 里的完整单测命令。
Expected: 全 PASS。

- [ ] **Step 3: 构建 Debug 版(NemoLoopDev 签名,勿用通配路径)**

```bash
pkill -x NemoLoop
xcodebuild build -project NemoLoop.xcodeproj -scheme NemoLoop -configuration Debug -destination 'platform=macOS' ENABLE_DEBUG_DYLIB=NO CODE_SIGN_IDENTITY="NemoLoopDev" DEVELOPMENT_TEAM="" CODE_SIGN_STYLE=Manual 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`。(ENABLE_DEBUG_DYLIB=NO 是项目实证过的唯一不崩组合:Debug dylib 在自签下过不了库验证。)

- [ ] **Step 4: 启动验看**

先定位精确 DerivedData(**严禁 `NemoLoop-*` 通配**——本机有一个旧 worktree 的 ffnxo 目录,通配会开错版本):

```bash
APP="$(ls -d ~/Library/Developer/Xcode/DerivedData/NemoLoop-*/Build/Products/Debug/NemoLoop.app | grep -v ffnxo | head -1)"
open "$APP" --args --toast-test
```

验看清单(2s 后):
1. 鼠标所在屏、屏幕下方居中出现黑色 error 胶囊,红色三角图标 + 白字
2. 约 3.5s 后淡出消失,无残影
3. 胶囊出现时用鼠标点它 → 点击穿透到底下的窗口
4. 把鼠标移到另一块屏再触发一次(可再 `open "$APP" --args --toast-test` 前先 pkill)→ toast 跟着鼠标屏走

- [ ] **Step 5: 提交**

```bash
git branch --show-current   # 必须是 feature/toast-service
git add NemoLoop/App/AppDelegate.swift
git commit -m "feat(toast): AppDelegate 挂载 + --toast-test 验证口"
```

---

### Task 6: 收尾(全量回归 + spec 状态)

**Files:**
- Modify: `docs/superpowers/specs/2026-09-11-toast-service-design.md`(仅状态行)

- [ ] **Step 1: 全量测试最后一遍**

Run: Global Constraints 里的完整单测命令。
Expected: 全 PASS,数量 = Task 4 Step 4 时相同 + 0(本任务不加测试)。

- [ ] **Step 2: spec 状态行更新**

把 spec 首行 `状态:已与用户逐节确认(四拍板),待审阅。` 改为 `状态:已实施(feature/toast-service),验收通过待合并。`

- [ ] **Step 3: 提交**

```bash
git branch --show-current   # 必须是 feature/toast-service
git add docs/superpowers/specs/2026-09-11-toast-service-design.md
git commit -m "docs(toast): spec 状态更新为已实施"
```

- [ ] **Step 4: 汇报**

向用户汇报:测试计数、渲染 PNG 路径、--toast-test 实拍结论、分支状态;并列出 spec 实机验收中**待用户执行**的两项:触发含禁用插件步骤的链看 error 胶囊、OCR 截图看 success 胶囊(含全屏 app 上触发仍可见)。**不要自行合并 develop、不要跑 build.sh**——合并与安装版重建由用户在验收后决定(项目惯例:合并后必须重跑 build.sh)。
