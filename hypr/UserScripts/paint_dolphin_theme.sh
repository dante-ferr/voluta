#!/usr/bin/env bash
# paint_dolphin_theme.sh — Recolor Dolphin's Qt stack from the wallust palette.
#
# Dolphin follows qt6ct + Kvantum + the KDE color scheme. This writes those
# three from the current wallpaper colors and points Kvantum at the Imperium
# theme. Sharp corners are already baked into the theme template.
set +m

_rice_paths="$HOME/.config/hypr/UserScripts/lib/rice_paths.sh"
[[ -r $_rice_paths ]] || _rice_paths="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/rice_paths.sh"
# shellcheck source=lib/rice_paths.sh
source "$_rice_paths"

root=$(imperium_rice_root) || exit 0
colors="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/wallust/colors-shell.sh"

exec python3 - "$root" "$colors" "$HOME" <<'PY'
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

root, colors_path, home = sys.argv[1:4]

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

bg = palette["bg"]
fg = palette["fg"]
# Match Kitty's wallust background (lighten(0.03)), with less glass showing
# through Dolphin. Other Qt apps keep their existing Imperium surfaces.
dolphin_bg = lighten(bg, 0.03)
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
svg_in = os.path.join(template_dir, "imperium.svg.in")
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
with open(os.path.join(theme_dir, "imperium.svg"), "w", encoding="utf-8") as handle:
    handle.write(fill(svg_in))
filled_kv = fill(kv_in)
with open(os.path.join(theme_dir, "imperium.kvconfig"), "w", encoding="utf-8") as handle:
    handle.write(filled_kv)

# Dolphin gets a roomier copy of the same theme. Other Qt apps keep the
# tighter Imperium margins.
dolphin_theme = os.path.join(home, ".config", "Kvantum", "dolphin")
os.makedirs(dolphin_theme, exist_ok=True)
# Translucency and the Kitty-like background are Dolphin-only.
dolphin_tokens = {"@@BASE@@": hx(dolphin_bg), "@@MANTLE@@": hx(dolphin_bg)}
dolphin_kv = fill(kv_in, dolphin_tokens).replace("layout_margin=4", "layout_margin=12", 1)
dolphin_kv = dolphin_kv.replace("translucent_windows=false", "translucent_windows=true", 1)
# 94% opacity keeps the wallpaper subtle; Kitty remains at 75%.
dolphin_kv = dolphin_kv.replace("reduce_window_opacity=0", "reduce_window_opacity=6", 1)
dolphin_kv = dolphin_kv.replace("splitter_width=7", "splitter_width=2", 1)
with open(os.path.join(dolphin_theme, "dolphin.kvconfig"), "w", encoding="utf-8") as handle:
    handle.write(dolphin_kv)
svg_path = os.path.join(dolphin_theme, "dolphin.svg")
if os.path.islink(svg_path):
    os.remove(svg_path)
