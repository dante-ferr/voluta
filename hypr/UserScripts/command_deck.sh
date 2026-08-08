#!/usr/bin/env bash
# command_deck.sh - SUPER + CTRL + Return: raise the Imperium Command Deck.
#
# The app launcher stays the centrepiece; two floating kitty panels flank it —
# the heraldic sigil on the left, live telemetry on the right. Everything is
# styled from the current wallust palette.
#
# The three windows behave as one cluster: whichever member goes first — an app
# chosen, Escape, rofi losing focus, or either panel closed by hand — takes the
# other two down with it.

set -uo pipefail

UserScripts="$HOME/.config/hypr/UserScripts"
SIGIL_CLASS="imperium-sigil"
TELEMETRY_CLASS="imperium-telemetry"

# shellcheck source=lib/wallust_env.sh
source "$UserScripts/lib/wallust_env.sh"

SIGIL_SCRIPT="$UserScripts/imperium_sigil.sh"
TELEMETRY_SCRIPT="$UserScripts/imperium_telemetry.sh"
CLUSTER_PIDS=()

# Below this the launcher already takes most of the screen and the wings would be
# unreadable slivers, so the deck degrades to the launcher on its own. Compared
# against logical, not physical, size: a scaled output has fewer usable pixels.
MIN_DECK_W=1280
MIN_DECK_H=600

monitor_fits_wings() {
    local w h
    read -r w h < <(hyprctl monitors -j 2>/dev/null |
        jq -r 'first(.[] | select(.focused)) | "\(.width / .scale | round) \(.height / .scale | round)"' \
            2>/dev/null)
    # If the geometry cannot be read, show the wings rather than silently dropping them.
    [[ -z ${w:-} || -z ${h:-} ]] && return 0
    ((w >= MIN_DECK_W && h >= MIN_DECK_H))
}

# Teardown signals processes rather than asking Hyprland to close windows: this
# config is Lua, so hyprctl's dispatch parser reads `closewindow class:...` as
# Lua and rejects it. Killing a panel's kitty makes its window vanish anyway.
# The pkill pass is the fallback that catches panels orphaned by an earlier run,
# matching on the script paths, which only the panels carry in their cmdline.
close_deck() {
    local pid
    for pid in ${CLUSTER_PIDS[@]+"${CLUSTER_PIDS[@]}"}; do
        kill "$pid" 2>/dev/null
    done
    pkill -f "$SIGIL_SCRIPT" 2>/dev/null
    pkill -f "$TELEMETRY_SCRIPT" 2>/dev/null
}

deck_is_up() {
    pgrep -x rofi >/dev/null 2>&1 && return 0
    pgrep -f "$TELEMETRY_SCRIPT" >/dev/null 2>&1
}

# Pressing the binding again dismisses whatever is still on screen.
if deck_is_up; then
    pkill -x rofi 2>/dev/null
    close_deck
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
    CLUSTER_PIDS+=("$!")
}

trap close_deck EXIT INT TERM HUP

if monitor_fits_wings; then
    panel "$SIGIL_CLASS" "Imperium Sigil" "$SIGIL_SCRIPT"
    panel "$TELEMETRY_CLASS" "Imperium Telemetry" "$TELEMETRY_SCRIPT"
fi

rofi -show drun -modi drun,filebrowser,run,window \
    -theme "$HOME/.config/rofi/dashboard.rasi" >/dev/null 2>&1 &
CLUSTER_PIDS+=("$!")

# Returns as soon as any one of the three exits; the exit trap then closes the
# survivors, so the cluster always lives and dies together.
wait -n
