# 已打开应用环（Running-Apps Ring）— 设计

**日期**: 2026-07-04
**范围**: 新增一个「运行中应用」服务、第二个快捷键，以及一个扇形数量随打开应用数动态变化的环

## 目标

在现有的 launcher 环（6 个固定配置槽、按住唤出、松开启动）之外，新增：

1. 一个获取当前已打开应用的服务。
2. 一个新的、可在设置中自定义的快捷键。
3. 按住该快捷键唤出一个环——**有几个打开的应用就有几个扇形**（动态数量），松开时**切换到（激活）**松开位置那个应用。

交互与现有 launcher 环一致：**按住唤出、松开选中**。应用按**最近使用（MRU）优先**排序，数量上限 **10**。

## 方案（方案 A：解耦 RingView，快照驱动）

把 `RingView` 从 `SliceStore` 解耦，改为渲染一个不可变的图标数组；`HotkeyService` 提供通用的 summon 流程，两个快捷键各自构造图标和「选中动作」。环、窗口、`RingViewModel` 全部复用。环是瞬时显示（按住期间数据不变），因此快照驱动等价于实时绑定且更简单。

### 1. `RunningAppsService`（新增，`NemoLoop/Services/RunningAppsService.swift`）

`@MainActor @Observable`，常驻（由 `AppDelegate` 持有）。

- 监听 `NSWorkspace.shared.notificationCenter` 的 `NSWorkspace.didActivateApplicationNotification`，维护一个 `[pid_t]` 的 MRU 顺序（最近激活的排最前）。init 时用当前 `NSWorkspace.shared.frontmostApplication` 播种。
- `RunningApp`：`{ app: NSRunningApplication, name: String, icon: NSImage? }`，保留 `NSRunningApplication` 以便调用 `activate()`。
- `func snapshot(limit: Int) -> [RunningApp]`：
  - 过滤 `NSWorkspace.shared.runningApplications`，条件 `activationPolicy == .regular && !isTerminated`，并排除 NemoLoop 自身（`processIdentifier != ProcessInfo.processInfo.processIdentifier`）。
  - 按 MRU 排序，取 `prefix(limit)`。
- 排序抽为纯静态函数便于单测：
  `static func order(_ apps: [RunningApp], mru: [pid_t], limit: Int) -> [RunningApp]`
  —— MRU 列表中出现的应用按其在 MRU 中的位置排前，未出现的按传入（系统）顺序追加在后，最后 `prefix(limit)`。
- 日志：init/deinit（`.info`）、激活通知回调（`.debug`，记录 bundle id）、snapshot 结果数量（`.debug`）。

### 2. 环解耦（`NemoLoop/Ring/RingView.swift`、`RingViewModel.swift`）

- `RingView`：签名改为 `init(icons: [NSImage?], viewModel: RingViewModel)`。
  - `wedgeCount = icons.count`（不再用 `SliceConfig.wedgeCount`）。
  - 空槽判定由 `store.config.slots[i] == nil` 改为 `icons[i] == nil`。
  - 图标由 `store.icon(at:)` 改为 `icons[i]`。
  - 其余（`AnnulusShape` 环底、`WedgeShape`、高亮/动画/图标布局）不变。
- `RingViewModel.begin(centerGlobal:wedgeCount:)`：新增 `wedgeCount` 参数并存为属性；`sample()` 把它传给 `RingGeometry.wedgeIndex(..., wedgeCount:)`（该函数已支持该参数）。

### 3. `HotkeyService` 双快捷键（`NemoLoop/Services/HotkeyService.swift`）

- 新增 `KeyboardShortcuts.Name.summonRunningApps`（无默认绑定，用户自设）。
- 通用私有流程 `summon(icons: [NSImage?], onSelect: @escaping (Int) -> Void)`：
  - 记录本次会话的 `onSelect` 闭包与 `icons`。
  - `viewModel.begin(centerGlobal:wedgeCount: icons.count)`，`controller.show(content: RingView(icons:viewModel:), ...)`。
- `release()`：取 `viewModel.selectedIndex`，teardown，若有 index 则调用会话的 `onSelect(index)`。
- `.summonRing`（launcher）：`icons` = `store.config.slots.map { $0.map { NSWorkspace…icon } }`（复用 `store.icons`），`onSelect = { i in if let url = store.config.slots[i] { Launcher.launch(url: url) } }`。行为与现状一致。
- `.summonRunningApps`（新）：`let apps = runningApps.snapshot(limit: maxRunningAppWedges)`；**若 `apps.isEmpty` 则直接 return（不弹环）**；`icons = apps.map(\.icon)`，`onSelect = { i in apps[i].app.activate() }`。
- `maxRunningAppWedges` 常量置于 `RingTheme` 或 `HotkeyService`（默认 `10`）。

### 4. 设置与装配

- `SettingsView.ringSettings` 的 Hotkey 段增加第二个 `LuminareCompose` + `KeyboardShortcuts.Recorder("", name: .summonRunningApps)`，文案说明「按住显示已打开的应用，松开切换」。
- `AppDelegate`：新增 `let runningAppsService = RunningAppsService()`，构造 `HotkeyService` 时注入。

## 保持不变

- 环的视觉（连续磨砂圆环 backing、更宽的环、圆角扇形、间隙、图标、动画、命中测试）不变。
- launcher 环的行为与观感不变。
- `RingGeometry.wedgeIndex` 已支持 `wedgeCount` 参数，无需改动。

## 边界与错误处理

- 无其他打开的应用（仅 NemoLoop）：`snapshot` 为空 → 不弹环。
- 应用在唤出后、松开前退出：`NSRunningApplication.activate()` 对已终止实例返回 `false`，无副作用（记 `.warn`）。
- `activate()` 若在当前部署目标已弃用，使用可用的无参 `activate()`；必要时用 `activate(options:)` 兜底。

## 验证

- 构建：`xcodebuild -project NemoLoop.xcodeproj -scheme NemoLoop -destination 'platform=macOS' build`
- 单测（`NemoLoopTests`，Swift Testing）：`RunningAppsService.order(_:mru:limit:)` —— MRU 排序、未知应用追加、limit 截断。
- 真机：在 Settings 设 `summonRunningApps` 快捷键 → 按住 → 环按当前打开的应用数出扇形、按 MRU 排序 → 松开在某扇形上 → 切换到该应用。再验证 launcher 环行为未变。

## 未纳入（YAGNI）

- 不做常驻的应用列表 UI、不做实时刷新环、不做应用关闭按钮、不持久化 MRU（进程内维护即可）。
