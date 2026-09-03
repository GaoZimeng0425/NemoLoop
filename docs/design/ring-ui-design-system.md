# NemoLoop Ring — UI Design System (extracted from Loop)

> Source of truth: Kai Azim's **Loop** radial menu (`/Users/gaozimeng/Learn/macOS/Loop/Loop/Window Action Indicators/Radial Menu/`). This doc extracts Loop's *visual language* and re-expresses it for NemoLoop, which since 2026-09-03 draws **overlapping fan blades** (Dory-style annular sectors, each wider than its slot so it tucks under the previous one; upright icons) rather than Loop's fill-and-mask technique. We borrow Loop's **look** (gradient accent, glass/blur material, hairline borders, motion), not its **construction**. Parts A/B/C below describe the earlier wedge-based construction and remain as historical reference for the shared tokens.

---

## Part A — What Loop actually does (extracted, with refs)

Loop's ring is **one uniformly-filled band + one animated highlight wedge**, assembled by masking:

1. `radialMenuFill()` — a `Rectangle` filled with a **diagonal gradient** `LinearGradient([color1, color2], .topLeading → .bottomTrailing)` (`RadialMenuView.swift:107`).
2. `.mask(directionSelectorMask)` — clips that fill to the **current selection wedge** (a pie slice ±22.5°), so only the selected direction shows accent (`RadialMenuView.swift:122`).
3. `.mask(radialMenuMask)` — clips everything to the **ring band**, produced by **stroking a shape**: `Circle().strokeBorder(.black, lineWidth: radialMenuThickness)` (`RadialMenuView.swift:158`). The stroke *width* is the donut band; the hole is free.
4. `radialMenuBorder()` — two `.quinary` hairlines (`lineWidth: 2`): one on the outer edge, one inset by `thickness` for the inner edge (`RadialMenuView.swift:140`).
5. Backing material: pre-Tahoe `VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)` (`RadialMenuView.swift:96`); macOS 26+ `.glassEffect(.regular.tint(color1.opacity(0.025)), in: .rect(cornerRadius:))` Liquid Glass (`RadialMenuView.swift:50`).
6. `overlayImage()` — the action's SF Symbol, `foregroundStyle(color1)`, `.system(size: 20, weight: .bold)`, with `.symbolEffect(.drawOn)` / `.replace` transitions on Tahoe (`RadialMenuView.swift:175`).

### Extracted constants (Loop defaults)

| Token | Value | Source |
|---|---|---|
| Diameter (`radialMenuSize`) | **100** pt | `RadialMenuView.swift:21` |
| Band thickness (`radialMenuThickness`) | **22** pt | `Defaults+Extensions.swift:30` |
| Corner radius (`radialMenuCornerRadius`) | **50** (= size/2 → perfect circle; if `< size/2 − 2` → rounded-square variant) | `Defaults+Extensions.swift:29`, `RadialMenuView.swift:128` |
| Outer padding | **40** pt (shadow/scale headroom) + `.fixedSize()` | `RadialMenuView.swift` body |
| Selection half-angle | **±22.5°** → 45° wedges → 8 directions | `DirectionSelectorCircleSegment.swift:39` |
| Accent mode | `.system` or custom; `customAccentColor` default `.teal`, `gradientColor` default `.blue` | `Defaults+Extensions.swift:22-25` |
| Border color | `.quinary`, `lineWidth: 2`, ×2 (outer + inner) | `RadialMenuView.swift:140` |
| Shadow | `radius: 10`, `black.opacity(0.2)` | `RadialMenuView.swift` |
| Fill-all scale | `scaleEffect(0.85)` when whole ring fills (center action) | `RadialMenuViewModel.shouldFillRadialMenu` |

### Extracted motion

| Motion | Curve / value | Source |
|---|---|---|
| Appearance (`isShown`) | `.smooth(duration: 0.1)` | `RadialMenuViewModel.setIsShown` |
| Shadow appearance | same, **offset by 0.05** so shadow trails the body | `RadialMenuViewModel.setIsShown` |
| Pop-in transition (Tahoe) | `.scale(scale: 1.25).combined(with: .opacity)` | `RadialMenuView.swift:78` |
| **Highlight slide between directions** | `.timingCurve(0.22, 1, 0.36, 1, duration: 0.2)` | `AnimationConfiguration.radialMenuAngle` |
| Size changes | `.easeOut(duration: 0.2)` (0.1–0.2 by speed preset) | `AnimationConfiguration.radialMenuSize` |
| Speed presets | fluid / relaxed / snappy / brisk / instant | `AnimationConfiguration` |

