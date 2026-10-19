#!/usr/bin/env python3
"""Render dark Waybar decorations over a soft Wallust-colored glow.

Source SVG geometry stays unchanged. Generated SVGs and absolute CSS URLs live
under waybar/wallust and are rebuilt on wallpaper refresh and Waybar startup.
"""
from pathlib import Path
from copy import deepcopy
import json
import math
import subprocess
import re
import xml.etree.ElementTree as ET

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
    ("#mpris", "note.svg"),
    ("#mpris.paused", "note-paused.svg"),
    ("#custom-patera", "patera.svg"),
)
DISPLAY_HEIGHTS = {
    "angels-left.svg": 30, "angels.svg": 30,
    "ornaments-left.svg": 28, "ornaments-right.svg": 28,
    "volute-left.svg": 20, "note.svg": 17, "note-paused.svg": 17,
    "patera.svg": 14,
}

DISPLAY_WIDTHS = {
    "angels-left.svg": 97.5, "angels.svg": 97.5,
    "ornaments-left.svg": 75, "ornaments-right.svg": 75,
    "volute-left.svg": 12, "note.svg": 12, "note-paused.svg": 12,
    "patera.svg": 14,
}


def glowing(source, target, glow_color, settings):
    root = ET.parse(source).getroot()
    if source.name in ("ornaments-left.svg", "ornaments-right.svg"):
        # Flip only the rendered ornaments, including their glow, in place.
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
    root.set("fill", "#0A0A0E")
    for element in root.iter():
        for paint in ("fill", "stroke"):
            value = element.get(paint)
            if value and value.lower() not in ("none", "transparent"):
                element.set(paint, "#0A0A0E")
    if glow_color:
        add_glow(root, DISPLAY_HEIGHTS[source.name], glow_color, settings)
    # Rasterize the authored SVG at 3x display resolution. GTK then only loads
    # a small PNG; the Gaussian blur is computed once per palette refresh.
    x, y, width, view_height = map(float, root.get("viewBox").split())
    height = DISPLAY_HEIGHTS[source.name]
    # Eight screen pixels contain the expanded mask and its soft fade.
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


def add_glow(root, height, color, settings):
    """Expand one union mask before blurring, supporting fine details evenly."""
    view_height = float(root.get("viewBox").split()[3])
    unit = view_height / height
    artwork = [child for child in root
               if child.tag.rsplit("}", 1)[-1] not in ("defs", "metadata", "title", "desc")]
    defs = ET.SubElement(root, f"{{{SVG}}}defs")
    effect = ET.SubElement(defs, f"{{{SVG}}}filter", {
        "id": "soft-glow", "x": "-30%", "y": "-50%",
        "width": "160%", "height": "200%", "color-interpolation-filters": "sRGB",
    })
    # SourceAlpha is the composite silhouette, rather than a glow per path.
    # Dilation widens thin feathers and merges nearby details at full opacity,
    # so overlapping shapes cannot add separate light contributions.
    ET.SubElement(effect, f"{{{SVG}}}feMorphology", {
        "in": "SourceAlpha", "operator": "dilate",
        "radius": str(unit * settings["expansion_px"]), "result": "expanded-mask",
    })
    ET.SubElement(effect, f"{{{SVG}}}feGaussianBlur", {
        "in": "expanded-mask", "stdDeviation": str(unit * settings["blur_px"]),
        "result": "soft-mask",
    })
    ET.SubElement(effect, f"{{{SVG}}}feFlood", {
        "flood-color": color, "result": "palette",
    })
    ET.SubElement(effect, f"{{{SVG}}}feComposite", {
        "in": "palette", "in2": "soft-mask", "operator": "in",
    })
    glow = ET.Element(f"{{{SVG}}}g", {
        "fill": color, "opacity": str(settings["opacity"]), "filter": "url(#soft-glow)",
    })
    for child in artwork:
        copy = deepcopy(child)
        for element in copy.iter():
            element.attrib.pop("id", None)
            for paint in ("fill", "stroke"):
                if element.get(paint, "none") != "none":
                    element.set(paint, color)
        glow.append(copy)
    root.insert(0, glow)


def main():
    settings = json.loads((ROOT / "glow.json").read_text())
    for section, keys in (("decorations", ("expansion_px", "blur_px", "opacity")),
                          ("boxes", ("blur_px", "opacity"))):
        for key in keys:
            value = settings[section][key]
            if (isinstance(value, bool) or not isinstance(value, (int, float))
                    or not math.isfinite(value) or value < 0
                    or (key == "opacity" and value > 1)):
                raise ValueError(f"glow.json: invalid {section}.{key}")
    palette = ROOT / "wallust/colors-waybar.css"
    colors = dict(re.findall(r"@define-color\s+(\w+)\s+(#[0-9a-fA-F]{6})\s*;",
                             palette.read_text() if palette.exists() else ""))
    color = colors.get("foreground")
    output = ROOT / "wallust/glowing"
    output.mkdir(parents=True, exist_ok=True)
    rules = []
    for selector, filename in DECORATIONS:
        source = ROOT / "assets" / filename
        target = output / Path(filename).with_suffix(".png")
        glowing(source, target, color, settings["decorations"])
        rules.append(f'{selector} {{\n    background-image: url("{target.as_uri()}");\n}}\n')
    boxes = settings["boxes"]
    rules.append(
        "#window, #mpris, #workspaces, #clock,\n"
        "#custom-swaync, #tray, #temperature, #network,\n"
        "#pulseaudio, #battery, #custom-power {\n"
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
