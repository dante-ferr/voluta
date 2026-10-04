-- UserDecorations.lua - Imperium Cyber-Sacred Rice Aesthetics (Opaque, Sharp Edges, Dynamic Wallust Borders)
---@module 'hl'

local wallust = require("UserConfigs.wallust")

-- Fallbacks are Imperial Gold & Obsidian Slate.
local active_color = wallust.get("color1", "rgb(D4AF37)")
local inactive_color = wallust.get("color0", "rgb(16161D)")

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
            size = 2,
            passes = 2,
            new_optimizations = true,
            -- Windows are opaque by rule, so this only ever reaches surfaces that
            -- ask for alpha themselves — kitty being the one that does.
            xray = false,
            ignore_opacity = false,
            -- Chromium and Brave popups hand Hyprland regions with a zero or
            -- negative extent. pixman_region32_init_rect rejects those, and
            -- the following blur pass is what reset the GL context.
            popups = false,
            -- Darkened and desaturated: a bright wallpaper behind a translucent
            -- terminal otherwise washes out the foreground text.
            brightness = 0.65,
            contrast = 1.05,
            vibrancy = 0.15,
            vibrancy_darkness = 0.4,
            noise = 0.012,
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

-- Brave stays opaque. Blur, shadows, and the popin animation on that class
-- are what preceded the GPU reset (media-process SIGILL, then Hyprland ABRT
-- in CHyprOpenGLImpl::begin).
hl.window_rule({
    name = "brave-skip-effects",
    match = { class = "^(brave-browser|Brave-browser)$" },
    no_blur = true,
    no_shadow = true,
    no_anim = true,
})
