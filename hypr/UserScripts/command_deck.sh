#!/usr/bin/env bash
# command_deck.sh - SUPER + CTRL + Return: raise the Imperium Command Deck.
#
# The app launcher stays the centrepiece; two floating kitty panels flank it —
# the heraldic sigil on the left, live telemetry on the right. Everything is
# styled from the current wallust palette and torn down together when the
# launcher closes.

set -uo pipefail

UserScripts="$HOME/.config/hypr/UserScripts"
SIGIL_CLASS="imperium-sigil"
TELEMETRY_CLASS="imperium-telemetry"

# shellcheck source=lib/wallust_env.sh
source "$UserScripts/lib/wallust_env.sh"

close_panels() {
    local cls
    for cls in "$SIGIL_CLASS" "$TELEMETRY_CLASS"; do
        hyprctl dispatch closewindow "class:^(${cls})$" >/dev/null 2>&1
    done
}

deck_is_up() {
    pgrep -x rofi >/dev/null 2>&1 && return 0
    hyprctl clients -j 2>/dev/null | grep -q "\"class\": \"${TELEMETRY_CLASS}\""
}

# Pressing the binding again dismisses whatever is still on screen.
if deck_is_up; then
    pkill -x rofi 2>/dev/null
    close_panels
    exit 0
fi

# Panels borrow the wallust background/foreground directly so they match rofi
# even if kitty has not reloaded its generated theme yet.
panel() {
    local class=$1 title=$2 script=$3
    kitty \
        --class "$class" \
        --title "$title" \
        --override background="#${wc_bg}" \
        --override foreground="#${wc_fg}" \
        --override background_opacity=1.0 \
        --override window_padding_width=10 \
        --override tab_bar_min_tabs=2 \
        --override confirm_os_window_close=0 \
        --override cursor_trail=0 \
        --override font_size=10 \
        -- bash "$script" >/dev/null 2>&1 &
}

panel "$SIGIL_CLASS" "Imperium Sigil" "$UserScripts/imperium_sigil.sh"
panel "$TELEMETRY_CLASS" "Imperium Telemetry" "$UserScripts/imperium_telemetry.sh"

trap close_panels EXIT INT TERM

# Blocks until an app is chosen or Escape is pressed; the panels die with it.
rofi -show drun -modi drun,filebrowser,run,window \
    -theme "$HOME/.config/rofi/dashboard.rasi" >/dev/null 2>&1
