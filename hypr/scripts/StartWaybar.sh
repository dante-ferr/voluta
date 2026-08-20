#!/usr/bin/env bash
# Start a single waybar from its config dir so CSS url("assets/...") resolves.
# No-op if waybar is already running (combined_wallust / Refresh restart explicitly).

pgrep -x waybar >/dev/null 2>&1 && exit 0
command -v waybar >/dev/null 2>&1 || exit 0

waybar_dir=$(readlink -f "${HOME}/.config/waybar" 2>/dev/null || true)
if [[ -d ${waybar_dir:-} ]]; then
    (cd "$waybar_dir" && exec waybar)
else
    exec waybar
fi
