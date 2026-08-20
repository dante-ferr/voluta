#!/usr/bin/env bash
# combined_wallust.sh - Generate wallust color schemes and reload desktop components
#
# Waypaper's post_command is fire-and-forget and can overlap a refresh already
# in progress. Callers write the requested path to PENDING, then wait briefly
# for the lock. The holder drains PENDING so the latest wallpaper wins.
#
# GTK caches @import CSS, so SIGUSR2 does not pick up a new wallust palette.
# The bar has to be restarted. Hyprland borders are set with keyword IPC
# instead of a full config reload.

wallpaper="$1"

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if [[ -z "$WAYLAND_DISPLAY" ]]; then
    for sock in "$XDG_RUNTIME_DIR"/wayland-*; do
        if [[ -S "$sock" ]]; then
            export WAYLAND_DISPLAY="$(basename "$sock")"
            break
        fi
    done
    export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
fi

_rice_paths="$HOME/.config/hypr/UserScripts/lib/rice_paths.sh"
[[ -r $_rice_paths ]] || _rice_paths="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/rice_paths.sh"
# shellcheck source=lib/rice_paths.sh
source "$_rice_paths"

LOCK_DIR="${XDG_RUNTIME_DIR:-/tmp}"
[[ -n "$LOCK_DIR" && -w "$LOCK_DIR" ]] || LOCK_DIR="/tmp"
LOCK="$LOCK_DIR/imperium-combined-wallust.lock"
PENDING="$LOCK_DIR/imperium-combined-wallust.pending"

if [[ -n "$wallpaper" ]]; then
    pending_tmp="${PENDING}.$$"
    printf '%s\n' "$wallpaper" >"$pending_tmp" && mv -f "$pending_tmp" "$PENDING" || true
    rm -f "$pending_tmp"
fi

exec 9>"$LOCK" || {
    echo "combined_wallust: cannot open lock $LOCK" >&2
    exit 1
}

# Wait a bit so overlapping post_commands coalesce. Give up rather than hang
# forever if a previous refresh is stuck.
if ! flock -w 8 9; then
    echo "combined_wallust: lock busy, leaving $PENDING for the holder" >&2
    exit 0
fi

expand_path() {
    local p="$1"
    p="${p#"${p%%[![:space:]]*}"}"
    p="${p%"${p##*[![:space:]]}"}"
    p="${p#\"}"
    p="${p%\"}"
    p="${p#\'}"
    p="${p%\'}"
    p="${p//\\ / }"
    p="${p/#\~/$HOME}"
    printf '%s\n' "$p"
}

resolve_wallpaper() {
    local wp
    wp=$(expand_path "$1")
    if [[ -n "$wp" && -f "$wp" ]]; then
        printf '%s\n' "$wp"
        return
    fi
    if [[ -n "$wp" ]]; then
        if [[ -f "$HOME/Pictures/Wallpapers/$wp" ]]; then
            printf '%s\n' "$HOME/Pictures/Wallpapers/$wp"
            return
        elif [[ -f "$HOME/Pictures/$wp" ]]; then
            printf '%s\n' "$HOME/Pictures/$wp"
            return
        fi
    fi

    if command -v awww >/dev/null 2>&1; then
        wp=$(awww query 2>/dev/null | grep -o 'image: .*' | head -n 1 | cut -d ' ' -f 2-)
        wp=$(expand_path "$wp")
        if [[ -n "$wp" && -f "$wp" ]]; then
            printf '%s\n' "$wp"
            return
        fi
    fi
    if command -v swww >/dev/null 2>&1; then
        wp=$(swww query 2>/dev/null | grep -o 'image: .*' | head -n 1 | cut -d ' ' -f 2-)
        wp=$(expand_path "$wp")
        if [[ -n "$wp" && -f "$wp" ]]; then
            printf '%s\n' "$wp"
            return
        fi
    fi
    local state_conf="$HOME/.local/state/waypaper/state.ini"
    local waypaper_conf="$HOME/.config/waypaper/config.ini"
    for conf in "$state_conf" "$waypaper_conf"; do
        [[ -f $conf ]] || continue
        wp=$(grep -E '^\s*wallpaper\s*=' "$conf" | head -n 1 | cut -d '=' -f 2- | sed 's/^[ \t]*//')
        wp=${wp%%$'\n'*}
        wp=${wp%%$'\t'*}
        wp=$(expand_path "$wp")
        if [[ -n "$wp" && -f "$wp" ]]; then
            printf '%s\n' "$wp"
            return
        elif [[ -n "$wp" && -f "$HOME/Pictures/Wallpapers/$wp" ]]; then
            printf '%s\n' "$HOME/Pictures/Wallpapers/$wp"
            return
        fi
    done
}

# GTK resolves CSS url() against waybar's working directory (often $HOME),
# not the stylesheet, so relative assets/angel-*.svg paths vanish on any
# machine that does not start waybar from ~/.config/waybar. Write absolute
# file:// URLs after every refresh; style.css imports this when it exists.
write_waybar_angel_css() {
    local waybar_dir css left right lit_left lit_right
    waybar_dir=$(imperium_waybar_dir)
    [[ -d $waybar_dir ]] || return
    mkdir -p "$waybar_dir/wallust"
    left="$waybar_dir/assets/angel-left.svg"
    right="$waybar_dir/assets/angel-right.svg"
    lit_left="$waybar_dir/wallust/angel-left-lit.svg"
    lit_right="$waybar_dir/wallust/angel-right-lit.svg"
    [[ -f $lit_left ]] || lit_left=$left
    [[ -f $lit_right ]] || lit_right=$right
    [[ -f $left && -f $right ]] || return

    css="$waybar_dir/wallust/angel-paths.css"
    cat >"$css" <<EOF
#custom-angel-left {
    background-image: url("file://${left}");
}
#custom-angel-right {
    background-image: url("file://${right}");
}
@keyframes angel-flare-left {
    0% { background-image: url("file://${lit_left}"); }
    100% { background-image: url("file://${left}"); }
}
@keyframes angel-flare-right {
    0% { background-image: url("file://${lit_right}"); }
    100% { background-image: url("file://${right}"); }
}
EOF
}

