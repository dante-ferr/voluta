# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH

export ZSH="$HOME/.oh-my-zsh"

# ZSH_THEME="agnosterzak"

plugins=(
    git
    archlinux
    zsh-autosuggestions
    zsh-syntax-highlighting
)

source $ZSH/oh-my-zsh.sh

# Check archlinux plugin commands here
# https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/archlinux

# Pokemon fetch: cool closed-border box, side-by-side or stacked by sprite height
_pokefetch() {
    # Collect system info
    local title os_v kern up wm_v sh_v cpu_v gpu_v ram_v
    title="${USER}@${HOST%%.*}"
    os_v=$(sed -n 's/^PRETTY_NAME="\(.*\)"/\1/p' /etc/os-release 2>/dev/null)
    kern=$(uname -r)
    up=$(uptime -p 2>/dev/null | sed 's/up //;s/ hours\?/h/g;s/ minutes\?/m/g;s/, / /g')
    wm_v="${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-?}}"
    sh_v="${SHELL##*/}"
    cpu_v=$(sed -n 's/^model name[[:space:]]*: //p' /proc/cpuinfo 2>/dev/null | head -1 \
            | sed 's/(R)//g;s/(TM)//g;s/  */ /g')
    gpu_v=$(lspci 2>/dev/null | grep -iE 'VGA|3D' | grep -iv intel \
            | sed 's/.*\[//;s/\].*//' | head -1)
    ram_v=$(free -h --si 2>/dev/null | awk '/Mem:/ {print $3 " / " $2}')
    [[ -z "$gpu_v" ]] && gpu_v="N/A"
    [[ -z "$up"    ]] && up="?"

    typeset -a lbls=(os kernel uptime wm shell cpu gpu ram)
    typeset -a vals=("$os_v" "$kern" "$up" "$wm_v" "$sh_v" "$cpu_v" "$gpu_v" "$ram_v")

    # Compute box width from longest value
    local max_v=0 v
    for v in "${vals[@]}"; do (( ${#v} > max_v )) && max_v=${#v}; done
    # inner = space(1) + key(8) + space(1) + val(max_v) + space(1) = max_v + 11
    local inner=$(( max_v + 11 ))
    # Ensure title "⚡  <title>" fits (needs inner - 5 chars for title)
    (( ${#title} > inner - 5 )) && inner=$(( ${#title} + 5 ))
    local val_w=$(( inner - 11 ))
    local sw_pad=$(( inner - 17 ))   # padding after 8 color circles (15 visible chars)
    local div; div=$(printf '═%.0s' $(seq 1 $inner))

    # ANSI colors
    local nc=$'\e[0m' bold=$'\e[1m'
    local r=$'\e[31m' g=$'\e[32m' y=$'\e[33m' b=$'\e[34m' m=$'\e[35m' c=$'\e[36m' w=$'\e[37m'
    typeset -a kc=("$y" "$c" "$m" "$b" "$g" "$r" "$c" "$m")

    # Get sprite
    local tmp_spr; tmp_spr=$(mktemp /tmp/pokefetch_spr.XXXXXX)
    pokemon-colorscripts --no-title -s -r > "$tmp_spr"
    local height; height=$(wc -l < "$tmp_spr")

    # Draw closed box to temp file
    local tmp_box; tmp_box=$(mktemp /tmp/pokefetch_box.XXXXXX)
    {
        echo "╔${div}╗"
        printf "║ ${bold}⚡  %-$((inner - 5))s${nc} ║\n" "$title"
        echo "╠${div}╣"
        local i
        for (( i = 1; i <= ${#lbls[@]}; i++ )); do
            printf "║ ${kc[$i]}%-8s${nc} %-${val_w}s ║\n" "${lbls[$i]}" "${vals[$i]}"
        done
        echo "╠${div}╣"
        printf "║ ${r}●${nc} ${g}●${nc} ${y}●${nc} ${b}●${nc} ${m}●${nc} ${c}●${nc} ${w}●${nc} ${bold}●${nc}%${sw_pad}s ║\n" ""
        echo "╚${div}╝"
    } > "$tmp_box"

    # Side-by-side (small sprite) or stacked (large sprite)
    if (( height <= 14 )); then
        python3 - "$tmp_spr" "$tmp_box" << 'PYEOF'
import sys, re

def vis_len(s):
    return len(re.sub(r'\x1b\[[0-9;]*[A-Za-z]', '', s))

with open(sys.argv[1]) as f:
    left = f.read().splitlines()
with open(sys.argv[2]) as f:
    right = f.read().splitlines()

w = max((vis_len(l) for l in left), default=0)
n = max(len(left), len(right))
for i in range(n):
    la = left[i] if i < len(left) else ''
    lb = right[i] if i < len(right) else ''
    print(la + ' ' * (w - vis_len(la) + 2) + lb)
PYEOF
    else
        cat "$tmp_spr"
        echo ""
        cat "$tmp_box"
    fi

    rm -f "$tmp_spr" "$tmp_box"
}
# Startup decorations, plus a way to wipe only them on resize.
# The banner draws its logo with the kitty graphics protocol, and those images
# are pinned to the cells they were placed on: they do not reflow with the text
# when the window changes size, so a resize leaves the banner mangled. While the
# screen still holds nothing but the banner we can tell it apart from real work,
# so that is the window in which we are allowed to remove it.
autoload -U add-zsh-hook

typeset -gi _IMPERIUM_BANNER_ONSCREEN=0
# Geometry the banner was painted at, and the last geometry a resize reported.
# The first says whether the banner is stale at all, the second tells a real
# resize apart from a SIGWINCH that did not change anything.
typeset -gi _IMPERIUM_BANNER_COLS=0 _IMPERIUM_BANNER_LINES=0
typeset -gi _IMPERIUM_SEEN_COLS=0 _IMPERIUM_SEEN_LINES=0
# How many rows the banner occupies, measured once from the cursor position the
# moment it finishes drawing. Knowing this lets the first command delete exactly
# those rows instead of clearing the screen out from under the prompt.
typeset -gi _IMPERIUM_BANNER_ROWS=0

# Safe to ask the terminal where the cursor is only while zle is not reading, so
# this is called from banner draw time and nowhere else.
_imperium_cursor_row() {
    local answer
    print -n $'\e[6n' > /dev/tty
    # A local terminal answers in about a millisecond. The wait is kept short
    # because anything typed during it gets read here instead of by the prompt.
    read -rs -d 'R' -t 0.15 answer < /dev/tty || return 1
    answer=${answer##*$'\e['}
    answer=${answer%%;*}
    [[ $answer == <-> ]] || return 1
    print -r -- $answer
}

_imperium_draw_banner() {
    if [[ -f "$HOME/.config/fastfetch/config.jsonc" ]]; then
        if [[ -x "$HOME/.config/fastfetch/fetch.sh" ]]; then
            "$HOME/.config/fastfetch/fetch.sh"
        else
            fastfetch --config "$HOME/.config/fastfetch/config.jsonc"
        fi
    elif command -v fastfetch >/dev/null 2>&1; then
        fastfetch
    else
        _pokefetch
    fi
    _IMPERIUM_BANNER_ONSCREEN=1
    local row
    if row=$(_imperium_cursor_row); then
        _IMPERIUM_BANNER_ROWS=$(( row - 1 ))
    else
        _IMPERIUM_BANNER_ROWS=0
    fi
    _IMPERIUM_BANNER_COLS=$COLUMNS
    _IMPERIUM_BANNER_LINES=$LINES
    _IMPERIUM_SEEN_COLS=$COLUMNS
    _IMPERIUM_SEEN_LINES=$LINES
}

# Drop the kitty image placements and the scrollback the banner owns. The caller
# repaints, since only it knows whether zle is around to do it.
_imperium_banner_erase() {
    print -n '\e_Ga=d,d=A\e\\\e[3J'
}

# Cut the banner's rows out of the top of the screen, leaving whatever sits
# below them, prompt and typed command included, exactly where it is. Everything
# under the deleted block slides up, so the cursor has to come up by as much.
_imperium_banner_lift() {
    _IMPERIUM_BANNER_ONSCREEN=0
    _imperium_banner_erase
    local -i n=$_IMPERIUM_BANNER_ROWS
    # A banner taller than the screen has already scrolled, so its top rows are
    # no longer the rows we measured. Nothing left to be surgical about.
    if (( n > 0 && n + 4 <= LINES )); then
        print -n "\e7\e[H\e[${n}M\e8\e[${n}A"
    else
        print -n '\e[H\e[2J'
    fi
}

# The first command takes the banner with it. Letting it outlive that is what
# stranded it above real output, where a later resize could no longer safely
# clear it. cleanfetch is exempt: it does the removal itself.
_imperium_banner_on_command() {
    [[ ${1%% *} == cleanfetch ]] && return 0
    (( _IMPERIUM_BANNER_ONSCREEN )) || return 0
    _imperium_banner_lift
}
add-zsh-hook preexec _imperium_banner_on_command

TRAPWINCH() {
    [[ ${IMPERIUM_WIPE_BANNER_ON_RESIZE:-1} == 1 ]] || return 0
    (( _IMPERIUM_BANNER_ONSCREEN )) || return 0
    # Any real change in geometry counts, however soon after startup it lands. A
    # delay here only made this fire sometimes: a tiling layout settles within
    # moments of the window opening, so the resize that actually mangles the
    # banner is usually the very first one.
    (( COLUMNS == _IMPERIUM_SEEN_COLS && LINES == _IMPERIUM_SEEN_LINES )) && return 0
    _IMPERIUM_SEEN_COLS=$COLUMNS
    _IMPERIUM_SEEN_LINES=$LINES
    # No line editor means nothing can repaint the prompt, so hold the claim and
    # let the precmd below finish the job rather than half wiping and latching off.
    zle || return 0
    _IMPERIUM_BANNER_ONSCREEN=0
    _imperium_banner_erase
    zle clear-screen
}

# Catches a resize that landed while zle was not up, such as during startup
# before the first prompt. precmd runs before the prompt is drawn, so clearing
# here simply lands the prompt at the top.
_imperium_banner_catchup() {
    (( _IMPERIUM_BANNER_ONSCREEN )) || return 0
    (( COLUMNS == _IMPERIUM_BANNER_COLS && LINES == _IMPERIUM_BANNER_LINES )) && return 0
    [[ ${IMPERIUM_WIPE_BANNER_ON_RESIZE:-1} == 1 ]] || return 0
    _IMPERIUM_BANNER_ONSCREEN=0
    _imperium_banner_erase
    print -n '\e[H\e[2J'
}
add-zsh-hook precmd _imperium_banner_catchup

# For clearing the banner on its own, when you have neither resized nor got
# anything else to run.
cleanfetch() {
    if (( _IMPERIUM_BANNER_ONSCREEN )); then
        _imperium_banner_lift
    else
        print -n '\e_Ga=d,d=A\e\\'
        print -u2 -- "cleanfetch: banner no longer isolated; removed stray images only"
    fi
}

_imperium_draw_banner

# Set-up icons for files/directories in terminal using lsd
alias ls='lsd'
alias l='ls -l'
alias la='ls -a'
alias lla='ls -la'
alias lt='ls --tree'

# Set-up FZF key bindings (CTRL R for fuzzy history finder)
source <(fzf --zsh)

HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt appendhistory

export PATH="$HOME/.cargo/bin:$PATH"

# Count lines of code excluding junk
count_loc() {
	(git submodule foreach --quiet 'echo "$path: $(git ls-files -- "*.py" | xargs -r cat | wc -l)"' && echo "Total: $(git ls-files --recurse-submodules -- "*.py" | xargs -r cat | wc -l)")
}

count_loc_clean() {
	(git submodule foreach --quiet 'echo "$path: $(git ls-files -- "*.py" | xargs -r cat | grep -cve "^\s*#\|^\s*$")"' && echo "Total: $(git ls-files --recurse-submodules -- "*.py" | xargs -r cat | grep -cve "^\s*#\|^\s*$")")
}

eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv zsh)"

eval "$(starship init zsh)"
# opencode
export PATH=/home/dante/.opencode/bin:$PATH

# >>> conda initialize >>>
if [ -f "/home/dante/miniconda3/etc/profile.d/conda.sh" ]; then
    . "/home/dante/miniconda3/etc/profile.d/conda.sh"
else
    export PATH="/home/dante/miniconda3/bin:$PATH"
fi
# <<< conda initialize <<<

# Auto-activate conda environments
autoload -U add-zsh-hook

load-conda-env() {
    if [[ -f environment.yml ]]; then
        local env_name=$(grep -m 1 '^name:' environment.yml | awk '{print $2}')
        
        if [[ -n "$env_name" && "$CONDA_DEFAULT_ENV" != "$env_name" ]]; then
            conda activate "$env_name"
        fi
    # Deactivate only if we leave a project directory and are not in 'base'
    elif [[ -n "$CONDA_DEFAULT_ENV" && "$CONDA_DEFAULT_ENV" != "base" && ! -f environment.yml ]]; then
        conda deactivate
    fi
}

add-zsh-hook chpwd load-conda-env
# Run once on startup in case you start terminal already in a project folder
load-conda-env

# Force VA-API for hardware video decoding
export MOZ_DISABLE_RDD_SANDBOX=1
export LIBVA_DRIVER_NAME=nvidia # Change to 'i915' for Intel or 'radeonsi' for AMD

# Force Wayland usage (if applicable)
export MOZ_ENABLE_WAYLAND=1


# Added by Antigravity CLI installer
export PATH="/home/dante/.local/bin:$PATH"

alias fix-blue="bluetoothctl remove 99:2A:36:72:03:D6 && echo 'Coloque o fone no modo de pareamento agora...' && sleep 3 && timeout 7 bluetoothctl scan on >/dev/null 2>&1; bluetoothctl pair 99:2A:36:72:03:D6 && bluetoothctl trust 99:2A:36:72:03:D6 && bluetoothctl connect 99:2A:36:72:03:D6"

export ANDROID_HOME=$HOME/Android/Sdk
export PATH=$PATH:$ANDROID_HOME/emulator
export PATH=$PATH:$ANDROID_HOME/platform-tools

