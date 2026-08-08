#!/usr/bin/env bash
# fetch.sh - Smart responsive Fastfetch runner with 100% original aspect ratio & colors

# Below this the 55-column info box wraps into a mess, so nothing is printed at
# all. zshrc reads the same two variables for its banner bookkeeping, so keep the
# names and the defaults in step with it.
MIN_COLS=${IMPERIUM_FETCH_MIN_COLS:-60}
MIN_LINES=${IMPERIUM_FETCH_MIN_LINES:-20}
FORCE=0
[[ "$1" == "--force" ]] && FORCE=1

# Ask the tty itself rather than trusting COLUMNS/LINES, which can be inherited
# stale from whatever spawned this and would then describe the wrong window.
TERM_COLS="" TERM_LINES=""
if size=$(stty size </dev/tty 2>/dev/null); then
    TERM_LINES=${size%% *}
    TERM_COLS=${size##* }
fi
[[ $TERM_COLS =~ ^[0-9]+$ && $TERM_COLS -gt 0 ]] || TERM_COLS=$(tput cols 2>/dev/null || echo 100)
[[ $TERM_LINES =~ ^[0-9]+$ && $TERM_LINES -gt 0 ]] || TERM_LINES=$(tput lines 2>/dev/null || echo 30)

if (( ! FORCE )) && (( TERM_COLS < MIN_COLS || TERM_LINES < MIN_LINES )); then
    exit 0
fi

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
