"""Generate the three Roam logo concepts as black-on-white SVGs."""
import math
from pathlib import Path

OUT = Path(__file__).parent / "concepts"
INK = "#000"
WM_STROKE = 18


def svg(w, h, body):
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}">\n{body}\n</svg>\n'


def f(n):
    return f"{n:.2f}".rstrip("0").rstrip(".")


# --- Wordmark: monoline geometric lowercase "roam", x-height 100, baseline y=0 ---

def wordmark(o_style="plain"):
    s = f'fill="none" stroke="{INK}" stroke-width="{WM_STROKE}"'
    r = f'<path {s} d="M9,0 V-100 M9,-50 A41,41 0 0 1 50,-91" stroke-linecap="butt"/>'
    r_cap = f'<circle cx="50" cy="-91" r="9" fill="{INK}"/>'
    if o_style == "puck":
        o = (f'<circle cx="123" cy="-50" r="41" {s}/>'
             f'<circle cx="123" cy="-50" r="17" fill="{INK}"/>')
    else:
        o = f'<circle cx="123" cy="-50" r="41" {s}/>'
    a = f'<circle cx="249" cy="-50" r="41" {s}/><path {s} d="M290,-100 V0"/>'
    m = (f'<path {s} d="M336,0 V-100 M336,-59 A32,32 0 0 1 400,-59 V0 '
         f'M400,-59 A32,32 0 0 1 464,-59 V0"/>')
    return r + r_cap + o + a + m


WM_W, WM_H = 473, 100


def wordmark_group(x, baseline, scale, o_style="plain"):
    return f'<g transform="translate({f(x)},{f(baseline)}) scale({f(scale)})">{wordmark(o_style)}</g>'


# --- A: Route R — one continuous drive from an origin dot to the finish ---

def route_r():
    d = "M88,199 V83 A46,46 0 0 1 134,37 H146 A46,46 0 0 1 146,129 H126 L190,193"
    return (f'<path d="{d}" fill="none" stroke="{INK}" stroke-width="30" '
            f'stroke-linecap="round" stroke-linejoin="round"/>'
            f'<circle cx="88" cy="199" r="24" fill="{INK}"/>')


# --- B: Road Check — a check whose long arm recedes like a road, centre-line cut out ---

def lerp(a, b, t):
    return a + (b - a) * t


def offset_pt(p, n, d):
    return (p[0] + n[0] * d, p[1] + n[1] * d)


def unit_normal(a, b):
    dx, dy = b[0] - a[0], b[1] - a[1]
    L = math.hypot(dx, dy)
    return (-dy / L, dx / L)


def line_intersect(p1, p2, p3, p4):
    x1, y1 = p1; x2, y2 = p2; x3, y3 = p3; x4, y4 = p4
    den = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4)
    t = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / den
    return (x1 + t * (x2 - x1), y1 + t * (y2 - y1))


def poly(pts):
    return "M" + " L".join(f"{f(x)},{f(y)}" for x, y in pts) + " Z"


def road_check():
    p0, p1, p2 = (46, 116), (100, 170), (222, 50)
    h0, h2 = 28, 9
    n1 = unit_normal(p0, p1)
    n2 = unit_normal(p1, p2)
    a_top0, a_top1 = offset_pt(p0, n1, h0), offset_pt(p1, n1, h0)
    a_bot0, a_bot1 = offset_pt(p0, n1, -h0), offset_pt(p1, n1, -h0)
    b_top1, b_top2 = offset_pt(p1, n2, h0), offset_pt(p2, n2, h2)
    b_bot1, b_bot2 = offset_pt(p1, n2, -h0), offset_pt(p2, n2, -h2)
    inner = line_intersect(a_top0, a_top1, b_top1, b_top2)
    outer = line_intersect(a_bot0, a_bot1, b_bot1, b_bot2)
    outline = [a_top0, inner, b_top2, b_bot2, outer, a_bot0]

    holes = []
    # Dashes shrink with the road's taper so they read as perspective.
    for t0, t1 in [(0.16, 0.34), (0.46, 0.60), (0.70, 0.79)]:
        c0 = (lerp(p1[0], p2[0], t0), lerp(p1[1], p2[1], t0))
        c1 = (lerp(p1[0], p2[0], t1), lerp(p1[1], p2[1], t1))
        w0, w1 = lerp(h0, h2, t0) * 0.2, lerp(h0, h2, t1) * 0.2
        holes.append([offset_pt(c0, n2, w0), offset_pt(c1, n2, w1),
                      offset_pt(c1, n2, -w1), offset_pt(c0, n2, -w0)])
    d = poly(outline) + " " + " ".join(poly(h) for h in holes)
    return f'<path d="{d}" fill="{INK}" fill-rule="evenodd"/>'


# --- C: Puck o — the wordmark's o is a live-location puck ---

def puck_symbol():
    return (f'<circle cx="128" cy="128" r="82" fill="none" stroke="{INK}" stroke-width="36"/>'
            f'<circle cx="128" cy="128" r="34" fill="{INK}"/>')


def lockup(symbol_body, o_style="plain"):
    scale = 1.25
    x = 256 + 44
    baseline = 128 + WM_H * scale / 2
    w = x + WM_W * scale + 8
    return svg(math.ceil(w), 256, symbol_body + wordmark_group(x, baseline, scale, o_style))


def wordmark_only(o_style):
    scale = 2.0
    pad = 20
    w = WM_W * scale + pad * 2
    return svg(math.ceil(w), 256, wordmark_group(pad, 128 + WM_H * scale / 2, scale, o_style))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    files = {
        "a-symbol.svg": svg(256, 256, route_r()),
        "a-lockup.svg": lockup(route_r()),
        "b-symbol.svg": svg(256, 256, road_check()),
        "b-lockup.svg": lockup(road_check()),
        "c-symbol.svg": svg(256, 256, puck_symbol()),
        "c-lockup.svg": wordmark_only("puck"),
    }
    for name, body in files.items():
        (OUT / name).write_text(body)
    print("\n".join(str(OUT / n) for n in files))


if __name__ == "__main__":
    main()
