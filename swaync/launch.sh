#!/bin/sh
# Keep GTK's cold GPU initialization off the notification opening path.
# Respect an explicit renderer chosen by the owner or service environment.
: "${GSK_RENDERER:=cairo}"
export GSK_RENDERER
exec /usr/bin/swaync "$@"
