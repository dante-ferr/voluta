-- Complete Hyprland Lua Keybindings
---@module 'hl'

local home = os.getenv("HOME") or ""
local scriptsDir = home .. "/.config/hypr/scripts"
local UserScripts = home .. "/.config/hypr/UserScripts"

local settings = require("configs.Voluta")
local seen = {}
local function has_trigger(chord)
    if type(chord) ~= "string" then return false end
    for part in chord:gmatch("[^+]+") do
        local token = part:match("^%s*(.-)%s*$"):upper()
        if token ~= "" and token ~= "SUPER" and token ~= "CTRL"
            and token ~= "CONTROL" and token ~= "ALT" and token ~= "SHIFT" then
            return true
        end
    end
    return false
end
local function bind(chord, dispatcher, options)
    -- A malformed private override must not abort loading every later bind.
    if not has_trigger(chord) then
        print("[Voluta] Skipping keybinding without a trigger")
        return
    end
    seen[chord] = true
    local choice = settings.keybindings[chord]
    if choice == false then return end
    if type(choice) == "string" then dispatcher = hl.dsp.exec_cmd(choice) end
    hl.bind(chord, dispatcher, options)
end
local riceSelect = "voluta rice-switch"

-- Pixels added or removed per resize keypress; holding the key repeats it.
local RESIZE_STEP = 120

-- Helper for active window resizing (works for both floating & tiled windows; no-ops if maximized/fullscreen).
-- Must use hl.dsp.window.resize: hl.dsp.exec_raw accepts any string but never runs it.
local function resize_active(dx, dy)
    local win = hl.get_active_window()
    if not win then return end
    if win.fullscreen and win.fullscreen ~= 0 and win.fullscreen ~= false then
        return
    end
    if win.fullscreen_client and win.fullscreen_client ~= 0 and win.fullscreen_client ~= false then
        return
    end
    hl.dispatch(hl.dsp.window.resize({ x = dx, y = dy, relative = true }))
end

-- 1. App Launchers
bind("SUPER + Return", hl.dsp.exec_cmd(settings.apps.terminal or "kitty"))
bind("SUPER + E", hl.dsp.exec_cmd(settings.apps.file_manager or "dolphin"))
bind("SUPER + B", hl.dsp.exec_cmd(settings.apps.browser or "gtk-launch firefox"))
bind("SUPER + W", hl.dsp.exec_cmd("waypaper"))
bind("SUPER + D", hl.dsp.exec_cmd(home .. "/.config/rofi/launch-dashboard.sh"))
bind("SUPER + SHIFT + Return", hl.dsp.exec_cmd(home .. "/.config/rofi/launch-dashboard.sh"))
-- Launcher menu.
bind("SUPER + CTRL + Return", hl.dsp.exec_cmd(UserScripts .. "/command_deck.sh"))
bind("SUPER + I", hl.dsp.exec_cmd(UserScripts .. "/system_hud.sh"))
bind("SUPER + CTRL + T", hl.dsp.exec_cmd(UserScripts .. "/system_hud.sh"))
bind("SUPER + SHIFT + M", hl.dsp.exec_cmd("kitty --class system-monitor -e btop"))
if settings.enabled("rgb") then
    bind("SUPER + G", hl.dsp.exec_cmd("voluta rgb menu"))
    bind("SUPER + CTRL + G", hl.dsp.exec_cmd(UserScripts .. "/pixel-widget.sh"))
else
    bind("SUPER + G", hl.dsp.exec_cmd(UserScripts .. "/pixel-widget.sh"))
end
if settings.enabled("obs") then
    bind("SUPER + KP_Add", hl.dsp.exec_cmd("obs-cmd recording toggle"))
end

-- Config shortcuts
bind("CTRL + SUPER + Slash", hl.dsp.exec_cmd("xdg-open ~/.config/voluta/settings.json"))
bind("CTRL + SUPER + ALT + Slash", hl.dsp.exec_cmd("xdg-open ~/.config/hypr/UserConfigs/UserKeybinds.lua"))

-- Display layout profiles (nwg-displays)
for _, chord in ipairs({"SUPER + F1", "SUPER + F2", "SUPER + F3"}) do
    if type(settings.keybindings[chord]) == "string" then
        bind(chord, hl.dsp.exec_cmd(settings.keybindings[chord]))
    end
end

-- 2. Window State Operations
bind("SUPER + Q", hl.dsp.window.close())
bind("SUPER + C", hl.dsp.window.close())
bind("SUPER + T", hl.dsp.window.float({ action = "toggle" }))
bind("SUPER + SPACE", hl.dsp.window.float({ action = "toggle" }))
-- Maximized keeps gaps_out and reserved space (waybar); real fullscreen covers everything.
bind("SUPER + F", hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }))
bind("SUPER + SHIFT + F", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))

