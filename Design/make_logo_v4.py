#!/usr/bin/env python3
"""NemoLoop logo generator v4 (mixed sheet: simplified rings A1-A3 + new concepts B1-B3).

v3 feedback -> v4: user still unsatisfied with "app ring UI scaled into an icon"
(11 small cards = too much information at icon sizes). This round puts BOTH
routes on one comparison sheet, all on the same warm-paper (E) body:

  A1 分段环   — abstract segmented ring, 7 round-cap dashes at 45° pitch,
                orange dash at 12, natural opening upper-left (loose nod to
                the app's 11 o'clock gap; cards dropped)
  A2 动势三弧 — three bold chasing arcs (tight->loose gaps) suggesting
                spin/launch, orange leading arc at 12
  A3 六大卡   — route-A faithful: only 6 big rounded blade cards (was 11),
                orange card popped at 12
  B1 回环点   — pure loop glyph: one bold 280° arc, orange dot nestled in the
                gap at 11 o'clock ("the loop completes when you launch")
  B2 N字标    — NemoLoop monogram, round-cap N with orange diagonal
  B3 六瓣光圈 — 6 stadium-shaped petals in a shutter/swirl, hexafoil opening
                at center, orange petal at 12 (fan abstracted to petals)

Usage:
  python3 make_logo_v4.py            # variants/A1..B3-*.svg + variants/sheet-mix.svg
  python3 make_logo_v4.py A1         # promote option -> ../logo.svg + previews
"""
import math
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
VARIANTS = os.path.join(HERE, "variants")
PREVIEW = os.path.join(HERE, "preview")

BODY = (100, 100, 824, 824, 185)  # macOS icon body: x, y, w, h, corner

# E palette (v2/v3 decision, keep verbatim)
BG = ("#F7F3EA", "#EAE3D3", "#D7CEBA")
FACE = ("#3A342E", "#282320", "#1D1A17")
HOT = ("#EB9433", "#DA7E20")

CANDS = ["A1", "A2", "A3", "B1", "B2", "B3"]
LABELS = {
    "A1": "分段环",
    "A2": "动势三弧",
    "A3": "六大卡",
    "B1": "回环点",
    "B2": "N字标",
    "B3": "六瓣光圈",
}


def polar(a_deg, r):
    a = math.radians(a_deg)
    return (r * math.sin(a), -r * math.cos(a))


def fmt(p):
    return f"{p[0]:.2f},{p[1]:.2f}"


def arc_d(a0, a1, r):
    """Clockwise arc path from angle a0 to a1 (deg, 0=12 o'clock) on circle r."""
    large = 1 if (a1 - a0) > 180 else 0
    return f"M {fmt(polar(a0, r))} A {r:.1f} {r:.1f} 0 {large} 1 {fmt(polar(a1, r))}"


def card_d(half, cin, cout, r1, r2):
    """Rounded annular sector: Q-fillet corners (90° corners, v3-proven look)
    + true circular outer edge on r2 (tangent pull-in asin(cout/(r2-cout)))
    -> silhouette stays within +/-half, no neighbor overlap at coarse pitch."""
    tin = math.degrees(cin / r1)                 # corner pull-back, inner arc
    do = math.asin(cout / (r2 - cout))
    ao = half - math.degrees(do)                 # outer arc extent

    return (
        f"M {fmt(polar(-half + tin, r1))} "
        f"A {r1:.1f} {r1:.1f} 0 0 1 {fmt(polar(half - tin, r1))} "
        f"Q {fmt(polar(half, r1))} {fmt(polar(half, r1 + cin))} "
        f"L {fmt(polar(half, r2 - cout))} "
        f"Q {fmt(polar(half, r2))} {fmt(polar(ao, r2))} "
        f"A {r2:.1f} {r2:.1f} 0 0 0 {fmt(polar(-ao, r2))} "
        f"Q {fmt(polar(-half, r2))} {fmt(polar(-half, r2 - cout))} "
        f"L {fmt(polar(-half, r1 + cin))} "
        f"Q {fmt(polar(-half, r1))} {fmt(polar(-half + tin, r1))} Z"
    )


def body(tag):
    return f'''<rect x="{BODY[0]}" y="{BODY[1]}" width="{BODY[2]}" height="{BODY[3]}" rx="{BODY[4]}" fill="url(#bg{tag})"/>
<rect x="{BODY[0]}" y="{BODY[1]}" width="{BODY[2]}" height="{BODY[3]}" rx="{BODY[4]}" fill="url(#sn{tag})"/>
<rect x="{BODY[0] + 6}" y="{BODY[1] + 6}" width="{BODY[2] - 12}" height="{BODY[3] - 12}" rx="{BODY[4] - 5}"
      fill="none" stroke="#000000" stroke-opacity="0.06" stroke-width="3"/>'''


