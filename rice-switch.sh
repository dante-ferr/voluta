#!/usr/bin/env bash
# rice-switch.sh - Toggle between ~/dotfiles and this Imperium rice.
# JaKooLit's Hyprland-Dots is a separate tree and is not a switch target.

set -e

RICE="${1:-toggle}"

# This script lives in the imperium rice. ~/rice-switch.sh is a symlink into
# the checkout. dirname of that symlink is $HOME, and a switch from there
# removes ~/.config/hypr and turns ~/.zshrc into a symlink to itself.
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || true)"
if [[ -z "$SCRIPT_PATH" || ! -f "$SCRIPT_PATH" ]]; then
    echo "Cannot resolve $(basename "${BASH_SOURCE[0]}"). Run the copy inside the rice checkout."
    exit 1
fi
IMPERIUM_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
if [[ -n "${IMPERIUM_DEFAULT_DIR:-}" ]]; then
    DEFAULT_DIR="$IMPERIUM_DEFAULT_DIR"
elif [[ -d "$HOME/dotfiles" ]]; then
    DEFAULT_DIR="$HOME/dotfiles"
else
    DEFAULT_DIR=""
fi
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
    if [[ -z "$DEFAULT_DIR" || ! -d "$DEFAULT_DIR" ]]; then
        echo "No default rice directory. Expected ~/dotfiles, or set IMPERIUM_DEFAULT_DIR."
        exit 1
    fi
    TARGET_DIR="$DEFAULT_DIR"
    echo "🔄 Switching to Default rice ($TARGET_DIR)..."
else
    echo "Usage: $0 [imperium | default | toggle]"
    exit 1
fi

if [[ "$(readlink -f "$TARGET_DIR")" == "$(readlink -f "$HOME")" ]]; then
    echo "Refusing to switch: rice directory resolved to \$HOME."
    exit 1
fi

# --- Imperium dependency bootstrap ------------------------------------------

