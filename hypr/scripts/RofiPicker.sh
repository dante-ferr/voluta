#!/usr/bin/env bash
# RofiPicker.sh - Super+. emoji and Super+, symbols selectors (rofimoji).
#
# Pressing the bind again dismisses an open picker, matching the other rofi
# toggles. After a choice, the character is copied and inserted into the
# window that was focused when the picker opened.
#
# Native clients get wtype. Electron/Chromium ignore the virtual keyboard,
# so those receive a compositor Ctrl+V (Ctrl+Shift+V in terminals). V is
# sent as an XKB keycode so it still works on the us,br layout.

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

target_addr=""
target_class=""
if command -v hyprctl >/dev/null 2>&1; then
    if command -v jq >/dev/null 2>&1; then
        mapfile -t win_fields < <(hyprctl activewindow -j 2>/dev/null | jq -r '.address // empty, .class // empty' || true)
    else
        mapfile -t win_fields < <(
            hyprctl activewindow -j 2>/dev/null | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
print(d.get('address') or '')
print(d.get('class') or '')
" || true
        )
    fi
    target_addr=${win_fields[0]:-}
    target_class=${win_fields[1]:-}
fi

selector_args=()
if [[ -f $theme ]]; then
    selector_args=(--selector-args "-theme ${theme}")
fi

common=(
    --action print
    --selector rofi
    "${selector_args[@]}"
)

set +e
case "$mode" in
    symbols | math)
        char=$(rofimoji "${common[@]}" \
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
            supplemental_mathematical_operators)
        status=$?
        ;;
    emoji | *)
        char=$(rofimoji "${common[@]}" --prompt "😀 ")
        status=$?
        ;;
esac
set -e

# Rofi cancel is a non-zero exit; nothing to insert.
((status == 0)) || exit 0

char=${char%$'\n'}
char=${char%$'\r'}
[[ -n $char ]] || exit 0

if command -v wl-copy >/dev/null 2>&1; then
    printf '%s' "$char" | wl-copy --type text
    printf '%s' "$char" | wl-copy --type text --primary
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        if [[ "$(wl-paste --type text --no-newline 2>/dev/null || true)" == "$char" ]]; then
            break
        fi
        sleep 0.05
    done
fi

hypr_dispatch() {
    local out
    out=$(hyprctl dispatch "$1" 2>&1) || true
    [[ ${out//$'\n'/} == ok ]]
}

is_terminal() {
    case "${1,,}" in
        kitty* | alacritty* | foot | footclient | org.wezfurlong.wezterm* | \
        com.mitchellh.ghostty* | ghostty | gnome-terminal* | org.gnome.terminal* | \
        konsole | terminator | xfce4-terminal*)
            return 0
            ;;
    esac
    return 1
}

# Chromium-based apps ignore wtype's virtual keyboard.
is_electron() {
    case "${1,,}" in
        brave-browser | chromium | google-chrome | google-chrome-* | \
        chrome | vivaldi* | microsoft-edge* | opera | cursor | code | \
        code-url-handler | discord | vesktop | slack | spotify | \
        ferdium | electron | *electron*)
            return 0
            ;;
    esac
    return 1
}

# KEY_V is evdev 47; Hyprland code:NN is XKB (evdev+8).
paste_via_compositor() {
    local mods="CTRL"
    if is_terminal "$target_class"; then
        mods="CTRL + SHIFT"
    fi
    local payload="hl.dsp.send_shortcut({ mods = \"${mods}\", key = \"code:55\""
    if [[ -n $target_addr ]]; then
        payload+=", window = \"address:${target_addr}\""
    fi
    payload+=" })"
    hypr_dispatch "$payload"
}

insert_character() {
    if [[ -n $target_addr ]]; then
        hypr_dispatch "hl.dsp.focus({ window = \"address:${target_addr}\" })" || true
    else
        hypr_dispatch "hl.dsp.focus({ last = true })" || true
    fi

    # Layer-shell rofi steals keyboard focus; Chromium restores the caret slowly.
    local waited=0
    while pgrep -x rofi >/dev/null 2>&1 && ((waited < 20)); do
        sleep 0.05
        waited=$((waited + 1))
    done
    if is_electron "$target_class"; then
        sleep 0.4
    else
        sleep 0.12
    fi

    if is_electron "$target_class"; then
        paste_via_compositor && return 0
    elif command -v wtype >/dev/null 2>&1; then
        wtype -- "$char" && return 0
        paste_via_compositor && return 0
    else
        paste_via_compositor && return 0
    fi
    return 1
}

if ! command -v hyprctl >/dev/null 2>&1; then
    notify-send -u low "Character picker" "Copied to clipboard"
    exit 0
fi

if ! insert_character; then
    notify-send -u low "Character picker" "Copied to clipboard — paste with Ctrl+V"
fi