-- Cycle windows (Alt+Tab)
bind("ALT + Tab", hl.dsp.window.cycle_next())
bind("ALT + SHIFT + Tab", hl.dsp.window.cycle_next({ prev = true }))
bind("ALT + code:23", hl.dsp.window.cycle_next())
bind("ALT + SHIFT + code:23", hl.dsp.window.cycle_next({ prev = true }))

-- 3. System Actions & Session Refresh (Super + Alt + R)
bind("SUPER + ALT + R", hl.dsp.exec_cmd(scriptsDir .. "/Refresh.sh"))
if settings.enabled("rice_switch") then
    bind("SUPER + SHIFT + R", hl.dsp.exec_cmd(riceSelect))
end
if settings.enabled("rice_switch") then
    bind("SUPER + ALT + S", hl.dsp.exec_cmd(riceSelect))
end
bind("SUPER + ALT + L", hl.dsp.exec_cmd(scriptsDir .. "/LockScreen.sh"), { locked = true })
bind("SUPER + ALT + E", hl.dsp.exec_cmd(scriptsDir .. "/RofiPicker.sh emoji"))
bind("SUPER + period", hl.dsp.exec_cmd(scriptsDir .. "/RofiPicker.sh emoji"))
bind("SUPER + comma", hl.dsp.exec_cmd(scriptsDir .. "/RofiPicker.sh symbols"))
bind("SUPER + V", hl.dsp.exec_cmd("pkill rofi || cliphist list | rofi -dmenu | cliphist decode | wl-copy"))
bind("SUPER + ALT + K", hl.dsp.exec_cmd("hyprctl switchxkblayout all next"))

-- 4. Notifications and Night Light
bind("SUPER + N", hl.dsp.exec_cmd("sh " .. home .. "/.config/swaync/toggle-panel.sh"))
bind("SUPER + M", hl.dsp.exec_cmd("sh " .. home .. "/.config/music/toggle.sh"))
bind("SUPER + O", hl.dsp.exec_cmd("sh " .. home .. "/.config/session-menu/toggle.sh"))
bind("SUPER + SHIFT + N", hl.dsp.exec_cmd("sh -c 'if pgrep -x hyprsunset >/dev/null 2>&1; then pkill -9 -x hyprsunset; notify-send \"Night Light\" \"Disabled\"; else (hyprsunset -t 3000 &) 2>/dev/null; notify-send \"Night Light\" \"Enabled (3000K)\"; fi'"))

-- 5. Screenshots (PrintScreen, Super + P, and modern Super + Shift + S)
bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("sh -c 'mkdir -p ~/Pictures/Screenshots && f=~/Pictures/Screenshots/Screenshot_$(date +%Y%m%d_%H%M%S).png && grim -g \"$(slurp)\" \"$f\" && wl-copy < \"$f\" && notify-send \"Screenshot Captured\" \"Saved to $f\"'"))
bind("SUPER + SHIFT + P", hl.dsp.exec_cmd("sh -c 'mkdir -p ~/Pictures/Screenshots && f=~/Pictures/Screenshots/Screenshot_$(date +%Y%m%d_%H%M%S).png && grim -g \"$(slurp)\" \"$f\" && wl-copy < \"$f\" && notify-send \"Screenshot Captured\" \"Saved to $f\"'"))
bind("SUPER + P", hl.dsp.exec_cmd("sh -c 'mkdir -p ~/Pictures/Screenshots && f=~/Pictures/Screenshots/Screenshot_$(date +%Y%m%d_%H%M%S).png && grim \"$f\" && wl-copy < \"$f\" && notify-send \"Screenshot Captured\" \"Saved to $f\"'"))
bind("Print", hl.dsp.exec_cmd("sh -c 'mkdir -p ~/Pictures/Screenshots && f=~/Pictures/Screenshots/Screenshot_$(date +%Y%m%d_%H%M%S).png && grim \"$f\" && wl-copy < \"$f\" && notify-send \"Screenshot Captured\" \"Saved to $f\"'"))
bind("SHIFT + Print", hl.dsp.exec_cmd("sh -c 'mkdir -p ~/Pictures/Screenshots && f=~/Pictures/Screenshots/Screenshot_$(date +%Y%m%d_%H%M%S).png && grim -g \"$(slurp)\" \"$f\" && wl-copy < \"$f\" && notify-send \"Screenshot Captured\" \"Saved to $f\"'"))
bind("SUPER + SHIFT + T", hl.dsp.exec_cmd(scriptsDir .. "/ScreenShot.sh --text"))