pkg_installed() {
    pacman -Q "$1" >/dev/null 2>&1 && return 0
    # Some tools are already on disk without a pacman entry. Matching only
    # /usr/bin avoids the Imperium Dolphin wrapper in ~/.local/bin.
    [[ -x "/usr/bin/$1" ]]
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
            log=$(mktemp /tmp/imperium-deps-XXXXXX.log)
            {
                echo '#!/usr/bin/env bash'
                echo 'set -o pipefail'
                echo 'log=$1'
                echo 'fail=0'
                echo 'echo "Installing Imperium packages with paru..." | tee -a "$log"'
                # One package per transaction. A file conflict in one name
                # must not roll back the rest of the rice.
                for pkg in "${missing_pkgs[@]}"; do
                    printf 'echo ">> %q" | tee -a "$log"\n' "$pkg"
                    printf 'if ! paru -S --needed --noconfirm %q 2>&1 | tee -a "$log"; then\n' "$pkg"
                    echo '  fail=1'
                    echo 'fi'
                done
                echo 'if ((fail != 0)); then'
                echo '  echo "Install failed." | tee -a "$log"'
                echo '  exit 1'
                echo 'fi'
                echo 'echo "Packages installed." | tee -a "$log"'
            } >"$installer"
            chmod +x "$installer"
            # A graphical switch has no terminal for paru's password prompt.
            # The installer tees into the log, so a closed window still explains a failure.
            if command -v kitty >/dev/null 2>&1 && [[ -n ${WAYLAND_DISPLAY:-}${DISPLAY:-} ]]; then
                kitty --class imperium-deps --title "Imperium deps" -e bash "$installer" "$log" || true
            else
                bash "$installer" "$log" || true
            fi
            if [[ -s "$log" ]]; then
                cat "$log"
            fi
            rm -f "$installer" "$log"
            collect_missing_pkgs
            if ((${#MISSING_PKGS[@]} > 0)); then
                echo "⚠️  Still missing: ${MISSING_PKGS[*]}"
                notify-send "Imperium Rice" "Still missing: ${MISSING_PKGS[*]}" 2>/dev/null || true
            fi
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
    if [[ ! -e "$src" && -e "$TARGET_DIR/config/$name" ]]; then
        src="$TARGET_DIR/config/$name"
    fi
    local dest="$HOME/.config/$name"

    if [[ -d "$src" || -f "$src" ]]; then
        if [[ "$src" == "$dest" ]]; then
            echo "  Refusing to link ~/.config/$name onto itself"
            exit 1
        fi
        if [[ -L "$dest" || -e "$dest" ]]; then
            rm -rf "$dest"
        fi
        ln -s "$src" "$dest"
        echo "  Linked ~/.config/$name -> $src"
    elif [[ -L "$dest" ]]; then
        rm -f "$dest"
    fi
}

# Same treatment for dotfiles that live in $HOME rather than ~/.config. The
# shell rc is the one that matters here: left unlinked, a git pull on another
# machine never reaches its shell, so fetch fixes like the fastfetch migration
# silently fail to propagate.
link_home() {
    local name="$1"
    local src="$TARGET_DIR/$name"
    [[ -e "$src" ]] || src="$TARGET_DIR/.$name"
    [[ -e "$src" ]] || src="$TARGET_DIR/config/$name"
    local dest="$HOME/.$name"

    if [[ -f "$src" ]]; then
        if [[ "$src" == "$dest" ]]; then
            echo "  Refusing to link ~/.$name onto itself"
            exit 1
        fi
        if [[ -L "$dest" || -e "$dest" ]]; then
            rm -rf "$dest"
        fi
        ln -s "$src" "$dest"
        echo "  Linked ~/.$name -> $src"
    fi
}

link_home_file() {
    local name="$1"
    local src="${2:-$TARGET_DIR/$name}"
    local dest="$HOME/$name"

    if [[ -f "$src" ]]; then
        if [[ "$src" == "$dest" ]]; then
            echo "  Refusing to link ~/$name onto itself"
            exit 1
        fi
        ln -sfn "$src" "$dest"
        echo "  Linked ~/$name -> $src"
    fi
}

# Drop Imperium-only Dolphin links so the other rice does not keep this
# launcher, shortcut file, or desktop override.
drop_link_into() {
    local dest="$1"
    local root="$2"
    local target
    [[ -L "$dest" ]] || return 0
    target=$(readlink -f "$dest" 2>/dev/null || true)
    [[ "$target" == "$root/"* ]] || return 0
    rm -f "$dest"
    echo "  Removed $dest"
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
if [[ "$RICE" == "imperium" ]]; then
    python3 "$TARGET_DIR/dolphin/apply-config.py"
else
    link_config "dolphinrc"
fi

# Dolphin keeps custom shortcuts in kxmlgui, outside ~/.config.
if [[ -f "$TARGET_DIR/dolphin/dolphinui.rc" ]]; then
    kxml_dest="$HOME/.local/share/kxmlgui5/dolphin/dolphinui.rc"
    mkdir -p "$(dirname "$kxml_dest")"
    ln -sfn "$TARGET_DIR/dolphin/dolphinui.rc" "$kxml_dest"
    echo "  Linked $kxml_dest"
fi

# The wrapper loads the live palette hook. A user desktop file beats the
# system one, and DBus activation would skip Exec, so that flag stays off.
if [[ -x "$TARGET_DIR/dolphin/launch.sh" || -f "$TARGET_DIR/dolphin/launch.sh" ]]; then
    mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications"
    chmod +x "$TARGET_DIR/dolphin/launch.sh"
    ln -sfn "$TARGET_DIR/dolphin/launch.sh" "$HOME/.local/bin/dolphin"
    echo "  Linked $HOME/.local/bin/dolphin"
    if [[ "$RICE" == "imperium" ]]; then
        bash "$TARGET_DIR/dolphin/launch.sh" --prepare
    fi
    if [[ -f /usr/share/applications/org.kde.dolphin.desktop ]]; then
        desktop_dst="$HOME/.local/share/applications/org.kde.dolphin.desktop"
        sed -e "s|^Exec=dolphin |Exec=$HOME/.local/bin/dolphin |" \
            -e "s|^DBusActivatable=true|DBusActivatable=false|" \
            /usr/share/applications/org.kde.dolphin.desktop > "$desktop_dst"
        echo "  Wrote $desktop_dst"
    fi
fi

link_home "zshrc"
link_home "zprofile"
# Keep this clone's switcher on $HOME. ~/dotfiles ships an older copy that
# does not install Imperium packages.
link_home_file "rice-select.sh" "$IMPERIUM_DIR/rice-select.sh"
link_home_file "rice-switch.sh" "$IMPERIUM_DIR/rice-switch.sh"

if [[ "$RICE" != "imperium" ]]; then
    for service in org.freedesktop.FileManager1 org.kde.dolphin.FileManager1; do
        service_dst="${XDG_DATA_HOME:-$HOME/.local/share}/dbus-1/services/$service.service"
        if [[ -f "$service_dst" ]] && grep -q '^# Managed by Imperium SetDefaultFileManager.sh$' "$service_dst"; then
            rm -f "$service_dst"
        fi
    done
    drop_link_into "$HOME/.local/bin/dolphin" "$IMPERIUM_DIR"
    drop_link_into "$HOME/.local/share/kxmlgui5/dolphin/dolphinui.rc" "$IMPERIUM_DIR"
    desktop_dst="$HOME/.local/share/applications/org.kde.dolphin.desktop"
    if [[ -f "$desktop_dst" ]] && grep -q "$HOME/.local/bin/dolphin" "$desktop_dst"; then
        rm -f "$desktop_dst"
        echo "  Removed $desktop_dst"
    fi
fi

if [[ "$RICE" == "imperium" && -f /usr/share/applications/org.kde.dolphin.desktop ]]; then
    bash "$TARGET_DIR/hypr/scripts/SetDefaultFileManager.sh"
fi

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
    waybar_dir=$(readlink -f "${HOME}/.config/waybar" 2>/dev/null || true)
    shim="${waybar_dir}/lib/libwaybar_hyprland_shim.so"
    if [[ -f $shim ]]; then
        export LD_PRELOAD="$shim${LD_PRELOAD:+:$LD_PRELOAD}"
    fi
    waybar >/dev/null 2>&1 &
fi

echo "✅ Switched to '$RICE' rice successfully!"
