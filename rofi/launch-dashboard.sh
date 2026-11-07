#!/bin/sh
# Toggle the app selector. The theme centers the plate; do not override that.
if pkill rofi; then
    exit 0
fi

directory="${XDG_CONFIG_HOME:-$HOME/.config}/rofi"
exec sh "$directory/run-selector.sh" -show drun -theme "$directory/dashboard.rasi"
