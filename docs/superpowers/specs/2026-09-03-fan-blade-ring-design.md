# 扇形叠环（Fan-Blade Ring）— 设计

**日期**: 2026-09-03
**范围**: 环的视觉改为 Dory App Switcher 风格的**独立倾斜扇叶、一片压一片**布局
**参考**: Dory App Switcher 高清截图（用户提供）——环扇楔片、相邻压叠、每片带独立倾角、图标正立
**演进**: 2026-08-30 开口弧（误解为有缺口）→ 2026-09-03 早上圆角卡片（误解为矩形卡片）→ 同日 v1 同心扇形（用户：缺倾斜、叠放方向反）→ v2 独立倾斜（用户：线性叠放必然一片压两个/被两个压）→ v3 固定尺寸 + 收口缺口 → v4 独立 view + `rotation3DEffect` 切向轴 3D 倾斜 → 本方案 v5：**每个扇面固定 30°、以正上方为中心对称边贴边排布（最多 11 片铺满 330°），命中边界改按刀片边缘切分**——v4 的 hover 错位（命中按槽位中心取最近、视觉刀缝在前导边，两者系统性错开 `(片宽−间距)/2`）随之根除 → v5.1（用户：logo 不在扇面中）：**3D 倾斜轴锚到每片中带图标中心**（图标零位移归位扇面；v4 轴穿环心，透视把 logo 甩离槽位，亦是 v4 hover 观感错位主因），并恢复选中片外滑 6pt → v5.2（用户实机两次均不对）：**放弃 3D 倾斜，`blade3DTiltDegrees = 0` 纯平面**；变换由 `BladeTilt` 修饰符承载、token 非 0 才挂载（0° 时完全跳过,平面渲染走像素验证过的同一路径）→ v5.3（用户指令）：**每片改为"以 logo 为中心的局部 view"**——扇面围绕 logo 画（`WedgeShape.arcCenter` 把弧心偏移到环心方向）、view 整体 3D 倾斜；logo 恒在旋转 pivot 上,结构上不可能与扇面分离；`BladeTilt` 移除,恢复 tilt 20°。**同时修复自 v4 起的真根因:`WedgeShape.centerAngle` 是 SwiftUI 角(0=+x、顺时针、y 向下),渲染层却直接喂 from-up-cw 槽位角,整fan扇面相对图标/命中恒差 +90°——v4 以来"logo 不在扇面、hover 指哪亮哪都不对"皆源于此;新架构传入 `θ−π/2` 并由 `WedgeShapeTests` 锁死该约定** → v5.4（用户指令）：**0 号片居中 12 点方向、其余顺时针**（`start = −bladeWidth/2`，缺口在 0 号片逆时针侧/左上方），替代 v5 的"以正上为中心对称"

## 平台视图坑（v4 实证，重要）

- 刀片材质**不能用** `Material`（`.ultraThinMaterial`）或 `VisualEffectView`，也**不能用** macOS 26 `glassEffect`：
  - 多个 `glassEffect` 在同一 compositing group 只渲染最后一个并吞掉兄弟图层；
  - `Material` / NSViewRepresentable 特性视图在 macOS 上会打破同容器 Z 序合成——渲染对照实验证实会**吞掉同容器的兄弟图标**（v4 中表现为 0 号图标消失）。
- 定案：每片用**半透明深色纯填充**（`glassTint` 黑 28%）作为表面，配每片投影（黑 30%、半径 3）表达折纸式层叠深度。

## 目标

1. 每个 app 是一个**环扇楔片**（两条径向直边 + 内外弧），中心镂空。
2. **固定 30° 扇面（v5）**：所有刀片角宽恒为 `bladeDegrees = 30°`，与 app 数量无关；`N ≤ 11` 时间距也是 30°（边贴边，**不再互相压叠**），11 片正好铺满 330°。
3. **收口缺口（v3，v5 泛化；v5.4 起点修正）**：**0 号片居中正上（12 点方向）、其余顺时针排布**（`start = −bladeWidth/2`），缺口在 0 号片逆时针侧、左上方；`N ≤ 11` 时缺口 = `360° − 30°·N ≥ 30°`，`N > 11` 时间距压缩到 `(360°−30°−30°)/(N−1)`（此时才出现叠压）以保证缺口不小于 30°。
4. **每片独立 3D 倾斜（v4）**：每个 item 是独立 view，logo 居中画在扇面 view 里，view 整体绕自身切向轴做 `rotation3DEffect` 透视倾斜（近大远小），替代 v2 的 2D 平面旋转 + 轴心偏移。
5. **图标正立**、位于槽位中心、中径处，画在所属 item view 内（随 view 倾斜），且在所有刀片图层之上路径渲染。
6. **选中反馈**：高亮片填 accent 渐变并沿角平分线**向外滑 6pt**（pop 位移并入 position 计算），空槽高亮用白 16%。
7. **命中测试（v3 引入，v5 重写）**：`BladeLayout` 是布局唯一真源（渲染与命中共用）——指针角度按**刀片边缘**切块（`floor` 到前导边），叠压区归后画的上层刀片，命中区域与视觉刀缝逐度一致；**落在缺口内返回 nil**（不选中）；死区不变。

