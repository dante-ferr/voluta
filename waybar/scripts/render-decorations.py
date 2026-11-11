#!/usr/bin/env python3
"""Render Wallust-colored decorations and the top glow state.

Source SVG geometry stays unchanged. Generated SVGs and absolute CSS URLs live
under wallust/assets/generated/waybar; rebuilt on wallpaper refresh and startup.
"""
from pathlib import Path
import json
import math
import subprocess
import re
import xml.etree.ElementTree as ET
from PIL import Image, ImageFilter, ImageOps

ROOT = Path(__file__).resolve().parents[1]
SVG = "http://www.w3.org/2000/svg"
ET.register_namespace("", SVG)
ET.register_namespace("xlink", "http://www.w3.org/1999/xlink")

SIDES = ("top", "right", "bottom", "left")
CHROME_DEFAULTS = {
    "outline": {
        "width_px": 1,
        "color1_mix": 0.4,
        "plates": {side: side == "bottom" for side in SIDES},
        "svgs": {side: side == "bottom" for side in SIDES},
    },
}

PLATE_OUTLINE_SELECTORS = (
    "#window, #custom-mpris, #workspaces, #clock,\n"
    "#custom-swaync, #tray, #temperature, #network,\n"
    "#bluetooth, #pulseaudio, #powerplate"
)

DECORATIONS = (
    ("#custom-angel-left", "angels-left.svg"),
    ("#custom-angel-right", "angels.svg"),
    (".modules-left,\nbox.modules-left", "ornaments-left.svg"),
    (".modules-right,\nbox.modules-right", "ornaments-right.svg"),
    ("#custom-mpris", "note.svg"),
    ("#custom-mpris.paused", "note-paused.svg"),
    ("#custom-patera", "patera.svg"),
)
DISPLAY_HEIGHTS = {
    "angels-left.svg": 30, "angels.svg": 30,
    "ornaments-left.svg": 28, "ornaments-right.svg": 28,
    "note.svg": 17, "note-paused.svg": 17,
    "patera.svg": 15,
}

DISPLAY_WIDTHS = {
    "angels-left.svg": 97.5, "angels.svg": 97.5,
    "ornaments-left.svg": 75, "ornaments-right.svg": 75,
    "note.svg": 12, "note-paused.svg": 12,
    "patera.svg": 28,
}

def mix_hex(foreground, background, toward_background):
    """Blend two #RRGGBB colors; toward_background matches GTK mix() weight."""
    return "#" + "".join(
        f"{round(int(foreground[i:i + 2], 16) * (1 - toward_background)
                 + int(background[i:i + 2], 16) * toward_background):02x}"
        for i in (1, 3, 5)
    )


def render(source, target, paint):
    root = ET.parse(source).getroot()
    if source.name in ("ornaments-left.svg", "ornaments-right.svg"):
        # Flip only the rendered ornaments in place.
        _, y, _, height = map(float, root.get("viewBox").split())
        flipped = ET.Element(f"{{{SVG}}}g", {
            "transform": f"translate(0 {2 * y + height:g}) scale(1 -1)",
        })
        for child in list(root):
            if child.tag.rsplit("}", 1)[-1] not in ("defs", "metadata", "title", "desc"):
                root.remove(child)
                flipped.append(child)
        root.append(flipped)
    # Preserve negative space, existing icon strokes and all transforms.
    # Change only explicit paint colors; filled shapes otherwise default black.
    root.set("fill", paint)
    for element in root.iter():
        for attr in ("fill", "stroke"):
            value = element.get(attr)
            if value and value.lower() not in ("none", "transparent"):
                element.set(attr, paint)
    # Rasterize the authored SVG at 3x display resolution. GTK then only loads
    # a small PNG.
    x, y, width, view_height = map(float, root.get("viewBox").split())
    height = DISPLAY_HEIGHTS[source.name]
    # Eight transparent screen pixels pad each image edge.
    # CSS adds the same space to the background size and compensates its
    # position, keeping the actual artwork scale and contact edge unchanged.
    display_width = DISPLAY_WIDTHS[source.name]
    pad_x, pad_y = 8 * width / display_width, 8 * view_height / height
    root.set("viewBox", f"{x-pad_x} {y-pad_y} {width+2*pad_x} {view_height+2*pad_y}")
    root.set("preserveAspectRatio", "none")
    subprocess.run([
        "rsvg-convert", "--width", str(round((display_width + 16) * 3)),
        "--height", str((height + 16) * 3), "--output", str(target),
    ], input=ET.tostring(root), check=True)


