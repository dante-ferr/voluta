#!/bin/bash
# Launch Dolphin with the live palette hook. Child processes do not keep it:
# the library removes itself from LD_PRELOAD as soon as Dolphin starts.
set -u

here=$(readlink -f "$0")
here=${here%/*}
src="$here/live.cpp"
lib="${HOME}/.local/lib/imperium/libdolphin-live.so"

if [[ ! -f "$lib" || "$src" -nt "$lib" ]]; then
    # Opening a window must not wait for a compiler. Keep using the existing
    # hook while a replacement builds; a first launch can use Dolphin alone.
    (
        libdir=${lib%/*}
        mkdir -p "$libdir" || exit
        exec 9>"$libdir/.dolphin-live-build.lock" || exit
        flock -n 9 || exit
        # Another launch may have completed the build before we got the lock.
        [[ -f "$lib" && ! "$src" -nt "$lib" ]] && exit
        exec >"$libdir/dolphin-live-build.log" 2>&1
        build_tmp=$(mktemp "$libdir/.libdolphin-live.XXXXXX.so") || exit
        trap 'rm -f -- "$build_tmp"' EXIT
        if g++ -shared -fPIC -O2 -std=c++17 -pthread -o "$build_tmp" "$src" \
            -I/usr/include/KF6/KIconThemes \
            -I/usr/include/KF6/KParts \
            $(pkg-config --cflags --libs Qt6Widgets) -lKF6IconThemes; then
            chmod 755 "$build_tmp" && mv -f -- "$build_tmp" "$lib"
        fi
    ) </dev/null >/dev/null 2>&1 &
fi

if [[ -f "$lib" ]]; then
    export LD_PRELOAD="${lib}${LD_PRELOAD:+:$LD_PRELOAD}"
fi
exec /usr/bin/dolphin "$@"