-- 6. Audio Volume & Media Playback (with SwayNC OSD notifications)
-- Speaker mute must target the sink. The previous XF86AudioMute bind
-- toggled DEFAULT_AUDIO_SOURCE, so Fn+mute flipped the microphone instead.
-- Volume up/down go through Volume.sh so they also unmute a muted sink.
bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd(scriptsDir .. "/Volume.sh --inc"), { locked = true, repeating = true })
bind("XF86AudioLowerVolume", hl.dsp.exec_cmd(scriptsDir .. "/Volume.sh --dec"), { locked = true, repeating = true })
bind("XF86AudioMute", hl.dsp.exec_cmd(scriptsDir .. "/Volume.sh --toggle"), { locked = true, repeating = true })
bind("XF86AudioMicMute", hl.dsp.exec_cmd(scriptsDir .. "/Volume.sh --toggle-mic"), { locked = true, repeating = true })

bind("XF86AudioPlay", hl.dsp.exec_cmd("sh -c 'playerctl play-pause; sleep 0.1; title=$(playerctl metadata title 2>/dev/null); notify-send -e -u low -i \"$HOME/.config/swaync/icons/music.png\" \"Playback Toggled\" \"$title\"'"), { locked = true })
bind("XF86AudioPause", hl.dsp.exec_cmd("sh -c 'playerctl play-pause; sleep 0.1; title=$(playerctl metadata title 2>/dev/null); notify-send -e -u low -i \"$HOME/.config/swaync/icons/music.png\" \"Playback Toggled\" \"$title\"'"), { locked = true })
bind("XF86AudioNext", hl.dsp.exec_cmd("sh -c 'playerctl next; sleep 0.1; title=$(playerctl metadata title 2>/dev/null); notify-send -e -u low -i \"$HOME/.config/swaync/icons/music.png\" \"Next Track\" \"$title\"'"), { locked = true })
bind("XF86AudioPrev", hl.dsp.exec_cmd("sh -c 'playerctl previous; sleep 0.1; title=$(playerctl metadata title 2>/dev/null); notify-send -e -u low -i \"$HOME/.config/swaync/icons/music.png\" \"Previous Track\" \"$title\"'"), { locked = true })

-- 7. Brightness Controls
bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl set +5%"), { locked = true, repeating = true })
bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl set 5%-"), { locked = true, repeating = true })

-- 8. Move focus with arrow keys / HJKL
-- Each combo must be bound exactly once. Hyprland resolves keysyms case-insensitively
-- and then runs every bind that matches, so a "Left" + "left" pair moves focus twice
-- per keypress. "Left" alone already matches both cases.
bind("SUPER + Left",  hl.dsp.focus({ direction = "left" }))
bind("SUPER + Right", hl.dsp.focus({ direction = "right" }))
bind("SUPER + Up",    hl.dsp.focus({ direction = "up" }))
bind("SUPER + Down",  hl.dsp.focus({ direction = "down" }))

bind("ALT + Left",  hl.dsp.focus({ direction = "left" }))
bind("ALT + Right", hl.dsp.focus({ direction = "right" }))
bind("ALT + Up",    hl.dsp.focus({ direction = "up" }))
bind("ALT + Down",  hl.dsp.focus({ direction = "down" }))

bind("SUPER + H", hl.dsp.focus({ direction = "left" }))
bind("SUPER + L", hl.dsp.focus({ direction = "right" }))
bind("SUPER + K", hl.dsp.focus({ direction = "up" }))
bind("SUPER + J", hl.dsp.focus({ direction = "down" }))

bind("ALT + H", hl.dsp.focus({ direction = "left" }))
bind("ALT + L", hl.dsp.focus({ direction = "right" }))
bind("ALT + K", hl.dsp.focus({ direction = "up" }))
bind("ALT + J", hl.dsp.focus({ direction = "down" }))

-- 9. Window Resizing (Continuous Keyboard Resizing for Floating & Tiled)
-- Direct keybinds: Super + Shift + Arrows
bind("SUPER + SHIFT + Left", function() resize_active(-RESIZE_STEP, 0) end, { repeating = true })
bind("SUPER + SHIFT + Right", function() resize_active(RESIZE_STEP, 0) end, { repeating = true })
bind("SUPER + SHIFT + Up", function() resize_active(0, -RESIZE_STEP) end, { repeating = true })
bind("SUPER + SHIFT + Down", function() resize_active(0, RESIZE_STEP) end, { repeating = true })

