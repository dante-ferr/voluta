#!/usr/bin/env bash
# RofiPicker.sh - Super+. emoji and Super+, symbols selectors (rofimoji).
#
# Pressing the bind again dismisses an open picker, matching the other rofi
# toggles. Enter types into the focused window (needs wtype) and copies.

set -euo pipefail

mode="${1:-emoji}"
theme="${HOME}/.config/rofi/picker.rasi"

if pgrep -x rofi >/dev/null 2>&1; then
    pkill -x rofi
    exit 0
fi

if ! command -v rofimoji >/dev/null 2>&1; then
    notify-send -u low "Character picker" "rofimoji is not installed"
    exit 1
fi

selector_args=()
if [[ -f $theme ]]; then
    selector_args=(--selector-args "-theme ${theme}")
fi

common=(
    --action type copy
    --clipboarder wl-copy
    --selector rofi
    "${selector_args[@]}"
)

case "$mode" in
    symbols | math)
        exec rofimoji "${common[@]}" \
            --prompt "Σ " \
            --files \
            math \
            arrows \
            supplemental_arrows \
            geometric_shapes \
            letterlike_symbols \
            nerd_font \
            currency_symbols \
            box_drawing \
            general_punctuation \
            dingbats \
            miscellaneous_mathematical_symbols \
            supplemental_mathematical_operators
        ;;
    emoji | *)
        exec rofimoji "${common[@]}" --prompt "😀 "
        ;;
esac
