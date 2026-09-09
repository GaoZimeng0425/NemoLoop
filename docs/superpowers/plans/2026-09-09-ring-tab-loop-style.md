# Ring 标签 Loop 式改造实现计划（Mini-Ring Inspector + 行内选择器）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ring 标签获得 Loop 式交互：右栏常驻真实 mini 环预览（悬停发牌/空闲轮播/点空槽直配）+ 槽位行嵌套菜单换成点击式搜索选择器 popover。

**Architecture:** 复用现有 `RingView`/`RingViewModel`（加 `isSettingsPreview` 关闭全局采样，坐标空间自洽——begin 的 center 与 updatePointer 的点都用 inspector 本地坐标）；选择器是纯数据模型（`ActionPickerModel` 分区+打分）+ 原生 `.popover` 视图；窗口加宽经 `SettingsChrome.inspectorVisible` 的 didSet 回调驱动 `SettingsWindowController` 动画改宽。

**Tech Stack:** Swift 6 / SwiftUI+AppKit / Luminare 0.2.0（**不升级**）/ swift-testing。无新依赖。

**Spec:** `docs/superpowers/specs/2026-09-09-ring-tab-loop-style-design.md`（实现时 spec 与本计划同读）

**计划内裁定（对 spec 的一处修正）:** spec 写 `luminarePopover 300×360`——实测 Luminare 0.2.0 的 popover 只有 `.hover`/`.forceTouch` 触发（无点击触发，那是 Loop 私有 fork 的能力）。改用原生 SwiftUI `.popover(isPresented:)`（点击语义、锚定弹出来源行/扇叶），内容仍是 Luminare 组件（LuminareTextField + LuminareList + 材质卡片），尺寸 300×360 不变。spec 的交互意图（点击弹出、搜索、分区）逐条保留。

## Global Constraints

- 单测命令（ad-hoc 签名，worktree 根目录执行）：
  `xcodebuild test -project NemoLoop.xcodeproj -scheme NemoLoop -destination 'platform=macOS' -only-testing:NemoLoopTests CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual`（迭代时加 `-only-testing:NemoLoopTests/<StructName>`；提交前必须全量绿）。
- Xcode 工程 file-system-synchronized groups——新文件免工程配置。**Design/ 目录在三个 target 之外**，渲染脚本放那里不影响 app 构建。
- UI 字符串英文；注释解释"为什么"，口吻对照 `NemoLoop/Services/SystemActions.swift`。
- Luminare 锁 0.2.0，禁止升级/换 fork。
- 已有可复用锚点：`RingView(icons:viewModel:subicons:dimmed:preAppeared:)`（`RingView.swift:34`，读 `\.`ringCenter` 环境）；`RingViewModel.begin(centerGlobal:wedgeCount:childrenCounts:input:)`/`updatePointer(at:now:)`/`openSubIndex`（`RingViewModel.swift:56,113`，`now` 可注入 `:46`）；`RingGeometry.wedgeIndex(from:to:layout:deadZoneRadius:outerRadius:)`（`RingGeometry.swift:60`）；`BladeLayout.forCount(_:)`/`centerAngle(_:)`（`RingGeometry.swift:28,37`）；`SliceStore.icons/childIcons`（快照）与 `SliceStore.isEnabled(_:)`；`PluginRegistry.shared`；`attachWholePlugin(_:at:registry:)`。
- 每任务收尾：全量单测绿 + commit（worktree 内）。

---

### Task 1: AppScanner——已装 app 扫描服务

**Files:**
- Create: `NemoLoop/Services/AppScanner.swift`
- Test: `NemoLoopTests/AppScannerTests.swift`

**Interfaces:**
- Produces: `struct AppEntry: Identifiable, Equatable { let id: String /* bundle id 或路径 */; let name: String; let url: URL }`（icon 由视图层经 `NSWorkspace.shared.icon(forFile:)` 现取，不入模型——可测试性）；`@MainActor enum AppScanner { static func scan(dirs: [URL], workspace: WorkspaceDescribing = NSWorkspace.shared) -> [AppEntry]; static func defaultDirs() -> [URL] }`。`protocol WorkspaceDescribing { func urlsForApplications(withConfiguration:) throws -> [URL]; func displayName(forFile:) -> String? }`——NSWorkspace 桥接，测试注入假件。

- [ ] **Step 1: 写失败测试**

```swift
// NemoLoopTests/AppScannerTests.swift
import Testing
import Foundation
@testable import NemoLoop

