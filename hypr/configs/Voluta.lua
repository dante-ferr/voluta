-- JSON preferences are resolved by the same code used by bin/voluta.
local M = { initialized = false, features = {}, hyprland = {} }
local function quote(value)
    return "'" .. value:gsub("'", "'\\''") .. "'"
end
local config = os.getenv("XDG_CONFIG_HOME") or ((os.getenv("HOME") or "") .. "/.config")
local helper = config .. "/hypr/../voluta/cli.py"
local pipe = io.popen("python3 " .. quote(helper) .. " render-lua")
if pipe then
    local source = pipe:read("*a")
    local ok = pipe:close()
    if ok then
        local chunk = load(source, "Voluta settings", "t", {})
        if chunk then
            local valid, result = pcall(chunk)
            if valid and type(result) == "table" then M = result end
        end
    else
        print("[Voluta] Settings unavailable; retaining legacy defaults")
    end
end
function M.enabled(name)
    if not M.initialized then return true end
    return M.features[name] == true
end
return M
