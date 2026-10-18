#!/usr/bin/env bash
# Start a single waybar from its config dir so CSS url("assets/...") resolves.
# No-op if waybar is already running (combined_wallust / Refresh restart explicitly).

pgrep -x waybar >/dev/null 2>&1 && exit 0
command -v waybar >/dev/null 2>&1 || exit 0

waybar_dir=$(readlink -f "${HOME}/.config/waybar" 2>/dev/null || true)
shim="${waybar_dir}/lib/libwaybar_hyprland_shim.so"
if [[ -f $shim ]]; then
    export LD_PRELOAD="$shim${LD_PRELOAD:+:$LD_PRELOAD}"
fi

# shellcheck source=waybar-config.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/waybar-config.sh"
waybar_prepare_config "${waybar_dir:+$waybar_dir/config}"

if [[ -d ${waybar_dir:-} ]]; then
    python3 "$waybar_dir/scripts/render-decorations.py"
    (cd "$waybar_dir" && exec waybar "${waybar_config_args[@]}")
else
    exec waybar "${waybar_config_args[@]}"
fi