struct AppScannerTests {
    /// FileManager-driven fake: lists .app bundles under fixture dirs.
    private func makeFixture(_ names: [String]) -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("app-scanner-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for name in names {
            let appDir = root.appendingPathComponent("\(name).app")
            try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        }
        return root
    }

    private final class FakeWorkspace: WorkspaceDescribing {
        var displayNames: [String: String] = [:]
        func urlsForApplications(withConfiguration configuration: NSWorkspace.OpenConfiguration?) throws -> [URL] { [] }
        func displayName(forFile path: String) -> String? { displayNames[path] }
    }

    @Test func scansAppBundlesWithLocalizedNamesSorted() {
        let dir = makeFixture(["Zeplin", "Safari", "Notes"])
        let ws = FakeWorkspace()
        ws.displayNames[dir.appendingPathComponent("Safari.app").path] = "Safari"
        ws.displayNames[dir.appendingPathComponent("Notes.app").path] = "备忘录"
        ws.displayNames[dir.appendingPathComponent("Zeplin.app").path] = "Zeplin"

        let entries = AppScanner.scan(dirs: [dir], workspace: ws)
        #expect(entries.map(\.name) == ["Safari", "Zeplin", "备忘录"]) // 按本地化名排序
        #expect(entries.allSatisfy { $0.url.pathExtension == "app" })
        #expect(entries.allSatisfy { $0.id.contains(".app") }) // 无 bundle id 时以路径为 id
    }

    @Test func dedupesAcrossDirsByPath() {
        let a = makeFixture(["Safari"])
        let b = makeFixture(["Safari"])   // 同名不同目录 → 两条都保留（路径不同）
        let entries = AppScanner.scan(dirs: [a, b])
        #expect(entries.filter { $0.name == "Safari" }.count == 2)
    }

    @Test func skipsNonAppBundles() {
        let dir = makeFixture(["Good"])
        try? FileManager.default.createDirectory(
            at: dir.appendingPathComponent("README.txt"), withIntermediateDirectories: true)
        let entries = AppScanner.scan(dirs: [dir])
        #expect(entries.count == 1)
    }

    @Test func defaultDirsCoverBothApplicationRoots() {
        let dirs = AppScanner.defaultDirs()
        #expect(dirs.contains(URL(filePath: "/Applications")))
        #expect(dirs.contains(URL(filePath: "\(NSHomeDirectory())/Applications")))
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: 全量命令 + `-only-testing:NemoLoopTests/AppScannerTests`
Expected: FAIL —— `cannot find 'AppScanner' in scope`。

- [ ] **Step 3: 最小实现**

```swift
// NemoLoop/Services/AppScanner.swift
import AppKit
import Foundation

/// One launchable app found on disk. Icons are NOT captured here — the view
/// layer resolves them via NSWorkspace so the model stays testable.
struct AppEntry: Identifiable, Equatable {
    let id: String          // bundleIdentifier when available, else path
    let name: String        // localized display name, falls back to filename
    let url: URL
}

/// NSWorkspace seam — the scanner only needs these two calls.
protocol WorkspaceDescribing {
    func displayName(forFile path: String) -> String?
}

extension NSWorkspace: WorkspaceDescribing {}

@MainActor
enum AppScanner {
    /// Scans the given directories one level deep for .app bundles, dedupes
    /// by id (bundle id or path), sorts by localized name. Called once when
    /// the picker first opens; the caller caches.
    static func scan(dirs: [URL], workspace: WorkspaceDescribing = NSWorkspace.shared) -> [AppEntry] {
        var seen = Set<String>()
        var entries: [AppEntry] = []
        let fm = FileManager.default
        for dir in dirs {
            guard let children = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for url in children where url.pathExtension == "app" {
                let name = workspace.displayName(forFile: url.path)
                    ?? url.deletingPathExtension().lastPathComponent
                let id = Bundle(url: url)?.bundleIdentifier ?? url.path
                guard seen.insert(id).inserted else { continue }
                entries.append(AppEntry(id: id, name: name, url: url))
            }
        }
        return entries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func defaultDirs() -> [URL] {
        [URL(filePath: "/Applications"), URL(filePath: "\(NSHomeDirectory())/Applications")]
    }
}
```

（若 `Bundle(url:)` 在测试 fixture 下返回 nil，路径 id 兜底已覆盖——测试断言的就是路径 id。）

- [ ] **Step 4: 跑全部单测确认绿**

Run: 全量命令
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add NemoLoop/Services/AppScanner.swift NemoLoopTests/AppScannerTests.swift
git commit -m "feat(settings): app scanner for the action picker"
```

---

### Task 2: ActionPickerModel——选择器数据模型（分区+搜索打分）

**Files:**
- Create: `NemoLoop/Services/ActionPickerModel.swift`
- Test: `NemoLoopTests/ActionPickerModelTests.swift`

**Interfaces:**
- Consumes: Task 1 的 `AppEntry`；`PluginRegistry`（`plugin(id:)`/`op(pluginID:opID:)`/`isEnabled`）；`SlotAction`。
- Produces:
  - `enum PickerContext { case mainSlot, subSlot }`（subSlot 无整挂项）
  - `struct PickerItem: Identifiable, Equatable { enum Kind: Equatable { case browseApps; case browseFolder; case wholePlugin(String); case op(pluginID: String, opID: String); case app(AppEntry) }; let id: String; let kind: Kind; let title: String; let subtitle: String?; let symbolName: String? }`
  - `@MainActor struct ActionPickerModel { init(apps: [AppEntry], registry: PluginRegistry = .shared); func sections(context: PickerContext, query: String) -> [PickerSection]; var connectedPluginFootnote: String }`
  - `struct PickerSection: Equatable { let title: String; let items: [PickerItem] }`（空 section 不出现）
  - `enum PickerSearch { static func score(query: String, name: String) -> Int? }`——0 前缀 / 1 包含 / 2 子序列 / nil 不匹配（Loop 同款）

- [ ] **Step 1: 写失败测试**

```swift
// NemoLoopTests/ActionPickerModelTests.swift
import Testing
import Foundation
@testable import NemoLoop

@MainActor
struct ActionPickerModelTests {
    private func makeModel(connectedSystem: Bool = true) -> ActionPickerModel {
        let defaults = UserDefaults(suiteName: "picker-tests-\(UUID().uuidString)")!
        let registry = PluginRegistry(defaults: defaults, plugins: [SystemPlugin(), AppearancePlugin()])
        if connectedSystem { try? Task.sync { try await registry.setEnabled("system", true) } }
        // Appearance 留未连接——过滤路径要验证它。
        let apps = [AppEntry(id: "com.apple.Safari", name: "Safari",
                             url: URL(filePath: "/Applications/Safari.app")),
                    AppEntry(id: "com.apple.Terminal", name: "Terminal",
                             url: URL(filePath: "/Applications/Terminal.app"))]
        return ActionPickerModel(apps: apps, registry: registry)
    }

    @Test func mainSlotSectionsAppsThenConnectedPluginsThenFolders() {
        let model = makeModel()
        let sections = model.sections(context: .mainSlot, query: "")
        #expect(sections.map(\.title) == ["Apps", "Plugins", "Folders"])
        let apps = sections[0].items
        #expect(apps.map(\.title) == ["Safari", "Terminal"])
        #expect(apps.last?.kind == .browseApps)          // Browse… 收尾

        let plugins = sections[1].items
        #expect(plugins.first?.kind == .wholePlugin("system"))   // 整挂领头
        #expect(plugins.first?.subtitle == "5 actions")
        #expect(plugins.contains { $0.kind == .op(pluginID: "system", opID: "lockScreen") })
        #expect(!plugins.contains { $0.kind == .wholePlugin("appearance") }) // 未连接不出现
        #expect(plugins.contains { $0.kind == .op(pluginID: "system", opID: "ocr") })

        #expect(sections[2].items.map(\.kind) == [.browseFolder])
    }

    @Test func subSlotContextDropsWholePluginEntries() {
        let model = makeModel()
        let sections = model.sections(context: .subSlot, query: "")
        let plugins = sections.first { $0.title == "Plugins" }!
        #expect(!plugins.items.contains { if case .wholePlugin = $0.kind { return true }; return false })
        #expect(plugins.items.contains { $0.kind == .op(pluginID: "system", opID: "sleep") })
    }

    @Test func searchFiltersAcrossSectionsByScore() {
        let model = makeModel()
        let sections = model.sections(context: .mainSlot, query: "sa")
        let titles = sections.flatMap(\.items).map(\.title)
        #expect(titles.contains("Safari"))          // 前缀 0
        #expect(!titles.contains("Terminal"))
        // “sa” 也是 "Sleep Displays"? 不——按 title 匹配；“Safari” 唯一命中即可。
        #expect(titles.filter { $0 == "Safari" }.count == 1)
    }

    @Test func emptyQueryShowsEverythingUnfiltered() {
        let model = makeModel()
        let all = model.sections(context: .mainSlot, query: "").flatMap(\.items)
        #expect(all.count >= 2 + 1 + 6 + 1)   // 2 app + browse + 1 whole + 5 ops + folder
    }
}

/// 测试辅助：同步等待 async setEnabled（仅测试 target）。
extension Task where Success == Void, Failure == Never {
    static func sync(priority: TaskPriority = .userInitiated, _ body: @MainActor @Sendable () async throws -> Void) rethrows {
        let semaphore = DispatchSemaphore(value: 0)
        Task(priority: priority) { try? await body(); semaphore.signal() }
        semaphore.wait()
    }
}
```

> 注意：`Task.sync` 伪代码仅为示意——swift-testing 的 `@Test func` 可以直接 `async throws`，把 `makeModel` 改成 `async throws` 并 `try await registry.setEnabled(...)` 更干净。落地时按后者写，不要 semaphore。

- [ ] **Step 2: 跑测试确认失败**

Run: 全量命令 + `-only-testing:NemoLoopTests/ActionPickerModelTests`
Expected: FAIL —— `cannot find 'ActionPickerModel' in scope`。

- [ ] **Step 3: 最小实现**

```swift
// NemoLoop/Services/ActionPickerModel.swift
import Foundation

/// Where the picker is being used — sub-slots have no whole-plugin mounting.
enum PickerContext {
    case mainSlot
    case subSlot
}

struct PickerItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case browseApps
        case browseFolder
        case wholePlugin(String)
        case op(pluginID: String, opID: String)
        case app(AppEntry)
    }
    let id: String
    let kind: Kind
    let title: String
    let subtitle: String?
    let symbolName: String?
}

