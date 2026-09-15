#!/usr/bin/env python3
"""Generate waybar rinceaux.

Center pair: true incised strokes (no fill) behind the putti.
Spread pair: filled stone growing out of the left/right plates toward the
middle. Not part of the runtime bar — run from waybar/ to refresh assets.
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

PAD = 18
FILL_STROKE = 10
INC_STROKE = 7
SCALE = 6
SPREAD_W, SPREAD_H = 520, 170


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


def cubic_pts(p0, p1, p2, p3, n=56):
    pts = []
    for i in range(n + 1):
        t = i / n
        u = 1.0 - t
        x = u**3 * p0[0] + 3 * u**2 * t * p1[0] + 3 * u * t**2 * p2[0] + t**3 * p3[0]
        y = u**3 * p0[1] + 3 * u**2 * t * p1[1] + 3 * u * t**2 * p2[1] + t**3 * p3[1]
        pts.append((x, y))
    return pts


def cubic_d(p0, p1, p2, p3):
    return (
        f"M{p0[0]:.1f},{p0[1]:.1f} "
        f"C{p1[0]:.1f},{p1[1]:.1f} {p2[0]:.1f},{p2[1]:.1f} {p3[0]:.1f},{p3[1]:.1f}"
    )


def circle_d(x, y, r):
    return f"M{x - r:.1f},{y:.1f} a{r:.1f},{r:.1f} 0 1 1 {2 * r:.1f},0 a{r:.1f},{r:.1f} 0 1 1 {-2 * r:.1f},0"


def leaf_d(x, y, deg, length):
    a = math.radians(deg)
    x1 = x + math.cos(a) * length
    y1 = y + math.sin(a) * length
    nx = -math.sin(a) * length * 0.28
    ny = math.cos(a) * length * 0.28
    return (
        f"M{x:.1f},{y:.1f} "
        f"Q{x + (x1 - x) * 0.45 + nx:.1f},{y + (y1 - y) * 0.45 + ny:.1f} {x1:.1f},{y1:.1f} "
        f"Q{x + (x1 - x) * 0.45 - nx:.1f},{y + (y1 - y) * 0.45 - ny:.1f} {x:.1f},{y:.1f}"
    )


def flower_ds(x, y, s):
    out = []
    for i in range(5):
        a = math.radians(-90 + i * 72)
        out.append(circle_d(x + math.cos(a) * s * 0.72, y + math.sin(a) * s * 0.72, s * 0.38))
    out.append(circle_d(x, y, s * 0.28))
    return out


def tangent_deg(pts, i):
    j = min(i + 2, len(pts) - 1)
    k = max(i - 2, 0)
    return math.degrees(math.atan2(pts[j][1] - pts[k][1], pts[j][0] - pts[k][0]))


def incised_center_paths():
    """Tablet on the right, crook on the left. Open strokes, no silhouette."""
    spine_c = ((548, 100), (410, 24), (290, 148), (172, 88))
    crook_c = ((172, 88), (118, 40), (52, 14), (26, 56))
    ret_c = ((26, 56), (32, 86), (62, 92), (80, 74))
    spine = cubic_pts(*spine_c)
    crook = cubic_pts(*crook_c, n=32)
    paths = [
        cubic_d(*spine_c),
        cubic_d(*crook_c),
        cubic_d(*ret_c),
    ]
    for idx, side, length in (
        (10, 1, 28),
        (20, -1, 24),
        (32, 1, 22),
        (44, -1, 20),
        (54, 1, 16),
    ):
        paths.append(leaf_d(*spine[idx], tangent_deg(spine, idx) + side * 55, length))
    paths.extend(flower_ds(spine[24][0] - 2, spine[24][1] - 16, 7))
    paths.append(f"M{spine[24][0]:.1f},{spine[24][1]:.1f} {spine[24][0] - 2:.1f},{spine[24][1] - 16:.1f}")
    paths.extend(flower_ds(crook[-1][0] - 4, crook[-1][1] + 2, 8))
    paths.extend(flower_ds(crook[10][0] - 8, crook[10][1] - 10, 5))
    paths.extend(flower_ds(70, 88, 5.5))
    return paths


def svg_incised(paths, vb_w, vb_h, note, mirror=False):
    xf = f' transform="translate({vb_w:.2f} 0) scale(-1 1)"' if mirror else ""
    body = "\n".join(f'    <path d="{d}"/>' for d in paths)
    inner = f"""  <g fill="none" stroke="#2A2A38" stroke-width="{INC_STROKE}" stroke-linejoin="round" stroke-linecap="round"{xf}>
{body}
  </g>"""
    return (
        f"<!-- Imperium waybar - {note}. Contour only: open strokes, no fill. -->\n"
        f'<svg xmlns="http://www.w3.org/2000/svg" '
        f'viewBox="0 0 {vb_w:.0f} {vb_h:.0f}" width="{vb_w:.0f}" height="{vb_h:.0f}">\n'
        f"{inner}\n"
        f"</svg>\n"
    )


def stem(ctx, pts, r0, r1):
    n = max(len(pts) - 1, 1)
    for i in range(n):
        t = i / n
        capsule(ctx, *pts[i], *pts[i + 1], r0 * (1.0 - t) + r1 * t)


def leaf(ctx, x, y, deg, length, width):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    ellipse(ctx, x + c * length * 0.38, y + s * length * 0.38, length * 0.4, width * 0.42, deg)
    ellipse(ctx, x + c * length * 0.7, y + s * length * 0.7, length * 0.26, width * 0.26, deg)
    circle(ctx, x + c * length * 0.92, y + s * length * 0.92, width * 0.18)
    circle(ctx, x, y, width * 0.3)


def flower(ctx, x, y, s):
    for i in range(5):
        a = math.radians(-90 + i * 72)
        circle(ctx, x + math.cos(a) * s * 0.78, y + math.sin(a) * s * 0.78, s * 0.5)
    circle(ctx, x, y, s * 0.38)


def dove(ctx, x, y, face=1):
    """Tiny dove flying toward the centre cluster."""
    ellipse(ctx, x, y, 16, 9, face * -12)
    circle(ctx, x + face * 16, y - 4, 7)
    ellipse(ctx, x + face * 18, y - 6, 4, 2.5, face * 10)
    ellipse(ctx, x - face * 2, y - 10, 14, 6, face * -28)
    ellipse(ctx, x - face * 4, y - 2, 10, 5, face * 18)
    ellipse(ctx, x - face * 16, y + 4, 8, 4, face * 20)


def seraph(ctx, x, y):
    """Winged head at the plate origin."""
    circle(ctx, x, y, 11)
    circle(ctx, x - 2, y - 10, 6)
    circle(ctx, x + 3, y - 9, 5)
    ellipse(ctx, x - 18, y + 2, 16, 7, -18)
    ellipse(ctx, x + 18, y + 2, 16, 7, 18)
    ellipse(ctx, x - 14, y + 8, 12, 5, 12)
    ellipse(ctx, x + 14, y + 8, 12, 5, -12)


def draw_spread(ctx):
    """Filled vine: plate origin on the left, terminus toward the middle."""
    ctx.set_source_rgb(0, 0, 0)
    spine = cubic_pts((18, 88), (140, 28), (280, 150), (400, 70), n=64)
    stem(ctx, spine, 6.5, 3.8)
    seraph(ctx, 22, 86)
    for idx, side, length, width in (
        (12, 1, 36, 14),
        (22, -1, 32, 13),
        (34, 1, 28, 12),
        (46, -1, 24, 11),
    ):
        leaf(ctx, *spine[idx], tangent_deg(spine, idx) + side * 58, length, width)
    flower(ctx, spine[28][0] + 2, spine[28][1] - 16, 8)
    capsule(ctx, *spine[28], spine[28][0] + 2, spine[28][1] - 16, 3)
    crook = cubic_pts(spine[-1], (450, 36), (498, 18), (508, 58), n=32)
    stem(ctx, crook, 3.8, 2.4)
    ret = cubic_pts(crook[-1], (500, 88), (470, 96), (452, 78), n=18)
    stem(ctx, ret, 2.4, 2.0)
    flower(ctx, crook[-1][0] - 2, crook[-1][1] + 2, 8.5)
    flower(ctx, 488, 28, 6)
    dove(ctx, 430, 48, face=1)


def rasterize(draw_fn, w, h):
    img_w, img_h = w * SCALE, h * SCALE
    surface = cairo.ImageSurface(cairo.FORMAT_A8, img_w, img_h)
    ctx = cairo.Context(surface)
    ctx.set_antialias(cairo.ANTIALIAS_DEFAULT)
    ctx.scale(SCALE, SCALE)
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
        return rdp(points[: idx + 1], epsilon)[:-1] + rdp(points[idx:], epsilon)
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
    return rdp(pts, epsilon=0.55)


def svg_filled(body, cw, ch, note, mirror=False):
    xf = f' transform="translate({cw:.2f} 0) scale(-1 1)"' if mirror else ""
    vb_w, vb_h = cw + PAD * 2, ch + PAD * 2
    paths = f'      <path d="{body}"/>'
    inner = f"""  <g fill-rule="evenodd"{xf}>
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


