-- Power profile for frank-notebook. Loaded only when /etc/hostname matches.
-- The shared UserSettings keep the desktop on the NVIDIA GL and VA-API path.
---@module 'hl'

hl.env("LIBVA_DRIVER_NAME", "iHD")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "mesa")
hl.env("NVD_BACKEND", "")

hl.config({
    cursor = {
        no_hardware_cursors = false,
    },
    misc = {
        vrr = 0,
    },
})

hl.monitor({
    output = "eDP-1",
    mode = "1920x1080@120",
    position = "0x0",
    scale = 1,
})
