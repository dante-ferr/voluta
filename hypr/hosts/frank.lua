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
        vrr = 1,
        allow_session_lock_restore = true,
    },
})
