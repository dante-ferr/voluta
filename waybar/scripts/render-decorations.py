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
from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[1]
SVG = "http://www.w3.org/2000/svg"
ET.register_namespace("", SVG)
ET.register_namespace("xlink", "http://www.w3.org/1999/xlink")

DECORATIONS = (
    ("#custom-angel-left", "angels-left.svg"),
    ("#custom-angel-right", "angels.svg"),
    (".modules-left,\nbox.modules-left", "ornaments-left.svg"),
    (".modules-right,\nbox.modules-right", "ornaments-right.svg"),
    ("#window", "volute-left.svg"),
    ("#custom-mpris", "note.svg"),
    ("#custom-mpris.paused", "note-paused.svg"),
    ("#custom-patera", "patera.svg"),
)
DISPLAY_HEIGHTS = {
    "angels-left.svg": 30, "angels.svg": 30,
    "ornaments-left.svg": 28, "ornaments-right.svg": 28,
    "volute-left.svg": 20, "note.svg": 17, "note-paused.svg": 17,
    "patera.svg": 15,
}

DISPLAY_WIDTHS = {
    "angels-left.svg": 97.5, "angels.svg": 97.5,
    "ornaments-left.svg": 75, "ornaments-right.svg": 75,
    "volute-left.svg": 12, "note.svg": 12, "note-paused.svg": 12,
    "patera.svg": 28,
}

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
    heaven = {"opacity": 0.55, "height_px": 220, "fps": 10, "drift_px_per_s": 14,
              "animate": True, "pause_on_battery": True,
              "full_below": 0.05, "off_above": 0.14, **settings.get("heaven", {})}
    for key in ("opacity", "height_px", "fps", "drift_px_per_s"):
        value = heaven[key]
        if (isinstance(value, bool) or not isinstance(value, (int, float))
                or not math.isfinite(value) or value < 0
                or (key == "opacity" and value > 1) or (key == "fps" and value < 1)):
            raise ValueError(f"glow.json: invalid heaven.{key}")
    if not 0 <= heaven["full_below"] < heaven["off_above"] <= 1:
        raise ValueError("glow.json: heaven.full_below must be below heaven.off_above")
    for key in ("animate", "pause_on_battery"):
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
    rules = [f"@define-color box-background {dark};\n",
             f"@define-color decoration-bright {bright};\n"]
    for selector, filename in DECORATIONS:
        source = ROOT.parent / "wallust/assets" / filename
        # Icons on opaque plates stay in the bright ink; the rest use dark ink.
        boxed_icon = filename in ("volute-left.svg", "note.svg", "note-paused.svg")
        variant, paint = ("bright", bright) if boxed_icon else ("dark", dark)
        target = output / f"{Path(filename).stem}-{variant}.png"
        render(source, target, paint)
        rules.append(f'{selector} {{\n    background-image: url("{target.as_uri()}");\n}}\n')
    # glow.qml reads this file and repaints when it changes. Colors are the muted
    # bright ink plus two palette accents already lightened by the template.
    state = {
        "opacity": heaven["opacity"], "height": heaven["height_px"], "fps": heaven["fps"],
        "drift": heaven["drift_px_per_s"], "animate": heaven["animate"],
        "pause_on_battery": heaven["pause_on_battery"],
        "outputs": top_light_factors(heaven),
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
        "/* Generated from waybar/glow.json; edit that file to tune the glow. */\n"
        + "\n".join(rules)
    )


if __name__ == "__main__":
    main()
