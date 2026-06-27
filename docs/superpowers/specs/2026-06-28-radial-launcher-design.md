# NemoLoop — 径向启动器(Radial Launcher)设计

- 状态:已批准设计,待写实现计划
- 日期:2026-06-28
- 作者:GaoZimeng + Claude

## 1. 概述

NemoLoop 是一个 macOS 工具:按住全局快捷键时,在鼠标光标位置弹出一个甜甜圈形圆环,圆环被分为 6 个楞形(扇区),每个楞形绑定一个应用。用户朝某个方向移动鼠标高亮对应楞形,松开快捷键即启动该应用。

目标是"按住-松开、方向选择"的快速启动体验 —— 无需精确点击,方向容错高。

## 2. 范围(MVP)

**包含:**
- 全局快捷键(用户自定义,无默认绑定)按住唤出 / 松开触发
- 6 楞甜甜圈圆环,以光标为圆心,出现在光标所在屏幕
- 每个楞形绑定一个应用(.app),松手启动/前置该应用
- 设置窗口:6 个槽位,每个槽位用 `NSOpenPanel` 选择应用
- 持久化 6 槽位配置

**不包含(YAGNI):**
- URL / 文件 / 脚本 / 系统动作绑定(仅应用)
- 可变楞数(固定 6)
- 环上直接编辑模式(配置只在设置窗口)
- 多套圆环 / 嵌套子环
- 点击式交互(仅按住-松开方向模式)

## 3. 交互流程

1. **按下**全局快捷键 → 在鼠标所在屏幕、以光标为圆心弹出 6 楞圆环。
2. 朝某方向**移动鼠标** → 对应楞形高亮(由光标相对圆心的角度决定,而非精确落点)。
3. **松开**快捷键 → 启动高亮楞形绑定的应用,圆环消失。
4. **取消条件:**
   - 松手时光标仍在圆心 `deadZoneRadius` 半径内(未朝任何方向移动)→ 不触发。
   - 任意时刻按 `ESC` → 取消并关闭圆环。
5. **空槽位**(未配置应用)渲染为暗淡占位;可被高亮但松手不触发任何动作。

### 角度映射

- 6 楞 × 60°/楞。
- 顶部(12 点方向)为第 1 楞(索引 0)的中心。
- 读取光标相对圆心的角度,归一化后除以 60° → 楞索引。
- 光标到圆心距离 < `deadZoneRadius` → 返回"无选择"(取消)。
- 此映射为纯函数,单元测试覆盖。

## 4. 架构

全新 SwiftUI + AppKit 项目。`NSApp.setActivationPolicy(.accessory)`(无 Dock 图标、不出现在 Cmd-Tab),通过 `MenuBarExtra` 提供"设置 / 退出"入口。

| 组件 | 职责 | playbook 依据 |
|------|------|--------------|
| `HotkeyService` | 用 `KeyboardShortcuts` 注册 `summonRing` Name;`onKeyDown` → 显示圆环,`onKeyUp` → 触发高亮楞 | events-hotkeys/hotkeys.md |
| `RingWindowController` + `RingPanel` | 无边框透明 `NSPanel`(级别 `.statusBar+`、`canJoinAllSpaces`、`fullScreenAuxiliary`),覆盖光标所在屏幕;`ignoresMouseEvents = true` | window/multi-screen-overlay.md, window/nspanel-and-notch.md |
| `RingViewModel` (`@Observable`) | 显示状态、当前高亮楞索引;消费全局 `.mouseMoved` 事件计算角度 | events-hotkeys/global-event-monitor.md |
| `RingView` (SwiftUI) | 渲染甜甜圈 6 楞 + 各楞应用图标 + 高亮动画 | swiftui/ |
| `SliceStore` (`@Observable`) | 6 个槽位(每个 `bundleURL?` + 缓存图标),持久化到 UserDefaults | architecture/ |
| `Launcher` | `NSWorkspace.shared.openApplication`/`open(_:)` 启动或前置应用 | — |
| `SettingsView` (SwiftUI) | 6 槽位列表,每槽 `NSOpenPanel` 选 .app;`KeyboardShortcuts.Recorder` 设快捷键 | — |

### 数据流

```
按键 → HotkeyService.onKeyDown
     → RingWindowController.show(at: 光标屏幕)
     → RingViewModel.begin() 启动全局 mouseMoved 监听
鼠标移动 → 全局监听 → RingViewModel.update(highlightedIndex)
     → RingView 高亮重绘(SwiftUI 响应式)
松键 → HotkeyService.onKeyUp
     → RingViewModel.currentSelection (nil 若在死区/空槽)
     → Launcher.launch(slice) (若有效)
     → RingWindowController.hide() + 停止监听
```

## 5. 关键技术决策

- **快捷键无默认绑定**:用户在设置里用 `KeyboardShortcuts.Recorder` 自定义,避免与系统快捷键冲突。
- **应用按 bundle URL 存储**;图标用 `NSWorkspace.shared.icon(forFile:)` 获取并缓存。
- **鼠标追踪用全局 `NSEvent` 监听**(`addGlobalMonitorForEvents(matching: .mouseMoved)`);圆环窗口 `ignoresMouseEvents = true` —— 方向模式不需要窗口接收点击。
- **圆环窗口不抢焦点**(`NSPanel` 不 becomeKey/becomeMain),松手后再前置目标应用,避免打断当前 App 的焦点。
- **多屏**:圆环出现在包含光标的 `NSScreen` 上,窗口覆盖该屏 frame,圆环在该窗口内以光标为中心绘制。
- **圆环形态**:甜甜圈(中心空洞)分 6 楞,高亮整楞扁亮;空槽位暗淡。

## 6. 测试策略(Swift Testing)

测试纯逻辑,跳过 NSWindow / 全局监听 / AX 等需真实权限的集成:
- 角度 → 楞索引映射(各方向、边界角度)
- 死区判定(圆心半径内返回无选择)
- 空槽位:松手无动作
- `SliceStore` 编解码 / 持久化往返

## 7. 未决 / 后续扩展(非 MVP)

- URL / 文件 / 脚本绑定
- 可配置楞数
- 环上直接编辑
- 圆环主题 / 外观自定义
