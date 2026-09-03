# 扇形叠环（Fan-Blade Ring）— 设计

**日期**: 2026-09-03
**范围**: 环的视觉改为 Dory App Switcher 风格的**扇形（环扇楔片）一片叠一片**布局：每片比自己的等分份额更宽，直边压在相邻片上形成斜缝 cascade
**参考**: Dory App Switcher 高清截图（用户提供）——环扇楔片、相邻压叠、图标正立、选中片沿角平分线外滑
**演进**: 2026-08-30 开口弧方案（误解为有缺口）→ 2026-09-03 早上圆角卡片方案（误解为矩形卡片）→ 本方案（用户澄清：是扇形，一片叠一片）

## 目标

1. 每个	app 是一个**环扇楔片**（两条径向直边 + 内外弧），不是矩形卡片。
2. **全圆 360° 无缺口**：楔片中心按 `360°/N` 均布（0 号居中正上）。
3. **压叠**：楔片自身角宽 = 槽距 × `bladeOverlapFactor`（1.35），比等分份额宽，于是每片的 a0 侧直边压在逆时针邻片上面，形成 Dory 的斜缝 cascade。Z 序：索引逆序绘制 → 0 号压最上（与参考图一致）。
4. **图标正立**、位于楔片槽位中心、中径处，画在所有楔片之上。
5. **选中反馈**：高亮楔片填充 accent 渐变并沿自身角平分线**向外滑出 6pt**（Dory 的 pop），空槽高亮用白 16%。
6. 命中测试保持全圆均分（`RingGeometry`，0 号居中正上、顺时针、中心死区 nil）——压叠区域内按最近槽位中心选中，语义正确。

## 布局数学（`RingView`，纯视图层）

- 槽位角 `θ_i = i · 2π/N`（from-up 顺时针）；图标位置 = 圆心 + midRadius·(sin θ, −cos θ)，midRadius = (inner+outer)/2 = 68。
- 楔片角宽 `ω = min(2π/N × 1.35, 120°)`；`WedgeShape` 新增 `bladeWidth` 参数：楔片中心仍按槽距均布（`startAngle = -π/2 - π/N`、`span = 2π`），但边界角取 `center ± ω/2` 而非 `center ± slice/2`。
- 画布半径 = `outerRadius + popOffset + shadowPad`。
- N 很小（1–3）时楔片宽封顶 120°，片间出现空隙——数量少的退化形态，可接受。

## `WedgeShape`（恢复自 develop 版本 + bladeWidth 参数）

- 删除 `gap` 参数（压叠方案没有缝隙；原平行偏移数学随 g=0 退化移除）。
- 圆角 fillet 的 clamp 用 `sin(ω/2)`（楔片自身半宽）而非槽距半宽。
- 其余（asin 角内缩、fillet 中心构造）与 develop 版一致。

## Token（`RingTheme`）

- 恢复 `outerRadius 96` / `innerRadius 40` / 圆角 10；新增 `bladeOverlapFactor 1.35`、`maxBladeDegrees 120`、`popOffset 6`、`shadowPad 14`；`iconSize 32`。
- 移除卡片 token（cardWidth/Height/CornerRadius/cardOverlap/minCardRadius/highlightScale）与弧形 token。
- `emptyFill` 白 7% 保留（无共享背衬后每片自带材质+填充）。

## 材质（重要坑）

- 每片自带 `VisualEffectView`（hudWindow + behindWindow + glassTint overlay），**不用** macOS 26 `glassEffect`：多个 glassEffect 位于同一 compositing group 时只渲染最后一个并吞掉兄弟图层（已用渲染对照实验证实）。所有系统统一走 VisualEffectView 路径。

## 保持不变

- 交互流程（按住唤出、死区、松开选中）、`RingViewModel`、`RingPanel`、`RingWindowController`、`HotkeyService`、`RingGeometry`、两个环共用一套视图、弹入/高亮动画、阴影。

## 验证

- 临时渲染 harness（真实 `RingView` + 真实窗口截图）人工核对：压叠方向、斜缝、图标正立、全圆无缺口（不入库）。
- 单测（命中测试语义未变，原有 12 个全过）。
- 构建 + 启动真机验看。

## 未纳入（YAGNI）

- 压叠比例/楔片宽度不做设置项；不改配色（保留磨砂玻璃语言，不搬 Dory 奶油色）；不做 List/Palette 模式。
