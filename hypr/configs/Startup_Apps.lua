-- Default Startup Apps Configuration for Hyprland Lua
---@module 'hl'

local home = os.getenv("HOME") or "/home/dante"
local UserScripts = home .. "/.config/hypr/UserScripts"
local Scripts = home .. "/.config/hypr/scripts"

-- Official autostart: only on hyprland.start (not on every hyprctl reload).
-- See https://wiki.hypr.land/Configuring/Basics/Autostart/
hl.on("hyprland.start", function()
    -- Environment and D-Bus activation
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE")
    hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE")

    -- Notification Daemon (SwayNC) - Critical for OSD volume & media popups
    hl.exec_cmd("sh -c 'pgrep -x swaync >/dev/null || swaync &'")

    -- Wallpaper restore without post_command: waypaper fires post_command once
    -- per monitor in parallel, which used to stack duplicate waybars. Colors and
    -- the bar are refreshed once below via combined_wallust.sh instead.
    hl.exec_cmd("waypaper --restore --no-post-command || true")

    -- Early bar from last session's CSS so a hung wallust/reload path cannot
    -- leave the desktop bare. combined_wallust restarts it once colors are ready.
    hl.exec_cmd(Scripts .. "/StartWaybar.sh")

    hl.exec_cmd("bash " .. UserScripts .. "/combined_wallust.sh &")

    hl.exec_cmd("playerctld daemon || true")

    -- Idle Daemon (Hypridle)
    hl.exec_cmd("sh -c 'pgrep -x hypridle >/dev/null || hypridle &'")

    -- Clipboard manager
    hl.exec_cmd("sh -c 'pgrep -x cliphist >/dev/null || (wl-paste --type text --watch cliphist store & wl-paste --type image --watch cliphist store &)'")
end)
