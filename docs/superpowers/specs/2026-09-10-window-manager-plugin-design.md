# WindowManager 插件(Windows)设计 — Flick 移植 P1

日期:2026-09-10。状态:已与用户逐节确认,待审阅。
来源:Flick 动作集移植 P1 子项目(handoff 2026-09-10;P0 已完成于 feature/plugin-config-chains)。
分支:基于 feature/plugin-config-chains 栈式开发(P0 未合 develop 前避免 registry/harness 冲突)。

## 背景与目标

Flick 清单第 2 类"Windows"共 10 项,移植为 NemoLoop 的 **Windows 插件**(纯静态 op,不需要
P0 参数化地基):窗口吸附(半屏/三分格/四象限)、最大化、最小化、进/出全屏。交互完全走
NemoLoop 既有链路(环 → picker → `.pluginOp("windows", <opID>)`)。

## 已确认决策(用户拍板)

| 决策点 | 结论 |
|---|---|
| AX 授权引导 | 设置卡片 Grant Access 按钮(+needsAuth 黄点);环上未授权触发**静默**+日志,不弹窗 |
| 最大化语义 | set frame 填满屏幕可用区(visibleFrame,留菜单栏/Dock),Rectangle 风格;v1 不做恢复原位 |
| Stage Manager | v1 跳过(无公共切换 API;开设置面板价值弱,P5 一并评估) |
| 架构 | 方案 1:纯函数几何层 + WindowServicing seam + 14 静态 op |

## 自决事项(设计时裁定,可推翻)

- **多屏**:吸附相对窗口**中心点**所在 NSScreen 计算。
- **默认断开**:opt-in(与 System 出厂即连不同,无历史槽位包袱);插件 id `windows`。
- **全屏**:单 op "Toggle Fullscreen"(`kAXFullscreen` 取反,进出双向)。
- **Mission Control**:已在 System 插件,不迁移不重复。
- 三分格图标 `rectangle.leading/center/trailingthird.inset.filled` 若当前 SDK 缺失,实现时
  换最接近的 `rectangle.*` 变体并回写本 spec。

## 范围

**做**:WindowLayout(纯几何)+ WindowServicing seam + AccessibilityWindowService 真实现 +
WindowManagerPlugin(14 ops)+ 设置卡权限行(Grant 按钮/状态文案)+ 注册进 shared + 渲染
harness 第 5 接缝 + 单测 + 启动验收。

**不做**:Stage Manager;恢复原位;平铺动画;跨屏拖拽吸附;窗口记忆;P0 参数化依赖。

**明确不动**:环端、SlotAction、Launcher、P0 各文件(仅 PluginRegistry.shared 插件列表加一行
+ harness 接缝/断言)。

## 几何层(NemoLoop/Plugins/Windows/WindowLayout.swift)

```swift
enum WindowRegion: String, CaseIterable, Identifiable {
    case halfLeft, halfRight, halfTop, halfBottom
    case thirdLeft, thirdCenter, thirdRight
    case quadrantTopLeft, quadrantTopRight, quadrantBottomLeft, quadrantBottomRight
    case maximize
    var id: String { rawValue }
    var displayName: String { … }   // "Left Half" / "Maximize" …
    var symbolName: String { … }
    func targetFrame(in visibleFrame: CGRect) -> CGRect
}
```

计算规则(AppKit 坐标,原点左下;V = 传入 visibleFrame):

| region | frame(x, y, w, h) |
|---|---|
| halfLeft | (V.minX, V.minY, V.w/2, V.h) |
| halfRight | (V.midX, V.minY, V.w/2, V.h) |
| halfTop | (V.minX, V.midY, V.w, V.h/2) |
| halfBottom | (V.minX, V.minY, V.w, V.h/2) |
| thirdLeft | (V.minX, V.minY, V.w/3, V.h) |
| thirdCenter | (V.minX + V.w/3, V.minY, V.w/3, V.h) |
| thirdRight | (V.minX + 2·V.w/3, V.minY, V.w/3, V.h) |
| quadrantTopLeft | (V.minX, V.midY, V.w/2, V.h/2) |
| quadrantTopRight | (V.midX, V.midY, V.w/2, V.h/2) |
| quadrantBottomLeft | (V.minX, V.minY, V.w/2, V.h/2) |
| quadrantBottomRight | (V.midX, V.minY, V.w/2, V.h/2) |
| maximize | V 原样 |

图标:半屏 `rectangle.lefthalf.filled` / `rectangle.righthalf.filled` /
`rectangle.tophalf.filled` / `rectangle.bottomhalf.filled`;三分格
`rectangle.leadingthird.inset.filled` / `rectangle.centerthird.inset.filled` /
`rectangle.trailingthird.inset.filled`(缺则换近邻变体并回写);四象限
`arrow.up.left.square` / `arrow.up.right.square` / `arrow.down.left.square` /
`arrow.down.right.square`;maximize `arrow.up.left.and.arrow.down.right`。

