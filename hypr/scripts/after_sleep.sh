#!/usr/bin/env bash
# Portable resume; host renderer recovery lives in the private companion.
host=$(hostname)
custom="${XDG_CONFIG_HOME:-$HOME/.config}/voluta/resume/$host.sh"
if [[ -r $custom ]]; then exec bash "$custom"; fi
hyprctl dispatch 'hl.dsp.dpms({action = "on"})' >/dev/null 2>&1 || true
