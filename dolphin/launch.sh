#!/bin/bash
# Launch Dolphin with the live palette hook. Child processes do not keep it:
# the library removes itself from LD_PRELOAD as soon as Dolphin starts.
set -u

here=$(dirname "$(readlink -f "$0")")
src="$here/live.cpp"
lib="${HOME}/.local/lib/imperium/libdolphin-live.so"
mkdir -p "$(dirname "$lib")"

if [[ ! -f "$lib" || "$src" -nt "$lib" ]]; then
    if ! g++ -shared -fPIC -O2 -std=c++17 -pthread -o "$lib" "$src" \
        -I/usr/include/KF6/KIconThemes \
        $(pkg-config --cflags --libs Qt6Widgets) -lKF6IconThemes; then
        exec /usr/bin/dolphin "$@"
    fi
fi

export LD_PRELOAD="${lib}${LD_PRELOAD:+:$LD_PRELOAD}"
exec /usr/bin/dolphin "$@"
