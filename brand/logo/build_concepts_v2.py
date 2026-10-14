"""Round 3 Roam logo concepts: each as a mono symbol and a colour app-icon tile."""
import math
from pathlib import Path

OUT = Path(__file__).parent / "concepts-v3"
BLUE, NAVY, AMBER, SKY, WHITE, BLACK = "#3158D4", "#1a2340", "#F2B33D", "#CFE0F7", "#FFFFFF", "#000000"


def f(n):
    return f"{n:.2f}".rstrip("0").rstrip(".")


def svg(body, w=256, h=256):
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}">\n{body}\n</svg>\n'


def tile(bg, body):
    return svg(f'<rect width="256" height="256" rx="57" fill="{bg}"/>{body}')


def poly(pts):
    return "M" + " L".join(f"{f(x)},{f(y)}" for x, y in pts) + " Z"


def bezier(p0, p1, p2, p3, t):
    u = 1 - t
    return tuple(u**3 * a + 3 * u * u * t * b + 3 * u * t * t * c + t**3 * d for a, b, c, d in zip(p0, p1, p2, p3))


def tapered_ribbon(p0, p1, p2, p3, w0, w1, n=48):
    """Filled outline of a cubic centre-line whose width goes from w0 to w1."""
    left, right = [], []
    for i in range(n + 1):
        t = i / n
        a, b = bezier(p0, p1, p2, p3, max(t - 1e-3, 0)), bezier(p0, p1, p2, p3, min(t + 1e-3, 1))
        dx, dy = b[0] - a[0], b[1] - a[1]
        L = math.hypot(dx, dy)
        nx, ny = -dy / L, dx / L
        c = bezier(p0, p1, p2, p3, t)
        hw = (w0 + (w1 - w0) * t) / 2
        left.append((c[0] + nx * hw, c[1] + ny * hw))
        right.append((c[0] - nx * hw, c[1] - ny * hw))
    return left + right[::-1]


# --- A: Road-leg R — the R's leg opens into the road ahead ---

def lerp2(p, q, t):
    return (p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t)


def road_leg_r(fg, cut):
    stem_bowl = "M78,214 V92 A44,44 0 0 1 122,48 H140 A44,44 0 0 1 140,136 H118"
    tl, tr, bl, br = (104, 146), (140, 118), (160, 214), (230, 214)
    leg = [tl, tr, br, bl]
    dashes = []
    for t0, t1 in [(0.30, 0.46), (0.60, 0.80), (0.93, 1.0)]:
        quad = []
        for t, sign in [(t0, -1), (t1, -1), (t1, 1), (t0, 1)]:
            l, r = lerp2(tl, bl, t), lerp2(tr, br, t)
            half = 0.045 + 0.02 * t
            quad.append(lerp2(l, r, 0.5 + sign * half))
        dashes.append([quad[0], quad[1], quad[2], quad[3]])
    body = (f'<path d="{stem_bowl}" fill="none" stroke="{fg}" stroke-width="40" stroke-linejoin="round"/>'
            f'<circle cx="118" cy="136" r="20" fill="{fg}"/>'
            f'<path d="{poly(leg)}" fill="{fg}"/>')
    body += "".join(f'<path d="{poly(d)}" fill="{cut}"/>' for d in dashes)
    return f'<g transform="translate(-10,-3)">{body}</g>'


# --- B: Switchback — a mountain road climbing in perspective, the learning curve ---

