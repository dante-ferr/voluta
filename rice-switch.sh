#!/usr/bin/env bash
# rice-switch.sh - Toggle between system dotfiles rices (default vs imperium)

set -e

RICE="${1:-toggle}"

# This script lives in the imperium rice; resolve it so clones outside
# ~/imperivm-dotfiles still switch correctly.
IMPERIUM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_DIR="${IMPERIUM_DEFAULT_DIR:-$HOME/dotfiles}"
DEPS_FILE="$IMPERIUM_DIR/deps/arch.txt"
FLOORP_FLATPAK="one.ablaze.floorp"

CURRENT_TARGET=$(readlink -f "$HOME/.config/hypr" 2>/dev/null || true)

if [[ "$RICE" == "toggle" ]]; then
    if [[ "$CURRENT_TARGET" == "$IMPERIUM_DIR/hypr" || "$CURRENT_TARGET" == *"/imperivm-dotfiles/"* ]]; then
        RICE="default"
    else
        RICE="imperium"
    fi
fi

if [[ "$RICE" == "imperium" ]]; then
    TARGET_DIR="$IMPERIUM_DIR"
    echo "⚡ Switching to Imperium Cyber-Sacred rice..."
elif [[ "$RICE" == "default" || "$RICE" == "main" ]]; then
    TARGET_DIR="$DEFAULT_DIR"
    echo "🔄 Switching to Default rice..."
else
    echo "Usage: $0 [imperium | default | toggle]"
    exit 1
fi

# --- Imperium dependency bootstrap ------------------------------------------

pkg_installed() {
    pacman -Q "$1" >/dev/null 2>&1
}