struct PickerSection: Equatable {
    let title: String
    let items: [PickerItem]
}

/// Loop's three-tier match scoring: prefix beats contains beats subsequence.
enum PickerSearch {
    static func score(query: String, name: String) -> Int? {
        let q = query.lowercased(), n = name.lowercased()
        guard !q.isEmpty else { return 0 }
        if n.hasPrefix(q) { return 0 }
        if n.contains(q) { return 1 }
        // Subsequence: every query char appears in order.
        var qi = q.startIndex
        for char in n where qi < q.endIndex && char == q[qi] { qi = q.index(after: qi) }
        return qi == q.endIndex ? 2 : nil
    }
}

@MainActor
struct ActionPickerModel {
    let apps: [AppEntry]
    let registry: PluginRegistry

    var connectedPluginFootnote: String {
        "Plugins not listed are disconnected — connect them in the Plugins tab."
    }

    func sections(context: PickerContext, query: String) -> [PickerSection] {
        var sections: [PickerSection] = []

        var appItems = apps.map { entry in
            PickerItem(id: "app:\(entry.id)", kind: .app(entry), title: entry.name, subtitle: nil, symbolName: nil)
        }
        appItems.append(PickerItem(id: "browse:apps", kind: .browseApps, title: "Browse…",
                                   subtitle: nil, symbolName: "folder.badge.plus"))
        sections.append(PickerSection(title: "Apps", items: filtered(appItems, query: query)))

        var pluginItems: [PickerItem] = []
        for plugin in registry.plugins where registry.isEnabled(plugin.id) {
            if context == .mainSlot {
                pluginItems.append(PickerItem(
                    id: "whole:\(plugin.id)", kind: .wholePlugin(plugin.id),
                    title: plugin.displayName,
                    subtitle: "\(plugin.operations.count) action\(plugin.operations.count == 1 ? "" : "s")",
                    symbolName: plugin.symbolName))
            }
            for op in plugin.operations {
                pluginItems.append(PickerItem(
                    id: "op:\(plugin.id):\(op.id)", kind: .op(pluginID: plugin.id, opID: op.id),
                    title: op.displayName, subtitle: plugin.displayName, symbolName: op.symbolName))
            }
        }
        if !pluginItems.isEmpty {
            sections.append(PickerSection(title: "Plugins", items: filtered(pluginItems, query: query)))
        }

        let folders = [PickerItem(id: "browse:folder", kind: .browseFolder, title: "Browse Folder…",
                                  subtitle: nil, symbolName: "folder")]
        sections.append(PickerSection(title: "Folders", items: filtered(folders, query: query)))

        return sections.filter { !$0.items.isEmpty }
    }

    /// Keeps section order, filters by best score, sorts within by (score, title).
    private func filtered(_ items: [PickerItem], query: String) -> [PickerItem] {
        guard !query.isEmpty else { return items }
        return items.compactMap { item -> (PickerItem, Int)? in
            guard let score = PickerSearch.score(query: query, name: item.title) else { return nil }
            return (item, score)
        }
        .sorted { lhs, rhs in
            lhs.1 != rhs.1 ? lhs.1 < rhs.1 : lhs.0.title.localizedCaseInsensitiveCompare(rhs.0.title) == .orderedAscending
        }
        .map(\.0)
    }
}
```

- [ ] **Step 4: 跑全部单测确认绿**

Run: 全量命令
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add NemoLoop/Services/ActionPickerModel.swift NemoLoopTests/ActionPickerModelTests.swift
git commit -m "feat(settings): action picker model — sections, connected filter, tiered search"
```

