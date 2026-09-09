# 插件架构实现计划（Plugin Architecture Implementation Plan）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把"一族操作+连接生命周期+配置"组织为内置插件：插件可整体挂一级扇叶（操作自动成二级）或单体挂任意扇叶；设置页新增 Plugins 标签；`SystemAction` 收编为 System 插件；首批落 Appearance 与 Screenshot 两插件。

**Architecture:** `NemoPlugin`/`PluginOp` 协议 + `PluginRegistry`（@MainActor @Observable，启用状态持久化 UserDefaults）。`SlotAction` 增 `.plugin(String)` 与 `.pluginOp(pluginID:opID:)`，整体挂载复用 `SlotEntry.children` 存有序操作列表，环端子轮盘链路零改动；触发统一收敛到 `Launcher.run` → `registry.perform`。旧 `.system` 数据经自定义 Codable 解码无损映射为 `.pluginOp("system", …)`。

**Tech Stack:** Swift 6 / SwiftUI+AppKit / swift-testing / Luminare（设置页既有组件库）。无新外部依赖。

**Spec:** `docs/superpowers/specs/2026-09-09-plugin-architecture-design.md`（实现时 spec 与本计划同读）

## Global Constraints

- 单测命令（**ad-hoc 签名**——NemoLoopDev 自签证书在 xctest 宿主下会被 dyld 的 Team ID 校验拒载 `NemoLoop.debug.dylib`，2026-09-09 实测；ad-hoc 只跑单测不涉 TCC，启动构建仍用 NemoLoopDev）：
  `xcodebuild test -project NemoLoop.xcodeproj -scheme NemoLoop -destination 'platform=macOS' -only-testing:NemoLoopTests CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual`
- 运行单个测试文件：同命令加 `-only-testing:NemoLoopTests/<StructName>`。
- UITests 在本环境无法加载，禁止跑 `-only-testing:NemoLoopUITests`。
- Xcode 工程使用 file-system-synchronized groups：**新建 .swift 文件无需改 pbxproj**。
- UI 字符串全部英文（现有设置页惯例）；代码注释密度与现有文件一致（解释"为什么"）。
- `@MainActor` 是 app 层默认隔离（SliceStore/SettingsView/Ring* 均如此）；Model 值类型保持非隔离。
- 常量落位：二级扇叶角宽 `RingTheme.subPitchDegrees = 15`（**已是现状，勿改**）；容量 `SlotEntry.maxPluginChildren = 8`、`SlotEntry.maxManualChildren = 4`。
- 每个任务结束必须全量单测绿 + commit。

---

### Task 1: SlotAction 插件 case + 显式 Codable + 按动作的容量上限

**Files:**
- Modify: `NemoLoop/Model/SlotAction.swift`
- Test: `NemoLoopTests/SlotActionMigrationTests.swift`（新建）

**Interfaces:**
- Produces: `SlotAction.plugin(String)`、`SlotAction.pluginOp(pluginID: String, opID: String)`（本期 `.system` 暂留，Task 4 移除）；`SlotEntry.maxPluginChildren = 8`、`SlotEntry.maxManualChildren = 4`、`SlotEntry.childLimit(for:) -> Int`；`SlotAction.identity` 对新 case 返回 `"plugin:<id>"` / `"pluginOp:<pluginID>:<opID>"`。
- 后续任务依赖：显式 Codable 的编码格式必须与 Swift 合成格式逐字节一致（单 key 关联值 `{"_0": …}`），这是 Task 4 旧数据迁移的地基。

- [ ] **Step 1: 写失败测试**

```swift
// NemoLoopTests/SlotActionMigrationTests.swift
import Testing
import Foundation
@testable import NemoLoop

struct SlotActionMigrationTests {
    @Test func pluginCasesRoundTrip() throws {
        let actions: [SlotAction] = [.plugin("media"),
                                     .pluginOp(pluginID: "system", opID: "lockScreen"),
                                     .app(URL(filePath: "/Applications/Safari.app"))]
        let data = try JSONEncoder().encode(actions)
        let decoded = try JSONDecoder().decode([SlotAction].self, from: data)
        #expect(decoded == actions)
    }

    /// 旧版合成 Codable 把关联值编码为 {"case":{"_0":value}}——显式编码器必须逐字节复刻。
    @Test func explicitEncodingMatchesSynthesizedShape() throws {
        let encoded = String(data: try JSONEncoder().encode(SlotAction.plugin("media")), encoding: .utf8)
        #expect(encoded == #"{"plugin":{"_0":"media"}}"#)

        let opEncoded = String(data: try JSONEncoder()
            .encode(SlotAction.pluginOp(pluginID: "system", opID: "ocr")), encoding: .utf8)
        #expect(opEncoded == #"{"pluginOp":{"pluginID":"system","opID":"ocr"}}"#)
    }

    @Test func legacySystemJSONStillDecodes() throws {
        // Task 1 阶段 .system case 仍在：合成时代的磁盘数据必须照常解出。
        let json = #"{"system":{"_0":"lockScreen"}}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SlotAction.self, from: json)
        #expect(decoded == .system(.lockScreen))
    }

    @Test func legacyAppJSONStillDecodes() throws {
        // 磁盘上最多的存量格式：app 槽位同样是嵌套 _0 形状。
        let json = #"{"app":{"_0":"/Applications/Safari.app"}}"#.data(using: .utf8)!
        #expect(try JSONDecoder().decode(SlotAction.self, from: json)
                == .app(URL(filePath: "/Applications/Safari.app")))
    }

    @Test func identityForPluginCases() {
        #expect(SlotAction.plugin("media").identity == "plugin:media")
        #expect(SlotAction.pluginOp(pluginID: "system", opID: "ocr").identity
                == "pluginOp:system:ocr")
    }

    @Test func childLimitDependsOnAction() {
        #expect(SlotEntry.childLimit(for: .plugin("media")) == SlotEntry.maxPluginChildren)
        #expect(SlotEntry.childLimit(for: .pluginOp(pluginID: "system", opID: "ocr"))
                == SlotEntry.maxManualChildren)
        #expect(SlotEntry.childLimit(for: .app(URL(filePath: "/A.app")))
                == SlotEntry.maxManualChildren)
        #expect(SlotEntry.childLimit(for: nil) == SlotEntry.maxManualChildren)
    }

    @Test func entryInitTruncatesToActionLimit() {
        let nineOps = (0..<9).map { SlotAction.pluginOp(pluginID: "media", opID: "op\($0)") }
        let entry = SlotEntry(action: .plugin("media"), children: nineOps)
        #expect(entry.children.count == SlotEntry.maxPluginChildren)

        let five = (0..<5).map { SlotAction.pluginOp(pluginID: "media", opID: "op\($0)") }
        let manual = SlotEntry(action: .pluginOp(pluginID: "media", opID: "play"), children: five)
        #expect(manual.children.count == SlotEntry.maxManualChildren)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -project NemoLoop.xcodeproj -scheme NemoLoop -destination 'platform=macOS' -only-testing:NemoLoopTests/SlotActionMigrationTests CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual`
Expected: FAIL —— `type 'SlotAction' has no case 'plugin'` 编译错误。

- [ ] **Step 3: 最小实现**

`NemoLoop/Model/SlotAction.swift`：`SlotAction` 增两 case（放 `.system` 之后）；为整段 enum 写显式 `Codable`（单 key keyed container，关联值标签 `_0` / `pluginID`+`opID`，与合成格式一致）；`identity` 与 `displayName` 补新 case（displayName 插件 case 返回 `"pluginID/opID"` 兜底，正式名称由 Task 3 的 MainActor 解析器提供）；`SlotEntry` 增容量 API：

