#!/bin/sh
# Start input immediately and let the decorative layer leave after Rofi.
config=${XDG_CONFIG_HOME:-$HOME/.config}
directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
assets="$config/wallust/assets/generated"

if ! command -v quickshell >/dev/null || ! command -v jq >/dev/null ||
    [ ! -r "$assets/selector-aperture.png" ] || [ ! -r "$assets/big-angel-box.png" ] ||
    [ ! -r "$assets/launcher-vignette.svg" ]; then
    exec rofi "$@"
fi

# A binary can exist but fail to load after a Qt upgrade. Keep Rofi's own
# artwork unless the renderer can actually start.
if ! quickshell --version >/dev/null 2>&1; then
    printf '%s\n' 'Voluta: Quickshell cannot start; using the static selector frame. Check quickshell --version.' >&2
    exec rofi "$@"
fi

monitor=$(hyprctl -j monitors 2>/dev/null | jq -r '
    .[] | select(.focused) | (.transform // 0) as $rotation |
    (if $rotation % 2 == 0 then [.width, .height] else [.height, .width] end) as $size |
    select($size[0] / .scale >= 1152 and $size[1] / .scale >= 1024) | .name' 2>/dev/null)
colors=$(awk -F "'" '/^wc_(2|4|fg)=/ && length($2) == 6 && $2 ~ /^[[:xdigit:]]+$/ {
    color[$1] = $2
}
END {
    if (color["wc_2="] && color["wc_4="] && color["wc_fg="])
        printf "#%s #%s #%s", color["wc_2="], color["wc_4="], color["wc_fg="]
}' "$config/hypr/wallust/colors-shell.sh" 2>/dev/null)
if [ -z "$monitor" ] || [ -z "$colors" ]; then
    exec rofi "$@"
fi

# Keep stdin for dmenu when the shell backgrounds Rofi to handle signals.
exec 3<&0
rofi -m "$monitor" "$@" \
    -theme-str 'window { background-image: none; } mainbox { background-image: none; }' <&3 3<&- &
selector=$!
exec 3<&-
VOLUTA_SELECTOR_MONITOR=$monitor VOLUTA_SELECTOR_COLORS=$colors VOLUTA_SELECTOR_ASSETS=$assets \
    quickshell -p "$directory/stained-glass.qml" </dev/null >/dev/null 2>&1 &
animation=$!
trap 'kill "$animation" 2>/dev/null; wait "$animation" 2>/dev/null' EXIT
trap 'kill "$selector" 2>/dev/null; exit 143' TERM
trap 'kill "$selector" 2>/dev/null; exit 130' INT
wait "$selector"
status=$?

# Return the selection immediately; the outgoing frame has no input focus.
trap - EXIT
(
    if ! timeout 0.35s quickshell ipc --pid "$animation" call selector dismiss; then
        kill "$animation" 2>/dev/null
    fi
) </dev/null >/dev/null 2>&1 &
exit "$status"