**Key idea:** the highlight is a **single wedge whose `angle` is `animatableData`** — moving between directions animates the angle, so the accent *slides* smoothly around the ring instead of cutting.

---

## Part B — NemoLoop design tokens

NemoLoop's ring is bigger (it holds 28pt app icons) and draws **6 content wedges that are always visible**, so we adapt rather than copy 1:1. Centralize everything in one `RingTheme`:

```swift
// NemoLoop/Ring/RingTheme.swift
import SwiftUI

enum RingTheme {
    // Geometry (keep current RingView radii)
    static let outerRadius: CGFloat = 96
    static let innerRadius: CGFloat = 40          // band thickness = 56
    static let canvasPadding: CGFloat = 40        // shadow/pop-in headroom
    static let wedgeGap: Angle = .degrees(1.5)    // hairline gap between wedges

    // Accent gradient (Loop's color1 → color2, diagonal)
    static let accentStart = Color.accentColor
    static let accentEnd   = Color.accentColor.mix(with: .blue, by: 0.45)
    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accentStart, accentEnd],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // Surfaces / state fills
    static let baseFill        = Color.black.opacity(0.55)   // assigned, idle
    static let emptyFill       = Color.black.opacity(0.32)   // empty slot, idle
    static let highlightEmpty  = Color.white.opacity(0.18)   // empty slot, highlighted

    // Borders (Loop's dual quinary hairlines)
    static let borderColor = Color.white.opacity(0.18)       // ≈ .quinary on dark
    static let borderWidth: CGFloat = 1
    static let dividerColor = Color.white.opacity(0.12)
    static let dividerWidth: CGFloat = 1

    // Icon
    static let iconSize: CGFloat = 28
    static let iconTint = Color.white

    // Depth
    static let shadowRadius: CGFloat = 10
    static let shadowColor = Color.black.opacity(0.22)

    // Motion
    static let appear   = Animation.smooth(duration: 0.16)
    static let highlight = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.16)
    static let popIn = AnyTransition.scale(scale: 1.2).combined(with: .opacity)
}
```

---

## Part C — Concrete implementation plan

We **keep `WedgeShape`** (it draws each annular sector). We add five visual layers on top of the current `RingView`, all reading from `RingTheme`. Build order, each independently buildable:

### Step 1 — Material backing (glass on Tahoe, blur below)

A single ring-shaped material sits **behind** all wedges, giving Loop's frosted depth. Mask a material to the donut band via a stroked circle (Loop's trick, used here only for the backing):

```swift
private var ringBand: some Shape {           // donut band as one shape, for masking
    Circle().strokeBorder(style: .init(lineWidth: outerRadius - innerRadius))
    // or: a custom Shape if you want the exact inner/outer radii
}

@ViewBuilder private func backing() -> some View {
    let band = Circle().strokeBorder(lineWidth: RingTheme.outerRadius - RingTheme.innerRadius)
    if #available(macOS 26.0, *) {
        Color.clear
            .glassEffect(.regular.tint(RingTheme.accentStart.opacity(0.025)),
                         in: .circle)
            .mask(band)
    } else {
        VisualEffectView(material: .hudWindow, blendingMode: .behindWindow, state: .active)
            .mask(band)
    }
}
```

> Pre-Tahoe needs an `NSVisualEffectView` wrapper (`VisualEffectView`) — copy Loop's small `NSViewRepresentable`. On macOS 26+, `glassEffect` is native.

### Step 2 — Per-wedge fills, now gradient-on-highlight