```swift
enum SlotAction: Codable, Equatable {
    case app(URL)
    case folder(URL)
    case system(SystemAction)                       // Task 4 移除
    case plugin(String)
    case pluginOp(pluginID: String, opID: String)

    private enum CodingKeys: String, CodingKey {
        case app, folder, system, plugin, pluginOp
    }
    private enum SingleValueKeys: String, CodingKey { case _0 }
    private enum PluginOpKeys: String, CodingKey { case pluginID, opID }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Swift 合成格式把每个单关联值 case 包成 {"case":{"_0":value}}——
        // app/folder/system/plugin 四个 case 全部按嵌套 _0 解，平铺一律不认。
        if container.contains(.app) {
            let nested = try container.nestedContainer(keyedBy: SingleValueKeys.self, forKey: .app)
            self = .app(try nested.decode(URL.self, forKey: ._0)); return
        }
        if container.contains(.folder) {
            let nested = try container.nestedContainer(keyedBy: SingleValueKeys.self, forKey: .folder)
            self = .folder(try nested.decode(URL.self, forKey: ._0)); return
        }
        if container.contains(.system) {
            let nested = try container.nestedContainer(keyedBy: SingleValueKeys.self, forKey: .system)
            let raw = try nested.decode(String.self, forKey: ._0)
            guard let system = SystemAction(rawValue: raw) else {
                throw DecodingError.dataCorruptedError(forKey: .system, in: container,
                                                       debugDescription: "unknown system action \(raw)")
            }
            self = .system(system); return
        }
        if container.contains(.plugin) {
            let nested = try container.nestedContainer(keyedBy: SingleValueKeys.self, forKey: .plugin)
            self = .plugin(try nested.decode(String.self, forKey: ._0)); return
        }
        if container.contains(.pluginOp) {
            let nested = try container.nestedContainer(keyedBy: PluginOpKeys.self, forKey: .pluginOp)
            self = .pluginOp(pluginID: try nested.decode(String.self, forKey: .pluginID),
                             opID: try nested.decode(String.self, forKey: .opID))
            return
        }
        throw DecodingError.dataCorruptedError(forKey: .system, in: container,
                                               debugDescription: "no known SlotAction case")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .app(let url):
            var nested = container.nestedContainer(keyedBy: SingleValueKeys.self, forKey: .app)
            try nested.encode(url, forKey: ._0)
        case .folder(let url):
            var nested = container.nestedContainer(keyedBy: SingleValueKeys.self, forKey: .folder)
            try nested.encode(url, forKey: ._0)
        case .system(let system):
            var nested = container.nestedContainer(keyedBy: SingleValueKeys.self, forKey: .system)
            try nested.encode(system.rawValue, forKey: ._0)
        case .plugin(let id):
            var nested = container.nestedContainer(keyedBy: SingleValueKeys.self, forKey: .plugin)
            try nested.encode(id, forKey: ._0)
        case .pluginOp(let pluginID, let opID):
            var nested = container.nestedContainer(keyedBy: PluginOpKeys.self, forKey: .pluginOp)
            try nested.encode(pluginID, forKey: .pluginID)
            try nested.encode(opID, forKey: .opID)
        }
    }
}
```

> `pluginOp` 的关联值带标签，合成 Codable 直接用标签名（`pluginID`/`opID`，无 `_0` 前缀），上面的 `PluginOpKeys` 已按标签名对齐；单值 case 统一走 `SingleValueKeys._0`。

`SlotEntry` 部分：

```swift
struct SlotEntry: Codable, Equatable {
    static let maxManualChildren = 4
    static let maxPluginChildren = 8

    var action: SlotAction?
    var children: [SlotAction] = []

    init(action: SlotAction? = nil, children: [SlotAction] = []) {
        self.action = action
        self.children = Array(children.prefix(Self.childLimit(for: action)))
    }

    /// 子扇叶容量：整体挂载的插件槽放宽到 8，其余（含空槽）保持 4。
    static func childLimit(for action: SlotAction?) -> Int {
        if case .plugin = action { return maxPluginChildren }
        return maxManualChildren
    }
}
```

同步更新 `SliceStore.addChild` 的上限判断（`SliceStore.swift:58`）：`config.slots[index].children.count < SlotEntry.childLimit(for: config.slots[index].action)`。

- [ ] **Step 4: 跑全部单测确认绿**

Run: 全量命令（见 Global Constraints，不带 `-only-testing` 限定 struct）
Expected: PASS（`SliceConfigTests` 等既有测试不受影响——显式 Codable 与合成格式等价）。

- [ ] **Step 5: Commit**

```bash
git add NemoLoop/Model/SlotAction.swift NemoLoopTests/SlotActionMigrationTests.swift
git commit -m "feat(model): plugin/pluginOp slot actions, explicit Codable, per-action child limit"
```

---

### Task 2: 插件协议 + PluginRegistry

**Files:**
- Create: `NemoLoop/Model/PluginModels.swift`
- Create: `NemoLoop/Services/PluginRegistry.swift`
- Test: `NemoLoopTests/PluginRegistryTests.swift`（新建）

**Interfaces:**
- Produces: `@MainActor protocol PluginOp: Identifiable { var id/displayName/symbolName: String; func perform() }`；`@MainActor protocol NemoPlugin: Identifiable { var id/displayName/symbolName/summary: String; var operations: [any PluginOp]; var status: PluginStatus; func connect() async throws; func disconnect() async; var configSections: AnyView? }`（extension 给 `configSections` 默认 nil、`connect/disconnect` 默认空实现，简单插件零样板）；`enum PluginStatus: Equatable { case notInstalled, needsAuth, ready }`；`@MainActor @Observable final class PluginRegistry`：
  - `static let shared: PluginRegistry`（默认注册 Task 3 起的内置插件；Task 2 先空表）
  - `init(defaults: UserDefaults = .standard, plugins: [any NemoPlugin] = [])`
  - `private(set) var plugins: [any NemoPlugin]`
  - `func isEnabled(_ pluginID: String) -> Bool`
  - `func setEnabled(_ pluginID: String, _ enabled: Bool) async throws`（开=connect 失败即回滚并 rethrow；关=disconnect + 持久化；持久化 key `nemoloop.plugin.<id>.enabled`）
  - `func perform(pluginID: String, opID: String)`（禁用/缺失 → `NSLog("NemoLoop plugin: …")` 后返回）
  - `func plugin(id: String) -> (any NemoPlugin)?`、`func op(pluginID: String, opID: String) -> (any PluginOp)?`

- [ ] **Step 1: 写失败测试**

```swift
// NemoLoopTests/PluginRegistryTests.swift
import Testing
import Foundation
import SwiftUI
@testable import NemoLoop

@MainActor
struct PluginRegistryTests {
    /// 测试替身：记录调用次数的最小插件/操作。
    private final class StubOp: PluginOp, Equatable {
        let id: String; let displayName: String; let symbolName: String
        private(set) var performed = 0
        init(_ id: String) { self.id = id; displayName = id; symbolName = "circle" }
        func perform() { performed += 1 }
        static func == (l: StubOp, r: StubOp) -> Bool { l.id == r.id }
    }

    private final class StubPlugin: NemoPlugin {
        let id = "stub"; let displayName = "Stub"; let symbolName = "puzzlepiece"
        let summary = "test double"
        let ops: [StubOp]
        var connectError: Error?
        private(set) var connectCalls = 0
        private(set) var disconnectCalls = 0
        init(_ ops: [StubOp]) { self.ops = ops }
        var operations: [any PluginOp] { ops }
        var status: PluginStatus { .ready }
        func connect() async throws {
            connectCalls += 1
            if let connectError { throw connectError }
        }
        func disconnect() async { disconnectCalls += 1 }
    }

    private func makeDefaults() -> UserDefaults {
        let name = "plugin-registry-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func enabledPersistsAcrossInstances() async throws {
        let plugin = StubPlugin([StubOp("a")])
        let defaults = makeDefaults()
        let r1 = PluginRegistry(defaults: defaults, plugins: [plugin])
        #expect(!r1.isEnabled("stub"))
        try await r1.setEnabled("stub", true)
        #expect(r1.isEnabled("stub"))

        let r2 = PluginRegistry(defaults: defaults, plugins: [StubPlugin([StubOp("a")])])
        #expect(r2.isEnabled("stub"))
    }

    @Test func connectFailureRollsBackAndThrows() async {
        let plugin = StubPlugin([StubOp("a")])
        plugin.connectError = URLError(.notConnectedToInternet)
        let registry = PluginRegistry(defaults: makeDefaults(), plugins: [plugin])
        await #expect(throws: (any Error).self) {
            try await registry.setEnabled("stub", true)
        }
        #expect(!registry.isEnabled("stub"))           // 弹回 off
        #expect(plugin.connectCalls == 1)
    }

    @Test func performRoutesToOpAndToleratesMissing() async throws {
        let op = StubOp("play")
        let registry = PluginRegistry(defaults: makeDefaults(), plugins: [StubPlugin([op])])
        try await registry.setEnabled("stub", true)
        registry.perform(pluginID: "stub", opID: "play")
        #expect(op.performed == 1)

        registry.perform(pluginID: "stub", opID: "nope")   // 不崩、不计数
        registry.perform(pluginID: "ghost", opID: "play")
        #expect(op.performed == 1)
    }

    @Test func performIgnoredWhenDisabled() async throws {
        let op = StubOp("play")
        let registry = PluginRegistry(defaults: makeDefaults(), plugins: [StubPlugin([op])])
        try await registry.setEnabled("stub", true)
        try await registry.setEnabled("stub", false)
        registry.perform(pluginID: "stub", opID: "play")
        #expect(op.performed == 0)
        #expect(registry.plugin(id: "stub")!.disconnectCalls == 1)
    }

    @Test func unknownPluginDefaultsDisabled() {
        let registry = PluginRegistry(defaults: makeDefaults(), plugins: [])
        #expect(!registry.isEnabled("ghost"))
        #expect(registry.plugin(id: "ghost") == nil)
        #expect(registry.op(pluginID: "ghost", opID: "x") == nil)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: 全量命令 + `-only-testing:NemoLoopTests/PluginRegistryTests`
Expected: FAIL —— `cannot find 'PluginOp' in scope`。

- [ ] **Step 3: 最小实现**

```swift
// NemoLoop/Model/PluginModels.swift
import SwiftUI

