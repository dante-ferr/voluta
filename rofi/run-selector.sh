#!/bin/sh
# Keep the optional stained glass tied to the lifetime of this Rofi invocation.
config=${XDG_CONFIG_HOME:-$HOME/.config}
directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
aperture="$config/wallust/assets/generated/selector-aperture.png"

if ! command -v quickshell >/dev/null || ! command -v jq >/dev/null || [ ! -r "$aperture" ]; then
    exec rofi "$@"
fi

monitor=$(hyprctl -j monitors 2>/dev/null | jq -r '.[] | select(.focused) | .name' 2>/dev/null)
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
VOLUTA_SELECTOR_MONITOR=$monitor VOLUTA_SELECTOR_COLORS=$colors VOLUTA_SELECTOR_APERTURE=$aperture \
    quickshell -p "$directory/stained-glass.qml" </dev/null >/dev/null 2>&1 &
animation=$!
trap 'kill "$animation" 2>/dev/null; wait "$animation" 2>/dev/null' EXIT
exec 3<&0
rofi -m "$monitor" "$@" <&3 3<&- &
selector=$!
exec 3<&-
trap 'kill "$selector" 2>/dev/null; exit 143' TERM
trap 'kill "$selector" 2>/dev/null; exit 130' INT
wait "$selector"