def load_chrome():
    """Read waybar/chrome.json outline knobs with safe defaults."""
    path = ROOT / "chrome.json"
    raw = json.loads(path.read_text()) if path.exists() else {}
    outline = {**CHROME_DEFAULTS["outline"], **raw.get("outline", {})}
    for group in ("plates", "svgs"):
        sides = {**CHROME_DEFAULTS["outline"][group], **outline.get(group, {})}
        for side in SIDES:
            if not isinstance(sides.get(side), bool):
                raise ValueError(f"chrome.json: outline.{group}.{side} must be bool")
        outline[group] = sides
    width = outline["width_px"]
    mix = outline["color1_mix"]
    if (isinstance(width, bool) or not isinstance(width, (int, float))
            or not math.isfinite(width) or width < 0):
        raise ValueError("chrome.json: outline.width_px must be a non-negative number")
    if (isinstance(mix, bool) or not isinstance(mix, (int, float))
            or not math.isfinite(mix) or not 0 <= mix <= 1):
        raise ValueError("chrome.json: outline.color1_mix must be between 0 and 1")
    outline["width_px"] = width
    outline["color1_mix"] = mix
    return {"outline": outline}


def plate_side_rule(selectors, side, width_px):
    """Emit one rectangular outline side for style.css (after `* { border: none }`)."""
    width = int(round(width_px))
    return (
        f"{selectors} {{\n"
        f"    border-{side}: {width}px solid @bar-outline;\n"
        "}\n"
    )


CHROME_MARK_START = "/* @@chrome-outline:start */"
CHROME_MARK_END = "/* @@chrome-outline:end */"


def write_style_chrome_outline(plates, width_px):
    """Replace the marked outline block in style.css from chrome.json."""
    chunks = [
        "/* Generated from waybar/chrome.json — edit that file, not this block. */\n"
    ]
    if plates["top"]:
        chunks.append(plate_side_rule(PLATE_OUTLINE_SELECTORS, "top", width_px))
    if plates["bottom"]:
        chunks.append(plate_side_rule(PLATE_OUTLINE_SELECTORS, "bottom", width_px))
    if plates["left"]:
        chunks.append(plate_side_rule(
            "#window, #custom-mpris, #workspaces, #custom-swaync, #powerplate",
            "left",
            width_px,
        ))
    if plates["right"]:
        chunks.append(plate_side_rule(
            "#window, #custom-mpris, #clock, #pulseaudio, #powerplate",
            "right",
            width_px,
        ))
    if len(chunks) == 1:
        chunks.append("/* All plate outline sides disabled in chrome.json. */\n")
    block = "".join(chunks)
    path = ROOT / "style.css"
    text = path.read_text()
    start = text.find(CHROME_MARK_START)
    end = text.find(CHROME_MARK_END)
    if start < 0 or end < 0 or end < start:
        raise ValueError("style.css: missing @@chrome-outline markers")
    end += len(CHROME_MARK_END)
    path.write_text(
        text[:start] + CHROME_MARK_START + "\n" + block + CHROME_MARK_END + text[end:]
    )


def paint_side_contours(target, color, sides, outline_px, scale=3):
    """Paint enabled silhouette sides, following alpha (not a bounding box).

    Dilate the artwork, take the exterior ring, and keep pixels that face an
    enabled side (top/bottom/left/right) of solid content.
    """
    if not any(sides.get(side) for side in SIDES):
        return
    image = Image.open(target).convert("RGBA")
    alpha = image.getchannel("A")
    radius = max(1, round(outline_px * scale))
    dilated = alpha.filter(ImageFilter.MaxFilter(radius * 2 + 1))
    width, height = image.size
    solid = alpha.load()
    outer = dilated.load()
    pixels = image.load()
    red, green, blue = (int(color[i:i + 2], 16) for i in (1, 3, 5))
    reach = radius + 2

    def opaque_in(x0, y0, x1, y1):
        x0, y0 = max(0, x0), max(0, y0)
        x1, y1 = min(width - 1, x1), min(height - 1, y1)
        for yy in range(y0, y1 + 1):
            for xx in range(x0, x1 + 1):
                if solid[xx, yy] >= 128:
                    return True
        return False

    for y in range(height):
        for x in range(width):
            if outer[x, y] < 128 or solid[x, y] >= 128:
                continue
            above = opaque_in(x - 1, y - reach, x + 1, y - 1)
            below = opaque_in(x - 1, y + 1, x + 1, y + reach)
            left = opaque_in(x - reach, y - 1, x - 1, y + 1)
            right = opaque_in(x + 1, y - 1, x + reach, y + 1)
            keep = (
                (sides.get("bottom") and above and not below)
                or (sides.get("top") and below and not above)
                or (sides.get("left") and right and not left)
                or (sides.get("right") and left and not right)
            )
            if keep:
                pixels[x, y] = (red, green, blue, 255)
    image.save(target)


