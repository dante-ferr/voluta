#!/usr/bin/env python3
"""Render palette variants and wallpaper samples for adaptive decorations.

Source SVG geometry stays unchanged. Generated SVGs and absolute CSS URLs live
under wallust/assets/generated/waybar; rebuilt on wallpaper refresh and startup.
"""
from pathlib import Path
from copy import deepcopy
import json
import math
import subprocess
import re
import xml.etree.ElementTree as ET
import configparser
import os
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


def glowing(source, target, glow_color, settings, paint):
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
    root.set("fill", paint)
    for element in root.iter():
        for paint in ("fill", "stroke"):
            value = element.get(paint)
            if value and value.lower() not in ("none", "transparent"):
                element.set(paint, root.get("fill"))
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


def query(command):
    try:
        return subprocess.check_output(command, text=True, stderr=subprocess.DEVNULL,
                                       timeout=3)
    except (OSError, subprocess.SubprocessError):
        return ""


def wallpaper_image(path, size, resize="crop", background="#ffffff",
                    gravity="center", image_filter="Lanczos3"):
    """Reconstruct awww's output canvas before selecting the actual bar region.

    awww resizes the decoded raster without applying EXIF orientation. Crop
    gravity is a centering fraction in fast_image_resize's fit_into_destination.
    Keep native output pixels: reducing to logical pixels would blend colors
    before the bar-wide darkness coverage is measured.
    """
    anchors = {"center": (.5, .5), "top-left": (0, 0), "top": (.5, 0),
               "top-right": (1, 0), "left": (0, .5), "right": (1, .5),
               "bottom-left": (0, 1), "bottom": (.5, 1), "bottom-right": (1, 1)}
    filters = {"Nearest": Image.Resampling.BOX, "Bilinear": Image.Resampling.BILINEAR,
               "CatmullRom": Image.Resampling.BICUBIC, "Mitchell": Image.Resampling.BICUBIC,
               "Lanczos3": Image.Resampling.LANCZOS}
    sampling = filters[image_filter]
    with Image.open(path) as source:
        source = source.convert("RGB")
        if resize in ("crop", "stretch"):
            image = (ImageOps.fit(source, size, sampling, centering=anchors[gravity])
                     if resize == "crop" else source.resize(size, sampling))
        elif resize in ("fit", "no"):
            image = Image.new("RGB", size, background)
            if resize == "fit":
                scale = min(size[0] / source.width, size[1] / source.height)
                source = source.resize((max(1, int(source.width * scale)),
                                        max(1, int(source.height * scale))), sampling)
            # awww uses integer division for centered padding/cropping.
            offset = tuple((dest - src) // 2 if dest >= src else -((src - dest) // 2)
                           for dest, src in zip(size, source.size))
            image.paste(source, offset)
        else:
            raise ValueError(f"unsupported wallpaper placement: {resize}")
        return image


def cached_placement(daemon, output, image_path):
    """Read awww's versioned namespace/resize/filter/path cache, if it matches."""
    if daemon != "awww":
        return None
    root = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / daemon
    candidates = sorted(root.glob(f"*/{output}"), key=lambda p: p.stat().st_mtime, reverse=True)
    for path in candidates:
        try:
            fields = path.read_bytes().decode("utf-8").split("\0")
        except (OSError, UnicodeError):
            continue
        for start in range(0, len(fields) - 3, 4):
            namespace, resize, image_filter, saved_path = fields[start:start+4]
            if namespace or saved_path != image_path:
                continue
            method, _, gravity = resize.partition(":")
            return method, gravity or "center", image_filter
    return None


