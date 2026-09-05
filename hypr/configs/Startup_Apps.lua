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

    -- Early bar from last session's CSS so a hung wallust path cannot leave
    -- the desktop bare. combined_wallust restarts it once colors are ready.
    hl.exec_cmd(Scripts .. "/StartWaybar.sh")

    -- Wallpaper restore without post_command: waypaper fires post_command once
    -- per monitor in parallel, which used to stack duplicate waybars. Once restored,
    -- combined_wallust refreshes the palette and desktop components synchronously.
    hl.exec_cmd("sh -c 'waypaper --restore --no-post-command || true; bash " .. UserScripts .. "/combined_wallust.sh' &")

    hl.exec_cmd("playerctld daemon || true")

    -- Idle Daemon (Hypridle)
    hl.exec_cmd("sh -c 'pgrep -x hypridle >/dev/null || hypridle &'")

    -- Clipboard manager
    hl.exec_cmd("sh -c 'pgrep -x cliphist >/dev/null || (wl-paste --type text --watch cliphist store & wl-paste --type image --watch cliphist store &)'")

    -- Session Manager: Restore previous windows and start auto-save daemon
    hl.exec_cmd("python3 " .. Scripts .. "/session_manager.py restore &")
    hl.exec_cmd("python3 " .. Scripts .. "/session_manager.py daemon &")
end)
