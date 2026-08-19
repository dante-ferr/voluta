#!/usr/bin/env bash
# Session lock launcher.
# --no-fade-in / --grace 0: hyprlock must be fully locked before NVIDIA sleep,
# and must not fade while the DRM node is coming back.

LOCK_ARGS=(--no-fade-in --grace 0)

if command -v hyprlock >/dev/null 2>&1; then
    pidof hyprlock >/dev/null 2>&1 && exit 0
    hyprlock "${LOCK_ARGS[@]}" &
    exit 0
fi

if command -v swaylock >/dev/null 2>&1; then
    swaylock -f &
elif command -v gtklock >/dev/null 2>&1; then
    gtklock &
fi
