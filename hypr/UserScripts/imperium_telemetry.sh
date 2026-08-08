#!/usr/bin/env bash
# imperium_telemetry.sh - Live telemetry panel of the Imperium Command Deck.
#
# Renders CPU / RAM / GPU history graphs, thermals, storage, network and power
# in the current wallust palette. Runs inside its own floating kitty window.
#
# Every escape sequence and repeated glyph run is precomputed at startup (and on
# resize) so a frame costs no subshells: the draw loop only concatenates strings.

set -uo pipefail

# shellcheck source=lib/wallust_env.sh
source "$HOME/.config/hypr/UserScripts/lib/wallust_env.sh"

INTERVAL=1
GPU_CACHE="${XDG_RUNTIME_DIR:-/tmp}/imperium-gpu.$$"
SPARK=(▁ ▂ ▃ ▄ ▅ ▆ ▇ █)

# --- Palette roles ----------------------------------------------------------
# Named roles resolved once from wallust; a wallpaper change is the only thing
# needed to restyle the whole panel.

RS=$(rs)
BD=$(bold)
E_TITLE=$(fg "$wc_15")
E_ACCENT=$(fg "$wc_12")
E_LABEL=$(fg "$wc_7")
E_VALUE=$(fg "$wc_15")
E_MUTED=$(fg "$(mix "$wc_bg" "$wc_fg" 40)")
E_TRACK=$(fg "$(mix "$wc_bg" "$wc_fg" 20)")
E_RULE=$(fg "$(mix "$wc_bg" "$wc_12" 75)")
# ANSI slots 2/3/1 carry the green/yellow/red hues of a wallust theme, so the
# severity ramp stays on-palette while keeping the expected warning ordering.
E_LOW=$(fg "$wc_2")
E_MID=$(fg "$wc_3")
E_HIGH=$(fg "$wc_1")
E_DOWN=$(fg "$wc_2")
E_UP=$(fg "$wc_3")

cleanup() {
    printf '\033[?25h\033[0m\n'
    [[ -n "${GPU_PID:-}" ]] && kill "$GPU_PID" 2>/dev/null
    rm -f "$GPU_CACHE"
}
trap cleanup EXIT INT TERM

# --- Sampling ---------------------------------------------------------------

declare -a cpu_prev_total=() cpu_prev_idle=() cpu_pct=()
sample_cpu() {
    local key user nice sys idle iowait irq softirq steal idx=0 total idlev dt di
    while read -r key user nice sys idle iowait irq softirq steal _; do
        [[ $key == cpu* ]] || break
        total=$((user + nice + sys + idle + iowait + irq + softirq + steal))
        idlev=$((idle + iowait))
        dt=$((total - ${cpu_prev_total[idx]:-0}))
        di=$((idlev - ${cpu_prev_idle[idx]:-0}))
        if ((dt > 0)); then cpu_pct[idx]=$((100 * (dt - di) / dt)); else cpu_pct[idx]=0; fi
        cpu_prev_total[idx]=$total
        cpu_prev_idle[idx]=$idlev
        ((idx++))
    done </proc/stat
}

mem_total=1 mem_used=0 mem_pct=0 swap_pct=0
sample_mem() {
    local k v swap_total=0 swap_free=0 mem_avail=0
    while read -r k v _; do
        case $k in
            MemTotal:) mem_total=$v ;;
            MemAvailable:) mem_avail=$v ;;
            SwapTotal:) swap_total=$v ;;
            SwapFree:) swap_free=$v ;;
        esac
    done </proc/meminfo
    mem_used=$((mem_total - mem_avail))
    mem_pct=$((100 * mem_used / mem_total))
    if ((swap_total > 0)); then swap_pct=$((100 * (swap_total - swap_free) / swap_total)); else swap_pct=0; fi
}