---

### Task 3: RingViewModel.isSettingsPreview——关闭全局鼠标采样

**Files:**
- Modify: `NemoLoop/Ring/RingViewModel.swift`（`sample()` 与 `begin` 附近）
- Test: `NemoLoopTests/RingPreviewTests.swift`

**Interfaces:**
- Produces: `RingViewModel` 增 `var isSettingsPreview = false`（默认 false，真环零变化）；`sample()` 在 `isSettingsPreview == true` 时直接 return（该函数当前在计时器里读 `NSEvent.mouseLocation`，预览不容许它抢输入）。

- [ ] **Step 1: 写失败测试**

```swift
// NemoLoopTests/RingPreviewTests.swift
import Testing
import Foundation
import CoreGraphics
@testable import NemoLoop

@MainActor
struct RingPreviewTests {
    @Test func previewSampleIsInertWhileRealRingStillSamples() {
        // 预览模式：采样被禁用——即便真鼠标在别处，悬停态只由显式 updatePointer 决定。
        let vm = RingViewModel()
        vm.isSettingsPreview = true
        vm.begin(centerGlobal: .zero, wedgeCount: 6, input: .vector(deadZone: 36) { .zero })
        vm.sample()
        #expect(vm.selection == nil)   // 没有显式喂点，什么都不选

        // 显式喂点照常生效（T9 已证路径，回归保护）。
        vm.updatePointer(at: CGPoint(x: 0, y: 80), now: Date())
        XCTAssertNotNil(vm.selection)  // 若 selection 非 Optional，用对应 hover 断言
    }
}
```

> 落地时按 `RingViewModel` 真实 API 调整断言（`selection` 的可选性/`hoveredSubIndex` 等），意图不变：**preview 下 sample() 无副作用；updatePointer 显式驱动照常**。第二段断言若与 API 不符（如 selection 恒非 nil），改断 `vm.selection.index == 0` 之类等价事实，并在测试注释说明。

- [ ] **Step 2: 跑测试确认失败**

Run: 全量命令 + `-only-testing:NemoLoopTests/RingPreviewTests`
Expected: FAIL —— `isSettingsPreview` 不存在。

- [ ] **Step 3: 最小实现**

```swift
// RingViewModel —— 存储属性区（input/now 旁）加：
/// Settings-inspector mode: no global mouse sampling (NSEvent.mouseLocation),
/// input arrives exclusively from explicit updatePointer calls (SwiftUI
/// gestures + carousel). The real ring leaves this false.
var isSettingsPreview = false

// sample() 顶部加：
func sample() {
    guard !isSettingsPreview else { return }
    // …现有实现不动…
}
```

- [ ] **Step 4: 跑全部单测确认绿**

Run: 全量命令（`RingViewModelCancelTests`/`RingSubWheelTests` 必须不受影响——默认 false 路径零变化）
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add NemoLoop/Ring/RingViewModel.swift NemoLoopTests/RingPreviewTests.swift
git commit -m "feat(ring): isSettingsPreview flag disables global mouse sampling"
```

---

### Task 4: RingSnapshot 快照助手 + RingTabInspector 视图（mini 环 + 轮播 + 手势）

**Files:**
- Create: `NemoLoop/Ring/RingSnapshot.swift`
- Create: `NemoLoop/Settings/RingTabInspector.swift`
- Modify: `NemoLoop/Ring/RingSummoner.swift:70-86`（换用 RingSnapshot，行为零变化）
- Test: `NemoLoopTests/RingSnapshotTests.swift`

**Interfaces:**
- Consumes: Task 3 的 `isSettingsPreview`；`SliceStore.icons/childIcons/isEnabled`；`RingView`/`RingGeometry`/`BladeLayout`/`RingTheme`。
- Produces:
  - `struct RingSnapshot: Equatable { let icons: [NSImage?]; let subicons: [[NSImage?]]; let dimmed: [Bool]; let childrenCounts: [Int]; @MainActor static func make(store: SliceStore) -> RingSnapshot }`——把 Summoner 里内联拼四件套的逻辑抽出来，两端共用
  - `struct RingTabInspector: View { init(store: SliceStore, selectedSlot: Binding<Int?>, configureSlot: (Int) -> Void) }`——`configureSlot` 由父层接 popover（空槽点击直配）；内部 `@State private var carousel: CarouselDriver?` 走 Timer

- [ ] **Step 1: 写失败测试（快照部分）**

```swift
// NemoLoopTests/RingSnapshotTests.swift
import Testing
import Foundation
@testable import NemoLoop

@MainActor
struct RingSnapshotTests {
    private func makeStore() -> SliceStore {
        let name = "ring-snapshot-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return SliceStore(defaults: d)
    }

    @Test func snapshotMirrorsStoreArrays() {
        let store = makeStore()
        store.setAction(.app(URL(filePath: "/Applications/Safari.app")), at: 0)
        store.addChild(.pluginOp(pluginID: "system", opID: "lockScreen"), at: 0)
        store.setAction(.plugin("system"), at: 1)

        let snap = RingSnapshot.make(store: store)
        #expect(snap.icons.count == 6)
        #expect(snap.icons[0] != nil && snap.icons[1] != nil && snap.icons[2] == nil)
        #expect(snap.childrenCounts[0] == 1)
        #expect(snap.dimmed[0] == false)   // app 槽永亮
        #expect(snap.dimmed[1] == false)   // system 已连接（出厂默认）
        #expect(snap.subicons[0].count == 1)
    }
}
```

（`NSImage` 非 Equatable——`RingSnapshot` 的 Equatable 只比 `dimmed`/`childrenCounts` 与 icons 的 nil 模式：手写 `==` 比较 `icons.map { $0 == nil }` 与 subicons 的计数。）

- [ ] **Step 2: 跑测试确认失败**

Run: 全量命令 + `-only-testing:NemoLoopTests/RingSnapshotTests`
Expected: FAIL —— `RingSnapshot` 不存在。

- [ ] **Step 3: 实现 RingSnapshot + 改 Summoner**

```swift
// NemoLoop/Ring/RingSnapshot.swift
import AppKit

