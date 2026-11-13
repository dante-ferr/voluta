#!/bin/sh
# Toggle the music salon through Quickshell IPC. SIGUSR1 is only a fallback.
config=${XDG_CONFIG_HOME:-$HOME/.config}
runtime=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
rice=$(CDPATH= cd -- "$(dirname -- "$(readlink -f -- "$0")")/.." && pwd)
renderer=$(readlink -f -- "$config/music/salon.qml")
watcher="$config/music/watch.py"
pidfile="$runtime/voluta-music.pid"

renderer_pid() {
    voluta_renderer_pid music "$renderer"
}

menu_publication() {
    PYTHONPATH="$rice${PYTHONPATH:+:$PYTHONPATH}" python3 "$rice/voluta/menus.py" "$1" 2>/dev/null
}

ipc_toggle() {
    pid=$1
    [ -n "$pid" ] || return 1
    kill -0 "$pid" 2>/dev/null || return 1
    colors=
    assets=
    version=
    if [ "${2:-}" != close ]; then
        publication=$(menu_publication music) || publication=
        if [ -n "$publication" ]; then
            colors=$(printf '%s\n' "$publication" | sed -n '1p')
            assets=$(printf '%s\n' "$publication" | sed -n '2p')
            version=$(printf '%s\n' "$publication" | sed -n '3p')
        fi
    fi
    # Closing ignores these. Opening applies the same publication as the selector.
    timeout 0.5s quickshell ipc --pid "$pid" call music toggle "$colors" "$assets" "$version" </dev/null >/dev/null 2>&1
}

signal_watcher() {
    [ -r "$pidfile" ] || return 1
    pid=$(tr -dc '0-9' < "$pidfile")
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && kill -USR1 "$pid"
}

start_watcher() {
    mkdir -p "${XDG_STATE_HOME:-$HOME/.local/state}/voluta" "$runtime"
    setsid -f /usr/bin/python3 "$watcher" >>"${XDG_STATE_HOME:-$HOME/.local/state}/voluta/music-salon.log" 2>&1 </dev/null
}

ensure_watcher() {
    if [ -r "$pidfile" ]; then
        wpid=$(tr -dc '0-9' < "$pidfile")
        [ -n "$wpid" ] && kill -0 "$wpid" 2>/dev/null && return 0
    fi
    start_watcher
}

root=$(CDPATH= cd -- "${0%/*}/.." && pwd)
# shellcheck disable=SC1091
. "$root/hypr/scripts/framed-runtime.sh"
pid=$(renderer_pid) || pid=
# Closing does not republish the palette or walk the other menus.
if voluta_menu_open music && ipc_toggle "$pid" close; then
    ensure_watcher
    exit 0
fi
sh "$root/hypr/scripts/exclusive-framed.sh" music

if ipc_toggle "$pid"; then
    ensure_watcher
    exit 0
fi
if signal_watcher && ipc_toggle "$(renderer_pid)"; then
    exit 0
fi
start_watcher
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    sleep 0.1
    ipc_toggle "$(renderer_pid)" && exit 0
done
signal_watcher
exit 1