## 布局数学（`BladeLayout`，`RingGeometry.swift`）

- `bladeWidth = bladeDegrees = 30°`（恒定，与 N 无关）；`pitch = min(30°, (360 − arcGapDegrees − 30°)/(N−1))`——N ≤ 11 时 = 30°（边贴边、无叠压），N > 11 时 < 30°（叠压出现）。
- 槽位中心 `centerAngle(i) = start + bladeWidth/2 + i·pitch`，`start = −bladeWidth/2`（**0 号片居中 12 点、顺时针**，缺口在其逆时针侧/左上方；`span = (N−1)·pitch + bladeWidth`）。
- `index(forAngle:)`：rel = 归一化(angle − start)；`rel > span` → nil（缺口）；否则 `i = floor(rel / pitch)` 并 clamp——**边界即刀片边缘**，叠压区归后画的上层刀片。
- `RingGeometry.wedgeIndex(from:to:layout:deadZoneRadius:)` 接收 `BladeLayout`；`RingViewModel` 在 `begin` 时按 icons 数构建并存下。
- N=1：单片居中正上；N=6（当前 `wedgeCount`）：覆盖 −15°…+165°（中心 0/30/…/150），左下方 180° 缺口。

## 视图层（`RingView`，v4）

- **每个 item 一个局部 view（v5.3）**：view 中心 = 该片槽位点（槽位角 θ、中径 68），**logo 恰在 view 中心**（ZStack 默认居中，无 .position 偏移）；`WedgeShape(centerAngle: θ−π/2, bladeWidth: 30°, arcCenter: 指向环心的偏移)` 把扇面**围绕 logo 画出**（局部坐标系里弧心 = `bladeViewSide/2 − 槽位向量`）。组装：`ZStack { 表面填充 + 状态填充 + 描边 + logo }.frame(bladeViewSide 64).shadow(缝投影).rotation3DEffect(切向轴, anchor 默认 .center = logo).position(环心 + 槽位向量 + pop·径向)`。旧结构（v1–v5.2，环心画布 + logo 偏移 68pt）在 3D 变换下会把画布内偏移的 logo 甩离扇面——v5.0/v5.1 分离的根因；新结构里 logo 在 pivot 上，任何变换都带着扇面刚体同动。
- 形状 `WedgeShape(index: 0, count: 1, centerAngle: θ_i, bladeWidth: ω)`——`centerAngle` 参数（v4 加入）直接指定槽位角，形状自己完成槽位放置，**全程无 2D rotationEffect**（`rotation3DEffect` 与 `rotationEffect` 组合会破坏布局，渲染实验证实）。
- 3D 倾斜（**v5.2 当前关闭：`blade3DTiltDegrees = 0`，`BladeTilt` 修饰符仅在该 token 非 0 时应用 `rotation3DEffect`，否则完全跳过**）：轴 = 该片切向 `(cos θ, sin θ, 0)`、`anchor:` 锚到该片图标中心（`UnitPoint(iconCenter/side)`）、perspective 0.75——历史教训：默认 `.center` 的轴穿环心，图标离轴 68pt 转后获 ±23pt z 位移，被透视甩离槽位；锚到图标后数学上图标零位移,但实机观感仍不对（两次尝试均被用户否决）,如重试需先用真实窗口截图验证。
- 框半径 = `outerRadius + popOffset + shadowPad`；缺口不改变画布尺寸。
- `WedgeShape`：`bladeWidth` 角宽与槽距解耦；`centerAngle` 覆写槽位角；fillet clamp 用 `sin(ω/2)`；原 `gap` 数学已删。

## Token（`RingTheme`）

`outerRadius 96` / `innerRadius 40` / `bladeCornerRadius 10` / **`bladeDegrees 30`**（v5：固定扇面角宽，11 片 × 30° = 330°）/ `arcGapDegrees 30`（收口缺口下限）/ `blade3DTiltDegrees 0`（v5.2 关闭 3D 倾斜）/ `blade3DPerspective 0.75`（tilt 为 0 时不生效）/ `popOffset 6` / `shadowPad 14` / `iconSize 32` / 每片缝投影（黑 30%、半径 3）。v5 删除 `bladeOverlapFactor`、`maxBladeDegrees`。