/// The value-type payload a ring render needs, captured from the store at
/// summon (or settings-preview render) time. Icon identity stability is the
/// store's job (see SliceStore.icons) — this only packages.
struct RingSnapshot {
    let icons: [NSImage?]
    let subicons: [[NSImage?]]
    let dimmed: [Bool]
    let childrenCounts: [Int]

    @MainActor
    static func make(store: SliceStore) -> RingSnapshot {
        let dimmed = store.config.slots.map { slot in
            slot.action.map { !store.isEnabled($0) } ?? false
        }
        return RingSnapshot(icons: store.icons,
                            subicons: store.childIcons,
                            dimmed: dimmed,
                            childrenCounts: store.config.slots.map(\.children.count))
    }
}
```

`RingSummoner.swift`（`:70-86` 附近）：删掉内联的 `icons/subicons/dimmed/childrenCounts` 拼装，改 `let snap = RingSnapshot.make(store: store)` 后逐项传入（`RingView(icons: snap.icons, viewModel: viewModel, subicons: snap.subicons, dimmed: snap.dimmed)`、`viewModel.begin(..., childrenCounts: snap.childrenCounts, ...)`）。**行为零变化**——`RingViewModelCancelTests` 等现有测试就是回归网。

- [ ] **Step 4: 实现 RingTabInspector**

```swift
// NemoLoop/Settings/RingTabInspector.swift
import SwiftUI

/// The permanent mini-ring preview in the Ring tab's inspector column.
/// Reuses the real RingView + RingViewModel (isSettingsPreview: no global
/// sampling); hover feeds updatePointer in LOCAL coordinates (the vm only
/// ever measures point−center, so begin(centerGlobal:) takes the local
/// center too and the two spaces stay consistent).
struct RingTabInspector: View {
    @Bindable var store: SliceStore
    @Binding var selectedSlot: Int?
    /// Called when an EMPTY blade is clicked — the parent opens the picker
    /// popover anchored here (spec: empty-blade click = configure directly).
    let configureSlot: (Int) -> Void

    @State private var viewModel = RingViewModel()
    @State private var userInteracting = false
    @State private var resumeTask: Task<Void, Never>?
    @State private var carouselIndex = 0

    private let side: CGFloat = 240   // fits the 6-blade fan + shadow pad

    var body: some View {
        ZStack {
            let snap = RingSnapshot.make(store: store)
            RingView(icons: snap.icons, viewModel: viewModel,
                     subicons: snap.subicons, dimmed: snap.dimmed, preAppeared: true)
                .environment(\.ringCenter, CGPoint(x: side / 2, y: side / 2))
        }
        .frame(width: side, height: side)
        .onAppear {
            viewModel.isSettingsPreview = true
            viewModel.begin(centerGlobal: CGPoint(x: side / 2, y: side / 2),
                            wedgeCount: snap.icons.count,
                            childrenCounts: snap.childrenCounts,
                            input: .vector(deadZone: 36) { .zero })
        }
        .onContinuousHover { phase in
            userInteracting = true
            scheduleResume()
            if case .active(let point) = phase {
                viewModel.updatePointer(at: point, now: Date())
            }
        }
        // DragGesture(minimumDistance: 0) is the macOS way to get a CLICK
        // WITH location — onTapGesture doesn't carry coordinates.
        .gesture(DragGesture(minimumDistance: 0).onEnded { value in
            userInteracting = true
            scheduleResume()
            handleTap(at: value.location, snapshot: snap)
        })
        .task(id: carouselIdentity(snap)) { await runCarousel() }
        .onChange(of: store.config) { restart(in: RingSnapshot.make(store: store)) }
    }

    private func handleTap(at point: CGPoint, snapshot: RingSnapshot) {
        // Same hit math as the real ring: dead zone, band, wrap gap → nil.
        guard let layout = layoutFor(snapshot),
              let index = RingGeometry.wedgeIndex(
                  from: CGPoint(x: side / 2, y: side / 2), to: point,
                  layout: layout,
                  deadZoneRadius: RingTheme.deadZoneRadius,
                  outerRadius: RingTheme.subCancelRadius) else { return }
        if snapshot.icons.indices.contains(index), snapshot.icons[index] == nil {
            configureSlot(index)          // empty blade → picker (parent decides)
        } else {
            selectedSlot = index          // configured blade → select + lock
        }
    }

    private func layoutFor(_ snap: RingSnapshot) -> BladeLayout? {
        BladeLayout.forCountIfPositive(snap.icons.count)
    }

