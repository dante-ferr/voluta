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

-- 6. Host overrides. hosts/<hostname>.lua, then hosts/<hostname>-power.lua.
local function machine_hostname()
    local f = io.open("/etc/hostname", "r")
    if not f then
        return ""
    end
    local name = f:read("*l") or ""
    f:close()
    return (name:gsub("%s+$", ""))
end

local hostname = machine_hostname()

local function load_host_file(path)
    local f = io.open(path, "r")
    if not f then
        return
    end
    f:close()
    local ok, err = pcall(dofile, path)
    if not ok then
        print(string.format("[Hyprland.lua] Error loading %s: %s", path, tostring(err)))
    end
end

if hostname ~= "" then
    -- hosts/frank-notebook.lua turns shadows off. It was never sourced, so
    -- the notebook kept the desktop shadow path.
    load_host_file(hypr_dir .. "/hosts/" .. hostname .. ".lua")
    load_host_file(hypr_dir .. "/hosts/" .. hostname .. "-power.lua")
end
