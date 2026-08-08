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
        blur = {
            enabled = false, -- Disabled blur for crisp legibility
        },
        shadow = {
            enabled = true,
            range = 24,
            render_power = 3,
            sharp = false, -- Soft falloff, even though the windows are square
            color = shadow_of(shadow_base, "B3"),
            color_inactive = shadow_of(shadow_base, "59"),
            offset = "0 5", -- Light source overhead, cast slightly downward
            scale = 0.98,
        },
    },
})
