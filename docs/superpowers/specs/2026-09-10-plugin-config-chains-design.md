# 插件自管配置地基 + 动作链插件(Chains)设计

日期:2026-09-10。状态:已与用户逐节确认,待审阅。
来源:Flick 动作集移植任务 P0 子项目(handoff:动作清单 + 上下文,2026-09-10)。

## 背景与目标

Flick 移植任务把约 65 个动作按依赖切成 P0–P9 子项目(见 handoff)。P0 是地基:当前
`PluginOp` 是静态无参列表(`id / displayName / symbolName / perform()`),而链、固定 URL、
文本片段、脚本等动作都需要**用户配置的数据**。P0 落两件事:

1. **插件自管配置模式**:插件自己持久化配置、从配置动态派生 `operations`、在
   `configSections` 提供 CRUD UI。这是后续 Web / TextClip / Automation 等子项目复用的模板。
2. **Chains 插件**(第一个消费方):动作链 = 多个动作串成一次触发、顺序执行;单步重复
   合并为链的字段(Flick 的两个 Combinator 合一)。

交互完全保留 NemoLoop 自己的(热键唤环 → 扇形叠环 → 槽位/二级扇叶级联)。

## 已确认决策(用户拍板)

| 决策点 | 结论 |
|---|---|
| 建模方案 | 插件自管配置 + 动态派生 op(候选:SlotAction 加参数 case / 中央 schema 仓库,均否) |
| 链步骤范围 | 任意**非链**动作:`.pluginOp` / `.app` / `.folder`;v1 不嵌套链 |
| 单步重复 | 合并为链字段(repeatCount),不设独立功能/独立 picker 入口 |
| 失败语义 | 任一步骤失败 → 中止整链 + 日志(不做"失败继续",留待有需求再说) |
| 延迟粒度 | 链级统一 interStepDelay,不设每步延迟 |

## 范围

**做**:ChainDefinition / ChainStore / ChainPlugin / ChainExecutor / 链构建器设置 UI /
ActionPickerPopover 回调化重构 + `.chainStep` 上下文 / `PluginRegistry.perform` 返回
`@discardableResult Bool` / AppOpening 与 ChainSleeping 两个测试 seam / 单测与渲染复查。

**不做**(后续子项目):Web/TextClip/Automation 等具体插件(复用本模式);嵌套链;每步
延迟;失败继续;步骤级暗态;键盘宏(TCC 授权流另行先问用户)。

**明确不动**:环端(RingView/RingViewModel/RingSnapshot/RingGeometry)、`SlotAction` 枚举
(无新 case、无迁移)、`Launcher`、SliceStore 持久化格式、槽位/子轮盘交互。

## 数据模型

```swift
// NemoLoop/Plugins/Chain/ChainDefinition.swift
struct ChainDefinition: Codable, Identifiable, Equatable {
    var id: UUID = UUID()                   // opID 即 uuidString,编辑不改 id
    var name: String                        // 用户命名
    var symbolName: String = "link"         // SF Symbol
    var steps: [SlotAction] = []            // 任意非链动作
    var repeatCount: Int = 1                // 1...20
    var interStepDelay: TimeInterval = 0.2  // 0...5 秒
}
```

上限常量(构建器与 store 双重钳制):链 ≤ 32(`maxChains`)、步骤 ≤ 16(`maxSteps`)。

## 存储与持久化

- `ChainStore`(`@MainActor`,`@Published private(set) var chains: [ChainDefinition]`),
  UserDefaults JSON,key:`nemoloop.plugin.chain.chains`(新 key,无迁移;与
  `nemoloop.plugin.<id>.enabled` 同风格,不混入 `nemoloop.slotEntries`)。
- API:`add / update / remove`,全部钳制上限;`SliceStore` 不知情。

## ChainPlugin

```swift
// NemoLoop/Plugins/Chain/ChainPlugin.swift
@MainActor final class ChainPlugin: NemoPlugin {
    let id = "chain"; let displayName = "Chains"; let symbolName = "link"
    let summary = "把多个动作串成一键序列,可设重复次数与步间延迟"
    let isEnabledByDefault = true          // 出厂连接;status 恒 .ready(无授权需求)
    var operations: [any PluginOp] { store.chains.map { ChainOp(definition: $0, executor: executor) } }
    let configSections: AnyView?           // ChainConfigSection(store:)
    // 构造注入:ChainPlugin(store: ChainStore = ..., executor: ChainExecuting = ...),沿
    // AppearancePlugin 注入 ShellRunning 的测试惯例
}
```

- `ChainOp: PluginOp`:id = 链 uuid 字符串、displayName = 链名、symbolName = 链图标;
  `perform()` 以 `Task` 异步发起 `executor.run(definition)`(环面板不等待多秒链跑完)。
- **编辑跟随**:链名/图标/步骤变更后 uuid 不变,已挂载槽位展示自动更新(动态派生收益)。
- 执行中编辑链:在跑的链持有当时的 definition 值拷贝,不受编辑影响。

## ChainExecutor

```swift
// NemoLoop/Plugins/Chain/ChainExecutor.swift
@MainActor protocol ChainExecuting { func run(_ chain: ChainDefinition) async }
```

语义(全部经设计确认):

1. **重入保护**:同一链(id)执行中再次触发 → 忽略 + NSLog(executor 持 `running: Set<UUID>`)。
2. **顺序执行**:迭代 `repeatCount` 轮,轮内按 `steps` 顺序执行。
3. **延迟规则**:除整次运行的**第一步**外,每个步骤执行前等待 `interStepDelay`
   (迭代间过渡同样适用;`interStepDelay == 0` 不等待)。