## AX 服务层(NemoLoop/Plugins/Windows/WindowServicing.swift)

```swift
@MainActor protocol WindowServicing: AnyObject {
    func isTrusted() -> Bool                 // AXIsProcessTrusted()
    func promptForTrust()                    // AXIsProcessTrustedWithOptions(kAXTrustedCheckOptionPrompt: true)
    func focusedWindowFrame() -> CGRect?     // kAXFocusedApplication → kAXFocusedWindow → position+size
    func setFrame(_ frame: CGRect) -> Bool   // 写 kAXPosition + kAXSize
    func setMinimized() -> Bool              // kAXMinimized = true
    func toggleFullscreen() -> Bool          // kAXFullscreen = !current
}
@MainActor final class AccessibilityWindowService: WindowServicing
```

真实现:`AXUIElementCreateSystemWide()` → `kAXFocusedApplicationAttribute` →
`kAXFocusedWindowAttribute`;AXValue 转 CGPoint/CGSize;CFError 收敛为 `Bool + NSLog`
(沿 registry 容错惯例)。不直测真实现(真 AX 不可离线测),行为靠 seam 测试钉。

Region op 执行流:`focusedWindowFrame()`(nil→静默+日志)→ 按窗口中心点选
`NSScreen.screens` 中所在屏(无命中退 `NSScreen.main`)→ `targetFrame(in:
screen.visibleFrame)` → `setFrame`。最小化/全屏为属性操作,不经几何层。

## 插件与权限流(NemoLoop/Plugins/Windows/WindowManagerPlugin.swift)

- `id "windows"`、displayName "Windows"、symbol `rectangle.split.2x2`、
  `isEnabledByDefault = false`(opt-in);构造注入 `WindowServicing`。
- `operations` 14 个:12 Region op(id = rawValue,名称/图标取自 region)+
  `minimize`("Minimize",`minus`)+ `toggleFullscreen`("Toggle Fullscreen",
  `arrow.up.backward.and.arrow.down.forward`)。
- `status`:`isTrusted() ? .ready : .needsAuth`(项目第一个真 needsAuth)。
- op perform 时未授权 → **静默 + NSLog**(拍板)。
- `configSections`:权限行 = 状态文案 + Grant Access 按钮(未授权点击
  `promptForTrust()` 弹系统授权窗;已授权显示 "Accessibility granted" 绿字)。TCC 无系统
  通知,不自动监听:Grant 点击后轻量轮询数秒刷新,平时以卡片重开为准(已知简化)。

## 边界情况

| 情况 | 行为 |
|---|---|
| 无聚焦窗口(桌面/Finder 无窗) | 静默 + 日志 |
| AX 属性不可设/写失败 | Bool false + 日志,不崩 |
| 原生全屏中的窗口被 snap | 系统行为受限,v1 已知限制 |
| 窗口跨屏 | 按中心点所在屏 |
| notch/侧 Dock | visibleFrame 已排除,几何天然正确 |
| 授权撤回 | status 回 needsAuth,op 静默 |

## 测试策略(TDD;ad-hoc 签名,命令同 P0)

| 文件 | 覆盖 |
|---|---|
| `WindowLayoutTests` | 12 region × 代表 visibleFrame(普通矩形、minX>0 侧 Dock、minY>0)精确 CGRect;三分格边界;maximize 恒等 |
| `WindowManagerPluginTests`(fake seam) | region op → `setFrame` 收到 == region 对主屏 visibleFrame 的计算(同源确定);未授权触发 seam 零调用;minimize/fullscreen 路由;status 两态;默认断开;14 op 元数据 |
| 既有套件回归 | PluginRegistry/picker 全绿 |

渲染 harness 第 5 接缝沿 P0 模式:**编译真实 `WindowLayout.swift`**(纯 Foundation),
镜像插件壳(去 configSections、perform no-op、op 列表从真实 WindowRegion 派生保证 id 一致);
registryPins 加 `windows YES`;断言更新:整挂行 3→4(trailingBands==3→4、
trailingPixels ≥36→≥48)、整挂行标题 +["Windows"]、pluginItems 10→25(4 whole +
System 5 + Screenshot 1 + Chains 1 + Windows 14 = 25)。UI 改完立即启动验证(先 pkill 旧实例);
AX 授权(TCC)留人工。

## 后续

Stage Manager 待 P5 System 扩展时评估公共 API;恢复原位/窗口记忆若有需求另行立项。
