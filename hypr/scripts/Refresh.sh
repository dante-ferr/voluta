#!/usr/bin/env bash
# Reload the live session after a checkout sync.
# voluta update copies the checkout only when it is newer or a deployed file
# is missing, and it publishes frames once. This script reloads Hyprland,
# Waybar, SwayNC, and the top glow only when their files changed.

config_home=${XDG_CONFIG_HOME:-$HOME/.config}
state_home=${XDG_STATE_HOME:-$HOME/.local/state}
refresh_script=$(readlink -f -- "${BASH_SOURCE[0]}")
rice_root=$(cd -- "$(dirname -- "$refresh_script")/../.." && pwd)
generated=$config_home/wallust/assets/generated

tree_fingerprint() {
    local path
    {
        for path in "$@"; do
            [[ -e $path || -L $path ]] || continue
            find -H "$path" \( -type f -o -type l \) -printf '%p %s %T@\n' 2>/dev/null
        done
    } | LC_ALL=C sort | sha256sum | awk '{print $1}'
}

file_hash() {
    sha256sum "$@" 2>/dev/null | LC_ALL=C sort | sha256sum | awk '{print $1}'
}

# Sample before the copy so a real deploy shows up as a difference afterward.
hypr_before=$(tree_fingerprint "$config_home/hypr")
waybar_before=$(tree_fingerprint "$config_home/waybar" "$generated/waybar")
swaync_before=$(tree_fingerprint "$config_home/swaync" \
    "$generated/notification-aperture.png" "$generated/notification-glass.png" \
    "$generated/launcher-vignette.svg")
glow_before=$(tree_fingerprint "$config_home/waybar/glow.qml" \
    "$config_home/waybar/wallust/glow-state.json" "$generated/waybar")
palette_before=$(tree_fingerprint "$config_home/hypr/wallust/colors-shell.sh")

# A pull updates the checkout, not the deployed copy Hyprland is reading.
# Copy first, without package installation and without starting this script again.
published=0
force_reload=0
if [[ -n ${VOLUTA_REFRESH_SKIP_SYNC:-} ]]; then
    # The caller already deployed. Reload the session, and filter frames only
    # when that deploy did not publish them.
    published=1
    force_reload=1
else
    voluta_bin=${XDG_DATA_HOME:-$HOME/.local/share}/voluta/current/bin/voluta
    if [[ ! -x $voluta_bin ]]; then
        voluta_bin=$(command -v voluta || true)
    fi
    if [[ -n ${voluta_bin} && -x $voluta_bin ]]; then
        if "$voluta_bin" update --skip-deps --no-session-refresh; then
            published=1
        else
            notify-send "Voluta update failed" "Run voluta update in a terminal for details."
        fi
    fi
fi
if [[ -n ${VOLUTA_REFRESH_FORCE_FRAMES:-} ]]; then
    published=0
fi

if [[ $published -eq 0 && -f $rice_root/voluta/surfaces.py ]]; then
    # Share the palette lock with the wallpaper hook so both use a complete palette.
    lock_dir=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
    [[ -w $lock_dir ]] || lock_dir=/tmp
    if ! flock -w 8 "$lock_dir/imperium-combined-wallust.lock" \
        /usr/bin/python3 "$rice_root/voluta/surfaces.py" --refresh-frames; then
        notify-send "Voluta frame refresh failed" "Check the frame PNGs and Wallust palette, then run Refresh again."
    fi
fi
# Capitaine is required for the default cursor; reload cannot invent the theme.
if ! pacman -Q capitaine-cursors >/dev/null 2>&1; then
    notify-send "Cursor theme missing" "Install capitaine-cursors (voluta deps), then refresh again."
fi

# Reinstall Dolphin when its module changed. Repaint only when the palette changed.
dolphin_stamp=$state_home/voluta/dolphin-apply.stamp
dolphin_now=$(tree_fingerprint "$rice_root/dolphin" "$rice_root/deps/dolphin.txt" \
    "$rice_root/hypr/scripts/SetDefaultFileManager.sh")
palette_after=$(tree_fingerprint "$config_home/hypr/wallust/colors-shell.sh")
if [[ -f $rice_root/dolphin/apply.sh && -f $dolphin_stamp && $(<"$dolphin_stamp") == "$dolphin_now" ]]; then
    dolphin_paint=$rice_root/hypr/UserScripts/paint_dolphin_theme.sh
    if [[ $palette_before != "$palette_after" && -r $dolphin_paint ]] && ! bash "$dolphin_paint"; then
        notify-send "Dolphin refresh failed" "Run voluta update in a terminal for details."
    fi
elif [[ -f $rice_root/dolphin/apply.sh ]]; then
    if bash "$rice_root/dolphin/apply.sh"; then
        mkdir -p -- "$state_home/voluta"
        printf '%s\n' "$dolphin_now" >"$dolphin_stamp"
    else
        notify-send "Dolphin refresh failed" "Run voluta update in a terminal for details."
    fi
fi