with open(svg_path, "w", encoding="utf-8") as handle:
    handle.write(fill(svg_in, dolphin_tokens))

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
for app_name in ("dolphin", "org.kde.dolphin"):
    if re.search(rf"(?m)^{app_name}=", rc):
        rc = re.sub(rf"(?m)^{app_name}=.*$", f"{app_name}=dolphin", rc)
    else:
        rc = rc.rstrip() + f"\n{app_name}=dolphin"
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
alt_hex = hx(alternate)
sel_hex = hx(select_bg)
sel_fg = hx(selection_text)
hover_hex = hx(hover)
edge = hx(mix(accent, mantle, 0.45))
panel = hx(base)
quiet = hx(muted)
with open(qss_path, "w", encoding="utf-8") as handle:
    handle.write(f"""
DolphinMainWindow {{
    color: #{ivory};
    padding: 18px;
}}
DolphinMainWindow QToolBar {{
    background-color: transparent;
    border: none;
    padding: 8px 12px;
    spacing: 6px;
    margin: 8px 12px 6px 12px;
}}
DolphinMainWindow QStatusBar {{
    background-color: transparent;
    color: #{quiet};
    border: none;
    padding: 8px 16px;
    margin: 6px 12px 12px 12px;
}}
DolphinMainWindow QDockWidget {{
    background-color: transparent;
    color: #{ivory};
    border: none;
    titlebar-close-icon: none;
    margin: 10px;
    padding: 6px;
}}
DolphinMainWindow::separator {{
    background-color: #{edge};
    width: 2px;
    height: 2px;
}}
DolphinMainWindow::separator:hover {{
    background-color: #{hx(accent)};
}}
DolphinMainWindow QSplitter::handle {{
    background-color: #{edge};
    width: 2px;
    height: 2px;
}}
DolphinMainWindow QSplitter::handle:hover {{
    background-color: #{hx(accent)};
}}
DolphinMainWindow QDockWidget#placesDock {{
    margin-right: 2px;
    padding-right: 0px;
}}
DolphinMainWindow QToolButton {{
    background-color: transparent;
    color: #{ivory};
    border: none;
    padding: 6px;
    margin: 0 2px;
}}
DolphinMainWindow QToolButton:hover {{
    background-color: #{hover_hex};
    color: #{ivory};
}}
DolphinMainWindow QDockWidget::title {{
    background-color: transparent;
    color: #{quiet};
    padding: 10px 14px 4px 14px;
    border: none;
}}
QDockWidget#terminalDock {{
    min-height: 220px;
}}
QDockWidget#terminalDock::title {{
    max-height: 0px;
    padding: 0;
    margin: 0;
}}
TerminalPanel {{
    background-color: transparent;
    color: #{ivory};
    border: none;
    min-height: 200px;
}}
TerminalPanel QWidget {{
    background-color: transparent;
    color: #{ivory};
    border: none;
}}
DolphinStatusBar QLabel {{
    min-width: 240px;
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
    alternate-background-color: #{alt_hex};
    color: #{ivory};
    selection-background-color: #{sel_hex};
    selection-color: #{sel_fg};
    outline: 0;
    border: none;
    padding: 4px;
}}
DolphinMainWindow QGraphicsView,
DolphinMainWindow KItemListContainer,
DolphinMainWindow QTreeView,
DolphinMainWindow QListView,
DolphinMainWindow QTableView,
DolphinMainWindow QColumnView,
DolphinMainWindow QHeaderView::section {{
    background-color: transparent;
    alternate-background-color: transparent;
    color: #{ivory};
    border: none;
    padding: 8px;
}}
QTreeView::item, QListView::item, QTableView::item {{
    color: #{ivory};
    padding: 6px 12px;
    background-color: transparent;
}}
DolphinMainWindow QTreeView::item,
DolphinMainWindow QListView::item {{
    background-color: transparent;
    alternate-background-color: transparent;
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
    background-color: transparent;
    qproperty-spacing: 1;
    padding: 4px 0px 8px 12px;
}}
DolphinMainWindow KFilePlacesView::item {{
    color: #{ivory};
    background-color: transparent;
    padding: 3px 12px;
    margin: 0px;
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
    border: none;
    border-bottom: 1px solid #{edge};
    padding: 8px 12px;
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
    padding: 6px 10px;
}}
QMenu {{
    background-color: #{panel};
    color: #{ivory};
    border: 1px solid #{edge};
    padding: 5px 8px;
}}
QMenu::item {{
    padding: 6px 12px;
}}
QMenu::item:selected {{
    background-color: #{sel_hex};
    color: #{sel_fg};
}}
QMenu::separator {{
    height: 1px;
    margin: 5px 8px;
    background-color: #{edge};
}}
QPlainTextEdit, QTextEdit, KTextEdit {{
    background-color: #{panel};
    color: #{ivory};
    border: 1px solid #{edge};
    selection-background-color: #{sel_hex};
    selection-color: #{sel_fg};
}}
QTextEdit, KTextEdit {{
    padding: 8px;
}}
KMessageWidget {{
    background-color: #{panel};
    color: #{ivory};
    border: 1px solid #{edge};
    padding: 8px 12px;
}}
Baloo--FileMetaDataWidget {{
    min-width: 260px;
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
font = '"Monaspace Argon,10,-1,5,50,0,0,0,0,0,0,0,0,0,0,0,1,Regular"'
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
    "Fonts": {"fixed": font, "general": font},
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

# A fresh filename misses KColorScheme's in-process cache. View and window
# backgrounds in this copy are 94% opaque. Fully clear backgrounds were
# flattened to black by opaque widgets. The shared Imperium scheme stays
# opaque for every other Qt app.
def clear_backgrounds(body):
    groups = {"Colors:View", "Colors:Window", "Colors:Complementary"}
    lines = []
    group = ""
    for line in body.splitlines():
        if line.startswith("[") and line.endswith("]"):
            group = line[1:-1]
        elif group in groups and (
            line.startswith("BackgroundNormal=") or line.startswith("BackgroundAlternate=")
        ):
            if line.count(",") == 2:
                # The file view must stay clear so it does not paint a second
                # near-black slab over the window. The window fill is 94%.
                key = line.split("=", 1)[0]
                line = f"{key}={rgb(dolphin_bg)}," + ("0" if group == "Colors:View" else "240")
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
font_kde = "Monaspace Argon,10,-1,5,50,0,0,0,0,0,Regular"
font_small = "Monaspace Argon,8,-1,5,50,0,0,0,0,0,Regular"
font_toolbar = "Monaspace Argon,10,-1,5,50,0,0,0,0,0,Regular"
kde_keys = {
    "ColorScheme": "Imperium",
    "TerminalApplication": "kitty",
    "TerminalService": "kitty.desktop",
    "font": font_kde,
    "menuFont": font_kde,
    "toolBarFont": font_toolbar,
    "smallestReadableFont": font_small,
    "fixed": font_kde,
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
    source = "/usr/share/icons/breeze-dark"
    dest = os.path.join(home, ".local", "share", "icons", "imperium")
    stamp = os.path.join(dest, ".accent")
    preview_stamp = os.path.join(dest, ".folder-preview-accent")
    accent_hex = hx(icon_accent)
    preview_token = accent_hex + ":workers-v2"
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
    if not os.path.isdir(source):
        return
    os.makedirs(dest, exist_ok=True)
    index_src = os.path.join(source, "index.theme")
    if os.path.isfile(index_src):
        with open(index_src, encoding="utf-8") as handle:
            index = handle.read()
        index = re.sub(r"(?m)^Name=.*$", "Name=Imperium", index, count=1)
        if "Inherits=" not in index:
            index = index.replace("[Icon Theme]", "[Icon Theme]\nInherits=breeze-dark", 1)
        else:
            index = re.sub(r"(?m)^Inherits=.*$", "Inherits=breeze-dark", index, count=1)
        with open(os.path.join(dest, "index.theme"), "w", encoding="utf-8") as handle:
            handle.write(index)
    needle = re.compile(r"#3[Dd][Aa][Ee][Ee]9")
    for dirpath, _, filenames in os.walk(source):
        for name in filenames:
            if not name.endswith(".svg"):
                continue
            src = os.path.join(dirpath, name)
            try:
                with open(src, encoding="utf-8") as handle:
                    body = handle.read()
            except (OSError, UnicodeError):
                continue
            if not needle.search(body):
                continue
            rel = os.path.relpath(src, source)
            target = os.path.join(dest, rel)
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with open(target, "w", encoding="utf-8") as handle:
                handle.write(needle.sub("#" + accent_hex, body))

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
        "Font=Monaspace Argon,10\n"
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

# Converge existing installations too; appearance is owned by the repo.
subprocess.run([sys.executable, os.path.join(root, "dolphin", "apply-config.py"),
                "--home", home], check=True)

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
    handle.write(f"scheme={live_scheme}\nqss={qss_path}\nicons={hx(icon_accent)}:workers-v2\nterminal={terminal_live}\n")
os.replace(pending_conf, live_conf)

with open(qss_path, encoding="utf-8") as handle:
    push_open_windows(handle.read())
PY
