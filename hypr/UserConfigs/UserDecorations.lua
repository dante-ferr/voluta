-- UserDecorations.lua - Imperium Cyber-Sacred Rice Aesthetics (Opaque, Sharp Edges, Dynamic Wallust Borders)
---@module 'hl'

local wallust = require("UserConfigs.wallust")

-- Lifted border tokens from colors-hyprland.conf. Raw color1/color0 follow the
-- wallpaper and can sit near-black; active_border / inactive_border keep the
-- same contrast lift Kitty and Waybar apply to accents.
local active_color = wallust.get("active_border", "rgb(E0C46A)")
local inactive_color = wallust.get("inactive_border", "rgb(3A3A48)")

--- Hyprland wants shadows as rgba(RRGGBBAA), but wallust emits rgb(RRGGBB).
---@param color string
---@param alpha string two hex digits
---@return string
local function shadow_of(color, alpha)
    local hex = color:match("rgba?%(#?(%x%x%x%x%x%x)")
    return string.format("rgba(%s%s)", hex or "05050A", alpha)
end

-- Shadows are tinted with the palette's own background rather than flat black,
-- so they read as depth against the wallpaper instead of a grey smudge.
local shadow_base = wallust.get("background", "rgb(05050A)")

hl.config({
    general = {
        gaps_in = 6,
        gaps_out = 12,
        border_size = 2,
        ["col.active_border"] = active_color,
        ["col.inactive_border"] = inactive_color,
        layout = "dwindle",
    },
    decoration = {
        rounding = 0, -- Strict 90-degree sharp corners
        active_opacity = 1.0, -- 100% solid opacity (No window transparency)
        inactive_opacity = 1.0,
        fullscreen_opacity = 1.0,
        dim_special = 0.6, -- Dim background behind special workspace (0.0 - 1.0)
        blur = {
            enabled = true,
            special = true, -- Blur background behind special workspace
            -- A light frost behind the launcher. Larger kernels washed the
            -- wallpaper out; size 1 was invisible.
            size = 3,
            passes = 1,
            new_optimizations = true,
            -- Windows are opaque by rule, so this only reaches translucent
            -- surfaces: kitty terminals and the Rofi launcher layer.
            xray = false,
            ignore_opacity = false,
            -- Chromium and Brave popups hand Hyprland regions with a zero or
            -- negative extent. pixman_region32_init_rect rejects those, and
            -- the following blur pass is what reset the GL context.
            popups = false,
            -- Darkened and desaturated: a bright wallpaper behind a translucent
            -- terminal otherwise washes out the foreground text.
            brightness = 1.0,
            contrast = 1.0,
            vibrancy = 0,
            vibrancy_darkness = 0,
            noise = 0,
        },
        shadow = {
            enabled = true,
            -- range 24 at render_power 3 on the 1440p@200 output, plus the
            -- 1080p panel, was allocating shadow textures until the NVIDIA
            -- BAR1 aperture returned NV_ERR_NO_MEMORY.
            range = 8,
            render_power = 2,
            sharp = false, -- Soft falloff, even though the windows are square
            color = shadow_of(shadow_base, "B3"),
            color_inactive = shadow_of(shadow_base, "59"),
            offset = "0 5", -- Light source overhead, cast slightly downward
            scale = 0.98,
        },
    },
})
