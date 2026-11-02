-- Hyprland Master Lua Configuration
---@module 'hl'



local hypr_dir = (os.getenv("XDG_CONFIG_HOME") or ((os.getenv("HOME") or "") .. "/.config")) .. "/hypr"
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
package.loaded["configs.Voluta"] = nil

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

-- 6. Personal Lua hooks live in the private companion, never in the public core.
package.loaded["configs.Voluta"] = nil
local settings_ok, settings = pcall(require, "configs.Voluta")
local function personal_file(path)
    local f = io.open(path, "r")
    if not f then return end
    f:close()
    local ok, err = pcall(dofile, path)
    if not ok then print("[Voluta] Personal hook failed: " .. tostring(err)) end
end
if settings_ok and settings.initialized then
    personal_file(settings.personal_dir .. "/shared.lua")
    personal_file(settings.personal_dir .. "/hosts/" .. settings.host .. ".lua")
    personal_file(settings.personal_dir .. "/hosts/" .. settings.host .. "-power.lua")
    local applied, err = pcall(hl.config, settings.hyprland)
    if not applied then print("[Voluta] Invalid Hyprland override: " .. tostring(err)) end
    for _, monitor in ipairs(settings.monitors or {}) do hl.monitor(monitor) end
    for _, workspace in ipairs(settings.workspaces or {}) do hl.workspace_rule(workspace) end
end
