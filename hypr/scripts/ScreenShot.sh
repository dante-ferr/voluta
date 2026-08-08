#!/usr/bin/env bash
# High-performance Screenshot utility for Wayland & Hyprland

TARGET_DIR="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")/Screenshots"
mkdir -p "$TARGET_DIR"

TIMESTAMP="$(date "+%Y-%m-%d_%H-%M-%S")"
FILE_PATH="$TARGET_DIR/Screenshot_${TIMESTAMP}.png"

send_notif() {
    local target="$1"
    if [[ -f "$target" ]]; then
        notify-send -t 3500 -u low -i "$target" "Screenshot Captured" "Saved to $(basename "$target")\nCopied to clipboard."
    fi
}

case "$1" in
    "--now"|"-n")
        grim "$FILE_PATH"
        wl-copy < "$FILE_PATH"
        send_notif "$FILE_PATH"
        ;;
    "--area"|"-s")
        GEOM=$(slurp -d)
        if [[ -n "$GEOM" ]]; then
            grim -g "$GEOM" "$FILE_PATH"
            wl-copy < "$FILE_PATH"
            send_notif "$FILE_PATH"
        fi
        ;;
    "--in5"|"-5")
        notify-send -t 2000 -u low -i "camera-photo" "Screenshot" "Capturing in 5 seconds..."
        sleep 5
        grim "$FILE_PATH"
        wl-copy < "$FILE_PATH"
        send_notif "$FILE_PATH"
        ;;
    "--active"|"-a")
        WIN_GEOM=$(hyprctl activewindow -j 2>/dev/null | jq -r '"\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"')
        if [[ -n "$WIN_GEOM" && "$WIN_GEOM" != "null" ]]; then
            grim -g "$WIN_GEOM" "$FILE_PATH"
            wl-copy < "$FILE_PATH"
            send_notif "$FILE_PATH"
        else
            # Fallback to full screen if no active window
            grim "$FILE_PATH"
            wl-copy < "$FILE_PATH"
            send_notif "$FILE_PATH"
        fi
        ;;
    "--edit"|"-e")
        GEOM=$(slurp -d)
        if [[ -n "$GEOM" ]]; then
            if command -v swappy >/dev/null 2>&1; then
                grim -g "$GEOM" - | swappy -f -
            else
                grim -g "$GEOM" "$FILE_PATH"
                wl-copy < "$FILE_PATH"
                send_notif "$FILE_PATH"
            fi
        fi
        ;;
    *)
        grim "$FILE_PATH"
        wl-copy < "$FILE_PATH"
        send_notif "$FILE_PATH"
        ;;
esac
