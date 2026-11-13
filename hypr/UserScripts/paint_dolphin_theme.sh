#!/usr/bin/env bash
# paint_dolphin_theme.sh — Recolor Dolphin's Qt stack from the wallust palette.
#
# Dolphin follows qt6ct + Kvantum + the KDE color scheme. This writes those
# three from the current wallpaper colors and points Kvantum at the Imperium
# theme. Soft corners and the Oxanium UI font are applied in the QSS layer;
# the embedded terminal keeps Monaspace Argon.
set +m

_rice_paths="$HOME/.config/hypr/UserScripts/lib/rice_paths.sh"
[[ -r $_rice_paths ]] || _rice_paths="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/rice_paths.sh"
# shellcheck source=lib/rice_paths.sh
source "$_rice_paths"

root=$(imperium_rice_root) || exit 0
# Generic Qt colors remain core; advanced Dolphin mutations are optional.
dolphin_enabled=false
python3 "$root/voluta/cli.py" enabled dolphin --legacy && dolphin_enabled=true
colors="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/wallust/colors-shell.sh"

exec python3 - "$root" "$colors" "$HOME" "$dolphin_enabled" <<'PY'
import json
import os
import re
import select
import signal
import subprocess
import sys
import time
import urllib.parse
import zlib
import xml.etree.ElementTree as ET

root, colors_path, home = sys.argv[1:4]
dolphin_enabled = len(sys.argv) <= 4 or sys.argv[4] == "true"
sys.path.insert(0, os.path.join(root, "voluta"))
from theme import preferred_background

def parse_hex(value):
    value = value.strip().lstrip("#")
    if len(value) != 6:
        return None
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))

def load_palette():
    found = {}
    if os.path.isfile(colors_path):
        with open(colors_path, encoding="utf-8") as handle:
            for line in handle:
                match = re.match(r"wc_(\w+)='([0-9A-Fa-f]{6})'", line.strip())
                if match:
                    found[match.group(1)] = parse_hex(match.group(2))
    if "bg" in found and "fg" in found and "1" in found:
        return found
    fallback = os.path.join(root, "wallust", "colorschemes", "imperium.json")
    if not os.path.isfile(fallback):
        return None
    with open(fallback, encoding="utf-8") as handle:
        data = json.load(handle)
    mapped = {
        "bg": parse_hex(data["background"]),
        "fg": parse_hex(data["foreground"]),
        "15": parse_hex(data["color15"]),
    }
    for index in range(0, 15):
        mapped[str(index)] = parse_hex(data[f"color{index}"])
    return mapped

def clamp(channel):
    return max(0, min(255, int(round(channel))))

def mix(a, b, amount):
    return tuple(clamp(a[i] * (1 - amount) + b[i] * amount) for i in range(3))

def lighten(color, amount):
    return mix(color, (255, 255, 255), amount)

def darken(color, amount):
    return mix(color, (0, 0, 0), amount)

def channel(unit):
    if unit <= 0.04045:
        return unit / 12.92
    return ((unit + 0.055) / 1.055) ** 2.4

def luminance(color):
    r, g, b = (channel(c / 255) for c in color)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b

def contrast(a, b):
    lighter = max(luminance(a), luminance(b))
    darker = min(luminance(a), luminance(b))
    return (lighter + 0.05) / (darker + 0.05)

def readable(color, against, minimum=7.0):
    if contrast(color, against) >= minimum:
        return color
    # Find the smallest adjustment that meets the contrast floor. Choosing
    # either black or white also handles unexpectedly light wallpapers.
    target = max(((0, 0, 0), (255, 255, 255)), key=lambda c: contrast(c, against))
    low, high = 0.0, 1.0
    for _ in range(24):
        amount = (low + high) / 2
        if contrast(mix(color, target, amount), against) >= minimum:
            high = amount
        else:
            low = amount
    return mix(color, target, high)

def hx(color):
    return f"{color[0]:02x}{color[1]:02x}{color[2]:02x}"

def rgb(color, alpha=None):
    if alpha is None:
        return f"{color[0]},{color[1]},{color[2]}"
    return f"{color[0]},{color[1]},{color[2]},{alpha}"

def argb(color, alpha="ff"):
    return f"#{alpha}{hx(color)}"

palette = load_palette()
if not palette:
    sys.exit(0)

bg = preferred_background(palette)
fg = palette["fg"]
# Every application derives its base from the same Voluta background policy.
# Dolphin keeps its own opacity; the underlying RGB is shared.
dolphin_bg = bg
accent_src = palette.get("1") or fg
secondary_src = palette.get("2") or accent_src
negative_src = palette.get("3") or accent_src

# Keep the wallpaper hues. A fixed lift toward white made every dark
# wallpaper collapse to the same surface and ivory text.
mantle = bg
base = mix(bg, fg, 0.07)
surface0 = mix(bg, fg, 0.11)
accent = accent_src
while contrast(accent, mantle) < 2.4 and luminance(accent) < 0.5:
    accent = lighten(accent, 0.07)
secondary = secondary_src
while contrast(secondary, mantle) < 2.2 and luminance(secondary) < 0.5:
    secondary = lighten(secondary, 0.07)
negative = negative_src
while contrast(negative, mantle) < 2.2 and luminance(negative) < 0.5:
    negative = lighten(negative, 0.07)
text = fg
if contrast(text, mantle) < 4.5:
    text = readable(text, mantle, 4.5)
muted = mix(text, mantle, 0.38)
while contrast(muted, mantle) < 3.5:
    muted = lighten(muted, 0.05)
alternate = mix(mantle, text, 0.06)
hover = mix(mantle, accent, 0.34)
select_bg = mix(mantle, accent, 0.50)
selection_text = text if contrast(text, select_bg) >= 4.5 else readable(text, select_bg, 4.5)
surface1 = mix(surface0, accent, 0.35)
surface2 = muted
link = lighten(accent, 0.12)
icon_accent = accent
while contrast(icon_accent, mantle) < 3.0 and luminance(icon_accent) < 0.55:
    icon_accent = lighten(icon_accent, 0.08)
shadow = darken(bg, 0.4)

tokens = {
    "@@MANTLE@@": hx(mantle),
    "@@BASE@@": hx(base),
    "@@ALT@@": hx(alternate),
    "@@SURFACE0@@": hx(surface0),
    "@@SURFACE1@@": hx(surface1),
    "@@SURFACE2@@": hx(surface2),
    "@@TEXT@@": hx(text),
    "@@SELECT_BG@@": hx(select_bg),
    "@@SELECT_TEXT@@": hx(selection_text),
    "@@ACCENT@@": hx(accent),
    "@@NEGATIVE@@": hx(negative),
    "@@SECONDARY@@": hx(secondary),
    "@@LINK@@": hx(link),
}

template_dir = os.path.join(root, "kvantum")
svg_in = os.path.join(root, "wallust", "assets", "imperium.svg.in")
kv_in = os.path.join(template_dir, "imperium.kvconfig.in")
if not (os.path.isfile(svg_in) and os.path.isfile(kv_in)):
    sys.exit(0)

