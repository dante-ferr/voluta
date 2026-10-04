-- Power profile for frank-notebook. Loaded only when /etc/hostname matches.
-- Hyprland and the apps it launches stay on the Intel iGPU: Mesa GLX and
-- the iHD VA-API driver. hosts/frank.lua (NVIDIA GLX) is not loaded here.
-- CUDA is not masked, so an ML job can still open the
-- dGPU without the compositor holding it awake.
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
