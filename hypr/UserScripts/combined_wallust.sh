#!/usr/bin/env bash
# combined_wallust.sh - Generate wallust color schemes and reload desktop components
#
# Waypaper's post_command is fire-and-forget and can overlap a refresh already
# in progress. Callers write the requested path to PENDING, then wait briefly
# for the lock. The holder drains PENDING so the latest wallpaper wins.
#
# GTK caches @import CSS, so SIGUSR2 does not pick up a new wallust palette.
# The bar has to be restarted. Hyprland is then reloaded so window borders
# and Lua decorations pick up the new palette.
set +m

wallpaper="$1"

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if [[ -z "$WAYLAND_DISPLAY" ]]; then
    for sock in "$XDG_RUNTIME_DIR"/wayland-*; do
        if [[ -S "$sock" ]]; then
            export WAYLAND_DISPLAY="$(basename "$sock")"
            break
        fi
    done
    export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
fi

_rice_paths="$HOME/.config/hypr/UserScripts/lib/rice_paths.sh"
[[ -r $_rice_paths ]] || _rice_paths="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/rice_paths.sh"
# shellcheck source=lib/rice_paths.sh
source "$_rice_paths"

LOCK_DIR="${XDG_RUNTIME_DIR:-/tmp}"
[[ -n "$LOCK_DIR" && -w "$LOCK_DIR" ]] || LOCK_DIR="/tmp"
LOCK="$LOCK_DIR/imperium-combined-wallust.lock"
PENDING="$LOCK_DIR/imperium-combined-wallust.pending"

if [[ -n "$wallpaper" ]]; then
    pending_tmp="${PENDING}.$$"
    printf '%s\n' "$wallpaper" >"$pending_tmp" && mv -f "$pending_tmp" "$PENDING" || true
    rm -f "$pending_tmp"
fi

exec 9>"$LOCK" || {
    echo "combined_wallust: cannot open lock $LOCK" >&2
    exit 1
}

# Wait a bit so overlapping post_commands coalesce. Give up rather than hang
# forever if a previous refresh is stuck.
if ! flock -w 8 9; then
    echo "combined_wallust: lock busy, leaving $PENDING for the holder" >&2
    exit 0
fi