net_prev_rx=0 net_prev_tx=0 net_rx_rate=0 net_tx_rate=0
sample_net() {
    local line iface rx=0 tx=0
    while read -r line; do
        [[ $line == *:* ]] || continue
        iface=${line%%:*}
        iface=${iface// /}
        [[ $iface == lo ]] && continue
        # shellcheck disable=SC2086
        set -- ${line#*:}
        rx=$((rx + $1))
        tx=$((tx + $9))
    done </proc/net/dev
    if ((net_prev_rx > 0)); then
        net_rx_rate=$(((rx - net_prev_rx) / INTERVAL))
        net_tx_rate=$(((tx - net_prev_tx) / INTERVAL))
    fi
    net_prev_rx=$rx
    net_prev_tx=$tx
}

declare -A TEMP_PATH=()
discover_temps() {
    local h name lbl f
    for h in /sys/class/hwmon/hwmon*; do
        [[ -r "$h/name" ]] || continue
        name=$(<"$h/name")
        case $name in
            coretemp | k10temp | zenpower)
                for f in "$h"/temp*_label; do
                    [[ -r "$f" ]] || continue
                    lbl=$(<"$f")
                    [[ $lbl == "Package id 0" || $lbl == Tctl ]] && TEMP_PATH[cpu]="${f%_label}_input"
                done
                [[ -n ${TEMP_PATH[cpu]:-} ]] || TEMP_PATH[cpu]="$h/temp1_input"
                ;;
            nvme) [[ -n ${TEMP_PATH[ssd]:-} ]] || TEMP_PATH[ssd]="$h/temp1_input" ;;
            mt7921* | iwlwifi | ath* | rtw*) TEMP_PATH[net]="$h/temp1_input" ;;
            acpitz) [[ -n ${TEMP_PATH[brd]:-} ]] || TEMP_PATH[brd]="$h/temp1_input" ;;
        esac
    done
}

t_cpu=-1 t_ssd=-1 t_net=-1
sample_temps() {
    local p
    p=${TEMP_PATH[cpu]:-}; if [[ -r ${p:-/nonexistent} ]]; then t_cpu=$(($(<"$p") / 1000)); fi
    p=${TEMP_PATH[ssd]:-}; if [[ -r ${p:-/nonexistent} ]]; then t_ssd=$(($(<"$p") / 1000)); fi
    p=${TEMP_PATH[net]:-}; if [[ -r ${p:-/nonexistent} ]]; then t_net=$(($(<"$p") / 1000)); fi
}

# nvidia-smi costs ~200ms per invocation, far too slow for the draw loop, so it
# streams into a cache file that the loop only ever reads the last line of.
gpu_name="" gpu_util=-1 gpu_temp=-1 gpu_mem_used=0 gpu_mem_total=0
start_gpu_feed() {
    command -v nvidia-smi >/dev/null 2>&1 || return
    : >"$GPU_CACHE"
    stdbuf -oL nvidia-smi \
        --query-gpu=name,utilization.gpu,temperature.gpu,memory.used,memory.total \
        --format=csv,noheader,nounits -l "$INTERVAL" >"$GPU_CACHE" 2>/dev/null &
    GPU_PID=$!
}

sample_gpu() {
    [[ -s "$GPU_CACHE" ]] || return
    local line
    line=$(tail -n 1 "$GPU_CACHE" 2>/dev/null)
    [[ -n $line ]] || return
    IFS=, read -r gpu_name gpu_util gpu_temp gpu_mem_used gpu_mem_total <<<"$line"
    gpu_name="${gpu_name## }"
    gpu_name="${gpu_name/NVIDIA GeForce /}"
    gpu_util="${gpu_util## }"
    gpu_temp="${gpu_temp## }"
    gpu_mem_used="${gpu_mem_used## }"
    gpu_mem_total="${gpu_mem_total## }"
    [[ $gpu_util =~ ^[0-9]+$ ]] || gpu_util=-1
    [[ $gpu_temp =~ ^[0-9]+$ ]] || gpu_temp=-1
}

disk_pct=0 disk_free=""
sample_disk() {
    read -r _ _ disk_free disk_pct _ < <(df -h --output=size,used,avail,pcent,target / | tail -1)
    disk_pct=${disk_pct%\%}
    [[ $disk_pct =~ ^[0-9]+$ ]] || disk_pct=0
}

bat_pct=-1 bat_status=""
sample_battery() {
    local b
    for b in /sys/class/power_supply/BAT*; do
        [[ -r "$b/capacity" ]] || continue
        bat_pct=$(<"$b/capacity")
        bat_status=$(<"$b/status")
        return
    done
}

# --- Formatting -------------------------------------------------------------

fmt_kib() {
    local k=$1
    if ((k >= 1048576)); then printf '%d.%dG' $((k / 1048576)) $(((k % 1048576) * 10 / 1048576))
    else printf '%dM' $((k / 1024)); fi
}

fmt_rate() {
    local b=$1
    if ((b >= 1048576)); then printf '%d.%d MB/s' $((b / 1048576)) $(((b % 1048576) * 10 / 1048576))
    elif ((b >= 1024)); then printf '%d.%d KB/s' $((b / 1024)) $(((b % 1024) * 10 / 1024))
    else printf '%d B/s' "$b"; fi
}

fmt_temp() {
    local t=$1
    if ((t < 0)); then printf '  --°'; else printf '%3d°' "$t"; fi
}

# --- Geometry and precomputed glyph runs ------------------------------------

COLS=50 ROWS=30 W=46 GW=24 GRAPH_CPU=4 GRAPH_MEM=3 GRAPH_GPU=2
declare -a PRE_BLOCK=() PRE_DASH=() PRE_SPACE=()

