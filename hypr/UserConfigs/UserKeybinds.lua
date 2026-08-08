-- Complete Hyprland Lua Keybindings
---@module 'hl'

local home = os.getenv("HOME") or "/home/dante"
local scriptsDir = home .. "/.config/hypr/scripts"
local UserScripts = home .. "/.config/hypr/UserScripts"

-- -- Helper for active window resizing (works for both floating & tiled windows; no-ops if maximized/fullscreen)
local function resize_active(dx, dy)
    local win = hl.get_active_window()
    if not win then return end
    if win.fullscreen and win.fullscreen ~= 0 and win.fullscreen ~= false then
        return
    end
    if win.fullscreen_client and win.fullscreen_client ~= 0 and win.fullscreen_client ~= false then
        return
    end
    hl.dispatch(hl.dsp.exec_raw(string.format("resizeactive %d %d", dx, dy)))
end

-- 1. App Launchers
hl.bind("SUPER + Return", hl.dsp.exec_cmd("kitty"))
hl.bind("SUPER + E", hl.dsp.exec_cmd("nautilus"))
hl.bind("SUPER + B", hl.dsp.exec_cmd("floorp"))
hl.bind("SUPER + W", hl.dsp.exec_cmd("waypaper"))
hl.bind("SUPER + D", hl.dsp.exec_cmd("pkill rofi || rofi -show drun -theme " .. home .. "/.config/rofi/dashboard.rasi"))
-- Launcher plus its flanking sigil and telemetry panels.
hl.bind("SUPER + CTRL + Return", hl.dsp.exec_cmd(UserScripts .. "/command_deck.sh"))

-- 2. Window State Operations
hl.bind("SUPER + Q", hl.dsp.window.close())
hl.bind("SUPER + C", hl.dsp.window.close())
hl.bind("SUPER + T", hl.dsp.window.float({ action = "toggle" }))
hl.bind("SUPER + SPACE", hl.dsp.window.float({ action = "toggle" }))
hl.bind("SUPER + F", hl.dsp.window.fullscreen())
hl.bind("SUPER + SHIFT + F", hl.dsp.window.fullscreen())

-- Cycle windows (Alt+Tab)
hl.bind("ALT + Tab", hl.dsp.window.cycle_next())
hl.bind("ALT + SHIFT + Tab", hl.dsp.window.cycle_next({ prev = true }))
hl.bind("ALT + code:23", hl.dsp.window.cycle_next())
hl.bind("ALT + SHIFT + code:23", hl.dsp.window.cycle_next({ prev = true }))

-- 3. System Actions & Session Refresh (Super + Alt + R)
hl.bind("SUPER + ALT + R", hl.dsp.exec_cmd("sh -c 'hyprctl reload; pkill -x waybar || true; sleep 0.1; waybar >/dev/null 2>&1 & swaync-client --reload-config 2>/dev/null || true; notify-send \"Desktop Refreshed\" \"Hyprland, Waybar, and SwayNC reloaded.\"'"))
hl.bind("SUPER + SHIFT + R", hl.dsp.exec_cmd("pkill rofi || " .. home .. "/rice-select.sh"))
hl.bind("SUPER + ALT + S", hl.dsp.exec_cmd("pkill rofi || " .. home .. "/rice-select.sh"))
hl.bind("SUPER + ALT + L", hl.dsp.exec_cmd(scriptsDir .. "/LockScreen.sh"))
hl.bind("SUPER + ALT + E", hl.dsp.exec_cmd("pkill rofi || rofimoji"))
hl.bind("SUPER + V", hl.dsp.exec_cmd("pkill rofi || cliphist list | rofi -dmenu | cliphist decode | wl-copy"))
hl.bind("SUPER + ALT + K", hl.dsp.exec_cmd("hyprctl switchxkblayout all next"))
hl.bind("ALT + SHIFT", hl.dsp.exec_cmd("hyprctl switchxkblayout all next"))

-- 4. Night Light Filter (Super + N)
hl.bind("SUPER + N", hl.dsp.exec_cmd("sh -c 'if pgrep -x hyprsunset >/dev/null 2>&1; then pkill -9 -x hyprsunset; notify-send \"Night Light\" \"Disabled\"; else (hyprsunset -t 3000 &) 2>/dev/null; notify-send \"Night Light\" \"Enabled (3000K)\"; fi'"))

