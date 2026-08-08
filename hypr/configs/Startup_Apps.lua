-- Default Startup Apps Configuration for Hyprland Lua
---@module 'hl'

local home = os.getenv("HOME") or "/home/dante"
local scriptsDir = home .. "/.config/hypr/scripts"
local UserScripts = home .. "/.config/hypr/UserScripts"

hl.on("hyprland.start", function()
    -- Environment and D-Bus activation
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE")
    hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE")

    -- Notification Daemon (SwayNC) - Critical for OSD volume & media popups
    hl.exec_cmd("pkill -x swaync || true && swaync &")

    -- Bar, Wallpaper & Media
    hl.exec_cmd("pkill -x waybar || true && waybar &")
    hl.exec_cmd("waypaper --restore || true")
    hl.exec_cmd("playerctld daemon || true")

    -- Idle Daemon (Hypridle)
    hl.exec_cmd("pkill -x hypridle || true && hypridle &")

    -- Clipboard manager
    hl.exec_cmd("wl-paste --type text --watch cliphist store &")
    hl.exec_cmd("wl-paste --type image --watch cliphist store &")
end)
