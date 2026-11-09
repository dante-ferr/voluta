#!/usr/bin/env bash
# Start the top-edge light that Waybar's decorations rely on for contrast.
# Pass --restart to replace a running instance so QML changes load.
command -v quickshell >/dev/null 2>&1 || exit 0
qml=$(readlink -f "${HOME}/.config/waybar/glow.qml" 2>/dev/null || true)
[[ -f $qml ]] || exit 0
if [[ ${1:-} == --restart ]]; then
    if quickshell kill -p "$qml" >/dev/null 2>&1; then
        # -n refuses to start while the old instance is still exiting.
        for _ in {1..25}; do
            quickshell list -p "$qml" 2>/dev/null | grep -q . || break
            sleep 0.1
        done
    fi
fi
exec quickshell -n -d -p "$qml" >/dev/null 2>&1