expand_path() {
    local p="$1"
    p="${p#"${p%%[![:space:]]*}"}"
    p="${p%"${p##*[![:space:]]}"}"
    p="${p#\"}"
    p="${p%\"}"
    p="${p#\'}"
    p="${p%\'}"
    p="${p//\\ / }"
    p="${p/#\~/$HOME}"
    printf '%s\n' "$p"
}

get_active_monitors() {
    if command -v hyprctl >/dev/null 2>&1; then
        if command -v jq >/dev/null 2>&1; then
            hyprctl monitors -j 2>/dev/null | jq -r '
                (map(select(.id == 0)) | .[0].name // empty),
                (map(select(.focused == true)) | .[0].name // empty),
                (.[].name // empty)
            ' 2>/dev/null | awk '!seen[$0]++'
            return
        else
            hyprctl monitors 2>/dev/null | grep -E '^Monitor ' | awk '{print $2}'
            return
        fi
    fi
}

resolve_wallpaper() {
    local wp
    wp=$(expand_path "$1")
    if [[ -n "$wp" && -f "$wp" ]]; then
        printf '%s\n' "$wp"
        return
    fi
    if [[ -n "$wp" ]]; then
        if [[ -f "$HOME/Pictures/Wallpapers/$wp" ]]; then
            printf '%s\n' "$HOME/Pictures/Wallpapers/$wp"
            return
        elif [[ -f "$HOME/Pictures/$wp" ]]; then
            printf '%s\n' "$HOME/Pictures/$wp"
            return
        fi
    fi

    local monitors=()
    while IFS= read -r mon; do
        [[ -n "$mon" ]] && monitors+=("$mon")
    done < <(get_active_monitors)

    # 1. Query live wallpaper daemons (awww, swww)
    local query_out=""
    for daemon in awww swww; do
        command -v "$daemon" >/dev/null 2>&1 || continue
        for (( retry=0; retry<10; retry++ )); do
            query_out=$("$daemon" query 2>/dev/null || true)
            [[ -n "$query_out" ]] && break
            if pgrep -x "${daemon}-daemon" >/dev/null 2>&1 || pgrep -x "$daemon" >/dev/null 2>&1; then
                sleep 0.15
            else
                break
            fi
        done
        if [[ -n "$query_out" ]]; then
            for mon in "${monitors[@]}"; do
                wp=$(echo "$query_out" | grep -E "(^|: )${mon}:" | grep -o 'image: .*' | head -n 1 | cut -d ' ' -f 2-)
                wp=$(expand_path "$wp")
                if [[ -n "$wp" && -f "$wp" ]]; then
                    printf '%s\n' "$wp"
                    return
                fi
            done
            wp=$(echo "$query_out" | grep -o 'image: .*' | head -n 1 | cut -d ' ' -f 2-)
            wp=$(expand_path "$wp")
            if [[ -n "$wp" && -f "$wp" ]]; then
                printf '%s\n' "$wp"
                return
            fi
        fi
    done

    # 2. Check waypaper persistent state (handles multi-line per-monitor configs)
    if command -v python3 >/dev/null 2>&1; then
        wp=$(python3 -c '
import configparser, os, sys

active_monitors = sys.argv[1:]
for conf in ["~/.local/state/waypaper/state.ini", "~/.config/waypaper/config.ini"]:
    path = os.path.expanduser(conf)
    if not os.path.isfile(path):
        continue
    p = configparser.ConfigParser()
    try:
        p.read(path, "utf-8")
    except Exception:
        continue
    sec = "State" if p.has_section("State") else ("Settings" if p.has_section("Settings") else None)
    if not sec:
        continue
    mons = [m.strip() for m in p.get(sec, "monitors", fallback="").splitlines() if m.strip()]
    walls = [w.strip() for w in p.get(sec, "wallpaper", fallback="").splitlines() if w.strip()]
    mapping = dict(zip(mons, walls))
    for m in active_monitors:
        if m in mapping and mapping[m]:
            expanded = os.path.expanduser(mapping[m])
            if os.path.isfile(expanded):
                print(expanded)
                sys.exit(0)
    if "All" in mapping and mapping["All"]:
        expanded = os.path.expanduser(mapping["All"])
        if os.path.isfile(expanded):
            print(expanded)
            sys.exit(0)
    for w in walls:
        expanded = os.path.expanduser(w)
        if os.path.isfile(expanded):
            print(expanded)
            sys.exit(0)
' "${monitors[@]}" 2>/dev/null)
        if [[ -n "$wp" && -f "$wp" ]]; then
            printf '%s\n' "$wp"
            return
        fi
    fi

    # 3. Fallback to default wallpaper assets if nothing else resolved
    local default_wp="$HOME/.config/hypr/assets/school-of-athens.jpg"
    if [[ -f "$default_wp" ]]; then
        printf '%s\n' "$default_wp"
        return
    fi
}

# GTK resolves CSS url() against waybar's working directory (often $HOME),
# not the stylesheet, so relative assets/angel-*.svg paths vanish on any
# machine that does not start waybar from ~/.config/waybar. Write absolute
# file:// URLs after every refresh; style.css imports this when it exists.
write_waybar_angel_css() {
    local waybar_dir css left right lit_left lit_right
    local cherub_left cherub_right lit_cherub_left lit_cherub_right
    local outer_left outer_right lit_outer_left lit_outer_right
    local rinceau_left rinceau_right
    local spread_left spread_right
    local volute_left lyre lyre_paused corbel_left corbel_right patera mascaron
    waybar_dir=$(imperium_waybar_dir)
    [[ -d $waybar_dir ]] || return
    mkdir -p "$waybar_dir/wallust"
    left="$waybar_dir/assets/angel-left.svg"
    right="$waybar_dir/assets/angel-right.svg"
    lit_left="$waybar_dir/wallust/angel-left-lit.svg"
    lit_right="$waybar_dir/wallust/angel-right-lit.svg"
    cherub_left="$waybar_dir/assets/cherub-left.svg"
    cherub_right="$waybar_dir/assets/cherub-right.svg"
    lit_cherub_left="$waybar_dir/wallust/cherub-left-lit.svg"
    lit_cherub_right="$waybar_dir/wallust/cherub-right-lit.svg"
    outer_left="$waybar_dir/assets/cherub-outer-left.svg"
    outer_right="$waybar_dir/assets/cherub-outer-right.svg"
    lit_outer_left="$waybar_dir/wallust/cherub-outer-left-lit.svg"
    lit_outer_right="$waybar_dir/wallust/cherub-outer-right-lit.svg"
    rinceau_left="$waybar_dir/assets/rinceau-left.svg"
    rinceau_right="$waybar_dir/assets/rinceau-right.svg"
    spread_left="$waybar_dir/assets/spread-left.svg"
    spread_right="$waybar_dir/assets/spread-right.svg"
    volute_left="$waybar_dir/assets/volute-left.svg"
    lyre="$waybar_dir/assets/lyre.svg"
    lyre_paused="$waybar_dir/assets/lyre-paused.svg"
    corbel_left="$waybar_dir/assets/corbel-left.svg"
    corbel_right="$waybar_dir/assets/corbel-right.svg"
    patera="$waybar_dir/assets/patera.svg"
    mascaron="$waybar_dir/assets/mascaron.svg"
    [[ -f $lit_left ]] || lit_left=$left
    [[ -f $lit_right ]] || lit_right=$right
    [[ -f $lit_cherub_left ]] || lit_cherub_left=$cherub_left
    [[ -f $lit_cherub_right ]] || lit_cherub_right=$cherub_right
    [[ -f $lit_outer_left ]] || lit_outer_left=$outer_left
    [[ -f $lit_outer_right ]] || lit_outer_right=$outer_right
    [[ -f $left && -f $right ]] || return

    css="$waybar_dir/wallust/angel-paths.css"
    cat >"$css" <<EOF
#custom-angel-left {
    background-image: url("file://${left}");
}
#custom-angel-right {
    background-image: url("file://${right}");
}
#custom-cherub-left {
    background-image: url("file://${cherub_left}");
}
#custom-cherub-right {
    background-image: url("file://${cherub_right}");
}
#custom-cherub-outer-left {
    background-image: url("file://${outer_left}");
}
#custom-cherub-outer-right {
    background-image: url("file://${outer_right}");
}
.modules-center,
box.modules-center {
    background-image: url("file://${rinceau_left}"), url("file://${rinceau_right}");
}
.modules-left,
box.modules-left {
    background-image: url("file://${spread_left}");
}
.modules-right,
box.modules-right {
    background-image: url("file://${spread_right}");
}
#window {
    background-image: url("file://${volute_left}");
}
#mpris {
    background-image: url("file://${lyre}"), url("file://${corbel_right}");
}
#mpris.paused {
    background-image: url("file://${lyre_paused}"), url("file://${corbel_right}");
}
#custom-swaync {
    background-image: url("file://${corbel_left}");
}
#pulseaudio {
    background-image: url("file://${corbel_right}");
}
#custom-patera {
    background-image: url("file://${patera}");
}
#custom-power {
    background-image: url("file://${mascaron}");
}
@keyframes angel-flare-left {
    0% { background-image: url("file://${lit_left}"); }
    100% { background-image: url("file://${left}"); }
}
@keyframes angel-flare-right {
    0% { background-image: url("file://${lit_right}"); }
    100% { background-image: url("file://${right}"); }
}
@keyframes cherub-flare-left {
    0% { background-image: url("file://${lit_cherub_left}"); }
    100% { background-image: url("file://${cherub_left}"); }
}
@keyframes cherub-flare-right {
    0% { background-image: url("file://${lit_cherub_right}"); }
    100% { background-image: url("file://${cherub_right}"); }
}
@keyframes cherub-outer-flare-left {
    0% { background-image: url("file://${lit_outer_left}"); }
    100% { background-image: url("file://${outer_left}"); }
}
@keyframes cherub-outer-flare-right {
    0% { background-image: url("file://${lit_outer_right}"); }
    100% { background-image: url("file://${outer_right}"); }
}
EOF
}

