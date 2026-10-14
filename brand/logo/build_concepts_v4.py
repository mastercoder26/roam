"""Round 4 Roam logo concepts: chunky solid marks with a rounded wordmark."""
import math
from pathlib import Path

OUT = Path(__file__).parent / "concepts-v4"
INK, PAPER = "#000", "#fff"


def f(n):
    return f"{n:.2f}".rstrip("0").rstrip(".")


def svg(body, w=256, h=256):
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}">\n{body}\n</svg>\n'


def poly(pts):
    return "M" + " L".join(f"{f(x)},{f(y)}" for x, y in pts) + " Z"


# --- Wordmark: chunky rounded lowercase "roam", x-height 100, baseline y=0 ---

WM_SW = 30
WM_W, WM_H = 452, 100


def wordmark():
    s = f'fill="none" stroke="{INK}" stroke-width="{WM_SW}" stroke-linecap="round" stroke-linejoin="round"'
    h = WM_SW / 2
    r = f'<path {s} d="M{h},{-h} V-50 A35,35 0 0 1 50,-85 H56"/>'
    o = f'<circle {s} cx="128" cy="-50" r="{50 - h}"/>'
    a = f'<circle {s} cx="238" cy="-50" r="{50 - h}"/><path {s} d="M273,-85 V{-h}"/>'
    m = (f'<path {s} d="M{318 + h},{-h} V-85 M{318 + h},-58 A27,27 0 0 1 {387},-58 V{-h} '
         f'M387,-58 A27,27 0 0 1 {437},-58 V{-h}"/>')
    return r + o + a + m


def lockup(symbol_body):
    scale = 1.22
    x = 256 + 36
    baseline = 128 + WM_H * scale / 2 + 4
    w = x + WM_W * scale + 10
    group = f'<g transform="translate({f(x)},{f(baseline)}) scale({scale})">{wordmark()}</g>'
    return svg(symbol_body + group, math.ceil(w), 256)


# --- A: Blinker r — the arm of the r is a turn signal ---

def blinker_r():
    arm = "M92,208 V124 A46,46 0 0 1 138,78 H150"
    head = poly([(146, 34), (216, 78), (146, 122)])
    return (f'<path d="{arm}" fill="none" stroke="{INK}" stroke-width="60" stroke-linecap="round" stroke-linejoin="round"/>'
            f'<path d="{head}" fill="{INK}" stroke="{INK}" stroke-width="18" stroke-linejoin="round"/>')


# --- B: Beep — a car-front mascot that winks and grins ---

def beep():
    cabin = "M76,120 V96 A36,36 0 0 1 112,60 H144 A36,36 0 0 1 180,96 V120 Z"
    body = f'<rect x="34" y="108" width="188" height="88" rx="40" fill="{INK}"/>'
    wheels = (f'<rect x="54" y="170" width="40" height="46" rx="14" fill="{INK}"/>'
              f'<rect x="162" y="170" width="40" height="46" rx="14" fill="{INK}"/>')
    windshield = f'<path d="M96,112 V100 A18,18 0 0 1 114,82 H142 A18,18 0 0 1 160,100 V112 Z" fill="{PAPER}"/>'
    eye = f'<circle cx="82" cy="142" r="15" fill="{PAPER}"/>'
    wink = f'<path d="M160,146 Q174,130 188,146" fill="none" stroke="{PAPER}" stroke-width="14" stroke-linecap="round"/>'
    grin = f'<path d="M100,158 Q128,190 156,158 Z" fill="{PAPER}" stroke="{PAPER}" stroke-width="8" stroke-linejoin="round"/>'
    return wheels + f'<path d="{cabin}" fill="{INK}"/>' + body + windshield + eye + wink + grin


# --- C: Key R — bowl is the key head (counter = ring hole), leg is the toothed blade ---

def key_blade():
    L, hw = 104, 24
    pts = [(0, -hw), (L - 14, -hw), (L, -hw + 14), (L, hw)]
    notches = [(76, 12), (52, 20), (28, 12)]
    for x0, depth in notches:
        pts += [(x0 + 12, hw), (x0 + 12, hw - depth), (x0, hw - depth), (x0, hw)]
    pts += [(0, hw)]
    return poly(pts)


def key_r():
    stem = f'<rect x="50" y="34" width="50" height="190" rx="10" fill="{INK}"/>'
    bowl = (f'<path d="M60,34 H136 A64,64 0 0 1 136,162 H60 Z '
            f'M138,74 A24,24 0 1 0 138,122 A24,24 0 1 0 138,74 Z" fill="{INK}" fill-rule="evenodd"/>')
    blade = f'<g transform="translate(116,146) rotate(45)"><path d="{key_blade()}" fill="{INK}"/></g>'
    return f'<g transform="translate(4,-2)">{stem}{bowl}{blade}</g>'


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    marks = {"a": blinker_r(), "b": beep(), "c": key_r()}
    for k, body in marks.items():
        (OUT / f"{k}-symbol.svg").write_text(svg(body))
        (OUT / f"{k}-lockup.svg").write_text(lockup(body))
    (OUT / "wordmark.svg").write_text(svg(f'<g transform="translate(20,178) scale(1.6)">{wordmark()}</g>', 764, 256))


if __name__ == "__main__":
    main()
