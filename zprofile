# Login path must never fail or initialize interactive tools.
emulate -R sh
set +e
unset NVD_BACKEND GBM_BACKEND
_voluta_login="${XDG_CONFIG_HOME:-$HOME/.config}/voluta-login-env.sh"
if [ -r "$_voluta_login" ]; then . "$_voluta_login" || true; fi
unset _voluta_login
export PATH="$HOME/.local/bin:$PATH"
{
    mkdir -p "${XDG_STATE_HOME:-$HOME/.local/state}" &&
    printf '%s host=%s\n' "$(date -Iseconds 2>/dev/null || date)" "$(hostname 2>/dev/null)" >>"${XDG_STATE_HOME:-$HOME/.local/state}/graphical-login.log"
} 2>/dev/null || true