def fill(path, overrides=None):
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    for token, value in (tokens | (overrides or {})).items():
        text = text.replace(token, "#" + value)
    return text

theme_dir = os.path.join(home, ".config", "Kvantum", "imperium")
os.makedirs(theme_dir, exist_ok=True)
shared_svg_dir = os.path.join(home, ".config", "wallust", "assets", "generated")
os.makedirs(shared_svg_dir, exist_ok=True)
shared_imperium_svg = os.path.join(shared_svg_dir, "kvantum-imperium.svg")
with open(shared_imperium_svg, "w", encoding="utf-8") as handle:
    handle.write(fill(svg_in))
installed_svg = os.path.join(theme_dir, "imperium.svg")
if os.path.lexists(installed_svg):
    os.remove(installed_svg)
os.symlink(shared_imperium_svg, installed_svg)
filled_kv = fill(kv_in)
with open(os.path.join(theme_dir, "imperium.kvconfig"), "w", encoding="utf-8") as handle:
    handle.write(filled_kv)

# Dolphin keeps a compact translucent body. Other Qt apps keep the shared
# Imperium margins.
dolphin_theme = os.path.join(home, ".config", "Kvantum", "dolphin")
os.makedirs(dolphin_theme, exist_ok=True)
# Translucency and the Kitty-like background are Dolphin-only.
dolphin_tokens = {"@@BASE@@": hx(dolphin_bg), "@@MANTLE@@": hx(dolphin_bg)}
dolphin_kv = fill(kv_in, dolphin_tokens).replace("layout_margin=4", "layout_margin=6", 1)
dolphin_kv = dolphin_kv.replace("translucent_windows=false", "translucent_windows=true", 1)
# Percent of opacity removed from the window fill. 30 leaves the file body
# near 70% before the body alpha is applied. Sidebar/toolbar stay denser
# translucent plates on top of that fade.
dolphin_kv = dolphin_kv.replace("reduce_window_opacity=0", "reduce_window_opacity=30", 1)
dolphin_kv = dolphin_kv.replace("splitter_width=7", "splitter_width=0", 1)
with open(os.path.join(dolphin_theme, "dolphin.kvconfig"), "w", encoding="utf-8") as handle:
    handle.write(dolphin_kv)
svg_path = os.path.join(dolphin_theme, "dolphin.svg")
shared_dolphin_svg = os.path.join(shared_svg_dir, "kvantum-dolphin.svg")
with open(shared_dolphin_svg, "w", encoding="utf-8") as handle:
    handle.write(fill(svg_in, dolphin_tokens))
if os.path.lexists(svg_path):
    os.remove(svg_path)
os.symlink(shared_dolphin_svg, svg_path)

# The portal file dialog is a separate process, so it never loads Dolphin's
# hook. Give it the same translucent palette with slightly tighter margins
# than the main window's 6px Kvantum layout.
picker_theme = os.path.join(home, ".config", "Kvantum", "dolphin-picker")
os.makedirs(picker_theme, exist_ok=True)
picker_kv = dolphin_kv.replace("layout_margin=6", "layout_margin=4", 1)
with open(os.path.join(picker_theme, "dolphin-picker.kvconfig"), "w", encoding="utf-8") as handle:
    handle.write(picker_kv)
picker_svg = os.path.join(picker_theme, "dolphin-picker.svg")
if os.path.lexists(picker_svg):
    os.remove(picker_svg)
os.symlink(shared_dolphin_svg, picker_svg)

kvantum_rc = os.path.join(home, ".config", "Kvantum", "kvantum.kvconfig")
if os.path.isfile(kvantum_rc):
    with open(kvantum_rc, encoding="utf-8") as handle:
        rc = handle.read()
else:
    rc = "[General]\ntheme=imperium\n"
if re.search(r"(?m)^theme=", rc):
    rc = re.sub(r"(?m)^theme=.*$", "theme=imperium", rc)
elif "[General]" in rc:
    rc = rc.replace("[General]", "[General]\ntheme=imperium", 1)
else:
    rc = "[General]\ntheme=imperium\n" + rc
if "[Applications]" not in rc:
    rc = rc.rstrip() + "\n\n[Applications]\n"
for app_name, theme_name in (
    ("dolphin", "dolphin"),
    ("org.kde.dolphin", "dolphin"),
    ("xdg-desktop-portal-kde", "dolphin-picker"),
):
    if re.search(rf"(?m)^{re.escape(app_name)}=", rc):
        rc = re.sub(rf"(?m)^{re.escape(app_name)}=.*$", f"{app_name}={theme_name}", rc)
    else:
        rc = rc.rstrip() + f"\n{app_name}={theme_name}"
if not rc.endswith("\n"):
    rc += "\n"
with open(kvantum_rc, "w", encoding="utf-8") as handle:
    handle.write(rc)

roles = [
    text,          # WindowText
    surface0,      # Button
    surface1,      # Light
    surface1,      # Midlight
    mantle,        # Dark
    surface2,      # Mid
    text,          # Text
    text,          # BrightText
    text,          # ButtonText
    mantle,        # Base
    base,          # Window
    shadow,        # Shadow
    select_bg,     # Highlight
    selection_text,# HighlightedText
    link,          # Link
    secondary,     # LinkVisited
    alternate,     # AlternateBase
    text,          # NoRole
    base,          # ToolTipBase
    text,          # ToolTipText
    surface2,      # PlaceholderText
]
active = ", ".join(argb(color) for color in roles)
disabled_roles = list(roles)
disabled_roles[0] = surface2
disabled_roles[6] = surface2
disabled_roles[8] = surface2
disabled_roles[12] = surface1
disabled_roles[13] = surface2
disabled = ", ".join(argb(color) for color in disabled_roles)
inactive_roles = list(roles)
inactive_roles[12] = select_bg
inactive_roles[13] = selection_text
inactive = ", ".join(argb(color) for color in inactive_roles)
# PlaceholderText keeps a half-alpha so empty fields stay quiet.
active_parts = active.split(", ")
active_parts[-1] = argb(surface2, "80")
active = ", ".join(active_parts)

qt_dir = os.path.join(home, ".config", "qt6ct", "colors")
os.makedirs(qt_dir, exist_ok=True)
qt_colors = os.path.join(qt_dir, "Imperium.conf")
with open(qt_colors, "w", encoding="utf-8") as handle:
    handle.write(
        "[ColorScheme]\n"
        f"active_colors={active}\n"
        f"disabled_colors={disabled}\n"
        f"inactive_colors={inactive}\n"
    )