4. **失败即中止**:步骤失败 → 停止整链 + NSLog;已执行的不回滚。
5. 步骤分派:
   - `.pluginOp(p, o)` → `registry.perform(pluginID: p, opID: o)`,以返回 Bool 判成败;
   - `.app(url)` / `.folder(url)` → `AppOpening` seam(`func open(_ url: URL) -> Bool`,
     真实现包 `NSWorkspace.shared.open`);
   - `.plugin`(整挂)→ 构建器已过滤不可达,执行器防御性按失败处理 + NSLog。

装配:`PluginRegistry.shared` 构造插件时无法把自身引用传给 executor(初始化期循环),
故 `ChainExecutor` 默认实现**执行时**才取 `PluginRegistry.shared`;测试注入自定义
registry / stub。

### 既有代码唯一 API 改动

`PluginRegistry.perform(pluginID:opID:)` 返回值从 `Void` 改为
`@discardableResult Bool`(op 缺失/插件禁用 → false;现有丢弃返回值的调用点零改动)。

## 设置 UI(环端零改动)

### PluginsTab → Chains 卡片

既有 `PluginCard` 模式:开关 + 状态徽章 + 可展开 `configSections`。展开区:

- **链列表**:行 = 链图标 + 链名 + 摘要(如"3 步 × 2 次"),点击行内展开编辑(沿
  1562576 子动作行内可折叠模式);底部"+ 新建链"。链满 32 条时禁用新建。
- **链编辑器**:
  - 名称 TextField;
  - 图标:预设符号横排芯片(10 个:`link` `bolt` `clock` `arrow.triangle.2.circlepath`
    `square.stack.3d.up` `globe` `doc.text` `keyboard` `paintbrush` `terminal`),默认
    `link`,不做完整 symbol 浏览器;
  - **步骤列表**:序号 + 动作图标 + 名称 + 删除 + 上移/下移按钮(不做拖拽);
  - "添加步骤" → 弹 ActionPickerPopover(`.chainStep` 上下文);
  - repeatCount Stepper(1…20)、interStepDelay 输入(0…5 秒,0.1 步进);
  - 步骤为空时保存禁用。

### ActionPickerPopover 回调化重构

现状 `choose` 直接写槽位(`setAction`/`addChild`),与槽位上下文耦合。重构:

- 抽通用选择回调:SettingsView 传入槽位写入闭包(行为不变),链构建器传入"追加步骤"
  闭包;popover 呈现状态由各自持有(链构建器在 ChainConfigSection 内自持)。
- `PickerContext` 加 `.chainStep`:隐藏 Chains 插件整组(防嵌套)+ 隐藏"整插件挂载"行
  (仅列单 op / Apps / Folders)。
- **零 op 插件不渲染空组**:Chains 无链时 picker 中不出现空组(model 层过滤零 op 的
  已连接插件,该过滤对所有插件生效)。

### 环端

零改动:链作为普通 `.pluginOp("chain", <uuid>)` 挂载,picker 的 Plugins 分区自动出现
Chains 组;扇叶渲染、二级扇叶、暗态逻辑全部走既有路径。

## 边界情况

| 情况 | 行为 |
|---|---|
| 步骤引用的插件被断开 | 该步失败 → 中止整链 + 日志;链扇叶只反映 Chains 插件启用态,无步骤级暗态(已知简化) |
| 删除已挂载的链 | 槽位 `.pluginOp` 悬空 → 既有容错(unknown op 日志,不崩) |
| 编辑链 | uuid 不变,槽位展示自动跟随 |
| 执行中重复触发 | 重入保护忽略 |
| 执行中编辑 | 在跑链用 definition 值拷贝,不受影响 |
| `.plugin` 整挂混入步骤 | 构建器过滤 + 执行器防御性失败 |
| 空 steps / 越界值 | 构建器禁存;store 钳制 |

## 测试策略(TDD;单测须 ad-hoc 签名,证书失效)

| 文件 | 覆盖 |
|---|---|
| `ChainDefinitionTests` | Codable round-trip、默认值 |
| `ChainStoreTests` | key 契约 `nemoloop.plugin.chain.chains`、增删改、上限截断 |
| `ChainExecutorTests`(核心) | 执行顺序(stub 计数)、重复轮数、失败中止、`.app/.folder` 经 AppOpening seam、重入忽略、延迟调用经 ChainSleeping seam 断言(`protocol ChainSleeping { func sleep(seconds:) async throws }`,真实现 Task.sleep) |
| `ChainPluginTests` | 动态 op 派生、编辑跟随、默认启用、configSections 非 nil |
| `PluginRegistryTests` 增补 | perform 返回 Bool(存在/缺失/禁用三态) |
| `ActionPickerModelTests` 增补 | `.chainStep` 过滤(无 Chains 组、无整挂行)、零 op 插件不出现 |
| `LauncherRoutingTests` 增补 | 链 op 触发经 registry 路由到 executor |

渲染:挂载链后的扇叶渲染与既有 sub-wheel 路径完全同路,不新开 harness;Ring tab 渲染
harness 的 picker 帧加 Chains 组 fixture 复查一次(沿 T7 自举模式)。UI 改完立即启动验证
(先 pkill 旧实例)。

## 后续子项目如何复用地基

P1 WindowManager / P2 TextClip / P3 Web / P4 Media / P5 System 扩展 / P6 Apps+Files /
P7 Automation / P9 场景模板,均按本模式:插件自管 UserDefaults JSON 配置 +
`operations` 动态派生(opID = 条目 uuid)+ `configSections` CRUD。P8 键盘宏待 TCC 授权流
先问用户。子项目清单与顺序见 handoff 文档。
