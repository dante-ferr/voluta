#!/bin/sh
# Keep GTK's cold GPU initialization off the notification opening path.
# Respect an explicit renderer chosen by the owner or service environment.
# The control center's top margin is rewritten from the Hyprland window grid.
: "${GSK_RENDERER:=cairo}"
export GSK_RENDERER
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo=$(CDPATH= cd -- "$here/.." && pwd)
runtime="${XDG_RUNTIME_DIR:-/tmp}/voluta"
config=$here/config.json
if command -v python3 >/dev/null 2>&1 && command -v hyprctl >/dev/null 2>&1; then
    mkdir -p "$runtime"
    if python3 "$repo/voluta/window_grid.py" --swaync-config "$config" "$runtime/swaync-config.json"; then
        config=$runtime/swaync-config.json
    fi
fi
exec /usr/bin/swaync -c "$config" -s "$here/style.css" "$@"