def defs_common(tag):
    return f'''  <linearGradient id="bg{tag}" x1="0" y1="0" x2="0.6" y2="1">
    <stop offset="0" stop-color="{BG[0]}"/>
    <stop offset="0.55" stop-color="{BG[1]}"/>
    <stop offset="1" stop-color="{BG[2]}"/>
  </linearGradient>
  <radialGradient id="sn{tag}" cx="0.5" cy="0.05" r="0.9">
    <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.35"/>
    <stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
  </radialGradient>
  <linearGradient id="fc{tag}" gradientUnits="userSpaceOnUse" x1="212" y1="812" x2="812" y2="212">
    <stop offset="0" stop-color="{FACE[0]}"/>
    <stop offset="0.55" stop-color="{FACE[1]}"/>
    <stop offset="1" stop-color="{FACE[2]}"/>
  </linearGradient>
  <linearGradient id="ht{tag}" gradientUnits="userSpaceOnUse" x1="312" y1="712" x2="712" y2="312">
    <stop offset="0" stop-color="{HOT[0]}"/>
    <stop offset="1" stop-color="{HOT[1]}"/>
  </linearGradient>
  <filter id="cs{tag}" filterUnits="userSpaceOnUse" x="-512" y="-512" width="1024" height="1024">
    <feDropShadow dx="0" dy="9" stdDeviation="9" flood-color="#000000" flood-opacity="0.30"/>
    <feDropShadow dx="0" dy="24" stdDeviation="28" flood-color="#000000" flood-opacity="0.15"/>
  </filter>
  <filter id="hm{tag}" filterUnits="userSpaceOnUse" x="-512" y="-512" width="1024" height="1024">
    <feDropShadow dx="0" dy="11" stdDeviation="11" flood-color="#000000" flood-opacity="0.34"/>
    <feDropShadow dx="0" dy="0" stdDeviation="26" flood-color="#FFD9A0" flood-opacity="0.30"/>
  </filter>'''


# ---- candidate mark builders: return inner content, canvas center (512,512) ----

def mark_a1(tag):
    # 7 round-cap dashes at 45° pitch (0..270), orange at 12; the missing
    # 45° slot reads as an upper-left opening.
    r, w, arc = 245.0, 118.0, 9.0
    out = []
    for k in range(1, 7):
        c = k * 45.0
        out.append(f'  <path d="{arc_d(c - arc / 2, c + arc / 2, r)}" fill="none"'
                   f' stroke="url(#fc{tag})" stroke-width="{w}" stroke-linecap="round"/>')
    out.append(f'  <path d="{arc_d(-arc / 2, arc / 2, r)}" fill="none"'
               f' stroke="url(#ht{tag})" stroke-width="{w}" stroke-linecap="round"'
               f' filter="url(#hm{tag})"/>')
    return "\n".join(out)


def mark_a2(tag):
    # Three chasing arcs, clockwise; gaps tighten toward the orange leader.
    r, w = 250.0, 132.0
    arcs = [(-5.0, 83.0, True), (120.0, 184.0, False), (240.0, 282.0, False)]
    out = []
    for a0, a1, hot in arcs:
        stroke = f"url(#ht{tag})" if hot else f"url(#fc{tag})"
        extra = f' filter="url(#hm{tag})"' if hot else ""
        out.append(f'  <path d="{arc_d(a0, a1, r)}" fill="none" stroke="{stroke}"'
                   f' stroke-width="{w}" stroke-linecap="round"{extra}/>')
    return "\n".join(out)


def mark_a3(tag):
    # 6 big rounded cards, pitch 48° -> 72° gap centered ~324°; orange card
    # popped at 12. Base path is defined hidden and referenced via <use>.
    half, cin, cout, r1, r2 = 19.5, 22.0, 34.0, 155.0, 345.0
    d = card_d(half, cin, cout, r1, r2)
    cards = "".join(
        f'  <use href="#cd{tag}" transform="rotate({k * 48})" fill="url(#fc{tag})"'
        f' stroke="#FFFFFF" stroke-opacity="0.14" stroke-width="2" filter="url(#cs{tag})"/>\n'
        for k in range(5, 0, -1)
    )
    pop = (f'  <use href="#cd{tag}" transform="translate(0 -22)" fill="url(#ht{tag})"'
           f' filter="url(#hm{tag})"/>\n')
    # base path inside inline <defs>: never rendered itself, so uses keep their own fill
    return f'  <defs><path id="cd{tag}" d="{d}"/></defs>\n' + cards + pop


def mark_b1(tag):
    # One bold 280° loop, gap centered at 330 (11 o'clock); orange dot nestled
    # in the gap bridging the loop = "the loop completes".
    r, w = 250.0, 140.0
    out = [f'  <path d="{arc_d(10.0, 290.0, r)}" fill="none" stroke="url(#fc{tag})"'
           f' stroke-width="{w}" stroke-linecap="round"/>']
    dx, dy = polar(330.0, r)
    out.append(f'  <circle cx="{dx:.2f}" cy="{dy:.2f}" r="88" fill="url(#ht{tag})"'
               f' filter="url(#hm{tag})"/>')
    return "\n".join(out)


