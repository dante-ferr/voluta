#!/usr/bin/env bash
# Session lock launcher

if command -v hyprlock >/dev/null 2>&1; then
    hyprlock &
elif command -v swaylock >/dev/null 2>&1; then
    swaylock -f &
elif command -v gtklock >/dev/null 2>&1; then
    gtklock &
fi
