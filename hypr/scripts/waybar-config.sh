#!/usr/bin/env bash
# Host-specific waybar config arguments.
#
# frank: the bar is bound to DP-2, the 200 Hz main display. HDMI-A-1 stays bare.
# frank-notebook and any other host keep waybar/config unchanged, so the bar
# stays on every output (the notebook panel is eDP-1).
#
# This waybar build has no --output flag. The output key has to live in the
# config. A runtime copy keeps waybar/config as the single source.

waybar_config_args=()

waybar_prepare_config() {
    waybar_config_args=()
    local host src runtime dest
    host=$(cat /etc/hostname 2>/dev/null || true)
    host=${host%%$'\n'*}
    [[ $host == frank ]] || return 0

    src=${1:-}
    if [[ -z $src ]]; then
        src=$(readlink -f "${HOME}/.config/waybar/config" 2>/dev/null || true)
    fi
    [[ -f $src ]] || return 0

    runtime=${XDG_RUNTIME_DIR:-}
    [[ -n $runtime && -w $runtime ]] || runtime=/tmp
    dest=$runtime/imperium-waybar-config.json

    if ! python3 - "$src" "$dest" <<'PY'
import json
import sys

src, dest = sys.argv[1], sys.argv[2]
with open(src, encoding="utf-8") as handle:
    data = json.load(handle)
data["output"] = "DP-2"
with open(dest, "w", encoding="utf-8") as handle:
    json.dump(data, handle)
    handle.write("\n")
PY
    then
        waybar_config_args=()
        return 0
    fi
    waybar_config_args=(-c "$dest")
}
