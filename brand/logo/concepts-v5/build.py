#!/usr/bin/env python3
"""Roam logo concepts, round 5. Black geometry only. Letters are constructed, not set in a font."""

import math
import os
import re

OUT = os.path.dirname(os.path.abspath(__file__))


def fmt(n):
    s = f"{n:.2f}"
    if "." in s:
        s = s.rstrip("0").rstrip(".")
    return s if s not in ("", "-") else "0"


def svg_doc(body, w, h, title):
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {fmt(w)} {fmt(h)}" '
        f'width="{fmt(w)}" height="{fmt(h)}" role="img" aria-labelledby="title">\n'
        f'  <title id="title">{title}</title>\n'
        f'  {body}\n'
        f'</svg>\n'
    )


def compound(parts, fill="#000"):
    return f'<path fill="{fill}" fill-rule="evenodd" d="{" ".join(parts)}"/>'


def circle(cx, cy, r, sweep=1):
    return (
        f"M{fmt(cx - r)},{fmt(cy)} "
        f"A{fmt(r)},{fmt(r)} 0 1 {sweep} {fmt(cx + r)},{fmt(cy)} "
        f"A{fmt(r)},{fmt(r)} 0 1 {sweep} {fmt(cx - r)},{fmt(cy)} Z"
    )


def ring(cx, cy, ro, ri):
    return circle(cx, cy, ro, 1) + " " + circle(cx, cy, ri, 0)


def rect(x, y, w, h):
    return f"M{fmt(x)},{fmt(y)} H{fmt(x + w)} V{fmt(y + h)} H{fmt(x)} Z"


def rounded_rect(x, y, w, h, rx):
    rx = min(rx, w / 2, h / 2)
    return (
        f"M{fmt(x + rx)},{fmt(y)} H{fmt(x + w - rx)} "
        f"A{fmt(rx)},{fmt(rx)} 0 0 1 {fmt(x + w)},{fmt(y + rx)} "
        f"V{fmt(y + h - rx)} A{fmt(rx)},{fmt(rx)} 0 0 1 {fmt(x + w - rx)},{fmt(y + h)} "
        f"H{fmt(x + rx)} A{fmt(rx)},{fmt(rx)} 0 0 1 {fmt(x)},{fmt(y + h - rx)} "
        f"V{fmt(y + rx)} A{fmt(rx)},{fmt(rx)} 0 0 1 {fmt(x + rx)},{fmt(y)} Z"
    )


def write(name, text):
    path = os.path.join(OUT, name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)
    return path


# Local coordinates: y grows down. Stems sit on y=0..H. Rounds overshoot.
H = 100.0
S = 31.0
OVER = 4.0


def letter_r():
    """Geometric r: full stem, arm as thick as the stem, round terminal."""
    arm = 36.0
    rad = S / 2
    right = S + arm
    d = (
        f"M0,{fmt(H)} V0 H{fmt(right - rad)} "
        f"A{fmt(rad)},{fmt(rad)} 0 0 1 {fmt(right - rad)},{fmt(S)} "
        f"H{fmt(S)} V{fmt(H)} Z"
    )
    return [d], right


def letter_o():
    ro = H / 2 + OVER
    ri = ro - S
    return [ring(ro, H / 2, ro, ri)], ro * 2


def letter_a():
    """Single-story a. Ring and stem are separate paths so they union instead of punching a hole."""
    ro = H / 2 + OVER
    ri = ro - S
    width = ro * 2
    # Stem kisses the counter; it repaints the right wall of the ring.
    return [ring(ro, H / 2, ro, ri), rect(width - S, 0, S, H)], width


def letter_m():
    """Three stems, two circular arches. Each piece is its own path so overlaps stay solid."""
    ri = 15.0
    ro = ri + S
    pitch = S + 2 * ri
    cy = ro
    parts = []
    for i in range(2):
        cx = ro + i * pitch
        # Sweep 1 travels through the top of the circle (smaller y).
        parts.append(
            f"M{fmt(cx - ro)},{fmt(cy)} "
            f"A{fmt(ro)},{fmt(ro)} 0 0 1 {fmt(cx + ro)},{fmt(cy)} "
            f"L{fmt(cx + ri)},{fmt(cy)} "
            f"A{fmt(ri)},{fmt(ri)} 0 0 0 {fmt(cx - ri)},{fmt(cy)} Z"
        )
        parts.append(rect(cx - ro, cy, S, H - cy))
        parts.append(rect(cx + ri, cy, S, H - cy))
    # Second arch center is ro+pitch; its right edge is that plus ro.
    return parts, 2 * ro + pitch


