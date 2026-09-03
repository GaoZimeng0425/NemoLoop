# 扇形叠环（Fan-Blade Ring）— 设计

**日期**: 2026-09-03
**范围**: 环的视觉改为 Dory App Switcher 风格的**独立倾斜扇叶、一片压一片**布局
**参考**: Dory App Switcher 高清截图（用户提供）——环扇楔片、相邻压叠、每片带独立倾角、图标正立
**演进**: 2026-08-30 开口弧（误解为有缺口）→ 2026-09-03 早上圆角卡片（误解为矩形卡片）→ 同日 v1 同心扇形（用户：缺倾斜、叠放方向反）→ v2 独立倾斜（用户：线性叠放必然一片压两个/被两个压）→ 本方案 v3：**所有刀片固定同尺寸，扇面只占 ~330°，第一片与最后一片之间留收口缺口**

## 目标

1. 每个 app 是一个**环扇楔片**（两条径向直边 + 内外弧），中心镂空。
2. **固定尺寸（v3）**：所有刀片角宽相同 `ω = min(bladeOverlapFactor × (360°−缺口)/N, maxBladeDegrees)`。
3. **收口缺口（v3）**：刀片均布在 **360° − `arcGapDegrees`(30°)** 的弧上（0 号居中正上，顺时针排布），第一片与最后一片之间是 **30° 缺口**——线性叠放的"一片压两个/被两个压"异常随之消失：每片只压住逆时针邻片，缺口处不重叠。
4. **每片独立倾斜**：共用"正上方"一片的形状，各自绕自身弧心旋转 `槽位角 + bladeTiltDegrees(12°)`；弧心相对环心**切向偏移 `bladePivotOffset`(12pt)** 使倾斜可见。整体轮廓呈风车状扇叶感，中心孔呈扇贝形。
5. **图标正立**、位于槽位中心、中径处，画在所有楔片之上。
6. **选中反馈**：高亮片填 accent 渐变并沿角平分线**向外滑 6pt**（pop 位移并入 position 计算），空槽高亮用白 16%。
7. **命中测试（v3 重写）**：`BladeLayout` 是布局唯一真源（渲染与命中共用）——指针角度对槽位中心取最近；**落在缺口内返回 nil**（不选中）；死区不变。

## 布局数学（`BladeLayout`，`RingGeometry.swift`）

- `occupied = 360 − arcGapDegrees`；`bladeWidth = min(bladeOverlapFactor × occupied / N, maxBladeDegrees)`；`pitch = (occupied − bladeWidth) / (N − 1)`。
- 槽位中心 `centerAngle(i) = start + bladeWidth/2 + i·pitch`，`start = −bladeWidth/2`（0 号居中正上，缺口在它逆时针侧、左上方）。
- `index(forAngle:)`：rel = 归一化(angle − start)；`rel > span`（= (N−1)·pitch + bladeWidth）→ nil（缺口）；否则对槽位中心取最近并 clamp。
- `RingGeometry.wedgeIndex(from:to:layout:deadZoneRadius:)` 接收 `BladeLayout`；`RingViewModel` 在 `begin` 时按 icons 数构建并存下。
- N=1：单片居中正上；N=2..3：宽度触顶 120°，片间是空隙——退化形态可接受。

## 视图层（`RingView`）

- 共享形状 `WedgeShape(index: 0, count: N, startAngle: -π/2 - π/N, bladeWidth: ω)`，每片 `rotationEffect(θ_i + 12°)` + `position(环心 + e·切向 + pop·径向)`。
- 框半径 = `outerRadius + popOffset + shadowPad`；缺口不改变画布尺寸。
- `WedgeShape` 的 `bladeWidth` 参数使角宽与槽距解耦；fillet clamp 用 `sin(ω/2)`；原 `gap` 数学已删。

## Token（`RingTheme`）

`outerRadius 96` / `innerRadius 40` / `bladeCornerRadius 10` / `bladeOverlapFactor 1.35` / `maxBladeDegrees 120` / **`arcGapDegrees 30`（收口缺口）** / `bladeTiltDegrees 12` / `bladePivotOffset 12` / `popOffset 6` / `shadowPad 14` / `iconSize 32` / 每片缝投影（黑 30%、半径 3）。

## 材质（重要坑）

- 每片材质用 `VisualEffectView`（hudWindow + behindWindow + glassTint overlay），**不用** macOS 26 `glassEffect`：多个 glassEffect 位于同一 compositing group 时只渲染最后一个并吞掉兄弟图层（渲染对照实验证实）。所有系统统一走 VisualEffectView 路径。

## 保持不变

- 交互流程（按住唤出、死区、松开选中）、`RingPanel`、`RingWindowController`、`HotkeyService`、两个环共用一套视图、弹入/高亮动画、整体阴影。

## 验证

- 渲染 harness（真实 `RingView` + 真实窗口截图）人工核对：六片同尺寸、第一片与最后一片之间缺口清晰、倾斜可见、图标正立（不入库）。
- 单测 17 个全过（新增 `BladeLayout` 布局数学 + 缺口命中用例；350° 在刀片 0 范围内的边界语义由测试锁定）。
- 构建 + 真机验看。

## 未纳入（YAGNI）

- 缺口角度/倾角/轴心偏移不做设置项（改 token 即可调）；倾斜方向若与参考图相反，翻转 `bladeTiltDegrees` 符号即可；不改配色（保留磨砂玻璃语言）；不做 List/Palette 模式。
