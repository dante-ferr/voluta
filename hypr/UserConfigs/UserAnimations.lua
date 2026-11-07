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
-- A gentle lift before acceleration keeps small notification cards visible
-- while their full-height layer surface starts travelling off-screen.
hl.curve("inertialLift", { type = "bezier", points = { { 0.65, 0.0 }, { 0.85, 0.35 } } })

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
hl.animation({ leaf = "layersIn", enabled = true, speed = 4, bezier = "snappySpring", style = "fade" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 5, bezier = "inertialLift", style = "fade" })
hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 4, bezier = "softEaseInOut" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 5, bezier = "softEaseInOut" })

-- Popup and panel share the same entrance, exit, and inertial easing.
-- These layers inherit snappySpring on entry and inertialLift on exit above;
-- slide also animates alpha from zero to one and back on every map/unmap.
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
    no_anim = true,
})

-- Rofi owns input and slides independently of the decorative layer.
hl.layer_rule({
    name = "rofi-launcher",
    match = { namespace = "^rofi$" },
    blur = true,
    xray = false,
    ignore_alpha = 0,
    animation = "slide bottom",
})

-- Quickshell owns the frame's fast entrance and slower delayed departure.
hl.layer_rule({
    name = "voluta-selector-glass",
    match = { namespace = "^voluta-selector-glass$" },
    blur = true,
    xray = false,
    ignore_alpha = 0,
    no_anim = true,
})
