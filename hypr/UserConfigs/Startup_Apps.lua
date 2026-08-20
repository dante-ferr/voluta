---@module 'hl'

-- Kept in sync with configs.Startup_Apps (the one hyprland.lua loads). Not
-- required separately; left here so a host profile that pulls UserConfigs
-- does not resurrect the old double-waybar startup path.

local home = os.getenv("HOME") or "/home/dante"
local UserScripts = home .. "/.config/hypr/UserScripts"
local Scripts = home .. "/.config/hypr/scripts"

hl.on("hyprland.start", function()
    hl.exec_cmd("~/.config/hypr/UserScripts/auto_host_link.sh")
    hl.exec_cmd("waypaper --restore --no-post-command || true")
    hl.exec_cmd(Scripts .. "/StartWaybar.sh")
    hl.exec_cmd("bash " .. UserScripts .. "/combined_wallust.sh &")
    hl.exec_cmd("playerctld daemon")
    hl.exec_cmd("sh -c 'pgrep -x hypridle >/dev/null || hypridle &'")
end)