waybar_dir=$(readlink -f "${config_home}/waybar" 2>/dev/null || true)
if [[ -f ${waybar_dir}/Makefile && -f ${waybar_dir}/src/hyprland_dispatch_shim.c ]]; then
    shim=${waybar_dir}/lib/libwaybar_hyprland_shim.so
    shim_stamp=${waybar_dir}/lib/.shim-sources.stamp
    shim_now=$(file_hash "$waybar_dir"/src/*.c "$waybar_dir/Makefile")
    if [[ ! -f $shim || ! -f $shim_stamp || $(<"$shim_stamp") != "$shim_now" ]]; then
        if make -C "$waybar_dir"; then
            mkdir -p -- "${waybar_dir}/lib"
            printf '%s\n' "$shim_now" >"$shim_stamp"
        else
            notify-send -u critical "Waybar build failed" "The existing Waybar shim will be used. Check the build output and run Refresh again."
        fi
    fi
fi
if [[ -f ${waybar_dir}/scripts/render-decorations.py ]]; then
    # Arch python-pillow; Homebrew/Conda python3 on PATH often lacks PIL.
    # The script returns immediately when the palette, glow.json, and wallpapers match.
    /usr/bin/python3 "$waybar_dir/scripts/render-decorations.py" ||
        notify-send "Waybar decorations failed" "Check glow.json and the Wallust palette, then run Refresh again."
fi

hypr_after=$(tree_fingerprint "$config_home/hypr")
waybar_after=$(tree_fingerprint "$config_home/waybar" "$generated/waybar")
swaync_after=$(tree_fingerprint "$config_home/swaync" \
    "$generated/notification-aperture.png" "$generated/notification-glass.png" \
    "$generated/launcher-vignette.svg")
glow_after=$(tree_fingerprint "$config_home/waybar/glow.qml" \
    "$config_home/waybar/wallust/glow-state.json" "$generated/waybar")

reloaded=0
if [[ $force_reload -eq 1 || $waybar_before != "$waybar_after" ]] || ! pgrep -x waybar >/dev/null 2>&1; then
    pkill -x waybar || true
    for _ in {1..15}; do
        pgrep -x waybar >/dev/null 2>&1 || break
        sleep 0.04
    done
    if pgrep -x waybar >/dev/null 2>&1; then
        pkill -9 -x waybar || true
        sleep 0.04
    fi
    # shellcheck source=waybar-config.sh
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/waybar-config.sh"
    waybar_prepare_config "${waybar_dir:+$waybar_dir/config}"
    (
        shim="${waybar_dir}/lib/libwaybar_hyprland_shim.so"
        if [[ -f $shim ]]; then
            export LD_PRELOAD="$shim${LD_PRELOAD:+:$LD_PRELOAD}"
        fi
        if [[ -d ${waybar_dir:-} ]]; then
            cd "$waybar_dir" || exit 0
        fi
        exec setsid waybar "${waybar_config_args[@]}" >/dev/null 2>&1
    ) &
    disown $! 2>/dev/null || true
    reloaded=1
fi

# The glow poll can take a few seconds. Do not block the rest of the refresh on it.
glow_script=$(dirname -- "$refresh_script")/StartTopGlow.sh
glow_qml=$(readlink -f "$config_home/waybar/glow.qml" 2>/dev/null || true)
glow_up=0
if [[ -n $glow_qml ]] && command -v quickshell >/dev/null 2>&1 \
    && quickshell list -p "$glow_qml" 2>/dev/null | grep -q .; then
    glow_up=1
fi
if [[ -x $glow_script || -f $glow_script ]]; then
    if [[ $force_reload -eq 1 || $glow_before != "$glow_after" ]]; then
        setsid "$glow_script" --restart >/dev/null 2>&1 </dev/null &
        disown $! 2>/dev/null || true
        reloaded=1
    elif [[ $glow_up -eq 0 ]]; then
        setsid "$glow_script" >/dev/null 2>&1 </dev/null &
        disown $! 2>/dev/null || true
    fi
fi

if command -v swaync-client >/dev/null 2>&1; then
    if [[ $force_reload -eq 1 || $swaync_before != "$swaync_after" ]] || ! pgrep -x swaync >/dev/null 2>&1; then
        swaync-client -R -rs >/dev/null 2>&1 || (pkill -x swaync || true; swaync >/dev/null 2>&1 &)
        reloaded=1
    fi
fi

# Reload once, after frames and the palette are on disk.
if [[ $force_reload -eq 1 || $hypr_before != "$hypr_after" ]]; then
    timeout -k 1 5 hyprctl reload >/dev/null 2>&1 || true
    reloaded=1
fi

if [[ $reloaded -eq 1 ]]; then
    notify-send -t 2000 -u low -i "view-refresh" "Desktop Refreshed" "Hyprland, Waybar, and SwayNC reloaded."
else
    notify-send -t 2000 -u low -i "view-refresh" "Desktop Refreshed" "Hyprland, Waybar, and SwayNC are current."
fi
