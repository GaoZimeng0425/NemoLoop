#!/usr/bin/env python3
"""NemoLoop logo generator (v3, palette E + rounded blades).

v2 feedback -> v3: on the 暖纸 (E) palette, blades become individual rounded
cards — much larger corner radii (outer edge clearly rounded), a thin angular
seam between blades so each rounded silhouette reads, same ring structure
(11 blades, gap at 11 o'clock, hot card popped at 12).

Usage:
  python3 make_logo.py            # variants/E1..E3 + variants/sheet-e.svg
  python3 make_logo.py E2         # promote option -> ../logo.svg + previews
"""
import math
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
VARIANTS = os.path.join(HERE, "variants")

# ---- ring geometry (RingTheme proportions, x2.615 to the 1024 canvas) ----
R1 = 146.0        # inner radius (56 * s)
R2 = 340.0        # outer radius (130 * s)
BOW = 1.0         # outer edge follows the ring circle -> smooth rim
POP = 12.0        # selected blade slides outward
BODY = (100, 100, 824, 824, 185)  # macOS icon body: x, y, w, h, corner

# Roundness levels for the blade cards (half = angular half-span in degrees,
# cin/cout = inner/outer corner radii; pitch stays 30 deg, seam = 30-2*half).
GEOS = {
    "E1": dict(tag="E1", label="适度圆角", half=14.0, cin=24.0, cout=36.0),
    "E2": dict(tag="E2", label="更圆", half=13.5, cin=30.0, cout=48.0),
    "E3": dict(tag="E3", label="药丸圆角", half=13.0, cin=32.0, cout=60.0),
}
DEFAULT_GEO = GEOS["E2"]

PALETTES = {
    "E": dict(name="暖纸", bg=("#F7F3EA", "#EAE3D3", "#D7CEBA"),
              face=("#3A342E", "#282320", "#1D1A17"), hot=("#EB9433", "#DA7E20"),
              dark_cards=True, sheen=0.35, edge=("#000000", 0.06), sh=(0.30, 0.15)),
}

def polar(a_deg, r):
    a = math.radians(a_deg)
    return (r * math.sin(a), -r * math.cos(a))

def fmt(p):
    return f"{p[0]:.2f},{p[1]:.2f}"

def blade_d(half, cin, cout):
    """Rounded-trapezoid sector: inner/outer arcs on the ring circles, radial
    sides, circular-arc corner fillets via tangent-shortened edges + quadratic
    corner joins."""
    x_c = R2 * math.sin(math.radians(half))
    y_c = -R2 * math.cos(math.radians(half))
    sag = R2 * (1 - math.cos(math.radians(half))) * BOW
    Rb = (x_c * x_c + sag * sag) / (2 * sag)
    bow_c = (0.0, y_c + (Rb - sag))

    def bow_pt(a_deg):
        a = math.radians(a_deg)
        return (bow_c[0] + Rb * math.cos(a), bow_c[1] + Rb * math.sin(a))

    a_lead = math.degrees(math.atan2(y_c - bow_c[1], x_c))
    a_trail = math.degrees(math.atan2(y_c - bow_c[1], -x_c))
    tin = math.degrees(cin / R1)          # fillet run measured on the inner arc
    tout = math.degrees(cout / Rb)        # fillet run on the outer arc

    return (
        f"M {fmt(polar(-half + tin, R1))} "
        f"A {R1:.1f} {R1:.1f} 0 0 1 {fmt(polar(half - tin, R1))} "
        f"Q {fmt(polar(half, R1))} {fmt(polar(half, R1 + cin))} "
        f"L {fmt(polar(half, R2 - cout))} "
        f"Q {fmt(polar(half, R2))} {fmt(bow_pt(a_lead + tout))} "
        f"A {Rb:.1f} {Rb:.1f} 0 0 0 {fmt(bow_pt(a_trail - tout))} "
        f"Q {fmt(polar(-half, R2))} {fmt(polar(-half, R2 - cout))} "
        f"L {fmt(polar(-half, R1 + cin))} "
        f"Q {fmt(polar(-half, R1))} {fmt(polar(-half + tin, R1))} Z"
    )

