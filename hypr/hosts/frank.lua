-- Host specific configuration for frank (converted to Hyprland Lua)
---@module 'hl'

hl.config({
    general = {
        border_size = 2,
    },
    decoration = {
        shadow = {
            enabled = true,
        },
    },
    input = {
        kb_layout = "us,br",
        kb_variant = ",abnt2",
        kb_options = "grp:alt_shift_toggle",
        repeat_delay = 250,
        repeat_rate = 35,
        follow_mouse = 1,
    },
    cursor = {
        no_hardware_cursors = true,
    },
    binds = {
        focus_preferred_method = 1,
        window_direction_monitor_fallback = true,
        movefocus_cycles_fullscreen = true,
    },
    misc = {
        -- DP-2 is 200Hz and HDMI-A-1 is 60Hz. VRR on the NVIDIA open module
        -- in that mix is one of the paths that ends in "GPU is probably locked".
        vrr = 0,
        allow_session_lock_restore = true,
    },
})

-- Desktop only. hyprland.lua loads this file when /etc/hostname is frank.
-- frank-notebook never reaches this line. VA-API stays off so Brave does
-- not load nvidia-vaapi-driver (see UserSettings.lua).
-- Do not set GBM_BACKEND here. Hyprland reads it while opening the DRM
-- device; nvidia-drm makes that open fail and SDDM returns to the password
-- field. The compositor already selects this machine's only GPU.
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
