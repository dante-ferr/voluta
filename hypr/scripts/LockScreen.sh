#!/usr/bin/env bash
# Session lock launcher.
# --no-fade-in / --grace 0: hyprlock must be fully locked before NVIDIA sleep,
# and must not fade while the DRM node is coming back.

umask 077
state="${XDG_STATE_HOME:-$HOME/.local/state}/voluta/lock"
mkdir -p "$state" || exit 1
log="$state/hyprlock.log"
if [[ -f "$log" && $(stat -c %s "$log") -gt 1048576 ]]; then
    mv -f "$log" "$log.1"
fi

# Serialize hotkey and logind requests. Keep the fd open in the locker so a
# second request cannot create another client competing for the session lock.
runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
exec 9>"$runtime/voluta-session-lock.lock" || exit 1
flock -n 9 || exit 0
exec >>"$log" 2>&1
LOCK_ARGS=(--no-fade-in --grace 0)

if command -v hyprlock >/dev/null 2>&1; then
    pgrep -u "$(id -u)" -x hyprlock >/dev/null 2>&1 && exit 0
    printf '\n[%s] starting hyprlock\n' "$(date -Is)"
    exec hyprlock "${LOCK_ARGS[@]}"
fi

if command -v swaylock >/dev/null 2>&1; then
    exec swaylock -f
elif command -v gtklock >/dev/null 2>&1; then
    exec gtklock
else
    printf '[%s] ERROR: no supported session locker installed\n' "$(date -Is)"
    exit 1
fi
