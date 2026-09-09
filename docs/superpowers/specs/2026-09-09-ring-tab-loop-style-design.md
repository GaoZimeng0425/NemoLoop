# Ring 标签 Loop 式改造设计（mini 环预览 + 行内选择器）

- 日期：2026-09-09
- 状态：已与用户逐节确认，待实现
- 前置：插件架构（`2026-09-09-plugin-architecture-design.md`，分支 feature/plugin-architecture）
- 参考：MrKai77/Loop 的设置 UI（用户点名参考；关键模式来自其 `SettingsContentView.swift` / `RadialMenuActionsGuide.swift` / `RadialMenuActionPickerView.swift`）

## 背景与目标

插件架构落地后，设置 UI 有三个痛点：挂载路径藏得深（Ring → 槽行 → Configure → 三层嵌套菜单）、连接与上环两页割裂、挂载前零预览。本设计参考 Loop 的三个模式逐条对应解决：**右栏常驻真环预览**、**行内搜索式选择器 popover**、**列表↔环双向联动**。

### 已定决策

| 决策点 | 结论 |
|---|---|
| 方案 | 方案一：只改 Ring 标签（inspector + 行选择器）；Plugins 页保持纯连接职责；不做全窗三栏（方案三挂起） |
| Luminare 版本 | **不升级**（锁 0.2.0）——`luminarePopover`/`LuminareList` 已有；三栏用普通 HStack+Divider 手拼；不碰 Loop 的 fork 分支 |
| mini 环点击 | 空扇叶单击=直接弹选择器配置该槽；已配扇叶单击=选中（列表联动+环锁定高亮） |
| 选择器 app 来源 | 扫描 `/Applications` + `~/Applications`（图标+本地化名+缓存）+ 末尾 Browse… 文件面板兜底 |
| 轮播 | 空闲自动轮播扇叶（Loop 同款 1s/槽，有子动作的槽展示发牌），任何 hover/点击即停 |
| 子动作配置 | 芯片排保留（T5 产物），"+" 入口换用同一选择器（子槽上下文：无整挂项） |
| 系统动作 | 不设独立分区——System 插件自然落在 Plugins 分区 |

## 第 1 节：布局

- Ring 标签激活时表单右侧追加 inspector 栏（~280pt 常驻）：`HStack(表单) | Divider | inspector`，窗口随之平滑加宽（680→~950pt），动画复用 `SettingsChrome` 管 sidebar 的同一机制
- 其它标签不加宽、无 inspector（General/Appearance/About 维持现状）

## 第 2 节：mini 环预览（复用真实 RingView + 状态机）

- `RingViewModel` 加 `isSettingsPreview` 标志：不挂全局事件监听，输入来自 SwiftUI 手势（T9 渲染 harness 已验证此注入路径可行：注入时钟 + 编程驱动 begin/updatePointer）
- 悬停扇叶：鼠标位置换算角度喂 `updatePointer`——高亮/发牌/子轮盘全走真状态机，悬停 0.25s 同样发子轮盘，与真环逐帧一致
- 空闲轮播：无交互 timer 逐槽预览；hover/点击即停（`isPreviewingUserSelection` 语义同 Loop）
- 选中联动：点已配扇叶 → 选中槽位，左侧槽行高亮；反之槽行选中 → 环锁定高亮该扇叶
- 配置变化即时反映：预览直接读 `SliceStore`（含暗态——禁用插件扇叶在 mini 环同样降饱和）

## 第 3 节：槽位行 + ActionPickerPopover

**槽位行**：Configure 嵌套菜单移除；动作区变为单按钮（当前动作图标+名称，空槽 "Choose…"）→ 点击弹选择器。Clear 与芯片排保留；芯片排 "+" 弹同一选择器（子槽上下文）。

**ActionPickerPopover**（`luminarePopover` 300×360）：

- 顶部 `LuminareTextField` 搜索（自动聚焦），三级打分：前缀 0 > 包含 1 > 子序列 2（Loop 同款）
- **APPS** 分区：`AppScanner` 扫描 `/Applications` + `~/Applications`（`NSWorkspace` 图标+本地化名，去重、按名排序；首次打开选择器时扫描并缓存，进程内复用），末尾 `Browse…`（NSOpenPanel 兜底特殊路径）
- **PLUGINS** 分区：仅已连接插件；每插件先"整挂"项（图标+名+"N actions"副标题）后其全部操作；子槽上下文无整挂项；footer 提示未连接插件去 Plugins 标签连接
- **FOLDERS** 分区：`Browse Folder…`（NSOpenPanel）
- 键盘导航优先 `LuminareList` 自带选择语义，实测不足再补 ↑↓↵

## 第 4 节：与插件系统的衔接

- 整挂=复用 `attachWholePlugin`；单挂=`setAction`/`addChild`——**数据层零新增**，纯 UI 改造
- 插件/操作挂载的槽行显示 🔗 引用小图标；插件断开 → 槽行文字与 mini 环扇叶同步变暗（同源 `SliceStore.isEnabled`）
- 整挂完成：popover 关闭、芯片排自动展开供复查
- mini 环扇叶图标：插件 symbol（现状已然，无改动）

## 第 5 节：测试与验收

- 单测：`AppScanner`（fixture 目录注入；去重/排序/本地化名）；选择器数据源（已连接过滤、主/子槽上下文、搜索打分排序）；预览状态机（轮播步进、交互即停、点击选中、空槽点击回调）
- 渲染验证：T9 harness 模式扩展——Ring 标签整页（mini 环+槽行+popover 打开态）像素检查：扇叶数与配置一致、暗态扇叶可辨、popover 分区可见
- 人工清单：悬停发子轮盘节奏=真环、popover 键盘导航、窗口加宽动画、空槽直配闭环
- e2e（挂起，随 AX 授权解）：popover 可开、搜 "Lock" 出结果

## 非目标

- 全窗三栏化（方案三）、外观页/插件页的 inspector 预览（本设计留了渐进路径）
- 拖拽挂载（Loop 亦无此实现，自建成本另评）
- Luminare 升级或 fork 引入
