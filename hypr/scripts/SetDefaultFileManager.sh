#!/usr/bin/env bash
# Apply both folder defaults and the D-Bus API used by apps' “Show in folder”.
set -euo pipefail

script=$(readlink -f -- "${BASH_SOURCE[0]}")
root=$(cd -- "$(dirname -- "$script")/../.." && pwd)
config_dir=${XDG_CONFIG_HOME:-$HOME/.config}
data_dir=${XDG_DATA_HOME:-$HOME/.local/share}

if [[ ! -x /usr/bin/dolphin ]]; then
    echo "Dolphin is not installed; file-manager defaults were not changed." >&2
    exit 1
fi

mkdir -p "$config_dir" "$data_dir/dbus-1/services"
# Update only these associations, preserving the user's other app defaults.
xdg-mime default org.kde.dolphin.desktop inode/directory
xdg-mime default org.kde.dolphin.desktop application/x-directory

# Open/Save dialogs have a separate provider from the default file manager.
# Install both names because the desktop-specific file takes precedence.
mkdir -p "$config_dir/xdg-desktop-portal"
for config in hyprland-portals.conf portals.conf; do
    ln -sfn "$root/xdg-desktop-portal/$config" "$config_dir/xdg-desktop-portal/$config"
done

# Both system service filenames can claim the same bus name. Override both
# so activation consistently uses Dolphin and its live palette wrapper.
for service in org.freedesktop.FileManager1 org.kde.dolphin.FileManager1; do
    cat >"$data_dir/dbus-1/services/$service.service" <<EOF
# Managed by Imperium SetDefaultFileManager.sh
[D-BUS Service]
Name=org.freedesktop.FileManager1
Exec="$root/dolphin/launch.sh" --daemon
EOF
done

if [[ -n ${DBUS_SESSION_BUS_ADDRESS:-} ]]; then
    dbus-send --session --type=method_call --print-reply \
        --dest=org.freedesktop.DBus /org/freedesktop/DBus \
        org.freedesktop.DBus.ReloadConfig >/dev/null
fi