qss_dir = os.path.join(home, ".config", "qt6ct", "qss")
os.makedirs(qss_dir, exist_ok=True)
qss_path = os.path.join(qss_dir, "imperium.qss")
ivory = hx(text)
bg_hex = hx(mantle)
# The wallpaper base is often near-black, so darkening it again does not
# separate the plates. Chrome stays on that dark base; the file body is lifted
# toward the foreground.
chrome = dolphin_bg
body = mix(dolphin_bg, text, 0.16)
# Body stays the clearer glass (~40%). The Places column stays translucent
# too, but denser (75%) so that left pane still reads above the files.
body_alpha = 102
chrome_alpha = 191
# Faint zebra: a soft lift toward the text, mostly clear.
stripe = mix(body, text, 0.06)
stripe_alpha = 40
chrome_hex = hx(chrome)
chrome_rgba = f"rgba({rgb(chrome)}, {chrome_alpha})"
body_hex = hx(body)
alt_hex = hx(alternate)
stripe_rgba = f"rgba({rgb(stripe)}, {stripe_alpha})"
sel_hex = hx(select_bg)
sel_fg = hx(selection_text)
hover_hex = hx(hover)
edge = hx(mix(accent, chrome, 0.38))
panel = hx(base)
quiet = hx(muted)
# Shared artwork stays outside Dolphin's private configuration. Repaint it
# from the same readable palette before publishing the live refresh marker.
asset_dir = os.path.join(home, ".config", "wallust", "assets", "generated")
os.makedirs(asset_dir, exist_ok=True)
ET.register_namespace("", "http://www.w3.org/2000/svg")
# Match the shared Wallust artwork when its rendered palette is available.
corner_ink = "#" + hx(darken(fg, 0.30))
notification_palette = os.path.join(home, ".config", "swaync", "wallust", "colors-swaync.css")
if os.path.isfile(notification_palette):
    with open(notification_palette, encoding="utf-8") as handle:
        match = re.search(r"@define-color\s+corner-ornament\s+(#[0-9A-Fa-f]{6})\s*;", handle.read())
    if match:
        corner_ink = match.group(1)
for source_name, output_name, size in (
    ("big-corner-tl.svg", "big-corner-tl.svg", (64, 64)),
    ("ornaments.svg", "dolphin-ornaments.svg", (64, 16)),
):
    artwork = ET.parse(os.path.join(root, "wallust", "assets", source_name))
    svg = artwork.getroot()
    svg.set("width", str(size[0]))
    svg.set("height", str(size[1]))
    for element in svg.iter():
        for paint in ("fill", "stroke"):
            value = element.get(paint)
            if value and value not in ("none", "transparent"):
                element.set(paint, corner_ink if source_name == "big-corner-tl.svg" else "#" + hx(mix(text, mantle, 0.30)))
    artwork.write(os.path.join(asset_dir, output_name), encoding="unicode")
ornament_url = os.path.join(asset_dir, "dolphin-ornaments.svg").replace("\\", "/")
with open(qss_path, "w", encoding="utf-8") as handle:
    handle.write(f"""
DolphinMainWindow {{
    background-color: rgba({rgb(body)}, {body_alpha});
    color: #{ivory};
    padding: 6px;
}}
DolphinMainWindow QToolBar {{
    background-color: {chrome_rgba};
    border: none;
    padding: 3px 8px;
    spacing: 3px;
    margin: 0px;
}}
DolphinMainWindow QStatusBar {{
    background-color: {chrome_rgba};
    color: #{quiet};
    border: none;
    padding: 3px 10px;
    margin: 0px;
}}
DolphinMainWindow QDockWidget {{
    background-color: {chrome_rgba};
    color: #{ivory};
    border: none;
    titlebar-close-icon: none;
    margin: 0px;
    padding: 0px;
}}
DolphinMainWindow::separator {{
    background-color: transparent;
    width: 0px;
    height: 0px;
}}
DolphinMainWindow QSplitter::handle {{
    background-color: transparent;
    width: 0px;
    height: 0px;
}}
DolphinMainWindow QDockWidget#placesDock {{
    margin-right: 0px;
    padding-right: 0px;
    background-color: {chrome_rgba};
}}
DolphinMainWindow QWidget#imperiumPlacesPlate {{
    background-color: {chrome_rgba};
}}
DolphinMainWindow KFilePlacesView,
DolphinMainWindow KFilePlacesView::viewport {{
    background-color: transparent;
}}
DolphinMainWindow QToolButton {{
    background-color: transparent;
    color: #{ivory};
    border: none;
    border-radius: 6px;
    padding: 4px;
    margin: 0 1px;
}}
DolphinMainWindow QToolButton:hover {{
    background-color: #{hover_hex};
    color: #{ivory};
}}
DolphinMainWindow QDockWidget::title {{
    background-color: {chrome_rgba};
    color: #{quiet};
    font-weight: 600;
    padding: 6px 10px 4px 10px;
    border: none;
}}
DolphinMainWindow QDockWidget#placesDock::title,
DolphinMainWindow QDockWidget#foldersDock::title,
DolphinMainWindow QDockWidget#infoDock::title {{
    background-image: url("{ornament_url}");
    background-repeat: no-repeat;
    background-position: right center;
    padding-right: 64px;
}}
/* Path / breadcrumb strip: same chrome plate as the toolbars. */
DolphinMainWindow UrlNavigator,
DolphinMainWindow KUrlNavigator,
DolphinMainWindow DolphinTabWidget QTabBar {{
    background-color: {chrome_rgba};
    color: #{ivory};
    border: none;
    padding: 2px 6px;
    margin: 0px;
}}
DolphinMainWindow DolphinTabWidget QTabBar::tab {{
    background-color: transparent;
    color: #{quiet};
    border: none;
    border-radius: 6px;
    padding: 4px 10px;
    margin: 2px 1px;
}}
DolphinMainWindow DolphinTabWidget QTabBar::tab:selected,
DolphinMainWindow DolphinTabWidget QTabBar::tab:hover {{
    background-color: #{hover_hex};
    color: #{ivory};
}}
QDockWidget#terminalDock {{
    min-height: 180px;
}}
QDockWidget#terminalDock::title {{
    max-height: 0px;
    padding: 0;
    margin: 0;
    border: none;
}}
TerminalPanel {{
    background-color: transparent;
    color: #{ivory};
    border: none;
    min-height: 160px;
}}
TerminalPanel QWidget {{
    background-color: transparent;
    color: #{ivory};
    border: none;
}}
DolphinStatusBar QLabel {{
    min-width: 200px;
    color: #{quiet};
}}
TerminalPanel QMenuBar, TerminalPanel QToolBar, TerminalPanel QTabBar {{
    max-height: 0px;
    min-height: 0px;
    padding: 0;
    margin: 0;
    border: none;
    background-color: transparent;
}}
TerminalPanel QScrollBar:vertical {{
    width: 0px;
    max-width: 0px;
}}
TerminalPanel QScrollBar:horizontal {{
    height: 0px;
    max-height: 0px;
}}
QTreeView, QListView, QTableView, QColumnView {{
    background-color: #{bg_hex};
    alternate-background-color: {stripe_rgba};
    color: #{ivory};
    selection-background-color: #{sel_hex};
    selection-color: #{sel_fg};
    outline: 0;
    border: none;
    padding: 2px;
}}
DolphinMainWindow QGraphicsView,
DolphinMainWindow KItemListContainer,
DolphinMainWindow QTreeView,
DolphinMainWindow QListView,
DolphinMainWindow QTableView,
DolphinMainWindow QColumnView {{
    background-color: transparent;
    alternate-background-color: {stripe_rgba};
    color: #{ivory};
    border: none;
    padding: 4px;
}}
DolphinMainWindow QHeaderView::section {{
    background-color: #{bg_hex};
    color: #{quiet};
    border: none;
    padding: 5px 10px;
}}
QTreeView::item, QListView::item, QTableView::item {{
    color: #{ivory};
    padding: 3px 10px;
    border-radius: 6px;
    background-color: transparent;
}}
DolphinMainWindow QTreeView::item,
DolphinMainWindow QListView::item {{
    background-color: transparent;
    alternate-background-color: {stripe_rgba};
}}
QTreeView::item:hover, QListView::item:hover, QTableView::item:hover {{
    background-color: #{hover_hex};
    color: #{ivory};
}}
QTreeView::item:selected, QListView::item:selected, QTableView::item:selected,
QTreeView::item:selected:!active, QListView::item:selected:!active, QTableView::item:selected:!active {{
    background-color: #{sel_hex};
    color: #{sel_fg};
}}
DolphinMainWindow KFilePlacesView {{
    background-color: {chrome_rgba};
    qproperty-spacing: 1;
    padding: 2px 0px 4px 4px;
}}
DolphinMainWindow KFilePlacesView::item {{
    color: #{ivory};
    background-color: transparent;
    border-radius: 6px;
    padding: 3px 8px;
    margin: 0px 2px;
}}
DolphinMainWindow KFilePlacesView::item:hover {{
    background-color: #{hover_hex};
    color: #{ivory};
}}
DolphinMainWindow KFilePlacesView::item:selected {{
    background-color: #{sel_hex};
    color: #{sel_fg};
}}
QHeaderView::section {{
    background-color: #{bg_hex};
    color: #{quiet};
    font-weight: 600;
    border: none;
    padding: 5px 10px;
}}
FilterBar {{
    max-height: 0px;
    min-height: 0px;
    margin: 0px;
    padding: 0px;
    border: none;
}}
QToolTip {{
    background-color: #{panel};
    color: #{ivory};
    border: 1px solid #{edge};
    border-radius: 6px;
    padding: 5px 9px;
}}
QMenu {{
    background-color: #{panel};
    color: #{ivory};
    border: 1px solid #{edge};
    border-radius: 8px;
    padding: 4px 6px;
}}
QMenu::item {{
    border-radius: 5px;
    padding: 5px 10px;
}}
QMenu::item:selected {{
    background-color: #{sel_hex};
    color: #{sel_fg};
}}
QMenu::separator {{
    height: 1px;
    margin: 4px 8px;
    background-color: transparent;
}}
QLineEdit, QComboBox {{
    background-color: #{panel};
    color: #{ivory};
    border: 1px solid #{edge};
    border-radius: 6px;
    padding: 4px 8px;
    selection-background-color: #{sel_hex};
    selection-color: #{sel_fg};
}}
QPlainTextEdit, QTextEdit, KTextEdit {{
    background-color: #{panel};
    color: #{ivory};
    border: 1px solid #{edge};
    border-radius: 6px;
    selection-background-color: #{sel_hex};
    selection-color: #{sel_fg};
}}
QTextEdit, KTextEdit {{
    padding: 6px;
}}
/* F2 uses a one-line KTextEdit. Extra padding clips its initial filename
   until textChanged makes Dolphin recalculate the editor's height. */
KItemListRoleEditor {{
    padding: 0px;
    border-radius: 5px;
}}
KMessageWidget {{
    background-color: #{panel};
    color: #{ivory};
    border: 1px solid #{edge};
    border-radius: 6px;
    padding: 6px 10px;
}}
Baloo--FileMetaDataWidget {{
    min-width: 220px;
    color: #{ivory};
}}
""".lstrip())

