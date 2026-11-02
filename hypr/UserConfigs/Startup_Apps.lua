---@module 'hl'

-- Kept in sync with configs.Startup_Apps (the one hyprland.lua loads). Not
-- required separately; left here so a host profile that pulls UserConfigs
-- does not resurrect the old double-waybar startup path.

local home = os.getenv("HOME") or "/home/dante"
local UserScripts = home .. "/.config/hypr/UserScripts"
local Scripts = home .. "/.config/hypr/scripts"

hl.on("hyprland.start", function()
    hl.exec_cmd("~/.config/hypr/UserScripts/auto_host_link.sh")
    hl.exec_cmd(Scripts .. "/StartWaybar.sh")
    hl.exec_cmd("sh -c 'waypaper --restore --no-post-command || true; bash " .. UserScripts .. "/combined_wallust.sh' &")
    hl.exec_cmd("playerctld daemon")
    hl.exec_cmd(Scripts .. "/StartHypridle.sh")

    -- Restore first, then autosave under one per-compositor lock.
    hl.exec_cmd("sh -c 'mkdir -p \"${XDG_STATE_HOME:-$HOME/.local/state}\"; python3 " .. Scripts .. "/session_manager.py start >>\"${XDG_STATE_HOME:-$HOME/.local/state}/hyprland-session.log\" 2>&1'")
end)
