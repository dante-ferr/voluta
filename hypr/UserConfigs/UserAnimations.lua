-- UserAnimations.lua - Fluid, high-performance animation curves for Hyprland Lua
---@module 'hl'

hl.config({
    animations = {
        enabled = true,
    },
})

-- Custom Fluid & Spring Bezier Curves
hl.curve("fluidDecel", { type = "bezier", points = { { 0.16, 1.0 }, { 0.30, 1.0 } } })
hl.curve("snappySpring", { type = "bezier", points = { { 0.05, 0.95 }, { 0.15, 1.05 } } })
hl.curve("softEaseInOut", { type = "bezier", points = { { 0.42, 0.0 }, { 0.58, 1.0 } } })
hl.curve("fastOut", { type = "bezier", points = { { 0.25, 0.1 }, { 0.25, 1.0 } } })

-- Window Animations
hl.animation({ leaf = "windows", enabled = true, speed = 5, bezier = "fluidDecel", style = "slide" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 5, bezier = "snappySpring", style = "popin 85%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 4, bezier = "fastOut", style = "popin 85%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 5, bezier = "fluidDecel", style = "slide" })

-- Border color fades. borderangle stays off: the borders are solid wallust
-- colors, and style=loop damages them every frame. On the 200Hz panel that
-- kept the GPU mapping new blur and shadow buffers until the driver locked.
hl.animation({ leaf = "border", enabled = true, speed = 5, bezier = "fluidDecel" })
hl.animation({ leaf = "borderangle", enabled = false })

-- Fade transitions
hl.animation({ leaf = "fade", enabled = true, speed = 4, bezier = "softEaseInOut" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 4, bezier = "softEaseInOut" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 3, bezier = "softEaseInOut" })

-- Workspace transitions (Silky horizontal slides)
hl.animation({ leaf = "workspaces", enabled = true, speed = 5, bezier = "fluidDecel", style = "slide" })
hl.animation({ leaf = "workspacesIn", enabled = true, speed = 5, bezier = "fluidDecel", style = "slide" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 4, bezier = "fluidDecel", style = "slide" })

-- Layer Surface Animations (Rofi, Waybar, Notifications)
hl.animation({ leaf = "layers", enabled = true, speed = 4, bezier = "fluidDecel", style = "fade" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 4, bezier = "snappySpring", style = "fade" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 3, bezier = "fastOut", style = "fade" })
