#!/bin/sh
# Toggle the native panel directly; opening must not wait on client-side setup.
if root=$(CDPATH= cd -- "${0%/*}/.." && pwd); then
    /bin/sh "$root/hypr/scripts/exclusive-framed.sh" notification || true
    if command -v quickshell >/dev/null 2>&1; then
        runtime=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
        pidfile=$runtime/voluta-notification-glass.pid
        alive=
        if [ -r "$pidfile" ]; then
            pid=$(tr -dc '0-9' < "$pidfile")
            [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && alive=1
        fi
        if [ -z "$alive" ]; then
            mkdir -p "${XDG_STATE_HOME:-$HOME/.local/state}/voluta"
            setsid -f /usr/bin/python3 "$root/swaync/watch-glass.py" \
                >>"${XDG_STATE_HOME:-$HOME/.local/state}/voluta/notification-glass.log" 2>&1 </dev/null
        fi
    fi
fi
if command -v gdbus >/dev/null 2>&1; then
    exec gdbus call --session --timeout 5 \
        --dest org.erikreider.swaync.cc \
        --object-path /org/erikreider/swaync/cc \
        --method org.erikreider.swaync.cc.ToggleVisibility >/dev/null
fi
exec swaync-client -t -sw
