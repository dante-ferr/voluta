-- wallust.lua - Shared access to the palette wallust generates for Hyprland.
--
-- Parses the same $color variables Hyprland itself sources, so Lua-side rules
-- and decorations restyle themselves on every wallpaper change.
---@module 'hl'

local home = os.getenv("HOME") or "/home/dante"
local colors_path = home .. "/.config/hypr/wallust/wallust-hyprland.conf"

-- Imperial gold on obsidian, used until wallust has written a palette.
local palette = {
    background = "rgb(0A0A0E)",
    foreground = "rgb(E6E6F0)",
    color0 = "rgb(16161D)",
    color1 = "rgb(D4AF37)",
}

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

--- Returns the wallust color named `key`, falling back when it is absent.
---@param key string
---@param fallback string
---@return string
function palette.get(key, fallback)
    return palette[key] or fallback
end

return palette