def ensure_pair(lines, section, key, value):
    text = "".join(lines)
    if f"[{section}]" not in text:
        if text and not text.endswith("\n"):
            text += "\n"
        text += f"[{section}]\n{key}={value}\n"
        return text.splitlines(keepends=True)
    out = []
    in_section = False
    replaced = False
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            if in_section and not replaced:
                out.append(f"{key}={value}\n")
                replaced = True
            in_section = stripped == f"[{section}]"
        if in_section and stripped.startswith(f"{key}="):
            out.append(f"{key}={value}\n")
            replaced = True
            continue
        out.append(line)
    if in_section and not replaced:
        out.append(f"{key}={value}\n")
    return out


qt_conf = os.path.join(home, ".config", "qt6ct", "qt6ct.conf")
# QFont::toString() in Qt 6 uses OpenType weights (Normal=400). A long
# Qt 6 string with legacy weight 50 requests an extremely light font.
# UI chrome uses Oxanium; mono stays on Monaspace for the terminal pane.
font_ui = "Oxanium,11,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,Regular,0,0"
font_mono = "Monaspace Argon,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,Regular,0,0"
font_ui_quoted = '"' + font_ui + '"'
font_mono_quoted = '"' + font_mono + '"'
if os.path.isfile(qt_conf):
    with open(qt_conf, encoding="utf-8") as handle:
        qt_lines = handle.readlines()
else:
    qt_lines = []
# Insert missing Interface keys too. An existing qt6ct.conf without stylesheets
# otherwise silently missed all the generated spacing and toolbar styling.
for section, values in {
    "Appearance": {
        "color_scheme_path": os.path.join(qt_dir, "Imperium.conf"),
        "custom_palette": "true", "icon_theme": "imperium", "style": "kvantum",
    },
    "Fonts": {"fixed": font_mono_quoted, "general": font_ui_quoted},
    "Interface": {"stylesheets": qss_path},
}.items():
    for key, value in values.items():
        qt_lines = ensure_pair(qt_lines, section, key, value)
os.makedirs(os.path.dirname(qt_conf), exist_ok=True)
with open(qt_conf, "w", encoding="utf-8") as handle:
    handle.writelines(qt_lines)

def scheme_group(background, alternate_bg, foreground, background_alpha=None):
    return "\n".join([
        f"BackgroundAlternate={rgb(alternate_bg, background_alpha)}",
        f"BackgroundNormal={rgb(background, background_alpha)}",
        f"DecorationFocus={rgb(icon_accent)}",
        f"DecorationHover={rgb(lighten(icon_accent, 0.1))}",
        f"ForegroundActive={rgb(text)}",
        f"ForegroundInactive={rgb(muted)}",
        f"ForegroundLink={rgb(link)}",
        f"ForegroundNegative={rgb(negative)}",
        f"ForegroundNeutral={rgb(secondary)}",
        f"ForegroundNormal={rgb(foreground)}",
        f"ForegroundPositive={rgb(lighten(secondary, 0.08))}",
        f"ForegroundVisited={rgb(secondary)}",
    ])

