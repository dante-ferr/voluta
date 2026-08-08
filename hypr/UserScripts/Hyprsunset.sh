#!/usr/bin/env bash
# Blue light filter & night-light toggle

if pgrep -x hyprsunset >/dev/null 2>&1; then
    pkill -x hyprsunset || true
    notify-send -t 2000 -u low -i "weather-clear-night" "Night Light" "Blue light filter disabled"
elif pgrep -x wlsunset >/dev/null 2>&1; then
    pkill -x wlsunset || true
    notify-send -t 2000 -u low -i "weather-clear-night" "Night Light" "Blue light filter disabled"
else
    if command -v hyprsunset >/dev/null 2>&1; then
        hyprsunset -t 3200 >/dev/null 2>&1 &
        notify-send -t 2000 -u low -i "weather-clear-night" "Night Light" "Enabled (3200K Warmth)"
    elif command -v wlsunset >/dev/null 2>&1; then
        wlsunset -t 3200 >/dev/null 2>&1 &
        notify-send -t 2000 -u low -i "weather-clear-night" "Night Light" "Enabled (3200K Warmth)"
    fi
fi