def write_contrast_cache(output, thresholds):
    config = configparser.ConfigParser(interpolation=None)
    config["assets"] = {"directory": str(output)}
    config["contrast"] = {name: str(value) for name, value in thresholds.items()}
    settings = configparser.ConfigParser(interpolation=None)
    settings.read(Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
                  / "waypaper/config.ini")
    # Installed Waypaper maps stretch to crop and tile to no-resize for awww/swww.
    resize = {"fill": "crop", "fit": "fit", "center": "no", "stretch": "crop", "tile": "no"}[
        settings.get("Settings", "fill", fallback="fill").lower()]
    background = settings.get("Settings", "color", fallback="#ffffff")
    try:
        monitors = json.loads(query(["hyprctl", "-j", "monitors"]) or "[]")
    except ValueError:
        monitors = []
    wallpapers = {}
    for daemon in ("awww", "swww"):
        for line in query([daemon, "query"]).splitlines():
            match = re.search(r"(?:^|: )([^:]+): (\d+)x(\d+), scale: ([\d.]+), .*image: (.*)$", line)
            if match:
                wallpapers[match[1]] = (match[5], int(match[2]), int(match[3]), float(match[4]))
        if wallpapers:
            break
    for monitor in monitors:
        live = wallpapers.get(monitor["name"])
        if not live:
            continue
        path, logical_width, logical_height, daemon_scale = live
        # Query dimensions are already oriented logical output dimensions.
        # awww's real_dim rounds fractional scales to the nearest native pixel.
        width = math.floor(logical_width * daemon_scale + .5)
        height = math.floor(logical_height * daemon_scale + .5)
        size = (logical_width, logical_height)
        key = f'monitor:{monitor["x"]}:{monitor["y"]}:{size[0]}:{size[1]}'
        target = ROOT / "wallust" / f'wallpaper-{monitor["name"]}.png'
        method, gravity, image_filter = cached_placement(daemon, monitor["name"], path) or (
            resize, "center", settings.get("Settings", "swww_filter", fallback="Lanczos3"))
        try:
            wallpaper_image(path, (width, height), method, background, gravity, image_filter).save(target)
        except (OSError, ValueError, KeyError) as error:
            print(f"Waybar contrast: {error}; keeping dark artwork", flush=True)
            continue
        config[key] = {"image": str(target), "output": monitor["name"],
                       "namespace": f"{daemon}-daemon", "source": path,
                       "resize": method, "gravity": gravity, "filter": image_filter}
    with (ROOT / "wallust/contrast.ini").open("w") as handle:
        config.write(handle)


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
    for name in ("dark_luminance", "dark_coverage"):
        value = settings["contrast"][name]
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not 0 < value <= 1:
            raise ValueError(f"glow.json: invalid contrast.{name}")
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
    if not {"foreground", "color0"}.issubset(colors):
        print("Waybar contrast: no Wallust palette yet; keeping existing assets")
        return
    color = colors.get("foreground")
    output = ROOT.parent / "wallust/assets/generated/waybar"
    output.mkdir(parents=True, exist_ok=True)
    def brightness(value):
        return sum(weight * int(value[i:i+2], 16) for weight, i in
                   ((.2126, 1), (.7152, 3), (.0722, 5)))
    bright_name = max(("foreground", "color15") if "color15" in colors else ("foreground",),
                      key=lambda name: brightness(colors[name]))
    # Mute both light variants toward Wallust's dark ink, without changing
    # opacity or introducing a halo. Keep sampler colors identical to the PNGs.
    def muted(paint):
        dark = colors["color0"]
        return "#" + "".join(f"{round(int(paint[i:i+2], 16) * .8 + int(dark[i:i+2], 16) * .2):02x}"
                              for i in (1, 3, 5))
    accent = colors.get("color12", colors["foreground"])
    accent = "#" + "".join(f"{round(int(accent[i:i+2], 16) * .75 + 255 * .25):02x}"
                             for i in (1, 3, 5))
    accent, bright = muted(accent), muted(colors[bright_name])
    rules = [f"@define-color decoration-light {accent};\n",
             f"@define-color decoration-bright {bright};\n"]
    for selector, filename in DECORATIONS:
        source = ROOT.parent / "wallust/assets" / filename
        stem = Path(filename).stem
        for variant, paint in (("dark", colors["color0"]), ("light", accent), ("bright", bright)):
            target = output / f"{stem}-{variant}.png"
            glowing(source, target, color if variant == "dark" else None,
                    settings["decorations"], paint)
            # A class on the bar selects every decoration together.
            selectors = selector.split(",\n")
            decorated = ",\n".join(f"window#waybar.decoration-{variant} {s}" for s in selectors)
            if variant == "dark":
                decorated = selector + ",\n" + decorated
            rules.append(f'{decorated} {{\n    background-image: url("{target.as_uri()}");\n}}\n')
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
    write_contrast_cache(output, settings["contrast"])


if __name__ == "__main__":
    main()
