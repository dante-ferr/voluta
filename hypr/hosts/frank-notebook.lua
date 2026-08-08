-- Host specific configuration for frank-notebook (converted to Hyprland Lua)
---@module 'hl'

hl.config({
    general = {
        border_size = 2,
    },
    decoration = {
        shadow = {
            enabled = false,
        },
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
        vrr = 0,
    },
})
