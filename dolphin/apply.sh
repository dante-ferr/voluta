#!/usr/bin/env bash
# Reapply the complete Dolphin appearance without switching the rest of the rice.
set -euo pipefail
here=$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")
root=${here%/*}
[[ -x /usr/bin/dolphin ]] || exit 0

python3 "$here/apply-config.py"
mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications"
ln -sfn "$here/launch.sh" "$HOME/.local/bin/dolphin"
if [[ -f /usr/share/applications/org.kde.dolphin.desktop ]]; then
    sed -e "s|^Exec=dolphin |Exec=$HOME/.local/bin/dolphin |" \
        -e 's|^DBusActivatable=true|DBusActivatable=false|' \
        /usr/share/applications/org.kde.dolphin.desktop \
        >"$HOME/.local/share/applications/org.kde.dolphin.desktop"
fi
bash "$root/hypr/scripts/SetDefaultFileManager.sh"
bash "$here/launch.sh" --prepare
bash "$root/hypr/UserScripts/paint_dolphin_theme.sh"

if command -v fc-match >/dev/null 2>&1 && ! fc-match -f '%{family}' 'Monaspace Argon' | grep -q 'Monaspace Argon'; then
    echo 'Install otf-monaspace for the Imperium Dolphin font.' >&2
    notify-send "Dolphin font missing" "Install otf-monaspace, then reopen Dolphin." 2>/dev/null || true
fi
if pgrep -u "$(id -u)" -x dolphin >/dev/null; then
    notify-send "Dolphin appearance applied" "Fully quit Dolphin and reopen it to apply updated code and saved view settings." 2>/dev/null || true
fi
