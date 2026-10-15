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
import subprocess
import sys
import time

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
    lifted = color
    for _ in range(12):
        if contrast(lifted, against) >= minimum:
            return lifted
        lifted = lighten(lifted, 0.08)
    return lifted

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
select_bg = mix(mantle, accent, 0.72)
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

def fill(path):
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    for token, value in tokens.items():
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
# Spacing stays at the template value so Places / Remote / Recent do not
# grow a second time. Translucency is dolphin-only; other Qt apps stay solid.
dolphin_kv = filled_kv.replace("layout_margin=4", "layout_margin=12", 1)
dolphin_kv = dolphin_kv.replace("translucent_windows=false", "translucent_windows=true", 1)
# 12% reduction is 88% opacity. Kitty is 75%, so Dolphin stays easier to read.
dolphin_kv = dolphin_kv.replace("reduce_window_opacity=0", "reduce_window_opacity=12", 1)
with open(os.path.join(dolphin_theme, "dolphin.kvconfig"), "w", encoding="utf-8") as handle:
    handle.write(dolphin_kv)
svg_link = os.path.join(dolphin_theme, "dolphin.svg")
svg_target = os.path.join(theme_dir, "imperium.svg")
if os.path.lexists(svg_link):
    os.remove(svg_link)
os.symlink(svg_target, svg_link)

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
    qproperty-spacing: 4;
    padding: 4px 8px 8px 12px;
}}
DolphinMainWindow KFilePlacesView::item {{
    color: #{ivory};
    background-color: transparent;
    padding: 4px 12px;
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
    padding: 4px 8px;
}}
QMenu {{
    background-color: #{panel};
    color: #{ivory};
    border: 1px solid #{edge};
}}
QMenu::item:selected {{
    background-color: #{sel_hex};
    color: #{sel_fg};
}}
QPlainTextEdit, QTextEdit, KTextEdit {{
    background-color: #{panel};
    color: #{ivory};
    border: 1px solid #{edge};
    selection-background-color: #{sel_hex};
    selection-color: #{sel_fg};
}}
KMessageWidget {{
    background-color: #{panel};
    color: #{ivory};
    border: 1px solid #{edge};
}}
Baloo--FileMetaDataWidget {{
    min-width: 260px;
    color: #{ivory};
}}
""".lstrip())

qt_conf = os.path.join(home, ".config", "qt6ct", "qt6ct.conf")
font = '"JetBrains Mono,11,-1,5,50,0,0,0,0,0,0,0,0,0,0,1,Regular"'
font_general = '"JetBrains Mono,12,-1,5,50,0,0,0,0,0,0,0,0,0,0,1,Regular"'
replacements = {
    "color_scheme_path": "$HOME/.config/qt6ct/colors/Imperium.conf",
    "custom_palette": "true",
    "icon_theme": "imperium",
    "style": "kvantum",
    "fixed": font,
    "general": font_general,
    "stylesheets": qss_path,
}
if os.path.isfile(qt_conf):
    with open(qt_conf, encoding="utf-8") as handle:
        lines = handle.readlines()
else:
    lines = ["[Appearance]\n", "[Fonts]\n", "[Interface]\n"]
seen = set()
out_lines = []
for line in lines:
    key = line.split("=", 1)[0].strip()
    if key in replacements:
        out_lines.append(f"{key}={replacements[key]}\n")
        seen.add(key)
    else:
        out_lines.append(line if line.endswith("\n") else line + "\n")
missing_appearance = [k for k in ("color_scheme_path", "custom_palette", "icon_theme", "style") if k not in seen]
missing_fonts = [k for k in ("fixed", "general") if k not in seen]
if missing_appearance or missing_fonts:
    rebuilt = []
    inserted_a = False
    inserted_f = False
    for line in out_lines:
        rebuilt.append(line)
        if line.strip() == "[Appearance]" and missing_appearance:
            for key in missing_appearance:
                rebuilt.append(f"{key}={replacements[key]}\n")
            inserted_a = True
        if line.strip() == "[Fonts]" and missing_fonts:
            for key in missing_fonts:
                rebuilt.append(f"{key}={replacements[key]}\n")
            inserted_f = True
    if missing_appearance and not inserted_a:
        rebuilt.insert(0, "[Appearance]\n")
        for key in missing_appearance:
            rebuilt.insert(1, f"{key}={replacements[key]}\n")
    if missing_fonts and not inserted_f:
        rebuilt.append("[Fonts]\n")
        for key in missing_fonts:
            rebuilt.append(f"{key}={replacements[key]}\n")
    out_lines = rebuilt
os.makedirs(os.path.dirname(qt_conf), exist_ok=True)
with open(qt_conf, "w", encoding="utf-8") as handle:
    handle.writelines(out_lines)

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
# backgrounds in this copy are 88% opaque. Fully clear backgrounds were
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
                # near-black slab over the window. The window fill is 88%.
                line += ",0" if group == "Colors:View" else ",224"
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
font_kde = "JetBrains Mono,11,-1,5,50,0,0,0,0,0,Regular"
font_small = "JetBrains Mono,8,-1,5,50,0,0,0,0,0,Regular"
font_toolbar = "JetBrains Mono,10,-1,5,50,0,0,0,0,0,Regular"
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

kde_out = ensure_pair(kde_out, "Icons", "Theme", "imperium")
kde_out = ensure_pair(kde_out, "KDE", "widgetStyle", "kvantum")
with open(kdeglobals, "w", encoding="utf-8") as handle:
    handle.writelines(kde_out)

def paint_icons():
    source = "/usr/share/icons/breeze-dark"
    dest = os.path.join(home, ".local", "share", "icons", "imperium")
    stamp = os.path.join(dest, ".accent")
    accent_hex = hx(icon_accent)
    if os.path.isfile(stamp):
        with open(stamp, encoding="utf-8") as handle:
            if handle.read().strip() == accent_hex:
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
    with open(stamp, "w", encoding="utf-8") as handle:
        handle.write(accent_hex + "\n")

paint_icons()

# The icon files have to be in place before Dolphin is told the palette
# changed, or the repaint keeps the previous pixmaps.
os.makedirs(os.path.dirname(live_conf), exist_ok=True)
with open(live_conf, "w", encoding="utf-8") as handle:
    handle.write(f"scheme={live_scheme}\nqss={qss_path}\nicons={hx(icon_accent)}\n")

konsole_dir = os.path.join(home, ".local", "share", "konsole")
os.makedirs(konsole_dir, exist_ok=True)
ansi = []
for index in range(8):
    normal = palette.get(str(index)) or mantle
    intense = palette.get(str(index + 8)) or lighten(normal, 0.2)
    ansi.append(f"[Color{index}]\nColor={rgb(normal)}\n")
    ansi.append(f"[Color{index}Intense]\nColor={rgb(intense)}\n")
    ansi.append(f"[Color{index}Faint]\nColor={rgb(mix(normal, mantle, 0.45))}\n")
scheme_body = "\n".join([
    "[Background]",
    f"Color={rgb(mantle)}",
    "[BackgroundIntense]",
    f"Color={rgb(base)}",
    "[BackgroundFaint]",
    f"Color={rgb(mantle)}",
    "[Foreground]",
    f"Color={rgb(text)}",
    "[ForegroundIntense]",
    f"Color={rgb(lighten(text, 0.08))}",
    "[ForegroundFaint]",
    f"Color={rgb(muted)}",
    "[General]",
    "Description=Imperium",
    "Opacity=0.88",
    "",
]) + "\n" + "\n".join(ansi)
with open(os.path.join(konsole_dir, "Imperium.colorscheme"), "w", encoding="utf-8") as handle:
    handle.write(scheme_body)
with open(os.path.join(konsole_dir, "Imperium.profile"), "w", encoding="utf-8") as handle:
    handle.write(
        "[Appearance]\n"
        "BoldIntense=false\n"
        "ColorScheme=Imperium\n"
        "Font=JetBrains Mono,11\n"
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
        "TerminalMargin=2\n"
    )
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

view_dir = os.path.join(home, ".local", "share", "dolphin", "view_properties", "global")
view_file = os.path.join(view_dir, ".directory")
if not os.path.isfile(view_file):
    os.makedirs(view_dir, exist_ok=True)
    with open(view_file, "w", encoding="utf-8") as handle:
        handle.write(
            "[Dolphin]\n"
            "ViewMode=2\n"
            "PreviewsShown=true\n"
            "HiddenFilesShown=false\n"
        )

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
        for raw in tree.splitlines():
            if "/Sessions/" not in raw:
                continue
            path = raw.strip().split()[-1]
            subprocess.run(
                [
                    "busctl", "--user", "call", service, path,
                    "org.kde.konsole.Session", "setProfile", "s", "Imperium",
                ],
                env=env, check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )

with open(qss_path, encoding="utf-8") as handle:
    push_open_windows(handle.read())
PY
