#!/usr/bin/env bash
# Install the Imperium SDDM theme over simple_sddm_2's QML.
# Needs root: writes /usr/share/sddm/themes/imperium and a drop-in in
# /etc/sddm.conf.d so it wins over the sugar-candy override.

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RICE="$(cd "$SRC/.." && pwd)"
DEST="/usr/share/sddm/themes/imperium"
BASE="/usr/share/sddm/themes/simple_sddm_2"
WALL="$RICE/hypr/assets/school-of-athens.jpg"
DROPIN="/etc/sddm.conf.d/zz-imperium.conf"

# sudo resets HOME to /root; keep the invoking user's Cinzel.
if [[ -n ${SUDO_USER:-} ]]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    USER_HOME="${HOME:-/home/dante}"
fi
CINZEL_SRC="$USER_HOME/.local/share/fonts/cinzel/Cinzel[wght].ttf"

if [[ $EUID -ne 0 ]]; then
    echo "sddm/install.sh: re-running with root privileges..." >&2
    exec sudo -- "$0" "$@"
fi

if [[ ! -d "$BASE" ]]; then
    echo "sddm/install.sh: $BASE is missing (install simple_sddm_2)." >&2
    exit 1
fi

if [[ ! -f "$WALL" ]]; then
    echo "sddm/install.sh: wallpaper not found at $WALL" >&2
    exit 1
fi

mkdir -p "$DEST/Backgrounds"

ln -sfn "$BASE/Main.qml" "$DEST/Main.qml"
ln -sfn "$BASE/Assets" "$DEST/Assets"

# Copy Components so the input fields can be made opaque (upstream QML
# paints them at 20% opacity, which vanishes on the fresco).
rm -rf "$DEST/Components"
cp -a "$BASE/Components" "$DEST/Components"
# Only the input-field and login-button fills; leave hover/state opacities.
sed -i 's/opacity: 0.2/opacity: 0.92/' "$DEST/Components/Input.qml"

install -m 644 "$SRC/theme.conf" "$DEST/theme.conf"
install -m 644 "$SRC/metadata.desktop" "$DEST/metadata.desktop"
install -m 644 "$WALL" "$DEST/Backgrounds/school-of-athens.jpg"

if [[ -f "$CINZEL_SRC" ]]; then
    mkdir -p /usr/local/share/fonts/imperium
    install -m 644 "$CINZEL_SRC" /usr/local/share/fonts/imperium/Cinzel[wght].ttf
    fc-cache -f /usr/local/share/fonts/imperium >/dev/null 2>&1 || true
fi

cat >"$DROPIN" <<'EOF'
[Theme]
Current=imperium
EOF

echo "Installed Imperium SDDM theme at $DEST (Current=imperium)."