def ribbon_along(pts, widths):
    left, right = [], []
    for i, (x, y) in enumerate(pts):
        a = pts[max(i - 1, 0)]; b = pts[min(i + 1, len(pts) - 1)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        L = math.hypot(dx, dy) or 1
        nx, ny = -dy / L, dx / L
        hw = widths[i] / 2
        left.append((x + nx * hw, y + ny * hw)); right.append((x - nx * hw, y - ny * hw))
    return left + right[::-1]


SWITCH_LEVELS = [(208, 58, 38), (160, 50, 28), (123, 40, 20), (96, 31, 14), (77, 23, 9)]
SWITCH_CX = 122


def switchback_centerline():
    pts, widths = [], []
    for i, (y0, a0, w0) in enumerate(SWITCH_LEVELS):
        s = 1 if i % 2 == 0 else -1
        x_start, x_end = SWITCH_CX - s * a0, SWITCH_CX + s * a0
        if i == len(SWITCH_LEVELS) - 1:
            x_end = SWITCH_CX + s * a0 * 0.4
        n = 30
        for k in range(n + 1):
            pts.append((x_start + (x_end - x_start) * k / n, y0)); widths.append(w0)
        if i == len(SWITCH_LEVELS) - 1:
            break
        y1, a1, w1 = SWITCH_LEVELS[i + 1]
        P, Q = (x_end, y0), (SWITCH_CX + s * a1, y1)
        k_ctrl = (y0 - y1) * 0.62
        c1, c2 = (P[0] + s * k_ctrl, P[1]), (Q[0] + s * k_ctrl, Q[1])
        m = 28
        for j in range(1, m):
            pts.append(bezier(P, c1, c2, Q, j / m)); widths.append(w0 + (w1 - w0) * j / m)
    return pts, widths


def switchback(fg, accent):
    pts, widths = switchback_centerline()
    end = pts[-1]
    return (f'<path d="{poly(ribbon_along(pts, widths))}" fill="{fg}" stroke="{fg}" stroke-width="0.6" stroke-linejoin="round"/>'
            f'<circle cx="{f(end[0] + 34)}" cy="{f(end[1] - 26)}" r="13" fill="{accent}"/>')


# --- C: Roundabout — a ring road from above, one exit taken ---

def roundabout(fg, accent, bg):
    ring_r, road_w = 58, 30
    stubs = ""
    for ang in (90, 345, 200):
        a = math.radians(ang)
        x0, y0 = 128 + math.cos(a) * ring_r, 128 + math.sin(a) * ring_r
        x1, y1 = 128 + math.cos(a) * 112, 128 + math.sin(a) * 112
        stubs += f'<line x1="{f(x0)}" y1="{f(y0)}" x2="{f(x1)}" y2="{f(y1)}" stroke="{fg}" stroke-width="{road_w}"/>'
    ring = f'<circle cx="128" cy="128" r="{ring_r}" fill="none" stroke="{fg}" stroke-width="{road_w}"/>'
    # Route: enter from the bottom, go round counter-clockwise, leave by the upper-right exit.
    a_in, a_out = math.radians(90), math.radians(-15)
    r = ring_r
    sx, sy = 128, 128 + 106
    p1 = (128 + math.cos(a_in) * r, 128 + math.sin(a_in) * r)
    p2 = (128 + math.cos(a_out) * r, 128 + math.sin(a_out) * r)
    ex, ey = 128 + math.cos(a_out) * 104, 128 + math.sin(a_out) * 104
    route = (f'<path d="M{f(sx)},{f(sy)} L{f(p1[0])},{f(p1[1])} A{r},{r} 0 0 0 {f(p2[0])},{f(p2[1])} '
             f'L{f(ex)},{f(ey)}" fill="none" stroke="{accent}" stroke-width="10" stroke-linecap="round" stroke-linejoin="round"/>')
    dx, dy = math.cos(a_out), math.sin(a_out)
    tip = (ex + dx * 16, ey + dy * 16)
    nxp, nyp = -dy, dx
    head = [tip, (ex + nxp * 13, ey + nyp * 13), (ex - nxp * 13, ey - nyp * 13)]
    return (f'<circle cx="128" cy="128" r="{ring_r - road_w / 2 + 1}" fill="{bg}"/>' + stubs + ring + route
            + f'<path d="{poly(head)}" fill="{accent}" stroke="{accent}" stroke-width="4" stroke-linejoin="round"/>')


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    files = {
        "a-symbol.svg": svg(road_leg_r(BLACK, WHITE)),
        "a-tile.svg": tile(BLUE, road_leg_r(WHITE, BLUE)),
        "b-symbol.svg": svg(switchback(BLACK, BLACK)),
        "b-tile.svg": tile(BLUE, switchback(WHITE, AMBER)),
        "c-symbol.svg": svg(roundabout(BLACK, BLACK, WHITE)),
        "c-tile.svg": tile(NAVY, roundabout(WHITE, AMBER, NAVY)),
    }
    for name, body in files.items():
        (OUT / name).write_text(body)


if __name__ == "__main__":
    main()
