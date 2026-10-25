#!/usr/bin/env bash
# Tint the power-tablet line art with the live wallust accent and rasterize
# it. GTK3 blurs SVGs as soon as it scales them; a 64×64 PNG is painted 1:1.

paint_wlogout_icons() {
    local dir="${XDG_CONFIG_HOME:-$HOME/.config}/wlogout"
    local src="${XDG_CONFIG_HOME:-$HOME/.config}/wallust/assets"
    local svg_out="$src/generated"
    local out="$dir/wallust"
    mkdir -p "$out" "$svg_out"

    local lib="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/UserScripts/lib/wallust_env.sh"
    # shellcheck source=/dev/null
    [[ -r $lib ]] && source "$lib"

    local accent="${wc_1:-C9A227}"
    accent="${accent#\#}"
    if declare -F mix >/dev/null 2>&1; then
        # Same lift waybar applies to @color1 (lighten 0.30).
        accent=$(mix "$accent" "FFFFFF" 30)
    fi

    local name
    local pids=()
    for name in lock logout suspend hibernate reboot shutdown; do
        [[ -f $src/wlogout-$name.svg ]] || continue
        (
            sed "s/#C9A227/#${accent}/g" "$src/wlogout-$name.svg" >"$svg_out/wlogout-$name.svg"
            if command -v rsvg-convert >/dev/null 2>&1; then
                rsvg-convert -w 64 -h 64 -f png --background-color none \
                    -o "$out/$name.png" "$svg_out/wlogout-$name.svg" >/dev/null 2>&1 || true
            elif command -v magick >/dev/null 2>&1; then
                magick -background none "$svg_out/wlogout-$name.svg" PNG32:"$out/$name.png" >/dev/null 2>&1 || true
            fi
        ) &
        pids+=($!)
    done
    local pid
    for pid in "${pids[@]}"; do
        wait "$pid" || true
    done
}

# Allow `bash paint-icons.sh` as well as sourcing.
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    paint_wlogout_icons
fi
