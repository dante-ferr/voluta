#!/usr/bin/env bash
# imperium_sigil.sh - Heraldic panel of the Imperium Command Deck.
#
# Renders the rice's sigil artwork through the kitty graphics protocol, then a
# live clock with a Latin/Roman date, the active wallust palette, the wallpaper
# currently driving that palette, and whatever is playing. While music plays,
# the image frame swaps the sigil for the track's cover art, so the panel gains
# the art without growing.

set -uo pipefail

# shellcheck source=lib/wallust_env.sh
source "$HOME/.config/hypr/UserScripts/lib/wallust_env.sh"

ASSETS="$HOME/.config/fastfetch/assets"
# If ~/.config/fastfetch is a symlink into the rice, follow it so a machine that
# cloned the repo somewhere other than ~/imperivm-dotfiles still finds the art.
if [[ -L "$HOME/.config/fastfetch" ]]; then
    ASSETS="$(readlink -f "$HOME/.config/fastfetch")/assets"
fi
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/imperium"
INTERVAL=1

# Artwork currently occupying the image frame: the track's cover while music
# plays, the tinted sigil otherwise. draw_art resolves the fallback itself.
ART_IMG=""

RS=$(rs)
BD=$(bold)
E_ACCENT=$(fg "$wc_12")
E_LABEL=$(fg "$wc_7")
E_TIME=$(fg "$wc_15")
E_MUTED=$(fg "$(mix "$wc_bg" "$wc_fg" 40)")
E_RULE=$(fg "$(mix "$wc_bg" "$wc_12" 75)")

# Kitty graphics placements outlive an erase-screen, so a resize would otherwise
# leave the previous, differently-sized sigil layered over the live block.
clear_images() { printf '\033_Ga=d,d=A\033\\'; }

trap 'clear_images; printf "\033[?25h\033[0m\n"' EXIT INT TERM

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

# Recolour the artwork into the live palette: luminance drives a ramp from the
# panel background up to the accent, so the sigil reads as part of whatever
# wallpaper is driving wallust rather than as a fixed gold plate.
#
# Two corrections keep it legible at panel size. The accent is lifted most of
# the way towards color15, because palettes usually put color12 mid-dark and a
# ramp topping out there sinks the crown and filigree. The gamma lift then
# raises the midtones, where nearly all of this painting's detail lives; gamma
# leaves the endpoints alone, so the darkest areas still match the panel
# background and the art keeps its borderless edge.
#
# The result is cached under XDG_CACHE_HOME, not in the repo: it is a derived
# artifact and there is one per wallpaper.
SIGIL_GAMMA=2.0
SIGIL_LIFT=75

tint_sigil() {
    local src=$1 hi key out
    [[ -n $src ]] || return
    command -v magick >/dev/null 2>&1 || {
        printf '%s' "$src"
        return
    }

    hi=$(mix "$wc_12" "$wc_15" "$SIGIL_LIFT")
    key=$(printf '%s|%s|%s|%s|%s' "$src" "$(stat -c %Y "$src" 2>/dev/null)" \
        "$wc_bg" "$hi" "$SIGIL_GAMMA" | cksum | cut -d' ' -f1)
    out="$CACHE/sigil-$key.png"

    if [[ ! -s $out ]]; then
        mkdir -p "$CACHE" 2>/dev/null
        magick "$src" -colorspace Gray -auto-level -gamma "$SIGIL_GAMMA" \
            \( -size 1x256 gradient:"#${wc_bg}"-"#${hi}" \) -clut \
            -resize '700x>' -strip PNG24:"$out" 2>/dev/null || {
            printf '%s' "$src"
            return
        }
        # One cached tint per palette is enough; the rest are last wallpaper's.
        find "$CACHE" -maxdepth 1 -name 'sigil-*.png' ! -name "${out##*/}" -delete 2>/dev/null
    fi
    printf '%s' "$out"
}

# --- Album cover ------------------------------------------------------------

# The frame belongs to whatever is actually playing. A paused browser tab or
# an idle player still advertises art over MPRIS, and letting that through
# evicts the sigil even though nothing is audible.
playing_player() {
    command -v playerctl >/dev/null 2>&1 || return 1
    local p
    while IFS= read -r p; do
        if [[ $(playerctl -p "$p" status 2>/dev/null) == Playing ]]; then
            printf '%s' "$p"
            return 0
        fi
    done < <(playerctl -l 2>/dev/null)
    return 1
}

