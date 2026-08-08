-- Main Keybinds Configuration for Hyprland Lua
---@module 'hl'

local home = os.getenv("HOME") or "/home/dante"
local scriptsDir = home .. "/.config/hypr/scripts"
local UserScripts = home .. "/.config/hypr/UserScripts"

-- Core System Actions
hl.bind("SUPER + ALT + R", hl.dsp.exec_cmd(scriptsDir .. "/Refresh.sh"))
hl.bind("SUPER + ALT + E", hl.dsp.exec_cmd("pkill rofi || rofimoji"))
hl.bind("SUPER + V", hl.dsp.exec_cmd("pkill rofi || cliphist list | rofi -dmenu | cliphist decode | wl-copy"))

-- Screenshots (Super + P and standard PrintScreen key)
hl.bind("SUPER + P", hl.dsp.exec_cmd(scriptsDir .. "/ScreenShot.sh --now"))
hl.bind("SUPER + SHIFT + P", hl.dsp.exec_cmd(scriptsDir .. "/ScreenShot.sh --area"))
hl.bind("SUPER + CTRL + P", hl.dsp.exec_cmd(scriptsDir .. "/ScreenShot.sh --in5"))
hl.bind("SUPER + ALT + P", hl.dsp.exec_cmd(scriptsDir .. "/ScreenShot.sh --active"))

hl.bind("Print", hl.dsp.exec_cmd(scriptsDir .. "/ScreenShot.sh --now"))
hl.bind("SHIFT + Print", hl.dsp.exec_cmd(scriptsDir .. "/ScreenShot.sh --area"))
hl.bind("CTRL + Print", hl.dsp.exec_cmd(scriptsDir .. "/ScreenShot.sh --in5"))
hl.bind("ALT + Print", hl.dsp.exec_cmd(scriptsDir .. "/ScreenShot.sh --active"))

