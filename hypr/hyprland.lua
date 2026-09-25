-- Hyprland Master Lua Configuration
---@module 'hl'



local hypr_dir = (os.getenv("HOME") or "/home/dante") .. "/.config/hypr"
package.path = hypr_dir .. "/?.lua;" .. hypr_dir .. "/?/init.lua;" .. package.path

local function load_module(mod_name)
    package.loaded[mod_name] = nil
    local ok, err = pcall(require, mod_name)
    if not ok then
        print(string.format("[Hyprland.lua] Error loading %s: %s", mod_name, tostring(err)))
    end
end

-- UserDecorations and UserKeybinds require() this. The Lua VM survives
-- hyprctl reload, so a cached module would keep the previous wallpaper's
-- palette on borders and window rules.
package.loaded["UserConfigs.wallust"] = nil

-- 1. Visuals, Animations & Decorations
load_module("UserConfigs.UserDecorations")
load_module("UserConfigs.UserAnimations")

-- 2. Input, Keyboard Layouts & User Settings
load_module("UserConfigs.UserSettings")

-- 3. Core Keybindings & Controls
load_module("UserConfigs.UserKeybinds")

-- 4. Startup Daemons (SwayNC, Waybar, etc.)
load_module("configs.Startup_Apps")

-- 5. Dynamic Monitor & Workspace Layout (from nwg-displays)
load_module("monitors")
load_module("workspaces")

-- 6. Notebook power overrides. Desktop hostname "frank" does not load this.
local function machine_hostname()
    local f = io.open("/etc/hostname", "r")
    if not f then
        return ""
    end
    local name = f:read("*l") or ""
    f:close()
    return (name:gsub("%s+$", ""))
end

if machine_hostname() == "frank-notebook" then
    local power = hypr_dir .. "/hosts/frank-notebook-power.lua"
    local ok, err = pcall(dofile, power)
    if not ok then
        print(string.format("[Hyprland.lua] Error loading %s: %s", power, tostring(err)))
    end
end