/// 一个插件操作：环上扇叶触发的一个原子动作。
@MainActor
protocol PluginOp: Identifiable {
    var id: String { get }
    var displayName: String { get }
    var symbolName: String { get }
    func perform()
}

enum PluginStatus: Equatable {
    case notInstalled   // 依赖缺失（如媒体插件的 perl 桥没装）
    case needsAuth      // 需要 TCC/登录等授权
    case ready
}

/// 一个内置插件：一族相关操作 + 自己的连接生命周期与配置区。
@MainActor
protocol NemoPlugin: Identifiable {
    var id: String { get }
    var displayName: String { get }
    var symbolName: String { get }
    var summary: String { get }
    var operations: [any PluginOp] { get }
    var status: PluginStatus { get }
    func connect() async throws
    func disconnect() async
    var configSections: AnyView? { get }
}

extension NemoPlugin {
    func connect() async throws {}
    func disconnect() async {}
    var configSections: AnyView? { nil }
}
```

```swift
// NemoLoop/Services/PluginRegistry.swift
import Foundation
import Observation

/// 内置插件的注册表与启用状态真源。开关驱动 connect/disconnect；
/// 触发统一走 perform(pluginID:opID:)，缺失/禁用一律 NSLog 后静默返回。
@MainActor
@Observable
final class PluginRegistry {
    static let shared = PluginRegistry(plugins: [
        // Task 3 起逐个登记内置插件；本期先空表。
    ])

    private static let enabledKeyPrefix = "nemoloop.plugin."

    private let defaults: UserDefaults
    private(set) var plugins: [any NemoPlugin]
    private var enabledIDs: Set<String>

    init(defaults: UserDefaults = .standard, plugins: [any NemoPlugin] = []) {
        self.defaults = defaults
        self.plugins = plugins
        self.enabledIDs = Set(plugins.compactMap { plugin in
            defaults.bool(forKey: Self.enabledKeyPrefix + plugin.id) ? plugin.id : nil
        })
    }

    func isEnabled(_ pluginID: String) -> Bool { enabledIDs.contains(pluginID) }

    func plugin(id: String) -> (any NemoPlugin)? {
        plugins.first { $0.id == id }
    }

    func op(pluginID: String, opID: String) -> (any PluginOp)? {
        plugin(id: pluginID)?.operations.first { $0.id == opID }
    }

    /// 打开=connect（失败回滚并抛出让 UI 报错）；关闭=disconnect。两者都持久化。
    func setEnabled(_ pluginID: String, _ enabled: Bool) async throws {
        guard let plugin = plugin(id: pluginID) else {
            NSLog("NemoLoop plugin: toggle for unknown plugin \(pluginID)")
            return
        }
        if enabled {
            try await plugin.connect()
            enabledIDs.insert(pluginID)
        } else {
            await plugin.disconnect()
            enabledIDs.remove(pluginID)
        }
        defaults.set(enabled, forKey: Self.enabledKeyPrefix + pluginID)
    }

    func perform(pluginID: String, opID: String) {
        guard isEnabled(pluginID) else {
            NSLog("NemoLoop plugin: op \(pluginID).\(opID) skipped — plugin disabled")
            return
        }
        guard let op = op(pluginID: pluginID, opID: opID) else {
            NSLog("NemoLoop plugin: unknown op \(pluginID).\(opID)")
            return
        }
        op.perform()
    }
}
```

> `@Observable` 宏与协议存在类型（`any NemoPlugin`）数组共存没问题——观察粒度是 `plugins`/`enabledIDs` 这两个存储属性。

- [ ] **Step 4: 跑全部单测确认绿**

Run: 全量命令
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add NemoLoop/Model/PluginModels.swift NemoLoop/Services/PluginRegistry.swift NemoLoopTests/PluginRegistryTests.swift
git commit -m "feat(plugins): NemoPlugin protocol + registry with persisted enable state"
```

---

### Task 3: System 插件 + Launcher 触发路由 + 名称/图标解析

**Files:**
- Create: `NemoLoop/Plugins/SystemPlugin.swift`
- Create: `NemoLoop/Services/ActionResolver.swift`
- Modify: `NemoLoop/Services/Launcher.swift:15-24`
- Modify: `NemoLoop/Model/SliceStore.swift:74-81`（`icon(for:)` 增插件分支）
- Test: `NemoLoopTests/SystemPluginTests.swift`、`NemoLoopTests/ActionResolverTests.swift`（新建）

**Interfaces:**
- Consumes: Task 1 的 `SlotAction` 新 case、Task 2 的 `PluginRegistry`。
- Produces: `SystemPlugin`（id `"system"`，5 个 op，id 即 `SystemAction.rawValue`，perform 转发现有 `SystemAction.perform()`；status 恒 `.ready`；connect 直接过——`setEnabled` 插入 enabledIDs 即"出厂连接"由 Task 5 的默认值处理）；`ActionResolver.name(for:) -> String`、`ActionResolver.symbolName(for:) -> String?`（`@MainActor`，app/folder 走 `SlotAction.displayName`/nil，插件 case 查 `PluginRegistry.shared`，缺失回退 `"pluginID/opID"`）；`Launcher.run(_:children:)`（`.plugin` 释放时触发其**第一个已配置子操作**，无子操作则 NSLog 返回）。

- [ ] **Step 1: 写失败测试**

```swift
// NemoLoopTests/SystemPluginTests.swift
import Testing
import Foundation
@testable import NemoLoop

@MainActor
struct SystemPluginTests {
    @Test func exposesFiveSystemOpsWithStableIDs() {
        let plugin = SystemPlugin()
        #expect(plugin.id == "system")
        #expect(plugin.status == .ready)
        #expect(plugin.operations.map(\.id)
                == ["lockScreen", "sleepDisplays", "sleep", "missionControl", "ocr"])
        #expect(plugin.operations.map(\.displayName)
                == ["Lock Screen", "Sleep Displays", "Sleep", "Mission Control", "OCR"])
    }

    @Test func sharedRegistryShipsSystemRegistered() {
        #expect(PluginRegistry.shared.plugin(id: "system") != nil)
    }
}
```