-- Audio & Volume Controls (with SwayNC animated OSD notifications)
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd(scriptsDir .. "/Volume.sh --inc"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd(scriptsDir .. "/Volume.sh --dec"), { locked = true, repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd(scriptsDir .. "/Volume.sh --toggle"), { locked = true, repeating = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd(scriptsDir .. "/Volume.sh --toggle-mic"), { locked = true, repeating = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd(scriptsDir .. "/MediaCtrl.sh --pause"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd(scriptsDir .. "/MediaCtrl.sh --pause"), { locked = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd(scriptsDir .. "/MediaCtrl.sh --nxt"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd(scriptsDir .. "/MediaCtrl.sh --prv"), { locked = true })

-- Brightness Controls (XF86 Keys)
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl set +5%"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl set 5%-"), { locked = true, repeating = true })

-- Focus movement (hjkl & arrows)
hl.bind("SUPER + Left", function() hl.dispatch(hl.dsp.exec_raw("movefocus", "l")) end)
hl.bind("SUPER + Right", function() hl.dispatch(hl.dsp.exec_raw("movefocus", "r")) end)
hl.bind("SUPER + Up", function() hl.dispatch(hl.dsp.exec_raw("movefocus", "u")) end)
hl.bind("SUPER + Down", function() hl.dispatch(hl.dsp.exec_raw("movefocus", "d")) end)

hl.bind("SUPER + left", function() hl.dispatch(hl.dsp.exec_raw("movefocus", "l")) end)
hl.bind("SUPER + right", function() hl.dispatch(hl.dsp.exec_raw("movefocus", "r")) end)
hl.bind("SUPER + up", function() hl.dispatch(hl.dsp.exec_raw("movefocus", "u")) end)
hl.bind("SUPER + down", function() hl.dispatch(hl.dsp.exec_raw("movefocus", "d")) end)

hl.bind("SUPER + code:113", function() hl.dispatch(hl.dsp.exec_raw("movefocus", "l")) end)
hl.bind("SUPER + code:114", function() hl.dispatch(hl.dsp.exec_raw("movefocus", "r")) end)
hl.bind("SUPER + code:111", function() hl.dispatch(hl.dsp.exec_raw("movefocus", "u")) end)
hl.bind("SUPER + code:116", function() hl.dispatch(hl.dsp.exec_raw("movefocus", "d")) end)

hl.bind("ALT + Left", function() hl.dispatch(hl.dsp.exec_raw("movefocus", "l")) end)
hl.bind("ALT + Right", function() hl.dispatch(hl.dsp.exec_raw("movefocus", "r")) end)
hl.bind("ALT + Up", function() hl.dispatch(hl.dsp.exec_raw("movefocus", "u")) end)
hl.bind("ALT + Down", function() hl.dispatch(hl.dsp.exec_raw("movefocus", "d")) end)

hl.bind("ALT + left", function() hl.dispatch(hl.dsp.exec_raw("movefocus", "l")) end)
hl.bind("ALT + right", function() hl.dispatch(hl.dsp.exec_raw("movefocus", "r")) end)
hl.bind("ALT + up", function() hl.dispatch(hl.dsp.exec_raw("movefocus", "u")) end)
hl.bind("ALT + down", function() hl.dispatch(hl.dsp.exec_raw("movefocus", "d")) end)

hl.bind("ALT + code:113", function() hl.dispatch(hl.dsp.exec_raw("movefocus", "l")) end)
hl.bind("ALT + code:114", function() hl.dispatch(hl.dsp.exec_raw("movefocus", "r")) end)
hl.bind("ALT + code:111", function() hl.dispatch(hl.dsp.exec_raw("movefocus", "u")) end)
hl.bind("ALT + code:116", function() hl.dispatch(hl.dsp.exec_raw("movefocus", "d")) end)

hl.bind("SUPER + H", function() hl.dispatch(hl.dsp.exec_raw("movefocus", "l")) end)
hl.bind("SUPER + L", function() hl.dispatch(hl.dsp.exec_raw("movefocus", "r")) end)
hl.bind("SUPER + K", function() hl.dispatch(hl.dsp.exec_raw("movefocus", "u")) end)
hl.bind("SUPER + J", function() hl.dispatch(hl.dsp.exec_raw("movefocus", "d")) end)

hl.bind("SUPER + h", function() hl.dispatch(hl.dsp.exec_raw("movefocus", "l")) end)
hl.bind("SUPER + l", function() hl.dispatch(hl.dsp.exec_raw("movefocus", "r")) end)
hl.bind("SUPER + k", function() hl.dispatch(hl.dsp.exec_raw("movefocus", "u")) end)
hl.bind("SUPER + j", function() hl.dispatch(hl.dsp.exec_raw("movefocus", "d")) end)

hl.bind("ALT + H", function() hl.dispatch(hl.dsp.exec_raw("movefocus", "l")) end)
hl.bind("ALT + L", function() hl.dispatch(hl.dsp.exec_raw("movefocus", "r")) end)
hl.bind("ALT + K", function() hl.dispatch(hl.dsp.exec_raw("movefocus", "u")) end)
hl.bind("ALT + J", function() hl.dispatch(hl.dsp.exec_raw("movefocus", "d")) end)

hl.bind("ALT + h", function() hl.dispatch(hl.dsp.exec_raw("movefocus", "l")) end)
hl.bind("ALT + l", function() hl.dispatch(hl.dsp.exec_raw("movefocus", "r")) end)
hl.bind("ALT + k", function() hl.dispatch(hl.dsp.exec_raw("movefocus", "u")) end)
hl.bind("ALT + j", function() hl.dispatch(hl.dsp.exec_raw("movefocus", "d")) end)

-- Alt + Tab: Window Switching (cyclenext & bringactivetotop)
hl.bind("ALT + Tab", function()
    hl.dispatch(hl.dsp.exec_raw("cyclenext", ""))
    hl.dispatch(hl.dsp.exec_raw("bringactivetotop", ""))
end)
hl.bind("ALT + SHIFT + Tab", function()
    hl.dispatch(hl.dsp.exec_raw("cyclenext", "prev"))
    hl.dispatch(hl.dsp.exec_raw("bringactivetotop", ""))
end)
hl.bind("ALT + code:23", function()
    hl.dispatch(hl.dsp.exec_raw("cyclenext", ""))
    hl.dispatch(hl.dsp.exec_raw("bringactivetotop", ""))
end)
hl.bind("ALT + SHIFT + code:23", function()
    hl.dispatch(hl.dsp.exec_raw("cyclenext", "prev"))
    hl.dispatch(hl.dsp.exec_raw("bringactivetotop", ""))
end)

-- Swap windows
hl.bind("SUPER + SHIFT + H", hl.dsp.exec_raw("swapwindow l"))
hl.bind("SUPER + SHIFT + L", hl.dsp.exec_raw("swapwindow r"))
hl.bind("SUPER + SHIFT + K", hl.dsp.exec_raw("swapwindow u"))
hl.bind("SUPER + SHIFT + J", hl.dsp.exec_raw("swapwindow d"))

-- Window Resizing (Super + Shift + Arrows with repeating)
hl.bind("SUPER + SHIFT + Left", hl.dsp.exec_raw("resizeactive -60 0"), { repeating = true })
hl.bind("SUPER + SHIFT + Right", hl.dsp.exec_raw("resizeactive 60 0"), { repeating = true })
hl.bind("SUPER + SHIFT + Up", hl.dsp.exec_raw("resizeactive 0 -60"), { repeating = true })
hl.bind("SUPER + SHIFT + Down", hl.dsp.exec_raw("resizeactive 0 60"), { repeating = true })

-- Mouse Window Moving & Resizing
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })
