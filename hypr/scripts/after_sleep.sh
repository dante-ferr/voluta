#!/usr/bin/env bash
# Portable resume; host renderer recovery lives in the private companion.
# Match StartHypridle.sh: Arch does not necessarily install the optional
# `hostname` command. An empty host silently bypassed personal recovery hooks.
host=$(cat /etc/hostname 2>/dev/null || true)
custom="${XDG_CONFIG_HOME:-$HOME/.config}/voluta/resume/$host.sh"
if [[ -r $custom ]]; then exec bash "$custom"; fi
timeout --kill-after=1s 3s hyprctl dispatch 'hl.dsp.dpms({action = "enable"})'
