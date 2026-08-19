#!/usr/bin/env bash
# Environment refresh tool for Hyprland, Waybar, and SwayNC

# 1. Reload Hyprland Window Manager
hyprctl reload >/dev/null 2>&1 || true

# 2. Restart Waybar from its config dir so CSS url("assets/...") resolves.
pkill -x waybar || true
sleep 0.15
waybar_dir=$(readlink -f "${HOME}/.config/waybar" 2>/dev/null || true)
if [[ -d ${waybar_dir:-} ]]; then
    (cd "$waybar_dir" && waybar >/dev/null 2>&1 &)
else
    waybar >/dev/null 2>&1 &
fi

# 3. Reload SwayNC Notification Center
if command -v swaync-client >/dev/null 2>&1; then
    swaync-client -R -rs >/dev/null 2>&1 || (pkill -x swaync || true; swaync >/dev/null 2>&1 &)
fi

notify-send -t 2000 -u low -i "view-refresh" "Desktop Refreshed" "Hyprland, Waybar, and SwayNC reloaded."
