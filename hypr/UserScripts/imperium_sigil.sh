#!/usr/bin/env bash
# imperium_sigil.sh - Heraldic panel of the Imperium Command Deck.
#
# Renders the rice's sigil artwork through the kitty graphics protocol, then a
# live clock with a Latin/Roman date, the active wallust palette, the wallpaper
# currently driving that palette, and whatever is playing.

set -uo pipefail

# shellcheck source=lib/wallust_env.sh
source "$HOME/.config/hypr/UserScripts/lib/wallust_env.sh"

ASSETS="$HOME/.config/fastfetch/assets"
INTERVAL=1

RS=$(rs)
BD=$(bold)
E_TITLE=$(fg "$wc_15")
E_ACCENT=$(fg "$wc_12")
E_LABEL=$(fg "$wc_7")
E_TIME=$(fg "$wc_15")
E_MUTED=$(fg "$(mix "$wc_bg" "$wc_fg" 40)")
E_RULE=$(fg "$(mix "$wc_bg" "$wc_12" 75)")

trap 'printf "\033[?25h\033[0m\n"' EXIT INT TERM

# --- Sigil artwork ----------------------------------------------------------

# Portrait art first: the panel is tall and narrow, so a 9:16 sigil fills it
# where the wide crown-angels painting would only occupy a thin band.
pick_sigil() {
    local c
    for c in "${IMPERIUM_SIGIL:-}" \
        "$ASSETS/imperium-sigil.png" \
        "$ASSETS/crown-angels-styled.png" \
        "$ASSETS/crown-angels.jpg"; do
        [[ -n $c && -r $c ]] && {
            printf '%s' "$c"
            return
        }
    done
}

# --- Latin calendar ---------------------------------------------------------

LAT_DAYS=(SOLIS LVNAE MARTIS MERCVRII IOVIS VENERIS SATVRNI)
LAT_MONTHS=(IANVARII FEBRVARII MARTII APRILIS MAII IVNII IVLII AVGVSTI
    SEPTEMBRIS OCTOBRIS NOVEMBRIS DECEMBRIS)

roman() {
    local n=$1 out="" i
    local -a val=(1000 900 500 400 100 90 50 40 10 9 5 4 1)
    local -a sym=(M CM D CD C XC L XL X IX V IV I)
    for i in "${!val[@]}"; do
        while ((n >= val[i])); do
            out+="${sym[i]}"
            n=$((n - val[i]))
        done
    done
    printf '%s' "$out"
}

latin_date() {
    local dow mon day year
    read -r dow mon day year <<<"$(date '+%w %m %-d %Y')"
    printf 'DIES %s · %s %s · %s' \
        "${LAT_DAYS[10#$dow]}" \
        "$(roman "$day")" \
        "${LAT_MONTHS[10#$mon - 1]}" \
        "$(roman "$year")"
}

# --- Context ----------------------------------------------------------------

wallpaper_name() {
    local wp=""
    if command -v swww >/dev/null 2>&1; then
        wp=$(swww query 2>/dev/null | head -n1 | grep -o 'image: .*' | cut -d' ' -f2-)
    fi
    if [[ -z $wp && -r "$HOME/.config/waypaper/config.ini" ]]; then
        wp=$(awk -F= '/^[[:space:]]*wallpaper[[:space:]]*=/{sub(/^[[:space:]]+/,"",$2); print $2; exit}' \
            "$HOME/.config/waypaper/config.ini")
    fi
    [[ -n $wp ]] && printf '%s' "${wp##*/}"
}

now_playing() {
    command -v playerctl >/dev/null 2>&1 || return
    local s
    s=$(playerctl metadata --format '{{artist}} — {{title}}' 2>/dev/null) || return
    s=${s# — }
    [[ -n $s ]] && printf '%s' "$s"
}

# --- Layout -----------------------------------------------------------------

COLS=34 ROWS=30 W=30 IMG_TOP=4 IMG_ROWS=14 INFO_TOP=19 RULE=""
measure() {
    COLS=$(tput cols 2>/dev/null || echo 34)
    ROWS=$(tput lines 2>/dev/null || echo 30)
    W=$((COLS - 4))
    ((W < 16)) && W=16
    IMG_TOP=4
    # Reserve the lower third for the live block, give the rest to the artwork.
    IMG_ROWS=$((ROWS - IMG_TOP - 11))
    ((IMG_ROWS < 6)) && IMG_ROWS=6
    INFO_TOP=$((IMG_TOP + IMG_ROWS + 1))
    RULE=$(printf '─%.0s' $(seq 1 "$W"))
}

center() {
    local text=$1 len=${2:-${#1}} pad
    pad=$(((W - len) / 2))
    ((pad < 0)) && pad=0
    printf '%*s%s' "$pad" "" "$text"
}

FRAME=""
L() { FRAME+="  ${1-}"$'\033[K\n'; }

rule() { L "${E_RULE}${RULE}${RS}"; }

# Static chrome plus the artwork; only redrawn on resize.
draw_static() {
    local sigil title="I M P E R I V M"
    printf '\033[2J\033[H'
    printf '  %s%s%s%s\033[K\n' "$E_ACCENT" "$BD" "$(center "✠ $title ✠" $((${#title} + 4)))" "$RS"
    printf '  %s%s%s\033[K\n' "$E_RULE" "$RULE" "$RS"

    sigil=$(pick_sigil)
    if [[ -n $sigil ]] && command -v chafa >/dev/null 2>&1; then
        printf '\033[%d;3H' "$IMG_TOP"
        chafa --format kitty --animate off --polite on --scale max \
            --bg "#${wc_bg}" --align center,center \
            --size "${W}x${IMG_ROWS}" "$sigil" 2>/dev/null
    fi
}

draw_live() {
    FRAME=""
    rule
    L "${E_TIME}${BD}$(center "$(date '+%H:%M:%S')" 8)${RS}"
    local ld
    ld=$(latin_date)
    L "${E_LABEL}$(center "$ld" ${#ld})${RS}"
    rule

    # The live wallust palette, rendered as its own swatch strip.
    local i strip="" name
    for i in {0..15}; do
        name="wc_$i"
        strip+="$(bg "${!name}") "
    done
    strip+="$RS"
    local swatch_pad=$(((W - 32) / 2))
    ((swatch_pad < 0)) && swatch_pad=0
    L "$(printf '%*s' "$swatch_pad" "")${strip}"
    L "${E_MUTED}$(center "PALETTA WALLVSTI" 16)${RS}"
    L ""

    local wp="$CACHE_WP" np="$CACHE_NP"
    [[ -n $wp ]] && {
        ((${#wp} > W - 3)) && wp="${wp:0:W-6}..."
        L "${E_ACCENT}󰸉${RS} ${E_MUTED}${wp}${RS}"
    }
    [[ -n $np ]] && {
        ((${#np} > W - 3)) && np="${np:0:W-6}..."
        L "${E_ACCENT}󰎇${RS} ${E_MUTED}${np}${RS}"
    }

    printf '\033[%d;1H%s\033[J' "$INFO_TOP" "$FRAME"
}

# --- Main -------------------------------------------------------------------

printf '\033[?25l'
measure
draw_static
trap 'measure; draw_static' WINCH

# Both lookups spawn helper processes, so they run on their own slow cadence
# rather than once per clock tick.
CACHE_WP="" CACHE_NP="" tick=0
while :; do
    ((tick % 15 == 0)) && CACHE_WP=$(wallpaper_name)
    ((tick % 2 == 0)) && CACHE_NP=$(now_playing)
    draw_live
    ((tick++))
    sleep "$INTERVAL"
done
