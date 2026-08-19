#!/usr/bin/env bash
# rice_paths.sh - Locate this clone's asset dirs from the real hypr path.
#
# ~/.config/hypr is a symlink into the rice after rice-switch. Following it
# finds fastfetch/waybar next to hypr even when the clone is not at
# ~/imperivm-dotfiles and even when those other configs were never linked.

imperium_rice_root() {
    local here hypr
    # This file lives at hypr/UserScripts/lib/rice_paths.sh: three parents up
    # is the clone root, which is the most reliable answer when the script
    # is sourced from inside the rice itself.
    here=$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || true)" 2>/dev/null || true)
    if [[ -n $here && -d $here/../../../fastfetch/assets ]]; then
        (cd "$here/../../.." && pwd)
        return 0
    fi
    hypr=$(readlink -f "${HOME}/.config/hypr" 2>/dev/null || true)
    if [[ -n $hypr && -d $hypr ]]; then
        printf '%s\n' "$(dirname "$hypr")"
        return 0
    fi
    return 1
}

imperium_fastfetch_assets() {
    local root dir
    if root=$(imperium_rice_root); then
        dir="${root}/fastfetch/assets"
        if [[ -d $dir ]]; then
            printf '%s\n' "$dir"
            return 0
        fi
    fi
    dir=$(readlink -f "${HOME}/.config/fastfetch" 2>/dev/null || true)
    if [[ -n $dir && -d ${dir}/assets ]]; then
        printf '%s\n' "${dir}/assets"
        return 0
    fi
    printf '%s\n' "${HOME}/.config/fastfetch/assets"
}

imperium_waybar_dir() {
    local root dir
    if root=$(imperium_rice_root); then
        dir="${root}/waybar"
        if [[ -d $dir ]]; then
            printf '%s\n' "$dir"
            return 0
        fi
    fi
    dir=$(readlink -f "${HOME}/.config/waybar" 2>/dev/null || true)
    if [[ -n $dir && -d $dir ]]; then
        printf '%s\n' "$dir"
        return 0
    fi
    printf '%s\n' "${HOME}/.config/waybar"
}
