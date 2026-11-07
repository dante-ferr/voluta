-- Default Startup Apps Configuration for Hyprland Lua
---@module 'hl'

local home = os.getenv("HOME") or ""
local config = os.getenv("XDG_CONFIG_HOME") or (home .. "/.config")
local UserScripts = config .. "/hypr/UserScripts"
local Scripts = config .. "/hypr/scripts"

-- The palette watcher is safe on reload: its per-session lock prevents duplicates.
-- Starting here also activates integrations enabled after the current login.
local function start_palette_watcher()
    hl.exec_cmd("sh -c 'mkdir -p \"${XDG_STATE_HOME:-$HOME/.local/state}\"; /usr/bin/python3 " .. Scripts .. "/../../voluta/runtime.py watch >>\"${XDG_STATE_HOME:-$HOME/.local/state}/voluta-palette.log\" 2>&1'")
end
start_palette_watcher()

-- The per-session lock also makes this safe when the compositor reloads.
-- Keep the native panel usable when the optional glass renderer cannot start.
local function start_notification_glass()
    hl.exec_cmd("sh -c 'mkdir -p \"${XDG_STATE_HOME:-$HOME/.local/state}/voluta\"; /usr/bin/python3 " .. config .. "/swaync/watch-glass.py >>\"${XDG_STATE_HOME:-$HOME/.local/state}/voluta/notification-glass.log\" 2>&1'")
end
start_notification_glass()

-- Official autostart: only on hyprland.start (not on every hyprctl reload).
-- See https://wiki.hypr.land/Configuring/Basics/Autostart/
hl.on("hyprland.start", function()
    -- Environment and D-Bus activation
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE QT_QPA_PLATFORMTHEME")
    hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE QT_QPA_PLATFORMTHEME")

    local settings = require("configs.Voluta")
    -- Apps also use FileManager1 over D-Bus, independently of MIME defaults.
    if settings.apps.file_manager == "dolphin" then
        hl.exec_cmd("bash " .. Scripts .. "/SetDefaultFileManager.sh")
    end

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

    -- Idle daemon. hypridle.<hostname>.conf wins when present.
    hl.exec_cmd(Scripts .. "/StartHypridle.sh")

    -- Clipboard manager
    hl.exec_cmd("sh -c 'pgrep -x cliphist >/dev/null || (wl-paste --type text --watch cliphist store & wl-paste --type image --watch cliphist store &)'")

    -- Companion startup commands replace by name; false disables a custom entry.
    for _, command in pairs(settings.startup or {}) do
        if type(command) == "string" then hl.exec_cmd(command) end
    end
    start_palette_watcher()
    start_notification_glass()

    -- Supervisor preserves legacy behavior until explicit Voluta initialization.
    -- It notices enable/disable selections during this session.
    hl.exec_cmd("sh -c 'mkdir -p \"${XDG_STATE_HOME:-$HOME/.local/state}\"; python3 " .. Scripts .. "/../../voluta/session.py >>\"${XDG_STATE_HOME:-$HOME/.local/state}/hyprland-session.log\" 2>&1'")
end)
