#!/usr/bin/env bash
# fetch.sh - Smart responsive Fastfetch runner with 100% original aspect ratio & colors

TERM_COLS=$(tput cols 2>/dev/null || echo 100)
CONFIG_FILE="$HOME/.config/fastfetch/config.jsonc"
ORIGINAL_IMG="$HOME/dotfiles-imperium/fastfetch/assets/crown-angels.jpg"
[[ ! -f "$ORIGINAL_IMG" ]] && ORIGINAL_IMG="$HOME/.config/fastfetch/assets/crown-angels.jpg"

# If terminal is narrower than 95 columns, disable image to prevent cramped/broken wrapping
if (( TERM_COLS < 95 )); then
    fastfetch --config "$CONFIG_FILE" --logo-type none
else
    if [[ -f "$ORIGINAL_IMG" ]]; then
        # Forced height to 13 lines with automatic proportional width (preserving exact 16:9 ratio)
        fastfetch --config "$CONFIG_FILE" --logo "$ORIGINAL_IMG" --logo-type kitty --logo-height 13
    else
        fastfetch --config "$CONFIG_FILE"
    fi
fi
