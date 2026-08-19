---@module 'hl'

-- Main Hyprland User Settings & Keyboard Configuration
-- Migrated from the former UserSettings.conf (Hyprland no longer loads .conf here).

hl.env("GDK_BACKEND", "wayland,x11,*")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("SDL_VIDEODRIVER", "wayland")
hl.env("CLUTTER_BACKEND", "wayland")
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
-- NVIDIA: required for a stable suspend/resume with hyprlock. Without these
-- the lock greeter can freeze on the DRM reset and only a reboot recovers it.
hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
hl.env("NVD_BACKEND", "direct")

hl.config({
    general = {
        gaps_in = 8,
        gaps_out = 16,
        border_size = 2,
        resize_on_border = true,
        layout = "dwindle",
    },
    input = {
        kb_layout = "us,br",
        kb_variant = ",abnt2",
        kb_options = "grp:alt_shift_toggle",
        repeat_delay = 250,
        repeat_rate = 35,
        sensitivity = 0,
        numlock_by_default = true,
        left_handed = false,
        follow_mouse = 1,
        float_switch_override_focus = false,
        touchpad = {
            natural_scroll = true,
        },
    },
    cursor = {
        no_warps = false,
        -- Hardware cursors on NVIDIA often come back dead after suspend, and
        -- the compositor then looks frozen on the lock screen.
        no_hardware_cursors = true,
    },
    binds = {
        workspace_back_and_forth = false,
        focus_preferred_method = 1,
        window_direction_monitor_fallback = true,
        movefocus_cycles_fullscreen = true,
    },
    dwindle = {
        preserve_split = true,
        special_scale_factor = 0.8,
    },
    misc = {
        vrr = 0,
        disable_hyprland_logo = true,
        -- Lets Super+Alt+L spawn a fresh hyprlock if the previous one died
        -- during resume ("Oopsie daisy") instead of wedging the session.
        allow_session_lock_restore = true,
    },
})
