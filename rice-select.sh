#!/usr/bin/env bash
# rice-select.sh - Interactive Rofi selector for system rices

OPTIONS="⚜ Imperium Cyber-Sacred\n⚙ Default Rice"

CHOSEN=$(echo -e "$OPTIONS" | rofi -dmenu -p " 👑 Select Rice" -theme-str 'window { width: 420px; } listview { lines: 2; }')

case "$CHOSEN" in
    *"Imperium"*)
        exec "$HOME/rice-switch.sh" imperium
        ;;
    *"Default"*)
        exec "$HOME/rice-switch.sh" default
        ;;
esac
