#!/usr/bin/env bash
# Independent Media Control Script with OSD Notifications

# Notification tag for in-place replacement
NOTIF_TAG="media_control"

get_metadata() {
    playerctl metadata --format '{{status}}:::{{artist}}:::{{title}}:::{{album}}' 2>/dev/null
}

show_notification() {
    local meta
    meta=$(get_metadata)
    
    if [[ -z "$meta" ]]; then
        return
    fi

    local status artist title album
    status=$(echo "$meta" | awk -F':::' '{print $1}')
    artist=$(echo "$meta" | awk -F':::' '{print $2}')
    title=$(echo "$meta" | awk -F':::' '{print $3}')
    album=$(echo "$meta" | awk -F':::' '{print $4}')

    local summary body icon="media-playback-start"
    
    if [[ "$status" == "Paused" ]]; then
        summary="Playback Paused"
        icon="media-playback-pause"
    else
        summary="Now Playing"
        icon="media-playback-start"
    fi

    if [[ -n "$artist" && -n "$title" ]]; then
        body="<b>$title</b>\nby $artist"
    elif [[ -n "$title" ]]; then
        body="<b>$title</b>"
    else
        body="Active Media Stream"
    fi

    notify-send -t 2000 -u low -h "string:x-canonical-private-synchronous:$NOTIF_TAG" -i "$icon" "$summary" "$body"
}

case "$1" in
    "--nxt"|"-n")
        playerctl next 2>/dev/null
        sleep 0.15
        show_notification
        ;;
    "--prv"|"-p")
        playerctl previous 2>/dev/null
        sleep 0.15
        show_notification
        ;;
    "--pause"|"--toggle"|"-t")
        playerctl play-pause 2>/dev/null
        sleep 0.15
        show_notification
        ;;
    "--stop"|"-s")
        playerctl stop 2>/dev/null
        notify-send -t 1500 -u low -h "string:x-canonical-private-synchronous:$NOTIF_TAG" -i "media-playback-stop" "Media" "Playback Stopped"
        ;;
    *)
        playerctl play-pause 2>/dev/null
        sleep 0.15
        show_notification
        ;;
esac
