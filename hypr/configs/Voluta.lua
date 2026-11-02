-- Resolve JSON once per reload, with a last-known-good fallback on read errors.
local M = package.loaded["voluta.last-good"] or {
    initialized = false, features = {}, hyprland = {}, apps = {}, keybindings = {}
}
local function quote(value)
    return "'" .. value:gsub("'", "'\\''") .. "'"
end
local config = os.getenv("XDG_CONFIG_HOME") or ((os.getenv("HOME") or "") .. "/.config")
local helper = config .. "/hypr/../voluta/cli.py"
local pipe = io.popen("python3 " .. quote(helper) .. " render-lua")
local valid = false
if pipe then
    local source = pipe:read("*a")
    -- Hyprland can reap subprocesses before Lua pclose(), returning ECHILD even
    -- when stdout is complete. Validate the result instead of trusting pclose.
    pcall(function() pipe:close() end)
    local chunk = load(source, "Voluta settings", "t", {})
    if chunk then
        local ok, result = pcall(chunk)
        if ok and type(result) == "table" and result.version == 1
            and type(result.hyprland) == "table" and type(result.features) == "table" then
            M = result
            package.loaded["voluta.last-good"] = M
            valid = true
        end
    end
end
if not valid then
    print("[Voluta] Could not resolve preferences; retaining last known settings")
end
function M.enabled(name)
    if not M.initialized then return true end
    return M.features[name] == true
end
return M