def translate_path(d, dx, dy):
    tokens = re.findall(r"[MmHhVvAaLlZz]|[-+]?(?:\d*\.\d+|\d+)(?:[eE][-+]?\d+)?", d)
    out = []
    i = 0
    cmd = None
    while i < len(tokens):
        t = tokens[i]
        if t.isalpha():
            cmd = t
            out.append(t)
            i += 1
            continue
        if cmd in ("M", "L"):
            x = float(t) + dx
            y = float(tokens[i + 1]) + dy
            out.append(f"{fmt(x)},{fmt(y)}")
            i += 2
        elif cmd == "H":
            out.append(fmt(float(t) + dx))
            i += 1
        elif cmd == "V":
            out.append(fmt(float(t) + dy))
            i += 1
        elif cmd == "A":
            rx, ry, rot, large, sweep = tokens[i:i + 5]
            x = float(tokens[i + 5]) + dx
            y = float(tokens[i + 6]) + dy
            out.append(f"{rx},{ry} {rot} {large} {sweep} {fmt(x)},{fmt(y)}")
            i += 7
        else:
            out.append(t)
            i += 1
    return " ".join(out)


def emit_paths(paths, dx=0.0, dy=0.0):
    moved = [translate_path(p, dx, dy) for p in paths]
    return "\n    ".join(f'<path fill="#000" fill-rule="evenodd" d="{p}"/>' for p in moved)


def word_group(notches=False):
    """Plain roam, or the same drawing with a lane cut through every stem."""
    gaps = [14.0, 10.0, 16.0]
    y0, nh = 60.0, 16.0
    chunks = []
    x = 0.0

    r_paths, r_w = letter_r()
    if notches:
        r_paths = r_paths + [rect(-0.2, y0, S + 0.4, nh)]
    chunks.append(emit_paths(r_paths, x, 0))
    x += r_w + gaps[0]

    o_paths, o_w = letter_o()
    chunks.append(emit_paths(o_paths, x, 0))
    x += o_w + gaps[1]

    a_paths, a_w = letter_a()
    if notches:
        ring_d = a_paths[0] + " " + rect(a_w - S, y0, S, nh)
        top = rect(a_w - S, 0, S, y0)
        bot = rect(a_w - S, y0 + nh, S, H - (y0 + nh))
        a_paths = [ring_d, top, bot]
    chunks.append(emit_paths(a_paths, x, 0))
    x += a_w + gaps[2]

    m_paths, m_w = letter_m()
    if notches:
        ri = 15.0
        ro = ri + S
        pitch = S + 2 * ri
        cy = ro
        arches = [p for p in m_paths if "A" in p]
        stems = []
        for k in range(3):
            sx = k * pitch
            stems.append(rect(sx, cy, S, max(0.0, y0 - cy)))
            stems.append(rect(sx, y0 + nh, S, H - (y0 + nh)))
        m_paths = arches + stems
    chunks.append(emit_paths(m_paths, x, 0))
    x += m_w
    return "\n    ".join(chunks), x


def roundabout(travel_deg=-36.0):
    """R whose bowl is a roundabout and whose leg is a blunt exit ramp.

    Stem, ring, and ramp are separate filled paths so overlaps stay solid.
    The ramp never enters the island.
    """
    left, stem_w = 36.0, 62.0
    baseline = 222.0
    ro, ri = 74.0, 30.0
    cx, cy = 130.0, 108.0
    stem_top = cy - ro + 8.0  # flat cap sits below the round overshoot
    stem = f'<path fill="#000" d="{rect(left, stem_top, stem_w, baseline - stem_top)}"/>'
    # Island sits a little right of center so the junction wall is thicker.
    bowl = (
        f'<path fill="#000" fill-rule="evenodd" d="{circle(cx, cy, ro, 1)} '
        f'{circle(cx + 5, cy - 1, ri, 0)}"/>'
    )
    # Travel direction in SVG, measured below the horizontal.
    ang = math.radians(travel_deg)  # negative = downward
    dx, dy = math.cos(ang), -math.sin(ang)
    # Perpendicular to the right of travel, so the ramp's mass sits outside the island.
    px, py = -dy, dx
    # A bar centered on a ray that starts in the ring and leaves down-right.
    # Half the bar stays in the black of the bowl, so the join is a solid mass.
    start_ang = math.radians(-52.0)
    r0 = ri + 34.0
    sx = cx + r0 * math.cos(start_ang)
    sy = cy - r0 * math.sin(start_ang)
    leg_w = 54.0
    hw = leg_w / 2.0
    length = 24.0
    for _ in range(90):
        far = (sx + dx * length, sy + dy * length)
        corners = [
            (far[0] - px * hw, far[1] - py * hw),
            (far[0] + px * hw, far[1] + py * hw),
        ]
        if max(p[1] for p in corners) >= baseline or max(p[0] for p in corners) >= 230:
            break
        length += 2.0
    c0 = (sx, sy)
    c1 = (sx + dx * length, sy + dy * length)
    quad = [
        (c0[0] - px * hw, c0[1] - py * hw),
        (c1[0] - px * hw, c1[1] - py * hw),
        (c1[0] + px * hw, c1[1] + py * hw),
        (c0[0] + px * hw, c0[1] + py * hw),
    ]
    ramp_d = "M" + " L".join(f"{fmt(x)},{fmt(y)}" for x, y in quad) + " Z"
    ramp = f'<path fill="#000" d="{ramp_d}"/>'
    return "\n  ".join([stem, bowl, ramp])