measure() {
    COLS=$(tput cols 2>/dev/null || echo 50)
    ROWS=$(tput lines 2>/dev/null || echo 30)
    W=$((COLS - 4))
    ((W > 64)) && W=64
    ((W < 18)) && W=18
    # One shared bar width keeps every gauge's end cap on the same column.
    GW=$((W - 22))
    ((GW < 8)) && GW=8
    if ((ROWS >= 38)); then GRAPH_CPU=5 GRAPH_MEM=3 GRAPH_GPU=3
    elif ((ROWS >= 32)); then GRAPH_CPU=4 GRAPH_MEM=3 GRAPH_GPU=2
    elif ((ROWS >= 27)); then GRAPH_CPU=3 GRAPH_MEM=2 GRAPH_GPU=2
    else GRAPH_CPU=2 GRAPH_MEM=1 GRAPH_GPU=1; fi

    # Incremental prefix strings avoid multibyte substring arithmetic later.
    PRE_BLOCK=("") PRE_DASH=("") PRE_SPACE=("")
    local i
    for ((i = 1; i <= W; i++)); do
        PRE_BLOCK[i]="${PRE_BLOCK[i - 1]}█"
        PRE_DASH[i]="${PRE_DASH[i - 1]}─"
        PRE_SPACE[i]="${PRE_SPACE[i - 1]} "
    done
    RULE_FULL="${PRE_DASH[W]}"
}

# --- Frame assembly ---------------------------------------------------------
# The frame is built as one string and flushed with a single write, so the panel
# never tears or flickers mid-repaint.

FRAME=""
L() { FRAME+="  ${1-}"$'\033[K\n'; }

