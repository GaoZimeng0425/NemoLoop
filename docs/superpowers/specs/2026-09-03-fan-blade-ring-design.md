# 扇形叠环（Fan-Blade Ring）— 设计

**日期**: 2026-09-03
**范围**: 环的视觉改为 Dory App Switcher 风格的**独立倾斜扇叶、一片压一片**布局
**参考**: Dory App Switcher 高清截图（用户提供）——环扇楔片、相邻压叠、每片带独立倾角、图标正立
**演进**: 2026-08-30 开口弧（误解为有缺口）→ 2026-09-03 早上圆角卡片（误解为矩形卡片）→ 同日 v1 同心扇形（用户：缺倾斜、叠放方向反）→ 本方案 v2

## 目标

1. 每个 app 是一个**环扇楔片**（两条径向直边 + 内外弧），全圆 360° 无缺口，中心镂空。
2. **每片独立倾斜**：所有楔片共用"正上方"一片的形状，各自绕自身弧心旋转 `槽位角 + bladeTiltDegrees(12°)`；弧心相对环心**切向偏移 `bladePivotOffset`(12pt)**——这个侧向轴心让倾斜可见（纯同心旋转只会平移槽位）。整体轮廓呈风车状扇叶感，不再是规整圆形，中心孔呈扇贝形。
3. **压叠方向（v2 修正）**：按索引**升序**绘制 → 每片盖住它的逆时针邻片，**最后一片在收口处盖住第一片**，顶部第一片不再压最后一片（v1 方向相反，用户指出）。
4. 楔片角宽 = 槽距 × `bladeOverlapFactor`(1.35)，保证相邻片有实际重叠。
5. **图标正立**、位于槽位中心、中径处，画在所有楔片之上。
6. **选中反馈**：高亮片填 accent 渐变并沿角平分线**向外滑 6pt**（pop 位移并入 position 计算），空槽高亮用白 16%。
7. 命中测试保持全圆均分（`RingGeometry` 不变）——压叠/倾斜只影响渲染，槽位角度未变，最近槽位中心即正确选中。

## 布局数学（`RingView`）

- 槽位角 `θ_i = i·2π/N`（from-up 顺时针）；图标位置 = 环心 + midRadius·(sin θ, −cos θ)，midRadius = (inner+outer)/2 = 68。
- 共享形状：`WedgeShape(index: 0, count: N, startAngle: -π/2 - π/N, span: 2π, bladeWidth: ω)`——永远画"正上方"那一片；`ω = min(2π/N × 1.35, 120°)`。
- 每片：`rotationEffect(θ_i + 12°)`（绕自身弧心）+ `position(环心 + e·切向 + pop·径向)`，切向单位向量 = (cos θ, sin θ)、径向 = (sin θ, −cos θ)，e = `bladePivotOffset`。
- 画布半径 = `outerRadius + popOffset + shadowPad`。
- N 很小（1–3）时楔片宽封顶 120°，片间出现空隙——数量少的退化形态，可接受。

## `WedgeShape`

- `bladeWidth` 参数：楔片角宽与槽距解耦；圆角 fillet clamp 用 `sin(ω/2)`。
- 原 `gap` 数学已删除（压叠无缝隙）。
- v2 起调用方固定传 `index: 0`（共享形状 + 逐片旋转）。

## Token（`RingTheme`）

`outerRadius 96` / `innerRadius 40` / `bladeCornerRadius 10` / `bladeOverlapFactor 1.35` / `maxBladeDegrees 120` / **`bladeTiltDegrees 12`** / **`bladePivotOffset 12`** / `popOffset 6` / `shadowPad 14` / `iconSize 32` / 每片缝投影（黑 30%、半径 3）。

## 材质（重要坑）

- 每片材质用 `VisualEffectView`（hudWindow + behindWindow + glassTint overlay），**不用** macOS 26 `glassEffect`：多个 glassEffect 位于同一 compositing group 时只渲染最后一个并吞掉兄弟图层（渲染对照实验证实）。所有系统统一走 VisualEffectView 路径。

## 保持不变

- 交互流程（按住唤出、死区、松开选中）、`RingViewModel`、`RingPanel`、`RingWindowController`、`HotkeyService`、`RingGeometry`、两个环共用一套视图、弹入/高亮动画、整体阴影。

## 验证

- 渲染 harness（真实 `RingView` + 真实窗口截图）人工核对：倾斜可见、收口处最后一片压第一片、图标正立（不入库）。
- 单测 12 个全过（命中语义未变）。
- 构建 + 真机验看。

## 未纳入（YAGNI）

- 倾角/轴心偏移不做设置项（改 token 即可调）；倾斜方向若与参考图相反，翻转 `bladeTiltDegrees` 符号即可；不改配色（保留磨砂玻璃语言）；不做 List/Palette 模式。
