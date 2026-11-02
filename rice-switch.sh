#!/usr/bin/env bash
# Compatibility entry point; safe switching is owned by Voluta.
set -euo pipefail
root=$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")
exec "$root/bin/voluta" rice-switch "$@"
