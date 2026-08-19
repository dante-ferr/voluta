#!/usr/bin/env bash
# Compact 3×2 Imperium power tablet. A second invocation dismisses it.
#
# wlogout expands every button to fill the area inside the margins, so the
# margins are what keep the tiles from eating the screen. They are measured
# from the focused output so the tablet stays the same physical size on a
# 1080p panel and a 1440p one.

if pgrep -x wlogout >/dev/null 2>&1; then
    pkill -x wlogout
    exit 0
fi

conf="${XDG_CONFIG_HOME:-$HOME/.config}/wlogout"

# Repaint icons if wallust has not produced the 64px PNGs yet this session.
if [[ ! -f $conf/wallust/lock.png ]]; then
    # shellcheck source=/dev/null
    source "$conf/paint-icons.sh"
    paint_wlogout_icons
fi

TILE_W=240
TILE_H=176
GAP=16
COLS=3
ROWS=2

grid_w=$((COLS * TILE_W + (COLS - 1) * GAP))
grid_h=$((ROWS * TILE_H + (ROWS - 1) * GAP))

read_geom() {
    python3 - <<'PY'
import json, subprocess, sys
try:
    mons = json.loads(subprocess.check_output(["hyprctl", "-j", "monitors"], text=True))
except Exception:
    sys.exit(1)
mon = next((m for m in mons if m.get("focused")), mons[0] if mons else None)
if not mon:
    sys.exit(1)
scale = float(mon.get("scale") or 1) or 1.0
w = int(round(int(mon["width"]) / scale))
h = int(round(int(mon["height"]) / scale))
print(f"{w} {h}")
PY
}

extra=(--margin 360)
if geom=$(read_geom 2>/dev/null); then
    mon_w=${geom%% *}
    mon_h=${geom##* }
    ml=$(( (mon_w - grid_w) / 2 ))
    mt=$(( (mon_h - grid_h) / 2 ))
    ((ml < 24)) && ml=24
    ((mt < 24)) && mt=24
    extra=(
        --margin-left "$ml"
        --margin-right "$ml"
        --margin-top "$mt"
        --margin-bottom "$mt"
    )
fi

exec wlogout \
    --layout "$conf/layout" \
    --css "$conf/style.css" \
    --protocol layer-shell \
    --buttons-per-row "$COLS" \
    --column-spacing "$GAP" \
    --row-spacing "$GAP" \
    "${extra[@]}"