```swift
// NemoLoopTests/ActionResolverTests.swift
import Testing
import Foundation
@testable import NemoLoop

@MainActor
struct ActionResolverTests {
    @Test func namesResolveThroughRegistryWithFallback() {
        // shared 注册表含 System 插件（未启用也允许解析名称——暗态规则要求"禁用仍可浏览"）。
        #expect(ActionResolver.name(for: .pluginOp(pluginID: "system", opID: "lockScreen"))
                == "Lock Screen")
        #expect(ActionResolver.name(for: .plugin("system")) == "System")
        #expect(ActionResolver.name(for: .pluginOp(pluginID: "ghost", opID: "x")) == "ghost/x")
        #expect(ActionResolver.symbolName(for: .pluginOp(pluginID: "system", opID: "ocr"))
                == "doc.text.viewfinder")
        #expect(ActionResolver.symbolName(for: .app(URL(filePath: "/A.app"))) == nil)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: 全量命令 + `-only-testing:NemoLoopTests/SystemPluginTests -only-testing:NemoLoopTests/ActionResolverTests`
Expected: FAIL —— `cannot find 'SystemPlugin' in scope`。

- [ ] **Step 3: 最小实现**

```swift
// NemoLoop/Plugins/SystemPlugin.swift
import Foundation

/// 出厂即有的系统动作族，收编为插件：id 沿用 SystemAction.rawValue，
/// perform 仍走 SystemActions.swift 的既有实现，零行为变化。
@MainActor
final class SystemPlugin: NemoPlugin {
    struct Op: PluginOp {
        let action: SystemAction
        var id: String { action.rawValue }
        var displayName: String { action.displayName }
        var symbolName: String { action.symbolName }
        func perform() { action.perform() }
    }

    let id = "system"
    let displayName = "System"
    let symbolName = "gearshape.2"
    let summary = "Built-in system actions: lock, sleep, Mission Control, OCR."

    let operations: [any PluginOp] = SystemAction.allCases.map(Op.init(action:))
    var status: PluginStatus { .ready }
}
```

> `PluginOp` 有 `Identifiable` 约束，`Op` 靠 `id` 计算属性满足，无需额外声明。

```swift
// NemoLoop/Services/ActionResolver.swift
import AppKit

/// 环/设置页共用的动作名称与符号解析：插件 case 要查注册表（禁用也解析，
/// 暗态仍可浏览），模型层保持非隔离所以解析单独放这里。
@MainActor
enum ActionResolver {
    static func name(for action: SlotAction) -> String {
        switch action {
        case .app, .folder, .system:
            return action.displayName
        case .plugin(let id):
            return PluginRegistry.shared.plugin(id: id)?.displayName ?? id
        case .pluginOp(let pluginID, let opID):
            return PluginRegistry.shared.op(pluginID: pluginID, opID: opID)?.displayName
                ?? "\(pluginID)/\(opID)"
        }
    }

    static func symbolName(for action: SlotAction) -> String? {
        switch action {
        case .app, .folder:
            return nil
        case .system(let system):
            return system.symbolName
        case .plugin(let id):
            return PluginRegistry.shared.plugin(id: id)?.symbolName
        case .pluginOp(let pluginID, let opID):
            return PluginRegistry.shared.op(pluginID: pluginID, opID: opID)?.symbolName
        }
    }
}
```

`PluginRegistry.shared` 登记内置插件（`PluginRegistry.swift`）：

```swift
static let shared = PluginRegistry(plugins: [
    SystemPlugin(),
])
```

`Launcher.run` 路由（`Launcher.swift`，整函数替换）：

```swift
/// Runs any slot action: apps launch, folders open in Finder, plugin ops
/// fire through the registry. A whole-plugin blade released without dwell
/// runs its first configured child op.
static func run(_ action: SlotAction, children: [SlotAction] = []) {
    switch action {
    case .app(let url):
        launch(url: url)
    case .folder(let url):
        NSWorkspace.shared.open(url)
    case .system(let system):
        system.perform()
    case .plugin:
        guard let first = children.first, case let .pluginOp(pluginID, opID) = first else {
            NSLog("NemoLoop: plugin blade released with no ops — nothing to run")
            return
        }
        PluginRegistry.shared.perform(pluginID: pluginID, opID: opID)
    case .pluginOp(let pluginID, let opID):
        PluginRegistry.shared.perform(pluginID: pluginID, opID: opID)
    }
}
```

> Launcher 静态方法从非隔离调用点（RingSummoner/MenuBarPanelController 均 @MainActor）没问题；`run` 隐式继承 MainActor 上下文——若编译器要求，给 `run` 标 `@MainActor` 并确认两处调用点已在 MainActor（它们是）。

`RingSummoner.swift:44` 把 `Launcher.run(action)` 改为 `Launcher.run(action, children: entry.children)`（该行上下文已持有 `entry`；`:42` 的子操作触发行不变）。`MenuBarPanelController.swift:101` 不传 children（插件主槽在菜单栏面板场景无子表，走 no-op 日志分支可接受）。

`SliceStore.icon(for:)`（`SliceStore.swift:74`）增分支（`system.symbolImage` 抽成按符号名绘制的通用函数，System 插件与 Appearance/Screenshot 复用）：

```swift
static func icon(for action: SlotAction) -> NSImage {
    switch action {
    case .app(let url), .folder(let url):
        return NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
    case .system(let system):
        return SymbolPlate.image(symbolName: system.symbolName, label: system.displayName)
    case .plugin(let id):
        let plugin = PluginRegistry.shared.plugin(id: id)
        return SymbolPlate.image(symbolName: plugin?.symbolName ?? "puzzlepiece",
                                 label: plugin?.displayName ?? id)
    case .pluginOp(let pluginID, let opID):
        let symbol = ActionResolver.symbolName(for: action) ?? "circle.dashed"
        return SymbolPlate.image(symbolName: symbol,
                                 label: ActionResolver.name(for: action))
    }
}
```

把现 `SystemAction.symbolImage` 的绘制体（`SliceStore.swift:96-112`）原样搬进新文件 `NemoLoop/Helpers/SymbolPlate.swift`：

```swift
import AppKit

/// Monochrome symbol drawn at app-icon size, tinted systemGray so it reads
/// on both the near-white card stock and the dark charcoal one.
enum SymbolPlate {
    static func image(symbolName: String, label: String) -> NSImage {
        // …SliceStore.symbolImage 的现有实现，参数从 system 改为入参…
    }
}
```

`SystemAction.symbolImage` 删除，`SymbolPlate` 成为唯一符号绘制路径（`rebuildIcons` 与设置页芯片经 `SliceStore.icon(for:)` 自动走新路径）。

- [ ] **Step 4: 跑全部单测确认绿**

Run: 全量命令
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add NemoLoop/Plugins/SystemPlugin.swift NemoLoop/Services/ActionResolver.swift NemoLoop/Services/Launcher.swift NemoLoop/Services/PluginRegistry.swift NemoLoop/Model/SliceStore.swift NemoLoop/Helpers/SymbolPlate.swift NemoLoop/Ring/RingSummoner.swift NemoLoopTests/SystemPluginTests.swift NemoLoopTests/ActionResolverTests.swift
git commit -m "feat(plugins): System plugin, registry-backed trigger routing, symbol plates"
```

---

### Task 4: 移除 `.system` case——旧数据解码映射 + 设置菜单数据源切换

**Files:**
- Modify: `NemoLoop/Model/SlotAction.swift`（删 `.system`、Codable 映射、identity/displayName）
- Modify: `NemoLoop/Settings/SettingsView.swift:148-153, 239-244`（两处 System 菜单数据源）
- Modify: `NemoLoop/Services/ActionResolver.swift`（删 `.system` 分支）
- Modify: `NemoLoop/Services/Launcher.swift`（删 `.system` 分支）
- Modify: `NemoLoop/Model/SliceStore.swift`（icon 删 `.system` 分支）
- Modify: `NemoLoop/Model/PluginModels.swift`（增 `isEnabledByDefault`）
- Modify: `NemoLoop/Services/PluginRegistry.swift`（三态启用初始化）
- Modify: `NemoLoop/Plugins/SystemPlugin.swift`（override 默认启用）
- Modify: `NemoLoopTests/SlotActionMigrationTests.swift`、`NemoLoopTests/SliceConfigTests.swift:28-39`（旧断言改新格式）
- Test: `NemoLoopTests/SlotActionMigrationTests.swift`、`NemoLoopTests/PluginRegistryTests.swift`

