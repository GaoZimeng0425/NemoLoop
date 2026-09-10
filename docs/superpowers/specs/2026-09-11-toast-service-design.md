# 全局 ToastService 设计

日期:2026-09-11。状态:已实施(feature/toast-service),验收通过待合并。
来源:NemoNotch CompletionFlash/HUD 调研(2026-09-11 会话);NemoLoop 现状为无全局
提示机制——唯一类 toast 是 OCR 模块私有实现,插件失败/链中断只 NSLog。
分支:feature/toast-service(基于 develop)。

## 背景与目标

NemoLoop 缺一个全局用户反馈通道:插件 op 失败(禁用/未知)、链步骤失败中断、OCR
结果反馈,目前要么只进日志要么各做各的。新建统一的 **ToastService**:任何模块一行
`ToastService.shared.show(kind, text)` 即可在屏幕下方弹一条自动消失的黑胶囊。

视觉与窗口参数参考 NemoNotch 已验证的实现(CompletionToastView 的胶囊样式、
CompletionFlashService 的"窗口晚于视觉状态落下"时序、OCR 现有 toast 的非激活面板
先例)。

## 已确认决策(用户拍板)

| 决策点 | 结论 |
|---|---|
| 服务定位 | **通用消息通道**:success / error / info 三种;OCR 迁入;插件失败、链中断接 error |
| 视觉 | **固定黑胶囊**(NemoNotch 式,不跟随 RingPalette 三档主题) |
| 位置 | **鼠标所在屏、下方居中**(距 visibleFrame 底部留白,避开 Dock) |
| 窗口层 | **方案 A 共享小面板**:懒创建单个胶囊尺寸 NSPanel,每次 show 重定位;不做每屏常驻全屏窗口(那是为全屏 edge glow 设计的) |

## 自决事项(设计时裁定,可推翻)

- **时长**:success/info 2.0s,error 3.5s;淡出动画 0.25s(easeOut)。
- **替换策略**:后到胜出,立即替换当前消息并重置计时;**不排队**(同一时刻屏幕只
  有一条,YAGNI)。
- **错误文案合并**:`perform` 的禁用/未知 op 两条路径共用一条文案(都是陈旧槽位场景,
  细分无行动价值)。
- **fire-and-forget**:调用方直接 `ToastService.shared.show(...)`,不给
  PluginRegistry/ChainExecutor 加 toast 注入 seam——现有单测只断言返回值,无头环境
  下 show 只改 @Observable 状态,安全且零破坏。
- **视觉细节**:黑 85% 填充、0.5pt 白 15% 描边、视图自带投影、高 44pt、字号 13
  medium;进出动画淡入淡出 + 6pt 上浮;图标色用系统语义色(绿/红/白 70%),不引入
  用户强调色橙(orange error 易读成 warning)。
- **不用任何 Material**(glassEffect/VisualEffectView 在 macOS 26 有吞图层前科,
  胶囊纯形状填充无此风险)。
- `screenUnderMouse()` 三行 helper 在 ToastWindowController 内自持一份,不为 3 行
  建公共文件(OCR 的那份随权限面板继续用)。

## 范围

**做**:ToastService(纯状态机)+ ToastWindowController(共享面板)+
ToastView(黑胶囊)+ 三个接入点(PluginRegistry.perform 失败、ChainExecutor 步骤
失败、OCR 迁移)+ AppDelegate 挂载 + 单测 + ImageRenderer 渲染自查 + 实机验收。

**不做**:消息队列/堆叠;主题跟随;点击交互(纯通知,点击穿透);设置项(无开关,
后续有需要再加);menubar 面板内嵌 toast(面板多数时间收起,全局提示放里面等于
看不见)。

**明确不动**:环端、SlotAction、各插件 op 本体、Settings UI。PluginRegistry 与
ChainExecutor 只各加一行 toast 调用(保留原 NSLog)。

## 架构与组件(NemoLoop/Services/Toast/)

```swift
// ToastService.swift — 纯状态机,不碰窗口,无头可测
@MainActor @Observable
final class ToastService {
    static let shared = ToastService()

    struct Toast: Equatable { let kind: ToastKind; let text: String }
    enum ToastKind { case success, error, info }

    private(set) var current: Toast?      // 当前消息(nil = 无)
    private(set) var visible: Bool        // 视图可见性,带动画归零
    private(set) var panelWanted: Bool    // 窗口层信号,晚一个淡出时长归零

    func show(_ kind: ToastKind, _ text: String)   // 后到胜出,重置计时
}
```

状态机时序(NemoNotch CompletionFlashService 已验证的模式):

