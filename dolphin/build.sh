#!/usr/bin/env bash
# Build before launch so a pulled customization never opens with the old hook.
set -euo pipefail
here=$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")
libdir="$HOME/.local/lib/imperium"
lib="$libdir/libdolphin-live.so"
mkdir -p "$libdir"
exec 9>"$libdir/.dolphin-live-build.lock"
flock 9

# Include the toolchain and KDE/Qt versions: an unchanged source can still
# need rebuilding after a system upgrade. Content hashes survive preserved mtimes.
signature=$({
    sha256sum "$here/live.cpp" "$here/build.sh"
    g++ -dumpfullversion
    pkg-config --modversion Qt6Widgets
    pkg-config --cflags --libs Qt6Widgets
    sha256sum /usr/include/KF6/KIconThemes/kiconthemes_version.h \
        /usr/include/KF6/KParts/kparts_version.h
} | sha256sum | cut -d ' ' -f 1)
if [[ -f "$lib" && -f "$lib.sha256" && $(< "$lib.sha256") == "$signature" ]]; then
    exit 0
fi

log="$libdir/dolphin-live-build.log"
previous_library=$(stat -Lc '%d:%i' "$lib" 2>/dev/null || true)
build_tmp=$(mktemp "$libdir/.libdolphin-live.XXXXXX.so")
trap 'rm -f -- "$build_tmp"' EXIT
if ! g++ -shared -fPIC -O2 -std=c++17 -pthread -o "$build_tmp" "$here/live.cpp" \
    -I/usr/include/KF6/KIconThemes -I/usr/include/KF6/KParts \
    $(pkg-config --cflags --libs Qt6Widgets) -lKF6IconThemes >"$log" 2>&1; then
    echo "Dolphin customization build failed. See $log" >&2
    exit 1
fi
chmod 755 "$build_tmp"
mv -f -- "$build_tmp" "$lib"
printf '%s\n' "$signature" >"$lib.sha256"

# Ordinary launches and unchanged refreshes are silent. Only a successful
# replacement can require a restart, and only for apps mapping that old file.
if [[ -n "$previous_library" ]]; then
    python3 "$here/notify-restart.py" --previous-library "$previous_library" \
        --revision "$signature" || true
fi
