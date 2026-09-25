#!/usr/bin/env bash
# Pick hypridle.conf, or hypridle.<hostname>.conf when that file exists.
# pgrep is the guard: a second start must not stack daemons.

host=$(cat /etc/hostname 2>/dev/null || true)
base="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
conf="$base/hypridle.conf"
if [[ -n $host && -f "$base/hypridle.${host}.conf" ]]; then
    conf="$base/hypridle.${host}.conf"
fi

if pgrep -x hypridle >/dev/null; then
    exit 0
fi

hypridle -c "$conf" >/dev/null 2>&1 &