-- 5. Screenshots (PrintScreen, Super + P, and modern Super + Shift + S)
hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("sh -c 'mkdir -p ~/Pictures/Screenshots && f=~/Pictures/Screenshots/Screenshot_$(date +%Y%m%d_%H%M%S).png && grim -g \"$(slurp)\" \"$f\" && wl-copy < \"$f\" && notify-send \"Screenshot Captured\" \"Saved to $f\"'"))
hl.bind("SUPER + SHIFT + P", hl.dsp.exec_cmd("sh -c 'mkdir -p ~/Pictures/Screenshots && f=~/Pictures/Screenshots/Screenshot_$(date +%Y%m%d_%H%M%S).png && grim -g \"$(slurp)\" \"$f\" && wl-copy < \"$f\" && notify-send \"Screenshot Captured\" \"Saved to $f\"'"))
hl.bind("SUPER + P", hl.dsp.exec_cmd("sh -c 'mkdir -p ~/Pictures/Screenshots && f=~/Pictures/Screenshots/Screenshot_$(date +%Y%m%d_%H%M%S).png && grim \"$f\" && wl-copy < \"$f\" && notify-send \"Screenshot Captured\" \"Saved to $f\"'"))
hl.bind("Print", hl.dsp.exec_cmd("sh -c 'mkdir -p ~/Pictures/Screenshots && f=~/Pictures/Screenshots/Screenshot_$(date +%Y%m%d_%H%M%S).png && grim \"$f\" && wl-copy < \"$f\" && notify-send \"Screenshot Captured\" \"Saved to $f\"'"))
hl.bind("SHIFT + Print", hl.dsp.exec_cmd("sh -c 'mkdir -p ~/Pictures/Screenshots && f=~/Pictures/Screenshots/Screenshot_$(date +%Y%m%d_%H%M%S).png && grim -g \"$(slurp)\" \"$f\" && wl-copy < \"$f\" && notify-send \"Screenshot Captured\" \"Saved to $f\"'"))