def build_svg(letter, geo=None):
    geo = geo or DEFAULT_GEO
    p = PALETTES[letter]
    i = geo["tag"]
    seam = ('#FFFFFF', 0.14) if p["dark_cards"] else ('#000000', 0.10)
    d = blade_d(geo["half"], geo["cin"], geo["cout"])
    blades = "".join(
        f'  <use href="#bl{i}" transform="rotate({k * 30})" fill="url(#fc{i})"'
        f' stroke="{seam[0]}" stroke-opacity="{seam[1]}" stroke-width="2" filter="url(#cs{i})"/>\n'
        for k in range(10, 0, -1)
    )
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<defs>
  <path id="bl{i}" d="{d}"/>
  <linearGradient id="fc{i}" x1="0" y1="1" x2="1" y2="0">
    <stop offset="0" stop-color="{p['face'][0]}"/>
    <stop offset="0.55" stop-color="{p['face'][1]}"/>
    <stop offset="1" stop-color="{p['face'][2]}"/>
  </linearGradient>
  <linearGradient id="ht{i}" x1="0" y1="1" x2="1" y2="0">
    <stop offset="0" stop-color="{p['hot'][0]}"/>
    <stop offset="1" stop-color="{p['hot'][1]}"/>
  </linearGradient>
  <linearGradient id="bg{i}" x1="0" y1="0" x2="0.6" y2="1">
    <stop offset="0" stop-color="{p['bg'][0]}"/>
    <stop offset="0.55" stop-color="{p['bg'][1]}"/>
    <stop offset="1" stop-color="{p['bg'][2]}"/>
  </linearGradient>
  <radialGradient id="sn{i}" cx="0.5" cy="0.05" r="0.9">
    <stop offset="0" stop-color="#FFFFFF" stop-opacity="{p['sheen']}"/>
    <stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
  </radialGradient>
  <filter id="cs{i}" x="-45%" y="-45%" width="190%" height="190%">
    <feDropShadow dx="0" dy="9" stdDeviation="9" flood-color="#000000" flood-opacity="{p['sh'][0]}"/>
    <feDropShadow dx="0" dy="24" stdDeviation="28" flood-color="#000000" flood-opacity="{p['sh'][1]}"/>
  </filter>
  <filter id="hm{i}" x="-60%" y="-60%" width="220%" height="220%">
    <feDropShadow dx="0" dy="11" stdDeviation="11" flood-color="#000000" flood-opacity="0.34"/>
    <feDropShadow dx="0" dy="0" stdDeviation="26" flood-color="#FFD9A0" flood-opacity="0.30"/>
  </filter>
</defs>

<rect x="{BODY[0]}" y="{BODY[1]}" width="{BODY[2]}" height="{BODY[3]}" rx="{BODY[4]}" fill="url(#bg{i})"/>
<rect x="{BODY[0]}" y="{BODY[1]}" width="{BODY[2]}" height="{BODY[3]}" rx="{BODY[4]}" fill="url(#sn{i})"/>
<rect x="{BODY[0] + 6}" y="{BODY[1] + 6}" width="{BODY[2] - 12}" height="{BODY[3] - 12}" rx="{BODY[4] - 5}"
      fill="none" stroke="{p['edge'][0]}" stroke-opacity="{p['edge'][1]}" stroke-width="3"/>

<g transform="translate(512 512)">
{blades}  <use href="#bl{i}" transform="translate(0 {-POP})" fill="url(#ht{i})" filter="url(#hm{i})"/>
</g>
</svg>
'''

def build_sheet():
    cells = []
    for n, (key, geo) in enumerate(GEOS.items()):
        x = 15 + n * 415
        inner = build_svg("E", geo)
        inner = inner[inner.index(">") + 1:inner.rindex("</svg>")]
        cells.append(
            f'<svg x="{x}" y="25" width="380" height="380" viewBox="0 0 1024 1024">{inner}</svg>\n'
            f'<text x="{x + 190}" y="449" text-anchor="middle" font-family="PingFang SC"'
            f' font-size="30" fill="#3A3A3A">{key} · {geo["label"]}</text>'
        )
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1260" height="490"'
            ' viewBox="0 0 1260 490">\n<rect width="1260" height="490" fill="#FFFFFF"/>\n'
            + "\n".join(cells) + "\n</svg>\n")

def main():
    os.makedirs(VARIANTS, exist_ok=True)
    for key, geo in GEOS.items():
        with open(os.path.join(VARIANTS, f"{key}-暖纸{geo['label']}.svg"), "w") as f:
            f.write(build_svg("E", geo))
    with open(os.path.join(VARIANTS, "sheet-e.svg"), "w") as f:
        f.write(build_sheet())
    print("wrote E1..E3 + sheet-e.svg")

    if len(sys.argv) > 1:
        arg = sys.argv[1]
        if arg not in GEOS:
            raise SystemExit(f"unknown option: {arg} (choose from {list(GEOS)})")
        with open(os.path.join(HERE, "logo.svg"), "w") as f:
            f.write(build_svg("E", GEOS[arg]))
        prev = os.path.join(HERE, "preview")
        os.makedirs(prev, exist_ok=True)
        for size in (1024, 128):
            subprocess.run(["qlmanage", "-t", "-s", str(size), "-o", prev,
                            os.path.join(HERE, "logo.svg")], capture_output=True)
            src = os.path.join(prev, "logo.svg.png")
            if os.path.exists(src):
                shutil.move(src, os.path.join(prev, f"logo-{size}.png"))
        print(f"promoted {arg} -> logo.svg + previews")

if __name__ == "__main__":
    main()