scheme = "\n".join([
    "[ColorEffects:Disabled]",
    "Color=112,111,110",
    "ColorAmount=0",
    "ColorEffect=0",
    "ContrastAmount=0.65",
    "ContrastEffect=1",
    "IntensityAmount=0.1",
    "IntensityEffect=2",
    "",
    "[ColorEffects:Inactive]",
    "ChangeSelectionColor=true",
    "Color=112,111,110",
    "ColorAmount=0.025",
    "ColorEffect=2",
    "ContrastAmount=0.1",
    "ContrastEffect=2",
    "Enable=false",
    "IntensityAmount=0",
    "IntensityEffect=0",
    "",
    "[Colors:Button]",
    scheme_group(surface0, surface1, text),
    "",
    "[Colors:Selection]",
    scheme_group(select_bg, hover, selection_text),
    "",
    "[Colors:Tooltip]",
    scheme_group(base, surface0, text),
    "",
    "[Colors:View]",
    scheme_group(mantle, alternate, text),
    "",
    "[Colors:Window]",
    scheme_group(base, surface0, text),
    "",
    "[Colors:Complementary]",
    scheme_group(mantle, alternate, text),
    "",
    "[General]",
    "ColorScheme=Imperium",
    "Name=Imperium",
    "shadeSortColumn=true",
    "",
    "[KDE]",
    "contrast=2",
    "",
    "[WM]",
    f"activeBackground={rgb(base)}",
    f"activeBlend={rgb(accent)}",
    f"activeForeground={rgb(text)}",
    f"inactiveBackground={rgb(mantle)}",
    f"inactiveBlend={rgb(mantle)}",
    f"inactiveForeground={rgb(surface2)}",
    "",
])
scheme_dir = os.path.join(home, ".local", "share", "color-schemes")
os.makedirs(scheme_dir, exist_ok=True)
with open(os.path.join(scheme_dir, "Imperium.colors"), "w", encoding="utf-8") as handle:
    handle.write(scheme)

# A fresh filename misses KColorScheme's in-process cache. View backgrounds
# stay clear aside from a faint zebra. The window fill is the lifted body so
# the wallpaper shows through the files. Fully clear window backgrounds were
# flattened to black by opaque widgets. The shared Imperium scheme stays
# opaque for every other Qt app.
def clear_backgrounds(scheme_text):
    groups = {"Colors:View", "Colors:Window", "Colors:Complementary"}
    lines = []
    group = ""
    for line in scheme_text.splitlines():
        if line.startswith("[") and line.endswith("]"):
            group = line[1:-1]
        elif group in groups and (
            line.startswith("BackgroundNormal=") or line.startswith("BackgroundAlternate=")
        ):
            if line.count(",") >= 2:
                # Dolphin copies the view color onto the file surface and
                # flattens a clear color to an opaque slab. The window and
                # complementary fills carry the body alpha. The view stays the
                # dark chrome base so the sidebar plate does not lighten.
                key = line.split("=", 1)[0]
                if group == "Colors:View":
                    if key == "BackgroundAlternate":
                        line = f"{key}={rgb(stripe)},{stripe_alpha}"
                    else:
                        line = f"{key}={rgb(dolphin_bg)},0"
                else:
                    line = f"{key}={rgb(body)},{body_alpha}"
        lines.append(line)
    return "\n".join(lines) + "\n"

live_stamp = str(time.time_ns())
live_scheme = os.path.join(scheme_dir, f"dolphin-live-{live_stamp}.colors")
with open(live_scheme, "w", encoding="utf-8") as handle:
    handle.write(clear_backgrounds(scheme))
for name in os.listdir(scheme_dir):
    if not name.startswith("dolphin-live-") or not name.endswith(".colors"):
        continue
    if name == os.path.basename(live_scheme):
        continue
    try:
        os.remove(os.path.join(scheme_dir, name))
    except OSError:
        pass
live_conf = os.path.join(home, ".config", "qt6ct", "dolphin-live.conf")

kdeglobals = os.path.join(home, ".config", "kdeglobals")
font_small = font_ui.replace(",11,", ",9,", 1)
kde_keys = {
    "ColorScheme": "Imperium",
    "TerminalApplication": "kitty",
    "TerminalService": "kitty.desktop",
    "font": font_ui,
    "menuFont": font_ui,
    "toolBarFont": font_ui,
    "smallestReadableFont": font_small,
    "fixed": font_mono,
}
if os.path.isfile(kdeglobals):
    with open(kdeglobals, encoding="utf-8") as handle:
        kde_lines = handle.readlines()
else:
    kde_lines = ["[General]\n", "[Icons]\n", "[KDE]\n"]
seen = set()
kde_out = []
for line in kde_lines:
    key = line.split("=", 1)[0].strip()
    if key in kde_keys:
        kde_out.append(f"{key}={kde_keys[key]}\n")
        seen.add(key)
    else:
        kde_out.append(line if line.endswith("\n") else line + "\n")
missing = [key for key in kde_keys if key not in seen]
if missing:
    rebuilt = []
    inserted = False
    for line in kde_out:
        rebuilt.append(line)
        if line.strip() == "[General]":
            for key in missing:
                rebuilt.append(f"{key}={kde_keys[key]}\n")
            inserted = True
    if not inserted:
        rebuilt.insert(0, "[General]\n")
        for key in missing:
            rebuilt.insert(1, f"{key}={kde_keys[key]}\n")
    kde_out = rebuilt


kde_out = ensure_pair(kde_out, "Icons", "Theme", "imperium")
kde_out = ensure_pair(kde_out, "KDE", "widgetStyle", "kvantum")
with open(kdeglobals, "w", encoding="utf-8") as handle:
    handle.writelines(kde_out)

