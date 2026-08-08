#!/usr/bin/env bash
# rice-switch.sh - Toggle between system dotfiles rices (default vs imperium)

set -e

RICE="${1:-toggle}"

CURRENT_TARGET=$(readlink -f "$HOME/.config/hypr" 2>/dev/null || true)

if [[ "$RICE" == "toggle" ]]; then
    if [[ "$CURRENT_TARGET" == *"/imperivm-dotfiles/"* ]]; then
        RICE="default"
    else
        RICE="imperium"
    fi
fi

if [[ "$RICE" == "imperium" ]]; then
    TARGET_DIR="$HOME/imperivm-dotfiles"
    echo "⚡ Switching to Imperium Cyber-Sacred rice..."
elif [[ "$RICE" == "default" || "$RICE" == "main" ]]; then
    TARGET_DIR="$HOME/dotfiles"
    echo "🔄 Switching to Default rice..."
else
    echo "Usage: $0 [imperium | default | toggle]"
    exit 1
fi

link_config() {
    local name="$1"
    local src="$TARGET_DIR/$name"
    local dest="$HOME/.config/$name"

    if [[ -d "$src" || -f "$src" ]]; then
        if [[ -L "$dest" || -e "$dest" ]]; then
            rm -rf "$dest"
        fi
        ln -s "$src" "$dest"
        echo "  Linked ~/.config/$name -> $src"
    fi
}

mkdir -p "$HOME/.config"

link_config "hypr"
link_config "waybar"
link_config "kitty"
link_config "rofi"
link_config "wallust"
link_config "fastfetch"
link_config "swaync"
link_config "starship.toml"

# Trigger wallpaper/wallust refresh and components reload
if [[ -f "$HOME/.config/hypr/UserScripts/combined_wallust.sh" ]]; then
    echo "🎨 Refreshing Wallust colors and desktop components..."
    bash "$HOME/.config/hypr/UserScripts/combined_wallust.sh"
elif command -v wallust >/dev/null 2>&1; then
    waypaper_conf="$HOME/.config/waypaper/config.ini"
    if [[ -f "$waypaper_conf" ]]; then
        wallpaper=$(grep -E '^\s*wallpaper\s*=' "$waypaper_conf" | head -n 1 | cut -d '=' -f 2- | sed 's/^[ \t]*//' | sed "s|^~|$HOME|")
        if [[ -n "$wallpaper" && -f "$wallpaper" ]]; then
            wallust run "$wallpaper"
        fi
    fi
    hyprctl reload >/dev/null 2>&1 || true
    pkill -x waybar || true
    sleep 0.2
    waybar >/dev/null 2>&1 &
fi

echo "✅ Switched to '$RICE' rice successfully!"
