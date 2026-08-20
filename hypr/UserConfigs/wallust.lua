-- wallust.lua - Shared access to the palette wallust generates for Hyprland.
--
-- Parses the same $color variables Hyprland itself sources, so Lua-side rules
-- and decorations restyle themselves on every wallpaper change.
-- hyprland.lua nils package.loaded for this module on reload; get() also
-- re-reads the file so a stale cached table cannot pin the old palette.
---@module 'hl'

local home = os.getenv("HOME") or "/home/dante"
local colors_path = home .. "/.config/hypr/wallust/wallust-hyprland.conf"

-- Imperial gold on obsidian, used until wallust has written a palette.
local defaults = {
    background = "rgb(0A0A0E)",
    foreground = "rgb(E6E6F0)",
    color0 = "rgb(16161D)",
    color1 = "rgb(D4AF37)",
}

local function read_palette()
    local palette = {}
    for key, value in pairs(defaults) do
        palette[key] = value
    end
    local f = io.open(colors_path, "r")
    if f then
        for line in f:lines() do
            local key, value = line:match("^%$(%w+)%s*=%s*(.-)%s*$")
            if key and value ~= "" then
                palette[key] = value
            end
        end
        f:close()
    end
    return palette
end

local M = {}

--- Returns the wallust color named `key`, falling back when it is absent.
---@param key string
---@param fallback string
---@return string
function M.get(key, fallback)
    local palette = read_palette()
    return palette[key] or fallback
end

return setmetatable(M, {
    __index = function(_, key)
        return read_palette()[key]
    end,
})
