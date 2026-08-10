#!/usr/bin/env bash
# rice-select.sh - Interactive Rofi selector for system rices

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWITCH="$SCRIPT_DIR/rice-switch.sh"
[[ -x "$SWITCH" ]] || SWITCH="$HOME/imperivm-dotfiles/rice-switch.sh"
[[ -x "$SWITCH" ]] || SWITCH="$HOME/rice-switch.sh"

OPTIONS="⚜ Imperium Cyber-Sacred\n⚙ Default Rice"

CHOSEN=$(echo -e "$OPTIONS" | rofi -dmenu -p " 👑 Select Rice" -theme-str 'window { width: 420px; } listview { lines: 2; }')

case "$CHOSEN" in
    *"Imperium"*)
        exec "$SWITCH" imperium
        ;;
    *"Default"*)
        exec "$SWITCH" default
        ;;
esac
