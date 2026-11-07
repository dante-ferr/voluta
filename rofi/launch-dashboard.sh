#!/bin/sh
# Toggle the app selector. The theme centers the plate; do not override that.
# Rofi already records its process. Avoid scanning every process on each keypress,
# and verify the name before signalling a PID from a potentially stale file.
pidfile="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/rofi.pid"
pid=
if [ -r "$pidfile" ]; then
    # Rofi's pidfile does not end with a newline.
    read -r pid < "$pidfile" || :
    case "$pid" in
        0|''|*[!0-9]*) ;;
        *)
            if [ -r "/proc/$pid/comm" ] && read -r name < "/proc/$pid/comm"; then
                case "$name" in
                    rofi|rofi-wayland) kill "$pid" 2>/dev/null && exit 0 ;;
                esac
            fi
            ;;
    esac
fi

directory="${XDG_CONFIG_HOME:-$HOME/.config}/rofi"
exec sh "$directory/run-selector.sh" -show drun -theme "$directory/dashboard.rasi"
