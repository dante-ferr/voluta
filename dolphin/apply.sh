#!/usr/bin/env bash
# Reapply the complete Dolphin appearance without switching the rest of the rice.
set -euo pipefail
here=$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")
root=${here%/*}
python3 "$root/voluta/cli.py" enabled dolphin --legacy || exit 0
# Install before touching appearance files or building the hook. The full
# rice installer includes the same manifest, so both entry points converge.
source "$root/deps/packages.sh"
ensure_arch_packages "$root/deps/dolphin.txt" Dolphin

need_cache=false
if ! fc-match -f '%{family}' 'Oxanium' | grep -q 'Oxanium'; then
    need_cache=true
fi
if ! fc-match -f '%{family}' 'Monaspace Argon' | grep -q 'Monaspace Argon'; then
    need_cache=true
fi
if $need_cache; then
    fc-cache -f
fi
if ! fc-match -f '%{family}' 'Oxanium' | grep -q 'Oxanium'; then
    echo 'ttf-oxanium is installed, but fontconfig cannot resolve Oxanium.' >&2
    exit 1
fi
if ! fc-match -f '%{family}' 'Monaspace Argon' | grep -q 'Monaspace Argon'; then
    echo 'otf-monaspace is installed, but fontconfig cannot resolve Monaspace Argon.' >&2
    exit 1
fi

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
