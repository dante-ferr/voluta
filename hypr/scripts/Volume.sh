#!/usr/bin/env bash
# Universal Volume & Audio Control Script for PipeWire & PulseAudio

NOTIF_TAG="volume_notif"

get_sink_volume() {
    if command -v wpctl >/dev/null 2>&1; then
        wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk '{print int($2 * 100)}'
    elif command -v pamixer >/dev/null 2>&1; then
        pamixer --get-volume 2>/dev/null || echo "50"
    else
        echo "50"
    fi
}

is_sink_muted() {
    if command -v wpctl >/dev/null 2>&1; then
        wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -qi "MUTED" && echo "yes" || echo "no"
    elif command -v pamixer >/dev/null 2>&1; then
        pamixer --get-mute 2>/dev/null && echo "yes" || echo "no"
    else
        echo "no"
    fi
}

notify_volume() {
    local vol muted icon
    vol=$(get_sink_volume)
    muted=$(is_sink_muted)

    if [[ "$muted" == "yes" || "$vol" -eq 0 ]]; then
        icon="audio-volume-muted"
        notify-send -t 1500 -u low -h "string:x-canonical-private-synchronous:$NOTIF_TAG" -h "int:value:0" -i "$icon" "Volume" "Muted"
    else
        if [[ "$vol" -ge 70 ]]; then
            icon="audio-volume-high"
        elif [[ "$vol" -ge 30 ]]; then
            icon="audio-volume-medium"
        else
            icon="audio-volume-low"
        fi
        notify-send -t 1500 -u low -h "string:x-canonical-private-synchronous:$NOTIF_TAG" -h "int:value:$vol" -i "$icon" "Volume" "${vol}%"
    fi
}

case "$1" in
    "--inc"|"-i")
        if command -v wpctl >/dev/null 2>&1; then
            wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+
        elif command -v pamixer >/dev/null 2>&1; then
            pamixer -i 5 --allow-boost --set-limit 150 2>/dev/null || pamixer -i 5
        fi
        notify_volume
        ;;
    "--dec"|"-d")
        if command -v wpctl >/dev/null 2>&1; then
            wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
        elif command -v pamixer >/dev/null 2>&1; then
            pamixer -d 5
        fi
        notify_volume
        ;;
    "--toggle"|"-t")
        if command -v wpctl >/dev/null 2>&1; then
            wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
        elif command -v pamixer >/dev/null 2>&1; then
            pamixer -t
        fi
        notify_volume
        ;;
    "--toggle-mic"|"-m")
        if command -v wpctl >/dev/null 2>&1; then
            wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle
        elif command -v pamixer >/dev/null 2>&1; then
            pamixer --default-source -t
        fi
        notify-send -t 1500 -u low -h "string:x-canonical-private-synchronous:mic_notif" -i "audio-input-microphone" "Microphone" "Input mute toggled"
        ;;
    *)
        notify_volume
        ;;
esac