-- Ergonomic Ctrl + Arrow & Ctrl + HJKL resizing
bind("SUPER + CTRL + Left", function() resize_active(-RESIZE_STEP, 0) end, { repeating = true })
bind("SUPER + CTRL + Right", function() resize_active(RESIZE_STEP, 0) end, { repeating = true })
bind("SUPER + CTRL + Up", function() resize_active(0, -RESIZE_STEP) end, { repeating = true })
bind("SUPER + CTRL + Down", function() resize_active(0, RESIZE_STEP) end, { repeating = true })
bind("SUPER + CTRL + H", function() resize_active(-RESIZE_STEP, 0) end, { repeating = true })
bind("SUPER + CTRL + L", function() resize_active(RESIZE_STEP, 0) end, { repeating = true })
bind("SUPER + CTRL + K", function() resize_active(0, -RESIZE_STEP) end, { repeating = true })
bind("SUPER + CTRL + J", function() resize_active(0, RESIZE_STEP) end, { repeating = true })

-- 10. Window Moving (Super + Alt + Arrows & Super + Shift + HJKL)
bind("SUPER + ALT + Left", hl.dsp.window.move({ direction = "left" }))
bind("SUPER + ALT + Right", hl.dsp.window.move({ direction = "right" }))
bind("SUPER + ALT + Up", hl.dsp.window.move({ direction = "up" }))
bind("SUPER + ALT + Down", hl.dsp.window.move({ direction = "down" }))
bind("SUPER + SHIFT + H", hl.dsp.window.swap({ direction = "left" }))
bind("SUPER + SHIFT + L", hl.dsp.window.swap({ direction = "right" }))
bind("SUPER + SHIFT + K", hl.dsp.window.swap({ direction = "up" }))
bind("SUPER + SHIFT + J", hl.dsp.window.swap({ direction = "down" }))

-- 11. Mouse Window Moving & Resizing (Super + Left/Right Drag)
bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true })
bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- 12. Workspaces (1-10)
-- Bound by keysym name only: this Hyprland build silently drops "code:NN" binds.
for i = 1, 10 do
    local num = tostring(i == 10 and 0 or i)
    bind("SUPER + " .. num, hl.dsp.focus({ workspace = tostring(i) }))
    bind("SUPER + SHIFT + " .. num, hl.dsp.window.move({ workspace = tostring(i) }))
end

-- Special Workspace (Scratchpad - Super + U)
bind("SUPER + U", hl.dsp.workspace.toggle_special())
bind("SUPER + SHIFT + U", hl.dsp.window.move({ workspace = "special" }))
bind("SUPER + CTRL + U", hl.dsp.window.move({ workspace = "special", silent = true }))


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
        bind("SUPER + " .. key, hl.dsp.focus({ workspace = tostring(ws) }))
        bind("SUPER + SHIFT + " .. key, hl.dsp.window.move({ workspace = tostring(ws) }))
    end
end

-- Mouse scroll workspace cycling
bind("SUPER + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
bind("SUPER + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

-- Kitty (and some other apps) request maximize on map. Without this, Super+Return
-- opens a maximized window instead of tiling into the dwindle grid.
hl.window_rule({
    name = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})

hl.window_rule({
    name = "widget-pixel-art",
    match = { title = "^(pixel-art-widget)$" },
    float = true,
    move = "cursor -50% -50%",
    pin = true,
    opacity = "1.0 1.0",
})

-- App Open/Save dialogs float; regular Dolphin windows use the normal layout.
hl.window_rule({
    name = "kde-file-picker-floating",
    match = { class = "^(org\\.freedesktop\\.impl\\.portal\\.desktop\\.kde|xdg-desktop-portal-kde|org\\.kde\\.xdg-desktop-portal-kde)$" },
    float = true,
})



-- Float, center, and resize volume control (pavucontrol) and network connection editor (nm-connection-editor)
hl.window_rule({
    name = "waybar-volume-menu",
    match = { class = "^(pavucontrol|pavucontrol-qt|org.pulseaudio.pavucontrol|com.saivert.pwvucontrol)$" },
    float = true,
    size = "900 650",
    center = true,
})

hl.window_rule({
    name = "waybar-network-menu",
    match = { class = "^(nm-connection-editor|nm-applet)$" },
    float = true,
    size = "900 650",
    center = true,
})

hl.window_rule({
    name = "waybar-bluetooth-menu",
    match = { class = "^(blueman-manager|\\.blueman-manager-wrapped)$" },
    float = true,
    size = "700 500",
    center = true,
})

hl.window_rule({
    name = "waybar-calendar",
    match = { class = "^gsimplecal$" },
    float = true,
    center = true,
    border_size = 0,
    no_shadow = true,
})

-- New personal bindings are additive; matching chords replace defaults above.
for chord, command in pairs(settings.keybindings) do
    if has_trigger(chord) and not seen[chord] and type(command) == "string" then
        hl.bind(chord, hl.dsp.exec_cmd(command))
    end
end
