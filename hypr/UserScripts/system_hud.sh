#!/usr/bin/env bash
# system_hud.sh - Interactive Imperium System Telemetry & Heraldic HUD Window

# If not running inside Kitty or if called from Hyprland keybind, spawn in dedicated floating window
if [[ "$1" != "--internal" ]]; then
    kitty --class "system-hud" --title "Voluta System Telemetry HUD" bash "$0" --internal
    exit 0
fi

clear
# Display Fastfetch with Baroque Artwork & Latin Specs
# --force because this window exists only to show the fetch: the size rule that
# keeps it out of small shells would otherwise leave the HUD blank.
if [[ -x "$HOME/.config/fastfetch/fetch.sh" ]]; then
    "$HOME/.config/fastfetch/fetch.sh" --force
elif [[ -f "$HOME/.config/fastfetch/config.jsonc" ]]; then
    fastfetch --config "$HOME/.config/fastfetch/config.jsonc"
else
    fastfetch
fi

echo ""
echo -e "\e[1;33m════════════════════════════════════════════════════════════════════════════════\e[0m"
echo -e "  \e[1;37m[m]\e[0m \e[0;33mHardware Monitor (Btop)\e[0m   │   \e[1;37m[w]\e[0m \e[0;33mWallpaper (Waypaper)\e[0m   │   \e[1;37m[a]\e[0m \e[0;33mApp Browser\e[0m   │   \e[1;37m[q]\e[0m \e[0;33mExit\e[0m"
echo -e "\e[1;33m════════════════════════════════════════════════════════════════════════════════\e[0m"

read -n 1 -s -r key
case "$key" in
    m|M)
        exec btop
        ;;
    w|W)
        waypaper >/dev/null 2>&1 &
        exit 0
        ;;
    a|A)
        "$HOME/.config/rofi/dashboard.sh" >/dev/null 2>&1 &
        exit 0
        ;;
    q|Q|$'\e')
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
