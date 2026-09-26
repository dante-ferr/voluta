#!/usr/bin/env python3
"""Generate waybar plate ornaments: cairo draw → contour → SVG.

Not part of the runtime bar. Incised marks (volute, corbel, mascaron)
are contour-only so they read on the #0A0A0E plates. The mpris mark is a
single quaver, drawn directly so it stays legible at bar size. The patera
is filled stone: it sits in the gap between the two right-hand plates.
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

import cairo
import numpy as np
from PIL import Image
from PIL import ImageFilter

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"

PAD = 14
PLATE_STROKE = "#C4C4D0"
INC_STROKE = 11
FILL_STROKE = 10
SCALE = 6


def circle(ctx, x, y, r):
    ctx.arc(x, y, r, 0, 2 * math.pi)
    ctx.fill()


def ellipse(ctx, x, y, rx, ry, deg=0):
    ctx.save()
    ctx.translate(x, y)
    ctx.rotate(math.radians(deg))
    ctx.scale(rx, ry)
    ctx.arc(0, 0, 1, 0, 2 * math.pi)
    ctx.restore()
    ctx.fill()


def capsule(ctx, x1, y1, x2, y2, radius):
    ctx.save()
    ctx.set_line_width(radius * 2)
    ctx.set_line_cap(cairo.LINE_CAP_ROUND)
    ctx.set_line_join(cairo.LINE_JOIN_ROUND)
    ctx.move_to(x1, y1)
    ctx.line_to(x2, y2)
    ctx.stroke()
    ctx.restore()


def rasterize(draw_fn, w, h):
    img_w, img_h = w * SCALE, h * SCALE
    surface = cairo.ImageSurface(cairo.FORMAT_A8, img_w, img_h)
    ctx = cairo.Context(surface)
    ctx.set_antialias(cairo.ANTIALIAS_DEFAULT)
    ctx.scale(SCALE, SCALE)
    ctx.set_source_rgb(0, 0, 0)
    draw_fn(ctx)
    buf = np.frombuffer(surface.get_data(), dtype=np.uint8)
    stride = surface.get_stride()
    alpha = np.ndarray((img_h, stride), buffer=buf, dtype=np.uint8)[:, :img_w]
    mask = (alpha > 48).astype(np.uint8)
    im = Image.fromarray(mask * 255)
    im = im.filter(ImageFilter.MaxFilter(5))
    im = im.filter(ImageFilter.MinFilter(5))
    return (np.array(im) > 0).astype(np.uint8)


def trace_contour(mask):
    img = np.pad(mask, 1, mode="constant")
    pos = np.argwhere(img)
    sy, sx = int(pos[0][0]), int(pos[0][1])
    nb = [(-1, -1), (-1, 0), (-1, 1), (0, 1), (1, 1), (1, 0), (1, -1), (0, -1)]
    start = (sy, sx)
    current = start
    back = (sy, sx - 1)
    pts = []
    second = None
    for _ in range(int(mask.sum()) * 2):
        pts.append((current[1] - 1, current[0] - 1))
        bvec = (back[0] - current[0], back[1] - current[1])
        try:
            idx = nb.index(bvec)
        except ValueError:
            idx = 7
        nxt = None
        new_back = back
        for k in range(1, 9):
            dy, dx = nb[(idx + k) % 8]
            ny, nx = current[0] + dy, current[1] + dx
            if img[ny, nx]:
                nxt = (ny, nx)
                pdy, pdx = nb[(idx + k - 1) % 8]
                new_back = (current[0] + pdy, current[1] + pdx)
                break
        if nxt is None:
            break
        if second is None:
            second = nxt
        elif current == start and nxt == second and len(pts) > 8:
            break
        back = new_back
        current = nxt
    return pts


def rdp(points, epsilon):
    if len(points) < 3:
        return points
    ax, ay = points[0]
    bx, by = points[-1]
    dx, dy = bx - ax, by - ay
    denom = math.hypot(dx, dy) or 1.0
    max_d = -1.0
    idx = 0
    for i in range(1, len(points) - 1):
        px, py = points[i]
        d = abs(dy * px - dx * py + bx * ay - by * ax) / denom
        if d > max_d:
            max_d = d
            idx = i
    if max_d > epsilon:
        left = rdp(points[: idx + 1], epsilon)
        right = rdp(points[idx:], epsilon)
        return left[:-1] + right
    return [points[0], points[-1]]


def path_d(points):
    parts = [f"M{points[0][0]:.2f},{points[0][1]:.2f}"]
    for x, y in points[1:]:
        parts.append(f"{x:.2f},{y:.2f}")
    parts.append("Z")
    return " ".join(parts)


def close_loop(pts):
    if len(pts) > 2:
        x0, y0 = pts[0]
        x1, y1 = pts[-1]
        if math.hypot(x1 - x0, y1 - y0) < 1.0:
            pts = pts[:-1]
    return rdp(pts, epsilon=0.45)


def contour_of(draw_fn, w, h):
    mask = rasterize(draw_fn, w, h)
    pts = close_loop([(x / SCALE, y / SCALE) for x, y in trace_contour(mask)])
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    minx, miny = min(xs), min(ys)
    body = path_d([(x - minx, y - miny) for x, y in pts])
    return body, max(xs) - minx, max(ys) - miny


def svg_incised(body, cw, ch, note, extra="", mirror=False):
    xf = f' transform="translate({cw:.2f} 0) scale(-1 1)"' if mirror else ""
    vb_w, vb_h = cw + PAD * 2, ch + PAD * 2
    extra_xml = f"\n    {extra}" if extra else ""
    inner = f"""  <g fill="none" stroke="{PLATE_STROKE}" stroke-width="{INC_STROKE}" stroke-linejoin="round" stroke-linecap="round"{xf}>
    <path d="{body}"/>{extra_xml}
  </g>"""
    return (
        f"<!-- Imperium waybar - {note}. Incised contour on the plate. -->\n"
        f'<svg xmlns="http://www.w3.org/2000/svg" '
        f'viewBox="{-PAD} {-PAD} {vb_w:.2f} {vb_h:.2f}" width="{vb_w:.0f}" height="{vb_h:.0f}">\n'
        f"{inner}\n"
        f"</svg>\n"
    )


def svg_filled(body, hole, cw, ch, note):
    vb_w, vb_h = cw + PAD * 2, ch + PAD * 2
    paths = f'      <path d="{body}"/>'
    if hole:
        paths += f'\n      <path d="{hole}"/>'
    inner = f"""  <g fill-rule="evenodd">
    <g fill="#0A0A0E" stroke="#2A2A38" stroke-width="{FILL_STROKE}" stroke-linejoin="round" stroke-linecap="round">
{paths}
    </g>
    <g fill="#0A0A0E">
{paths}
    </g>
  </g>"""
    return (
        f"<!-- Imperium waybar - {note}. Filled stone, same as the putti. -->\n"
        f'<svg xmlns="http://www.w3.org/2000/svg" '
        f'viewBox="{-PAD} {-PAD} {vb_w:.2f} {vb_h:.2f}" width="{vb_w:.0f}" height="{vb_h:.0f}">\n'
        f"{inner}\n"
        f"</svg>\n"
    )


def svg_strokes(paths, vb_w, vb_h, note, mirror=False, stroke=INC_STROKE):
    xf = f' transform="translate({vb_w:.2f} 0) scale(-1 1)"' if mirror else ""
    body = "\n".join(f'    <path d="{d}"/>' for d in paths)
    inner = f"""  <g fill="none" stroke="{PLATE_STROKE}" stroke-width="{stroke}" stroke-linejoin="round" stroke-linecap="round"{xf}>
{body}
  </g>"""
    return (
        f"<!-- Imperium waybar - {note}. Incised contour on the plate. -->\n"
        f'<svg xmlns="http://www.w3.org/2000/svg" '
        f'viewBox="0 0 {vb_w:.2f} {vb_h:.2f}" width="{vb_w:.0f}" height="{vb_h:.0f}">\n'
        f"{inner}\n"
        f"</svg>\n"
    )


def spiral_d(cx, cy, r0, r1, turns, n=36, start_deg=-20):
    parts = []
    for i in range(n + 1):
        t = i / n
        ang = math.radians(start_deg + t * 360 * turns)
        r = r0 * (1.0 - t) + r1 * t
        x = cx + math.cos(ang) * r
        y = cy + math.sin(ang) * r
        parts.append(f"{'M' if i == 0 else ''}{x:.2f},{y:.2f}")
    return " ".join(parts)


def volute_paths():
    return [
        spiral_d(38, 42, 26, 5, 1.15, n=40, start_deg=40),
        "M62,48 C78,62 72,88 58,108",
        "M58,108 C50,118 42,122 36,118",
    ]


def mascaron_paths():
    """Sun-face: rays survive at 16px; rings would collapse to noise."""
    paths = ["M40,50 a16,18 0 1 1 0.01,0"]
    for i in range(8):
        a = math.radians(-90 + i * 45)
        x0 = 40 + math.cos(a) * 20
        y0 = 50 + math.sin(a) * 22
        x1 = 40 + math.cos(a) * 30
        y1 = 50 + math.sin(a) * 32
        paths.append(f"M{x0:.2f},{y0:.2f} {x1:.2f},{y1:.2f}")
    paths += [
        "M28,44 Q40,36 52,44",
        "M33,52 m-2,0 a2,2.4 0 1 1 0.01,0",
        "M47,52 m-2,0 a2,2.4 0 1 1 0.01,0",
        "M40,56 38,64 40,62 42,64",
        "M34,70 Q40,75 46,70",
    ]
    return paths


def emit_incised(stem, draw_fn, w, h, note, extra="", mirror_too=False):
    body, cw, ch = contour_of(draw_fn, w, h)
    if mirror_too:
        (ASSETS / f"{stem}-left.svg").write_text(svg_incised(body, cw, ch, f"{note} (left)"))
        (ASSETS / f"{stem}-right.svg").write_text(
            svg_incised(body, cw, ch, f"{note} (right)", extra=extra, mirror=True)
        )
    else:
        (ASSETS / f"{stem}.svg").write_text(svg_incised(body, cw, ch, note, extra=extra))
    print(f"{stem}: {cw:.0f}x{ch:.0f}")


def emit_filled(stem, draw_fn, w, h, note, hole=None):
    body, cw, ch = contour_of(draw_fn, w, h)
    (ASSETS / f"{stem}.svg").write_text(svg_filled(body, hole, cw, ch, note))
    print(f"{stem}: {cw:.0f}x{ch:.0f}")


def draw_volute(ctx):
    """Ionic-ish scroll for the left edge of the window plate."""
    cx, cy, r = 58, 70, 28
    prev = (cx + r, cy)
    n = 32
    for i in range(1, n + 1):
        t = i / n
        ang = math.radians(-20 + t * 400)
        rr = r * (1.0 - t * 0.7)
        p = (cx + math.cos(ang) * rr, cy + math.sin(ang) * rr)
        capsule(ctx, *prev, *p, max(2.4, 7.2 * (1.0 - t * 0.55)))
        prev = p
    capsule(ctx, cx + r - 2, cy, 92, 118, 5.5)
    capsule(ctx, 92, 118, 78, 138, 4.2)
    ellipse(ctx, 88, 128, 10, 6, 40)
    circle(ctx, cx, cy, 6)


def draw_corbel(ctx):
    """Vertical acanthus console, drawn for the left side of a plate."""
    capsule(ctx, 48, 18, 48, 52, 8)
    ellipse(ctx, 48, 18, 16, 7, 0)
    capsule(ctx, 48, 50, 32, 78, 7)
    capsule(ctx, 32, 78, 44, 108, 6)
    capsule(ctx, 44, 108, 28, 132, 5)
    ellipse(ctx, 24, 138, 12, 8, -30)
    circle(ctx, 18, 144, 6)
    ellipse(ctx, 38, 70, 14, 7, -50)
    ellipse(ctx, 52, 96, 12, 6, 35)


def note_svg(paused=False):
    """Eighth note drawn as strokes so it stays legible at bar size."""
    slash = '\n    <path d="M8,18 L50,74"/>' if paused else ""
    state = ", paused" if paused else ""
    return f"""<!-- Imperium waybar - mpris note{state}. -->