def mark_b2(tag):
    # N monogram: two round-cap bars + orange diagonal (round caps unify).
    # Coordinates are GROUP-relative (group already translates to canvas center).
    x0, x1, y0, y1, w = -150.0, 150.0, -188.0, 188.0, 88.0
    return f'''  <path d="M {x0},{y1} L {x0},{y0}" fill="none" stroke="url(#fc{tag})" stroke-width="{w}" stroke-linecap="round"/>
  <path d="M {x1},{y1} L {x1},{y0}" fill="none" stroke="url(#fc{tag})" stroke-width="{w}" stroke-linecap="round"/>
  <path d="M {x0},{y0} L {x1},{y1}" fill="none" stroke="url(#ht{tag})" stroke-width="{w}" stroke-linecap="round" filter="url(#hm{tag})"/>'''


def mark_b3(tag):
    # Shutter/petal swirl: 6 stadium petals, radial, pitch 60°, inner tips at
    # r=100 leaving a hexafoil opening; orange petal points at 12.
    out = []
    for k in range(5, 0, -1):
        out.append(f'  <rect x="-55" y="-330" width="110" height="230" rx="55"'
                   f' transform="rotate({k * 60})" fill="url(#fc{tag})"/>')
    out.append(f'  <rect x="-55" y="-330" width="110" height="230" rx="55"'
               f' fill="url(#ht{tag})" filter="url(#hm{tag})"/>')
    return "\n".join(out)


MARKS = {"A1": mark_a1, "A2": mark_a2, "A3": mark_a3,
         "B1": mark_b1, "B2": mark_b2, "B3": mark_b3}


def build_svg(key):
    tag = key
    mark = MARKS[key](tag)
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<defs>
{defs_common(tag)}
</defs>

{body(tag)}

<g transform="translate(512 512)">
{mark}
</g>
</svg>
'''


def build_sheet():
    cells = []
    for n, key in enumerate(CANDS):
        col, row = n % 3, n // 3
        x = 15 + col * 415
        y = 60 + row * 465
        inner = build_svg(key)
        inner = inner[inner.index(">") + 1:inner.rindex("</svg>")]
        cells.append(
            f'<svg x="{x}" y="{y}" width="380" height="380" viewBox="0 0 1024 1024">{inner}</svg>\n'
            f'<text x="{x + 190}" y="{y + 424}" text-anchor="middle" font-family="PingFang SC"'
            f' font-size="30" fill="#3A3A3A">{key} · {LABELS[key]}</text>'
        )
    # 128px legibility strip under the grid
    strip = []
    for n, key in enumerate(CANDS):
        x = 15 + n * 178
        inner = build_svg(key)
        inner = inner[inner.index(">") + 1:inner.rindex("</svg>")]
        strip.append(
            f'<svg x="{x}" y="1010" width="128" height="128" viewBox="0 0 1024 1024">{inner}</svg>\n'
            f'<text x="{x + 64}" y="1168" text-anchor="middle" font-family="PingFang SC"'
            f' font-size="22" fill="#8A8A8A">{key} · 128px</text>'
        )
    note_x = 15 + 5 * 178 + 148
    strip_note = (f'<text x="{note_x}" y="1082" font-family="PingFang SC"'
                  f' font-size="24" fill="#8A8A8A">128px 可读性</text>')
    title = ('<text x="18" y="40" font-family="PingFang SC" font-size="26"'
             ' fill="#5A5248">NemoLoop logo v4 · 混合对比(简化环 A1-A3 / 新概念 B1-B3)</text>')
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1260" height="1190"'
            ' viewBox="0 0 1260 1190">\n<rect width="1260" height="1190" fill="#FFFFFF"/>\n'
            + title + "\n" + "\n".join(cells) + "\n" + "\n".join(strip) + "\n"
            + strip_note + "\n</svg>\n")


def main():
    os.makedirs(VARIANTS, exist_ok=True)
    os.makedirs(PREVIEW, exist_ok=True)
    for key in CANDS:
        name = f"{key}-{LABELS[key]}.svg"
        with open(os.path.join(VARIANTS, name), "w") as f:
            f.write(build_svg(key))
    with open(os.path.join(VARIANTS, "sheet-mix.svg"), "w") as f:
        f.write(build_sheet())
    print("wrote A1..B3 variants + sheet-mix.svg")

    if len(sys.argv) > 1:
        arg = sys.argv[1]
        if arg not in CANDS:
            raise SystemExit(f"unknown option: {arg} (choose from {CANDS})")
        with open(os.path.join(HERE, "logo.svg"), "w") as f:
            f.write(build_svg(arg))
        for size in (1024, 128):
            subprocess.run(["qlmanage", "-t", "-s", str(size), "-o", PREVIEW,
                            os.path.join(HERE, "logo.svg")], capture_output=True)
            src = os.path.join(PREVIEW, "logo.svg.png")
            if os.path.exists(src):
                shutil.move(src, os.path.join(PREVIEW, f"logo-{size}.png"))
        print(f"promoted {arg} -> logo.svg + previews")


if __name__ == "__main__":
    main()
