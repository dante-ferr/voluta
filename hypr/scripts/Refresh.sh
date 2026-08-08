#!/usr/bin/env bash
# Environment refresh tool for Hyprland, Waybar, and SwayNC

# 1. Reload Hyprland Window Manager
hyprctl reload >/dev/null 2>&1 || true

# 2. Restart Waybar
pkill -x waybar || true
sleep 0.15
waybar >/dev/null 2>&1 &

# 3. Reload SwayNC Notification Center
if command -v swaync-client >/dev/null 2>&1; then
    swaync-client -R -rs >/dev/null 2>&1 || (pkill -x swaync || true; swaync >/dev/null 2>&1 &)
fi

notify-send -t 2000 -u low -i "view-refresh" "Desktop Refreshed" "Hyprland, Waybar, and SwayNC reloaded."
