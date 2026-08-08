---@module 'hl'

-- Commands and Apps to be executed at launch
hl.on("hyprland.start", function()
    hl.exec_cmd("sleep 2 && waypaper --restore")
    hl.exec_cmd("~/.config/hypr/UserScripts/auto_host_link.sh")
    hl.exec_cmd("waybar")
    hl.exec_cmd("playerctld daemon")
    hl.exec_cmd("pkill -x hypridle || true && hypridle &")
end)
