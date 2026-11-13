#!/bin/sh
# Close every framed menu except the one named in $1
# (selector|notification|music|session). Closed menus have no open-state
# file, so this returns without Quickshell or D-Bus.
keep=${1:-}
config=${XDG_CONFIG_HOME:-$HOME/.config}
here=$(CDPATH= cd -- "${0%/*}" && pwd)
# shellcheck disable=SC1091
. "$here/framed-runtime.sh"
runtime=$(voluta_runtime)

close_selector() {
    [ "$keep" = selector ] && return 0
    found=
    pidfile="$runtime/rofi.pid"
    if [ -r "$pidfile" ]; then
        pid=
        read -r pid < "$pidfile" || :
        case "$pid" in
            0|''|*[!0-9]*) ;;
            *)
                if [ -r "/proc/$pid/comm" ] && read -r name < "/proc/$pid/comm"; then
                    case "$name" in
                        rofi|rofi-wayland) kill "$pid" 2>/dev/null && found=1 ;;
                    esac
                fi
                ;;
        esac
    fi
    if [ -n "$found" ] || voluta_menu_open selector; then
        pkill -x rofi >/dev/null 2>&1 || true
    fi
}

close_notification() {
    [ "$keep" = notification ] && return 0
    voluta_menu_open notification || return 0
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
    voluta_menu_open music || return 0
    pid=$(voluta_renderer_pid music "$config/music/salon.qml") || return 0
    timeout 0.5s quickshell ipc --pid "$pid" call music dismiss "" </dev/null >/dev/null 2>&1 || true
}

close_session() {
    [ "$keep" = session ] && return 0
    voluta_menu_open session || return 0
    pid=$(voluta_renderer_pid session "$config/session-menu/panel.qml") || return 0
    timeout 0.5s quickshell ipc --pid "$pid" call session dismiss "" </dev/null >/dev/null 2>&1 || true
}

close_selector
close_notification
close_music
close_session