# Keeps exactly `max` samples so a graph spans the full panel from the first
# frame and stays full after a resize, scrolling right to left.
push() {
    local -n _hist=$1
    local max=$3
    _hist+=("$2")
    while ((${#_hist[@]} < max)); do _hist=(0 "${_hist[@]}"); done
    ((${#_hist[@]} > max)) && _hist=("${_hist[@]: -max}")
}

rule() {
    local label="${1-}" used
    if [[ -z $label ]]; then
        L "${E_RULE}${RULE_FULL}${RS}"
        return
    fi
    used=$((${#label} + 6))
    ((used > W)) && used=$W
    L "${E_RULE}──┤${RS}${E_LABEL} ${label} ${RS}${E_RULE}├${PRE_DASH[W - used]}${RS}"
}

gauge() {
    local pct=$1 width=$2 warn=${3:-60} crit=${4:-85} e fill
    ((pct < 0)) && pct=0
    ((pct > 100)) && pct=100
    ((width < 1)) && width=1
    ((width > W)) && width=W
    if   ((pct >= crit)); then e=$E_HIGH
    elif ((pct >= warn)); then e=$E_MID
    else                       e=$E_LOW; fi
    fill=$((pct * width / 100))
    printf '%s' "${E_TRACK}▏${e}${PRE_BLOCK[fill]}${E_TRACK}${PRE_DASH[width - fill]}▕${RS}"
}

# Column chart at eighths resolution; only emits an escape when the color changes.
graph() {
    local -n _data=$1
    local height=$2 warn=${3:-60} crit=${4:-85}
    local n=${#_data[@]} row col v level cell out prev e ch pad
    ((n == 0)) && return
    pad=$((W - n))
    ((pad < 0)) && pad=0
    for ((row = height - 1; row >= 0; row--)); do
        out="${PRE_SPACE[pad]}"
        prev=""
        for ((col = 0; col < n; col++)); do
            v=${_data[col]}
            level=$((v * height * 8 / 100))
            cell=$((level - row * 8))
            if ((cell <= 0)); then
                e=$E_TRACK
                ch="·"
            else
                ((cell > 8)) && cell=8
                if   ((v >= crit)); then e=$E_HIGH
                elif ((v >= warn)); then e=$E_MID
                else                     e=$E_LOW; fi
                ch=${SPARK[cell - 1]}
            fi
            if [[ $e != "$prev" ]]; then
                out+=$e
                prev=$e
            fi
            out+=$ch
        done
        L "${out}${RS}"
    done
}

metric_row() {
    local label=$1 pct=$2 right=$3 warn=${4:-60} crit=${5:-85}
    L "${E_ACCENT}${BD}${label}${RS} $(gauge "$pct" "$GW" "$warn" "$crit") ${E_VALUE}$(printf '%3d%%' "$pct")${RS} ${E_LABEL}${right}${RS}"
}

temp_e() {
    local t=$1 warn=$2 crit=$3
    if   ((t < 0));     then printf '%s' "$E_TRACK"
    elif ((t >= crit)); then printf '%s' "$E_HIGH"
    elif ((t >= warn)); then printf '%s' "$E_MID"
    else                     printf '%s' "$E_LOW"; fi
}

draw() {
    FRAME=""
    L "${E_ACCENT}✠${RS} ${E_TITLE}${BD}TELEMETRIA  IMPERII${RS} ${E_ACCENT}✠${RS}"
    rule
    L ""

    metric_row "CPU" "${cpu_pct[0]}" "$(fmt_temp "$t_cpu")C" 65 88
    graph cpu_hist "$GRAPH_CPU" 65 88

    local ncores=$((${#cpu_pct[@]} - 1)) i v e prev="" out=""
    for ((i = 1; i <= ncores; i++)); do
        v=${cpu_pct[i]:-0}
        if   ((v >= 88)); then e=$E_HIGH
        elif ((v >= 65)); then e=$E_MID
        else                   e=$E_LOW; fi
        ((v < 4)) && e=$E_TRACK
        if [[ $e != "$prev" ]]; then
            out+=$e
            prev=$e
        fi
        if ((v < 4)); then out+="·"; else out+=${SPARK[v * 7 / 100]}; fi
    done
    L "${E_MUTED}cores${RS} ${out}${RS} ${E_MUTED}${ncores}t${RS}"
    L ""

    metric_row "RAM" "$mem_pct" "$(fmt_kib $mem_used)/$(fmt_kib $mem_total)" 70 90
    graph mem_hist "$GRAPH_MEM" 70 90
    L ""

    if ((gpu_util >= 0)); then
        metric_row "GPU" "$gpu_util" "$(fmt_temp "$gpu_temp")C" 70 88
        graph gpu_hist "$GRAPH_GPU" 70 88
        L "${E_MUTED}      ${gpu_name} · vram ${gpu_mem_used}/${gpu_mem_total}M${RS}"
        L ""
    fi

    rule "THERMAE"
    L "${E_MUTED}cpu${RS} $(temp_e "$t_cpu" 70 88)$(fmt_temp "$t_cpu")${RS}  \
${E_MUTED}gpu${RS} $(temp_e "$gpu_temp" 70 88)$(fmt_temp "$gpu_temp")${RS}  \
${E_MUTED}ssd${RS} $(temp_e "$t_ssd" 60 75)$(fmt_temp "$t_ssd")${RS}  \
${E_MUTED}net${RS} $(temp_e "$t_net" 60 75)$(fmt_temp "$t_net")${RS}"
    L ""

    rule "SYSTEMA"
    L "${E_ACCENT}DISK${RS} $(gauge "$disk_pct" "$GW" 80 92) ${E_VALUE}$(printf '%3d%%' "$disk_pct")${RS} ${E_MUTED}${disk_free} libre${RS}"
    L "${E_ACCENT}NET ${RS} ${E_DOWN}↓${RS} ${E_VALUE}$(printf '%-11s' "$(fmt_rate $net_rx_rate)")${RS} ${E_UP}↑${RS} ${E_VALUE}$(fmt_rate $net_tx_rate)${RS}"

    local load up_s up_h up_m
    read -r load _ <<<"$(</proc/loadavg)"
    read -r up_s _ <<<"$(</proc/uptime)"
    up_s=${up_s%.*}
    up_h=$((up_s / 3600))
    up_m=$(((up_s % 3600) / 60))
    L "${E_ACCENT}LOAD${RS} ${E_VALUE}${load}${RS} ${E_MUTED}· swap ${swap_pct}% · up ${up_h}h ${up_m}m${RS}"

    if ((bat_pct >= 0)); then
        local bicon="󱐋"
        [[ $bat_status == Discharging ]] && bicon="󰁽"
        L "${E_ACCENT}PWR ${RS} $(gauge "$bat_pct" "$GW" 101 101) ${E_VALUE}$(printf '%3d%%' "$bat_pct")${RS} ${E_MUTED}${bicon} ${bat_status,,}${RS}"
    fi

    printf '\033[H%s\033[J' "$FRAME"
}

# --- Main -------------------------------------------------------------------

declare -a cpu_hist=() mem_hist=() gpu_hist=()

measure
discover_temps
start_gpu_feed
sample_cpu
sample_net

printf '\033[?25l'
trap 'measure; printf "\033[2J"' WINCH

while :; do
    sample_cpu
    sample_mem
    sample_net
    sample_temps
    sample_gpu
    sample_disk
    sample_battery

    push cpu_hist "${cpu_pct[0]}" "$W"
    push mem_hist "$mem_pct" "$W"
    ((gpu_util >= 0)) && push gpu_hist "$gpu_util" "$W"

    draw
    sleep "$INTERVAL"
done
