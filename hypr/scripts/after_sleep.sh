#!/usr/bin/env bash
# Restore the session after suspend.
#
# Two things must happen, in order:
#   1. Displays come back. Hyprland 0.56 only accepts Lua dispatchers, so the
#      old `hyprctl dispatch dpms on` was a silent no-op — the lock greeter
#      then sat on a dead DRM node and the only recovery was a reboot.
#   2. The renderer is rebuilt. NVIDIA often keeps hyprlock's EGL context
#      invalid across the reset even after DPMS is on again.

hyprctl dispatch 'hl.dsp.dpms({action = "on"})' >/dev/null 2>&1 || true

sleep 0.7

hyprctl dispatch 'hl.dsp.force_renderer_reload()' >/dev/null 2>&1 || true

if ! pidof hyprlock >/dev/null 2>&1; then
    loginctl lock-session >/dev/null 2>&1 || true
fi
