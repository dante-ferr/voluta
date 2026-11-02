#!/usr/bin/env bash
# Compatibility wrapper; system setup remains an explicit optional action.
set -euo pipefail
root=$(dirname -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")")
exec "$root/bin/voluta" system-setup sddm "$@"