# Restart the bar. SIGUSR2 does not reload GTK @import of wallust/colors-waybar.css,
# so the palette would stay frozen if we only sent a signal.
launch_waybar() {
    local waybar_dir count=0
    command -v waybar >/dev/null 2>&1 || return

    pkill -x waybar || true
    while pgrep -x waybar >/dev/null 2>&1 && (( count < 10 )); do
        sleep 0.04
        (( count++ ))
    done
    if pgrep -x waybar >/dev/null 2>&1; then
        pkill -9 -x waybar || true
        sleep 0.04
    fi

    waybar_dir=$(imperium_waybar_dir)
    if [[ -d $waybar_dir ]]; then
        (cd "$waybar_dir" && setsid waybar >/dev/null 2>&1 &)
    else
        setsid waybar >/dev/null 2>&1 &
    fi
}

apply_hyprland_colors() {
    command -v hyprctl >/dev/null 2>&1 || return
    local conf="$HOME/.config/hypr/wallust/wallust-hyprland.conf"
    [[ -r $conf ]] || return

    local color1 color0 background hex
    color1=$(sed -n 's/^\$color1 = //p' "$conf")
    color0=$(sed -n 's/^\$color0 = //p' "$conf")
    background=$(sed -n 's/^\$background = //p' "$conf")
    [[ -n $color1 && -n $color0 && -n $background ]] || return

    hex="${background#rgb(}"
    hex="${hex#rgba(}"
    hex="${hex%)}"

    timeout -k 1 2 hyprctl --batch "keyword general:col.active_border ${color1} ; keyword general:col.inactive_border ${color0} ; keyword decoration:shadow:color rgba(${hex}B3) ; keyword decoration:shadow:color_inactive rgba(${hex}59)" >/dev/null 2>&1 || true
}

finish_refresh() {
    if command -v magick >/dev/null 2>&1; then
        local asset_dir source_img dest_img
        asset_dir=$(imperium_fastfetch_assets)
        mkdir -p "$asset_dir"
        source_img="$asset_dir/crown-angels.jpg"
        dest_img="$asset_dir/crown-angels-styled.png"
        if [[ -f $source_img && ( ! -f $dest_img || $source_img -nt $dest_img ) ]]; then
            magick "$source_img" -fuzz 14% -transparent black \
                "$dest_img" >/dev/null 2>&1 || true
        fi
    fi

    if command -v swaync-client >/dev/null 2>&1; then
        swaync-client -R -rs >/dev/null 2>&1 || true
    fi

    if command -v kitty >/dev/null 2>&1; then
        pkill -SIGUSR1 -x kitty >/dev/null 2>&1 || true
        if [[ -f "$HOME/.config/kitty/kitty-themes/01-Wallust.conf" ]]; then
            kitty @ set-colors --all "$HOME/.config/kitty/kitty-themes/01-Wallust.conf" >/dev/null 2>&1 || true
        fi
    fi

    if command -v cava >/dev/null 2>&1; then
        pkill -USR2 cava >/dev/null 2>&1 || true
    fi

    if [[ -r $HOME/.config/wlogout/paint-icons.sh ]]; then
        # shellcheck source=/dev/null
        source "$HOME/.config/wlogout/paint-icons.sh"
        paint_wlogout_icons
    fi
}

do_refresh() {
    local wp="$1"

    # Quiet is a global flag (`wallust -q run …`). Passing -q to `run` makes
    # wallust v4 treat it as the image path and skip palette generation.
    if [[ -n "$wp" && -f "$wp" ]] && command -v wallust >/dev/null 2>&1; then
        wallust run -s "$wp"
    fi

    write_waybar_angel_css
    launch_waybar
    apply_hyprland_colors

    finish_refresh &
    disown $! 2>/dev/null || true
}

last_wp=""
while true; do
    if [[ -r "$PENDING" ]]; then
        wallpaper=$(cat "$PENDING")
        rm -f "$PENDING"
    elif [[ -n "$last_wp" ]]; then
        break
    fi
    wallpaper=$(resolve_wallpaper "$wallpaper")
    if [[ -z "$last_wp" || ( -n "$wallpaper" && "$wallpaper" != "$last_wp" ) ]]; then
        do_refresh "$wallpaper"
        last_wp="${wallpaper:-__none__}"
    fi
done
