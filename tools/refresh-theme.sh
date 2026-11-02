#!/usr/bin/env bash
# Refresh Wallust consumers from the deployed tree, or this checkout before install.
set -euo pipefail
root=$(dirname -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")")
deployed="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/UserScripts/combined_wallust.sh"
if [[ -r $deployed ]]; then
  exec bash "$deployed" "$@"
fi
exec bash "$root/hypr/UserScripts/combined_wallust.sh" "$@"
