#!/usr/bin/env bash
# Host profile link manager for multi-machine Hyprland configurations

HOSTNAME_VAL=$(cat /etc/hostname 2>/dev/null || uname -n)
HYPR_DIR="$HOME/.config/hypr"
HOSTS_DIR="$HYPR_DIR/hosts"
USER_CONFIG="$HYPR_DIR/UserConfigs/UserSettings.lua"

if [[ -f "$HOSTS_DIR/$HOSTNAME_VAL.lua" ]]; then
    echo "Linking host configuration profile for $HOSTNAME_VAL"
    cp -f "$HOSTS_DIR/$HOSTNAME_VAL.lua" "$USER_CONFIG"
fi