def block_loop(gap=62.0, stroke=54.0, outer=200.0, radius=52.0, origin=28.0):
    """City-block loop. The gap rect stops at the outer edge so it doesn't grow a tab."""
    inner = outer - 2 * stroke
    inner_r = max(10.0, radius - stroke)
    ix = origin + stroke
    iy = origin + stroke
    gap_x = origin + (outer - gap) / 2
    # Cover only the bottom ring: from the inner edge to the outer edge, no further.
    gap_path = rect(gap_x, iy + inner, gap, stroke)
    return compound([
        rounded_rect(origin, origin, outer, outer, radius),
        rounded_rect(ix, iy, inner, inner, inner_r),
        gap_path,
    ])


def merge_mark():
    """Two lanes become one."""
    s = 58.0
    cx = 128.0
    join_y = 122.0
    stem = rounded_rect(cx - s / 2, join_y - 8, s, 108, 16)
    ang = math.radians(32)
    length = 112.0
    ux, uy = math.sin(ang), -math.cos(ang)

    def arm_path(sign):
        x0, y0 = cx, join_y
        x1 = x0 + sign * ux * length
        y1 = y0 + uy * length
        nx, ny = -uy * sign, ux * sign
        hw = s / 2
        pts = [
            (x0 + nx * hw, y0 + ny * hw),
            (x1 + nx * hw, y1 + ny * hw),
            (x1 - nx * hw, y1 - ny * hw),
            (x0 - nx * hw, y0 - ny * hw),
        ]
        poly = "M" + " L".join(f"{fmt(x)},{fmt(y)}" for x, y in pts) + " Z"
        return poly + " " + circle(x1, y1, hw, 1)

    return compound([stem, arm_path(1), arm_path(-1), circle(cx, join_y, s * 0.58, 1)])


def hill_mark():
    """One thick arch: the crest you can see over before you arrive."""
    ro, ri = 92.0, 46.0
    cx, cy = 128.0, 176.0
    arch = (
        f"M{fmt(cx - ro)},{fmt(cy)} "
        f"A{fmt(ro)},{fmt(ro)} 0 0 0 {fmt(cx + ro)},{fmt(cy)} "
        f"L{fmt(cx + ri)},{fmt(cy)} "
        f"A{fmt(ri)},{fmt(ri)} 0 0 1 {fmt(cx - ri)},{fmt(cy)} Z"
    )
    foot = ro - ri
    return compound([
        arch,
        rect(cx - ro, cy - 1, foot, 26),
        rect(cx + ri, cy - 1, foot, 26),
    ])


def turn_r():
    """The wordmark's r, scaled to fill an icon tile. No extra cut."""
    paths, w = letter_r()
    pad_y = 32.0
    scale = (256 - 2 * pad_y) / H
    ox = (256 - w * scale) / 2
    oy = pad_y - OVER * scale
    body = emit_paths(paths)
    return f'<g transform="translate({fmt(ox)},{fmt(oy)}) scale({fmt(scale)})">{body}</g>'


