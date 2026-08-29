# 开口弧形环（Open-Arc Ring）— 设计

**日期**: 2026-08-30
**范围**: 把环从完整 360° 圆环改为 Dory App Switcher 风格的开口 C 形弧（约 300° 跨度、左上方留缺口）；渲染与命中测试同步修改
**参考**: Dory App Switcher（https://apps.apple.com/nl/app/dory-app-switcher/id6746273626）截图——开口梯形扇环扇形 + 正立图标 + 空心中心

## 目标

把现有的完整 360° 环（连续磨砂背衬 + 均分楔片）改成**开口弧**：

1. 楔片分布在 **300° 的弧**上，而不是 360° 全周。
2. **缺口固定在左上方（10:30 方向）**，缺口中心角 = -45°（以正上方为 0°、顺时针为正），缺口跨度 **60°**。
3. 楔片 0 从弧的起点（-15°，即 11:30 位置）开始顺时针排布；索引语义与现状一致（顺时针递增）。
4. 连续磨砂背衬随之变为**同弧度的 C 形带**（平端收尾）。
5. 命中测试同步：指针落在缺口区域内（死区之外）返回 `nil`（无选中，松开不动作）。
6. 两个环（launcher 固定 6 格、running-apps 动态格数）共用同一几何，一起生效。

## 角度约定

- **"from-up" 约定**（`RingGeometry` 命中测试、`RingTheme` 常量）：0° = 正上方，顺时针为正，取值 [0°, 360°)。`atan2(dx, dy)`。
- **SwiftUI path 约定**（`WedgeShape`）：0 = +x（右），y 向下，顺时针为正；正上方 = -π/2。换算：`pathAngle = fromUpRadians - π/2`。

换算只发生一次：`RingView` 把 `RingGeometry` 的 from-up 弧参数转成 path 约定传给 `WedgeShape`。

## 方案

### 1. 常量（`RingTheme`）

```swift
// 开口弧几何：缺口在 10:30 方向，楔片均分其余 300°
static let arcGapCenterDegrees: Double = -45   // from-up 约定（-45° = 315° = 10:30）
static let arcGapSpanDegrees: Double = 60
static var arcSpanDegrees: Double { 360 - arcGapSpanDegrees }      // 300
static var arcStartDegrees: Double { arcGapCenterDegrees + arcGapSpanDegrees / 2 }  // -15
```

半径、间隙、圆角、图标、动画等其余 token 不变。

### 2. 命中测试（`RingGeometry`）

`wedgeIndex(from:to:wedgeCount:deadZoneRadius:)` 改为弧内判定：

1. 死区判定不变（距中心 < deadZoneRadius → nil）。
2. 求 from-up 角 `a`（0 at up, 顺时针, 归一化到 [0, 2π)）。
3. `rel = normalize(a - arcStart)`；`rel < arcSpan` → `Int(rel / (arcSpan / count))`；否则（在缺口内）→ `nil`。

`RingGeometry` 增加 `arcStart` / `arcSpan`（弧度，from-up 约定）两个静态计算属性，读取 `RingTheme` 常量——渲染与命中测试共用唯一真源，不会漂移。

### 3. 楔片形状（`WedgeShape`）

签名增加两个参数（不再依赖隐式的“0 号楔片居中正上方”）：

```swift
WedgeShape(index:count:innerRadius:outerRadius:cornerRadius:gap:
           startAngle: Double,   // path 约定，第 0 号楔片 a0 侧边界
           span: Double)         // path 约定，全部楔片的总角跨
```

内部：`slice = span / count`；`centerAngle = startAngle + slice/2 + index*slice`。其余（平行间隙 asin 偏移、圆角 fillet、clamp）不变——这些数学只依赖半径与边界角，与跨度无关。旧行为等价于 `startAngle = -π/2 - π/count, span = 2π`。

### 4. 视图（`RingView`）

- `WedgeShape` 两个调用点传入 `RingGeometry` 换算后的 `startAngle` / `span`。
- `iconView` 的角度：`angle = arcStart + slice/2 + i * slice`（from-up 约定），dx/dy 映射公式不变。
- `AnnulusShape`（整圆环背衬）→ **`ArcBandShape`**：同样接收 `startAngle` / `span` / `innerRadius` / `outerRadius`，用中心线弧 `Path.strokedPath(StrokeStyle(lineWidth: outer-inner, lineCap: .butt))` 生成填充路径——即一条厚度 = 背衬带宽、跨度 = 楔片弧跨的 C 形带，两端平收。
  - **为什么是平端而不是圆头**：背衬带很厚（72pt），圆头帽的角向延伸 ≈ asin(capR/midR) ≈ ±32°，两端共 ~64° 会把 60° 缺口完全吃掉。
- 背衬的 macOS 26 `glassEffect(in:)` / 回退 `VisualEffectView + clipShape` 用法不变，只是 Shape 换成 `ArcBandShape`。

## 保持不变

- 楔片圆角（10pt）、平行间隙（4pt）、半径（40/96）、背衬径向外扩（±8pt）、图标尺寸/正立姿态、高亮渐变、动画、阴影。
- 交互流程（按住唤出、死区、松开选中）、`RingViewModel`、`RingPanel`、`RingWindowController`、`HotkeyService`。
- launcher 环与 running-apps 环的唤出/选中逻辑；两者因共用 `RingView` 自动获得新形状。

## 边界与错误处理

- **楔片数为 1**（running-apps 只开了一个应用）：单个 300° 楔片 + C 形背衬，几何上仍成立（fillet clamp 按 slice=300° 计算仍为正）。
- **指针在缺口内**：`wedgeIndex` 返回 nil，行为与死区一致（高亮清除、松开不动作）。
- **旧测试中“左上方 → 楔片 5”的用例**：左上方（约 -60°）落在缺口内，期望值改为 nil——这是行为变更的体现，不是回归。

## 验证

- 单测（`RingGeometryTests`，Swift Testing）：
  - 正上方 → 0（不变）；右上 ~60° → 1（不变）；正下 → 3（不变）。
  - 左上（缺口内，~-60°）→ nil（**新行为**）。
  - 边界：6 楔片刻 34° → 0、36° → 1（楔片 0/1 分界从 30° 移到 35°）。
  - 动态数量：3 楔片刻 slice=100°，弧起点 -15°，验证 -10°→0、100°→1、200°→2。
  - 缺口中心 -45°、缺口边缘 -75°/-16° 之外 → nil。
- 构建：`xcodebuild -project NemoLoop.xcodeproj -scheme NemoLoop -destination 'platform=macOS' build`。
- 视觉：用测试把 `ArcBandShape` + `WedgeShape` 渲染成 PNG 人工核对 C 形与缺口位置（临时脚本，不入库）。
- 真机：两个快捷键各按住一次，确认环呈 C 形、缺口在左上、高亮跟随、缺口内无高亮、松开行为正常。

## 未纳入（YAGNI）

- 缺口方向/跨度不做设置项，固定常量。
- 不做 Dory 的 List/Palette 模式。
- 不改配色（Dory 的奶油色块不搬，保留 NemoLoop 磨砂玻璃语言）。