Replace `RingView.fillColor` so the **highlighted, assigned** wedge paints with the **gradient** (Loop's signature), not a flat accent. Because `.fill` wants a `ShapeStyle`, branch the view:

```swift
@ViewBuilder private func wedgeFill(for i: Int) -> some View {
    let shape = WedgeShape(index: i, count: wedgeCount,
                           innerRadius: RingTheme.innerRadius, outerRadius: RingTheme.outerRadius)
    let isEmpty = store.config.slots[i] == nil
    let isHot = viewModel.highlightedIndex == i

    if isHot && !isEmpty {
        shape.fill(RingTheme.accentGradient)          // ← Loop look
    } else if isHot {
        shape.fill(RingTheme.highlightEmpty)
    } else {
        shape.fill(isEmpty ? RingTheme.emptyFill : RingTheme.baseFill)
    }
}
```

### Step 3 — Dual hairline borders + wedge dividers

Loop strokes the outer and inner rims with `.quinary`. We add both rims once (not per wedge) plus thin radial dividers between wedges:

```swift
@ViewBuilder private func borders() -> some View {
    ZStack {
        Circle().stroke(RingTheme.borderColor, lineWidth: RingTheme.borderWidth)      // outer rim
            .frame(width: RingTheme.outerRadius * 2, height: RingTheme.outerRadius * 2)
        Circle().stroke(RingTheme.borderColor, lineWidth: RingTheme.borderWidth)      // inner rim
            .frame(width: RingTheme.innerRadius * 2, height: RingTheme.innerRadius * 2)
    }
}
```

Per-wedge `.stroke` (already in `RingView.swift:24-28`) becomes the divider — switch its color to `RingTheme.dividerColor`.

### Step 4 — Icon styling

Match Loop's bold, tinted icons. App icons stay full-color (`NSImage`); the empty-slot "+" adopts Loop's treatment:

```swift
Image(systemName: "plus")
    .font(.system(size: 18, weight: .bold))
    .foregroundStyle(RingTheme.iconTint.opacity(0.35))
```

On macOS 26+, optionally add `.contentTransition(.symbolEffect(.replace))` so a wedge's symbol animates when reassigned.

### Step 5 — Depth + motion

Wrap the whole ring (in `RingView.body`) with shadow, pop-in transition, and the highlight curve:

```swift
ZStack {
    backing()
    ForEach(0..<wedgeCount, id: \.self) { i in
        wedgeFill(for: i)
            .overlay(WedgeShape(...).stroke(RingTheme.dividerColor, lineWidth: RingTheme.dividerWidth))
        iconView(for: i)
    }
    borders()
}
.frame(width: RingTheme.outerRadius * 2, height: RingTheme.outerRadius * 2)
.compositingGroup()
.shadow(color: RingTheme.shadowColor, radius: RingTheme.shadowRadius)
.position(center)
.animation(RingTheme.highlight, value: viewModel.highlightedIndex)   // smooth highlight
.transition(RingTheme.popIn)                                         // 1.2× pop-in
```

The pop-in needs the ring to be conditionally inserted (`if viewModel.isShown`) for the transition to fire; the panel already creates/destroys the host on show/hide, so wrap the `ZStack` in `if viewModel.isShown { … }` to get the scale+fade.

---

## States reference

| State | Fill | Icon | Notes |
|---|---|---|---|
| Assigned, idle | `baseFill` (black 55%) | app icon | over frosted backing |
| Assigned, **highlighted** | **`accentGradient`** | app icon | the Loop signature |
| Empty, idle | `emptyFill` (black 32%) | dim "+" | clearly de-emphasized |
| Empty, highlighted | `highlightEmpty` (white 18%) | dim "+" | highlighted but no launch on release |
| Ring (all) | frosted material + dual hairline rims | — | shadow radius 10 |

---

## Light / dark & appearance notes

- Loop tints via Luminare's `luminareTint`. NemoLoop's ring panel is a dark transparent overlay, so the tokens above assume a **dark surface** (white-opacity borders). If a light variant is ever needed, swap `borderColor`/`dividerColor`/`baseFill` to `.black.opacity(...)` and gate on `@Environment(\.colorScheme)`.
- `glassEffect` is **macOS 26+ only**; always keep the `VisualEffectView` fallback so the ring renders on earlier systems.
- Keep the **curated accent gradient** (`accentStart → accentEnd`) as one place to retheme; do not hardcode gradient colors inside `RingView`.

---

## What we deliberately did NOT copy from Loop

- **Fill-and-mask construction** — we draw explicit `WedgeShape` sectors instead, because each NemoLoop wedge is an independent content slot (its own app + icon + state), which the single-mask approach can't express cleanly.
- **Rounded-square variant** (`DirectionSelectorSquareSegment`) — optional future token (`cornerRadius`), not in scope.
- **Any exact-slice construction** — since 2026-09-03 NemoLoop renders Dory-style overlapping fan blades (`BladeLayout` in `RingGeometry.swift` is the single layout source: fixed blade width over `360° − arcGapDegrees`, leaving a wrap gap between the last blade and the first; pointer in the gap selects nothing). Each blade is independently tilted via `rotationEffect(slot + tilt)` about an arc center offset tangentially by `bladePivotOffset`; ascending z-order; per-blade seam shadow; upright icons above all blades; no continuous ring backing. Per-blade macOS 26 `glassEffect` inside a compositing group renders only the last shape and suppresses siblings — each blade uses its own `VisualEffectView` material; do not reintroduce glassEffect here. See `docs/superpowers/specs/2026-09-03-fan-blade-ring-design.md`.
