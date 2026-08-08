#!/usr/bin/env bash
# Brightness control helper with synchronous OSD notifications

NOTIF_TAG="brightness_notif"

get_brightness_pct() {
    if command -v brightnessctl >/dev/null 2>&1; then
        local cur max
        cur=$(brightnessctl get)
        max=$(brightnessctl max)
        awk -v c="$cur" -v m="$max" 'BEGIN { printf("%d", (c/m)*100) }'
    else
        echo "50"
    fi
}

notify_brightness() {
    local pct icon
    pct=$(get_brightness_pct)
    if [[ "$pct" -ge 60 ]]; then
        icon="display-brightness-high"
    elif [[ "$pct" -ge 30 ]]; then
        icon="display-brightness-medium"
    else
        icon="display-brightness-low"
    fi
    notify-send -t 1500 -u low -h "string:x-canonical-private-synchronous:$NOTIF_TAG" -h "int:value:$pct" -i "$icon" "Brightness" "${pct}%"
}

case "$1" in
    "--inc"|"-i")
        brightnessctl set +5% >/dev/null 2>&1
        notify_brightness
        ;;
    "--dec"|"-d")
        brightnessctl set 5%- >/dev/null 2>&1
        notify_brightness
        ;;
    *)
        notify_brightness
        ;;
esac