    /// Idle carousel: every 1s, synthetically point at the next blade's
    /// center — the REAL dwell state machine does the rest (hover highlight,
    /// sub-wheel deal after subDwellDuration). Stops on any hover/click and
    /// resumes 3s after the pointer leaves.
    private func runCarousel() async {
        while !Task.isCancelled {
            if !userInteracting, let snap = currentSnapshot() {
                carouselIndex = (carouselIndex + 1) % max(snap.icons.count, 1)
                let layout = BladeLayout.forCount(snap.icons.count)
                let angle = layout.centerAngle(carouselIndex) * .pi / 180
                let radius = RingTheme.outerRadius * 0.7
                viewModel.updatePointer(
                    at: CGPoint(x: side / 2 + sin(angle) * radius,
                                y: side / 2 + cos(angle) * radius),
                    now: Date())
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func scheduleResume() {
        resumeTask?.cancel()
        resumeTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { userInteracting = false }
        }
    }

    // 以下两个小助手按真实 store/State 组合微调（currentSnapshot 从 store
    // 取、carouselIdentity 传 store.config 使 .task(id:) 在配置变化时重启）。
    private func currentSnapshot() -> RingSnapshot? { RingSnapshot.make(store: store) }
    private func carouselIdentity(_ snap: RingSnapshot) -> Int { snap.childrenCounts.hashValue }
    private func restart(in snap: RingSnapshot) {
        viewModel.begin(centerGlobal: CGPoint(x: side / 2, y: side / 2),
                        wedgeCount: snap.icons.count,
                        childrenCounts: snap.childrenCounts,
                        input: .vector(deadZone: 36) { .zero })
    }
}
```

> **落地注记（必读）**：①`BladeLayout.forCountIfPositive` 不存在——`handleTap` 里直接 `BladeLayout.forCount(max(count,1))`，删掉那个假方法；②`RingTheme.deadZoneRadius`/`subCancelRadius` 以 `RingTheme.swift` 真实常量名为准（`:71-131` 一带有 cancel 半径族），挑语义匹配死区/外界的那个；③`viewModel.begin` 在 `onAppear` 与 `onChange(of: store.config)` 双路径调用，`RingViewModel` 是引用类型 + `@State` 持有——重建时旧 vm 随视图释放，不需手动清理；④`.onContinuousHover` 需 macOS 13+（工程已是 macOS 26 目标，无碍）。

- [ ] **Step 5: 跑全部单测确认绿 + 编译面检查**

Run: 全量命令
Expected: PASS（RingTabInspector 是纯视图，编译+既有回归覆盖；快照测试新增）。

- [ ] **Step 6: Commit**

```bash
git add NemoLoop/Ring/RingSnapshot.swift NemoLoop/Settings/RingTabInspector.swift NemoLoop/Ring/RingSummoner.swift NemoLoopTests/RingSnapshotTests.swift
git commit -m "feat(settings): ring snapshot helper + live mini-ring inspector with carousel"
```

---

### Task 5: ActionPickerPopover 视图 + 槽位行/芯片排接线

**Files:**
- Create: `NemoLoop/Settings/ActionPickerPopover.swift`
- Modify: `NemoLoop/Settings/SettingsView.swift`（`wedgeRow` 的 Configure 菜单区 ~`:145-170`、`subRows` 的 "+" 菜单 ~`:236-262`）
- Test: 无新独立测试文件——数据层在 Task 2 已钉死；本任务接线正确性靠既有 SliceStore 套件 + Task 7 渲染验证 + 人工清单。

**Interfaces:**
- Consumes: Task 1 `AppScanner`/`AppEntry`、Task 2 `ActionPickerModel`/`PickerItem`/`PickerContext`、`store.setAction/addChild/attachWholePlugin`。
- Produces: `struct ActionPickerPopover: View { init(context: PickerContext, store: SliceStore, slot: Int, onDismiss: @escaping () -> Void) }`——内部 `@State query`、`@State apps: [AppEntry]?`（nil=未扫描）；首次出现时 `Task { apps = AppScanner.scan(dirs: AppScanner.defaultDirs()) }`（进程内 static 缓存：`AppScanner.cached()` 加个简单的 `nonisolated(unsafe) static var cache` 或放 `@MainActor static var`）。选中即写 store 并 `onDismiss()`。

- [ ] **Step 1: 实现 ActionPickerPopover**

```swift
// NemoLoop/Settings/ActionPickerPopover.swift
import Luminare
import SwiftUI

/// Click-triggered picker popover (native .popover — Luminare 0.2.0's own
/// popover is hover/forceTouch only) hosting Luminare content: search +
/// sectioned list. 300×360 per spec.
struct ActionPickerPopover: View {
    let context: PickerContext
    @Bindable var store: SliceStore
    let slot: Int
    let onDismiss: () -> Void

    @State private var query = ""
    @State private var apps: [AppEntry]?

    private var model: ActionPickerModel {
        ActionPickerModel(apps: apps ?? [], registry: .shared)
    }

    var body: some View {
        VStack(spacing: 8) {
            LuminareTextField("Search", text: $query)
                .padding(.horizontal, 10)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if apps == nil {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 20)
                    }
                    ForEach(model.sections(context: context, query: query)) { section in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(section.title.uppercased())
                                .font(.caption).foregroundStyle(.secondary)
                            ForEach(section.items) { item in
                                PickerRow(item: item) { choose(item) }
                            }
                        }
                    }
                    Text(model.connectedPluginFootnote)
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 10)
            }
        }
        .padding(.vertical, 10)
        .frame(width: 300, height: 360)
        .onAppear {
            if apps == nil { Task { @MainActor in apps = AppScanner.cachedScan() } }
        }
    }

    private func choose(_ item: PickerItem) {
        switch item.kind {
        case .app(let entry):  store.set(context == .mainSlot ? .app(entry.url) : .app(entry.url), at: slot)
        case .wholePlugin(let id):
            store.attachWholePlugin(id, at: slot)   // main-only: model guarantees
        case .op(let pluginID, let opID):
            let action = SlotAction.pluginOp(pluginID: pluginID, opID: opID)
            context == .mainSlot ? store.setAction(action, at: slot) : store.addChild(action, at: slot)
        case .browseApps:   runOpenPanel(kind: .appPanel)
        case .browseFolder: runOpenPanel(kind: .folderPanel)
        }
        onDismiss()
    }

    private enum PanelKind { case appPanel, folderPanel }
    private func runOpenPanel(kind: PanelKind) {
        // 复用 SettingsView 现有的 runOpenPanel 模式（app: /Applications 根；folder: 家目录）。
        // 落地：把 SettingsView.runOpenPanel(contentTypes:directory:canChooseDirectories:) 提为
        // 内部共享函数或原样复制调用语义——选择结果走同 choose 的 setAction/addChild 分支。
        onDismiss()
    }
}

