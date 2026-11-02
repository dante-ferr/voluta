#!/usr/bin/env bash
# Produce a local runtime config when a companion selects an output.
waybar_config_args=()
waybar_prepare_config() {
    waybar_config_args=()
    local src=${1:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar/config} root dest
    root=$(dirname -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")")
    dest="${XDG_RUNTIME_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}}/voluta-waybar-config.json"
    if python3 "$root/../voluta/runtime.py" waybar "$src" "$dest"; then
        waybar_config_args=(-c "$dest")
    fi
}
