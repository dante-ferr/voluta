#!/bin/bash
# Build Voluta's karere-custom-css overlay and install it.
# Stock karere is removed only after this package file exists.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
cache=${XDG_CACHE_HOME:-$HOME/.cache}/voluta/karere-custom-css
rm -rf "$cache"
mkdir -p "$cache"
cp "$here/PKGBUILD" "$here/fix-compile-resources-types.patch" "$cache/"
cd "$cache"

makepkg -s --noconfirm

mapfile -t packages < <(find "$cache" -maxdepth 1 -type f -name 'karere-custom-css-*.pkg.tar.zst' ! -name '*-debug-*' | sort)
if ((${#packages[@]} == 0)); then
    echo "karere-custom-css: makepkg produced no package" >&2
    exit 1
fi

# --ask 4 accepts pacman's conflict-removal question. --noconfirm alone answers no.
if [[ ${EUID} -eq 0 ]]; then
    pacman -U --noconfirm --ask 4 "${packages[@]}"
else
    sudo pacman -U --noconfirm --ask 4 "${packages[@]}"
fi