url_decode() { local s=${1//%/\\x}; printf '%b' "$s"; }

# Chafa rebuilds the frame at cell resolution, so art much smaller than this
# turns into a smear once kitty stretches it across the panel; the sigil is
# the better picture then.
COVER_MIN_PX=300

# playerctl reports the art as either a file:// path into the player's own
# cache or an https URL. Both are resolved to a local file under the imperium
# cache so chafa always reads from disk, and so a track that stays playing
# only ever pays the copy/download once.
cover_art() {
    local player=${1:-$(playing_player)}
    [[ -n $player ]] || return
    local url
    url=$(playerctl -p "$player" metadata mpris:artUrl 2>/dev/null) || return
    [[ -n $url ]] || return

    local key out
    key=$(printf '%s' "$url" | cksum | cut -d' ' -f1)
    out="$CACHE/cover-$key"
    if [[ ! -s $out ]]; then
        mkdir -p "$CACHE" 2>/dev/null
        case $url in
            file://*)
                local path
                path=$(url_decode "${url#file://}")
                [[ -r $path ]] || return
                cp "$path" "$out" 2>/dev/null || return
                ;;
            http://* | https://*)
                command -v curl >/dev/null 2>&1 || return
                curl -fsSL --max-time 4 -o "$out" "$url" 2>/dev/null || {
                    rm -f "$out"
                    return
                }
                ;;
            *)
                return
                ;;
        esac
        # Covers rotate with every track; one cached cover is enough.
        find "$CACHE" -maxdepth 1 -name 'cover-*' ! -name "${out##*/}" -delete 2>/dev/null
    fi

    # Reject corrupt or tiny art. Running the check on cache hits too is what
    # lets a rejected cover stay cached without ever being fetched again.
    if command -v magick >/dev/null 2>&1; then
        local dim
        dim=$(magick identify -format '%w %h' "$out" 2>/dev/null)
        if [[ ! $dim =~ ^([0-9]+)\ ([0-9]+)$ ]]; then
            rm -f "$out"
            return
        fi
        ((BASH_REMATCH[1] >= COVER_MIN_PX && BASH_REMATCH[2] >= COVER_MIN_PX)) || return
    fi
    printf '%s' "$out"
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
    # Prefer the playing player so the caption names the same track the frame
    # shows; with nothing playing, fall back to playerctl's own pick as before.
    local p=${1:-$(playing_player)} s
    if [[ -n $p ]]; then
        s=$(playerctl -p "$p" metadata --format '{{artist}} — {{title}}' 2>/dev/null)
    else
        s=$(playerctl metadata --format '{{artist}} — {{title}}' 2>/dev/null)
    fi
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

# The image frame: cover art while a track plays, the tinted sigil otherwise.
# Kitty placements stack instead of replacing, so every (re)draw first drops
# all placements — the frame only ever holds this one image.
draw_art() {
    local img=${ART_IMG:-${SIGIL_IMG:-}}
    clear_images
    [[ -n $img ]] || return
    command -v chafa >/dev/null 2>&1 || return
    # Start at column 1 and hand chafa the full width. Its centring is
    # measured against the whole view rather than --size, so indenting the
    # cursor first shifted the art right by exactly that indent. Aligning to
    # the top likewise stops it padding down over the live block.
    printf '\033[%d;1H' "$IMG_TOP"
    chafa --format kitty --animate off --polite on --scale max \
        --bg "#${wc_bg}" --align top,center \
        --size "${COLS}x${IMG_ROWS}" "$img" 2>/dev/null
}

# Static chrome plus the artwork; only redrawn on resize.
draw_static() {
    local title="I M P E R I V M"
    printf '\033[2J\033[H'
    printf '  %s%s%s%s\033[K\n' "$E_ACCENT" "$BD" "$(center "✠ $title ✠" $((${#title} + 4)))" "$RS"
    printf '  %s%s%s\033[K\n' "$E_RULE" "$RULE" "$RS"

    SIGIL_IMG=$(tint_sigil "$(pick_sigil)")
    draw_art
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
    # Two cells per swatch, so the strip is the 32 columns swatch_pad assumes.
    for i in {0..15}; do
        name="wc_$i"
        strip+="$(bg "${!name}")  "
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
# rather than once per clock tick. The playing player is resolved once per
# pass so the caption and the cover can never come from two different ones.
CACHE_WP="" CACHE_NP="" CACHE_ART="" tick=0 art="" player=""
while :; do
    ((tick % 15 == 0)) && CACHE_WP=$(wallpaper_name)
    if ((tick % 2 == 0)); then
        player=$(playing_player)
        CACHE_NP=$(now_playing "$player")
        art=$(cover_art "$player")
        # The frame repaints on a track change only: clearing and re-placing
        # the image on every pass would flicker.
        if [[ $art != "$CACHE_ART" ]]; then
            CACHE_ART=$art
            ART_IMG=$art
            draw_art
        fi
    fi
    draw_live
    ((tick++))
    sleep "$INTERVAL"
done
