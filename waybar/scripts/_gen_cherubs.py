#!/usr/bin/env python3
"""Generate waybar cherub silhouettes: cairo draw → contour → SVG.

Not part of the runtime bar. Run from waybar/ to refresh assets/cherub-*.svg
and the matching wallust lit templates.
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
TEMPLATES = ROOT.parent / "wallust" / "templates"

PAD = 18
STROKE = 10
LIT_STROKE = 34
CANVAS_W, CANVAS_H = 340, 360
SCALE = 6
IMG_W, IMG_H = CANVAS_W * SCALE, CANVAS_H * SCALE

# Halo is (cx, cy, rx_out, ry_out, rx_in, ry_in) — a wide oval on the crown.
IN_HEAD = (208.0, 108.0)
IN_HALO = (206.0, 22.0, 50.0, 22.0, 32.0, 12.0)
OUT_HEAD = (118.0, 102.0)
OUT_HALO = (116.0, 18.0, 50.0, 22.0, 32.0, 12.0)


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


def chubby_head(ctx, cx, cy, r, face_dir=1):
    """Oversized putto skull with a cloud of curls. face_dir: +1 right, -1 left."""
    circle(ctx, cx, cy, r)
    ellipse(ctx, cx + face_dir * r * 0.55, cy + r * 0.22, r * 0.45, r * 0.4, face_dir * 16)
    ellipse(ctx, cx + face_dir * r * 0.2, cy + r * 0.58, r * 0.42, r * 0.3, face_dir * 8)
    circle(ctx, cx + face_dir * r * 0.12, cy + r * 0.72, r * 0.3)
    back = -face_dir
    circle(ctx, cx, cy - r * 0.78, r * 0.52)
    circle(ctx, cx + back * r * 0.5, cy - r * 0.55, r * 0.5)
    circle(ctx, cx + face_dir * r * 0.42, cy - r * 0.62, r * 0.44)
    circle(ctx, cx + back * r * 0.72, cy - r * 0.12, r * 0.42)
    circle(ctx, cx + back * r * 0.62, cy + r * 0.28, r * 0.34)
    circle(ctx, cx + face_dir * r * 0.68, cy - r * 0.22, r * 0.3)
    circle(ctx, cx - r * 0.08, cy - r * 0.92, r * 0.34)
    circle(ctx, cx + back * r * 0.25, cy - r * 0.7, r * 0.36)


def draw_inward(ctx):
    """Swooping putto, looking right: diagonal flight, reaching the tablet."""
    ctx.set_source_rgb(0, 0, 0)
    ctx.set_fill_rule(cairo.FILL_RULE_WINDING)

    # Round putto wings from the dorsal — stacked scoops, not spears.
    ellipse(ctx, 108, 172, 52, 36, -36)
    ellipse(ctx, 68, 148, 40, 28, -42)
    ellipse(ctx, 42, 128, 24, 18, -38)
    circle(ctx, 28, 118, 12)
    ellipse(ctx, 102, 212, 46, 28, 16)
    ellipse(ctx, 62, 222, 32, 22, 22)
    circle(ctx, 38, 228, 14)
    ellipse(ctx, 148, 192, 28, 22, 8)

    chubby_head(ctx, *IN_HEAD, 64, face_dir=1)

    ellipse(ctx, 178, 210, 58, 62, 14)
    circle(ctx, 196, 228, 42)
    ellipse(ctx, 158, 236, 32, 28, 20)
    circle(ctx, 176, 252, 24)

    capsule(ctx, 220, 178, 258, 172, 22)
    capsule(ctx, 258, 172, 292, 152, 20)
    circle(ctx, 302, 146, 20)
    ellipse(ctx, 316, 136, 12, 8, -24)

    capsule(ctx, 196, 258, 238, 278, 24)
    capsule(ctx, 238, 278, 230, 312, 18)
    ellipse(ctx, 218, 322, 20, 10, -12)

    capsule(ctx, 158, 256, 128, 286, 22)
    capsule(ctx, 128, 286, 118, 316, 16)
    ellipse(ctx, 104, 324, 18, 9, 22)

    ctx.move_to(150, 242)
    ctx.curve_to(122, 252, 108, 278, 114, 304)
    ctx.curve_to(128, 298, 142, 270, 156, 250)
    ctx.close_path()
    ctx.fill()


def draw_outward(ctx):
    """Hovering putto, looking left: upright, one knee tucked, one arm raised."""
    ctx.set_source_rgb(0, 0, 0)
    ctx.set_fill_rule(cairo.FILL_RULE_WINDING)

    ellipse(ctx, 198, 152, 48, 34, 42)
    ellipse(ctx, 236, 118, 36, 26, 48)
    ellipse(ctx, 258, 92, 22, 16, 40)
    circle(ctx, 270, 80, 12)
    ellipse(ctx, 208, 198, 42, 26, -6)
    ellipse(ctx, 244, 198, 28, 20, 8)
    circle(ctx, 266, 200, 12)
    ellipse(ctx, 168, 188, 28, 22, -10)

    chubby_head(ctx, *OUT_HEAD, 66, face_dir=-1)

    ellipse(ctx, 148, 216, 60, 58, -8)
    circle(ctx, 138, 236, 44)
    ellipse(ctx, 168, 232, 30, 28, -16)
    circle(ctx, 150, 252, 26)

    # Arm clearly left of the hair mass.
    capsule(ctx, 88, 178, 42, 158, 24)
    capsule(ctx, 42, 158, 22, 128, 22)
    circle(ctx, 16, 118, 22)
    ellipse(ctx, 6, 104, 12, 8, 32)

    capsule(ctx, 168, 200, 188, 228, 18)
    circle(ctx, 196, 238, 18)

    # Fat knee parked out in front.
    ellipse(ctx, 78, 258, 40, 32, -22)
    capsule(ctx, 78, 258, 48, 278, 22)
    ellipse(ctx, 34, 292, 20, 12, 18)

    capsule(ctx, 168, 258, 186, 292, 20)
    ellipse(ctx, 176, 310, 16, 10, -8)

    ctx.move_to(172, 236)
    ctx.curve_to(198, 248, 210, 276, 200, 300)
    ctx.curve_to(186, 290, 176, 260, 164, 242)
    ctx.close_path()
    ctx.fill()


def rasterize(draw_fn):
    surface = cairo.ImageSurface(cairo.FORMAT_A8, IMG_W, IMG_H)
    ctx = cairo.Context(surface)
    ctx.set_antialias(cairo.ANTIALIAS_DEFAULT)
    ctx.scale(SCALE, SCALE)
    draw_fn(ctx)
    buf = np.frombuffer(surface.get_data(), dtype=np.uint8)
    stride = surface.get_stride()
    alpha = np.ndarray((IMG_H, stride), buffer=buf, dtype=np.uint8)[:, :IMG_W]
    mask = (alpha > 48).astype(np.uint8)
    im = Image.fromarray(mask * 255)
    im = im.filter(ImageFilter.MaxFilter(5))
    im = im.filter(ImageFilter.MinFilter(5))
    return (np.array(im) > 0).astype(np.uint8)


def trace_contour(mask):
    img = np.pad(mask, 1, mode="constant")
    pos = np.argwhere(img)
    sy, sx = int(pos[0][0]), int(pos[0][1])
    nb = [
        (-1, -1),
        (-1, 0),
        (-1, 1),
        (0, 1),
        (1, 1),
        (1, 0),
        (1, -1),
        (0, -1),
    ]
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


def halo_ellipse_d(cx, cy, rx_out, ry_out, rx_in, ry_in):
    return (
        f"M{cx:.2f},{cy - ry_out:.2f} "
        f"a{rx_out:.2f},{ry_out:.2f} 0 1 1 0,{2 * ry_out:.2f} "
        f"a{rx_out:.2f},{ry_out:.2f} 0 1 1 0,{-2 * ry_out:.2f}Z "
        f"M{cx:.2f},{cy - ry_in:.2f} "
        f"a{rx_in:.2f},{ry_in:.2f} 0 1 0 0,{2 * ry_in:.2f} "
        f"a{rx_in:.2f},{ry_in:.2f} 0 1 0 0,{-2 * ry_in:.2f}Z"
    )


def svg_body(body, halo, content_w, content_h, note, lit=False, mirror=False, rotate_deg=0):
    stroke = "{{color1 | lighten(0.30)}}" if lit else "#2A2A38"
    width = LIT_STROKE if lit else STROKE
    cx = content_w / 2.0
    cy = content_h / 2.0
    rad = math.radians(rotate_deg)
    cos_a, sin_a = math.cos(rad), math.sin(rad)

    def rot(x, y):
        dx, dy = x - cx, y - cy
        return (cx + dx * cos_a - dy * sin_a, cy + dx * sin_a + dy * cos_a)

    box = [(0.0, 0.0), (content_w, 0.0), (content_w, content_h), (0.0, content_h)]
    rx = [rot(x, y)[0] for x, y in box]
    ry = [rot(x, y)[1] for x, y in box]
    minx, miny = min(rx), min(ry)
    maxx, maxy = max(rx), max(ry)
    rw, rh = maxx - minx, maxy - miny
    vb_w = rw + PAD * 2
    vb_h = rh + PAD * 2
    side = "right" if mirror else "left"
    kind = "lit twin — " if lit else ""
    xf_parts = []
    if mirror:
        xf_parts.append(f"translate({rw:.2f} 0) scale(-1 1)")
    if abs(minx) > 0.05 or abs(miny) > 0.05:
        xf_parts.append(f"translate({-minx:.2f} {-miny:.2f})")
    if abs(rotate_deg) > 0.05:
        xf_parts.append(f"rotate({rotate_deg:.2f} {cx:.2f} {cy:.2f})")
    xf = f' transform="{" ".join(xf_parts)}"' if xf_parts else ""
    comment = (
        f"<!-- Imperium waybar - {note} ({side}).\n"
        f"     {kind}Body and contour match the plate colours in waybar/style.css. -->"
    )
    paths = f'      <path d="{body}"/>\n      <path d="{halo}"/>'
    inner = f"""  <g fill-rule="evenodd"{xf}>
    <g fill="#0A0A0E" stroke="{stroke}" stroke-width="{width}" stroke-linejoin="round" stroke-linecap="round">
{paths}
    </g>
    <g fill="#0A0A0E">
{paths}
    </g>
  </g>"""
    return (
        f"{comment}\n"
        f'<svg xmlns="http://www.w3.org/2000/svg" '
        f'viewBox="{-PAD} {-PAD} {vb_w:.2f} {vb_h:.2f}" width="{vb_w:.0f}" height="{vb_h:.0f}">\n'
        f"{inner}\n"
        f"</svg>\n"
    )


def emit(stem, draw_fn, halo, note, rotate_deg=0):
    mask = rasterize(draw_fn)
    pts = close_loop([(x / SCALE, y / SCALE) for x, y in trace_contour(mask)])
    hx, hy, rxo, ryo, rxi, ryi = halo
    xs = [p[0] for p in pts] + [hx - rxo, hx + rxo]
    ys = [p[1] for p in pts] + [hy - ryo, hy + ryo]
    minx, miny = min(xs), min(ys)
    maxx, maxy = max(xs), max(ys)
    body = path_d([(x - minx, y - miny) for x, y in pts])
    halo_d = halo_ellipse_d(hx - minx, hy - miny, rxo, ryo, rxi, ryi)
    content_w, content_h = maxx - minx, maxy - miny
    args = dict(
        body=body,
        halo=halo_d,
        content_w=content_w,
        content_h=content_h,
        note=note,
        rotate_deg=rotate_deg,
    )
    (ASSETS / f"{stem}-left.svg").write_text(svg_body(**args, lit=False, mirror=False))
    (ASSETS / f"{stem}-right.svg").write_text(svg_body(**args, lit=False, mirror=True))
    (TEMPLATES / f"{stem}-left-lit.svg").write_text(svg_body(**args, lit=True, mirror=False))
    (TEMPLATES / f"{stem}-right-lit.svg").write_text(svg_body(**args, lit=True, mirror=True))
    print(f"{stem}: pts={len(pts)} content={content_w:.1f}x{content_h:.1f} rot={rotate_deg}")


def main():
    sys.setrecursionlimit(20000)
    ASSETS.mkdir(exist_ok=True)
    TEMPLATES.mkdir(exist_ok=True)
    emit("cherub", draw_inward, IN_HALO, "inward putto of the central tablet", rotate_deg=-7)
    emit("cherub-outer", draw_outward, OUT_HALO, "outward putto of the central tablet", rotate_deg=16)


if __name__ == "__main__":
    main()