def emit_spread():
    mask = rasterize(draw_spread, SPREAD_W, SPREAD_H)
    pts = close_loop([(x / SCALE, y / SCALE) for x, y in trace_contour(mask)])
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    minx, miny = min(xs), min(ys)
    body = path_d([(x - minx, y - miny) for x, y in pts])
    cw, ch = max(xs) - minx, max(ys) - miny
    (ASSETS / "spread-left.svg").write_text(
        svg_filled(body, cw, ch, "rinceau from the left plates toward the centre", mirror=False)
    )
    (ASSETS / "spread-right.svg").write_text(
        svg_filled(body, cw, ch, "rinceau from the right plates toward the centre", mirror=True)
    )
    print(f"spread: {cw:.0f}x{ch:.0f}")


def main():
    sys.setrecursionlimit(20000)
    ASSETS.mkdir(exist_ok=True)
    paths = incised_center_paths()
    (ASSETS / "rinceau-left.svg").write_text(
        svg_incised(paths, 560, 160, "incised rinceau of the central tablet (left)")
    )
    (ASSETS / "rinceau-right.svg").write_text(
        svg_incised(paths, 560, 160, "incised rinceau of the central tablet (right)", mirror=True)
    )
    print(f"rinceau incised: {len(paths)} strokes")
    emit_spread()


if __name__ == "__main__":
    main()