1. `show()`:`current` 与 `visible` 立即为真,`panelWanted = true`,重启消失 Task。
2. Task 睡对应时长 → `withAnimation` 置 `visible = false`(胶囊淡出)→ 再睡 0.25s
   → `panelWanted = false`、`current = nil`。
3. **`panelWanted` 晚于 `visible` 归零**是刻意的:面板还承载着淡出动画,窗口随状态
   同步撤下会切断动画。

时长经 init 注入(默认 2.0/3.5/0.25),单测用 0.05s。

```swift
// ToastWindowController.swift — AppDelegate 启动时创建一次
@MainActor
final class ToastWindowController {
    init(service: ToastService)   // withObservationTracking 观察 panelWanted
    private func present()        // 懒建面板,重定位鼠标屏,orderFrontRegardless
    private func dismiss()        // orderOut(此时动画已播完)
}
```

面板参数(与 OCR toast 同源,补齐 NemoNotch 的跨 Space/穿透参数):

| 参数 | 值 | 依据 |
|---|---|---|
| styleMask | `[.borderless, .nonactivatingPanel]` | 不抢焦点,OCR 先例 |
| level | `.screenSaver` | 高于环面板 `.popUpMenu`,OCR 先例 |
| ignoresMouseEvents | `true` | 纯通知,点击穿透 |
| collectionBehavior | `[.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]` | 跨 Space、全屏 app 之上可见(NemoNotch 先例) |
| isOpaque / backgroundColor | `false` / `.clear` | 胶囊形状外全透明 |
| hasShadow | `false` | 投影由 ToastView 自绘 |

定位:鼠标所在屏 `visibleFrame` 水平居中、距底 72pt。

## ToastView 视觉(NemoLoop/Services/Toast/ToastView.swift)

| 元素 | 规格 |
|---|---|
| 胶囊 | 黑 85% 填充,0.5pt 白 15% 描边,shadow(black 0.5, r 12, y 6) |
| 文本 | 13 medium 白色,单行截断,`fixedSize` 按内容定宽 |
| 图标 | SF Symbol 14pt:success `checkmark.circle.fill` 绿;error `exclamationmark.triangle.fill` 红;info `info.circle.fill` 白 70% |
| 高度 | 44pt |
| 动画 | 淡入淡出 + 6pt 上浮,easeOut 0.25s |

## 接入点(第一期)

文案统一英文(app UI 语言为英文:SystemPlugin "System"、OCR 现有文案均英文;2026-09-11 计划期勘误,原中文文案弃用)。

| 调用点 | 类型 | 文案 |
|---|---|---|
| `PluginRegistry.perform` 失败(禁用/未知 op,两路合并) | error | `Action unavailable: plugin disabled or removed` |
| `ChainExecutor.run` 步骤失败中断(含 open 失败,一并覆盖) | error | `Chain '{name}' failed at step {N} — aborted` |
| OCR `showToast` 三处迁移 | success / info / error | `Snipped to clipboard` / `No text recognized` / `OCR failed: {detail}`(均为现有字符串,原样保留) |

- 迁移后删除 `OcrSessionController` 私有的 `toastPanel`/`toastTimer`/`showToast`
  整段;`screenUnderMouse` 保留(权限面板还在用)。
- 链的「重复触发忽略」保持只 NSLog(刻意不吵)。
- 原有 NSLog 全部保留(toast 是补充,不是替代)。

## 测试

- **单测**(`NemoLoopTests/ToastServiceTests.swift`,ad-hoc 签名跑,项目惯例):
  show 置位 current/visible/panelWanted;按类型取时长;后到替换重置计时;注入时长
  后自动消失的完整时序(visible 先落,panelWanted 晚 0.25 档落,current 清空);
  PluginRegistry.perform 失败路径与 ChainExecutor 中断路径的返回值行为不回归
  (现有 184 个测试不动即过)。
- **渲染自查**:ImageRenderer 出三种 kind 的 PNG,像素验证胶囊存在(黑占比)+
  图标区着色;toast 是独立面板不在环的 3D 层级里,无材质坑,但仍按极暗场景直方图
  惯例验。
- **实机验收**:合并后重跑 build.sh 重建安装版(项目惯例,防旧构建误报);app 加
  `--toast-test` 启动参数(沿用 `--settings` / `--ocr-test` 的验证口惯例,启动 2s 后弹
  一条 error toast)供直接验看;触发一条含禁用插件步骤的链 → 鼠标屏下方出 error
  胶囊,3.5s 淡出;OCR 截图 → success 胶囊;全屏 app 上触发 → toast 仍可见。