def split_o():
    """Two thick arcs. The lane between them is the road; together they are an o."""
    ro, stroke, gap = 96.0, 48.0, 32.0
    ri = ro - stroke
    cx = cy = 128.0
    half = gap / 2.0

    def lens(sign):
        # sign +1 is the top arc (smaller y). Cut where the band meets each circle.
        ao = math.asin(min(1.0, half / ro))
        ai = math.asin(min(1.0, half / ri))
        # Top: from angle ao to pi-ao through +pi/2. Bottom: through -pi/2.
        if sign > 0:
            a0, a1 = math.pi - ao, ao
            b0, b1 = math.pi - ai, ai
            sweep_o, sweep_i = 0, 1
        else:
            a0, a1 = ao, -ao  # unused; handled below
            b0, b1 = ai, -ai
            sweep_o, sweep_i = 1, 0
        if sign > 0:
            o0 = (cx + ro * math.cos(a0), cy - ro * math.sin(a0))
            o1 = (cx + ro * math.cos(a1), cy - ro * math.sin(a1))
            i1 = (cx + ri * math.cos(b1), cy - ri * math.sin(b1))
            i0 = (cx + ri * math.cos(b0), cy - ri * math.sin(b0))
        else:
            o0 = (cx + ro * math.cos(ao), cy + ro * math.sin(ao))
            o1 = (cx - ro * math.cos(ao), cy + ro * math.sin(ao))
            i1 = (cx - ri * math.cos(ai), cy + ri * math.sin(ai))
            i0 = (cx + ri * math.cos(ai), cy + ri * math.sin(ai))
            sweep_o, sweep_i = 0, 1
        return (
            f"M{fmt(o0[0])},{fmt(o0[1])} "
            f"A{fmt(ro)},{fmt(ro)} 0 0 {sweep_o} {fmt(o1[0])},{fmt(o1[1])} "
            f"L{fmt(i1[0])},{fmt(i1[1])} "
            f"A{fmt(ri)},{fmt(ri)} 0 0 {sweep_i} {fmt(i0[0])},{fmt(i0[1])} Z"
        )

    return "\n  ".join([
        f'<path fill="#000" d="{lens(1)}"/>',
        f'<path fill="#000" d="{lens(-1)}"/>',
    ])


def main():
    variants = {
        "variants/r-36.svg": symbol_svg(roundabout(-36), "Roundabout 36"),
        "variants/r-28.svg": symbol_svg(roundabout(-28), "Roundabout 28"),
        "variants/r-44.svg": symbol_svg(roundabout(-44), "Roundabout 44"),
        "variants/block.svg": symbol_svg(block_loop(), "Block"),
        "variants/block-wide.svg": symbol_svg(block_loop(gap=78, stroke=58, radius=46), "Block wide"),
        "variants/turn-r.svg": symbol_svg(turn_r(), "Turn r"),
        "variants/split-o.svg": symbol_svg(split_o(), "Split o"),
    }
    word, advance = word_group(False)
    variants["variants/word.svg"] = svg_doc(
        f'<g transform="translate(24,48) scale(1.45)">{word}</g>',
        int(advance * 1.45) + 48,
        250,
        "roam wordmark",
    )
    lane, lane_adv = word_group(True)
    variants["variants/word-lane.svg"] = svg_doc(
        f'<g transform="translate(24,48) scale(1.45)">{lane}</g>',
        int(lane_adv * 1.45) + 48,
        250,
        "roam centerline",
    )
    for name, text in variants.items():
        write(name, text)

    # Checkpoint artwork. A is the roundabout, B the block, C the centerline word.
    a_sym = f'<g transform="translate(-5,1)">{roundabout(-50)}</g>'
    b_sym = block_loop()
    c_sym = turn_r()
    write("a-symbol.svg", symbol_svg(a_sym, "Roam roundabout"))
    write("b-symbol.svg", symbol_svg(b_sym, "Roam curb"))
    write("c-symbol.svg", symbol_svg(c_sym, "Roam wordmark"))
    write("a-lockup.svg", lockup(a_sym, False, "Roam roundabout lockup"))
    write("b-lockup.svg", lockup(b_sym, False, "Roam curb lockup"))
    write("c-lockup.svg", lockup(c_sym, False, "Roam wordmark lockup"))
    print("wrote finals")


def lockup(symbol_inner, notches, title):
    word, advance = word_group(notches)
    target_h = 128.0
    ws = target_h / H
    word_w = advance * ws
    sym = 188.0
    gap = 36.0
    height = 256.0
    pad = 8.0
    width = math.ceil(pad + sym + gap + word_w + pad)
    sym_y = (height - sym) / 2
    word_y = (height - target_h) / 2 - OVER * ws * 0.15
    body = (
        f'<g transform="translate({fmt(pad)},{fmt(sym_y)}) scale({fmt(sym / 256)})">{symbol_inner}</g>\n'
        f'  <g transform="translate({fmt(pad + sym + gap)},{fmt(word_y)}) scale({fmt(ws)})">{word}</g>'
    )
    return svg_doc(body, width, height, title)


def symbol_svg(inner, title):
    return svg_doc(inner, 256, 256, title)


if __name__ == "__main__":
    main()
