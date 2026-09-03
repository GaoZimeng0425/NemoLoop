# 扇形叠环（Fan-Blade Ring）— 设计

**日期**: 2026-09-03
**范围**: 环的视觉改为 Dory App Switcher 风格的**独立倾斜扇叶、一片压一片**布局
**参考**: Dory App Switcher 高清截图（用户提供）——环扇楔片、相邻压叠、每片带独立倾角、图标正立
**演进**: 2026-08-30 开口弧（误解为有缺口）→ 2026-09-03 早上圆角卡片（误解为矩形卡片）→ 同日 v1 同心扇形（用户：缺倾斜、叠放方向反）→ v2 独立倾斜（用户：线性叠放必然一片压两个/被两个压）→ v3 固定尺寸 + 收口缺口 → 本方案 v4：**每个 item 是独立 view（logo 居中画在扇面 view 里，随 view 一起倾斜），倾斜改为 `rotation3DEffect` 绕切向轴的 3D 透视倾斜（近大远小）**

## 平台视图坑（v4 实证，重要）

- 刀片材质**不能用** `Material`（`.ultraThinMaterial`）或 `VisualEffectView`，也**不能用** macOS 26 `glassEffect`：
  - 多个 `glassEffect` 在同一 compositing group 只渲染最后一个并吞掉兄弟图层；
  - `Material` / NSViewRepresentable 特性视图在 macOS 上会打破同容器 Z 序合成——渲染对照实验证实会**吞掉同容器的兄弟图标**（v4 中表现为 0 号图标消失）。
- 定案：每片用**半透明深色纯填充**（`glassTint` 黑 28%）作为表面，配每片投影（黑 30%、半径 3）表达折纸式层叠深度。

## 目标

1. 每个 app 是一个**环扇楔片**（两条径向直边 + 内外弧），中心镂空。
2. **固定尺寸（v3）**：所有刀片角宽相同 `ω = min(bladeOverlapFactor × (360°−缺口)/N, maxBladeDegrees)`。
3. **收口缺口（v3）**：刀片均布在 **360° − `arcGapDegrees`(30°)** 的弧上（0 号居中正上，顺时针排布），第一片与最后一片之间是 **30° 缺口**——线性叠放的"一片压两个/被两个压"异常随之消失：每片只压住逆时针邻片，缺口处不重叠。
4. **每片独立 3D 倾斜（v4）**：每个 item 是独立 view，logo 居中画在扇面 view 里，view 整体绕自身切向轴做 `rotation3DEffect` 透视倾斜（近大远小），替代 v2 的 2D 平面旋转 + 轴心偏移。
5. **图标正立**、位于槽位中心、中径处，画在所属 item view 内（随 view 倾斜），且在所有刀片图层之上路径渲染。
6. **选中反馈**：高亮片填 accent 渐变并沿角平分线**向外滑 6pt**（pop 位移并入 position 计算），空槽高亮用白 16%。
7. **命中测试（v3 重写）**：`BladeLayout` 是布局唯一真源（渲染与命中共用）——指针角度对槽位中心取最近；**落在缺口内返回 nil**（不选中）；死区不变。

## 布局数学（`BladeLayout`，`RingGeometry.swift`）

- `occupied = 360 − arcGapDegrees`；`bladeWidth = min(bladeOverlapFactor × occupied / N, maxBladeDegrees)`；`pitch = (occupied − bladeWidth) / (N − 1)`。
- 槽位中心 `centerAngle(i) = start + bladeWidth/2 + i·pitch`，`start = −bladeWidth/2`（0 号居中正上，缺口在它逆时针侧、左上方）。
- `index(forAngle:)`：rel = 归一化(angle − start)；`rel > span`（= (N−1)·pitch + bladeWidth）→ nil（缺口）；否则对槽位中心取最近并 clamp。
- `RingGeometry.wedgeIndex(from:to:layout:deadZoneRadius:)` 接收 `BladeLayout`；`RingViewModel` 在 `begin` 时按 icons 数构建并存下。
- N=1：单片居中正上；N=2..3：宽度触顶 120°，片间是空隙——退化形态可接受。

## 视图层（`RingView`，v4）

- **每个 item 一个独立 view**：`Group { 表面填充 + 状态填充 + 描边 + logo(.position 于扇面视觉中心) }.frame(side).shadow(缝投影).rotation3DEffect(...).position(环心 + pop·径向)`——logo 与扇面同 view，随倾斜一起变换。
- 形状 `WedgeShape(index: 0, count: 1, centerAngle: θ_i, bladeWidth: ω)`——`centerAngle` 参数（v4 加入）直接指定槽位角，形状自己完成槽位放置，**全程无 2D rotationEffect**（`rotation3DEffect` 与 `rotationEffect` 组合会破坏布局，渲染实验证实）。
- 3D 倾斜：`rotation3DEffect(blade3DTiltDegrees(20°), axis: (cos θ, sin θ, 0), perspective: 0.75)`——轴在画布坐标系下即该片切向（径向 = (sin θ, −cos θ)，切向 ⊥ 径向，y 向下）；刀片绕切向轴透视倾斜，近大远小。
- 框半径 = `outerRadius + popOffset + shadowPad`；缺口不改变画布尺寸。
- `WedgeShape`：`bladeWidth` 角宽与槽距解耦；`centerAngle` 覆写槽位角；fillet clamp 用 `sin(ω/2)`；原 `gap` 数学已删。

## Token（`RingTheme`）

`outerRadius 96` / `innerRadius 40` / `bladeCornerRadius 10` / `bladeOverlapFactor 1.35` / `maxBladeDegrees 120` / `arcGapDegrees 30`（收口缺口）/ **`blade3DTiltDegrees 20`** / **`blade3DPerspective 0.75`** / `popOffset 6` / `shadowPad 14` / `iconSize 32` / 每片缝投影（黑 30%、半径 3）。

## 材质（重要坑，v4 两次实证）

- 每片表面用**半透明深色纯填充**（`glassTint` 黑 28%）。**禁用**三类材质方案：
  1. macOS 26 `glassEffect`——同一 compositing group 内多个 glassEffect 只渲染最后一个并吞掉兄弟图层；
  2. `VisualEffectView`（NSViewRepresentable）——NSView 不跟随 Core Animation 3D 变换；
  3. SwiftUI `Material`（`.ultraThinMaterial` 等，macOS 上同为 AppKit 特性视图backing）——会打破同容器 Z 序合成，**吞掉同容器的兄弟图层**（v4 渲染对照实验：加入 Material 后 0 号图标消失，换成纯填充即恢复）。

## 保持不变

- 交互流程（按住唤出、死区、松开选中）、`RingPanel`、`RingWindowController`、`HotkeyService`、两个环共用一套视图、弹入/高亮动画、整体阴影。

## 验证

- 渲染 harness（真实 `RingView` + 真实窗口截图）人工核对：六片同尺寸、第一片与最后一片之间缺口清晰、倾斜可见、图标正立（不入库）。
- 单测 17 个全过（新增 `BladeLayout` 布局数学 + 缺口命中用例；350° 在刀片 0 范围内的边界语义由测试锁定）。
- 构建 + 真机验看。

## 未纳入（YAGNI）

- 缺口角度/倾角/轴心偏移不做设置项（改 token 即可调）；倾斜方向若与参考图相反，翻转 `bladeTiltDegrees` 符号即可；不改配色（保留磨砂玻璃语言）；不做 List/Palette 模式。
