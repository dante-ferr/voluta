#!/bin/sh
# Start input immediately and let the decorative layer leave after Rofi.
config=${XDG_CONFIG_HOME:-$HOME/.config}
directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
assets="$config/wallust/assets/generated"
renderer="$directory/stained-glass.qml"
runtime=${XDG_RUNTIME_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/voluta}
renderer_pid="$runtime/voluta-selector.pid"
session="${HYPRLAND_INSTANCE_SIGNATURE:-}:${WAYLAND_DISPLAY:-}"
resident=false
if [ -r "$renderer_pid" ] && read -r cached_pid cached_session < "$renderer_pid"; then
    case "$cached_pid" in
        0|''|*[!0-9]*) ;;
        *) [ "$cached_session" != "$session" ] || ! kill -0 "$cached_pid" 2>/dev/null || resident=true ;;
    esac
fi
prewarm=false
if [ "${1:-}" = --prewarm ]; then
    prewarm=true
    shift
fi
if [ "$prewarm" = false ]; then
    sh "$directory/../hypr/scripts/exclusive-framed.sh" selector
fi
selector=
request=$$
launch_selector() {
    # Start the input owner before querying the compositor or palette. Preserve
    # stdin for dmenu, and let Rofi choose the focused output on the warm path.
    exec 3<&0
    rofi "$@" -theme-str 'window { background-image: none; } mainbox { background-image: none; }' <&3 3<&- &
    selector=$!
    exec 3<&-
    trap '(timeout 1s quickshell ipc --pid "$cached_pid" call selector dismiss "$request") </dev/null >/dev/null 2>&1 &' EXIT
    trap 'kill "$selector" 2>/dev/null; exit 143' TERM
    trap 'kill "$selector" 2>/dev/null; exit 130' INT
}
fallback() {
    [ "$prewarm" = false ] || exit 0
    if [ -n "$selector" ]; then
        wait "$selector"
        exit $?
    fi
    exec rofi "$@"
}

if ! command -v quickshell >/dev/null || ! command -v jq >/dev/null ||
    [ ! -r "$assets/selector-aperture.png" ] || [ ! -r "$assets/big-angel-box.png" ] ||
    [ ! -r "$assets/selector-glass.png" ] ||
    [ ! -r "$assets/launcher-vignette.svg" ]; then
    fallback "$@"
fi

# The warmed renderer is already validated. Nothing involving Qt, compositor
# IPC, palette reads, or asset timestamps may precede keyboard ownership here.
if [ "$resident" = true ] && [ "$prewarm" = false ]; then
    launch_selector "$@"
fi

# A binary can exist but fail to load after a Qt upgrade. Keep Rofi's own
# artwork unless the renderer can actually start.
if [ "$resident" = false ] && ! quickshell --version >/dev/null 2>&1; then
    printf '%s\n' 'Voluta: Quickshell cannot start; using the static selector frame. Check quickshell --version.' >&2
    fallback "$@"
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
    fallback "$@"
fi

# The resident renderer keeps Qt, decoded artwork, and graphics resources warm.
# --no-duplicate scopes the singleton to this config and Wayland display.
version=$(stat -c '%y:%s' "$assets/big-angel-box.png" "$assets/launcher-vignette.svg" "$assets/selector-aperture.png" "$assets/selector-glass.png" 2>/dev/null)
start_renderer() {
    mkdir -p "$runtime"
    # Serialize startup/reconciliation, including autostart overlapping a menu.
    # Keep the lock in a subshell so Rofi and the resident daemon cannot inherit it.
    (
        flock -x 4 || exit 1
        VOLUTA_SELECTOR_MONITOR=$monitor VOLUTA_SELECTOR_COLORS=$colors VOLUTA_SELECTOR_ASSETS=$assets VOLUTA_SELECTOR_VERSION=$version \
            quickshell -n -d -p "$renderer" 4>&- </dev/null >/dev/null 2>&1 || exit $?
        keep=
        # Older one-shot renderers can survive a QML hot reload into resident
        # mode. Keep one deterministic instance and close only this config's extras.
        for pid in $(quickshell list -j -p "$renderer" 2>/dev/null | jq -r '.[].pid' 2>/dev/null | sort -nu); do
            case "$pid" in 0|''|*[!0-9]*) continue ;; esac
            kill -0 "$pid" 2>/dev/null || continue
            if [ -z "$keep" ]; then
                keep=$pid
            else
                quickshell kill --pid "$pid" 4>&- >/dev/null 2>&1
            fi
        done
        [ -n "$keep" ] || exit 1
        printf '%s %s\n' "$keep" "$session" > "$renderer_pid.tmp.$$"
        mv -f "$renderer_pid.tmp.$$" "$renderer_pid"
    ) 4> "$runtime/voluta-selector-start.lock" || return $?
    read -r cached_pid cached_session < "$renderer_pid"
}
if [ "$prewarm" = true ]; then
    start_renderer
    exit $?
fi

if [ -z "$selector" ]; then
    launch_selector -m "$monitor" "$@"
fi
if ! timeout 0.25s quickshell ipc --pid "$cached_pid" call selector openSelector \
    "$monitor" "$colors" "$assets" "$request" "$version" </dev/null >/dev/null 2>&1; then
    start_renderer && timeout 1s quickshell ipc --pid "$cached_pid" call selector openSelector \
        "$monitor" "$colors" "$assets" "$request" "$version" </dev/null >/dev/null 2>&1
fi
wait "$selector"
status=$?
exit "$status"
