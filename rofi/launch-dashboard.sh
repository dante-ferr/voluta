#!/bin/sh
# Toggle the app selector. The theme centers the plate; do not override that.
if pkill rofi; then
    exit 0
fi

theme="${XDG_CONFIG_HOME:-$HOME/.config}/rofi/dashboard.rasi"
exec rofi -show drun -theme "$theme"
