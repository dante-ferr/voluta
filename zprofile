# SDDM runs `zsh --login` and then execs `uwsm`. This file is on that path.
# If this shell exits, or if Hyprland is handed a GPU backend it cannot open,
# the greeter comes back in one or two seconds and clears the password.
# Keep this file free of failing commands. Do not source .zshrc from here.

emulate -R sh
set +e

unset NVD_BACKEND
unset GBM_BACKEND

host_name=$(cat /etc/hostname 2>/dev/null || true)
case "$host_name" in
    frank-notebook)
        # Session stays on the Intel iGPU. CUDA is not masked.
        export LIBVA_DRIVER_NAME=iHD
        export __GLX_VENDOR_LIBRARY_NAME=mesa
        ;;
    frank)
        # Do not export GBM_BACKEND or LIBVA_DRIVER_NAME=nvidia. Both have
        # bounced this machine back to the SDDM password field.
        unset LIBVA_DRIVER_NAME
        ;;
esac

# A failed log must not print or abort the login shell.
{
    mkdir -p "$HOME/.local/state" &&
        printf '%s host=%s libva=%s glx=%s gbm=%s nvd=%s\n' \
            "$(date -Iseconds 2>/dev/null || date)" \
            "${host_name:-unknown}" \
            "${LIBVA_DRIVER_NAME-<unset>}" \
            "${__GLX_VENDOR_LIBRARY_NAME-<unset>}" \
            "${GBM_BACKEND-<unset>}" \
            "${NVD_BACKEND-<unset>}" \
            >>"$HOME/.local/state/graphical-login.log"
} 2>/dev/null || true
unset host_name

export PATH="$HOME/.local/bin:$PATH"