**Interfaces:**
- Consumes: Task 3 的 SystemPlugin（op id == SystemAction.rawValue）。
- Produces: `SlotAction` 终态四 case；旧 JSON `{"system":{"_0":"lockScreen"}}` 解码为 `.pluginOp(pluginID: "system", opID: "lockScreen")`；`NemoPlugin.isEnabledByDefault: Bool`（extension 默认 `false`，SystemPlugin override `true`）；`PluginRegistry` 启用判定三态化——key 未设置时取 `isEnabledByDefault`，显式设置（含 false）永远尊重用户。

- [ ] **Step 1: 改测试表达迁移语义（先红）**

`SlotActionMigrationTests.swift`：`legacySystemJSONStillDecodes` 改为：

```swift
    @Test func legacySystemJSONMapsToPluginOp() throws {
        // 磁盘上的 v3 时代数据：SystemAction 原样落成 System 插件 op id。
        let cases = ["lockScreen", "sleepDisplays", "sleep", "missionControl", "ocr"]
        for raw in cases {
            let json = #"{"system":{"_0":"\#(raw)"}}"#.data(using: .utf8)!
            let decoded = try JSONDecoder().decode(SlotAction.self, from: json)
            #expect(decoded == .pluginOp(pluginID: "system", opID: raw))
        }
        // 未知 system 值不崩：降级为占位 op id，数据不丢。
        let unknown = #"{"system":{"_0":"legacyThing"}}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SlotAction.self, from: unknown)
        #expect(decoded == .pluginOp(pluginID: "system", opID: "legacyThing"))
    }
```

`SliceConfigTests.mixedActionTypesAndChildrenRoundTrip`：把 `.system(.lockScreen)`/`.system(.missionControl)`/`.system(.sleep)` 全部替换为 `.pluginOp(pluginID: "system", opID: "lockScreen")` 等对应 op id。

`PluginRegistryTests.swift` 追加出厂默认启用测试（`.system` 一移除，registry 的 enabled 门槛就是系统动作的唯一通路——默认启用必须与本任务同落，否则老用户升级后系统动作全部哑火）：

```swift
    @Test func systemPluginEnabledByDefaultAndDisablePersists() async throws {
        // 全新 defaults：System 出厂即连（key 未写入）。
        let defaults = makeDefaults()
        let fresh = PluginRegistry(defaults: defaults, plugins: [SystemPlugin()])
        #expect(fresh.isEnabled("system"))

        // 显式断开持久化为 false；重开恢复——用户选择永远压过出厂默认。
        try await fresh.setEnabled("system", false)
        let afterDisable = PluginRegistry(defaults: defaults, plugins: [SystemPlugin()])
        #expect(!afterDisable.isEnabled("system"))

        try await afterDisable.setEnabled("system", true)
        #expect(PluginRegistry(defaults: defaults, plugins: [SystemPlugin()]).isEnabled("system"))
    }

    @Test func nonDefaultPluginsStayDisabledOnFreshDefaults() {
        let stub = StubPlugin([StubOp("a")])   // isEnabledByDefault = false（协议默认）
        let registry = PluginRegistry(defaults: makeDefaults(), plugins: [stub])
        #expect(!registry.isEnabled("stub"))
    }
```

- [ ] **Step 2: 跑测试确认失败**

Run: 全量命令 + `-only-testing:NemoLoopTests/SlotActionMigrationTests`
Expected: FAIL（`.system` 还在，解出 `.system` 而非 `.pluginOp`）。

- [ ] **Step 3: 实现**

`SlotAction.swift`：删 `case system(SystemAction)`；`CodingKeys` 删 `system` key；`init(from:)` 的 system 分支改为（**保留嵌套 `_0` 形状**，未知值不校验直接映射）：

```swift
        if container.contains(.system) {
            let nested = try container.nestedContainer(keyedBy: LegacySystemKeys.self, forKey: .system)
            let raw = try nested.decode(String.self, forKey: ._0)
            self = .pluginOp(pluginID: "system", opID: raw)
            return
        }
```

`private enum LegacySystemKeys: String, CodingKey { case _0 }`。编码侧不再产生 `system` key。`identity`/`displayName` 删 system 分支。`SystemAction` 枚举本身保留（SystemPlugin 内部用），`SlotEntry.childLimit` 无 system 分支（本来就走 default）。

逐处删 `.system` 编译错：
- `Launcher.run` 删 `case .system` 分支。
- `ActionResolver` 两个 switch 删 `case .system`。
- `SliceStore.icon(for:)` 删 `.system` 分支。
- `SettingsView.swift:148-153` 主槽菜单与 `:239-244` 子槽菜单：`ForEach(SystemAction.allCases)` 改为经注册表（System 插件）：

```swift
Menu("System") {
    if let system = PluginRegistry.shared.plugin(id: "system") {
        ForEach(system.operations) { op in
            Button(op.displayName) {
                store.setAction(.pluginOp(pluginID: system.id, opID: op.id), at: i)
            }
        }
    }
}
```

（子槽菜单同理用 `store.addChild(.pluginOp(pluginID: system.id, opID: op.id), at: i)`。Task 5 会把这两处菜单重做成通用 Plugins 菜单，此处先用最小改动保编译绿。）

出厂默认启用（三态）：

```swift
// PluginModels.swift —— NemoPlugin extension 增：
var isEnabledByDefault: Bool { false }

// SystemPlugin.swift —— 增：
var isEnabledByDefault: Bool { true }

// PluginRegistry.swift —— init 的 enabledIDs 构建改为三态：
// key 未写入 → isEnabledByDefault；显式写入（含 false）→ 用户选择优先。
private func initialEnabled(_ plugin: any NemoPlugin, defaults: UserDefaults) -> Bool {
    let key = Self.enabledKey(plugin.id)
    if defaults.object(forKey: key) != nil { return defaults.bool(forKey: key) }
    return plugin.isEnabledByDefault
}
```

（`enabledKey(_:)` 是 Task 2 已有的 key 组装辅助；`setEnabled` 不变——它总是显式写入 bool。）

- [ ] **Step 4: 跑全部单测确认绿**

Run: 全量命令
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(model)!: drop .system slot action — legacy data maps to System plugin ops"
```

---

### Task 5: 设置页 Plugins 标签 + 槽位菜单重做

**Files:**
- Create: `NemoLoop/Settings/PluginsTab.swift`
- Modify: `NemoLoop/Settings/SettingsView.swift`（`SettingsTab` 增 `.plugins`；两处槽位菜单重做）
- Modify: `NemoLoop/Model/SliceStore.swift`（增 `attachWholePlugin`）
- Test: `NemoLoopTests/SliceStorePluginTests.swift`（新建）

**Interfaces:**
- Consumes: Task 2 registry、Task 3 SystemPlugin、Task 4 四 case 模型。
- Produces: `SettingsTab.plugins`；`PluginCard`（卡片视图）；`SliceStore.attachWholePlugin(_ pluginID: String, at index: Int, registry: PluginRegistry = .shared)`——action 置 `.plugin(id)`、children 置该插件全部操作（截断到 `childLimit`）。

- [ ] **Step 1: 写失败测试**

```swift
// NemoLoopTests/SliceStorePluginTests.swift
import Testing
import Foundation
@testable import NemoLoop

@MainActor
struct SliceStorePluginTests {
    private func makeStore() -> SliceStore {
        let name = "slice-store-plugin-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return SliceStore(defaults: d)
    }

    @Test func attachWholePluginFillsChildrenWithAllOps() {
        let store = makeStore()
        store.attachWholePlugin("system", at: 0)
        let entry = store.config.slots[0]
        guard case .plugin("system") = entry.action else {
            Issue.record("expected whole-plugin action"); return
        }
        #expect(entry.children.count == 5)      // System 插件 5 op，低于 8 上限
        #expect(entry.children.first == .pluginOp(pluginID: "system", opID: "lockScreen"))

        store.persistNowForTesting()            // 见下：测试用落盘钩子
        let store2 = SliceStore(defaults: UserDefaults(suiteName: store.testingSuiteName!)!)
        #expect(store2.config.slots[0] == entry)
    }

    @Test func attachTruncatesOpsBeyondLimit() {
        let store = makeStore()
        store.attachWholePlugin("stub9", at: 1) // 测试注册表：9 个 op 的假插件
        #expect(store.config.slots[1].children.count == SlotEntry.maxPluginChildren)
    }