# Restart the bar. SIGUSR2 does not reload GTK @import of wallust/colors-waybar.css,
# so the palette would stay frozen if we only sent a signal. Close the lock fd
# before exec: a live waybar that inherits it pins the flock until logout.
launch_waybar() {
    local waybar_dir count=0
    command -v waybar >/dev/null 2>&1 || return

    pkill -x waybar || true
    while pgrep -x waybar >/dev/null 2>&1 && (( count < 10 )); do
        sleep 0.04
        (( count++ ))
    done
    if pgrep -x waybar >/dev/null 2>&1; then
        pkill -9 -x waybar || true
        sleep 0.04
    fi

    waybar_dir=$(imperium_waybar_dir)
    local shim="${waybar_dir}/lib/libwaybar_hyprland_shim.so"
    (
        exec 9>&-
        if [[ -f $shim ]]; then
            export LD_PRELOAD="$shim${LD_PRELOAD:+:$LD_PRELOAD}"
        fi
        if [[ -d $waybar_dir ]]; then
            cd "$waybar_dir" || exit 0
        fi
        exec setsid -f waybar >/dev/null 2>&1
    ) &
    disown $! 2>/dev/null || true
}

reload_hyprland() {
    command -v hyprctl >/dev/null 2>&1 || return
    # Re-runs hyprland.lua, which drops the cached wallust module and reapplies
    # decorations. Keywords do not restyle already-mapped windows on this setup.
    timeout -k 1 5 hyprctl reload >/dev/null 2>&1 || true
}

