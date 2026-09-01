#!/usr/bin/env bash
# command_deck.sh - SUPER + CTRL + Return: launch app menu.

set -uo pipefail

if pgrep -x rofi >/dev/null 2>&1; then
    pkill -x rofi 2>/dev/null
    exit 0
fi

exec rofi -show drun -modi drun,filebrowser,run,window \
    -theme "$HOME/.config/rofi/dashboard.rasi"
