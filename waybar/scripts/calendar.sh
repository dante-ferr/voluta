#!/bin/sh
# Toggle gsimplecal. A second click closes the centered window.
# Drop Waybar's preload so the clock helper is not injected into the calendar.
unset LD_PRELOAD
if pgrep -x gsimplecal >/dev/null 2>&1; then
    pkill -x gsimplecal
    exit 0
fi

real_config="${XDG_CONFIG_HOME:-$HOME/.config}"
runtime="${XDG_RUNTIME_DIR:-/tmp}/voluta-gsimplecal"
mkdir -p "$runtime/gtk-3.0" "$runtime/gsimplecal"
ln -sfn "$real_config/gsimplecal/config" "$runtime/gsimplecal/config"
# User CSS cannot see colors defined by the theme, so copy those tokens in.
python3 - "$real_config/hypr/wallust/colors-gtk.css" "$real_config/gsimplecal/gtk.css" "$runtime/gtk-3.0/gtk.css" <<'PY'
import re
import sys
palette, style, dest = sys.argv[1:]
defines = "\n".join(re.findall(r"@define-color\s+.+;", open(palette, encoding="utf-8").read()))
open(dest, "w", encoding="utf-8").write(defines + "\n\n" + open(style, encoding="utf-8").read())
PY

theme=$(awk -F '=' '/^gtk-theme-name/ { gsub(/[ \t]/, "", $2); print $2; exit }' "$real_config/gtk-3.0/settings.ini")
cat > "$runtime/gtk-3.0/settings.ini" << EOF
[Settings]
gtk-theme-name=${theme}
gtk-application-prefer-dark-theme=1
EOF

center="$real_config/gsimplecal/lib/libgsimplecal_center.so"
if [ -f "$center" ]; then
    export LD_PRELOAD="$center"
    # Keep in sync with calendar.day-number vertical padding in gsimplecal/gtk.css.
    export VOLUTA_GSIMPLECAL_DAY_PAD=14
fi

export XDG_CONFIG_HOME="$runtime"
if command -v gsimplecal >/dev/null 2>&1; then
    exec gsimplecal
fi
exec "${HOME}/.local/bin/gsimplecal"