collect_missing_pkgs() {
    local line pkg alts installed chosen
    MISSING_PKGS=()
    [[ -r "$DEPS_FILE" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" ]] && continue
        installed=0
        chosen=""
        IFS='|' read -r -a alts <<<"$line"
        for pkg in "${alts[@]}"; do
            pkg="${pkg#"${pkg%%[![:space:]]*}"}"
            pkg="${pkg%"${pkg##*[![:space:]]}"}"
            [[ -z "$pkg" ]] && continue
            [[ -z "$chosen" ]] && chosen=$pkg
            if pkg_installed "$pkg"; then
                installed=1
                break
            fi
        done
        if ((installed == 0)) && [[ -n "$chosen" ]]; then
            MISSING_PKGS+=("$chosen")
        fi
    done <"$DEPS_FILE"
}

floorp_present() {
    command -v floorp >/dev/null 2>&1 && return 0
    command -v flatpak >/dev/null 2>&1 && flatpak info "$FLOORP_FLATPAK" >/dev/null 2>&1
}

ensure_imperium_deps() {
    local missing_pkgs=() need_floorp=0 installer

    collect_missing_pkgs
    missing_pkgs=("${MISSING_PKGS[@]+"${MISSING_PKGS[@]}"}")

    if ! floorp_present; then
        need_floorp=1
    fi

    if ((${#missing_pkgs[@]} == 0)) && ((need_floorp == 0)); then
        echo "📦 Imperium dependencies already satisfied."
        return 0
    fi

    if ((${#missing_pkgs[@]} > 0)); then
        echo "📦 Missing packages: ${missing_pkgs[*]}"
        if ! command -v paru >/dev/null 2>&1; then
            echo "⚠️  paru not found; skipping package install. Install manually: ${missing_pkgs[*]}"
            notify-send "Imperium Rice" "paru missing; install: ${missing_pkgs[*]}" 2>/dev/null || true
        else
            installer=$(mktemp /tmp/imperium-deps-XXXXXX.sh)
            {
                echo '#!/usr/bin/env bash'
                echo 'set -e'
                echo 'echo "Installing Imperium packages with paru..."'
                printf 'paru -S --needed --noconfirm'
                printf ' %q' "${missing_pkgs[@]}"
                echo
                echo 'echo'
                echo 'echo "Done. Press Enter to close."'
                echo 'read -r'
            } >"$installer"
            chmod +x "$installer"
            if command -v kitty >/dev/null 2>&1; then
                kitty --class imperium-deps --title "Imperium deps" -e bash "$installer" || true
            else
                bash "$installer" || true
            fi
            rm -f "$installer"
        fi
    fi

    if ((need_floorp)); then
        echo "📦 Floorp not found; installing Flatpak $FLOORP_FLATPAK..."
        if ! command -v flatpak >/dev/null 2>&1; then
            echo "⚠️  flatpak not found; install Floorp manually (Flatpak: $FLOORP_FLATPAK)."
            notify-send "Imperium Rice" "flatpak missing; install Floorp ($FLOORP_FLATPAK)" 2>/dev/null || true
        else
            installer=$(mktemp /tmp/imperium-floorp-XXXXXX.sh)
            {
                echo '#!/usr/bin/env bash'
                echo 'set -e'
                echo 'flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo'
                echo "flatpak install -y flathub $FLOORP_FLATPAK"
                echo 'echo'
                echo 'echo "Done. Press Enter to close."'
                echo 'read -r'
            } >"$installer"
            chmod +x "$installer"
            if command -v kitty >/dev/null 2>&1; then
                kitty --class imperium-deps --title "Imperium Floorp" -e bash "$installer" || true
            else
                bash "$installer" || true
            fi
            rm -f "$installer"
        fi
    fi
}

if [[ "$RICE" == "imperium" ]]; then
    ensure_imperium_deps
fi

# --- Config linking ---------------------------------------------------------

link_config() {
    local name="$1"
    local src="$TARGET_DIR/$name"
    local dest="$HOME/.config/$name"

    if [[ -d "$src" || -f "$src" ]]; then
        if [[ -L "$dest" || -e "$dest" ]]; then
            rm -rf "$dest"
        fi
        ln -s "$src" "$dest"
        echo "  Linked ~/.config/$name -> $src"
    fi
}

# Same treatment for dotfiles that live in $HOME rather than ~/.config. The
# shell rc is the one that matters here: left unlinked, a git pull on another
# machine never reaches its shell, so fetch fixes like the fastfetch migration
# silently fail to propagate.
link_home() {
    local name="$1"
    local src="$TARGET_DIR/$name"
    local dest="$HOME/.$name"

    if [[ -f "$src" ]]; then
        if [[ -L "$dest" || -e "$dest" ]]; then
            rm -rf "$dest"
        fi
        ln -s "$src" "$dest"
        echo "  Linked ~/.$name -> $src"
    fi
}

mkdir -p "$HOME/.config"

link_config "hypr"
link_config "waybar"
link_config "kitty"
link_config "rofi"
link_config "wallust"
link_config "fastfetch"
link_config "swaync"
link_config "waypaper"
link_config "wlogout"
link_config "starship.toml"

link_home "zshrc"

# SDDM lives under /usr/share; apply the Imperium greeter when we can.
if [[ "$RICE" == "imperium" && -x "$TARGET_DIR/sddm/install.sh" ]]; then
    if [[ -w /usr/share/sddm/themes ]]; then
        echo "🏛️  Installing Imperium SDDM theme..."
        "$TARGET_DIR/sddm/install.sh" || true
    else
        echo "🏛️  SDDM login theme: run  sudo $TARGET_DIR/sddm/install.sh  once, as root."
    fi
fi

# Trigger wallpaper/wallust refresh and components reload
if [[ -f "$HOME/.config/hypr/UserScripts/combined_wallust.sh" ]]; then
    echo "🎨 Refreshing Wallust colors and desktop components..."
    bash "$HOME/.config/hypr/UserScripts/combined_wallust.sh"
elif command -v wallust >/dev/null 2>&1; then
    waypaper_conf="$HOME/.config/waypaper/config.ini"
    if [[ -f "$waypaper_conf" ]]; then
        wallpaper=$(grep -E '^\s*wallpaper\s*=' "$waypaper_conf" | head -n 1 | cut -d '=' -f 2- | sed 's/^[ \t]*//' | sed "s|^~|$HOME|")
        if [[ -n "$wallpaper" && -f "$wallpaper" ]]; then
            wallust run "$wallpaper"
        fi
    fi
    hyprctl reload >/dev/null 2>&1 || true
    pkill -x waybar || true
    sleep 0.2
    waybar >/dev/null 2>&1 &
fi

echo "✅ Switched to '$RICE' rice successfully!"
