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

-- Workspace transitions: incoming content drifts farther and more slowly;
-- outgoing content clears quickly for a layered sense of depth.
hl.animation({ leaf = "workspaces", enabled = true, speed = 6, bezier = "fluidDecel", style = "slidefade 30%" })
hl.animation({ leaf = "workspacesIn", enabled = true, speed = 6, bezier = "fluidDecel", style = "slidefade 24%" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 3, bezier = "fastOut", style = "slidefade 12%" })

-- Layer Surface Animations (Rofi, Waybar, Notifications)
hl.animation({ leaf = "layers", enabled = true, speed = 4, bezier = "fluidDecel", style = "fade" })
-- speed is duration in deciseconds. The exit is a little slower than the entrance.
hl.animation({ leaf = "layersIn", enabled = true, speed = 5, bezier = "snappySpring", style = "fade" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 6, bezier = "fastOut", style = "fade" })
hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 5, bezier = "softEaseInOut" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 6, bezier = "fastOut" })

-- Popup and panel share the same entrance and a moderate exit.
-- These layers inherit snappySpring on entry and fastOut on exit above;
-- slide also animates alpha from zero to one and back on every map/unmap.
-- The veil is one opacity across the screen. Hyprland blurs those pixels;
-- a fully transparent layer shows the sharp wallpaper instead.
hl.layer_rule({
    name = "notification-drop",
    match = { namespace = "^swaync-(control-center|notification-window)$" },
    blur = true,
    xray = false,
    ignore_alpha = 0,
    animation = "slide top",
})

-- The in-frame projection stays below SwayNC's native Overlay controls.
hl.layer_rule({
    name = "voluta-notification-glass",
    match = { namespace = "^voluta-notification-glass$" },
    blur = true,
    xray = false,
    ignore_alpha = 0,
    animation = "slide top",
})

-- Full-desktop blur sits below the sharp menu. The veil image adds no color.
hl.layer_rule({
    name = "voluta-notification-backdrop",
    match = { namespace = "^voluta-notification-backdrop$" },
    blur = true,
    xray = false,
    ignore_alpha = 0,
    order = 1,
    no_anim = true,
})

-- Rofi takes the keyboard immediately and still slides in and out.
hl.layer_rule({
    name = "rofi-launcher",
    match = { namespace = "^rofi$" },
    blur = true,
    xray = false,
    ignore_alpha = 0,
    animation = "slide bottom",
})

-- Quickshell owns the frame entrance and the short exit.
hl.layer_rule({
    name = "voluta-selector-glass",
    match = { namespace = "^voluta-selector-glass$" },
    blur = true,
    xray = false,
    ignore_alpha = 0,
    no_anim = true,
})

hl.layer_rule({
    name = "voluta-music-glass",
    match = { namespace = "^voluta-music-glass$" },
    blur = true,
    xray = false,
    ignore_alpha = 0,
    no_anim = true,
})

hl.layer_rule({
    name = "voluta-session-glass",
    match = { namespace = "^voluta-session-glass$" },
    blur = true,
    xray = false,
    ignore_alpha = 0,
    no_anim = true,
})
