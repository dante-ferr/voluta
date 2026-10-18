#!/usr/bin/env python3
"""Tint Waybar decorations with Wallust and add a compact dark shadow.

Source SVG geometry stays unchanged. Generated SVGs and absolute CSS URLs live
under waybar/wallust and are rebuilt on wallpaper refresh and Waybar startup.
"""
from pathlib import Path
from copy import deepcopy
import math
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


def muted_color(foreground, background):
    """Use an opaque, subdued palette tint rather than bright text color."""
    channels = [round(int(foreground[i:i+2], 16) * 0.7
                      + int(background[i:i+2], 16) * 0.3)
                for i in (1, 3, 5)]
    return "#" + "".join(f"{channel:02x}" for channel in channels)


def tinted(source, target, color):
    root = ET.parse(source).getroot()
    # Preserve negative space, existing icon strokes and all transforms.
    # Change only explicit paint colors; filled shapes otherwise default black.
    root.set("fill", color)
    for element in root.iter():
        for paint in ("fill", "stroke"):
            value = element.get(paint)
            if value and value.lower() not in ("none", "transparent"):
                element.set(paint, color)
    add_shadow(root, DISPLAY_HEIGHTS[source.name])
    ET.ElementTree(root).write(target, encoding="utf-8", xml_declaration=True)


def add_shadow(root, height):
    """Layer soft dark silhouettes without runtime SVG blur filters.

    A broad faint edge and tighter darker core approximate a small blur at
    bar size. Compensate for local SVG scaling so mirrored art looks alike.
    """
    x, y, width, view_height = map(float, root.get("viewBox").split())
    unit = view_height / height
    # Keep the source viewport: padding rescales the artwork and pulls its
    # attachment edge away from the adjacent Waybar box.
    artwork = [child for child in root
               if child.tag.rsplit("}", 1)[-1] not in ("defs", "metadata", "title", "desc")]

    def darken(element, radius, scale=1.0, inherited_width=0.0):
        for args in re.findall(r"scale\(([^)]+)\)", element.get("transform", "")):
            values = [float(v) for v in re.split(r"[ ,]+", args.strip())]
            scale *= math.sqrt(abs(values[0] * values[-1]))
        original_width = float(element.get("stroke-width", inherited_width))
        element.attrib.pop("id", None)
        for paint in ("fill", "stroke"):
            if element.get(paint, "none") != "none":
                element.set(paint, "#08080c")
        if element.tag.rsplit("}", 1)[-1] == "path":
            element.set("stroke", "#08080c")
            element.set("stroke-width", str(original_width + 2 * radius / scale))
            element.set("stroke-linejoin", "round")
            element.set("stroke-linecap", "round")
        for child in element:
            darken(child, radius, scale, original_width)

    shadow = ET.Element(f"{{{SVG}}}g", {
        "fill": "#08080c", "transform": f"translate(0 {unit * 0.35})",
    })
    for radius, opacity in ((1.0, 0.12), (0.65, 0.22), (0.3, 0.38)):
        layer = ET.SubElement(shadow, f"{{{SVG}}}g", {"opacity": str(opacity)})
        for child in artwork:
            copy = deepcopy(child)
            darken(copy, radius * unit)
            layer.append(copy)
    root.insert(0, shadow)


def main():
    palette = ROOT / "wallust/colors-waybar.css"
    colors = dict(re.findall(r"@define-color\s+(\w+)\s+(#[0-9a-fA-F]{6})\s*;",
                             palette.read_text() if palette.exists() else ""))
    color = (muted_color(colors["foreground"], colors["background"])
             if {"foreground", "background"} <= colors.keys() else None)
    output = ROOT / "wallust/shadowed"
    output.mkdir(parents=True, exist_ok=True)
    rules = []
    for selector, filename in DECORATIONS:
        source = ROOT / "assets" / filename
        target = source
        if color:
            target = output / filename
            tinted(source, target, color)
        rules.append(f'{selector} {{\n    background-image: url("{target.as_uri()}");\n}}\n')
    (ROOT / "wallust/angel-paths.css").write_text("\n".join(rules))


if __name__ == "__main__":
    main()
