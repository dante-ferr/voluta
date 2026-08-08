#!/usr/bin/env bash
# combined_wallust.sh - Generate wallust color schemes and reload desktop components

wallpaper="$1"

# If no wallpaper argument is provided, detect current wallpaper
if [[ -z "$wallpaper" || ! -f "$wallpaper" ]]; then
    if command -v swww >/dev/null 2>&1; then
        wallpaper=$(swww query 2>/dev/null | grep -o 'image: .*' | head -n 1 | cut -d ' ' -f 2-)
    fi
fi

if [[ -z "$wallpaper" || ! -f "$wallpaper" ]]; then
    waypaper_conf="$HOME/.config/waypaper/config.ini"
    if [[ -f "$waypaper_conf" ]]; then
        wallpaper=$(grep -E '^\s*wallpaper\s*=' "$waypaper_conf" | head -n 1 | cut -d '=' -f 2- | sed 's/^[ \t]*//' | sed "s|^~|$HOME|")
    fi
fi

# Run wallust
if [[ -n "$wallpaper" && -f "$wallpaper" ]]; then
    if command -v wallust >/dev/null 2>&1; then
        wallust run "$wallpaper"
    fi
fi

# Clean background transparency with 100% original image colors preserved
if command -v magick >/dev/null 2>&1; then
    asset_dir="$HOME/.config/fastfetch/assets"
    mkdir -p "$asset_dir"
    source_img="$asset_dir/crown-angels.jpg"
    [[ ! -f "$source_img" ]] && source_img="$HOME/imperivm-dotfiles/fastfetch/assets/crown-angels.jpg"
    
    if [[ -f "$source_img" ]]; then
        magick "$source_img" -fuzz 14% -transparent black "$asset_dir/crown-angels-styled.png" >/dev/null 2>&1 || true
    fi
fi

# 1. Reload Hyprland window manager
if command -v hyprctl >/dev/null 2>&1; then
    hyprctl reload >/dev/null 2>&1 || true
fi

# 2. Reload/Restart Waybar
if command -v waybar >/dev/null 2>&1; then
    pkill -x waybar || true
    sleep 0.15
    nohup waybar >/dev/null 2>&1 &
fi

# 3. Reload SwayNC Notification Center
if command -v swaync-client >/dev/null 2>&1; then
    swaync-client -R -rs >/dev/null 2>&1 || true
fi

# 4. Reload Kitty Terminal colors
if command -v kitty >/dev/null 2>&1; then
    pkill -SIGUSR1 -x kitty >/dev/null 2>&1 || true
    if [[ -f "$HOME/.config/kitty/kitty-themes/01-Wallust.conf" ]]; then
        kitty @ set-colors --all "$HOME/.config/kitty/kitty-themes/01-Wallust.conf" >/dev/null 2>&1 || true
    fi
fi

# 5. Reload Cava
if command -v cava >/dev/null 2>&1; then
    pkill -USR2 cava >/dev/null 2>&1 || true
fi
