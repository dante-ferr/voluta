#!/usr/bin/env bash
# combined_wallust.sh - Generate wallust color schemes and reload desktop components
#
# Waypaper runs post_command once per monitor on --restore, in parallel. Without
# coordination that stacks one waybar per display. Only one refresh runs at a
# time; concurrent callers leave a pending wallpaper path and exit so the holder
# can re-run once with the latest request.

wallpaper="$1"

LOCK_DIR="${XDG_RUNTIME_DIR:-/tmp}"
[[ -n "$LOCK_DIR" && -w "$LOCK_DIR" ]] || LOCK_DIR="/tmp"
LOCK="$LOCK_DIR/imperium-combined-wallust.lock"
PENDING="$LOCK_DIR/imperium-combined-wallust.pending"

if [[ -n "$wallpaper" ]]; then
    printf '%s\n' "$wallpaper" >"$PENDING" || true
fi

exec 9>"$LOCK" || {
    echo "combined_wallust: cannot open lock $LOCK" >&2
    exit 1
}

# Non-blocking: if another refresh owns the lock, our path is already in
# PENDING for it to pick up at the end of its loop.
if ! flock -n 9; then
    exit 0
fi

resolve_wallpaper() {
    local wp=$1
    if [[ -n "$wp" && -f "$wp" ]]; then
        printf '%s\n' "$wp"
        return
    fi
    if command -v awww >/dev/null 2>&1; then
        wp=$(awww query 2>/dev/null | grep -o 'image: .*' | head -n 1 | cut -d ' ' -f 2-)
        if [[ -n "$wp" && -f "$wp" ]]; then
            printf '%s\n' "$wp"
            return
        fi
    fi
    if command -v swww >/dev/null 2>&1; then
        wp=$(swww query 2>/dev/null | grep -o 'image: .*' | head -n 1 | cut -d ' ' -f 2-)
        if [[ -n "$wp" && -f "$wp" ]]; then
            printf '%s\n' "$wp"
            return
        fi
    fi
    local waypaper_conf="$HOME/.config/waypaper/config.ini"
    if [[ -f "$waypaper_conf" ]]; then
        wp=$(grep -E '^\s*wallpaper\s*=' "$waypaper_conf" | head -n 1 | cut -d '=' -f 2- | sed 's/^[ \t]*//' | sed "s|^~|$HOME|")
        if [[ -n "$wp" && -f "$wp" ]]; then
            printf '%s\n' "$wp"
            return
        fi
    fi
}

do_refresh() {
    local wp=$1

    if [[ -n "$wp" && -f "$wp" ]] && command -v wallust >/dev/null 2>&1; then
        wallust run "$wp"
    fi

    # Optional derived fetch asset (sigil fallback). The terminal fetch uses the
    # tracked transparent PNG directly; this keeps a black-keyed twin for anything
    # that still expects crown-angels-styled.png.
    if command -v magick >/dev/null 2>&1; then
        local asset_dir="$HOME/.config/fastfetch/assets"
        mkdir -p "$asset_dir"
        local source_img="$asset_dir/crown-angels.jpg"
        if [[ -f "$source_img" ]]; then
            magick "$source_img" -fuzz 14% -transparent black \
                "$asset_dir/crown-angels-styled.png" >/dev/null 2>&1 || true
        fi
    fi

    # hyprctl can block if the compositor is busy; never hold the lock forever.
    if command -v hyprctl >/dev/null 2>&1; then
        timeout 3 hyprctl reload >/dev/null 2>&1 || true
    fi

    if command -v waybar >/dev/null 2>&1; then
        pkill -x waybar || true
        sleep 0.2
        pkill -x waybar || true
        nohup waybar >/dev/null 2>&1 &
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

# Drain PENDING until concurrent callers stop stacking requests.
while true; do
    if [[ -r "$PENDING" ]]; then
        wallpaper=$(cat "$PENDING")
        rm -f "$PENDING"
    fi
    wallpaper=$(resolve_wallpaper "$wallpaper")
    do_refresh "$wallpaper"
    [[ -r "$PENDING" ]] || break
done
