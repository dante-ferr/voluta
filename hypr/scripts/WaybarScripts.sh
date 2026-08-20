#!/usr/bin/env bash
# Waybar script helper for Imperium dotfiles

term="kitty"
if [[ -f "$HOME/.config/hypr/UserConfigs/01-UserDefaults.conf" ]]; then
    config_content=$(sed 's/\$//g' "$HOME/.config/hypr/UserConfigs/01-UserDefaults.conf" | sed 's/ = /=/')
    eval "$config_content" 2>/dev/null || true
fi

if [[ "$1" == "--network" ]] || [[ "$1" == "--net" ]]; then
    "$HOME/.config/hypr/scripts/RofiWifi.sh" || nm-connection-editor || ${term:-kitty} nmtui
elif [[ "$1" == "--nmtui" ]]; then
    ${term:-kitty} nmtui
elif [[ "$1" == "--btop" ]]; then
    ${term:-kitty} --title btop sh -c 'btop'
elif [[ "$1" == "--nvtop" ]]; then
    ${term:-kitty} --title nvtop sh -c 'nvtop'
elif [[ "$1" == "--term" ]]; then
    ${term:-kitty} &
else
    echo "Usage: $0 [--network | --nmtui | --btop | --nvtop | --term]"
fi