-- 6. Audio Volume & Media Playback (with SwayNC OSD notifications)
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("sh -c 'wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+ || pamixer -i 5; vol=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk \"{print int(\\$2 * 100)}\"); notify-send -e -h int:value:\"$vol\" -h string:x-canonical-private-synchronous:volume_notif -u low \"Volume: ${vol}%\"'"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("sh -c 'wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- || pamixer -d 5; vol=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk \"{print int(\\$2 * 100)}\"); notify-send -e -h int:value:\"$vol\" -h string:x-canonical-private-synchronous:volume_notif -u low \"Volume: ${vol}%\"'"), { locked = true, repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("sh -c 'wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle || pamixer -t; notify-send -e -h string:x-canonical-private-synchronous:volume_notif -u low \"Mute Toggled\"'"), { locked = true, repeating = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("sh -c 'wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle; notify-send -e -u low \"Mic Mute Toggled\"'"), { locked = true, repeating = true })

hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("sh -c 'playerctl play-pause; sleep 0.1; title=$(playerctl metadata title 2>/dev/null); notify-send -e -u low -i \"$HOME/.config/swaync/icons/music.png\" \"Playback Toggled\" \"$title\"'"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("sh -c 'playerctl play-pause; sleep 0.1; title=$(playerctl metadata title 2>/dev/null); notify-send -e -u low -i \"$HOME/.config/swaync/icons/music.png\" \"Playback Toggled\" \"$title\"'"), { locked = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("sh -c 'playerctl next; sleep 0.1; title=$(playerctl metadata title 2>/dev/null); notify-send -e -u low -i \"$HOME/.config/swaync/icons/music.png\" \"Next Track\" \"$title\"'"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("sh -c 'playerctl previous; sleep 0.1; title=$(playerctl metadata title 2>/dev/null); notify-send -e -u low -i \"$HOME/.config/swaync/icons/music.png\" \"Previous Track\" \"$title\"'"), { locked = true })

-- 7. Brightness Controls
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl set +5%"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl set 5%-"), { locked = true, repeating = true })

-- 8. Move focus with arrow keys / HJKL
-- Each combo must be bound exactly once. Hyprland resolves keysyms case-insensitively
-- and then runs every bind that matches, so a "Left" + "left" pair moves focus twice
-- per keypress. "Left" alone already matches both cases.
hl.bind("SUPER + Left",  hl.dsp.focus({ direction = "left" }))
hl.bind("SUPER + Right", hl.dsp.focus({ direction = "right" }))
hl.bind("SUPER + Up",    hl.dsp.focus({ direction = "up" }))
hl.bind("SUPER + Down",  hl.dsp.focus({ direction = "down" }))

hl.bind("ALT + Left",  hl.dsp.focus({ direction = "left" }))
hl.bind("ALT + Right", hl.dsp.focus({ direction = "right" }))
hl.bind("ALT + Up",    hl.dsp.focus({ direction = "up" }))
hl.bind("ALT + Down",  hl.dsp.focus({ direction = "down" }))

hl.bind("SUPER + H", hl.dsp.focus({ direction = "left" }))
hl.bind("SUPER + L", hl.dsp.focus({ direction = "right" }))
hl.bind("SUPER + K", hl.dsp.focus({ direction = "up" }))
hl.bind("SUPER + J", hl.dsp.focus({ direction = "down" }))

hl.bind("ALT + H", hl.dsp.focus({ direction = "left" }))
hl.bind("ALT + L", hl.dsp.focus({ direction = "right" }))
hl.bind("ALT + K", hl.dsp.focus({ direction = "up" }))
hl.bind("ALT + J", hl.dsp.focus({ direction = "down" }))

-- 9. Window Resizing (Continuous Keyboard Resizing for Floating & Tiled)
-- Direct keybinds: Super + Shift + Arrows
hl.bind("SUPER + SHIFT + Left", function() resize_active(-60, 0) end, { repeating = true })
hl.bind("SUPER + SHIFT + Right", function() resize_active(60, 0) end, { repeating = true })
hl.bind("SUPER + SHIFT + Up", function() resize_active(0, -60) end, { repeating = true })
hl.bind("SUPER + SHIFT + Down", function() resize_active(0, 60) end, { repeating = true })

-- Ergonomic Ctrl + Arrow & Ctrl + HJKL resizing
hl.bind("SUPER + CTRL + Left", function() resize_active(-60, 0) end, { repeating = true })
hl.bind("SUPER + CTRL + Right", function() resize_active(60, 0) end, { repeating = true })
hl.bind("SUPER + CTRL + Up", function() resize_active(0, -60) end, { repeating = true })
hl.bind("SUPER + CTRL + Down", function() resize_active(0, 60) end, { repeating = true })
hl.bind("SUPER + CTRL + H", function() resize_active(-60, 0) end, { repeating = true })
hl.bind("SUPER + CTRL + L", function() resize_active(60, 0) end, { repeating = true })
hl.bind("SUPER + CTRL + K", function() resize_active(0, -60) end, { repeating = true })
hl.bind("SUPER + CTRL + J", function() resize_active(0, 60) end, { repeating = true })

-- Dedicated Resize Submap (Super + R)
hl.define_submap("resize", function()
    hl.bind("Right", function() resize_active(40, 0) end, { repeating = true })
    hl.bind("Left", function() resize_active(-40, 0) end, { repeating = true })
    hl.bind("Up", function() resize_active(0, -40) end, { repeating = true })
    hl.bind("Down", function() resize_active(0, 40) end, { repeating = true })
    hl.bind("l", function() resize_active(40, 0) end, { repeating = true })
    hl.bind("h", function() resize_active(-40, 0) end, { repeating = true })
    hl.bind("k", function() resize_active(0, -40) end, { repeating = true })
    hl.bind("j", function() resize_active(0, 40) end, { repeating = true })

    hl.bind("SHIFT + Right", function() resize_active(80, 0) end, { repeating = true })
    hl.bind("SHIFT + Left", function() resize_active(-80, 0) end, { repeating = true })
    hl.bind("SHIFT + Up", function() resize_active(0, -80) end, { repeating = true })
    hl.bind("SHIFT + Down", function() resize_active(0, 80) end, { repeating = true })

    hl.bind("Escape", hl.dsp.submap("reset"))
    hl.bind("Return", hl.dsp.submap("reset"))
end)
hl.bind("SUPER + R", hl.dsp.submap("resize"))

-- 10. Window Moving (Super + Alt + Arrows & Super + Shift + HJKL)
hl.bind("SUPER + ALT + Left", hl.dsp.exec_raw("movewindow l"))
hl.bind("SUPER + ALT + Right", hl.dsp.exec_raw("movewindow r"))
hl.bind("SUPER + ALT + Up", hl.dsp.exec_raw("movewindow u"))
hl.bind("SUPER + ALT + Down", hl.dsp.exec_raw("movewindow d"))
hl.bind("SUPER + SHIFT + H", hl.dsp.exec_raw("swapwindow l"))
hl.bind("SUPER + SHIFT + L", hl.dsp.exec_raw("swapwindow r"))
hl.bind("SUPER + SHIFT + K", hl.dsp.exec_raw("swapwindow u"))
hl.bind("SUPER + SHIFT + J", hl.dsp.exec_raw("swapwindow d"))

-- 11. Mouse Window Moving & Resizing (Super + Left/Right Drag)
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- 12. Workspaces (1-10)
-- Bound by keysym name only: this Hyprland build silently drops "code:NN" binds.
for i = 1, 10 do
    local num = tostring(i == 10 and 0 or i)
    hl.bind("SUPER + " .. num, hl.dsp.focus({ workspace = tostring(i) }))
    hl.bind("SUPER + SHIFT + " .. num, hl.dsp.window.move({ workspace = tostring(i) }))
end

-- Keypad workspaces. A keypad key emits a different keysym depending on NumLock (and
-- Shift inverts it), so both names are bound for each workspace to cover every state.
local keypad_keys = {
    [1]  = { "KP_1", "KP_End" },
    [2]  = { "KP_2", "KP_Down" },
    [3]  = { "KP_3", "KP_Next" },
    [4]  = { "KP_4", "KP_Left" },
    [5]  = { "KP_5", "KP_Begin" },
    [6]  = { "KP_6", "KP_Right" },
    [7]  = { "KP_7", "KP_Home" },
    [8]  = { "KP_8", "KP_Up" },
    [9]  = { "KP_9", "KP_Prior" },
    [10] = { "KP_0", "KP_Insert" },
}
for ws, keys in pairs(keypad_keys) do
    for _, key in ipairs(keys) do
        hl.bind("SUPER + " .. key, hl.dsp.focus({ workspace = tostring(ws) }))
        hl.bind("SUPER + SHIFT + " .. key, hl.dsp.window.move({ workspace = tostring(ws) }))
    end
end

-- Mouse scroll workspace cycling
hl.bind("SUPER + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind("SUPER + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

hl.window_rule({
    name = "widget-pixel-art",
    match = { title = "^(pixel-art-widget)$" },
    float = true,
    move = "cursor -50% -50%",
    pin = true,
    opacity = "1.0 1.0",
})

-- Command Deck: pinned wings flanking the centred app launcher. Sized off
-- monitor_w/monitor_h so the deck lays out identically on every output.
local wallust = require("UserConfigs.wallust")
local deck_border = wallust.get("color12", "rgb(D4AF37)") .. " " .. wallust.get("color4", "rgb(16161D)")

hl.window_rule({
    name = "imperium-deck-sigil",
    match = { class = "^(imperium-sigil)$" },
    float = true,
    size = "(monitor_w*0.23) (monitor_h*0.62)",
    move = "(monitor_w*0.04) (monitor_h*0.19)",
    pin = true,
    no_initial_focus = true,
    rounding = 0,
    border_color = deck_border,
    animation = "popin",
})

hl.window_rule({
    name = "imperium-deck-telemetry",
    match = { class = "^(imperium-telemetry)$" },
    float = true,
    size = "(monitor_w*0.25) (monitor_h*0.62)",
    move = "(monitor_w*0.71) (monitor_h*0.19)",
    pin = true,
    no_initial_focus = true,
    rounding = 0,
    border_color = deck_border,
    animation = "popin",
})