## 材质（重要坑，v4 两次实证）

- 每片表面用**半透明深色纯填充**（`glassTint` 黑 28%）。**禁用**三类材质方案：
  1. macOS 26 `glassEffect`——同一 compositing group 内多个 glassEffect 只渲染最后一个并吞掉兄弟图层；
  2. `VisualEffectView`（NSViewRepresentable）——NSView 不跟随 Core Animation 3D 变换；
  3. SwiftUI `Material`（`.ultraThinMaterial` 等，macOS 上同为 AppKit 特性视图backing）——会打破同容器 Z 序合成，**吞掉同容器的兄弟图层**（v4 渲染对照实验：加入 Material 后 0 号图标消失，换成纯填充即恢复）。

## 保持不变

- 交互流程（按住唤出、死区、松开选中）、`RingPanel`、`RingWindowController`、`HotkeyService`、两个环共用一套视图、弹入/高亮动画、整体阴影。

## 验证

- 渲染 harness（真实 `RingView` + 真实窗口截图）人工核对：六片 30° 同尺寸、以正上方为中心对称、正下方缺口清晰、倾斜可见、图标正立（不入库）。
- 单测全过（v5 重写 `BladeLayout` 布局数学：固定 30°、11 片上限、对称 start、**刀缝边界命中**、缺口 nil、单片与 12 片叠压语义）。
- 构建 + 真机验看。

## 未纳入（YAGNI）

- 缺口角度/倾角/轴心偏移不做设置项（改 token 即可调）；倾斜方向若与参考图相反，翻转 `bladeTiltDegrees` 符号即可；不改配色（保留磨砂玻璃语言）；不做 List/Palette 模式。

## v5.5：shingle 叠压 + 圆角梯形卡 + 内缘铰接 3D（2026-09-04，分支 `feature/blade-card-depth`）

用户以 Dory App Switcher 参考图为标准提出三点：环形 UI 要有 3D 倾斜与纵深、前一片 zIndex 高于后一片（微微压住后一个）、尽量 1:1 复刻。此前 v5.3/v5.4 的 20° 中心 pivot 倾斜实际只压缩卡面约 6%，观感是平的。

**改动（`RingTheme` token + `RingView`）：**

1. **内缘铰接倾斜**：`rotation3DEffect` 锚点从卡面中心移到内缘（`blade3DHingeFraction = 1`，anchor = 中心向环心偏 band/2），卡片像翻板一样从内缘向后倒，外缘远去——纵深的主线索。倾角 32°、perspective 0.6。实验结论：42°+0.6 会把外缘剪影整体塌进环里（弃）；`perspective` 旋钮在 0.6~0.85 间对透视反差作用很弱。
2. **前压后 z 序**：每片 `.zIndex(bladeCount − i)`（0 号最上，hover 片再加 `bladeCount` 顶到最上），fan 顺时针时每片盖住顺时针方向的下家；每片缝阴影因此自动变成"上家投影在下家上"。命中测试仍按 slot 刀缝（已确认接受被压条带外缘 ~3.5pt 命中归下家）。
3. **圆角梯形卡**：`WedgeShape`（弧边）替换为 `CardBladeShape`（内外缘直线弦 + 四角圆角 fillet，逐角按邻边 clamp）。角度约定与 WedgeShape 一致（SwiftUI 角、`−π/2` 转换），原约定哨兵测试移植为 `CardBladeShapeTests`。`cornerRadius` 10→18。
4. **几何比例**：`innerRadius 40→30`、`outerRadius 96→104`（band 74，卡面大而饱满、环孔占比小）、`bladeViewSide 64→88`、`iconSize 28→32`（随槽宽缩放：`min(iconSize, 2·midRadius·sin(rad(pitch+overlap)/2)·0.7)`，片多时图标跟着缩，防止串珠化）。
5. **叠压封顶**：渲染宽度 = pitch + min(8°, 30%·pitch)。>11 片 pitch 压缩时叠压不再放大，14 片实测仍为清爽叠瓦。
6. **浅色磨砂**：`glassTint` 黑 28% → 白 30%（参考图卡面为浅磨砂），分隔线白 12% → 黑 12%。

**验证**：临时渲染 probe（真实窗口 + 外部 `screencapture -l`；注意 xctest 进程无屏幕录制权限，须由有权限的 shell 按窗口号截）6 片 / 14 片双 Case 与参考图并排比对迭代 6 轮；单测 23 项全过；真机 ⌃T 验看。

**已知未复刻**：参考图顶卡外缘略窄于内缘（强透视反差），SwiftUI `perspective` 参数在该量级下拉不出；卡片角部高光、字母 label 未做（用户明确不加 label）。
