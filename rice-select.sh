#!/usr/bin/env bash
# rice-select.sh - Interactive Rofi selector for system rices

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWITCH_SCRIPT="$SCRIPT_DIR/rice-switch.sh"
[[ ! -f "$SWITCH_SCRIPT" ]] && SWITCH_SCRIPT="$HOME/imperivm-dotfiles/rice-switch.sh"
[[ ! -f "$SWITCH_SCRIPT" ]] && SWITCH_SCRIPT="$HOME/rice-switch.sh"

OPTIONS="⚜ Imperium Cyber-Sacred\n⚙ Default Rice"

CHOSEN=$(echo -e "$OPTIONS" | rofi -dmenu -p " 👑 Select Rice" -theme-str 'window { width: 420px; } listview { lines: 2; }')

case "$CHOSEN" in
    *"Imperium"*)
        exec "$SWITCH_SCRIPT" imperium
        ;;
    *"Default"*)
        exec "$SWITCH_SCRIPT" default
        ;;
esac
