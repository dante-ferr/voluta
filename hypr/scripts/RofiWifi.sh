#!/usr/bin/env bash
# RofiWifi.sh - Interactive Wi-Fi manager for Hyprland/Waybar using Rofi & nmcli

ROFI_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/rofi"

wifi_menu() {
    sh "$ROFI_DIR/run-selector.sh" -dmenu -theme "$ROFI_DIR/wifi.rasi" "$@"
}

# Get Wi-Fi radio status
WIFI_STATE=$(nmcli radio wifi)

if [[ "$WIFI_STATE" =~ "disabled" ]]; then
    TOGGLE_MSG="󰖩  Enable Wi-Fi"
else
    TOGGLE_MSG="󰖪  Disable Wi-Fi"
fi

# Read NetworkManager's cached access points once. Automatic rescans can block
# for several seconds before Rofi appears; scanning is an explicit menu action.
ACTIVE_SSID=""
NETWORKS=""
if [[ "$WIFI_STATE" =~ "enabled" ]]; then
    WIFI_NETWORKS=$(nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY dev wifi list --rescan no 2>/dev/null)
    ACTIVE_SSID=$(printf '%s\n' "$WIFI_NETWORKS" | awk -F':' '$1 == "*" { print $2; exit }')
    NETWORKS=$(printf '%s\n' "$WIFI_NETWORKS" | awk -F':' '
    $2 != "" {
        ssid = $2
        in_use = $1
        signal = $3 + 0
        sec = $4
        
        if (!(ssid in max_sig) || signal > max_sig[ssid]) {
            max_sig[ssid] = signal
            is_active[ssid] = in_use
            security[ssid] = sec
        }
    }
    END {
        for (s in max_sig) {
            sig = max_sig[s]
            sec = security[s]
            act = is_active[s]
            
            if (sig >= 75) icon = "󰤨"
            else if (sig >= 50) icon = "󰤥"
            else if (sig >= 25) icon = "󰤢"
            else icon = "󰤟"
            
            sec_icon = (sec != "" && sec != "--") ? " 󰌾" : ""
            
            if (act == "*") {
                printf "󰄬  %s  (%d%%)%s  [Connected]\n", s, sig, sec_icon
            } else {
                printf "%s  %s  (%d%%)%s\n", icon, s, sig, sec_icon
            }
        }
    }' | sort -k1,1 -r)
fi

# Build menu items
MENU_OPTIONS=""

if [[ -n "$ACTIVE_SSID" ]]; then
    MENU_OPTIONS+="󰌙  Disconnect from '$ACTIVE_SSID'\n"
fi

MENU_OPTIONS+="$TOGGLE_MSG\n"
MENU_OPTIONS+="󰒓  Connection Settings (nm-connection-editor)\n"
MENU_OPTIONS+="󰑐  Rescan Networks\n"

if [[ -n "$NETWORKS" ]]; then
    MENU_OPTIONS+="$NETWORKS"
fi

# Render Rofi menu
CHOSEN=$(echo -e "$MENU_OPTIONS" | wifi_menu -i -p "󰤨 Wi-Fi")

[[ -z "$CHOSEN" ]] && exit 0

# Actions
if [[ "$CHOSEN" =~ "Enable Wi-Fi" ]]; then
    nmcli radio wifi on
    notify-send "Wi-Fi" "Enabling Wi-Fi..."
elif [[ "$CHOSEN" =~ "Disable Wi-Fi" ]]; then
    nmcli radio wifi off
    notify-send "Wi-Fi" "Disabling Wi-Fi..."
elif [[ "$CHOSEN" =~ "Disconnect from" ]]; then
    nmcli con down id "$ACTIVE_SSID" 2>/dev/null || nmcli dev disconnect wlan0 2>/dev/null
    notify-send "Wi-Fi" "Disconnected from $ACTIVE_SSID"
elif [[ "$CHOSEN" =~ "Connection Settings" ]]; then
    nm-connection-editor &
elif [[ "$CHOSEN" =~ "Rescan Networks" ]]; then
    # Wait for fresh results before reopening the cached menu.
    nmcli dev wifi list --rescan yes >/dev/null 2>&1
    exec "$0"
else
    # Clean string to get raw SSID
    SSID_RAW=$(echo "$CHOSEN" | sed -E 's/^(󰄬|󰤨|󰤥|󰤢|󰤟)[[:space:]]+//; s/[[:space:]]+\([0-9]+%\).*//')
    
    [[ -z "$SSID_RAW" ]] && exit 1
    
    if [[ "$SSID_RAW" == "$ACTIVE_SSID" ]]; then
        ACTION=$(echo -e "Disconnect\nCancel" | wifi_menu -i -p "Active: $SSID_RAW")
        if [[ "$ACTION" == "Disconnect" ]]; then
            nmcli con down id "$SSID_RAW"
            notify-send "Wi-Fi" "Disconnected from $SSID_RAW"
        fi
        exit 0
    fi
    
    notify-send "Wi-Fi" "Connecting to $SSID_RAW..."
    
    CONN_OUTPUT=$(nmcli dev wifi connect "$SSID_RAW" 2>&1)
    
    if [[ $? -eq 0 ]]; then
        notify-send "Wi-Fi" "Successfully connected to $SSID_RAW"
    else
        # Password prompt if secrets required
        PASS=$(wifi_menu -password -p "Password for $SSID_RAW")
        if [[ -n "$PASS" ]]; then
            notify-send "Wi-Fi" "Connecting to $SSID_RAW..."
            CONN_PASS_OUTPUT=$(nmcli dev wifi connect "$SSID_RAW" password "$PASS" 2>&1)
            if [[ $? -eq 0 ]]; then
                notify-send "Wi-Fi" "Successfully connected to $SSID_RAW"
            else
                notify-send -u critical "Wi-Fi Error" "Failed to connect to $SSID_RAW:\n$CONN_PASS_OUTPUT"
            fi
        fi
    fi
fi