private struct PickerRow: View {
    let item: PickerItem
    let onChoose: () -> Void
    var body: some View {
        Button(action: onChoose) {
            HStack(spacing: 8) {
                if case .app(let entry) = item.kind {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                        .resizable().frame(width: 20, height: 20)
                } else if let symbol = item.symbolName {
                    Image(systemName: symbol).frame(width: 20)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                    if let subtitle = item.subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if case .wholePlugin = item.kind {
                    Image(systemName: "link")     // 引用语义：插件配置变则全环生效
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
```

> `AppScanner.cachedScan()`：给 `AppScanner` 加 `@MainActor private static var cache: [AppEntry]?` + `static func cachedScan() -> [AppEntry] { cache ?? { let r = scan(dirs: defaultDirs()); cache = r; return r }() }`（首次打开选择器时扫一次，进程内复用——spec 措辞）。`choose` 里 `.app` 分支的三元写法落地时展开成两个 case 共用的 `let action = SlotAction.app(entry.url)` 再按 context 分派——上面为省行数写糊了，**必须展开**。

- [ ] **Step 2: 槽位行接线（SettingsView）**

`wedgeRow` 的 `Menu("Configure"/"System"...)` 块整体替换为：

```swift
@State private var pickerSlot: PickerTarget?   // SettingsView 顶部加

enum PickerTarget: Identifiable { case main(Int), sub(Int); var id: String { ... } }
```

行内按钮（替换原 Configure Menu）：

```swift
Button {
    pickerSlot = .main(i)
} label: {
    HStack(spacing: 6) {
        if let icon = store.icon(at: i) {
            Image(nsImage: icon).resizable().interpolation(.high).frame(width: 20, height: 20)
        } else {
            Image(systemName: "plus.circle.dashed").foregroundStyle(.secondary)
        }
        Text(entry.action.map { ActionResolver.name(for: $0) } ?? "Choose…")
            .foregroundStyle(entry.action.map { store.isEnabled($0) ? .primary : .secondary } ?? .secondary)
    }
}
.buttonStyle(.luminareCompact)
.popover(item: $pickerSlot) { target in
    if case .main(let i) = target {
        ActionPickerPopover(context: .mainSlot, store: store, slot: i,
                            onDismiss: { pickerSlot = nil })
    } else if case .sub(let i) = target {
        ActionPickerPopover(context: .subSlot, store: store, slot: i,
                            onDismiss: { pickerSlot = nil })
    }
}
// 插件挂载引用图标：label 里在名称前加
if entry.action.isPluginBacked { Image(systemName: "link").font(.caption2).foregroundStyle(.tertiary) }
```

（`SlotAction.isPluginBacked`：Model 加计算属性 `if case .plugin = self { true } else if case .pluginOp = self { true } else { false }`——三处小 switch 之一，放 `SlotAction.swift`。）

`subRows` 的 "+" `Menu` 替换为同款按钮 `pickerSlot = .sub(i)`；芯片排其余不动。原 `chooseApp/chooseFolder` 的 `runOpenPanel` 保留给 popover 的 Browse 分支复用（提为 `SettingsView` 内 `static` 或移到 `ActionPickerPopover` 自持一份，二选一，落地时选改动小的）。

- [ ] **Step 3: 全量单测绿（含既有 SliceStore/Settings 相关）**

Run: 全量命令
Expected: PASS。

- [ ] **Step 4: Commit**

```bash
git add NemoLoop/Settings/ActionPickerPopover.swift NemoLoop/Settings/SettingsView.swift NemoLoop/Services/AppScanner.swift NemoLoop/Model/SlotAction.swift
git commit -m "feat(settings): click-through action picker replaces nested Configure menus"
```

---

### Task 6: 布局整合——inspector 第三栏 + 窗口动态加宽

**Files:**
- Modify: `NemoLoop/Settings/SettingsChrome.swift`（增 `inspectorVisible` + 变更回调）
- Modify: `NemoLoop/Settings/SettingsWindowController.swift:28`（加宽方法 + 回调接线）
- Modify: `NemoLoop/Settings/SettingsView.swift`（body 三栏、`onChange(of: tab)`、选中槽位联动）
- Test: `NemoLoopTests/SettingsChromeTests.swift`

**Interfaces:**
- Consumes: Task 4 `RingTabInspector`、Task 5 `pickerSlot`。
- Produces: `SettingsChrome.inspectorVisible: Bool`（didSet 触发 `inspectorDidChange: ((Bool) -> Void)?`）；`SettingsWindowController` 暴露 `func setInspectorLayout(_ visible: Bool)`（`NSAnimationContext.runAnimationGroup` + `window.animator().setFrame`，宽 680↔960，高 480 不变，保持窗口中心或左上锚定——**左上锚定**，避免设置窗漂移）。

- [ ] **Step 1: 写失败测试**

```swift
// NemoLoopTests/SettingsChromeTests.swift
import Testing
@testable import NemoLoop

@MainActor
struct SettingsChromeTests {
    @Test func inspectorToggleNotifiesSubscriber() {
        let chrome = SettingsChrome()
        var seen: [Bool] = []
        chrome.inspectorDidChange = { seen.append($0) }
        chrome.inspectorVisible = true
        chrome.inspectorVisible = false
        #expect(seen == [true, false])
    }

    @Test func inspectorVisibleStartsFalse() {
        #expect(SettingsChrome().inspectorVisible == false)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: 全量命令 + `-only-testing:NemoLoopTests/SettingsChromeTests`
Expected: FAIL —— `inspectorVisible` 不存在。

- [ ] **Step 3: 实现**

```swift
// SettingsChrome —— 加：
/// Ring-tab inspector column. Toggled by the tab switch, observed by the
/// window controller to animate the frame wider/narrower.
var inspectorVisible = false {
    didSet { inspectorDidChange?(inspectorVisible) }
}
var inspectorDidChange: ((Bool) -> Void)?
```

```swift
// SettingsWindowController —— showWindow 里 setContentSize 之后加回调；加方法：
func setInspectorLayout(_ visible: Bool) {
    guard let window else { return }
    let target = NSRect(x: window.frame.origin.x,
                        y: window.frame.origin.y,
                        width: visible ? 960 : 680,
                        height: window.frame.height)
    NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.25
        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        window.animator().setFrame(target, display: true)
    }
}
// 控制器持 chrome 的地方：chrome.inspectorDidChange = { [weak self] in self?.setInspectorLayout($0) }
```

`SettingsView.body`（HStack 尾部、动画修饰符之前）：

```swift
if tab == .ring {
    Divider()
    RingTabInspector(store: store,
                     selectedSlot: $selectedSlot,
                     configureSlot: { index in pickerSlot = .main(index) })  // 空槽直配：同一个 popover
        .frame(width: 280)
        .padding(.vertical, 12)
}
// body 链上加（与 sidebarVisible 动画同一 value 集）：
.animation(.smooth(duration: 0.25), value: chrome.inspectorVisible)
.onChange(of: tab) { chrome.inspectorVisible = ($0 == .ring) }
.onAppear { chrome.inspectorVisible = (tab == .ring) }
```

选中联动：SettingsView 增 `@State private var selectedSlot: Int?`；`wedgeRow` 根容器加 `.background(selectedSlot == i ? Color.accentColor.opacity(0.08) : .clear)` + `RoundedRectangle(cornerRadius: 8).strokeBorder(selectedSlot == i ? Color.accentColor.opacity(0.4) : .clear)`；行点击（Choose 按钮外的行区域 `ContentShape(Rectangle).onTapGesture { selectedSlot = i }`）设选中。

- [ ] **Step 4: 跑全部单测确认绿**

Run: 全量命令
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add NemoLoop/Settings/SettingsChrome.swift NemoLoop/Settings/SettingsWindowController.swift NemoLoop/Settings/SettingsView.swift NemoLoopTests/SettingsChromeTests.swift
git commit -m "feat(settings): Ring-tab inspector column with animated window widening"
```

---

### Task 7: 渲染验证——Ring 标签整页 + popover 打开态

**Files:**
- Create: `Design/render_check_ring_tab.swift`（一次性 harness，验完保留供回归）

**Interfaces:**
- Consumes: 全部前序任务终态。

- [ ] **Step 1: 写渲染脚本**

沿用 T9 的自举模式（`swiftc -D RENDER_HARNESS` 编译真实 Ring/Model 源 + 最小镜像缝合，头部文档写明运行方式与清单）。这次多编译 `NemoLoop/Settings/` 相关文件，难点是 SettingsView 依赖 Luminare 包——**绕开**：harness 不渲 SettingsView 整窗，而是分两张：
  1. **inspector 单视图**：`RingTabInspector`（依赖 Luminare 少——若它 import Luminare 则该脚本改为只渲其内部 `RingView` 组合 + 手势层用 `Section` 探针；落地时按实际 import 裁剪——RingTabInspector 设计上只 import SwiftUI，ActionPickerPopover 才碰 Luminare，预期可直接编）——渲 240×240，断言：六扇叶带、缺口方位空、暗态扇叶降饱和（复用 T9 的像素谓词）、子轮盘在悬停态打开（preDrive vm 悬停 0.3s）。
  2. **ActionPickerPopover 内容**：若 import Luminare 编不过（包不在 swiftc 路径），降级为渲 `ActionPickerModel.sections` 渲染的纯 SwiftUI 等价列表（自建 Row 视图）——分区标题/APPS/PLUGINS/FOLDERS 逐项可见 + 🔗 标记在整挂行。harness 头部注明降级原因（Luminare 包不可达于纯 swiftc 编译）。
- [ ] **Step 2: 跑脚本、按清单核验 PNG（Read 图片 + 像素直方图）**

Run: `swift Design/render_check_ring_tab.swift`
清单：①mini 环扇叶数=配置槽位数、图标带在外圈；②缺口方位空；③暗态扇叶可辨；④子轮盘打开帧存在；⑤选择器分区齐全（或降级列表等价）；⑥整挂行 🔗 可见。
Expected: 全过；不过则修（几何问题报规格裁定，UI 问题修 UI）。

- [ ] **Step 3: Commit**

```bash
git add Design/render_check_ring_tab.swift
git commit -m "test(render): Ring tab inspector + picker render check harness"
```

---

### Task 8: 全量回归 + 实机验收

**Files:** 无新文件。

- [ ] **Step 1: 全量单测**

Run: Global Constraints 全量命令
Expected: 全绿。

- [ ] **Step 2: 构建启动（先 pkill），`--settings` 打开，人工清单过一遍**

```bash
pkill -x NemoLoop 2>/dev/null; xcodebuild build -project NemoLoop.xcodeproj -scheme NemoLoop -destination 'platform=macOS' CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual
open ~/Library/Developer/Xcode/DerivedData/NemoLoop-ffnx*/Build/Products/Debug/NemoLoop.app --args --settings
```

清单：①Ring 标签窗口平滑加宽、切走收窄；②mini 环空闲轮播、悬停即停并发子轮盘、节奏=真环；③点空扇叶直接弹选择器（锚定 inspector）、点已配扇叶左侧行高亮联动；④槽行 Choose → popover：搜索 "Ter" 出 Terminal、点 Apps 项即挂上、PLUGINS 分区整挂 System 后芯片排自动展开 5 op；⑤子槽 "+" popover 无整挂项；⑥断开 Appearance 后其扇叶/槽行变暗、选择器 Plugins 分区不再出现、重连恢复；⑦Browse… 两个面板可用。

- [ ] **Step 3: 截图留档 + Commit（如有修复）**

```bash
screencapture -x Design/ring_tab_live.png
git add Design/ring_tab_live.png && git commit -m "docs(design): Ring tab acceptance screenshot"
```

---

## 计划自检记录

- **Spec 覆盖**：三栏布局/窗口加宽→T6；isSettingsPreview+手势驱动+轮播+点空槽直配→T3/T4；选择器分区/搜索/上下文→T2/T5；🔗/暗态/整挂复用→T5（isPluginBacked）+T4（快照 dimmed）；扫描+Browse→T1/T5；测试策略→各任务+T7/T8；popover 触发方式偏离已裁定（计划头）。
- **占位符**：T4/T5 的"落地注记"是对真实 API 的显式适配指令（含具体改法），非未决设计；T7 的降级路径写明判据。
- **类型一致性**：`AppEntry`/`ActionPickerModel.sections(context:query:)`/`PickerItem.Kind`/`RingSnapshot.make(store:)`/`SettingsChrome.inspectorDidChange`/`setInspectorLayout(_:)` 各任务互检一致；`AppScanner.cachedScan()` 在 T5 定义、T5 内使用。