def query(command):
    try:
        return subprocess.check_output(command, text=True, stderr=subprocess.DEVNULL, timeout=3)
    except (OSError, subprocess.SubprocessError):
        return ""


def relative_luminance(pixels):
    def linear(value):
        value /= 255
        return value / 12.92 if value <= .04045 else ((value + .055) / 1.055) ** 2.4
    table = [linear(v) for v in range(256)]
    total = sum(.2126 * table[r] + .7152 * table[g] + .0722 * table[b] for r, g, b in pixels)
    return total / max(1, len(pixels))


def top_light_factors(heaven):
    """Return a 0..1 glow strength per output from its wallpaper's top band.

    The glow only helps on medium to dark tops. At or below `full_below` it is
    fully on, at or above `off_above` it is off, with a linear ramp between.
    The wallpaper is approximated as center-cropped to fill the output.
    """
    try:
        monitors = json.loads(query(["hyprctl", "-j", "monitors"]) or "[]")
    except ValueError:
        return {}
    paths = {}
    for daemon in ("awww", "swww"):
        for line in query([daemon, "query"]).splitlines():
            match = re.search(r"(?:^|: )([^:]+): \d+x\d+, scale: [\d.]+, .*image: (.*)$", line)
            if match:
                paths[match[1]] = match[2]
        if paths:
            break
    low, high = heaven["full_below"], heaven["off_above"]
    factors = {}
    for monitor in monitors:
        path = paths.get(monitor["name"])
        if not path:
            continue
        try:
            with Image.open(path) as source:
                scale = 4
                size = (max(1, monitor["width"] // scale), max(1, monitor["height"] // scale))
                image = ImageOps.fit(source.convert("RGB"), size, Image.Resampling.BILINEAR)
        except (OSError, ValueError):
            continue
        band = max(1, round(heaven["height_px"] / scale))
        luminance = relative_luminance(list(getattr(image.crop((0, 0, size[0], band)), "get_flattened_data", image.getdata)()))
        factors[monitor["name"]] = round(min(1, max(0, (high - luminance) / (high - low))), 3)
    return factors


def main():
    settings = json.loads((ROOT / "glow.json").read_text())
    chrome = load_chrome()
    heaven = {"enabled": True, "opacity": 0.55, "height_px": 220, "fps": 10,
              "drift_px_per_s": 14, "animate": True, "pause_on_battery": True,
              "full_below": 0.05, "off_above": 0.14, **settings.get("heaven", {})}
    for key in ("opacity", "height_px", "fps", "drift_px_per_s"):
        value = heaven[key]
        if (isinstance(value, bool) or not isinstance(value, (int, float))
                or not math.isfinite(value) or value < 0
                or (key == "opacity" and value > 1) or (key == "fps" and value < 1)):
            raise ValueError(f"glow.json: invalid heaven.{key}")
    if not 0 <= heaven["full_below"] < heaven["off_above"] <= 1:
        raise ValueError("glow.json: heaven.full_below must be below heaven.off_above")
    for key in ("enabled", "animate", "pause_on_battery"):
        if not isinstance(heaven[key], bool):
            raise ValueError(f"glow.json: invalid heaven.{key}")
    for key in ("blur_px", "opacity"):
        value = settings["boxes"][key]
        if (isinstance(value, bool) or not isinstance(value, (int, float))
                or not math.isfinite(value) or value < 0 or (key == "opacity" and value > 1)):
            raise ValueError(f"glow.json: invalid boxes.{key}")
    palette = ROOT / "wallust/colors-waybar.css"
    colors = dict(re.findall(r"@define-color\s+(\w+)\s+(#[0-9a-fA-F]{6})\s*;",
                             palette.read_text() if palette.exists() else ""))
    if not {"foreground", "color0"}.issubset(colors):
        print("Waybar decorations: no Wallust palette yet; keeping existing assets")
        return
    output = ROOT.parent / "wallust/assets/generated/waybar"
    output.mkdir(parents=True, exist_ok=True)
    def brightness(value):
        return sum(weight * int(value[i:i+2], 16) for weight, i in
                   ((.2126, 1), (.7152, 3), (.0722, 5)))
    bright_name = max(("foreground", "color15") if "color15" in colors else ("foreground",),
                      key=lambda name: brightness(colors[name]))
    # Mute the bright ink toward Wallust's dark ink.
    def muted(paint):
        dark = colors["color0"]
        return "#" + "".join(f"{round(int(paint[i:i+2], 16) * .8 + int(dark[i:i+2], 16) * .2):02x}"
                              for i in (1, 3, 5))
    bright = muted(colors[bright_name])
    # Wallpaper-facing artwork and plates share half-brightness color0. The top
    # glow below lifts the backdrop so this dark artwork always contrasts.
    dark = "#" + "".join(f"{round(int(colors['color0'][i:i+2], 16) * .5):02x}"
                          for i in (1, 3, 5))
    outline_cfg = chrome["outline"]
    outline = mix_hex(
        colors.get("color1", bright), colors["background"], outline_cfg["color1_mix"])
    rules = [
        f"@define-color box-background {dark};\n",
        f"@define-color decoration-bright {bright};\n",
        # Same lifted accent as Hyprland active_border, mixed toward background.
        # Plate border rules land in style.css after `* { border: none }`.
        f"@define-color bar-outline mix(@color1, @background, "
        f"{outline_cfg['color1_mix']:.2f});\n",
    ]
    write_style_chrome_outline(outline_cfg["plates"], outline_cfg["width_px"])
    for selector, filename in DECORATIONS:
        source = ROOT.parent / "wallust/assets" / filename
        # Icons on opaque plates stay in the bright ink; the rest use dark ink.
        boxed_icon = filename in ("note.svg", "note-paused.svg")
        variant, paint = ("bright", bright) if boxed_icon else ("dark", dark)
        target = output / f"{Path(filename).stem}-{variant}.png"
        render(source, target, paint)
        if not boxed_icon:
            paint_side_contours(
                target, outline, outline_cfg["svgs"], outline_cfg["width_px"])
        rules.append(f'{selector} {{\n    background-image: url("{target.as_uri()}");\n}}\n')
    # glow.qml reads this file and repaints when it changes. Colors are the muted
    # bright ink plus two palette accents already lightened by the template.
    # Flip heaven.enabled in glow.json to restore the top light without retuning
    # opacity or animation.
    state = {
        "enabled": heaven["enabled"],
        "opacity": heaven["opacity"] if heaven["enabled"] else 0,
        "height": heaven["height_px"], "fps": heaven["fps"],
        "drift": heaven["drift_px_per_s"], "animate": heaven["animate"],
        "pause_on_battery": heaven["pause_on_battery"],
        "outputs": top_light_factors(heaven) if heaven["enabled"] else {},
        "colors": [bright, colors.get("color12", bright), colors.get("color13", bright)],
    }
    (ROOT / "wallust/glow-state.json").write_text(json.dumps(state, indent=2) + "\n")
    boxes = settings["boxes"]
    rules.append(
        "#window, #custom-mpris, #workspaces, #clock,\n"
        "#custom-swaync, #tray, #temperature, #network,\n"
        "#pulseaudio, #powerplate {\n"
        f'    box-shadow: 0 0 {boxes["blur_px"]}px '
        f'alpha(@foreground, {boxes["opacity"]});\n'
        "}\n"
    )
    (ROOT / "wallust/angel-paths.css").write_text(
        "/* Generated from waybar/glow.json and waybar/chrome.json. */\n"
        + "\n".join(rules)
    )


if __name__ == "__main__":
    main()
