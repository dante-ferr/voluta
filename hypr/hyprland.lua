-- Hyprland Master Lua Configuration
---@module 'hl'



local function load_module(mod_name)
    package.loaded[mod_name] = nil
    local ok, err = pcall(require, mod_name)
    if not ok then
        print(string.format("[Hyprland.lua] Note on loading %s: %s", mod_name, tostring(err)))
    end
end

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
