#!/bin/sh
# Close every framed menu except the one named in $1
# (selector|notification|music|session).
keep=${1:-}
config=${XDG_CONFIG_HOME:-$HOME/.config}
runtime=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}

close_selector() {
    [ "$keep" = selector ] && return 0
    pidfile="$runtime/rofi.pid"
    if [ -r "$pidfile" ]; then
        pid=
        read -r pid < "$pidfile" || :
        case "$pid" in
            0|''|*[!0-9]*) ;;
            *)
                if [ -r "/proc/$pid/comm" ] && read -r name < "/proc/$pid/comm"; then
                    case "$name" in
                        rofi|rofi-wayland) kill "$pid" 2>/dev/null ;;
                    esac
                fi
                ;;
        esac
    fi
    pkill -x rofi >/dev/null 2>&1 || true
}

close_notification() {
    [ "$keep" = notification ] && return 0
    if command -v gdbus >/dev/null 2>&1; then
        gdbus call --session --timeout 2 \
            --dest org.erikreider.swaync.cc \
            --object-path /org/erikreider/swaync/cc \
            --method org.erikreider.swaync.cc.SetVisibility false \
            >/dev/null 2>&1 && return 0
    fi
    command -v swaync-client >/dev/null 2>&1 || return 0
    swaync-client -cp -sw >/dev/null 2>&1 || true
}

close_music() {
    [ "$keep" = music ] && return 0
    command -v quickshell >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || return 0
    renderer=$(readlink -f -- "$config/music/salon.qml")
    [ -n "$renderer" ] || return 0
    pid=$(quickshell list -j -p "$renderer" 2>/dev/null | jq -r '.[].pid // empty' 2>/dev/null |
        awk 'NF && $1 ~ /^[0-9]+$/ { print; exit }')
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null || return 0
    timeout 0.5s quickshell ipc --pid "$pid" call music dismiss "" </dev/null >/dev/null 2>&1 || true
}

close_session() {
    [ "$keep" = session ] && return 0
    command -v quickshell >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || return 0
    renderer=$(readlink -f -- "$config/session-menu/panel.qml")
    [ -n "$renderer" ] || return 0
    pid=$(quickshell list -j -p "$renderer" 2>/dev/null | jq -r '.[].pid // empty' 2>/dev/null |
        awk 'NF && $1 ~ /^[0-9]+$/ { print; exit }')
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null || return 0
    timeout 0.5s quickshell ipc --pid "$pid" call session dismiss "" </dev/null >/dev/null 2>&1 || true
}

close_selector
close_notification
close_music
close_session
