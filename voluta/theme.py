"""Resolve the rice's shared background and publish it to generated app palettes."""

import argparse
import json
import os
from pathlib import Path
import re
import tempfile

from cli import config_home, hostname, resolve


def read_palette(path):
    return {key: tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))
            for key, value in re.findall(r"^wc_(\w+)='([0-9a-fA-F]{6})'\s*$", path.read_text(), re.M)}


def background_policy(palette, directory=None, host=None):
    settings, _ = resolve(directory if directory is not None else config_home(), hostname(host))
    policy = settings["appearance"]["background"]
    token = policy["source"]
    key = "source_bg" if token == "background" and "source_bg" in palette else "bg" if token == "background" else token[5:]
    if key not in palette:
        raise ValueError(f"palette has no background source {token}")
    return palette[key], policy["darken"]


def preferred_background(palette, directory=None, host=None):
    source, darken = background_policy(palette, directory, host)
    return tuple(round(channel * (1 - darken)) for channel in source)


def write_changed(path, text):
    if path.exists() and path.read_text() == text:
        return False
    # Generated application files may be symlinked into the deployed tree.
    destination = path.resolve() if path.is_symlink() else path
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", dir=destination.parent, delete=False) as handle:
        temporary = Path(handle.name)
        handle.write(text)
    try:
        temporary.replace(destination)
    finally:
        temporary.unlink(missing_ok=True)
    return True


def publish(config=None, cache=None, directory=None, host=None):
    config = config or Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    cache = cache or Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
    shell = config / "hypr/wallust/colors-shell.sh"
    palette = read_palette(shell)
    source, darken = background_policy(palette, directory or config / "voluta", host)
    background = tuple(round(channel * (1 - darken)) for channel in source)
    color = "#" + "".join(f"{channel:02x}" for channel in background)
    source_color = "#" + "".join(f"{channel:02x}" for channel in source)
    rgb = ",".join(map(str, background))
    changed = False

    def edit(relative, transform):
        nonlocal changed
        path = config / relative
        if path.is_file():
            changed = write_changed(path, transform(path.read_text())) or changed

    def shell_colors(text):
        if "source_bg" not in palette:
            text = re.sub(r"^wc_bg=", f"wc_source_bg='{''.join(f'{c:02x}' for c in palette['bg'])}'\nwc_bg=", text, flags=re.M)
        return re.sub(r"^wc_bg='[0-9a-fA-F]{6}'", f"wc_bg='{color[1:]}'", text, flags=re.M)

    edit("hypr/wallust/colors-shell.sh", shell_colors)
    for relative in ("waybar/wallust/colors-waybar.css", "swaync/wallust/colors-swaync.css", "wlogout/wallust/colors-wlogout.css", "hypr/wallust/colors-gtk.css"):
        def css(text):
            text = re.sub(r"(@define-color\s+(?:background|imperium_bg)\s+)#[0-9a-fA-F]{6}(\s*;)", lambda m: m[1] + color + m[2], text)
            return re.sub(r"(@define-color\s+(?:background-alt|veil)\s+rgba\()[^,]+,[^,]+,[^,]+,", lambda m: m[1] + rgb + ",", text)
        edit(relative, css)
    kitty_keys = "background|cursor_text_color|active_tab_background|inactive_tab_background|tab_bar_background|tab_bar_margin_color"
    edit("kitty/kitty-themes/01-Wallust.conf", lambda text: re.sub(rf"^({kitty_keys})(\s+)#[0-9a-fA-F]{{6}}", lambda m: m[1] + m[2] + color, text, flags=re.M))
    edit("hypr/wallust/wallust-hyprland.conf", lambda text: re.sub(r"^(\$background\s*=\s*rgb\()[0-9a-fA-F]{6}(\))", lambda m: m[1] + color[1:] + m[2], text, flags=re.M))
    rofi_keys = "normal-background|alternate-normal-background|alternate-urgent-background|background-color"
    def rofi(text):
        text = re.sub(rf"^({rofi_keys})(\s*:\s*)#[0-9a-fA-F]{{6}}", lambda m: m[1] + m[2] + color, text, flags=re.M)
        return re.sub(r"^(background\s*:\s*rgba\()[^,]+,[^,]+,[^,]+,", lambda m: m[1] + rgb + ",", text, flags=re.M)
    edit("rofi/wallust/colors-rofi.rasi", rofi)
    def quickshell(text):
        data = json.loads(text)
        data["windowBackground"] = color
        return json.dumps(data, indent=4) + "\n"
    edit("quickshell/qml_color.json", quickshell)
    # Wallust writes the extracted background. Replace that hex only, so the accent stays put
    # and a later refresh cannot darken the resolved base a second time. Karere also paints
    # from --WDS-*-RGB triplets, so those must move with the hex.
    source_rgb = ",".join(map(str, source))
    def replace_background(text):
        text = re.sub(re.escape(source_color), color, text, flags=re.IGNORECASE)
        return text.replace(source_rgb, rgb)
    edit("limusic/matugen.css", lambda text: re.sub(re.escape(source_color), color, text, flags=re.IGNORECASE))
    edit("karere/custom.css", replace_background)
    edit("gtk-4.0/gtk.css", lambda text: re.sub(re.escape(source_color), color, text, flags=re.IGNORECASE))
    edit("gtk-3.0/gtk.css", lambda text: re.sub(re.escape(source_color), color, text, flags=re.IGNORECASE))

    source = palette.get("source_bg", palette["bg"])
    generated = cache / "voluta"
    write_changed(generated / "theme.json", json.dumps({"version": 1, "background": color, "background_rgb": background, "source_background": "#" + "".join(f"{c:02x}" for c in source)}, indent=2) + "\n")
    write_changed(generated / "theme.css", f"@define-color voluta_background {color};\n")
    write_changed(generated / "theme.sh", f"voluta_bg='{color[1:]}'\nvoluta_bg_rgb='{rgb}'\n")
    from surfaces import publish as publish_surfaces
    publish_surfaces(config=config, directory=directory or config / "voluta", host=host)
    return changed


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args()
    try:
        publish()
    except (OSError, ValueError, KeyError) as error:
        parser.exit(1, f"Voluta theme: {error}\n")
