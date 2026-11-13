#!/bin/bash
# Launch Dolphin with the live palette hook. Child processes do not keep it:
# the library removes itself from LD_PRELOAD as soon as Dolphin starts.
set -eu

here=$(readlink -f "$0")
here=${here%/*}
lib="${HOME}/.local/lib/imperium/libdolphin-live.so"

# Disabled customization launches the unmodified system application. Invalid
# settings also leave a usable file manager instead of injecting an uncertain hook.
if ! python3 "$here/../voluta/cli.py" enabled dolphin --legacy; then
    [[ ${1:-} == --prepare ]] && exit 0
    exec /usr/bin/dolphin "$@"
fi

python3 "$here/apply-config.py"
if ! bash "$here/build.sh"; then
    notify-send "Dolphin customization failed" "See ~/.local/lib/imperium/dolphin-live-build.log" 2>/dev/null || true
    exit 1
fi
[[ ${1:-} == --prepare ]] && exit 0

export LD_PRELOAD="${lib}${LD_PRELOAD:+:$LD_PRELOAD}"
export QT_QPA_PLATFORMTHEME=qt6ct
export FONTCONFIG_FILE="$here/fonts.conf"
# The shared Imperium Kvantum theme stays opaque for other Qt apps.
export KVANTUM_THEME=dolphin

platform_args=()
rhi=$(python3 "$here/../voluta/cli.py" get dolphin_rhi 2>/dev/null || echo false)
if [[ "$rhi" == true && -n "${WAYLAND_DISPLAY:-}" ]]; then
    # Qt's default shared-memory presentation stalls during selection on DP-2.
    # The native Wayland RHI path was verified smooth in the interactive test.
    # Keep this workaround in Dolphin's launcher, away from session-wide Qt
    # settings and the notebook's Intel graphics configuration.
    # https://github.com/hyprwm/Hyprland/discussions/11133
    export QT_WIDGETS_RHI=1
    export QT_WIDGETS_RHI_BACKEND=opengl
    platform_args=(-platform wayland)
fi
exec /usr/bin/dolphin "${platform_args[@]}" "$@"
