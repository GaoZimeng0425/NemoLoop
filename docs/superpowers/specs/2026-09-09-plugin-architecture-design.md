# NemoLoop 插件架构设计

- 日期：2026-09-09
- 状态：已与用户逐节确认，待实现
- 前置：扇形叠环 v6.2（`2026-09-03-fan-blade-ring-design.md`）、子轮盘级联、OCR 扇叶

## 背景与目标

系统动作池将按功能池路线图（2026-09-08 定稿）从 5 个扩展到 20+：小开关包、文本包、媒体控制（迁 NemoNotch perl 桥）、AI 一期（迁采集层+权限审批+CompletionFlash）、番茄钟、环控音量/亮度。扁平的 `SystemAction` 枚举和扁平的设置菜单撑不住这个规模。

目标：把"一族相关操作 + 连接生命周期 + 配置区"组织为**内置插件**——插件是第一层扇叶可整体挂载，操作是二级扇叶可单体挂载；设置页新增 Plugins 标签负责连接与配置。

### 已定决策

| 决策点 | 结论 |
|---|---|
| 插件形态 | 内置模块化：功能编译进 app，协议 + 注册表组织；不做外部加载 |
| 上环方式 | 整体（插件占一级扇叶，操作自动成二级）或单体（单个操作挂任意扇叶）均可 |
| SystemAction | 收编为 System 插件，出厂默认连接，可断开；`SlotAction.system` case 移除，解码迁移 |
| 二级扇叶角宽 | 15°（常量 `subBladeAngle`） |
| 二级扇叶容量 | 插件槽 8（常量 `maxPluginOps`），手工子动作仍 4；几何匹配待渲染验证，均为单常量可调 |
| 连接语义 | 设置页卡片：开关 + 展开配置区 + 状态徽章；连接失败内联报错不静默 |

## 数据模型

### SlotAction

```swift
enum SlotAction: Codable, Equatable {
    case app(URL)
    case folder(URL)
    case plugin(String)                           // 整个插件占一级扇叶
    case pluginOp(pluginID: String, opID: String) // 单个操作，可挂任意一级/二级扇叶
}
```

- `.system` case 移除。自定义 `init(from: Decoder)` 把旧数据 `.system(x)` 映射为 `.pluginOp(pluginID: "system", opID: x.rawValue)`；编码只出新 case。老用户槽位无损升级，无独立迁移脚本。
- 整体挂载：`SlotEntry.children` 复用现有 `[SlotAction]` 字段，存该插件**显式选中的有序 `.pluginOp` 列表**（挂载时默认填全部操作）。子轮盘的渲染、发牌、触发、图标缓存全部走现有 children 链路，环端解析路径只有插件一条。
- 容量：`maxChildren` 由静态 4 改为按槽位动作类型判定——`.plugin` 扇叶上限 8，其余（app/folder/pluginOp 作主槽）仍 4。
- 插件被禁用或操作被移除时槽位数据**保留**，渲染为暗态；重连即恢复。

### 插件协议与注册表

```swift
protocol PluginOp {
    var id: String { get }
    var displayName: String { get }
    var symbolName: String { get }
    func perform()
}

protocol NemoPlugin: AnyObject {
    var id: String { get }
    var displayName: String { get }
    var symbolName: String { get }
    var summary: String { get }           // 设置卡片描述
    var operations: [PluginOp] { get }    // 该插件全部操作
    var status: PluginStatus { get }      // notInstalled / needsAuth / ready
    func connect() async throws           // 装 hook、触发授权引导等
    func disconnect() async
    var configSections: AnyView? { get }  // 配置区；nil 则卡片无展开
}
```

- `PluginRegistry`（@MainActor @Observable）：持有内置插件实例数组；每插件 `isEnabled` 持久化 UserDefaults（key `nemoloop.plugin.<id>.enabled`）；开关分别驱动 `connect()/disconnect()`。
- 触发统一入口 `registry.perform(pluginID:opID:)`；缺失/禁用则 NSLog 并无操作。

### 已知取舍

- `configSections: AnyView?` 丢类型标识、diff 退化为全量比较——设置页规模下可接受，不引入泛型擦除复杂度。
- 15°/8 的几何匹配未经渲染验证；两值均为常量，实测后一处改数。

## 内置插件清单（按路线图顺序落地）

| 插件 | 操作 | 来源 |
|---|---|---|
| System（`system`） | 锁屏、熄屏、睡眠、调度中心、OCR | 现有 `SystemActions` 实现，出厂 enabled |
| Appearance（`appearance`） | 外观切换（osascript System Events，首次弹 Automation TCC） | 新增 |
| Screenshot（`screenshot`） | 区域截图到剪贴板（复用 OCR ⌘⇧4 框选，`OcrSessionController` 加 `.ocr/.snip` 模式） | 新增 |
| Media（`media`） | 播放/暂停/上一首/下一首/seek | 迁 NemoNotch `MediaRemoteCommander` + perl 桥 |
| AI（`ai`） | 权限审批、会话状态 | 迁 NemoNotch 采集层一期；hook 目录改 `~/.NemoLoop` |

文本包（翻译剪贴板/朗读选中）落为 Text 插件，番茄钟、环控音量/亮度按路线图后续批次各自成插件。

## 设置页

`SettingsTab` 新增 `.plugins`（Ring 之后），图标 `puzzlepiece.extension`。

- 每插件一张卡：卡头 = 插件图标 + 名称 + 状态徽章（ready 绿 / needsAuth 黄 / notInstalled 灰）+ 连接开关；卡下方可展开配置区（`configSections`，nil 则无展开箭头）。
- 开关打开 = `connect()`，卡片内联显示进度与失败原因（红字 + 重试，开关弹回 off）；关闭 = `disconnect()`。已挂环的槽位不清空，仅变暗。
- Ring 标签槽位 Configure 菜单：原 "System Action" 子菜单替换为 "Plugins"——列出**已连接**插件，每插件下先"整插件"项再列全部操作；禁用插件不出现。

## 环上行为

- 整体挂载扇叶：图标 = 插件 symbol（现有 `symbolImage` 管线）；hover 停留发子轮盘 = 该槽 children，与现有发牌/点亮/外甩取消交互零差别。
- 暗态规则：插件禁用/操作缺失 → 图标降饱和、点击无效、子轮盘仍可浏览、tooltip 说明原因。
- 触发：环端只调 `registry.perform(pluginID:opID:)`。

## 错误处理

- 连接失败：卡片内联红字 + 重试按钮，开关弹回 off，不静默吞错。
- 触发失败（禁用/缺失）：NSLog + 无操作，环正常收起。
- 旧数据解码失败兜底沿用现有 SliceStore 的 v1/v2 迁移链。

## 测试策略

swift-testing 单测：

1. 旧数据 `.system(x)` 解码 → `.pluginOp("system", x.rawValue)` 映射正确（含子扇叶里的）。
2. registry 启用状态持久化（含 System 出厂 enabled）。
3. 容量规则：`.plugin` 槽 addChild 上限 8，其余 4。
4. `perform` 对缺失/禁用 op 容错不崩。
5. 整体挂载默认 children = 全部操作。

渲染验证（CLI harness，NSApp.run()）：15°/8 叶子轮盘图，按既有清单查——带在图标下、缺口方位空、暗态扇叶降饱和可辨。

## 非目标（本期不做）

- 外部插件加载（dylib/脚本/包）
- AI 二期（AIChat 控制台重写、LockScreenAIPanel）
- 剪贴板历史、专注模式（挂起中）
