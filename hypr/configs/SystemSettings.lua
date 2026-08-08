---@module 'hl'

-- Default System Settings
hl.config({
    general = {
        gaps_in = 4,
        gaps_out = 8,
        border_size = 2,
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
    misc = {
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        middle_click_paste = false,
        vrr = 1,
    },
})