<svg xmlns="http://www.w3.org/2000/svg" viewBox="4 8 52 72" width="52" height="72">
  <g fill="none" stroke="{PLATE_STROKE}" stroke-width="5.2" stroke-linejoin="round" stroke-linecap="round">
    <path d="M34.58,57.86 C36.76,62.33 32.89,68.70 25.95,72.09 C19.00,75.48 11.60,74.60 9.42,70.14 C7.24,65.67 11.11,59.30 18.05,55.91 C25.00,52.52 32.40,53.40 34.58,57.86 Z" fill="{PLATE_STROKE}" stroke="none"/>
    <path d="M33.2,60 V14"/>
    <path d="M33.2,14 C48,20 50,38 38,48"/>{slash}
  </g>
</svg>
"""


def draw_mascaron(ctx):
    """Sun-lion face: mane of curls around a short snout."""
    cx, cy = 70, 72
    circle(ctx, cx, cy, 28)
    for i in range(12):
        a = math.radians(-90 + i * 30)
        circle(ctx, cx + math.cos(a) * 34, cy + math.sin(a) * 34, 9 if i % 2 == 0 else 7)
    ellipse(ctx, cx, cy - 8, 22, 10, 0)
    ellipse(ctx, cx, cy + 10, 12, 10, 0)
    circle(ctx, cx, cy + 18, 8)
    ellipse(ctx, cx - 10, cy - 2, 6, 5, -10)
    ellipse(ctx, cx + 10, cy - 2, 6, 5, 10)


def draw_patera(ctx):
    """Eight-petal rosette rivet."""
    cx, cy = 70, 70
    for i in range(8):
        a = math.radians(-90 + i * 45)
        ellipse(ctx, cx + math.cos(a) * 22, cy + math.sin(a) * 22, 16, 11, math.degrees(a))
    circle(ctx, cx, cy, 16)


def hole_patera(cx, cy, r_out, r_in):
    return (
        f"M{cx:.2f},{cy - r_out:.2f} "
        f"a{r_out:.2f},{r_out:.2f} 0 1 1 0,{2 * r_out:.2f} "
        f"a{r_out:.2f},{r_out:.2f} 0 1 1 0,{-2 * r_out:.2f}Z "
        f"M{cx:.2f},{cy - r_in:.2f} "
        f"a{r_in:.2f},{r_in:.2f} 0 1 0 0,{2 * r_in:.2f} "
        f"a{r_in:.2f},{r_in:.2f} 0 1 0 0,{-2 * r_in:.2f}Z"
    )


def main():
    sys.setrecursionlimit(20000)
    ASSETS.mkdir(exist_ok=True)
    vp = volute_paths()
    (ASSETS / "volute-left.svg").write_text(svg_strokes(vp, 90, 128, "window-plate volute (left)", stroke=8))
    (ASSETS / "volute-right.svg").write_text(
        svg_strokes(vp, 90, 128, "window-plate volute (right)", mirror=True, stroke=8)
    )
    print("volute: stroke")
    emit_incised("corbel", draw_corbel, 90, 170, "plate corbel", mirror_too=True)
    (ASSETS / "note.svg").write_text(note_svg())
    (ASSETS / "note-paused.svg").write_text(note_svg(paused=True))
    print("note: stroke")
    mp = mascaron_paths()
    (ASSETS / "mascaron.svg").write_text(svg_strokes(mp, 80, 100, "power mascaron", stroke=6))
    print("mascaron: stroke")

    body, cw, ch = contour_of(draw_patera, 140, 140)
    hole = hole_patera(cw / 2.0, ch / 2.0, 9.0, 4.5)
    (ASSETS / "patera.svg").write_text(
        svg_filled(body, hole, cw, ch, "patera between the right-hand plates")
    )
    print(f"patera: {cw:.0f}x{ch:.0f}")


if __name__ == "__main__":
    main()
