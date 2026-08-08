#!/usr/bin/env bash
# Pixel art desktop widget launcher

if pkill -f pixel-art-widget 2>/dev/null; then
    exit 0
else
    pixel-art-widget >/dev/null 2>&1 &
fi