finish_refresh() {
    if command -v magick >/dev/null 2>&1; then
        local asset_dir source_img dest_img
        asset_dir=$(imperium_fastfetch_assets)
        mkdir -p "$asset_dir"
        source_img="$asset_dir/crown-angels.jpg"
        dest_img="$asset_dir/crown-angels-styled.png"
        if [[ -f $source_img && ( ! -f $dest_img || $source_img -nt $dest_img ) ]]; then
            magick "$source_img" -fuzz 14% -transparent black \
                "$dest_img" >/dev/null 2>&1 || true
        fi
    fi

    if command -v swaync-client >/dev/null 2>&1; then
        swaync-client -R -rs >/dev/null 2>&1 || true
    fi

    if command -v kitty >/dev/null 2>&1; then
        pkill -SIGUSR1 -x kitty >/dev/null 2>&1 || true
        if [[ -f "$HOME/.config/kitty/kitty-themes/01-Wallust.conf" ]]; then
            kitty @ set-colors --all "$HOME/.config/kitty/kitty-themes/01-Wallust.conf" >/dev/null 2>&1 || true
        fi
    fi

    if command -v cava >/dev/null 2>&1; then
        pkill -USR2 cava >/dev/null 2>&1 || true
    fi

    if [[ -r $HOME/.config/wlogout/paint-icons.sh ]]; then
        # shellcheck source=/dev/null
        source "$HOME/.config/wlogout/paint-icons.sh"
        paint_wlogout_icons
    fi
}

do_refresh() {
    local wp="$1"

    # -q is a global flag: `wallust -q run …`, not `wallust run -q`.
    if [[ -n "$wp" && -f "$wp" ]] && command -v wallust >/dev/null 2>&1; then
        wallust -q run -s "$wp"
    fi

    write_waybar_angel_css
    launch_waybar
    # Close fd 9 in the child so hyprctl/swaync cannot inherit the flock.
    (
        exec 9>&-
        # Let the wallpaper fade start so reload is not fighting the compositor.
        sleep 0.5
        reload_hyprland
        finish_refresh
    ) &
    disown $! 2>/dev/null || true
}

last_wp=""
while true; do
    if [[ -r "$PENDING" ]]; then
        wallpaper=$(cat "$PENDING")
        rm -f "$PENDING"
    elif [[ -n "$last_wp" ]]; then
        break
    fi
    wallpaper=$(resolve_wallpaper "$wallpaper")
    if [[ -z "$last_wp" || ( -n "$wallpaper" && "$wallpaper" != "$last_wp" ) ]]; then
        do_refresh "$wallpaper"
        last_wp="${wallpaper:-__none__}"
    fi
done
