---@module 'hl'

-- Main Hyprland User Settings & Keyboard Configuration
hl.config({
    general = {
        gaps_in = 8,
        gaps_out = 16,
        border_size = 2,
        resize_on_border = true,
    },
    input = {
        kb_layout = "us,br",
        kb_variant = ",abnt2",
        kb_options = "grp:alt_shift_toggle",
        repeat_delay = 250,
        repeat_rate = 35,
        follow_mouse = 1,
        touchpad = {
            natural_scroll = true,
        },
    },
    binds = {
        focus_preferred_method = 1,
        window_direction_monitor_fallback = true,
        movefocus_cycles_fullscreen = true,
    },
    misc = {
        vrr = 0,
        disable_hyprland_logo = true,
    },
})
