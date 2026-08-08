#!/usr/bin/env bash
# wallust_env.sh - Resolve the live wallust palette into shell variables.
#
# Sourced by every Command Deck panel so the whole UI repaints itself from the
# current wallpaper. Exposes wc_bg / wc_fg / wc_0 .. wc_15 as bare RRGGBB hex
# plus truecolor escape helpers.

_wc_shell_file="$HOME/.config/hypr/wallust/colors-shell.sh"
_wc_hypr_file="$HOME/.config/hypr/wallust/wallust-hyprland.conf"

# Hyprland's generated palette is the fallback source: it is written by the same
# wallust run but has existed far longer, so it is present even before the
# colors-shell template has been rendered for the first time.
_wc_load_from_hyprland() {
    local line key val
    while IFS= read -r line; do
        [[ $line =~ ^\$([a-zA-Z0-9_]+)[[:space:]]*=[[:space:]]*rgba?\(([0-9a-fA-F]{6}) ]] || continue
        key="${BASH_REMATCH[1]}"
        val="${BASH_REMATCH[2]}"
        case "$key" in
            background) wc_bg="$val" ;;
            foreground) wc_fg="$val" ;;
            color[0-9]*) printf -v "wc_${key#color}" '%s' "$val" ;;
        esac
    done <"$1"
}

if [[ -r "$_wc_shell_file" ]]; then
    # shellcheck source=/dev/null
    source "$_wc_shell_file"
elif [[ -r "$_wc_hypr_file" ]]; then
    _wc_load_from_hyprland "$_wc_hypr_file"
fi

# Neutral obsidian/gold defaults keep the panels legible if wallust has never run.
: "${wc_bg:=0A0A0E}" "${wc_fg:=E6E6F0}"
_wc_defaults=(101018 9A684B 88643F C9A227 634638 634C36 4A3A34 998B87
              554A46 9A684B 88643F C9A227 634638 634C36 4A3A34 B4ADAB)
for _i in {0..15}; do
    _name="wc_${_i}"
    [[ -n "${!_name:-}" ]] || printf -v "$_name" '%s' "${_wc_defaults[$_i]}"
done
unset _i _name _wc_defaults _wc_shell_file _wc_hypr_file

# --- Truecolor emitters -----------------------------------------------------

fg() { local h="${1#\#}"; printf '\033[38;2;%d;%d;%dm' "$((16#${h:0:2}))" "$((16#${h:2:2}))" "$((16#${h:4:2}))"; }
bg() { local h="${1#\#}"; printf '\033[48;2;%d;%d;%dm' "$((16#${h:0:2}))" "$((16#${h:2:2}))" "$((16#${h:4:2}))"; }
rs() { printf '\033[0m'; }
bold() { printf '\033[1m'; }

# Blend two palette hexes; used to fade graph tails and dim inactive gauge track.
mix() {
    local a="${1#\#}" b="${2#\#}" t="$3" i r out=""
    for i in 0 2 4; do
        r=$(( (16#${a:$i:2} * (100 - t) + 16#${b:$i:2} * t) / 100 ))
        out+=$(printf '%02X' "$r")
    done
    printf '%s' "$out"
}

# Severity ramp. ANSI slots 2/3/1 are the green/yellow/red hues of the palette,
# so a wallust theme keeps both its own colors and the expected warning ordering.
heat() {
    local pct="$1" warn="${2:-60}" crit="${3:-85}"
    if   (( pct >= crit )); then printf '%s' "$wc_1"
    elif (( pct >= warn )); then printf '%s' "$wc_3"
    else                         printf '%s' "$wc_2"
    fi
}
