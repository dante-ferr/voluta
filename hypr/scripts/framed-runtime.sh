# Open-state files and cached renderer pids for the framed menus.
# A missing or empty marker means that menu is closed. Callers must not
# start Quickshell just to confirm it.
voluta_runtime() {
    printf '%s\n' "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
}

voluta_menu_open() {
    [ -s "$(voluta_runtime)/voluta-$1.open" ]
}

voluta_renderer_pid() {
    runtime=$(voluta_runtime)
    pidfile="$runtime/voluta-$1-renderer.pid"
    if [ -r "$pidfile" ]; then
        pid=$(tr -dc '0-9' < "$pidfile")
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            printf '%s\n' "$pid"
            return 0
        fi
    fi
    command -v quickshell >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || return 1
    renderer=$(readlink -f -- "$2" 2>/dev/null) || return 1
    [ -n "$renderer" ] || return 1
    pid=$(quickshell list -j -p "$renderer" 2>/dev/null | jq -r '.[].pid // empty' 2>/dev/null |
        awk 'NF && $1 ~ /^[0-9]+$/ { print; exit }')
    [ -n "$pid" ] || return 1
    printf '%s\n' "$pid" > "$pidfile" 2>/dev/null || true
    printf '%s\n' "$pid"
}
