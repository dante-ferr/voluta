#!/usr/bin/env bash
# Pick hypridle.conf, or hypridle.<hostname>.conf when that file exists.
# pgrep is the guard: a second start must not stack daemons.

host=$(cat /etc/hostname 2>/dev/null || true)
base="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
conf="$base/hypridle.conf"
personal="${XDG_CONFIG_HOME:-$HOME/.config}/voluta/idle/$host.conf"
[[ -r $personal ]] && conf="$personal"

if pgrep -x hypridle >/dev/null; then
    exit 0
fi

# Retain lifecycle/errors across reboots without enabling input tracing.
umask 077
state="${XDG_STATE_HOME:-$HOME/.local/state}/voluta/lock"
mkdir -p "$state" || exit 1
log="$state/hypridle.log"
if [[ -f "$log" && $(stat -c %s "$log") -gt 1048576 ]]; then
    mv -f "$log" "$log.1"
fi
printf '\n[%s] starting hypridle config=%s\n' "$(date -Is)" "$conf" >>"$log"
hypridle -c "$conf" >>"$log" 2>&1 &
