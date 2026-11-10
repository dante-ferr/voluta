#!/usr/bin/env bash
# Waybar custom/mpris: print one JSON object while media is playing or paused.
# Empty output hides the module. Built-in mpris skips updates when stopped and
# leaves the last plate visible (Brave and other browsers keep a stopped MPRIS
# endpoint).
set -euo pipefail

status=$(playerctl status 2>/dev/null) || exit 0
case "$status" in
    Playing | Paused) ;;
    *) exit 0 ;;
esac

title=$(playerctl metadata title 2>/dev/null) || exit 0
[[ -n $title ]] || exit 0

/usr/bin/python3 - "$status" "$title" <<'PY'
import json
import sys

status, title = sys.argv[1], sys.argv[2]
payload = {"text": title, "tooltip": f"{status}: {title}"}
if status == "Paused":
    payload["class"] = "paused"
print(json.dumps(payload, ensure_ascii=False))
PY
