-- UserDecorations.lua - Imperium Cyber-Sacred Rice Aesthetics (Opaque, Sharp Edges, Dynamic Wallust Borders)
---@module 'hl'

local wallust = require("UserConfigs.wallust")

-- Fallbacks are Imperial Gold & Obsidian Slate.
local active_color = wallust.get("color1", "rgb(D4AF37)")
local inactive_color = wallust.get("color0", "rgb(16161D)")

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
            enabled = false,
        },
    },
})