    @Test func replacingPluginSlotTrimsChildrenToNewLimit() {
        let store = makeStore()
        store.setAction(.plugin("stub9"), at: 2)
        store.addChild(.pluginOp(pluginID: "stub9", opID: "op0"), at: 2)
        store.setAction(.pluginOp(pluginID: "system", opID: "ocr"), at: 2)  // 降回手动槽
        #expect(store.config.slots[2].children.count <= SlotEntry.maxManualChildren)
    }
}
```

> 测试需要两个小钩子（加在 `SliceStore`，`@inline(__always)` 私有性质注释标明测试专用）：`persistNowForTesting()`（调 `persist()`）与 `testingSuiteName: String?`（init 存下 suite 名）。`stub9` 假插件经 `PluginRegistry(defaults:plugins:)` 注入——`attachWholePlugin` 带 registry 参数正是为此：

```swift
func attachWholePlugin(_ pluginID: String, at index: Int, registry: PluginRegistry = .shared) {
    guard config.slots.indices.contains(index), let plugin = registry.plugin(id: pluginID) else { return }
    let ops = plugin.operations.prefix(SlotEntry.childLimit(for: .plugin(pluginID)))
    config.slots[index].action = .plugin(pluginID)
    config.slots[index].children = ops.map { .pluginOp(pluginID: pluginID, opID: $0.id) }
}
```

`setAction` 增修剪（换槽类型时 children 超限截断）：

```swift
func setAction(_ action: SlotAction?, at index: Int) {
    guard config.slots.indices.contains(index) else { return }
    config.slots[index].action = action
    let limit = SlotEntry.childLimit(for: action)
    if config.slots[index].children.count > limit {
        config.slots[index].children = Array(config.slots[index].children.prefix(limit))
    }
}
```

`stub9` 定义放测试文件里（复用 Task 2 的 StubPlugin 模式，9 个 StubOp）。

- [ ] **Step 2: 跑测试确认失败**

Run: 全量命令 + `-only-testing:NemoLoopTests/SliceStorePluginTests`
Expected: FAIL —— `attachWholePlugin` 不存在。

- [ ] **Step 3: 实现**

SliceStore 两方法如上。`SettingsTab` 增 case：

```swift
case general, ring, plugins, appearance, about
// title: "Plugins"; image: Image(systemName: "puzzlepiece.extension")
```

`paneContent` 增 `case .plugins: PluginsTab(registry: PluginRegistry.shared, store: store)`。

```swift
// NemoLoop/Settings/PluginsTab.swift
import Luminare
import SwiftUI

/// 每个内置插件一张卡：状态徽章 + 连接开关 + 可展开配置区。
/// 连接失败内联红字并弹回 off，不静默。
struct PluginsTab: View {
    @Bindable var registry: PluginRegistry   // 观察 enabledIDs 变化需要 registry 可绑定
    let store: SliceStore

    var body: some View {
        LuminareSection("Plugins",
                        "Connect feature packs. Slots already on the ring keep their data — a disconnected plugin just dims.") {
            ForEach(registry.plugins) { plugin in
                PluginCard(plugin: plugin, registry: registry)
            }
        }
    }
}

private struct PluginCard: View {
    let plugin: any NemoPlugin
    @Bindable var registry: PluginRegistry
    @State private var expanded = false
    @State private var errorText: String?
    @State private var busy = false

