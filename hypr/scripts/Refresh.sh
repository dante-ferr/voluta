#!/usr/bin/env bash
# Environment refresh tool for Hyprland, Waybar, and SwayNC

# A pull updates the checkout, not the deployed copy Hyprland is reading.
# Copy first, without package installation and without starting this script again.
if [[ -z ${VOLUTA_REFRESH_SKIP_SYNC:-} ]]; then
    voluta_bin=${XDG_DATA_HOME:-$HOME/.local/share}/voluta/current/bin/voluta
    if [[ ! -x $voluta_bin ]]; then
        voluta_bin=$(command -v voluta || true)
    fi
    if [[ -n ${voluta_bin} && -x $voluta_bin ]]; then
        if ! "$voluta_bin" update --skip-deps --no-session-refresh; then
            notify-send "Voluta update failed" "Run voluta update in a terminal for details."
        fi
    fi
fi

# 1. Reload Hyprland Window Manager
hyprctl reload >/dev/null 2>&1 || true

refresh_script=$(readlink -f -- "${BASH_SOURCE[0]}")
rice_root=$(cd -- "$(dirname -- "$refresh_script")/../.." && pwd)
if [[ -f "$rice_root/voluta/surfaces.py" ]]; then
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
# A pull also changes generated Qt styling, saved view defaults and the hook.
# Do this before setting Waybar's LD_PRELOAD below.
if [[ -f "$rice_root/dolphin/apply.sh" ]]; then
    if ! bash "$rice_root/dolphin/apply.sh"; then
        notify-send "Dolphin refresh failed" "Run voluta update in a terminal for details."
    fi
fi

# 2. Restart Waybar from its config dir so CSS url("assets/...") resolves.
pkill -x waybar || true
for _ in {1..15}; do
    pgrep -x waybar >/dev/null 2>&1 || break
    sleep 0.04
done
if pgrep -x waybar >/dev/null 2>&1; then
    pkill -9 -x waybar || true
    sleep 0.04
fi

waybar_dir=$(readlink -f "${HOME}/.config/waybar" 2>/dev/null || true)
if [[ -f "${waybar_dir}/Makefile" ]]; then
    if ! make -C "$waybar_dir"; then
        notify-send -u critical "Waybar build failed" "The existing Waybar shim will be used. Check the build output and run Refresh again."
    fi
fi
if [[ -f "${waybar_dir}/scripts/render-decorations.py" ]]; then
    # Arch python-pillow; Homebrew/Conda python3 on PATH often lacks PIL.
    /usr/bin/python3 "$waybar_dir/scripts/render-decorations.py" ||
        notify-send "Waybar decorations failed" "Check glow.json and the Wallust palette, then run Refresh again."
fi
shim="${waybar_dir}/lib/libwaybar_hyprland_shim.so"
if [[ -f $shim ]]; then
    export LD_PRELOAD="$shim${LD_PRELOAD:+:$LD_PRELOAD}"
fi
# shellcheck source=waybar-config.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/waybar-config.sh"
waybar_prepare_config "${waybar_dir:+$waybar_dir/config}"
if [[ -d ${waybar_dir:-} ]]; then
    (cd "$waybar_dir" && setsid waybar "${waybar_config_args[@]}" >/dev/null 2>&1 &)
else
    setsid waybar "${waybar_config_args[@]}" >/dev/null 2>&1 &
fi

# The top glow reads the state file render-decorations.py just wrote.
"$(dirname -- "$refresh_script")/StartTopGlow.sh" --restart || true

# 3. Reload SwayNC Notification Center
if command -v swaync-client >/dev/null 2>&1; then
    swaync-client -R -rs >/dev/null 2>&1 || (pkill -x swaync || true; swaync >/dev/null 2>&1 &)
fi

notify-send -t 2000 -u low -i "view-refresh" "Desktop Refreshed" "Hyprland, Waybar, and SwayNC reloaded."
