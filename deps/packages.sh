#!/usr/bin/env bash
# Shared Arch dependency bootstrap. Sourcing this file performs no installs.

pkg_installed() {
    pacman -Q "$1" >/dev/null 2>&1 && return 0
    [[ -x "/usr/bin/$1" ]]
}

append_missing_pkgs() {
    local manifest=$1 depth=${2:-0} line pkg chosen installed
    local -a alts
    if [[ ! -r "$manifest" || $depth -gt 8 ]]; then
        echo "Cannot read dependency manifest (or include nesting is too deep): $manifest" >&2
        return 1
    fi
    while IFS= read -r line || [[ -n "$line" ]]; do
        line=${line%%#*}
        line=${line#"${line%%[![:space:]]*}"}
        line=${line%"${line##*[![:space:]]}"}
        [[ -z "$line" ]] && continue
        if [[ "$line" == '@include '* ]]; then
            append_missing_pkgs "$(dirname -- "$manifest")/${line#@include }" "$((depth + 1))" || return 1
            continue
        fi
        installed=0
        chosen=''
        IFS='|' read -r -a alts <<<"$line"
        for pkg in "${alts[@]}"; do
            pkg=${pkg#"${pkg%%[![:space:]]*}"}
            pkg=${pkg%"${pkg##*[![:space:]]}"}
            [[ -z "$pkg" ]] && continue
            [[ -z "$chosen" ]] && chosen=$pkg
            if pkg_installed "$pkg"; then
                installed=1
                break
            fi
        done
        if ((installed == 0)) && [[ -n "$chosen" ]]; then
            # Without an AUR helper, prefer an available repository alternative
            # (e.g. wallust instead of wallust-git).
            if ! command -v paru >/dev/null 2>&1; then
                for pkg in "${alts[@]}"; do
                    pkg=${pkg#"${pkg%%[![:space:]]*}"}
                    pkg=${pkg%"${pkg##*[![:space:]]}"}
                    if pacman -Si "$pkg" >/dev/null 2>&1; then
                        chosen=$pkg
                        break
                    fi
                done
            fi
            MISSING_PKGS+=("$chosen")
        fi
    done <"$manifest"
}

collect_missing_pkgs() {
    MISSING_PKGS=()
    append_missing_pkgs "$1"
}

ensure_arch_packages() (
    set -o pipefail
    local manifest=$1 label=${2:-Imperium} installer log pkg status=0
    local -a install_command
    collect_missing_pkgs "$manifest" || return 1
    if ((${#MISSING_PKGS[@]} == 0)); then
        echo "$label dependencies already installed."
        return 0
    fi
    echo "$label missing packages: ${MISSING_PKGS[*]}"
    if command -v paru >/dev/null 2>&1; then
        install_command=(paru -S --needed --noconfirm)
    elif ((EUID == 0)); then
        install_command=(pacman -S --needed --noconfirm)
    elif command -v sudo >/dev/null 2>&1; then
        install_command=(sudo pacman -S --needed --noconfirm)
    else
        echo 'Cannot install packages: paru or sudo is required.' >&2
        return 1
    fi

    installer=$(mktemp /tmp/imperium-deps-XXXXXX.sh) || return 1
    log=$(mktemp /tmp/imperium-deps-XXXXXX.log) || { rm -f "$installer"; return 1; }
    {
        printf '#!/usr/bin/env bash\nset -o pipefail\nlog=$1\nfail=0\n'
        # Preserve the existing one-package-per-transaction behavior so one
        # conflicting package does not prevent installing the remaining ones.
        for pkg in "${MISSING_PKGS[@]}"; do
            printf 'echo %q | tee -a "$log"\n' "Installing $pkg..."
            printf 'if ! '
            printf '%q ' "${install_command[@]}" "$pkg"
            printf '2>&1 | tee -a "$log"; then fail=1; fi\n'
        done
        printf 'exit "$fail"\n'
    } >"$installer"

    # Refresh can run from a keybind with no terminal for the password prompt.
    if [[ ! -t 0 ]] && [[ -n ${WAYLAND_DISPLAY:-}${DISPLAY:-} ]] && command -v kitty >/dev/null 2>&1; then
        kitty --class imperium-deps --title "$label dependencies" -e bash "$installer" "$log" || status=$?
    else
        bash "$installer" "$log" || status=$?
    fi
    rm -f "$installer"
    collect_missing_pkgs "$manifest" || status=1
    if ((status != 0 || ${#MISSING_PKGS[@]} > 0)); then
        echo "$label dependency installation failed. Still missing: ${MISSING_PKGS[*]:-none}. Log: $log" >&2
        notify-send "$label dependency installation failed" "See $log" 2>/dev/null || true
        return 1
    fi
    rm -f "$log"
)
