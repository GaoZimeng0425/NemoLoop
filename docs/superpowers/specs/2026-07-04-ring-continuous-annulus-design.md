# 连续圆环底（Continuous Annulus Backing）— 设计

**日期**: 2026-07-04
**范围**: NemoLoop 径向环 UI 的视觉呈现

## 问题

当前径向环把六个扇形（wedge）画成**各自独立**的环状扇区：每个扇形有自己的磨砂玻璃 backing、独立圆角、并以 4pt 间隙（`wedgeGap`）彼此分开。视觉上读作「六块各自漂浮的圆角块」，而非「一个圆环」。用户希望这六个扇形看起来像浮在**同一个连续圆环**上。

## 方案（Option C：间隙填充圆环底）

在六个扇形背后铺一整层连续的磨砂玻璃圆环（annulus），填满原本的间隙——缝隙于是读作「环上的刻痕」而非空洞。扇形自身只保留状态色填充，磨砂玻璃统一由底层圆环提供。

### 改动点

**`NemoLoop/Ring/RingView.swift`**

1. 新增 `AnnulusShape`（`Shape`）：以 even-odd 规则用两个同心圆（`innerRadius` / `outerRadius`）构成整圈无缺口的环。
2. 在 `RingView.body` 的 `ZStack` 最底层加一层连续环底：
   - macOS 26+：`Color.clear.glassEffect(.regular.tint(RingTheme.glassTint), in: AnnulusShape(...))`
   - 更低版本：`VisualEffectView(material: .hudWindow, …).clipShape(AnnulusShape(...)).overlay(AnnulusShape(...).fill(RingTheme.glassTint))`
   - 复用现有 `wedgeBacking` 的两分支写法，仅把 `WedgeShape` 换成 `AnnulusShape`。
   - 可选：环底叠一圈极细内/外描边（`RingTheme.glassStroke`，见下）勾出圆环轮廓。
3. **移除逐扇形的磨砂玻璃 backing**：`wedgeFill(for:)` 中删除 `wedgeBacking(shape)` 调用；`wedgeBacking(_:)` 私有方法整体删除（其逻辑迁移到步骤 2 的环底）。
4. 扇形填充状态保持不变，未分配空闲扇形填充改为**透明**（直接露出底层环底），其余状态不变：
   - 高亮已分配 → `accentGradient`
   - 高亮空槽 → `highlightEmpty`
   - 已分配空闲 → `baseFill`
   - 未分配空闲 → 透明（无 fill）

**`NemoLoop/Ring/RingTheme.swift`**

- 若采用可选描边：新增 `glassStroke = Color.white.opacity(0.14)` 及 `glassStrokeWidth: CGFloat = 1`（若不需要则不加，YAGNI）。

### 保持不变

扇形的 `wedgeCornerRadius`、`wedgeGap`、分隔线（`dividerColor`/`dividerWidth`）、图标布局、highlight 动画、pop-in 动画、命中测试（`RingGeometry.wedgeIndex`）全部不变——正是圆角 + 间隙让缝隙在连续环上读作刻痕。

## 结果

视觉上是一整个磨砂玻璃圆环，上面浮着六块圆角扇形，缝隙透出同一层环底。改动集中在 `RingView.swift`（+`AnnulusShape`，-`wedgeBacking`）与 `RingTheme.swift`（可选描边），可回退。

## 验证

- 构建通过：`xcodebuild -project NemoLoop.xcodeproj -scheme NemoLoop -destination 'platform=macOS' build`
- 运行 app，触发环显示，肉眼确认：六个扇形共处一个连续磨砂圆环，缝隙透出环底而非空洞；高亮/空槽/图标表现与改动前一致。
- 现有测试（`RingGeometryTests` / `SliceConfigTests`）仍通过——几何命中逻辑未改。