def paint_icons():
    # Imperium is a Wallust-tinted Papirus. Papirus-Dark inherits most sizes
    # from Papirus, so places and devices are recolored from that shared tree.
    source = "/usr/share/icons/Papirus"
    dark = "/usr/share/icons/Papirus-Dark"
    dest = os.path.join(home, ".local", "share", "icons", "imperium")
    stamp = os.path.join(dest, ".accent")
    preview_stamp = os.path.join(dest, ".folder-preview-accent")
    accent_hex = hx(icon_accent)
    preview_token = accent_hex + ":papirus-v1"
    previous_accent = None
    previous_preview_accent = None
    if os.path.isfile(preview_stamp):
        with open(preview_stamp, encoding="utf-8") as handle:
            previous_preview_accent = handle.read().strip()
    if os.path.isfile(stamp):
        with open(stamp, encoding="utf-8") as handle:
            previous_accent = handle.read().strip()
        if previous_accent == accent_hex and previous_preview_accent == preview_token:
            return
    if not os.path.isdir(source) and not os.path.isdir(dark):
        return
    os.makedirs(dest, exist_ok=True)
    index_src = os.path.join(dark if os.path.isdir(dark) else source, "index.theme")
    if os.path.isfile(index_src):
        with open(index_src, encoding="utf-8") as handle:
            index = handle.read()
        index = re.sub(r"(?m)^Name=.*$", "Name=Imperium", index, count=1)
        inherit = "Papirus-Dark" if os.path.isdir(dark) else "Papirus"
        if "Inherits=" not in index:
            index = index.replace("[Icon Theme]", f"[Icon Theme]\nInherits={inherit}", 1)
        else:
            index = re.sub(r"(?m)^Inherits=.*$", f"Inherits={inherit}", index, count=1)
        with open(os.path.join(dest, "index.theme"), "w", encoding="utf-8") as handle:
            handle.write(index)

    # Papirus paints folders and many place marks with fixed blues and a small
    # set of hue variants. Map those onto the wallpaper palette so Dolphin
    # follows Wallust without flattening every icon to one accent.
    paper = mix(text, mantle, 0.10)
    accent_main = icon_accent
    accent_dark = mix(icon_accent, mantle, 0.36)
    accent_light = lighten(icon_accent, 0.22)
    accent_deep = mix(icon_accent, mantle, 0.62)
    positive = secondary
    positive_dark = mix(secondary, mantle, 0.36)
    warning = lighten(mix(secondary, negative, 0.35), 0.08)
    warning_dark = mix(warning, mantle, 0.30)
    alert = negative
    alert_dark = mix(negative, mantle, 0.30)
    violet = link
    violet_dark = mix(link, mantle, 0.36)
    grey = muted
    grey_dark = mix(muted, mantle, 0.40)
    ink = mix(mantle, text, 0.28)
    ink_dark = mix(mantle, text, 0.18)
    replacements = {
        "#5294e2": "#" + hx(accent_main),
        "#3a87e5": "#" + hx(accent_main),
        "#4285f4": "#" + hx(accent_main),
        "#2196f3": "#" + hx(accent_main),
        "#4877b1": "#" + hx(accent_dark),
        "#93c0ea": "#" + hx(accent_light),
        "#1d344f": "#" + hx(accent_deep),
        "#e25252": "#" + hx(alert),
        "#f44336": "#" + hx(alert),
        "#e84040": "#" + hx(alert),
        "#bf4b4b": "#" + hx(alert_dark),
        "#87b158": "#" + hx(positive),
        "#4caf50": "#" + hx(positive),
        "#60924b": "#" + hx(positive_dark),
        "#f9bd30": "#" + hx(warning),
        "#ff9800": "#" + hx(warning),
        "#e19d00": "#" + hx(warning_dark),
        "#ee923a": "#" + hx(warning),
        "#dd772f": "#" + hx(warning_dark),
        "#7e57c2": "#" + hx(violet),
        "#9c40d3": "#" + hx(violet),
        "#5d399b": "#" + hx(violet_dark),
        "#8e8e8e": "#" + hx(grey),
        "#727272": "#" + hx(grey_dark),
        "#4f4f4f": "#" + hx(ink),
        "#3f3f3f": "#" + hx(ink_dark),
        "#00bcd4": "#" + hx(accent_light),
        "#e4e4e4": "#" + hx(paper),
        "#dcdcdc": "#" + hx(paper),
    }
    # Match only the hue keys when deciding whether to rewrite; paper is
    # remapped together with those fills so plain grey glyphs stay stock.
    hue_keys = [key for key in replacements if key not in ("#e4e4e4", "#dcdcdc")]
    needle = re.compile("|".join(re.escape(key) for key in hue_keys), re.I)
    paint = re.compile("|".join(re.escape(key) for key in replacements), re.I)

    def tinted(match):
        return replacements[match.group(0).lower()]

    written = set()
    for tree in (source, dark):
        if not os.path.isdir(tree):
            continue
        for dirpath, _, filenames in os.walk(tree):
            rel_dir = os.path.relpath(dirpath, tree)
            parts = [] if rel_dir == "." else rel_dir.split(os.sep)
            if len(parts) < 2 or parts[1] not in ("places", "devices"):
                continue
            for name in filenames:
                if not name.endswith(".svg"):
                    continue
                src = os.path.join(dirpath, name)
                rel = os.path.relpath(src, tree)
                if rel in written:
                    continue
                try:
                    with open(src, encoding="utf-8") as handle:
                        body = handle.read()
                except (OSError, UnicodeError):
                    continue
                if not needle.search(body):
                    continue
                target = os.path.join(dest, rel)
                os.makedirs(os.path.dirname(target), exist_ok=True)
                with open(target, "w", encoding="utf-8") as handle:
                    handle.write(paint.sub(tinted, body))
                written.add(rel)

    # KIO's inode/directory thumbnail is a composite containing the current
    # folder icon. Remove only those composites when their tint changes; the
    # other cached previews are user data and remain valid across icon themes.
    if previous_accent != accent_hex or previous_preview_accent != preview_token:
        invalidate_folder_thumbnails()
        recycle_thumbnail_workers()

    with open(stamp, "w", encoding="utf-8") as handle:
        handle.write(accent_hex + "\n")
    # The separate stamp also repairs previews cached before invalidation was
    # implemented, even when this first application keeps the current accent.
    with open(preview_stamp, "w", encoding="utf-8") as handle:
        handle.write(preview_token + "\n")
    # Notify other Qt clients too. Thumbnail workers are restarted above
    # because their blocking loop cannot consume this Qt theme notification.
    env = os.environ.copy()
    runtime = env.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    env["XDG_RUNTIME_DIR"] = runtime
    env.setdefault("DBUS_SESSION_BUS_ADDRESS", f"unix:path={runtime}/bus")
    subprocess.run(
        ["busctl", "--user", "emit", "/KIconLoader", "org.kde.KIconLoader", "iconChanged", "i", "0"],
        env=env,
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

def session_thumbnail_worker(proc_dir, address):
    """Match only this user's thumbnail plugin on the same session bus."""
    try:
        if os.stat(proc_dir).st_uid != os.getuid():
            return False
        executable = os.readlink(os.path.join(proc_dir, "exe"))
        if os.path.basename(executable) != "kioworker":
            return False
        with open(os.path.join(proc_dir, "cmdline"), "rb") as handle:
            args = handle.read().split(b"\0")
        if len(args) < 2:
            return False
        plugin = os.fsdecode(args[1])
        if os.path.basename(plugin) != "thumbnail.so" or os.path.basename(os.path.dirname(plugin)) != "kio":
            return False
        # Read only to compare the bus; never print process environments.
        with open(os.path.join(proc_dir, "environ"), "rb") as handle:
            environment = handle.read().split(b"\0")
        bus = next((entry.split(b"=", 1)[1] for entry in environment if entry.startswith(b"DBUS_SESSION_BUS_ADDRESS=")), b"")
        return os.fsdecode(bus).split(",guid=", 1)[0] == address.split(",guid=", 1)[0]
    except OSError:
        return False

def recycle_thumbnail_workers():
    # The thumbnail worker's blocking dispatchLoop doesn't service Qt's theme
    # notifications. Its QIcon cache therefore survives the icon-change signal.
    # Retire only thumbnail workers; file and network workers are left alone.
    runtime = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    address = os.environ.get("DBUS_SESSION_BUS_ADDRESS") or f"unix:path={runtime}/bus"
    for entry in os.listdir("/proc"):
        if not entry.isdecimal():
            continue
        descriptor = None
        try:
            # Pin the process before inspecting it, avoiding PID reuse races.
            descriptor = os.pidfd_open(int(entry))
            if session_thumbnail_worker(os.path.join("/proc", entry), address):
                signal.pidfd_send_signal(descriptor, signal.SIGTERM)
                exited = select.poll()
                exited.register(descriptor, select.POLLIN)
                exited.poll(250)
        except OSError:
            pass
        finally:
            if descriptor is not None:
                os.close(descriptor)

def png_text_metadata(path):
    """Read PNG text chunks without decoding or exposing cached image data."""
    metadata = {}

    def inflate_text(payload):
        decoder = zlib.decompressobj()
        decoded = decoder.decompress(payload, 64 * 1024)
        if decoder.unconsumed_tail or not decoder.eof or len(decoded) >= 64 * 1024:
            return None
        return decoded

    try:
        with open(path, "rb") as handle:
            if handle.read(8) != b"\x89PNG\r\n\x1a\n":
                return metadata
            while True:
                header = handle.read(8)
                if len(header) != 8:
                    break
                length = int.from_bytes(header[:4], "big")
                chunk_type = header[4:]
                if chunk_type in (b"tEXt", b"zTXt", b"iTXt") and length <= 1024 * 1024:
                    chunk = handle.read(length)
                    if len(chunk) != length:
                        break
                else:
                    chunk = b""
                    handle.seek(length, os.SEEK_CUR)
                if len(handle.read(4)) != 4:
                    break
                if chunk_type == b"tEXt":
                    key, separator, value = chunk.partition(b"\0")
                    if separator:
                        metadata[key.decode("latin-1")] = value.decode("latin-1")
                elif chunk_type == b"zTXt":
                    key, separator, payload = chunk.partition(b"\0")
                    if separator and payload[:1] == b"\0":
                        try:
                            decoded = inflate_text(payload[1:])
                            if decoded is not None:
                                metadata[key.decode("latin-1")] = decoded.decode("latin-1")
                        except (UnicodeError, zlib.error):
                            pass
                elif chunk_type == b"iTXt":
                    key, separator, rest = chunk.partition(b"\0")
                    if not separator or len(rest) < 2:
                        continue
                    compressed, method = rest[:2]
                    _, separator, rest = rest[2:].partition(b"\0")
                    if not separator:
                        continue
                    _, separator, payload = rest.partition(b"\0")
                    if not separator:
                        continue
                    try:
                        if compressed == 1 and method == 0:
                            payload = inflate_text(payload)
                            if payload is None:
                                continue
                        metadata[key.decode("latin-1")] = payload.decode("utf-8")
                    except (UnicodeError, zlib.error):
                        pass
                if chunk_type == b"IEND":
                    break
    except OSError:
        pass
    return metadata

def local_directory_from_uri(uri):
    try:
        parsed = urllib.parse.urlsplit(uri)
        if parsed.scheme != "file" or parsed.netloc not in ("", "localhost"):
            return None
        path = urllib.parse.unquote(parsed.path)
        return path if path and os.path.isdir(path) else None
    except (TypeError, ValueError):
        return None

def invalidate_folder_thumbnails():
    cache_home = os.environ.get("XDG_CACHE_HOME") or os.path.join(home, ".cache")
    thumbnail_root = os.path.join(os.path.abspath(cache_home), "thumbnails")
    for tier in ("normal", "large", "x-large", "xx-large"):
        tier_dir = os.path.join(thumbnail_root, tier)
        if os.path.islink(tier_dir):
            continue
        try:
            names = os.listdir(tier_dir)
        except OSError:
            continue
        for name in names:
            if not name.endswith(".png"):
                continue
            path = os.path.join(tier_dir, name)
            if os.path.islink(path) or not os.path.isfile(path):
                continue
            uri = png_text_metadata(path).get("Thumb::URI")
            if uri and local_directory_from_uri(uri):
                try:
                    os.remove(path)
                except OSError:
                    pass

paint_icons()

konsole_dir = os.path.join(home, ".local", "share", "konsole")
os.makedirs(konsole_dir, exist_ok=True)
terminal_live = f"dolphin-terminal-live-{live_stamp}"
ansi = []
for index in range(8):
    normal = readable(palette.get(str(index)) or text, dolphin_bg, 4.5)
    intense = readable(palette.get(str(index + 8)) or lighten(normal, 0.2), dolphin_bg, 7.0)
    faint = readable(mix(normal, dolphin_bg, 0.25), dolphin_bg, 4.5)
    ansi.append(f"[Color{index}]\nColor={rgb(normal)}\n")
    ansi.append(f"[Color{index}Intense]\nColor={rgb(intense)}\n")
    ansi.append(f"[Color{index}Faint]\nColor={rgb(faint)}\n")
scheme_body = "\n".join([
    "[Background]",
    f"Color={rgb(dolphin_bg)}",
    "[BackgroundIntense]",
    f"Color={rgb(dolphin_bg)}",
    "[BackgroundFaint]",
    f"Color={rgb(dolphin_bg)}",
    "[Foreground]",
    f"Color={rgb(readable(text, dolphin_bg, 7.0))}",
    "[ForegroundIntense]",
    f"Color={rgb(readable(lighten(text, 0.08), dolphin_bg, 7.0))}",
    "[ForegroundFaint]",
    f"Color={rgb(readable(muted, dolphin_bg, 4.5))}",
    "[General]",
    "Description=Imperium",
    "Opacity=0.94",
    "",
]) + "\n" + "\n".join(ansi)
with open(os.path.join(konsole_dir, "Imperium.colorscheme"), "w", encoding="utf-8") as handle:
    handle.write(scheme_body)
# Konsole caches profiles and color schemes by name. Fresh names let the
# running embedded terminal pick up a wallpaper change without losing its shell.
with open(os.path.join(konsole_dir, terminal_live + ".colorscheme"), "w", encoding="utf-8") as handle:
    handle.write(scheme_body)
profile_body = (
        "[Appearance]\n"
        "BoldIntense=false\n"
        f"ColorScheme={terminal_live}\n"
        f"Font={font_mono}\n"
        "LineSpacing=0\n"
        "\n"
        "[General]\n"
        "Name=Imperium\n"
        "Parent=FALLBACK/\n"
        f"Command={root}/dolphin/terminal.sh\n"
        f"Environment=STARSHIP_CONFIG={root}/dolphin/starship.toml\n"
        "TerminalRows=12\n"
        "\n"
        "[Scrolling]\n"
        "HistoryMode=1\n"
        "ScrollBarPosition=0\n"
        "\n"
        "[Terminal Features]\n"
        "BlinkingCursorEnabled=false\n"
        "TerminalMargin=10\n"
)
with open(os.path.join(konsole_dir, "Imperium.profile"), "w", encoding="utf-8") as handle:
    handle.write(profile_body)
with open(os.path.join(konsole_dir, terminal_live + ".profile"), "w", encoding="utf-8") as handle:
    handle.write(profile_body.replace("Name=Imperium\n", f"Name={terminal_live}\n", 1))
# Keep the current and preceding generation for a window mid-refresh.
old_profiles = sorted(
    name for name in os.listdir(konsole_dir)
    if re.fullmatch(r"dolphin-terminal-live-\d+\.profile", name)
)
for name in old_profiles[:-2]:
    for extension in (".profile", ".colorscheme"):
        try:
            os.remove(os.path.join(konsole_dir, name.removesuffix(".profile") + extension))
        except OSError:
            pass
konsolerc = os.path.join(home, ".config", "konsolerc")
if os.path.isfile(konsolerc):
    with open(konsolerc, encoding="utf-8") as handle:
        konsole_lines = handle.readlines()
else:
    konsole_lines = ["[Desktop Entry]\n", "[General]\n"]
konsole_lines = ensure_pair(konsole_lines, "Desktop Entry", "DefaultProfile", "Imperium.profile")
konsole_lines = ensure_pair(konsole_lines, "KonsoleWindow", "ShowMenuBarByDefault", "false")
konsole_lines = ensure_pair(konsole_lines, "MainWindow", "MenuBar", "Disabled")
konsole_lines = ensure_pair(konsole_lines, "TabBar", "TabBarVisibility", "AlwaysHideTabBar")
with open(konsolerc, "w", encoding="utf-8") as handle:
    handle.writelines(konsole_lines)

def has_key(lines, section, key):
    in_section = False
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            in_section = stripped == f"[{section}]"
        elif in_section and stripped.startswith(f"{key}="):
            return True
    return False


def ensure_missing(lines, section, key, value):
    if has_key(lines, section, key):
        return lines
    return ensure_pair(lines, section, key, value)


def monitor_layout():
    try:
        raw = subprocess.check_output(
            ["hyprctl", "monitors", "-j"], text=True, stderr=subprocess.DEVNULL, timeout=2
        )
        monitors = json.loads(raw)
    except (OSError, subprocess.CalledProcessError, subprocess.TimeoutExpired, json.JSONDecodeError):
        return []
    return monitors if isinstance(monitors, list) else []


def dialog_size_for(prefix, monitors):
    match = re.fullmatch(r"(\d+)x(\d+) screen", prefix)
    if match:
        screen_w, screen_h = int(match.group(1)), int(match.group(2))
    elif monitors:
        screen_w = max(int(item.get("width") or 0) for item in monitors)
        screen_h = max(int(item.get("height") or 0) for item in monitors)
    else:
        screen_w, screen_h = 1920, 1080
    # Large enough to read a details view, and still short of a maximized window.
    width = min(1280, max(960, round(screen_w * 0.72 / 10) * 10))
    height = min(800, max(640, round(screen_h * 0.74 / 10) * 10))
    return width, height


def configure_file_dialog():
    """Size and density for the KDE portal file dialog.

    Width is written once. Later resizes stay in the portal state file.
    A saved maximize flag without a width opens at the widget's small hint
    on this compositor, so that case receives an explicit size too.
    """
    monitors = monitor_layout()
    state_path = os.path.join(home, ".local", "state", "xdg-desktop-portal-kdestaterc")
    if os.path.isfile(state_path):
        with open(state_path, encoding="utf-8") as handle:
            state_lines = handle.readlines()
    else:
        state_lines = []
    prefixes = []
    if len(monitors) == 1:
        prefixes.append(f"{int(monitors[0].get('width') or 0)}x{int(monitors[0].get('height') or 0)} screen")
    elif len(monitors) > 1:
        prefixes.append(f"{len(monitors)} screens")
    for line in state_lines:
        match = re.match(r"(.+): Window-Maximized=", line.strip())
        if match and match.group(1) not in prefixes:
            prefixes.append(match.group(1))
    for prefix in prefixes:
        width_key = f"{prefix}: Width"
        if has_key(state_lines, "FileDialogSize", width_key):
            continue
        width, height = dialog_size_for(prefix, monitors)
        state_lines = ensure_pair(state_lines, "FileDialogSize", width_key, str(width))
        state_lines = ensure_pair(state_lines, "FileDialogSize", f"{prefix}: Height", str(height))
        state_lines = ensure_pair(state_lines, "FileDialogSize", f"{prefix}: Window-Maximized", "false")
    os.makedirs(os.path.dirname(state_path), exist_ok=True)
    with open(state_path, "w", encoding="utf-8") as handle:
        handle.writelines(state_lines)

    portal_rc = os.path.join(home, ".config", "xdg-desktop-portal-kderc")
    if os.path.isfile(portal_rc):
        with open(portal_rc, encoding="utf-8") as handle:
            portal_lines = handle.readlines()
    else:
        portal_lines = []
    # DetailTree matches Dolphin's expandable details view. The places column
    # is narrower than Dolphin's 240px sidebar.
    for key, value in (
        ("View Style", "DetailTree"),
        ("Show Places Panel", "true"),
        ("Show Speedbar", "true"),
        ("Speedbar Width", "200"),
        ("Breadcrumb Navigation", "true"),
        ("Show Preview", "false"),
        ("Places Icons Auto-resize", "false"),
        ("Places Icons Static Size", "22"),
    ):
        portal_lines = ensure_missing(portal_lines, "KFileDialog Settings", key, value)
    with open(portal_rc, "w", encoding="utf-8") as handle:
        handle.writelines(portal_lines)


# Converge existing installations too; appearance is owned by the repo.
if dolphin_enabled:
    subprocess.run([sys.executable, os.path.join(root, "dolphin", "apply-config.py"),
                    "--home", home], check=True)
    configure_file_dialog()

def session_env():
    env = os.environ.copy()
    runtime = env.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    env["XDG_RUNTIME_DIR"] = runtime
    env.setdefault("DBUS_SESSION_BUS_ADDRESS", f"unix:path={runtime}/bus")
    return env

def push_open_windows(stylesheet):
    """Push the new stylesheet into Dolphin windows that are already open."""
    env = session_env()
    try:
        listing = subprocess.check_output(
            ["busctl", "--user", "list", "--no-legend"], text=True, env=env, stderr=subprocess.DEVNULL
        )
    except (OSError, subprocess.CalledProcessError):
        return
    for line in listing.splitlines():
        service = line.split()[0] if line.split() else ""
        if not service.startswith("org.kde.dolphin-"):
            continue
        try:
            tree = subprocess.check_output(
                ["busctl", "--user", "tree", service], text=True, env=env, stderr=subprocess.DEVNULL
            )
        except (OSError, subprocess.CalledProcessError):
            continue
        for raw in tree.splitlines():
            if "/dolphin/Dolphin_" not in raw and raw.strip().split()[-1:] != ["/MainApplication"]:
                continue
            path = raw.strip().split()[-1]
            if path != "/MainApplication" and path.count("/") != 2:
                continue
            interface = (
                "org.qtproject.Qt.QApplication"
                if path == "/MainApplication"
                else "org.qtproject.Qt.QWidget"
            )
            subprocess.run(
                [
                    "busctl", "--user", "call", service, path,
                    interface, "setStyleSheet", "s", stylesheet,
                ],
                env=env, check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )

# Publish only after icons, thumbnails, QSS, and terminal files are ready.
# An atomic replacement prevents the live hook from reading a partial marker.
os.makedirs(os.path.dirname(live_conf), exist_ok=True)
pending_conf = live_conf + "." + live_stamp
with open(pending_conf, "w", encoding="utf-8") as handle:
    handle.write(f"scheme={live_scheme}\nqss={qss_path}\nicons={hx(icon_accent)}:papirus-v1\nterminal={terminal_live}\n")
os.replace(pending_conf, live_conf)

if dolphin_enabled:
    with open(qss_path, encoding="utf-8") as handle:
        push_open_windows(handle.read())
PY