    var body: some View {
        LuminareCompose(alignment: .center) {
            HStack(spacing: 6) {
                if busy { ProgressView().controlSize(.small) }
                Toggle("", isOn: Binding(
                    get: { registry.isEnabled(plugin.id) },
                    set: { on in Task { await toggle(on) } }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: plugin.symbolName)
                    .font(.system(size: 16))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(plugin.displayName)
                    Text(plugin.summary).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                statusBadge
                if plugin.configSections != nil {
                    Button { withAnimation(.smooth(duration: 0.2)) { expanded.toggle() } } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        if expanded, let sections = plugin.configSections { sections }
        if let errorText {
            Text(errorText).font(.caption).foregroundStyle(.red)
        }
    }

    private var statusBadge: some View {
        Circle().fill(color).frame(width: 8, height: 8)
            .help(helpText)
    }
    private var color: Color {
        plugin.status == .ready ? .green : (plugin.status == .needsAuth ? .yellow : .gray)
    }
    private var helpText: String {
        switch plugin.status {
        case .ready: "Ready"; case .needsAuth: "Needs authorization"; case .notInstalled: "Not installed"
        }
    }

    private func toggle(_ on: Bool) async {
        busy = true; errorText = nil
        defer { busy = false }
        do { try await registry.setEnabled(plugin.id, on) }
        catch { errorText = "Connect failed: \(error.localizedDescription)" }
    }
}
```

> `ForEach(registry.plugins)`：`any NemoPlugin` 已 `Identifiable`（协议继承）。System 插件 `status == .ready`、`configSections == nil`，卡片自然成立。

两处槽位菜单重做（`SettingsView.swift:148-153` 与 `:239-244`）——替换 Task 4 的临时 System 菜单：

```swift
// 主槽：
Menu("Plugins") {
    ForEach(PluginRegistry.shared.plugins.filter { PluginRegistry.shared.isEnabled($0.id) }) { plugin in
        Button("Whole: \(plugin.displayName)") {
            store.attachWholePlugin(plugin.id, at: i)
        }
        Menu(plugin.displayName) {
            ForEach(plugin.operations) { op in
                Button(op.displayName) {
                    store.setAction(.pluginOp(pluginID: plugin.id, opID: op.id), at: i)
                }
            }
        }
    }
}
```

子槽菜单同构，动作用 `store.addChild(.pluginOp(pluginID: plugin.id, opID: op.id), at: i)`，去掉 "Whole" 项（子槽无整体挂载）。

- [ ] **Step 4: 跑全部单测确认绿 + 实机看一眼设置页**

Run: 全量命令；然后构建启动（`CODE_SIGN_IDENTITY="NemoLoopDev" DEVELOPMENT_TEAM="" CODE_SIGN_STYLE=Manual`，启动前 `pkill -x NemoLoop`），Settings → Plugins：System 卡可开可关；Ring 标签 Configure → Plugins 子菜单出现 "Whole: System" 与五个操作。
Expected: 单测 PASS；手动检查项如上。

- [ ] **Step 5: Commit**

```bash
git add NemoLoop/Settings/PluginsTab.swift NemoLoop/Settings/SettingsView.swift NemoLoop/Model/SliceStore.swift NemoLoopTests/SliceStorePluginTests.swift
git commit -m "feat(settings): Plugins tab with connect cards; slot menus list connected plugins"
```

---

### Task 6: 环上暗态——禁用插件的扇叶降饱和 + 触发无效（触发侧已由 registry 天然兜底）

**Files:**
- Modify: `NemoLoop/Model/SliceStore.swift`（增 `isEnabled(_:)`）
- Modify: `NemoLoop/Ring/RingView.swift`（图标暗态 + tooltip）
- Test: `NemoLoopTests/SliceStorePluginTests.swift`（追加）

**Interfaces:**
- Consumes: registry enabled 状态。
- Produces: `SliceStore.isEnabled(_ action: SlotAction?) -> Bool`——app/folder 恒 true；`.plugin`/`.pluginOp` 查 `PluginRegistry.shared.isEnabled` 且（对 op）op 存在；`.system` 已不存在。触发链无需改：Task 3 起 `registry.perform` 对禁用即静默返回。

- [ ] **Step 1: 追加失败测试**

```swift
    @Test func disabledPluginActionReportsDisabled() async throws {
        let store = makeStore()
        try await PluginRegistry.shared.setEnabled("system", true)
        #expect(store.isEnabled(.pluginOp(pluginID: "system", opID: "lockScreen")))
        try await PluginRegistry.shared.setEnabled("system", false)
        #expect(!store.isEnabled(.pluginOp(pluginID: "system", opID: "lockScreen")))
        #expect(!store.isEnabled(.plugin("system")))
        #expect(store.isEnabled(.app(URL(filePath: "/A.app"))))
        try await PluginRegistry.shared.setEnabled("system", true)   // 还原现场
    }
```

- [ ] **Step 2: 跑测试确认失败**

Run: 全量命令 + `-only-testing:NemoLoopTests/SliceStorePluginTests`
Expected: FAIL —— `isEnabled` 不存在。

- [ ] **Step 3: 实现**

```swift
/// 暗态规则：插件禁用或操作缺失时扇叶降饱和、点击无效（perform 侧已兜底）。
func isEnabled(_ action: SlotAction?) -> Bool {
    guard let action else { return false }
    switch action {
    case .app, .folder:
        return true
    case .plugin(let id):
        return PluginRegistry.shared.isEnabled(id) && PluginRegistry.shared.plugin(id: id) != nil
    case .pluginOp(let pluginID, let opID):
        return PluginRegistry.shared.op(pluginID: pluginID, opID: opID) != nil
            && PluginRegistry.shared.isEnabled(pluginID)
    }
}
```

> `op(pluginID:opID:)` 返回非 nil 即插件存在且 op 存在，与 enabled 合取即完整条件。

`RingView.swift`：找到槽位图标渲染处（搜 `store.icon(at:`）。图标 `Image` 链上加：

```swift
.opacity(store.isEnabled(entry.action) ? 1 : 0.35)
.saturation(store.isEnabled(entry.action) ? 1 : 0)
.help(!store.isEnabled(entry.action) ? "Plugin disconnected" : "")
```

（`entry` 为该槽 `SlotEntry`；若图标块只持有 index，就在同层取 `store.config.slots[i]`。tooltip 空串等于无 tooltip，enabled 时保持原状。）

- [ ] **Step 4: 跑全部单测确认绿**

Run: 全量命令
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add NemoLoop/Model/SliceStore.swift NemoLoop/Ring/RingView.swift NemoLoopTests/SliceStorePluginTests.swift
git commit -m "feat(ring): dimmed blades for disconnected plugin actions"
```

---

### Task 7: Appearance 插件（外观切换）

**Files:**
- Create: `NemoLoop/Plugins/AppearancePlugin.swift`
- Modify: `NemoLoop/Services/PluginRegistry.swift`（shared 登记）
- Test: `NemoLoopTests/AppearancePluginTests.swift`（新建）

**Interfaces:**
- Consumes: Task 2 协议。Shell 执行抽象为可注入 `ShellRunning`（`func run(executable: String, arguments: [String]) throws`），生产实现 `ProcessShellRunner` 包 `Process`。
- Produces: `AppearancePlugin`（id `"appearance"`，单 op `toggleDarkMode`，displayName "Toggle Appearance"，symbol `circle.lefthalf.filled`；perform 经 runner 跑 `osascript -e <script>`）；`ProcessShellRunner`（Task 8 Screenshot 不用、媒体插件将复用）。

- [ ] **Step 1: 写失败测试**

```swift
// NemoLoopTests/AppearancePluginTests.swift
import Testing
import Foundation
@testable import NemoLoop

@MainActor
struct AppearancePluginTests {
    private final class RecordingRunner: ShellRunning {
        var calls: [(String, [String])] = []
        func run(executable: String, arguments: [String]) throws {
            calls.append((executable, arguments))
        }
    }

    @Test func opFiresOsascriptToggle() throws {
        let runner = RecordingRunner()
        let plugin = AppearancePlugin(runner: runner)
        #expect(plugin.id == "appearance")
        #expect(plugin.status == .ready)

        let op = plugin.operations.first!
        #expect(op.id == "toggleDarkMode")
        #expect(op.displayName == "Toggle Appearance")

        op.perform()
        #expect(runner.calls.count == 1)
        let (exe, args) = runner.calls[0]
        #expect(exe == "/usr/bin/osascript")
        #expect(args.count == 2)
        #expect(args[0] == "-e")
        #expect(args[1].contains("set dark mode to not dark mode"))
    }

    @Test func performFailureDoesNotCrash() throws {
        struct ExplodingRunner: ShellRunning {
            func run(executable: String, arguments: [String]) throws { throw URLError(.badURL) }
        }
        let plugin = AppearancePlugin(runner: ExplodingRunner())
        plugin.operations.first!.perform()   // 抛错被 op 内部吞掉并 NSLog
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: 全量命令 + `-only-testing:NemoLoopTests/AppearancePluginTests`
Expected: FAIL —— `ShellRunning` 不存在。

- [ ] **Step 3: 实现**

`ShellRunning`/`ProcessShellRunner` 放 `NemoLoop/Services/ShellRunner.swift`：

```swift
import Foundation

/// 命令执行的抽象，仅为可测试：插件不直接 spawn Process。
protocol ShellRunning: AnyObject {
    func run(executable: String, arguments: [String]) throws
}

final class ProcessShellRunner: ShellRunning {
    func run(executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        try process.run()
    }
}
```

```swift
// NemoLoop/Plugins/AppearancePlugin.swift
import Foundation

/// 单操作插件：亮↔暗一键切换。走 System Events 的 AppleScript——首次触发
/// 弹一次"自动化"授权（TCC），环自身主题三档不受影响。
@MainActor
final class AppearancePlugin: NemoPlugin {
    private static let script =
        "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"

    private let runner: any ShellRunning

    init(runner: any ShellRunning = ProcessShellRunner()) { self.runner = runner }

    let id = "appearance"
    let displayName = "Appearance"
    let symbolName = "circle.lefthalf.filled"
    let summary = "One-tap Light/Dark system appearance toggle."

    struct Op: PluginOp {
        let id = "toggleDarkMode"
        let displayName = "Toggle Appearance"
        let symbolName = "circle.lefthalf.filled"
        let runner: any ShellRunning
        func perform() {
            do { try runner.run(executable: "/usr/bin/osascript", arguments: ["-e", AppearancePlugin.script]) }
            catch { NSLog("NemoLoop appearance toggle failed: \(error)") }
        }
    }

    var operations: [any PluginOp] { [Op(runner: runner)] }
    var status: PluginStatus { .ready }
}
```

`PluginRegistry.shared` 登记：`[SystemPlugin(), AppearancePlugin()]`。

- [ ] **Step 4: 跑全部单测确认绿**

Run: 全量命令
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add NemoLoop/Plugins/AppearancePlugin.swift NemoLoop/Services/ShellRunner.swift NemoLoop/Services/PluginRegistry.swift NemoLoopTests/AppearancePluginTests.swift
git commit -m "feat(plugins): appearance toggle plugin via osascript"
```

---

### Task 8: Screenshot 插件（区域截图到剪贴板）

**Files:**
- Modify: `NemoLoop/Services/Ocr/OcrSessionController.swift`（增 `CaptureMode`，入口带 mode，截完分流）
- Create: `NemoLoop/Plugins/ScreenshotPlugin.swift`
- Modify: `NemoLoop/Services/PluginRegistry.swift`（shared 登记）
- Test: `NemoLoopTests/ScreenshotPluginTests.swift`（新建）

**Interfaces:**
- Consumes: Task 2 协议。
- Produces: `OcrSessionController.CaptureMode { ocr, snip }`；`handleOcrRequested()` 保留（= `handleRequested(mode: .ocr)`，SystemPlugin 的 ocr op 继续调它）；新 `handleRequested(mode: CaptureMode)`；`ScreenshotPlugin`（id `"screenshot"`，单 op `snipToClipboard`，symbol `camera.viewfinder`，perform 调 `OcrSessionController.shared.handleRequested(mode: .snip)`）。

- [ ] **Step 1: 写失败测试**

```swift
// NemoLoopTests/ScreenshotPluginTests.swift
import Testing
import Foundation
@testable import NemoLoop

@MainActor
struct ScreenshotPluginTests {
    @Test func singleOpMetadata() {
        let plugin = ScreenshotPlugin()
        #expect(plugin.id == "screenshot")
        #expect(plugin.operations.count == 1)
        let op = plugin.operations.first!
        #expect(op.id == "snipToClipboard")
        #expect(op.symbolName == "camera.viewfinder")
        #expect(plugin.status == .ready)   // 屏幕录制授权运行时才知道；卡片徽章按 ready 呈现
    }

    @Test func ocrEntryStillRoutesToOcrMode() {
        // SystemPlugin 的 ocr op 语义不变：handleOcrRequested 就是 .ocr 模式。
        #expect(OcrSessionController.CaptureMode.ocr.isOcrFlow)
        #expect(!OcrSessionController.CaptureMode.snip.isOcrFlow)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: 全量命令 + `-only-testing:NemoLoopTests/ScreenshotPluginTests`
Expected: FAIL —— `ScreenshotPlugin` 不存在。

- [ ] **Step 3: 实现**

`OcrSessionController.swift`：

```swift
enum CaptureMode {
    case ocr   // 框选 → 识别 → 翻译 → 预览面板
    case snip  // 框选 → 像素直接进剪贴板

    var isOcrFlow: Bool { self == .ocr }
}

func handleOcrRequested() { handleRequested(mode: .ocr) }

func handleRequested(mode: CaptureMode) {
    guard selectionPanel == nil, permissionPanel == nil else { return }
    self.mode = mode
    // …原 handleOcrRequested 的 preflight 分支不动…
}
```

类增 `private var mode: CaptureMode = .ocr`；`process(rect:screen:excluding:)` 在**截图成功拿到图像后、进入 OCR 之前**插分流：

```swift
if mode == .snip {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.writeObjects([image])
    showToast("Snipped to clipboard")   // 复用现有空结果 toast 管线；文案按现有 toast 风格
    return
}
```

（`image` 为该函数内已有的捕获产物变量名，以实际为准；若捕获结果是 CGImage/NSImage 类型不同，用 `NSImage(cgImage:size:)` 包一层。toast 若无通用方法，复用 `showResult` 旁的 toast 面板代码路径，保持一次性自动关闭。）

```swift
// NemoLoop/Plugins/ScreenshotPlugin.swift
import Foundation

/// 单操作插件：⌘⇧4 式框选，像素直进剪贴板——复用 OCR 的选区与授权链路。
@MainActor
final class ScreenshotPlugin: NemoPlugin {
    let id = "screenshot"
    let displayName = "Screenshot"
    let symbolName = "camera.viewfinder"
    let summary = "Drag a region; the pixels go straight to your clipboard."

    struct Op: PluginOp {
        let id = "snipToClipboard"
        let displayName = "Snip to Clipboard"
        let symbolName = "camera.viewfinder"
        func perform() { OcrSessionController.shared.handleRequested(mode: .snip) }
    }

    var operations: [any PluginOp] { [Op()] }
    var status: PluginStatus { .ready }
}
```

`PluginRegistry.shared` 登记：`[SystemPlugin(), AppearancePlugin(), ScreenshotPlugin()]`。

- [ ] **Step 4: 跑全部单测确认绿**

Run: 全量命令
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add NemoLoop/Services/Ocr/OcrSessionController.swift NemoLoop/Plugins/ScreenshotPlugin.swift NemoLoop/Services/PluginRegistry.swift NemoLoopTests/ScreenshotPluginTests.swift
git commit -m "feat(plugins): snip-to-clipboard plugin reusing the OCR selection flow"
```

---

### Task 9: 渲染验证——15°/8 子轮盘 + 暗态扇叶 + 缺口方位

**Files:**
- Create: `Design/render_check_plugin_subwheel.swift`（一次性 harness，验完保留供回归）

**Interfaces:**
- Consumes: 全部前序任务的最终形态。

- [ ] **Step 1: 写渲染脚本**

沿用仓库既有渲染自查模式（`ImageRenderer` + 先让视图 `preAppear` 走完发牌动画、否则子轮盘是幽灵态；`NSApp.run()` 必须跑起 runloop）。脚本骨架——先读 `RingView` 的真实初始化签名再对齐参数，配置一个 8 操作的插件槽：

```swift
// Design/render_check_plugin_subwheel.swift
// swift Design/render_check_plugin_subwheel.swift
import AppKit
import SwiftUI

// 检查清单（对照 spec 渲染验证节）：
// 1. 二级扇叶 15° 网格、8 片全部可见，带在图标下方（外圈）
// 2. 缺口方位空（wrap gap 无人居住）
// 3. 断开插件的扇叶降饱和、其余正常

@MainActor
final class RenderCheck {
    static func main() {
        let store = SliceStore()   // 默认 UserDefaults——专用 suite 更干净，见下
        // 槽 0 挂 System 插件整体（5 op），再手动补 3 个 pluginOp 到 8 片：
        store.attachWholePlugin("system", at: 0)
        for extra in ["toggleDarkMode", "snipToClipboard", "extraOp"] {
            store.addChild(.pluginOp(pluginID: "media", opID: extra), at: 0)
        }
        // …按 RingView 真实签名构造：注入 store、preAppear 完成发牌、
        //    ImageRenderer(size:) 出 PNG 到 Design/render_check_subwheel.png…
        let renderer = ImageRenderer(content: /* ringView */)
        renderer.scale = 2
        if let png = renderer.nsImage.tiffRepresentation… { /* 写文件 */ }
        NSApp.terminate(nil)
    }
}

// @main 换成显式启动：NSApplication.shared + RenderCheck.main() + NSApp.run()
```

> 落笔时必须把注释占位换成真代码：以 `RingView` 当前 init/依赖为准（读 `RingView.swift` 顶部与调用点），视图发牌动画用 `task { try? await Task.sleep(...) }` 或视图内既有 preAppeared 通道喂满后再 render。**极暗背景下必须像素直方图验证**（读取 PNG、统计非零像素比例），不能只看导出成功。

- [ ] **Step 2: 跑脚本、按清单逐项核验 PNG**

Run: `swift Design/render_check_plugin_subwheel.swift`，然后 Read 导出的 PNG 逐项对照清单（8 片 15°、带在图标下、缺口方位空、暗态降饱和可辨）。
Expected: 四项全过；任何一项不过 → 修渲染/容量常量后重跑（容量是 `SlotEntry.maxPluginChildren` 单常量）。

- [ ] **Step 3: Commit**

```bash
git add Design/render_check_plugin_subwheel.swift
git commit -m "test(render): plugin sub-wheel render check harness (8 blades, dim state)"
```

---

### Task 10: 全量回归 + 实机验收清单

**Files:** 无新文件。

- [ ] **Step 1: 全量单测**

Run: Global Constraints 的全量命令
Expected: 全绿。

- [ ] **Step 2: 构建并启动（先杀旧实例）**

```bash
pkill -x NemoLoop 2>/dev/null; xcodebuild build -project NemoLoop.xcodeproj -scheme NemoLoop -destination 'platform=macOS' CODE_SIGN_IDENTITY="NemoLoopDev" DEVELOPMENT_TEAM="" CODE_SIGN_STYLE=Manual
open ~/Library/Developer/Xcode/DerivedData/NemoLoop-*/Build/Products/Debug/NemoLoop.app
```

- [ ] **Step 3: 手动验收清单**

1. Settings → Plugins：System/Appearance/Screenshot 三卡；关掉 Appearance 后 Ring 槽位菜单不再出现它、已挂扇叶变暗、点击无效；重开恢复。
2. Appearance 连接后挂到槽位，触发一次——系统亮暗切换、首次弹"自动化"授权。
3. Screenshot 触发——框选后 ⌘V 能贴出图。
4. 老用户升级路径：删 `~/Library/Preferences/…plist` 之前先用旧版写一个 `.system` 槽位再升级启动，槽位应等效保留（解为 System 插件 op）。
5. 菜单栏面板（menubar 两个分段）里的系统动作照常工作（`Launcher.run` 单点改造覆盖）。

- [ ] **Step 4: Commit（如有修复）**

```bash
git add -A && git commit -m "fix(plugins): acceptance pass adjustments"
```

---

## 计划自检记录

- **Spec 覆盖**：协议/注册表→T2；System 插件化+旧数据映射→T3/T4；Plugins 标签+卡片+菜单→T5；暗态规则→T6；Appearance/Screenshot→T7/T8；15°/容量常量+渲染验证→T9；触发统一入口→T3（Launcher）。Media/AI 插件按 spec"按路线图顺序落地"，另有独立迁移计划，不在本计划内。
- **占位符**：T9 的渲染脚本骨架标注了"以 RingView 真实签名为准"并给出对齐步骤与像素直方图要求——这是对既有 throwaway harness 模式的显式引用，非未决设计；其余任务代码完整。
- **类型一致性**：`attachWholePlugin`/`childLimit`/`setEnabled`/`perform(pluginID:opID:)`/`ShellRunning.run(executable:arguments:)` 各任务间签名已互检一致。
